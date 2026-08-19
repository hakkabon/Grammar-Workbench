#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import GrammarWorkbench
import GrammarWorkbenchSDK

@main
struct GrammarWorkbenchCLI {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            print(help)
            return
        }
        switch command {
        case "--help", "-h", "help":
            print(help)
        case "--version", "-v", "version":
            print("grammar-workbench \(GrammarWorkbenchRelease.version)")
        case "platform-info":
            guard arguments.count <= 2 else {
                throw CLIError.usage("platform-info accepts at most one output path")
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(GrammarRuntimePlatformReport.current)
            if let output = arguments.dropFirst().first {
                try data.write(to: URL(fileURLWithPath: output), options: .atomic)
                print("Wrote \(output)")
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
        case "tooling-request":
            guard arguments.count == 2 || arguments.count == 3 else {
                throw CLIError.usage("tooling-request requires REQUEST_JSON [RESPONSE_JSON]")
            }
            let request = try GrammarToolingCodec.decodeRequest(
                Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            )
            let response = await GrammarLanguageToolingService().handle(request)
            let data = try GrammarToolingCodec.encode(response)
            if arguments.count == 3 {
                try data.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
                print("Wrote \(arguments[2]): \(response.status.rawValue)")
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
            if response.status == .failure {
                throw CLIError.toolingRequestFailed(response.error?.message ?? "unknown SDK error")
            }
        case "validate":
            guard arguments.count == 2 else { throw CLIError.usage("validate requires a grammar file") }
            let source = try read(arguments[1])
            let compilation = GrammarWorkbenchAPI.compile(.init(
                source: source, notation: notation(for: arguments[1])
            ))
            for diagnostic in compilation.diagnostics {
                print("\(diagnostic.severity.rawValue):\(diagnostic.range.start.line):\(diagnostic.range.start.column): \(diagnostic.message)")
            }
            guard compilation.succeeded, let grammar = compilation.grammar else { throw CLIError.validationFailed }
            print("Valid grammar: \(grammar.productions.count) productions, \(grammar.terminals.count) terminals")
        case "test":
            guard arguments.count == 2 else { throw CLIError.usage("test requires a project interchange or .grammarworkbench file") }
            let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            let document: GrammarWorkbenchDocument
            if let interchange = try? GrammarInterchangeCodec.decode(data) {
                document = interchange
            } else {
                document = try JSONDecoder().decode(GrammarWorkbenchDocument.self, from: data)
            }
            guard let algorithm = GrammarAlgorithm(rawValue: document.algorithm) else {
                throw CLIError.usage("unknown LR algorithm ‘\(document.algorithm)’")
            }
            let compilation = GrammarWorkbenchAPI.compile(.init(
                source: document.source, algorithm: algorithm, notation: document.notation
            ))
            let report = compilation.runTests(document.tests)
            for result in report.results {
                print("\(result.status.rawValue.uppercased()) \(result.name): \(result.message)")
            }
            print("\(report.passed) passed, \(report.failed) failed")
            if !report.allPassed { throw CLIError.testsFailed }
        case "project-check":
            guard arguments.count == 2 else {
                throw CLIError.usage("project-check requires a project manifest")
            }
            let manifest = try GrammarProjectCodec.decode(
                Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            )
            let workspace = try GrammarProjectWorkspace(manifest: manifest)
            let analysis = try await workspace.analyze()
            for document in analysis.documents {
                let source = manifest.sources.first { $0.id == document.documentID }
                let status = document.lexing.diagnostics.isEmpty
                    ? document.parse.status.rawValue : "lexical-error"
                print("\(status.uppercased()) \(source?.path ?? document.documentID)")
            }
            for result in analysis.tests.results {
                print("\(result.status.rawValue.uppercased()) \(result.name): \(result.message)")
            }
            let generated = try await workspace.generate()
            print("Project \(manifest.name): \(analysis.documents.count) sources, \(analysis.index.entries.count) index entries, \(analysis.tests.passed) tests passed, \(generated.count) generator targets valid")
            if !analysis.isSuccessful { throw CLIError.projectFailed }
        case "source-project-check":
            guard arguments.count == 2 else {
                throw CLIError.usage("source-project-check requires a source-project descriptor")
            }
            let loaded = try GrammarSourceProjectLoader.load(
                at: URL(fileURLWithPath: arguments[1])
            )
            let analysis = try await GrammarProjectWorkspace(manifest: loaded.manifest).analyze()
            for document in analysis.documents {
                let source = loaded.manifest.sources.first { $0.id == document.documentID }
                let status = document.lexing.diagnostics.isEmpty
                    ? document.parse.status.rawValue : "lexical-error"
                print("\(status.uppercased()) \(source?.path ?? document.documentID)")
            }
            let semantics = loaded.semanticSchema.map { analysis.semanticWorkspace(schema: $0) }
            print("Source project \(loaded.descriptor.name): \(analysis.documents.count) files, \(analysis.index.entries.count) index entries, \(semantics?.workspaceSymbols().count ?? 0) workspace symbols")
            if !analysis.isSuccessful || semantics?.diagnostics.isEmpty == false {
                throw CLIError.projectFailed
            }
        case "source-project-export":
            guard arguments.count == 3 else {
                throw CLIError.usage("source-project-export requires DESCRIPTOR OUTPUT_PROJECT")
            }
            let loaded = try GrammarSourceProjectLoader.load(
                at: URL(fileURLWithPath: arguments[1])
            )
            try GrammarProjectCodec.encode(loaded.manifest).write(
                to: URL(fileURLWithPath: arguments[2]), options: .atomic
            )
            print("Wrote \(arguments[2]): \(loaded.manifest.sources.count) embedded source files")
        case "project-generate":
            guard arguments.count == 3 else {
                throw CLIError.usage("project-generate requires PROJECT OUTPUT_ROOT")
            }
            let manifest = try GrammarProjectCodec.decode(
                Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            )
            let workspace = try GrammarProjectWorkspace(manifest: manifest)
            let analysis = try await workspace.analyze()
            guard analysis.isSuccessful else { throw CLIError.projectFailed }
            let generated = try await workspace.generate()
            let root = URL(fileURLWithPath: arguments[2], isDirectory: true)
            for generation in generated {
                let directory = root.appendingPathComponent(
                    generation.target.outputDirectory, isDirectory: true
                )
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true
                )
                for file in generation.result.files {
                    let destination = directory.appendingPathComponent(file.suggestedFilename)
                    try file.contents.write(to: destination, options: .atomic)
                    print("Wrote \(destination.path)")
                }
            }
        case "project-semantic":
            guard arguments.count == 3 || arguments.count == 4 else {
                throw CLIError.usage("project-semantic requires PROJECT SCHEMA [OUTPUT]")
            }
            let manifest = try GrammarProjectCodec.decode(
                Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            )
            let schema = try JSONDecoder().decode(
                GrammarSemanticWorkspaceSchema.self,
                from: Data(contentsOf: URL(fileURLWithPath: arguments[2]))
            )
            let services = try await GrammarProjectWorkspace(manifest: manifest)
                .semanticWorkspace(schema: schema)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(services)
            if arguments.count == 4 {
                try data.write(to: URL(fileURLWithPath: arguments[3]), options: .atomic)
                print("Wrote \(arguments[3]): \(services.workspaceSymbols().count) symbols, \(services.diagnostics.count) diagnostics")
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
        case "project-rename":
            guard arguments.count == 7, let offset = Int(arguments[4]), offset >= 0 else {
                throw CLIError.usage("project-rename requires PROJECT SCHEMA DOCUMENT UTF16_OFFSET NEW_NAME OUTPUT_PROJECT")
            }
            let manifest = try GrammarProjectCodec.decode(
                Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            )
            let schema = try JSONDecoder().decode(
                GrammarSemanticWorkspaceSchema.self,
                from: Data(contentsOf: URL(fileURLWithPath: arguments[2]))
            )
            let workspace = try GrammarProjectWorkspace(manifest: manifest)
            let services = try await workspace.semanticWorkspace(schema: schema)
            let plan = try services.renamePlan(
                documentID: arguments[3], atUTF16Offset: offset, replacement: arguments[5]
            )
            let changed = try await workspace.applySemanticRename(plan)
            try GrammarProjectCodec.encode(changed.manifest).write(
                to: URL(fileURLWithPath: arguments[6]), options: .atomic
            )
            print("Wrote \(arguments[6]): renamed \(plan.affectedOccurrences) occurrence(s) in \(plan.documents.count) document(s)")
        case "kit-validate":
            guard arguments.count == 2 else {
                throw CLIError.usage("kit-validate requires KIT")
            }
            let kit = try GrammarSemanticLanguageKitCodec.decode(
                Data(contentsOf: URL(fileURLWithPath: arguments[1])),
                requirePassingTests: true
            )
            print("Valid semantic language kit \(kit.manifest.identifier)@\(kit.manifest.version): \(kit.semanticModel.productions.count) productions, \(kit.manifest.semantics.rules.count) semantic rules, \(kit.conformance.passed) tests passed")
        case "kit-project":
            guard arguments.count == 3 else {
                throw CLIError.usage("kit-project requires KIT OUTPUT_PROJECT")
            }
            let kit = try GrammarSemanticLanguageKitCodec.decode(
                Data(contentsOf: URL(fileURLWithPath: arguments[1])),
                requirePassingTests: true
            )
            try GrammarProjectCodec.encode(kit.project()).write(
                to: URL(fileURLWithPath: arguments[2]), options: .atomic
            )
            print("Wrote \(arguments[2]) from \(kit.manifest.identifier)@\(kit.manifest.version)")
        case "graph-layout":
            guard arguments.count == 3 || arguments.count == 4 else {
                throw CLIError.usage("graph-layout requires GRAPH OUTPUT [OPTIONS]")
            }
            let graph = try JSONDecoder().decode(
                GrammarGraph.self,
                from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            )
            let options = arguments.count == 4
                ? try JSONDecoder().decode(
                    GrammarGraphLayoutOptions.self,
                    from: Data(contentsOf: URL(fileURLWithPath: arguments[3]))
                )
                : GrammarGraphLayoutOptions()
            let layout = try GrammarGraphLayoutEngine.layout(graph, options: options)
            let output = URL(fileURLWithPath: arguments[2])
            if output.pathExtension.lowercased() == "svg" {
                try Data(GrammarGraphSVGRenderer.render(layout).utf8).write(to: output, options: .atomic)
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(layout).write(to: output, options: .atomic)
            }
            print("Wrote \(arguments[2]): \(layout.nodes.count) nodes, \(layout.routes.count) routes via \(layout.metrics.engine)")
        case "graph-validate", "graph-measure", "graph-dot":
            guard arguments.count == 2 || arguments.count == 3 else {
                throw CLIError.usage("\(arguments[0]) requires GRAPH [OUTPUT]")
            }
            let graph = try JSONDecoder().decode(
                GrammarGraph.self,
                from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            )
            let data: Data
            let summary: String
            if arguments[0] == "graph-dot" {
                data = Data(GrammarGraphDOTRenderer.render(graph).utf8)
                summary = "Graphviz DOT for \(graph.nodes.count) nodes and \(graph.edges.count) edges"
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                if arguments[0] == "graph-measure" {
                    let measured = try GrammarGraphMeasurementRunner.layout(graph)
                    data = try encoder.encode(measured)
                    summary = "\(measured.correctness.errorCount) errors, \(measured.correctness.warningCount) warnings; \(measured.measurement.totalNanoseconds) ns total"
                } else {
                    let structural = GrammarGraphValidator.validate(graph)
                    let report = structural.isValid
                        ? GrammarGraphValidator.validate(try GrammarGraphLayoutEngine.layout(graph), against: graph)
                        : structural
                    data = try encoder.encode(report)
                    summary = "\(report.errorCount) errors, \(report.warningCount) warnings"
                }
            }
            if arguments.count == 3 {
                try data.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
                print("Wrote \(arguments[2]): \(summary)")
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
        case "graph-geometry":
            guard arguments.count == 4 else {
                throw CLIError.usage("graph-geometry requires GRAPH SPECIFICATION OUTPUT")
            }
            let decoder = JSONDecoder()
            let graph = try decoder.decode(
                GrammarGraph.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            )
            let specification = try decoder.decode(
                GrammarGraphGeometrySpecification.self,
                from: Data(contentsOf: URL(fileURLWithPath: arguments[2]))
            )
            let output = URL(fileURLWithPath: arguments[3])
            if output.pathExtension.lowercased() == "dot" {
                let dot = GrammarGraphAdvancedDOTRenderer.render(graph, specification: specification)
                try Data(dot.utf8).write(to: output, options: .atomic)
            } else {
                let layout = try GrammarGraphGeometryEngine.layout(graph, specification: specification)
                if output.pathExtension.lowercased() == "svg" {
                    try Data(GrammarGraphAdvancedSVGRenderer.render(layout).utf8)
                        .write(to: output, options: .atomic)
                } else {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    try encoder.encode(layout).write(to: output, options: .atomic)
                }
            }
            print("Wrote \(arguments[3]): advanced geometry for \(graph.nodes.count) nodes and \(graph.edges.count) edges")
        case "portable-import":
            guard arguments.count >= 3 else {
                throw CLIError.usage("portable-import requires GRAMMAR OUTPUT [--notation=bnfProfile|workbench|ebnf] [--start=SYMBOL]")
            }
            let flags = arguments.dropFirst(3)
            let inferred: GrammarPortableNotation = switch URL(fileURLWithPath: arguments[1]).pathExtension.lowercased() {
            case "bnf": .bnfProfile
            case "ebnf": .ebnf
            default: .workbench
            }
            var selectedNotation = inferred
            var start: String?
            for flag in flags {
                if let value = stringOption(flag, name: "notation"),
                   let notation = GrammarPortableNotation(rawValue: value) {
                    selectedNotation = notation
                } else if let value = stringOption(flag, name: "start"), !value.isEmpty {
                    start = value
                } else {
                    throw CLIError.usage("unknown portable-import option ‘\(flag)’")
                }
            }
            let interchange = try GrammarPortableInterchangeCodec.importGrammar(
                try read(arguments[1]), notation: selectedNotation, startSymbol: start
            )
            try GrammarPortableInterchangeCodec.encode(interchange).write(
                to: URL(fileURLWithPath: arguments[2]), options: .atomic
            )
            print("Wrote \(arguments[2]): \(interchange.specification.productions.count) productions, fingerprint \(interchange.fingerprint)")
        case "portable-render":
            guard arguments.count >= 3 else {
                throw CLIError.usage("portable-render requires INTERCHANGE OUTPUT [--format=bnfProfile|workbench] [--verify]")
            }
            var format: GrammarPortableRenderFormat = .bnfProfile
            var verify = false
            for flag in arguments.dropFirst(3) {
                if flag == "--verify" {
                    verify = true
                } else if let value = stringOption(flag, name: "format"),
                          let selected = GrammarPortableRenderFormat(rawValue: value) {
                    format = selected
                } else {
                    throw CLIError.usage("unknown portable-render option ‘\(flag)’")
                }
            }
            let interchange = try GrammarPortableInterchangeCodec.decode(
                Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            )
            let rendered = try GrammarPortableInterchangeCodec.render(interchange, as: format)
            if verify {
                let report = try GrammarPortableInterchangeCodec.verifyRoundTrip(interchange, through: format)
                guard report.matches else {
                    throw CLIError.transformationFailed("portable \(format.rawValue) round trip changed the canonical grammar")
                }
            }
            try Data(rendered.utf8).write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
            print("Wrote \(arguments[2]) as \(format.rawValue)\(verify ? " (round trip verified)" : "")")
        case "export-artifact":
            guard arguments.count == 3 || arguments.count == 4 else {
                throw CLIError.usage("export-artifact requires GRAMMAR OUTPUT [ALGORITHM]")
            }
            let source = try read(arguments[1])
            let algorithm = arguments.count == 4 ? arguments[3] : "LALR(1)"
            let data = try GrammarInterchangeCodec.encodeArtifact(
                source: source, algorithm: algorithm, notation: notation(for: arguments[1])
            )
            try data.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
            print("Wrote \(arguments[2])")
        case "generate-swift":
            guard (3...5).contains(arguments.count) else {
                throw CLIError.usage("generate-swift requires GRAMMAR OUTPUT [ALGORITHM] [TYPE]")
            }
            let source = try read(arguments[1])
            let algorithmName = arguments.count >= 4 ? arguments[3] : GrammarAlgorithm.lalr.rawValue
            guard let algorithm = GrammarAlgorithm(rawValue: algorithmName) else {
                throw CLIError.usage("unknown LR algorithm ‘\(algorithmName)’")
            }
            let typeName = arguments.count == 5 ? arguments[4] : "GeneratedParser"
            let compilation = GrammarWorkbenchAPI.compile(.init(
                source: source, algorithm: algorithm, notation: notation(for: arguments[1])
            ))
            let generated = try compilation.generateSwiftParser(options: .init(typeName: typeName))
            try Data(generated.utf8).write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
            print("Wrote \(arguments[2])")
        case "list-generators":
            guard arguments.count == 1 else { throw CLIError.usage("list-generators takes no arguments") }
            let registry = GrammarGeneratorRegistry()
            for generator in await registry.availableGenerators() {
                print("\(generator.id)\t\(generator.displayName)\t.\(generator.defaultFileExtension)")
                for option in generator.options {
                    let fallback = option.defaultValue.map { " (default: \($0))" } ?? ""
                    print("  \(option.name)=VALUE\t\(option.summary)\(fallback)")
                }
            }
        case "generate":
            guard arguments.count >= 4 else {
                throw CLIError.usage("generate requires GENERATOR GRAMMAR OUTPUT [ALGORITHM] [KEY=VALUE ...]")
            }
            let source = try read(arguments[2])
            var optionIndex = 4
            var algorithm = GrammarAlgorithm.lalr
            if arguments.indices.contains(4), !arguments[4].contains("=") {
                guard let parsed = GrammarAlgorithm(rawValue: arguments[4]) else {
                    throw CLIError.usage("unknown LR algorithm ‘\(arguments[4])’")
                }
                algorithm = parsed
                optionIndex = 5
            }
            var values: [String: String] = [:]
            for option in arguments.dropFirst(optionIndex) {
                let parts = option.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2, !parts[0].isEmpty else {
                    throw CLIError.usage("generator option ‘\(option)’ must use KEY=VALUE")
                }
                values[parts[0]] = parts[1]
            }
            let compilation = GrammarWorkbenchAPI.compile(.init(
                source: source, algorithm: algorithm, notation: notation(for: arguments[2])
            ))
            let registry = GrammarGeneratorRegistry()
            let result = try await registry.generate(
                identifier: arguments[1], from: compilation, options: .init(values)
            )
            try write(result.files, to: arguments[3])
            for diagnostic in result.diagnostics { FileHandle.standardError.write(Data("note: \(diagnostic)\n".utf8)) }
        case "compare":
            guard arguments.count == 2 || arguments.count == 3 else {
                throw CLIError.usage("compare requires GRAMMAR [OUTPUT]")
            }
            let source = try read(arguments[1])
            let comparison = try GrammarWorkbenchAPI.compile(.init(
                source: source, notation: notation(for: arguments[1])
            )).compareAlgorithms()
            if arguments.count == 3 {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(comparison).write(
                    to: URL(fileURLWithPath: arguments[2]), options: .atomic
                )
                print("Wrote \(arguments[2])")
            } else {
                for metric in comparison.algorithmMetrics {
                    print("\(metric.algorithm.rawValue): \(metric.states) states, \(metric.tableEntries) entries, \(metric.unresolvedConflicts) unresolved conflicts")
                }
                print("Recommended: \(comparison.recommendedAlgorithm.rawValue) — \(comparison.recommendation)")
            }
        case "lower-ebnf":
            guard arguments.count == 3 else {
                throw CLIError.usage("lower-ebnf requires EBNF OUTPUT")
            }
            let lowering = try GrammarWorkbenchAPI.lowerEBNF(try read(arguments[1]))
            try Data(lowering.loweredSource.utf8).write(
                to: URL(fileURLWithPath: arguments[2]), options: .atomic
            )
            print("Wrote \(arguments[2]) (\(lowering.syntheticNonterminals.count) synthetic nonterminals)")
        case "diff":
            guard arguments.count == 3 || arguments.count == 4 else {
                throw CLIError.usage("diff requires OLD NEW [OUTPUT]")
            }
            let old = GrammarWorkbenchAPI.compile(.init(
                source: try read(arguments[1]), notation: notation(for: arguments[1])
            ))
            let new = GrammarWorkbenchAPI.compile(.init(
                source: try read(arguments[2]), notation: notation(for: arguments[2])
            ))
            let difference = try new.diff(from: old)
            if arguments.count == 4 {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(difference).write(
                    to: URL(fileURLWithPath: arguments[3]), options: .atomic
                )
                print("Wrote \(arguments[3])")
            } else {
                print("States \(signed(difference.stateDelta)), transitions \(signed(difference.transitionDelta)), table entries \(signed(difference.tableEntryDelta)), decisions \(signed(difference.decisionDelta))")
                for production in difference.addedProductions { print("+ \(production)") }
                for production in difference.removedProductions { print("- \(production)") }
            }
        case "parse":
            guard arguments.count == 3 || arguments.count == 4 else {
                throw CLIError.usage("parse requires GRAMMAR INPUT [OUTPUT]")
            }
            let compilation = GrammarWorkbenchAPI.compile(.init(
                source: try read(arguments[1]), notation: notation(for: arguments[1])
            ))
            let result = compilation.parse(arguments[2])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(result)
            if arguments.count == 4 {
                try data.write(to: URL(fileURLWithPath: arguments[3]), options: .atomic)
                print("Wrote \(arguments[3])")
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
            guard result.status == .accepted || result.status == .acceptedWithRecovery else {
                throw CLIError.parseFailed(result.status.rawValue)
            }
        case "parser-visualize":
            guard arguments.count == 4 else {
                throw CLIError.usage("parser-visualize requires GRAMMAR INPUT OUTPUT")
            }
            let compilation = GrammarWorkbenchAPI.compile(.init(
                source: try read(arguments[1]), notation: notation(for: arguments[1])
            ))
            guard let artifact = compilation.artifact else {
                throw CLIError.parseFailed("invalidGrammar")
            }
            let parsed = compilation.parse(arguments[2])
            let timeline = try GrammarParserVisualizationBuilder.make(
                artifact: artifact, parse: parsed
            )
            let output = URL(fileURLWithPath: arguments[3])
            if output.pathExtension.lowercased() == "html" {
                try Data(GrammarParserVisualizationHTMLRenderer.render(timeline).utf8)
                    .write(to: output, options: .atomic)
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(timeline).write(to: output, options: .atomic)
            }
            print("Wrote \(arguments[3]): \(timeline.frames.count) parser visualization frames")
        case "platform-parse":
            guard arguments.count >= 3 else {
                throw CLIError.usage("platform-parse requires GRAMMAR INPUT [OUTPUT] [OPTIONS]")
            }
            let trailing = Array(arguments.dropFirst(3))
            let outputs = trailing.filter { !$0.hasPrefix("--") }
            guard outputs.count <= 1 else {
                throw CLIError.usage("platform-parse accepts at most one output path")
            }
            var options = GrammarPlatformParseOptions()
            for flag in trailing where flag.hasPrefix("--") {
                if flag == "--strict" {
                    options.deterministic.enablesRecovery = false
                } else if flag == "--include-resolved" {
                    options.generalized.exploresResolvedConflicts = true
                } else if flag == "--breadth-first" {
                    options.generalized.searchStrategy = .breadthFirst
                } else if let value = stringOption(flag, name: "mode"),
                          let mode = GrammarParsingMode(rawValue: value) {
                    options.mode = mode
                } else if let value = stringOption(flag, name: "ambiguity"),
                          let selection = GrammarAmbiguitySelection(rawValue: value) {
                    options.ambiguitySelection = selection
                } else if let value = positiveOption(flag, name: "maximum-configurations") {
                    options.generalized.maximumConfigurations = value
                } else if let value = positiveOption(flag, name: "maximum-steps") {
                    options.generalized.maximumSteps = value
                } else if let value = positiveOption(flag, name: "maximum-trees") {
                    options.generalized.maximumTrees = value
                } else if let value = positiveOption(flag, name: "maximum-forest-nodes") {
                    options.generalized.maximumForestNodes = value
                } else if let value = positiveOption(flag, name: "maximum-packed-families") {
                    options.generalized.maximumPackedFamilies = value
                } else {
                    throw CLIError.usage("unknown platform parse option ‘\(flag)’")
                }
            }
            let compilation = GrammarWorkbenchAPI.compile(.init(
                source: try read(arguments[1]), notation: notation(for: arguments[1])
            ))
            let result = try GrammarParsingPlatform(compilation: compilation).parse(.init(
                input: arguments[2], options: options
            ))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(result)
            if let output = outputs.first {
                try data.write(to: URL(fileURLWithPath: output), options: .atomic)
                print("Wrote \(output): \(result.status.rawValue) via \(result.engine.rawValue)")
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
            guard result.isAccepted else { throw CLIError.platformParseFailed(result.status.rawValue) }
        case "grammar-analyze":
            guard arguments.count == 2 || arguments.count == 3 else {
                throw CLIError.usage("grammar-analyze requires GRAMMAR [OUTPUT]")
            }
            let compilation = GrammarWorkbenchAPI.compile(.init(
                source: try read(arguments[1]), notation: notation(for: arguments[1])
            ))
            let analysis = try GrammarEngineering.analyze(compilation)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(analysis)
            if arguments.count == 3 {
                try data.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
                print("Wrote \(arguments[2]): \(analysis.statistics.productions) productions, \(analysis.statistics.dependencyEdges) dependencies")
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
        case "grammar-transform":
            guard arguments.count == 4 else {
                throw CLIError.usage("grammar-transform requires duplicate|unreachable|unproductive GRAMMAR OUTPUT")
            }
            let kind: GrammarTransformationKind = switch arguments[1].lowercased() {
            case "duplicate", "duplicates": .removeDuplicateProductions
            case "unreachable": .removeUnreachableProductions
            case "unproductive": .removeUnproductiveProductions
            default: throw CLIError.usage("unknown grammar transformation ‘\(arguments[1])’")
            }
            let request = GrammarCompilationRequest(
                source: try read(arguments[2]), notation: notation(for: arguments[2])
            )
            let compilation = GrammarWorkbenchAPI.compile(request)
            let plan = try GrammarEngineering.plan(kind, for: compilation)
            guard plan.hasChanges else { throw CLIError.transformationFailed("no applicable declarations were found") }
            let result = try GrammarEngineering.execute(plan, request: request)
            guard result.isSafeToApply else {
                throw CLIError.transformationFailed(result.behavior.conclusion)
            }
            try result.proposedSource.write(
                to: URL(fileURLWithPath: arguments[3]), atomically: true, encoding: .utf8
            )
            print("Wrote \(arguments[3]): removed \(plan.affectedLines.count) declaration line(s); checked \(result.behavior.cases.count) inputs")
        case "bootstrap":
            let trailing = Array(arguments.dropFirst())
            let outputs = trailing.filter { !$0.hasPrefix("--") }
            guard outputs.count <= 1 else {
                throw CLIError.usage("bootstrap accepts at most one output path")
            }
            var maximumGenerations = 4
            for flag in trailing where flag.hasPrefix("--") {
                if let value = positiveOption(flag, name: "maximum-generations") {
                    maximumGenerations = value
                } else {
                    throw CLIError.usage("unknown bootstrap option ‘\(flag)’")
                }
            }
            let report = try GrammarBootstrapLaboratory.run(
                options: .init(maximumGenerations: maximumGenerations)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(report)
            if let output = outputs.first {
                try data.write(to: URL(fileURLWithPath: output), options: .atomic)
                print("Wrote \(output): fixed point at generation \(report.fixedPointGeneration.map(String.init) ?? "none"), \(report.corpus.filter(\.matches).count)/\(report.corpus.count) differential checks passed")
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
            guard report.succeeded else { throw CLIError.bootstrapFailed }
        case "bootstrap-bundle":
            guard arguments.count == 2 || arguments.count == 3 else {
                throw CLIError.usage("bootstrap-bundle requires OUTPUT [--maximum-generations=N]")
            }
            var maximumGenerations = 4
            if arguments.count == 3 {
                guard let value = positiveOption(arguments[2], name: "maximum-generations") else {
                    throw CLIError.usage("unknown bootstrap-bundle option ‘\(arguments[2])’")
                }
                maximumGenerations = value
            }
            let bundle = try GrammarBootstrapInterchangeCodec.makeBundle(
                options: .init(maximumGenerations: maximumGenerations)
            )
            try GrammarBootstrapInterchangeCodec.encode(bundle).write(
                to: URL(fileURLWithPath: arguments[1]), options: .atomic
            )
            print("Wrote \(arguments[1]): bootstrap fixed point \(bundle.report.fixedPointGeneration.map(String.init) ?? "none"), fingerprint \(bundle.metaGrammar.fingerprint)")
            guard bundle.report.succeeded else { throw CLIError.bootstrapFailed }
        case "research-validate":
            guard arguments.count == 2 || arguments.count == 3 else {
                throw CLIError.usage("research-validate requires PROGRAMME [OUTPUT]")
            }
            let programme = try GrammarResearchProgrammeCodec.decode(
                Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            )
            let report = try GrammarResearchValidator.run(programme)
            let data = try GrammarResearchProgrammeCodec.encode(report)
            if arguments.count == 3 {
                try data.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
                print("Wrote \(arguments[2]): \(report.passedCases)/\(report.cases.count) hypotheses passed, evidence \(report.evidenceFingerprint)")
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
            guard report.passed else { throw CLIError.researchValidationFailed }
        case "research-compare":
            guard arguments.count == 3 || arguments.count == 4 else {
                throw CLIError.usage("research-compare requires BASELINE CANDIDATE [OUTPUT]")
            }
            let baseline = try GrammarResearchProgrammeCodec.decodeReport(
                Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            )
            let candidate = try GrammarResearchProgrammeCodec.decodeReport(
                Data(contentsOf: URL(fileURLWithPath: arguments[2]))
            )
            let comparison = GrammarResearchValidator.compare(baseline: baseline, candidate: candidate)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(comparison)
            if arguments.count == 4 {
                try data.write(to: URL(fileURLWithPath: arguments[3]), options: .atomic)
                print("Wrote \(arguments[3]): \(comparison.regressions.count) regressions, \(comparison.evidenceChanges.count) evidence changes")
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
            guard comparison.compatibleProgramme, comparison.regressions.isEmpty else {
                throw CLIError.researchValidationFailed
            }
        case "research-preview":
            guard arguments.count == 2 || arguments.count == 3 else {
                throw CLIError.usage("research-preview requires list or STUDY [OUTPUT]")
            }
            if arguments[1] == "list" {
                guard arguments.count == 2 else {
                    throw CLIError.usage("research-preview list takes no output path")
                }
                for study in GrammarSelectedResearchCatalog.studies {
                    print("\(study.id)\t\(study.title)")
                }
                return
            }
            guard let study = GrammarSelectedResearchCatalog.study(id: arguments[1]) else {
                throw CLIError.usage("unknown selected research study ‘\(arguments[1])’")
            }
            let preview = try GrammarSelectedResearchPreviewEngine.run(study)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(preview)
            if arguments.count == 3 {
                try data.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
                print("Wrote \(arguments[2]): \(preview.passed ? "supported" : "falsified"), evidence \(preview.report.evidenceFingerprint)")
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
            guard preview.passed else { throw CLIError.researchValidationFailed }
        case "generalized-parse", "research-parse":
            guard arguments.count >= 3 else {
                throw CLIError.usage("\(command) requires GRAMMAR INPUT [OUTPUT] [OPTIONS]")
            }
            let trailing = Array(arguments.dropFirst(3))
            let outputs = trailing.filter { !$0.hasPrefix("--") }
            guard outputs.count <= 1 else {
                throw CLIError.usage("\(command) accepts at most one output path")
            }
            var options = GrammarGeneralizedParseOptions()
            for flag in trailing where flag.hasPrefix("--") {
                switch flag {
                case "--include-resolved": options.exploresResolvedConflicts = true
                case "--breadth-first": options.searchStrategy = .breadthFirst
                default:
                    if let value = positiveOption(flag, name: "maximum-configurations") {
                        options.maximumConfigurations = value
                    } else if let value = positiveOption(flag, name: "maximum-steps") {
                        options.maximumSteps = value
                    } else if let value = positiveOption(flag, name: "maximum-trees") {
                        options.maximumTrees = value
                    } else if let value = positiveOption(flag, name: "maximum-forest-nodes") {
                        options.maximumForestNodes = value
                    } else if let value = positiveOption(flag, name: "maximum-packed-families") {
                        options.maximumPackedFamilies = value
                    } else {
                        throw CLIError.usage("unknown generalized parse option ‘\(flag)’")
                    }
                }
            }
            let compilation = GrammarWorkbenchAPI.compile(.init(
                source: try read(arguments[1]), notation: notation(for: arguments[1])
            ))
            let result = await compilation.parseGeneralizedCancellable(arguments[2], options: options)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(result)
            if let output = outputs.first {
                try data.write(to: URL(fileURLWithPath: output), options: .atomic)
                print("Wrote \(output): \(result.status.rawValue), \(result.alternatives.count) alternative(s)")
            } else {
                print(String(decoding: data, as: UTF8.self))
            }
        default:
            throw CLIError.usage("unknown command ‘\(command)’")
        }
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    private static func notation(for path: String) -> GrammarSourceNotation {
        URL(fileURLWithPath: path).pathExtension.lowercased() == "ebnf" ? .ebnf : .workbench
    }

    private static func positiveOption(_ argument: String, name: String) -> Int? {
        let prefix = "--\(name)="
        guard argument.hasPrefix(prefix),
              let value = Int(argument.dropFirst(prefix.count)), value > 0 else { return nil }
        return value
    }

    private static func stringOption(_ argument: String, name: String) -> String? {
        let prefix = "--\(name)="
        guard argument.hasPrefix(prefix) else { return nil }
        return String(argument.dropFirst(prefix.count))
    }

    private static func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private static func write(_ files: [GrammarGeneratedFile], to path: String) throws {
        let destination = URL(fileURLWithPath: path)
        if files.count == 1 {
            try files[0].contents.write(to: destination, options: .atomic)
            print("Wrote \(path)")
            return
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in files {
            let url = destination.appendingPathComponent(file.suggestedFilename)
            try file.contents.write(to: url, options: .atomic)
            print("Wrote \(url.path)")
        }
    }

    private static let help = """
    Grammar Workbench \(GrammarWorkbenchRelease.version)

    Usage:
      grammar-workbench validate GRAMMAR
      grammar-workbench platform-info [OUTPUT]
      grammar-workbench test PROJECT
      grammar-workbench project-check PROJECT
      grammar-workbench source-project-check DESCRIPTOR
      grammar-workbench source-project-export DESCRIPTOR OUTPUT_PROJECT
      grammar-workbench project-generate PROJECT OUTPUT_ROOT
      grammar-workbench project-semantic PROJECT SCHEMA [OUTPUT]
      grammar-workbench project-rename PROJECT SCHEMA DOCUMENT UTF16_OFFSET NEW_NAME OUTPUT_PROJECT
      grammar-workbench kit-validate KIT
      grammar-workbench kit-project KIT OUTPUT_PROJECT
      grammar-workbench graph-layout GRAPH OUTPUT [OPTIONS]
      grammar-workbench graph-validate GRAPH [OUTPUT]
      grammar-workbench graph-measure GRAPH [OUTPUT]
      grammar-workbench graph-dot GRAPH [OUTPUT]
      grammar-workbench graph-geometry GRAPH SPECIFICATION OUTPUT
      grammar-workbench portable-import GRAMMAR OUTPUT [--notation=bnfProfile|workbench|ebnf] [--start=SYMBOL]
      grammar-workbench portable-render INTERCHANGE OUTPUT [--format=bnfProfile|workbench] [--verify]
      grammar-workbench tooling-request REQUEST_JSON [RESPONSE_JSON]
      grammar-workbench export-artifact GRAMMAR OUTPUT [ALGORITHM]
      grammar-workbench generate-swift GRAMMAR OUTPUT [ALGORITHM] [TYPE]
      grammar-workbench list-generators
      grammar-workbench generate GENERATOR GRAMMAR OUTPUT [ALGORITHM] [KEY=VALUE ...]
      grammar-workbench compare GRAMMAR [OUTPUT]
      grammar-workbench lower-ebnf EBNF OUTPUT
      grammar-workbench diff OLD NEW [OUTPUT]
      grammar-workbench parse GRAMMAR INPUT [OUTPUT]
      grammar-workbench parser-visualize GRAMMAR INPUT OUTPUT
      grammar-workbench platform-parse GRAMMAR INPUT [OUTPUT] [OPTIONS]
      grammar-workbench grammar-analyze GRAMMAR [OUTPUT]
      grammar-workbench grammar-transform duplicate|unreachable|unproductive GRAMMAR OUTPUT
      grammar-workbench bootstrap [OUTPUT] [--maximum-generations=N]
      grammar-workbench bootstrap-bundle OUTPUT [--maximum-generations=N]
      grammar-workbench research-validate PROGRAMME [OUTPUT]
      grammar-workbench research-compare BASELINE CANDIDATE [OUTPUT]
      grammar-workbench research-preview list|STUDY [OUTPUT]
      grammar-workbench generalized-parse GRAMMAR INPUT [OUTPUT] [OPTIONS]
      grammar-workbench research-parse GRAMMAR INPUT [OUTPUT] [OPTIONS]  (compatibility alias)
      grammar-workbench --version

    ALGORITHM is one of SLR(1), LALR(1), or Canonical LR(1).
    Generalized OPTIONS: --include-resolved, --breadth-first,
      --maximum-configurations=N, --maximum-steps=N, --maximum-trees=N,
      --maximum-forest-nodes=N, --maximum-packed-families=N.
    Platform OPTIONS: --mode=adaptive|deterministic|generalized,
      --ambiguity=requireUnique|firstStable|shallowest|deepest, --strict,
      plus all generalized options.
    """
}

private enum CLIError: LocalizedError {
    case usage(String)
    case validationFailed
    case testsFailed
    case parseFailed(String)
    case projectFailed
    case platformParseFailed(String)
    case transformationFailed(String)
    case bootstrapFailed
    case researchValidationFailed
    case toolingRequestFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage(let detail): "\(detail). Run with --help for usage."
        case .validationFailed: "grammar validation failed"
        case .testsFailed: "one or more grammar tests failed"
        case .parseFailed(let status): "input was not accepted (\(status))"
        case .projectFailed: "project validation failed"
        case .platformParseFailed(let status): "platform parse did not select an accepted tree (\(status))"
        case .transformationFailed(let message): "grammar transformation was not applied: \(message)"
        case .bootstrapFailed: "bootstrap laboratory did not reach a validated fixed point"
        case .researchValidationFailed: "research validation programme reported a regression or failed hypothesis"
        case .toolingRequestFailed(let message): "language-tooling request failed: \(message)"
        }
    }
}

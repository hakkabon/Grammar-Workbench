import Darwin
import Foundation
import GrammarWorkbench

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
      grammar-workbench test PROJECT
      grammar-workbench export-artifact GRAMMAR OUTPUT [ALGORITHM]
      grammar-workbench generate-swift GRAMMAR OUTPUT [ALGORITHM] [TYPE]
      grammar-workbench list-generators
      grammar-workbench generate GENERATOR GRAMMAR OUTPUT [ALGORITHM] [KEY=VALUE ...]
      grammar-workbench compare GRAMMAR [OUTPUT]
      grammar-workbench lower-ebnf EBNF OUTPUT
      grammar-workbench diff OLD NEW [OUTPUT]
      grammar-workbench parse GRAMMAR INPUT [OUTPUT]
      grammar-workbench --version

    ALGORITHM is one of SLR(1), LALR(1), or Canonical LR(1).
    """
}

private enum CLIError: LocalizedError {
    case usage(String)
    case validationFailed
    case testsFailed
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage(let detail): "\(detail). Run with --help for usage."
        case .validationFailed: "grammar validation failed"
        case .testsFailed: "one or more grammar tests failed"
        case .parseFailed(let status): "input was not accepted (\(status))"
        }
    }
}

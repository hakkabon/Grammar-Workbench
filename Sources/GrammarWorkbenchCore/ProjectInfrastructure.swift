import Foundation

public struct GrammarProjectGrammar: Hashable, Codable, Sendable {
    public var source: String
    public var notation: GrammarSourceNotation
    public var algorithm: GrammarAlgorithm

    public init(
        source: String,
        notation: GrammarSourceNotation = .workbench,
        algorithm: GrammarAlgorithm = .lalr
    ) {
        self.source = source
        self.notation = notation
        self.algorithm = algorithm
    }
}

public struct GrammarProjectSource: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var path: String
    public var text: String
    public var revision: Int

    public init(id: String, path: String, text: String, revision: Int = 0) {
        self.id = id
        self.path = path
        self.text = text
        self.revision = revision
    }
}

public struct GrammarProjectGeneratorTarget: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var generator: String
    public var outputDirectory: String
    public var options: GrammarGeneratorOptions

    public init(
        id: String? = nil,
        generator: String,
        outputDirectory: String,
        options: GrammarGeneratorOptions = .init()
    ) {
        self.id = id ?? generator
        self.generator = generator
        self.outputDirectory = outputDirectory
        self.options = options
    }
}

/// A portable, tool-neutral project manifest. Source texts are embedded so a
/// manifest is reproducible in CI, build daemons, and editor integrations
/// without imposing a host-specific filesystem abstraction on the library.
public struct GrammarProjectManifest: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-project"

    public let schemaVersion: Int
    public let kind: String
    public let apiVersion: Int
    public var name: String
    public var grammar: GrammarProjectGrammar
    public var sources: [GrammarProjectSource]
    public var tests: [WorkbenchTestCase]
    public var generators: [GrammarProjectGeneratorTarget]

    public init(
        name: String,
        grammar: GrammarProjectGrammar,
        sources: [GrammarProjectSource] = [],
        tests: [WorkbenchTestCase] = [],
        generators: [GrammarProjectGeneratorTarget] = []
    ) {
        schemaVersion = Self.currentSchemaVersion
        kind = Self.kindIdentifier
        apiVersion = GrammarWorkbenchAPI.version
        self.name = name
        self.grammar = grammar
        self.sources = sources
        self.tests = tests
        self.generators = generators
    }
}

public enum GrammarProjectError: Error, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case unsupportedAPIVersion(Int)
    case invalidKind(String)
    case emptyName
    case duplicateSourceID(String)
    case duplicateSourcePath(String)
    case invalidRelativePath(String)
    case duplicateGenerator(String)
    case unknownSource(String)
    case grammarFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let value): "Unsupported project schema version \(value)."
        case .unsupportedAPIVersion(let value): "Unsupported project API version \(value)."
        case .invalidKind(let value): "Unexpected project kind ‘\(value)’."
        case .emptyName: "A project name must not be empty."
        case .duplicateSourceID(let value): "Project source ID ‘\(value)’ is duplicated."
        case .duplicateSourcePath(let value): "Project source path ‘\(value)’ is duplicated."
        case .invalidRelativePath(let value): "Project path ‘\(value)’ is not a safe relative path."
        case .duplicateGenerator(let value): "Generator target ‘\(value)’ is declared more than once."
        case .unknownSource(let value): "No project source named ‘\(value)’ exists."
        case .grammarFailed(let value): "The project grammar did not compile: \(value)"
        }
    }
}

public enum GrammarProjectCodec {
    public static func encode(_ manifest: GrammarProjectManifest) throws -> Data {
        try validate(manifest)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    public static func decode(_ data: Data) throws -> GrammarProjectManifest {
        let value = try JSONDecoder().decode(GrammarProjectManifest.self, from: data)
        try validate(value)
        return value
    }

    public static func validate(_ manifest: GrammarProjectManifest) throws {
        guard manifest.schemaVersion == GrammarProjectManifest.currentSchemaVersion else {
            throw GrammarProjectError.unsupportedVersion(manifest.schemaVersion)
        }
        guard manifest.kind == GrammarProjectManifest.kindIdentifier else {
            throw GrammarProjectError.invalidKind(manifest.kind)
        }
        guard manifest.apiVersion == GrammarWorkbenchAPI.version else {
            throw GrammarProjectError.unsupportedAPIVersion(manifest.apiVersion)
        }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrammarProjectError.emptyName
        }
        var ids: Set<String> = []
        var paths: Set<String> = []
        for source in manifest.sources {
            guard !source.id.isEmpty, ids.insert(source.id).inserted else {
                throw GrammarProjectError.duplicateSourceID(source.id)
            }
            guard Self.isSafeRelativePath(source.path) else {
                throw GrammarProjectError.invalidRelativePath(source.path)
            }
            guard paths.insert(source.path.lowercased()).inserted else {
                throw GrammarProjectError.duplicateSourcePath(source.path)
            }
        }
        var generators: Set<String> = []
        for target in manifest.generators {
            guard !target.id.isEmpty, !target.generator.isEmpty,
                  generators.insert(target.id).inserted else {
                throw GrammarProjectError.duplicateGenerator(target.id)
            }
            guard Self.isSafeRelativePath(target.outputDirectory) else {
                throw GrammarProjectError.invalidRelativePath(target.outputDirectory)
            }
        }
    }

    public static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("\\"),
              !path.contains("\0"), !path.contains("\\") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }
}

public struct GrammarProjectIndexEntry: Hashable, Codable, Sendable {
    public let documentID: String
    public let path: String
    public let entry: GrammarIncrementalIndexEntry
}

public struct GrammarProjectIndex: Hashable, Codable, Sendable {
    public let entries: [GrammarProjectIndexEntry]

    public func entries(named symbol: String) -> [GrammarProjectIndexEntry] {
        entries.filter { $0.entry.symbol == symbol }
    }

    public func entries(documentID: String) -> [GrammarProjectIndexEntry] {
        entries.filter { $0.documentID == documentID }
    }
}

public struct GrammarProjectAnalysis: Sendable {
    public let manifest: GrammarProjectManifest
    public let compilation: GrammarCompilation
    public let documents: [GrammarIncrementalAnalysisSnapshot]
    public let index: GrammarProjectIndex
    public let tests: WorkbenchTestReport

    public var isSuccessful: Bool {
        compilation.succeeded
            && documents.count == manifest.sources.count
            && documents.allSatisfy { $0.lexing.diagnostics.isEmpty && $0.parse.status == .accepted }
            && (tests.results.isEmpty || tests.allPassed)
    }
}

public struct GrammarProjectGeneration: Sendable {
    public let target: GrammarProjectGeneratorTarget
    public let result: GrammarGenerationResult
}

/// Maintains all source documents in one manifest through the shared
/// incremental infrastructure and publishes a project-wide semantic index.
public actor GrammarProjectWorkspace {
    private var manifest: GrammarProjectManifest
    private var compilation: GrammarCompilation
    private var coordinator: GrammarIncrementalAnalysisCoordinator
    private var snapshots: [String: GrammarIncrementalAnalysisSnapshot] = [:]

    public init(manifest: GrammarProjectManifest) throws {
        try GrammarProjectCodec.validate(manifest)
        let compilation = GrammarWorkbenchAPI.compile(.init(
            source: manifest.grammar.source,
            algorithm: manifest.grammar.algorithm,
            notation: manifest.grammar.notation
        ))
        guard compilation.succeeded else {
            throw GrammarProjectError.grammarFailed(
                compilation.diagnostics.first?.message ?? "Unknown grammar error."
            )
        }
        self.manifest = manifest
        self.compilation = compilation
        coordinator = try GrammarIncrementalAnalysisCoordinator(compilation: compilation)
    }

    public func analyze() async throws -> GrammarProjectAnalysis {
        for source in manifest.sources {
            snapshots[source.id] = try await coordinator.synchronizeDocument(
                id: source.id, text: source.text, externalRevision: source.revision
            )
        }
        return currentAnalysis()
    }

    public func apply(
        documentID: String,
        edits: [GrammarTextEdit],
        revision: Int
    ) async throws -> GrammarProjectAnalysis {
        guard let index = manifest.sources.firstIndex(where: { $0.id == documentID }) else {
            throw GrammarProjectError.unknownSource(documentID)
        }
        if snapshots[documentID] == nil {
            let source = manifest.sources[index]
            snapshots[documentID] = try await coordinator.synchronizeDocument(
                id: source.id, text: source.text, externalRevision: source.revision
            )
        }
        let snapshot = try await coordinator.apply(
            documentID: documentID, edits: edits, externalRevision: revision
        )
        manifest.sources[index].text = snapshot.text.text
        manifest.sources[index].revision = snapshot.text.revision
        snapshots[documentID] = snapshot
        return currentAnalysis()
    }

    public func updateGrammar(_ grammar: GrammarProjectGrammar) async throws -> GrammarProjectAnalysis {
        let replacement = GrammarWorkbenchAPI.compile(.init(
            source: grammar.source, algorithm: grammar.algorithm, notation: grammar.notation
        ))
        guard replacement.succeeded else {
            throw GrammarProjectError.grammarFailed(
                replacement.diagnostics.first?.message ?? "Unknown grammar error."
            )
        }
        manifest.grammar = grammar
        compilation = replacement
        let refreshed = try await coordinator.updateCompilation(replacement)
        snapshots = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.documentID, $0) })
        for source in manifest.sources where snapshots[source.id] == nil {
            snapshots[source.id] = try await coordinator.synchronizeDocument(
                id: source.id, text: source.text, externalRevision: source.revision
            )
        }
        return currentAnalysis()
    }

    /// Reconciles a replacement source set while retaining incremental state
    /// for documents with the same identity. Removed documents release their
    /// session state; new and changed documents are analyzed atomically.
    public func replaceSources(
        _ sources: [GrammarProjectSource]
    ) async throws -> GrammarProjectAnalysis {
        var candidate = manifest
        candidate.sources = sources
        try GrammarProjectCodec.validate(candidate)

        let nextIDs = Set(sources.map(\.id))
        let removedIDs = snapshots.keys.filter { !nextIDs.contains($0) }
        for id in removedIDs {
            await coordinator.closeDocument(id: id)
            snapshots[id] = nil
        }
        manifest.sources = sources
        for index in manifest.sources.indices {
            let source = manifest.sources[index]
            let snapshot = try await coordinator.synchronizeDocument(
                id: source.id, text: source.text, externalRevision: source.revision
            )
            snapshots[source.id] = snapshot
            manifest.sources[index].revision = snapshot.text.revision
        }
        return currentAnalysis()
    }

    public func replaceTests(_ tests: [WorkbenchTestCase]) -> GrammarProjectAnalysis {
        manifest.tests = tests
        return currentAnalysis()
    }

    public func replaceGeneratorTargets(
        _ targets: [GrammarProjectGeneratorTarget]
    ) throws -> GrammarProjectAnalysis {
        var candidate = manifest
        candidate.generators = targets
        try GrammarProjectCodec.validate(candidate)
        manifest.generators = targets
        return currentAnalysis()
    }

    public func generate(
        using registry: GrammarGeneratorRegistry = .init()
    ) async throws -> [GrammarProjectGeneration] {
        var values: [GrammarProjectGeneration] = []
        for target in manifest.generators {
            values.append(.init(
                target: target,
                result: try await registry.generate(
                    identifier: target.generator,
                    from: compilation,
                    options: target.options
                )
            ))
        }
        return values
    }

    public func parse(
        documentID: String,
        options: GrammarPlatformParseOptions = .init()
    ) throws -> GrammarPlatformParseResult {
        guard let source = manifest.sources.first(where: { $0.id == documentID }) else {
            throw GrammarProjectError.unknownSource(documentID)
        }
        return try GrammarParsingPlatform(compilation: compilation).parse(.init(
            id: documentID, input: source.text, options: options
        ))
    }

    public func parseAll(
        options: GrammarPlatformParseOptions = .init(),
        batchOptions: GrammarPlatformBatchOptions = .init()
    ) async throws -> GrammarPlatformBatchResult {
        let platform = try GrammarParsingPlatform(compilation: compilation)
        return await platform.parseBatch(
            manifest.sources.map {
                .init(id: $0.id, input: $0.text, options: options)
            },
            options: batchOptions
        )
    }

    public func structuralGrammarAnalysis() throws -> GrammarStructuralAnalysis {
        try GrammarEngineering.analyze(compilation)
    }

    public func previewGrammarTransformation(
        _ kind: GrammarTransformationKind,
        options: GrammarBehaviorComparisonOptions = .init()
    ) throws -> GrammarTransformationResult {
        let request = GrammarCompilationRequest(
            source: manifest.grammar.source,
            algorithm: manifest.grammar.algorithm,
            notation: manifest.grammar.notation
        )
        let plan = try GrammarEngineering.plan(kind, for: compilation)
        let corpus = manifest.sources.map {
            GrammarBehaviorCorpusEntry(id: $0.id, input: $0.text, origin: $0.path)
        }
        return try GrammarEngineering.execute(
            plan, request: request, corpus: corpus, tests: manifest.tests, options: options
        )
    }

    public func previewGrammarRename(
        from oldName: String,
        to newName: String,
        options: GrammarBehaviorComparisonOptions = .init()
    ) throws -> GrammarRefactoringResult {
        let request = GrammarCompilationRequest(
            source: manifest.grammar.source,
            algorithm: manifest.grammar.algorithm,
            notation: manifest.grammar.notation
        )
        let plan = try GrammarRefactoring.planRename(from: oldName, to: newName, in: compilation)
        let corpus = manifest.sources.map {
            GrammarBehaviorCorpusEntry(id: $0.id, input: $0.text, origin: $0.path)
        }
        return try GrammarRefactoring.execute(
            plan, request: request, corpus: corpus, tests: manifest.tests, options: options
        )
    }

    public func projectManifest() -> GrammarProjectManifest { manifest }

    private func currentAnalysis() -> GrammarProjectAnalysis {
        let ordered = manifest.sources.compactMap { snapshots[$0.id] }
        let pathByID = Dictionary(uniqueKeysWithValues: manifest.sources.map { ($0.id, $0.path) })
        let entries = ordered.flatMap { snapshot in
            snapshot.semanticIndex.entries.map {
                GrammarProjectIndexEntry(
                    documentID: snapshot.documentID,
                    path: pathByID[snapshot.documentID] ?? snapshot.documentID,
                    entry: $0
                )
            }
        }
        return .init(
            manifest: manifest,
            compilation: compilation,
            documents: ordered,
            index: .init(entries: entries),
            tests: compilation.runTests(manifest.tests)
        )
    }
}

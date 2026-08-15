import Foundation

/// A portable language definition that binds syntax, workspace semantics,
/// conformance examples, and generator defaults into one reusable contract.
public struct GrammarSemanticLanguageKitManifest: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-semantic-language-kit"

    public let schemaVersion: Int
    public let kind: String
    public let apiVersion: Int
    public var identifier: String
    public var name: String
    public var version: String
    public var fileExtensions: [String]
    public var grammar: GrammarProjectGrammar
    public var semantics: GrammarSemanticWorkspaceSchema
    public var tests: [WorkbenchTestCase]
    public var generators: [GrammarProjectGeneratorTarget]
    public var metadata: [String: String]

    public init(
        identifier: String, name: String, version: String,
        fileExtensions: [String], grammar: GrammarProjectGrammar,
        semantics: GrammarSemanticWorkspaceSchema,
        tests: [WorkbenchTestCase] = [],
        generators: [GrammarProjectGeneratorTarget] = [],
        metadata: [String: String] = [:]
    ) {
        schemaVersion = Self.currentSchemaVersion
        kind = Self.kindIdentifier
        apiVersion = GrammarWorkbenchAPI.version
        self.identifier = identifier
        self.name = name
        self.version = version
        self.fileExtensions = fileExtensions
        self.grammar = grammar
        self.semantics = semantics
        self.tests = tests
        self.generators = generators
        self.metadata = metadata
    }
}

public enum GrammarSemanticLanguageKitError: Error, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case unsupportedAPIVersion(Int)
    case invalidKind(String)
    case invalidIdentifier(String)
    case emptyName
    case emptyVersion
    case invalidFileExtension(String)
    case duplicateFileExtension(String)
    case invalidSemanticRule(Int, String)
    case duplicateSemanticSelector(Int, Int)
    case grammarFailed(String)
    case conformanceFailed(Int)
    case unsupportedSourcePath(String)
    case duplicateKit(String)
    case unknownKit(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let value): "Unsupported semantic language-kit schema version \(value)."
        case .unsupportedAPIVersion(let value): "Unsupported Grammar Workbench API version \(value)."
        case .invalidKind(let value): "Unexpected semantic language-kit kind ‘\(value)’."
        case .invalidIdentifier(let value): "Language-kit identifier ‘\(value)’ is invalid."
        case .emptyName: "A language-kit name must not be empty."
        case .emptyVersion: "A language-kit version must not be empty."
        case .invalidFileExtension(let value): "Language-kit file extension ‘\(value)’ is invalid."
        case .duplicateFileExtension(let value): "Language-kit file extension ‘\(value)’ is duplicated."
        case .invalidSemanticRule(let index, let reason): "Semantic rule \(index) is invalid: \(reason)"
        case .duplicateSemanticSelector(let first, let second):
            "Semantic rule \(second) is unreachable because rule \(first) has the same selector."
        case .grammarFailed(let value): "The language-kit grammar did not compile: \(value)"
        case .conformanceFailed(let count): "The language kit has \(count) failing conformance test(s)."
        case .unsupportedSourcePath(let path): "The language kit does not support source path ‘\(path)’."
        case .duplicateKit(let identifier): "Language kit ‘\(identifier)’ is already registered."
        case .unknownKit(let identifier): "Language kit ‘\(identifier)’ is not registered."
        }
    }
}

public enum GrammarSemanticLanguageKitCodec {
    public static func encode(_ manifest: GrammarSemanticLanguageKitManifest) throws -> Data {
        _ = try GrammarSemanticLanguageKit.compile(manifest, requirePassingTests: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    public static func decode(
        _ data: Data, requirePassingTests: Bool = false
    ) throws -> GrammarSemanticLanguageKit {
        let manifest = try JSONDecoder().decode(GrammarSemanticLanguageKitManifest.self, from: data)
        return try GrammarSemanticLanguageKit.compile(
            manifest, requirePassingTests: requirePassingTests
        )
    }
}

/// A validated kit. Its compilation and semantic model are retained so hosts
/// can instantiate many projects without recompiling the language definition.
public struct GrammarSemanticLanguageKit: Sendable {
    public let manifest: GrammarSemanticLanguageKitManifest
    public let compilation: GrammarCompilation
    public let semanticModel: GrammarSemanticModel
    public let conformance: WorkbenchTestReport

    public var isConformant: Bool { conformance.results.isEmpty || conformance.allPassed }

    public static func compile(
        _ manifest: GrammarSemanticLanguageKitManifest,
        requirePassingTests: Bool = true
    ) throws -> Self {
        try validateEnvelope(manifest)
        let compilation = GrammarWorkbenchAPI.compile(.init(
            source: manifest.grammar.source,
            algorithm: manifest.grammar.algorithm,
            notation: manifest.grammar.notation
        ))
        guard compilation.succeeded else {
            throw GrammarSemanticLanguageKitError.grammarFailed(
                compilation.diagnostics.first?.message ?? "Unknown grammar error."
            )
        }
        let model = try GrammarSemanticModel(compilation: compilation)
        try validateSemanticRules(manifest.semantics.rules, model: model)
        let report = compilation.runTests(manifest.tests)
        if requirePassingTests, !report.allPassed, !report.results.isEmpty {
            throw GrammarSemanticLanguageKitError.conformanceFailed(report.failed)
        }
        return .init(
            manifest: manifest, compilation: compilation,
            semanticModel: model, conformance: report
        )
    }

    public func supportsFile(named path: String) -> Bool {
        guard let suffix = path.split(separator: ".").last, path.contains(".") else { return false }
        return manifest.fileExtensions.contains { $0.caseInsensitiveCompare(String(suffix)) == .orderedSame }
    }

    public func project(
        name: String? = nil, sources: [GrammarProjectSource] = []
    ) -> GrammarProjectManifest {
        .init(
            name: name ?? manifest.name, grammar: manifest.grammar,
            sources: sources, tests: manifest.tests, generators: manifest.generators
        )
    }

    public func makeWorkspace(
        name: String? = nil, sources: [GrammarProjectSource] = []
    ) throws -> GrammarProjectWorkspace {
        for source in sources where !supportsFile(named: source.path) {
            throw GrammarSemanticLanguageKitError.unsupportedSourcePath(source.path)
        }
        return try GrammarProjectWorkspace(manifest: project(name: name, sources: sources))
    }

    public func analyze(
        name: String? = nil, sources: [GrammarProjectSource]
    ) async throws -> GrammarSemanticLanguageKitAnalysis {
        let workspace = try makeWorkspace(name: name, sources: sources)
        let project = try await workspace.analyze()
        return .init(
            project: project,
            semantics: project.semanticWorkspace(schema: manifest.semantics)
        )
    }

    private static func validateEnvelope(
        _ manifest: GrammarSemanticLanguageKitManifest
    ) throws {
        guard manifest.schemaVersion == GrammarSemanticLanguageKitManifest.currentSchemaVersion else {
            throw GrammarSemanticLanguageKitError.unsupportedVersion(manifest.schemaVersion)
        }
        guard manifest.kind == GrammarSemanticLanguageKitManifest.kindIdentifier else {
            throw GrammarSemanticLanguageKitError.invalidKind(manifest.kind)
        }
        guard manifest.apiVersion == GrammarWorkbenchAPI.version else {
            throw GrammarSemanticLanguageKitError.unsupportedAPIVersion(manifest.apiVersion)
        }
        let identifierPattern = #"^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$"#
        guard manifest.identifier.range(of: identifierPattern, options: .regularExpression) != nil else {
            throw GrammarSemanticLanguageKitError.invalidIdentifier(manifest.identifier)
        }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrammarSemanticLanguageKitError.emptyName
        }
        guard !manifest.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GrammarSemanticLanguageKitError.emptyVersion
        }
        var extensions: Set<String> = []
        for value in manifest.fileExtensions {
            guard value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else {
                throw GrammarSemanticLanguageKitError.invalidFileExtension(value)
            }
            guard extensions.insert(value.lowercased()).inserted else {
                throw GrammarSemanticLanguageKitError.duplicateFileExtension(value)
            }
        }
        let project = GrammarProjectManifest(
            name: manifest.name, grammar: manifest.grammar,
            tests: manifest.tests, generators: manifest.generators
        )
        try GrammarProjectCodec.validate(project)
    }

    private static func validateSemanticRules(
        _ rules: [GrammarSemanticSymbolRule], model: GrammarSemanticModel
    ) throws {
        let terminals = Set(model.terminals)
        let productions = Set(model.productions.map(\.id))
        var selectors: [String: Int] = [:]
        for (index, rule) in rules.enumerated() {
            guard terminals.contains(rule.tokenKind) else {
                throw GrammarSemanticLanguageKitError.invalidSemanticRule(
                    index, "terminal ‘\(rule.tokenKind)’ does not exist"
                )
            }
            guard !rule.kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GrammarSemanticLanguageKitError.invalidSemanticRule(index, "symbol kind is empty")
            }
            if let production = rule.enclosingProduction, !productions.contains(production) {
                throw GrammarSemanticLanguageKitError.invalidSemanticRule(
                    index, "production \(production) does not exist"
                )
            }
            let selector = "\(rule.tokenKind)\u{1f}\(rule.enclosingProduction.map(String.init) ?? "*")"
            if let first = selectors[selector] {
                throw GrammarSemanticLanguageKitError.duplicateSemanticSelector(first, index)
            }
            selectors[selector] = index
        }
    }
}

public struct GrammarSemanticLanguageKitAnalysis: Sendable {
    public let project: GrammarProjectAnalysis
    public let semantics: GrammarSemanticWorkspaceSnapshot

    public var isSuccessful: Bool {
        project.isSuccessful && semantics.diagnostics.isEmpty
    }
}

/// An actor-backed catalog suitable for applications and long-running hosts.
/// Registration is explicit so two packages cannot silently replace the same
/// language identity.
public actor GrammarSemanticLanguageKitRegistry {
    private var kits: [String: GrammarSemanticLanguageKit] = [:]

    public init() {}

    @discardableResult
    public func register(
        _ manifest: GrammarSemanticLanguageKitManifest,
        replacingExisting: Bool = false
    ) throws -> GrammarSemanticLanguageKit {
        if kits[manifest.identifier] != nil, !replacingExisting {
            throw GrammarSemanticLanguageKitError.duplicateKit(manifest.identifier)
        }
        let kit = try GrammarSemanticLanguageKit.compile(manifest)
        kits[manifest.identifier] = kit
        return kit
    }

    public func unregister(identifier: String) throws {
        guard kits.removeValue(forKey: identifier) != nil else {
            throw GrammarSemanticLanguageKitError.unknownKit(identifier)
        }
    }

    public func kit(identifier: String) -> GrammarSemanticLanguageKit? {
        kits[identifier]
    }

    public func kits(forFile path: String) -> [GrammarSemanticLanguageKit] {
        kits.values.filter { $0.supportsFile(named: path) }.sorted {
            $0.manifest.identifier < $1.manifest.identifier
        }
    }

    public var registeredIdentifiers: [String] { kits.keys.sorted() }
}

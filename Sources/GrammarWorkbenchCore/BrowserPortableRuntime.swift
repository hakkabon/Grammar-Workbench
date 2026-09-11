import Foundation

public enum GrammarBrowserRuntimeProfile: String, Hashable, Codable, Sendable {
    case portableArtifactWorker
    case swiftWASIAdapter
}

/// The product decision separating supported browser execution from the
/// standalone WASI command host. Downstream clients can gate their integration
/// without inferring support from the presence of a `.wasm` artifact.
public struct GrammarBrowserRuntimeDecision: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let portableArtifactSchemaVersion = 2
    public static let portableRuntimeVersion = 1

    public let schemaVersion: Int
    public let maturity: GrammarWorkbenchFeatureMaturity
    public let selectedProfile: GrammarBrowserRuntimeProfile
    public let unsupportedProfiles: [GrammarBrowserRuntimeProfile]
    public let artifactKind: String
    public let artifactSchemaVersion: Int
    public let runtimeVersion: Int
    public let executionIsolation: String
    public let cancellation: String
    public let resourceLimits: [String]
    public let rationale: [String]

    public static let current = Self(
        schemaVersion: currentSchemaVersion,
        maturity: .stable,
        selectedProfile: .portableArtifactWorker,
        unsupportedProfiles: [.swiftWASIAdapter],
        artifactKind: "grammar-workbench-portable-lr",
        artifactSchemaVersion: portableArtifactSchemaVersion,
        runtimeVersion: portableRuntimeVersion,
        executionIsolation: "dedicated-web-worker-per-parse",
        cancellation: "worker-termination",
        resourceLimits: ["input-length", "token-count", "parser-steps", "stack-depth"],
        rationale: [
            "Portable LR artifacts require no browser WASI compatibility layer.",
            "A dedicated worker provides deterministic cancellation and isolates parser work from the UI.",
            "Grammar compilation remains available through native, service, and standalone WASI hosts."
        ]
    )
}

public struct BrowserPortableRuntimeGrammarGenerator: GrammarGenerator {
    public let descriptor = GrammarGeneratorDescriptor(
        id: "portable-browser", displayName: "Portable Browser LR Artifact",
        summary: "A validated table artifact for the worker-based browser runtime.",
        defaultFileExtension: "portable-lr.json", mediaType: "application/json",
        options: [.init(name: "name", summary: "Artifact display name.", defaultValue: "Portable parser")]
    )

    public init() {}

    public func generate(from compilation: GrammarCompilation, options: GrammarGeneratorOptions) throws -> GrammarGenerationResult {
        guard compilation.succeeded, let artifact = compilation.artifact,
              let grammar = compilation.parsedGrammar else {
            throw GrammarGeneratorRegistryError.compilationFailed("The grammar did not compile.")
        }
        guard grammar.lexerRules.allSatisfy({ $0.mode == "DEFAULT" && $0.action == .none }) else {
            throw GrammarGeneratorRegistryError.invalidOption(name: "grammar", value: "browser runtime supports DEFAULT-mode lexer rules without transitions")
        }
        var actions: [String: PortableAction] = [:]
        var gotos: [String: Int] = [:]
        for cell in artifact.table {
            guard cell.actions.count == 1, let action = cell.actions.first else {
                throw GrammarGeneratorRegistryError.invalidOption(name: "grammar", value: "portable browser artifacts require conflict-free tables")
            }
            let key = "\(cell.state)|\(cell.symbol)"
            switch action.kind {
            case .shift: actions[key] = .init(kind: "shift", state: action.targetState, production: nil)
            case .reduce: actions[key] = .init(kind: "reduce", state: nil, production: action.production)
            case .accept: actions[key] = .init(kind: "accept", state: nil, production: nil)
            case .goTo: if let state = action.targetState { gotos[key] = state }
            }
        }
        let patterned = Set(grammar.lexerRules.compactMap(\.token))
        var tokens = grammar.lexerRules.map {
            PortableToken(kind: $0.token ?? "__skip_\($0.id)", literal: nil, pattern: "^(?:\($0.pattern))", skip: $0.isSkipped)
        }
        tokens += grammar.terminals.filter { $0 != "$" && !patterned.contains($0) }.map {
            PortableToken(kind: $0, literal: $0, pattern: nil, skip: false)
        }
        let value = PortableArtifact(
            kind: GrammarBrowserRuntimeDecision.current.artifactKind,
            schemaVersion: GrammarBrowserRuntimeDecision.portableArtifactSchemaVersion,
            minimumRuntimeVersion: GrammarBrowserRuntimeDecision.portableRuntimeVersion,
            name: options["name"] ?? "Portable parser", limits: .init(), startState: 0,
            endToken: "$", tokens: tokens, productions: artifact.productions,
            actions: actions, gotos: gotos
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return .init(generator: descriptor, files: [
            .init(suggestedFilename: "Grammar.portable-lr.json", mediaType: descriptor.mediaType, contents: try encoder.encode(value))
        ])
    }
}

private struct PortableToken: Encodable { let kind: String; let literal: String?; let pattern: String?; let skip: Bool }
private struct PortableAction: Encodable { let kind: String; let state: Int?; let production: Int? }
private struct PortableLimits: Encodable {
    let maximumInputLength = 10_000, maximumTokens = 2_000, maximumSteps = 10_000, maximumStackDepth = 2_048
}
private struct PortableArtifact: Encodable {
    let kind: String, schemaVersion: Int, minimumRuntimeVersion: Int, name: String
    let limits: PortableLimits; let startState: Int; let endToken: String
    let tokens: [PortableToken]; let productions: [GrammarProductionSnapshot]
    let actions: [String: PortableAction]; let gotos: [String: Int]
}

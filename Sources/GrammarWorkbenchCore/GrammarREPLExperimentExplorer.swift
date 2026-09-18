import Foundation

/// Read-only Workbench projection of Grammar-REPL's schema-1 through schema-3 experiments.
/// Grammar-REPL remains the owner of capture, fingerprint validation, and replay verification.
public struct GrammarREPLExperimentArtifact: Hashable, Codable, Sendable {
    public static let supportedSchemaVersion = 3
    public static let supportedFingerprintAlgorithm = "fnv1a64"
    public static let canonicalEngines = [
        "earley", "earley-sl", "earley-el", "cyk", "rnglr",
        "ll1", "lr0", "slr", "lalr", "lr1",
    ]

    public let schemaVersion: Int
    public let producer: Producer
    public let input: String
    public let engines: [String]
    public let precedence: Precedence
    public let resolutionPolicy: String?
    public let agreement: Agreement
    public let observations: [Observation]
    public let semanticReport: SemanticReport?
    public let fingerprintAlgorithm: String
    public let fingerprint: String

    public struct Producer: Hashable, Codable, Sendable {
        public let name: String
        public let version: String
    }

    public enum Agreement: String, Hashable, Codable, Sendable {
        case complete
        case acceptanceOnly
        case divergent
        case inconclusive
    }

    public struct Precedence: Hashable, Codable, Sendable {
        public let levels: [Level]
        public let productionOverrides: [ProductionOverride]

        public struct Level: Hashable, Codable, Sendable {
            public let level: Int
            public let associativity: String

            private enum CodingKeys: String, CodingKey { case level, associativity }
        }

        public struct ProductionOverride: Hashable, Codable, Sendable {
            public let productionID: String

            private enum CodingKeys: String, CodingKey { case productionID }
        }
    }

    public struct Observation: Hashable, Codable, Sendable, Identifiable {
        public let parser: String
        public let availability: Availability
        public let unsupportedReason: String?
        public let contract: Contract
        public let treeFingerprints: [String]
        public var id: String { parser }
    }

    public enum Availability: String, Hashable, Codable, Sendable {
        case supported
        case unsupported
    }

    public struct Contract: Hashable, Codable, Sendable {
        public let schemaVersion: Int
        public let engine: Engine
        public let status: Status
        public let forest: Forest?
        public let diagnostics: [Diagnostic]
        public let replay: [ReplayEvent]

        public struct Engine: Hashable, Codable, Sendable {
            public let identity: String
            public let displayName: String
            public let algorithm: String
        }

        public struct Diagnostic: Hashable, Codable, Sendable {
            public let message: String

            private enum CodingKeys: String, CodingKey { case message }
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, engine, status, forest, diagnostics, replay
        }
    }

    public enum Status: String, Hashable, Codable, Sendable {
        case accepted
        case recovered
        case rejected
    }

    public struct Forest: Hashable, Codable, Sendable {
        public let schemaVersion: Int
        public let nodes: [ForestNode]
        public let edges: [ForestEdge]
        public let roots: [String]
        public let ambiguityNodes: [String]

        public var isAmbiguous: Bool { !ambiguityNodes.isEmpty }
    }

    public struct ForestNode: Hashable, Codable, Sendable, Identifiable {
        public let id: String
        public let kind: ForestNodeKind
        public let label: String?
        public let productionID: String?
        public let position: Int?
        public let leftExtent: Int
        public let rightExtent: Int
        public let pivot: Int?
    }

    public enum ForestNodeKind: String, Hashable, Codable, Sendable {
        case token
        case symbol
        case intermediate
        case packed
    }

    public struct ForestEdge: Hashable, Codable, Sendable {
        public let parent: String
        public let child: String
    }

    public struct ReplayEvent: Hashable, Codable, Sendable, Identifiable {
        public let step: Int
        public let kind: ReplayKind
        public let tokenIndex: Int?
        public let productionID: String?
        public let forestNodeID: String?
        public let diagnosticReason: String?
        public var id: Int { step }
    }

    public enum ReplayKind: String, Hashable, Codable, Sendable {
        case start
        case inspect
        case consume
        case applyProduction
        case discoverAmbiguity
        case recover
        case accept
        case reject
    }

    public struct SemanticReport: Hashable, Codable, Sendable {
        public let schemaVersion: Int
        public let agreement: SemanticAgreement
        public let ambiguity: SemanticAmbiguity?
        public let observations: [SemanticObservation]
    }

    public enum SemanticAgreement: String, Hashable, Codable, Sendable {
        case complete
        case divergent
        case inconclusive
    }

    public enum SemanticAmbiguity: String, Hashable, Codable, Sendable {
        case syntacticallyUnambiguous
        case semanticallyEquivalent
        case semanticallyDivergent
        case unresolved
    }

    public struct SemanticObservation: Hashable, Codable, Sendable, Identifiable {
        public let engine: String
        public let status: SemanticStatus
        public let derivationCount: Int
        public let values: [SemanticValue]
        public let diagnostics: [SemanticDiagnostic]
        public let ambiguity: SemanticAmbiguity?
        public let derivations: [SemanticDerivation]?
        public var id: String { engine }
    }

    public enum SemanticStatus: String, Hashable, Codable, Sendable {
        case evaluated
        case partiallyEvaluated
        case parseRejected
        case noSyntaxTree
        case failed
    }

    public struct SemanticDiagnostic: Hashable, Codable, Sendable {
        public let stage: String
        public let message: String
    }

    public struct SemanticDerivation: Hashable, Codable, Sendable, Identifiable {
        public let index: Int
        public let syntaxFingerprint: String
        public let value: SemanticValue?
        public let diagnostic: SemanticDiagnostic?
        public var id: Int { index }
    }

    public indirect enum SemanticValue: Hashable, Codable, Sendable {
        case integer(Int64)
        case floatingPoint(Double)
        case string(String)
        case boolean(Bool)
        case null
        case array([SemanticValue])
        case record(name: String, fields: [String: SemanticValue])

        public var displayValue: String {
            switch self {
            case .integer(let value): "\(value)"
            case .floatingPoint(let value): "\(value)"
            case .string(let value): value
            case .boolean(let value): value ? "true" : "false"
            case .null: "null"
            case .array(let values): "[\(values.map(\.displayValue).joined(separator: ", "))]"
            case .record(let name, let fields):
                "\(name) { \(fields.keys.sorted().map { "\($0): \(fields[$0]!.displayValue)" }.joined(separator: ", ")) }"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case kind, integer, floatingPoint, string, boolean, items, name, fields
        }
        private enum Kind: String, Codable {
            case integer, floatingPoint, string, boolean, null, array, record
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            switch try values.decode(Kind.self, forKey: .kind) {
            case .integer: self = .integer(try values.decode(Int64.self, forKey: .integer))
            case .floatingPoint: self = .floatingPoint(try values.decode(Double.self, forKey: .floatingPoint))
            case .string: self = .string(try values.decode(String.self, forKey: .string))
            case .boolean: self = .boolean(try values.decode(Bool.self, forKey: .boolean))
            case .null: self = .null
            case .array: self = .array(try values.decode([Self].self, forKey: .items))
            case .record:
                self = .record(
                    name: try values.decode(String.self, forKey: .name),
                    fields: try values.decode([String: Self].self, forKey: .fields)
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .integer(let value):
                try values.encode(Kind.integer, forKey: .kind); try values.encode(value, forKey: .integer)
            case .floatingPoint(let value):
                try values.encode(Kind.floatingPoint, forKey: .kind); try values.encode(value, forKey: .floatingPoint)
            case .string(let value):
                try values.encode(Kind.string, forKey: .kind); try values.encode(value, forKey: .string)
            case .boolean(let value):
                try values.encode(Kind.boolean, forKey: .kind); try values.encode(value, forKey: .boolean)
            case .null: try values.encode(Kind.null, forKey: .kind)
            case .array(let items):
                try values.encode(Kind.array, forKey: .kind); try values.encode(items, forKey: .items)
            case .record(let name, let fields):
                try values.encode(Kind.record, forKey: .kind)
                try values.encode(name, forKey: .name); try values.encode(fields, forKey: .fields)
            }
        }
    }

    public var summary: GrammarREPLExperimentSummary {
        .init(artifact: self)
    }

    public func observation(for parser: String) -> Observation? {
        observations.first { $0.parser == parser }
    }

    public func semanticObservation(for parser: String) -> SemanticObservation? {
        semanticReport?.observations.first { $0.engine == parser }
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 64 * 1_024 * 1_024 else {
            throw GrammarREPLExperimentExplorerError.artifactTooLarge
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let grammar = root["grammar"] as? [String: Any],
              grammar["start"] != nil,
              let productions = grammar["productions"] as? [Any],
              !productions.isEmpty else {
            throw GrammarREPLExperimentExplorerError.missingGrammar
        }
        let semanticMapping = root["semanticMapping"] as? [String: Any]
        guard (root["semanticMapping"] != nil) == (root["semanticReport"] != nil),
              semanticMapping == nil || semanticMapping?["version"] as? Int == 1 else {
            throw GrammarREPLExperimentExplorerError.invalidSemanticEvidence
        }
        let value: Self
        do { value = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw GrammarREPLExperimentExplorerError.malformed(String(describing: error)) }
        try value.validate()
        return value
    }

    public func validate() throws {
        guard (1...Self.supportedSchemaVersion).contains(schemaVersion) else {
            throw GrammarREPLExperimentExplorerError.unsupportedSchema(schemaVersion)
        }
        guard producer.name == "Grammar-REPL", Self.isCompatibleProducerVersion(producer.version) else {
            throw GrammarREPLExperimentExplorerError.invalidProducer
        }
        guard fingerprintAlgorithm == Self.supportedFingerprintAlgorithm,
              fingerprint.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil else {
            throw GrammarREPLExperimentExplorerError.invalidFingerprint
        }
        let selected = Set(engines)
        guard !engines.isEmpty, selected.count == engines.count,
              engines == Self.canonicalEngines.filter(selected.contains),
              observations.map(\.parser) == engines else {
            throw GrammarREPLExperimentExplorerError.invalidEngines
        }
        let precedenceLevels = precedence.levels.map(\.level)
        guard Set(precedenceLevels).count == precedenceLevels.count,
              precedenceLevels == precedenceLevels.sorted(),
              precedence.levels.allSatisfy({ ["left", "right", "nonAssociative"].contains($0.associativity) }),
              Set(precedence.productionOverrides.map(\.productionID)).count == precedence.productionOverrides.count,
              [nil, "preferShift", "preferReduce", "reject"].contains(resolutionPolicy) else {
            throw GrammarREPLExperimentExplorerError.invalidSettings
        }
        for observation in observations { try validate(observation) }
        if let semantics = semanticReport {
            let expectedSemanticSchema = schemaVersion >= 3 ? 2 : 1
            guard schemaVersion >= 2, semantics.schemaVersion == expectedSemanticSchema,
                  semantics.observations.map(\.engine) == engines else {
                throw GrammarREPLExperimentExplorerError.invalidSemanticEvidence
            }
            for observation in semantics.observations {
                let valid: Bool
                switch observation.status {
                case .evaluated:
                    valid = observation.derivationCount > 0
                        && !observation.values.isEmpty && observation.diagnostics.isEmpty
                case .partiallyEvaluated:
                    valid = semantics.schemaVersion >= 2 && observation.derivationCount > 1
                        && !observation.values.isEmpty && !observation.diagnostics.isEmpty
                case .parseRejected, .noSyntaxTree:
                    valid = observation.derivationCount == 0
                        && observation.values.isEmpty && observation.diagnostics.isEmpty
                case .failed:
                    valid = observation.derivationCount > 0
                        && observation.values.isEmpty && !observation.diagnostics.isEmpty
                }
                guard valid else {
                    throw GrammarREPLExperimentExplorerError.invalidSemanticEvidence
                }
                if semantics.schemaVersion == 1 {
                    guard observation.ambiguity == nil, observation.derivations == nil else {
                        throw GrammarREPLExperimentExplorerError.invalidSemanticEvidence
                    }
                } else {
                    try validateSemanticDerivations(observation)
                }
            }
            let evaluated = semantics.observations.filter { $0.status == .evaluated }
            let expectedAgreement: SemanticAgreement
            if evaluated.count < 2 || semantics.observations.contains(where: { $0.status == .partiallyEvaluated }) {
                expectedAgreement = .inconclusive
            } else {
                expectedAgreement = Set(evaluated.map { Set($0.values) }).count == 1
                    ? .complete : .divergent
            }
            guard semantics.agreement == expectedAgreement else {
                throw GrammarREPLExperimentExplorerError.invalidSemanticEvidence
            }
            if semantics.schemaVersion == 1 {
                guard semantics.ambiguity == nil else {
                    throw GrammarREPLExperimentExplorerError.invalidSemanticEvidence
                }
            } else {
                let classes = semantics.observations.compactMap(\.ambiguity)
                let expectedAmbiguity: SemanticAmbiguity
                if classes.contains(.semanticallyDivergent) { expectedAmbiguity = .semanticallyDivergent }
                else if classes.contains(.unresolved) { expectedAmbiguity = .unresolved }
                else if classes.contains(.semanticallyEquivalent) { expectedAmbiguity = .semanticallyEquivalent }
                else { expectedAmbiguity = classes.isEmpty ? .unresolved : .syntacticallyUnambiguous }
                guard semantics.ambiguity == expectedAmbiguity else {
                    throw GrammarREPLExperimentExplorerError.invalidSemanticEvidence
                }
            }
        }
    }

    private func validateSemanticDerivations(_ observation: SemanticObservation) throws {
        guard let ambiguity = observation.ambiguity,
              let derivations = observation.derivations,
              derivations.count == observation.derivationCount,
              derivations.map(\.index) == Array(derivations.indices),
              derivations.allSatisfy({
                  $0.syntaxFingerprint.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil
                      && (($0.value == nil) != ($0.diagnostic == nil))
              }) else {
            throw GrammarREPLExperimentExplorerError.invalidSemanticEvidence
        }
        let successful = derivations.compactMap(\.value)
        let failures = derivations.compactMap(\.diagnostic)
        guard Set(observation.values).count == observation.values.count,
              Set(successful) == Set(observation.values),
              failures == observation.diagnostics else {
            throw GrammarREPLExperimentExplorerError.invalidSemanticEvidence
        }
        if observation.status == .parseRejected || observation.status == .noSyntaxTree {
            guard derivations.isEmpty, ambiguity == .unresolved else {
                throw GrammarREPLExperimentExplorerError.invalidSemanticEvidence
            }
            return
        }
        let expectedStatus: SemanticStatus = failures.isEmpty
            ? .evaluated : (successful.isEmpty ? .failed : .partiallyEvaluated)
        let expectedAmbiguity: SemanticAmbiguity
        if derivations.isEmpty || !failures.isEmpty { expectedAmbiguity = .unresolved }
        else if derivations.count == 1 { expectedAmbiguity = .syntacticallyUnambiguous }
        else if Set(successful).count == 1 { expectedAmbiguity = .semanticallyEquivalent }
        else { expectedAmbiguity = .semanticallyDivergent }
        guard observation.status == expectedStatus, ambiguity == expectedAmbiguity else {
            throw GrammarREPLExperimentExplorerError.invalidSemanticEvidence
        }
    }

    private func validate(_ observation: Observation) throws {
        guard observation.contract.schemaVersion == 1,
              !observation.contract.engine.identity.isEmpty,
              !observation.contract.engine.algorithm.isEmpty,
              (observation.availability == .unsupported) == (observation.unsupportedReason != nil),
              observation.treeFingerprints == observation.treeFingerprints.sorted() else {
            throw GrammarREPLExperimentExplorerError.invalidObservation(observation.parser)
        }
        let replay = observation.contract.replay
        guard replay.map(\.step) == Array(replay.indices) else {
            throw GrammarREPLExperimentExplorerError.invalidReplay(observation.parser)
        }
        let expectedEnd: ReplayKind = observation.contract.status == .rejected ? .reject : .accept
        let hasValidEnvelope = replay.isEmpty
            ? observation.contract.status == .rejected
            : ((replay.first?.kind == .start || (replay.count == 1 && replay.first?.kind == expectedEnd))
               && replay.last?.kind == expectedEnd)
        guard hasValidEnvelope else {
            throw GrammarREPLExperimentExplorerError.invalidReplay(observation.parser)
        }
        guard let forest = observation.contract.forest else {
            if replay.contains(where: { $0.forestNodeID != nil }) {
                throw GrammarREPLExperimentExplorerError.invalidReplay(observation.parser)
            }
            return
        }
        guard forest.schemaVersion == 1 else {
            throw GrammarREPLExperimentExplorerError.invalidForest(observation.parser)
        }
        let nodeIDs = Set(forest.nodes.map(\.id))
        guard forest.nodes.count <= 250_000, replay.count <= 1_000_000,
              nodeIDs.count == forest.nodes.count,
              forest.nodes.allSatisfy({ $0.leftExtent >= 0 && $0.rightExtent >= $0.leftExtent && ($0.pivot == nil || ($0.pivot! >= $0.leftExtent && $0.pivot! <= $0.rightExtent)) }),
              forest.edges.allSatisfy({ nodeIDs.contains($0.parent) && nodeIDs.contains($0.child) }),
              forest.roots.allSatisfy(nodeIDs.contains),
              forest.ambiguityNodes.allSatisfy(nodeIDs.contains),
              replay.compactMap(\.forestNodeID).allSatisfy(nodeIDs.contains) else {
            throw GrammarREPLExperimentExplorerError.invalidForest(observation.parser)
        }
    }

    private static func isCompatibleProducerVersion(_ value: String) -> Bool {
        let components = value.split(separator: ".").compactMap { Int($0) }
        guard components.count == 3, components.allSatisfy({ $0 >= 0 }) else { return false }
        return components.lexicographicallyPrecedes([0, 5, 0]) == false
    }
}

public struct GrammarREPLExperimentSummary: Hashable, Codable, Sendable {
    public let engineCount: Int
    public let supportedEngineCount: Int
    public let acceptedEngineCount: Int
    public let ambiguousEngineCount: Int
    public let maximumDerivationCount: Int
    public let maximumForestNodeCount: Int
    public let replayEventCount: Int
    public let semanticEvaluatedEngineCount: Int
    public let semanticAgreement: GrammarREPLExperimentArtifact.SemanticAgreement?
    public let semanticAmbiguity: GrammarREPLExperimentArtifact.SemanticAmbiguity?

    init(artifact: GrammarREPLExperimentArtifact) {
        engineCount = artifact.observations.count
        supportedEngineCount = artifact.observations.count { $0.availability == .supported }
        acceptedEngineCount = artifact.observations.count { $0.contract.status != .rejected }
        ambiguousEngineCount = artifact.observations.count { $0.contract.forest?.isAmbiguous == true }
        maximumDerivationCount = artifact.observations.map(\.treeFingerprints.count).max() ?? 0
        maximumForestNodeCount = artifact.observations.compactMap { $0.contract.forest?.nodes.count }.max() ?? 0
        replayEventCount = artifact.observations.reduce(0) { $0 + $1.contract.replay.count }
        semanticEvaluatedEngineCount = artifact.semanticReport?.observations.count {
            $0.status == .evaluated || $0.status == .partiallyEvaluated
        } ?? 0
        semanticAgreement = artifact.semanticReport?.agreement
        semanticAmbiguity = artifact.semanticReport?.ambiguity
    }
}

/// Stable headless projection used by scripts and non-native clients.
public struct GrammarREPLExperimentExplorerReport: Hashable, Codable, Sendable {
    public let schemaVersion: Int
    public let producer: String
    public let producerVersion: String
    public let fingerprint: String
    public let fingerprintStatus: String
    public let input: String
    public let agreement: GrammarREPLExperimentArtifact.Agreement
    public let summary: GrammarREPLExperimentSummary
    public let engines: [Engine]

    public struct Engine: Hashable, Codable, Sendable {
        public let parser: String
        public let availability: GrammarREPLExperimentArtifact.Availability
        public let status: GrammarREPLExperimentArtifact.Status
        public let derivations: Int
        public let forestNodes: Int
        public let forestEdges: Int
        public let ambiguous: Bool
        public let replayEvents: Int
        public let diagnostics: Int
        public let semanticStatus: GrammarREPLExperimentArtifact.SemanticStatus?
        public let semanticValues: [String]
        public let semanticAmbiguity: GrammarREPLExperimentArtifact.SemanticAmbiguity?
        public let semanticDerivations: Int
    }

    public init(_ artifact: GrammarREPLExperimentArtifact) {
        schemaVersion = artifact.schemaVersion
        producer = artifact.producer.name
        producerVersion = artifact.producer.version
        fingerprint = artifact.fingerprint
        fingerprintStatus = "recorded-requires-grammar-repl-verification"
        input = artifact.input
        agreement = artifact.agreement
        summary = artifact.summary
        engines = artifact.observations.map {
            Engine(
                parser: $0.parser, availability: $0.availability,
                status: $0.contract.status,
                derivations: $0.treeFingerprints.count,
                forestNodes: $0.contract.forest?.nodes.count ?? 0,
                forestEdges: $0.contract.forest?.edges.count ?? 0,
                ambiguous: $0.contract.forest?.isAmbiguous ?? false,
                replayEvents: $0.contract.replay.count,
                diagnostics: $0.contract.diagnostics.count,
                semanticStatus: artifact.semanticObservation(for: $0.parser)?.status,
                semanticValues: artifact.semanticObservation(for: $0.parser)?.values.map(\.displayValue) ?? [],
                semanticAmbiguity: artifact.semanticObservation(for: $0.parser)?.ambiguity,
                semanticDerivations: artifact.semanticObservation(for: $0.parser)?.derivations?.count ?? 0
            )
        }
    }
}

public struct GrammarREPLExperimentEngineDelta: Hashable, Codable, Sendable {
    public let baseline: String
    public let candidate: String
    public let differences: [Difference]

    public enum Difference: String, Hashable, Codable, Sendable {
        case availability
        case status
        case ambiguity
        case derivationCount
        case forestShape
        case replayLength
        case diagnostics
    }

    public var agrees: Bool { differences.isEmpty }

    public init(
        baseline: GrammarREPLExperimentArtifact.Observation,
        candidate: GrammarREPLExperimentArtifact.Observation
    ) {
        self.baseline = baseline.parser
        self.candidate = candidate.parser
        var result: [Difference] = []
        if baseline.availability != candidate.availability { result.append(.availability) }
        if baseline.contract.status != candidate.contract.status { result.append(.status) }
        if baseline.contract.forest?.isAmbiguous != candidate.contract.forest?.isAmbiguous { result.append(.ambiguity) }
        if baseline.treeFingerprints.count != candidate.treeFingerprints.count { result.append(.derivationCount) }
        let baselineShape = baseline.contract.forest.map { Pair(first: $0.nodes.count, second: $0.edges.count) }
        let candidateShape = candidate.contract.forest.map { Pair(first: $0.nodes.count, second: $0.edges.count) }
        if baselineShape != candidateShape { result.append(.forestShape) }
        if baseline.contract.replay.count != candidate.contract.replay.count { result.append(.replayLength) }
        if baseline.contract.diagnostics.map(\.message) != candidate.contract.diagnostics.map(\.message) { result.append(.diagnostics) }
        differences = result
    }

    private struct Pair: Equatable {
        let first: Int
        let second: Int
    }
}

public struct GrammarREPLExperimentForestProjection: Hashable, Codable, Sendable {
    public let graph: GrammarGraph
    public let hiddenNodeCount: Int
    public let collapsedNodeIDs: [String]

    public static func project(
        _ forest: GrammarREPLExperimentArtifact.Forest,
        parser: String,
        collapsedNodeIDs: Set<String> = [],
        maximumVisibleNodes: Int = 500
    ) -> Self {
        let limit = min(2_000, max(1, maximumVisibleNodes))
        let outgoing = Dictionary(grouping: forest.edges, by: \.parent)
        var visible = Set<String>(), hidden = Set<String>(), queue = forest.roots
        while let node = queue.first, visible.count < limit {
            queue.removeFirst()
            guard visible.insert(node).inserted else { continue }
            let children = outgoing[node, default: []].map(\.child)
            if collapsedNodeIDs.contains(node) {
                var descendants = children
                while let child = descendants.popLast() {
                    guard hidden.insert(child).inserted else { continue }
                    descendants += outgoing[child, default: []].map(\.child)
                }
            } else { queue += children }
        }
        // Retain malformed-but-disconnected nodes in validation, but do not present them as roots.
        let nodes = forest.nodes.filter { visible.contains($0.id) }.map { node in
            let label = node.label ?? node.productionID ?? node.kind.rawValue
            let detail = collapsedNodeIDs.contains(node.id)
                ? "Collapsed · \(hidden.count) hidden"
                : "[\(node.leftExtent), \(node.rightExtent))" + (node.position.map { " · position \($0)" } ?? "")
            return GrammarGraphNode(
                id: node.id, label: label, detail: detail,
                kind: node.kind == .packed ? .packed : .forest,
                width: max(112, Double(max(label.count, detail.count) * 7 + 24)), height: 58,
                metadata: [
                    "parser": parser, "kind": node.kind.rawValue,
                    "ambiguous": String(forest.ambiguityNodes.contains(node.id)),
                    "collapsed": String(collapsedNodeIDs.contains(node.id)),
                ]
            )
        }
        let visibleIDs = Set(nodes.map(\.id))
        let edges: [GrammarGraphEdge] = forest.edges.enumerated().compactMap { index, edge in
            guard visibleIDs.contains(edge.parent), visibleIDs.contains(edge.child) else { return nil }
            return GrammarGraphEdge(
                id: "experiment:\(parser):\(index)", source: edge.parent, target: edge.child
            )
        }
        return .init(
            graph: .init(id: "experiment-\(parser)", title: "\(parser) parse forest", nodes: nodes, edges: edges),
            hiddenNodeCount: forest.nodes.count - nodes.count,
            collapsedNodeIDs: collapsedNodeIDs.sorted()
        )
    }
}

public struct GrammarREPLExperimentPlaybackState: Hashable, Codable, Sendable {
    public private(set) var step: Int
    public private(set) var collapsedNodeIDs: Set<String>

    public init(step: Int = 0, collapsedNodeIDs: Set<String> = []) {
        self.step = max(0, step)
        self.collapsedNodeIDs = collapsedNodeIDs
    }

    public mutating func seek(to value: Int, eventCount: Int) {
        step = min(max(0, eventCount - 1), max(0, value))
    }

    public mutating func stepForward(eventCount: Int) { seek(to: step + 1, eventCount: eventCount) }
    public mutating func stepBackward(eventCount: Int) { seek(to: step - 1, eventCount: eventCount) }
    public mutating func toggleCollapsed(_ nodeID: String) {
        if !collapsedNodeIDs.insert(nodeID).inserted { collapsedNodeIDs.remove(nodeID) }
    }
}

public enum GrammarREPLExperimentExplorerError: Error, Equatable, LocalizedError {
    case malformed(String)
    case artifactTooLarge
    case missingGrammar
    case unsupportedSchema(Int)
    case invalidProducer
    case invalidFingerprint
    case invalidEngines
    case invalidSettings
    case invalidObservation(String)
    case invalidReplay(String)
    case invalidForest(String)
    case invalidSemanticEvidence

    public var errorDescription: String? {
        switch self {
        case .malformed(let detail): "Malformed Grammar-REPL experiment: \(detail)"
        case .artifactTooLarge: "The Grammar-REPL experiment exceeds the 64 MiB import limit."
        case .missingGrammar: "The experiment does not contain its required self-contained grammar."
        case .unsupportedSchema(let version): "Grammar-REPL experiment schema \(version) is not supported."
        case .invalidProducer: "The experiment does not identify a compatible Grammar-REPL producer."
        case .invalidFingerprint: "The experiment fingerprint declaration is invalid. Verify it with Grammar-REPL."
        case .invalidEngines: "The experiment engine catalog or observation order is invalid."
        case .invalidSettings: "The experiment parser settings are invalid."
        case .invalidObservation(let parser): "The \(parser) observation is invalid."
        case .invalidReplay(let parser): "The \(parser) replay is incomplete or out of order."
        case .invalidForest(let parser): "The \(parser) forest contains invalid references or extents."
        case .invalidSemanticEvidence: "The Compiler semantic evidence is inconsistent with the experiment."
        }
    }
}

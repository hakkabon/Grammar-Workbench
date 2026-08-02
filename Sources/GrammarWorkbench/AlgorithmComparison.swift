import Foundation

public struct GrammarAlgorithmMetrics: Identifiable, Hashable, Codable, Sendable {
    public let algorithm: GrammarAlgorithm
    public let states: Int
    public let transitions: Int
    public let tableEntries: Int
    public let unresolvedConflicts: Int
    public let resolvedDecisions: Int
    public let expectedConflicts: Int
    public var id: GrammarAlgorithm { algorithm }
}

public struct GrammarStateCorrespondence: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let coreItems: [String]
    public let slrStates: [Int]
    public let lalrStates: [Int]
    public let canonicalStates: [Int]
    public var isCanonicalMerge: Bool { canonicalStates.count > 1 && lalrStates.count == 1 }

    public func states(for algorithm: GrammarAlgorithm) -> [Int] {
        switch algorithm {
        case .slr: slrStates
        case .lalr: lalrStates
        case .canonical: canonicalStates
        }
    }
}

public struct GrammarComparedCell: Identifiable, Hashable, Codable, Sendable {
    public let state: Int
    public let actions: [GrammarActionSnapshot]
    public var id: Int { state }
    public var isConflict: Bool { actions.count > 1 }
}

public enum GrammarTableDifferenceKind: String, Codable, Sendable {
    case actions
    case conflict
    case availability
}

public struct GrammarTableDifference: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let correspondenceID: String
    public let symbol: String
    public let kind: GrammarTableDifferenceKind
    public let slr: [GrammarComparedCell]
    public let lalr: [GrammarComparedCell]
    public let canonical: [GrammarComparedCell]

    public func cells(for algorithm: GrammarAlgorithm) -> [GrammarComparedCell] {
        switch algorithm {
        case .slr: slr
        case .lalr: lalr
        case .canonical: canonical
        }
    }
}

public struct GrammarAlgorithmComparison: Hashable, Codable, Sendable {
    public let apiVersion: Int
    public let algorithmMetrics: [GrammarAlgorithmMetrics]
    public let stateCorrespondences: [GrammarStateCorrespondence]
    public let tableDifferences: [GrammarTableDifference]
    public let recommendedAlgorithm: GrammarAlgorithm
    public let recommendation: String

    public func metric(for algorithm: GrammarAlgorithm) -> GrammarAlgorithmMetrics? {
        algorithmMetrics.first { $0.algorithm == algorithm }
    }
}

enum AlgorithmComparisonEngine {
    static func compare(
        grammar: ParsedGrammar,
        analysis: GrammarAnalysis,
        source: String,
        reusing artifact: GrammarArtifact? = nil
    ) -> GrammarAlgorithmComparison {
        var artifacts: [LRAlgorithm: GrammarArtifact] = [:]
        if let artifact { artifacts[artifact.algorithm] = artifact }
        for algorithm in LRAlgorithm.allCases where artifacts[algorithm] == nil {
            artifacts[algorithm] = LRConstructionEngine.construct(
                grammar: grammar, analysis: analysis, source: source, algorithm: algorithm
            )
        }

        let metrics = LRAlgorithm.allCases.compactMap { algorithm -> GrammarAlgorithmMetrics? in
            guard let artifact = artifacts[algorithm] else { return nil }
            return .init(
                algorithm: GrammarAlgorithm(rawValue: algorithm.rawValue)!,
                states: artifact.states.count, transitions: artifact.transitions.count,
                tableEntries: artifact.cells.count,
                unresolvedConflicts: artifact.decisions.count { $0.disposition == .unresolved },
                resolvedDecisions: artifact.decisions.count { $0.disposition == .resolved },
                expectedConflicts: artifact.decisions.count { $0.disposition == .expected }
            )
        }

        var statesByCore: [String: [LRAlgorithm: [AutomatonState]]] = [:]
        var coreItemsByID: [String: [String]] = [:]
        for (algorithm, artifact) in artifacts {
            for state in artifact.states {
                let items = coreItems(state, stripsLookahead: algorithm != .slr)
                let id = stableID(items.joined(separator: "\u{1f}"))
                statesByCore[id, default: [:]][algorithm, default: []].append(state)
                coreItemsByID[id] = items
            }
        }
        let correspondences = statesByCore.keys.sorted().map { id in
            let groups = statesByCore[id, default: [:]]
            return GrammarStateCorrespondence(
                id: id, coreItems: coreItemsByID[id] ?? [],
                slrStates: groups[.slr, default: []].map { $0.id.rawValue }.sorted(),
                lalrStates: groups[.lalr, default: []].map { $0.id.rawValue }.sorted(),
                canonicalStates: groups[.canonical, default: []].map { $0.id.rawValue }.sorted()
            )
        }

        let symbols = (grammar.terminals + ["$"] + grammar.nonterminals).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        var differences: [GrammarTableDifference] = []
        for correspondence in correspondences {
            for symbol in symbols {
                let slr = cells(correspondence.slrStates, symbol: symbol, artifact: artifacts[.slr]!)
                let lalr = cells(correspondence.lalrStates, symbol: symbol, artifact: artifacts[.lalr]!)
                let canonical = cells(correspondence.canonicalStates, symbol: symbol, artifact: artifacts[.canonical]!)
                let normalized = [
                    normalizedActions(slr, artifact: artifacts[.slr]!, statesByCore: statesByCore),
                    normalizedActions(lalr, artifact: artifacts[.lalr]!, statesByCore: statesByCore),
                    normalizedActions(canonical, artifact: artifacts[.canonical]!, statesByCore: statesByCore)
                ]
                guard Set(normalized).count > 1 else { continue }
                let presence = [!slr.isEmpty, !lalr.isEmpty, !canonical.isEmpty]
                let conflicts = [slr.contains(where: \.isConflict), lalr.contains(where: \.isConflict), canonical.contains(where: \.isConflict)]
                let kind: GrammarTableDifferenceKind = Set(presence).count > 1
                    ? .availability : (Set(conflicts).count > 1 ? .conflict : .actions)
                differences.append(.init(
                    id: "\(correspondence.id):\(symbol)", correspondenceID: correspondence.id,
                    symbol: symbol, kind: kind, slr: slr, lalr: lalr, canonical: canonical
                ))
            }
        }

        let recommendation = recommendation(metrics)
        return .init(
            apiVersion: GrammarWorkbenchAPIVersion.current,
            algorithmMetrics: metrics, stateCorrespondences: correspondences,
            tableDifferences: differences,
            recommendedAlgorithm: recommendation.algorithm,
            recommendation: recommendation.text
        )
    }

    private static func cells(_ states: [Int], symbol: String, artifact: GrammarArtifact) -> [GrammarComparedCell] {
        states.compactMap { state in
            guard let cell = artifact.cell(.init(state: .init(rawValue: state), symbol: symbol)) else { return nil }
            return .init(state: state, actions: cell.actions.map(GrammarActionSnapshot.init))
        }
    }

    private static func normalizedActions(
        _ cells: [GrammarComparedCell], artifact: GrammarArtifact,
        statesByCore: [String: [LRAlgorithm: [AutomatonState]]]
    ) -> String {
        let stateCore = Dictionary(uniqueKeysWithValues: artifact.states.map {
            ($0.id.rawValue, stableID(coreItems($0, stripsLookahead: artifact.algorithm != .slr).joined(separator: "\u{1f}")))
        })
        return cells.map { cell in
            cell.actions.map { action in
                switch action.kind {
                case .shift: "shift:\(action.targetState.flatMap { stateCore[$0] } ?? "?")"
                case .goTo: "goto:\(action.targetState.flatMap { stateCore[$0] } ?? "?")"
                case .reduce: "reduce:\(action.production.map(String.init) ?? "?")"
                case .accept: "accept"
                }
            }.sorted().joined(separator: "|")
        }.sorted().joined(separator: "||")
    }

    private static func coreItems(_ state: AutomatonState, stripsLookahead: Bool) -> [String] {
        Array(Set(state.items.map { item in
            guard stripsLookahead else { return item.text }
            guard let delimiter = item.text.range(of: ", ", options: .backwards) else { return item.text }
            return String(item.text[..<delimiter.lowerBound])
        })).sorted()
    }

    private static func stableID(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }

    private static func recommendation(_ metrics: [GrammarAlgorithmMetrics]) -> (algorithm: GrammarAlgorithm, text: String) {
        let slr = metrics.first { $0.algorithm == .slr }!
        let lalr = metrics.first { $0.algorithm == .lalr }!
        let canonical = metrics.first { $0.algorithm == .canonical }!
        if slr.unresolvedConflicts == 0 {
            return (.slr, "SLR(1) has no unresolved conflicts and uses the simplest construction.")
        }
        if lalr.unresolvedConflicts == 0 {
            return (.lalr, "LALR(1) removes the SLR(1) conflicts without canonical LR(1)'s additional states.")
        }
        if canonical.unresolvedConflicts < lalr.unresolvedConflicts {
            return (.canonical, "Canonical LR(1) has fewer unresolved conflicts than the merged LALR(1) machine.")
        }
        return (.lalr, "LALR(1) offers the smallest LR(1) state space with the same unresolved-conflict count as canonical LR(1).")
    }
}

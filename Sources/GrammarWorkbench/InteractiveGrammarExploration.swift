import Foundation

public struct GrammarExplorationProduction: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let text: String
    public let range: SourceRange
}

public struct GrammarRuleExploration: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let productions: [GrammarExplorationProduction]
    public let incomingRules: [String]
    public let outgoingRules: [String]
    public let first: [String]
    public let follow: [String]
    public let recursiveComponent: [String]
    public let isStart: Bool
    public let isReachable: Bool
    public let isProductive: Bool
    public let isNullable: Bool
    public let isDirectlyLeftRecursive: Bool

    public var sourceRange: SourceRange? { productions.first?.range }
    public var isRecursive: Bool {
        isDirectlyLeftRecursive || recursiveComponent.count > 1 || outgoingRules.contains(id)
    }
}

public struct GrammarExplorationSnapshot: Hashable, Codable, Sendable {
    public let startRule: String
    public let selectedRule: String
    public let pathFromStart: [String]
    public let rules: [GrammarRuleExploration]

    public var selected: GrammarRuleExploration? { rules.first { $0.id == selectedRule } }
}

/// Builds small immutable rule-centred projections over the existing structural
/// analysis. The service owns no UI state and performs no parser construction.
public enum GrammarInteractiveExplorer {
    public static func snapshot(
        _ compilation: GrammarCompilation, selectedRule requestedRule: String? = nil
    ) throws -> GrammarExplorationSnapshot {
        guard let grammar = compilation.parsedGrammar else {
            throw GrammarTransformationError.compilationFailed(
                compilation.diagnostics.first(where: { $0.severity == .error })?.message
                    ?? "The grammar did not compile."
            )
        }
        let structural = try GrammarEngineering.analyze(compilation)
        let declared = Set(grammar.productions.map(\.lhs))
        let orderedRules = grammar.nonterminals.filter(declared.contains)
            + declared.subtracting(grammar.nonterminals).sorted()
        let edges = structural.dependencyEdges
        let reachable = Set(structural.reachableNonterminals)
        let productive = Set(structural.productiveNonterminals)
        let nullable = Set(structural.nullableNonterminals)
        let directLeft = Set(structural.directlyLeftRecursiveNonterminals)
        let components = structural.stronglyConnectedComponents

        let rules = orderedRules.map { rule in
            GrammarRuleExploration(
                id: rule,
                productions: grammar.productions.filter { $0.lhs == rule }.map {
                    .init(id: $0.id, text: $0.text, range: $0.range)
                },
                incomingRules: Array(Set(edges.filter { $0.to == rule }.map(\.from))).sorted(),
                outgoingRules: Array(Set(edges.filter { $0.from == rule }.map(\.to))).sorted(),
                first: structural.first[rule] ?? [],
                follow: structural.follow[rule] ?? [],
                recursiveComponent: components.first(where: { $0.contains(rule) })?.sorted() ?? [rule],
                isStart: rule == grammar.startSymbol,
                isReachable: reachable.contains(rule),
                isProductive: productive.contains(rule),
                isNullable: nullable.contains(rule),
                isDirectlyLeftRecursive: directLeft.contains(rule)
            )
        }
        let selected = requestedRule.flatMap { declared.contains($0) ? $0 : nil }
            ?? grammar.startSymbol
        return .init(
            startRule: grammar.startSymbol, selectedRule: selected,
            pathFromStart: shortestPath(from: grammar.startSymbol, to: selected, edges: edges),
            rules: rules
        )
    }

    public static func matchingRules(
        in snapshot: GrammarExplorationSnapshot, query: String
    ) -> [GrammarRuleExploration] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return snapshot.rules }
        return snapshot.rules.filter { rule in
            rule.id.localizedCaseInsensitiveContains(term)
                || rule.productions.contains { $0.text.localizedCaseInsensitiveContains(term) }
                || rule.first.contains { $0.localizedCaseInsensitiveContains(term) }
                || rule.follow.contains { $0.localizedCaseInsensitiveContains(term) }
        }
    }

    private static func shortestPath(
        from start: String, to target: String, edges: [GrammarDependencyEdge]
    ) -> [String] {
        if start == target { return [start] }
        let adjacency = Dictionary(grouping: edges, by: \.from)
            .mapValues { Array(Set($0.map(\.to))).sorted() }
        var queue: [[String]] = [[start]]
        var visited: Set<String> = [start]
        while !queue.isEmpty {
            let path = queue.removeFirst()
            guard let current = path.last else { continue }
            for next in adjacency[current] ?? [] where visited.insert(next).inserted {
                let candidate = path + [next]
                if next == target { return candidate }
                queue.append(candidate)
            }
        }
        return []
    }
}

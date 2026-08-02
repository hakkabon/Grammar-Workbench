import Foundation

public enum GrammarGeneralizedParseStatus: String, Hashable, Codable, Sendable {
    case accepted
    case ambiguous
    case rejected
    case truncated
    case invalidGrammar
    case lexicalError
}

public struct GrammarGeneralizedParseOptions: Hashable, Codable, Sendable {
    public var maximumConfigurations: Int
    public var maximumSteps: Int
    public var maximumTrees: Int
    /// Also explores candidates suppressed by precedence or associativity.
    public var exploresResolvedConflicts: Bool

    public init(
        maximumConfigurations: Int = 4_096,
        maximumSteps: Int = 100_000,
        maximumTrees: Int = 32,
        exploresResolvedConflicts: Bool = false
    ) {
        self.maximumConfigurations = max(1, maximumConfigurations)
        self.maximumSteps = max(1, maximumSteps)
        self.maximumTrees = max(1, maximumTrees)
        self.exploresResolvedConflicts = exploresResolvedConflicts
    }
}

public struct GrammarGeneralizedParseMetrics: Hashable, Codable, Sendable {
    public let exploredConfigurations: Int
    public let peakPendingConfigurations: Int
    public let branchPoints: Int
    public let duplicateConfigurations: Int
    public let discardedConfigurations: Int
}

/// Experimental ambiguity-preserving result. Alternatives are concrete syntax
/// trees in deterministic discovery order, capped by the supplied research limits.
public struct GrammarGeneralizedParseResult: Hashable, Codable, Sendable {
    public let status: GrammarGeneralizedParseStatus
    public let tokens: [GrammarInputTokenSnapshot]
    public let alternatives: [GrammarSyntaxNode]
    public let diagnostics: [GrammarInputDiagnostic]
    public let metrics: GrammarGeneralizedParseMetrics
    public let wasTruncated: Bool

    public var isAccepted: Bool { !alternatives.isEmpty }
    public var isAmbiguous: Bool { alternatives.count > 1 }
}

enum GeneralizedLRParser {
    private struct Configuration: Hashable {
        var states: [StateID]
        var nodes: [ParseTreeNode]
        var cursor: Int
    }

    struct Result {
        let trees: [ParseTreeNode]
        let metrics: GrammarGeneralizedParseMetrics
        let truncated: Bool
    }

    static func parse(
        _ tokens: [String],
        artifact: GrammarArtifact,
        options: GrammarGeneralizedParseOptions
    ) -> Result {
        let input = tokens + ["$"]
        var pending = [Configuration(states: [.init(rawValue: 0)], nodes: [], cursor: 0)]
        var seen = Set(pending)
        var accepted: [ParseTreeNode] = []
        var acceptedSet: Set<ParseTreeNode> = []
        var explored = 0
        var peak = 1
        var branchPoints = 0
        var duplicates = 0
        var discarded = 0
        var truncated = false

        while let configuration = pending.popLast() {
            guard explored < options.maximumSteps else { truncated = true; break }
            explored += 1
            guard configuration.cursor < input.count,
                  let state = configuration.states.last else { discarded += 1; continue }
            let cellID = CellID(state: state, symbol: input[configuration.cursor])
            guard let cell = artifact.cell(cellID) else { discarded += 1; continue }
            var actions = cell.actions
            if options.exploresResolvedConflicts,
               let decision = artifact.decision(at: cellID) {
                let candidates = artifact.candidateActions(for: decision)
                if !candidates.isEmpty { actions = candidates }
            }
            actions = actions.filter { action in
                if case .goTo = action { return false }
                return true
            }
            if actions.count > 1 { branchPoints += 1 }

            // Reverse traversal keeps the artifact's first candidate first in DFS discovery order.
            for action in actions.reversed() {
                switch action {
                case .shift(let target):
                    guard input[configuration.cursor] != "$" else { discarded += 1; continue }
                    var next = configuration
                    next.states.append(target)
                    next.nodes.append(.init(symbol: input[configuration.cursor], children: []))
                    next.cursor += 1
                    enqueue(next)
                case .reduce(let productionID):
                    guard let production = artifact.productions.first(where: { $0.id == productionID }),
                          production.rhs.count < configuration.states.count,
                          production.rhs.count <= configuration.nodes.count else {
                        discarded += 1; continue
                    }
                    var next = configuration
                    let count = production.rhs.count
                    let children = count == 0 ? [] : Array(next.nodes.suffix(count))
                    if count > 0 {
                        next.states.removeLast(count)
                        next.nodes.removeLast(count)
                    }
                    guard let from = next.states.last,
                          let gotoCell = artifact.cell(.init(state: from, symbol: production.lhs)),
                          case .goTo(let target)? = gotoCell.actions.first else {
                        discarded += 1; continue
                    }
                    next.states.append(target)
                    next.nodes.append(.init(
                        symbol: production.lhs, children: children, production: productionID
                    ))
                    enqueue(next)
                case .accept:
                    if let tree = configuration.nodes.last,
                       acceptedSet.insert(tree).inserted {
                        if accepted.count < options.maximumTrees {
                            accepted.append(tree)
                        } else {
                            truncated = true
                        }
                    }
                case .goTo: break
                }
                if truncated { break }
            }
            if truncated { break }
        }

        return .init(
            trees: accepted,
            metrics: .init(
                exploredConfigurations: explored,
                peakPendingConfigurations: peak,
                branchPoints: branchPoints,
                duplicateConfigurations: duplicates,
                discardedConfigurations: discarded
            ),
            truncated: truncated
        )

        func enqueue(_ configuration: Configuration) {
            guard !seen.contains(configuration) else { duplicates += 1; return }
            guard seen.count < options.maximumConfigurations else {
                discarded += 1; truncated = true; return
            }
            seen.insert(configuration)
            pending.append(configuration)
            peak = max(peak, pending.count)
        }
    }
}

public extension GrammarCompilation {
    /// Runs bounded generalized LR exploration without changing the deterministic parser.
    func parseGeneralized(
        _ input: String,
        options: GrammarGeneralizedParseOptions = .init()
    ) -> GrammarGeneralizedParseResult {
        let emptyMetrics = GrammarGeneralizedParseMetrics(
            exploredConfigurations: 0, peakPendingConfigurations: 0,
            branchPoints: 0, duplicateConfigurations: 0, discardedConfigurations: 0
        )
        guard let compiledArtifact else {
            return .init(status: .invalidGrammar, tokens: [], alternatives: [], diagnostics: [],
                         metrics: emptyMetrics, wasTruncated: false)
        }
        let lexed = lex(input)
        guard !lexed.hasErrors else {
            return .init(status: .lexicalError, tokens: lexed.tokens, alternatives: [],
                         diagnostics: lexed.diagnostics, metrics: emptyMetrics, wasTruncated: false)
        }
        let result = GeneralizedLRParser.parse(
            lexed.tokens.map(\.kind), artifact: compiledArtifact, options: options
        )
        let alternatives = result.trees.map { GrammarSyntaxNode.make(from: $0, tokens: lexed.tokens) }
        let status: GrammarGeneralizedParseStatus
        if result.truncated { status = .truncated }
        else if alternatives.count > 1 { status = .ambiguous }
        else if alternatives.count == 1 { status = .accepted }
        else { status = .rejected }
        return .init(
            status: status, tokens: lexed.tokens, alternatives: alternatives, diagnostics: [],
            metrics: result.metrics, wasTruncated: result.truncated
        )
    }
}

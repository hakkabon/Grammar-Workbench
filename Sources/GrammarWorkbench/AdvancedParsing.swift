import Foundation

public enum GrammarGeneralizedParseStatus: String, Hashable, Codable, Sendable {
    case accepted
    case ambiguous
    case rejected
    case truncated
    case invalidGrammar
    case lexicalError
    case cancelled
}

public enum GrammarGeneralizedSearchStrategy: String, Hashable, Codable, Sendable {
    case depthFirst
    case breadthFirst
}

public enum GrammarGeneralizedLimit: String, Hashable, Codable, Sendable, CaseIterable {
    case configurations
    case steps
    case trees
}

public struct GrammarGeneralizedParseOptions: Hashable, Codable, Sendable {
    public var maximumConfigurations: Int
    public var maximumSteps: Int
    public var maximumTrees: Int
    /// Also explores candidates suppressed by precedence or associativity.
    public var exploresResolvedConflicts: Bool
    /// Breadth-first is useful when callers want shallow derivations first;
    /// depth-first retains the historical discovery order and lower peak memory.
    public var searchStrategy: GrammarGeneralizedSearchStrategy

    public init(
        maximumConfigurations: Int = 4_096,
        maximumSteps: Int = 100_000,
        maximumTrees: Int = 32,
        exploresResolvedConflicts: Bool = false,
        searchStrategy: GrammarGeneralizedSearchStrategy = .depthFirst
    ) {
        self.maximumConfigurations = max(1, maximumConfigurations)
        self.maximumSteps = max(1, maximumSteps)
        self.maximumTrees = max(1, maximumTrees)
        self.exploresResolvedConflicts = exploresResolvedConflicts
        self.searchStrategy = searchStrategy
    }

    private enum CodingKeys: String, CodingKey {
        case maximumConfigurations, maximumSteps, maximumTrees
        case exploresResolvedConflicts, searchStrategy
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maximumConfigurations: try values.decodeIfPresent(Int.self, forKey: .maximumConfigurations) ?? 4_096,
            maximumSteps: try values.decodeIfPresent(Int.self, forKey: .maximumSteps) ?? 100_000,
            maximumTrees: try values.decodeIfPresent(Int.self, forKey: .maximumTrees) ?? 32,
            exploresResolvedConflicts: try values.decodeIfPresent(Bool.self, forKey: .exploresResolvedConflicts) ?? false,
            searchStrategy: try values.decodeIfPresent(GrammarGeneralizedSearchStrategy.self, forKey: .searchStrategy) ?? .depthFirst
        )
    }
}

public struct GrammarGeneralizedParseMetrics: Hashable, Codable, Sendable {
    public let exploredConfigurations: Int
    public let peakPendingConfigurations: Int
    public let branchPoints: Int
    public let duplicateConfigurations: Int
    public let discardedConfigurations: Int
    public let shiftActions: Int
    public let reductionActions: Int
    public let acceptActions: Int
    public let furthestTokenIndex: Int

    public init(
        exploredConfigurations: Int,
        peakPendingConfigurations: Int,
        branchPoints: Int,
        duplicateConfigurations: Int,
        discardedConfigurations: Int,
        shiftActions: Int = 0,
        reductionActions: Int = 0,
        acceptActions: Int = 0,
        furthestTokenIndex: Int = 0
    ) {
        self.exploredConfigurations = exploredConfigurations
        self.peakPendingConfigurations = peakPendingConfigurations
        self.branchPoints = branchPoints
        self.duplicateConfigurations = duplicateConfigurations
        self.discardedConfigurations = discardedConfigurations
        self.shiftActions = shiftActions
        self.reductionActions = reductionActions
        self.acceptActions = acceptActions
        self.furthestTokenIndex = furthestTokenIndex
    }
}

public struct GrammarGeneralizedAlternative: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let tree: GrammarSyntaxNode

    public init(tree: GrammarSyntaxNode) {
        self.tree = tree
        self.id = Self.stableID(for: tree)
    }

    private static func stableID(for tree: GrammarSyntaxNode) -> String {
        // FNV-1a is deliberately used instead of Swift's randomized Hasher so
        // an alternative keeps the same identity across processes and exports.
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in tree.rendered().utf8 {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return String(value, radix: 16)
    }
}

public struct GrammarGeneralizedParseForest: Hashable, Codable, Sendable {
    public let alternatives: [GrammarGeneralizedAlternative]

    public init(trees: [GrammarSyntaxNode]) {
        alternatives = trees.map(GrammarGeneralizedAlternative.init)
    }

    public var isAmbiguous: Bool { alternatives.count > 1 }
    public func alternative(id: String) -> GrammarGeneralizedAlternative? {
        alternatives.first { $0.id == id }
    }
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
    /// Deterministically ordered for reproducible Codable output.
    public let reachedLimits: [GrammarGeneralizedLimit]
    public let syntaxDiagnostics: [GrammarSyntaxDiagnostic]
    public let forest: GrammarGeneralizedParseForest

    public var isAccepted: Bool { !alternatives.isEmpty }
    public var isAmbiguous: Bool { alternatives.count > 1 }
    public var wasCancelled: Bool { status == .cancelled }

    public func alternative(id: String) -> GrammarGeneralizedAlternative? {
        forest.alternative(id: id)
    }
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
        let reachedLimits: Set<GrammarGeneralizedLimit>
        let cancelled: Bool
        let furthestCursor: Int
        let expectedTerminals: [String]
        let statesAtFurthestCursor: [StateID]
    }

    static func parse(
        _ tokens: [String],
        artifact: GrammarArtifact,
        options: GrammarGeneralizedParseOptions
    ) -> Result {
        let input = tokens + ["$"]
        var pending = [Configuration(states: [.init(rawValue: 0)], nodes: [], cursor: 0)]
        var pendingHead = 0
        var seen = Set(pending)
        var accepted: [ParseTreeNode] = []
        var acceptedSet: Set<ParseTreeNode> = []
        var explored = 0
        var peak = 1
        var branchPoints = 0
        var duplicates = 0
        var discarded = 0
        var reachedLimits: Set<GrammarGeneralizedLimit> = []
        var cancelled = false
        var furthestCursor = 0
        var expected = Set<String>()
        var statesAtFurthest = Set<StateID>()
        var shifts = 0
        var reductions = 0
        var accepts = 0

        while options.searchStrategy == .depthFirst ? !pending.isEmpty : pendingHead < pending.count {
            if Task.isCancelled { cancelled = true; break }
            let configuration: Configuration
            if options.searchStrategy == .depthFirst {
                configuration = pending.removeLast()
            } else {
                configuration = pending[pendingHead]
                pendingHead += 1
            }
            guard explored < options.maximumSteps else {
                reachedLimits.insert(.steps)
                break
            }
            explored += 1
            guard configuration.cursor < input.count,
                  let state = configuration.states.last else { discarded += 1; continue }
            if configuration.cursor > furthestCursor {
                furthestCursor = configuration.cursor
                expected.removeAll()
                statesAtFurthest.removeAll()
            }
            if configuration.cursor == furthestCursor {
                statesAtFurthest.insert(state)
                expected.formUnion(expectedTerminals(in: state, artifact: artifact))
            }
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
                    shifts += 1
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
                    reductions += 1
                    enqueue(next)
                case .accept:
                    accepts += 1
                    if let tree = configuration.nodes.last,
                       acceptedSet.insert(tree).inserted {
                        if accepted.count < options.maximumTrees {
                            accepted.append(tree)
                        } else {
                            reachedLimits.insert(.trees)
                        }
                    }
                case .goTo: break
                }
                if reachedLimits.contains(.trees) { break }
            }
            if reachedLimits.contains(.trees) { break }
        }

        return .init(
            trees: accepted,
            metrics: .init(
                exploredConfigurations: explored,
                peakPendingConfigurations: peak,
                branchPoints: branchPoints,
                duplicateConfigurations: duplicates,
                discardedConfigurations: discarded,
                shiftActions: shifts,
                reductionActions: reductions,
                acceptActions: accepts,
                furthestTokenIndex: furthestCursor
            ),
            reachedLimits: reachedLimits,
            cancelled: cancelled,
            furthestCursor: furthestCursor,
            expectedTerminals: expected.sorted(),
            statesAtFurthestCursor: statesAtFurthest.sorted { $0.rawValue < $1.rawValue }
        )

        func enqueue(_ configuration: Configuration) {
            guard !seen.contains(configuration) else { duplicates += 1; return }
            guard seen.count < options.maximumConfigurations else {
                discarded += 1
                reachedLimits.insert(.configurations)
                return
            }
            seen.insert(configuration)
            pending.append(configuration)
            let activePending = options.searchStrategy == .depthFirst
                ? pending.count
                : pending.count - pendingHead
            peak = max(peak, activePending)
        }

        func expectedTerminals(in state: StateID, artifact: GrammarArtifact) -> [String] {
            var terminals: [String] = []
            for cell in artifact.cells where cell.id.state == state && cell.id.symbol != "$" {
                let hasParserAction = cell.actions.contains { action in
                    if case .goTo = action { return false }
                    return true
                }
                if hasParserAction { terminals.append(cell.id.symbol) }
            }
            return terminals
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
                         metrics: emptyMetrics, wasTruncated: false, reachedLimits: [],
                         syntaxDiagnostics: [], forest: .init(trees: []))
        }
        let lexed = lex(input)
        guard !lexed.hasErrors else {
            return .init(status: .lexicalError, tokens: lexed.tokens, alternatives: [],
                         diagnostics: lexed.diagnostics, metrics: emptyMetrics, wasTruncated: false,
                         reachedLimits: [], syntaxDiagnostics: [], forest: .init(trees: []))
        }
        let result = GeneralizedLRParser.parse(
            lexed.tokens.map(\.kind), artifact: compiledArtifact, options: options
        )
        let alternatives = result.trees.map { GrammarSyntaxNode.make(from: $0, tokens: lexed.tokens) }
        let status: GrammarGeneralizedParseStatus
        if result.cancelled { status = .cancelled }
        else if !result.reachedLimits.isEmpty { status = .truncated }
        else if alternatives.count > 1 { status = .ambiguous }
        else if alternatives.count == 1 { status = .accepted }
        else { status = .rejected }
        let syntaxDiagnostics: [GrammarSyntaxDiagnostic]
        if alternatives.isEmpty, !result.cancelled, result.reachedLimits.isEmpty {
            let tokenIndex = min(result.furthestCursor, lexed.tokens.count)
            let unexpected = tokenIndex < lexed.tokens.count ? lexed.tokens[tokenIndex].kind : "$"
            syntaxDiagnostics = [.init(
                id: 0,
                message: "Unexpected ‘\(unexpected)’. Expected: \(result.expectedTerminals.joined(separator: ", ")).",
                tokenIndex: tokenIndex,
                range: tokenIndex < lexed.tokens.count ? lexed.tokens[tokenIndex].range : lexed.tokens.last?.range,
                state: result.statesAtFurthestCursor.first?.rawValue ?? 0,
                unexpected: unexpected,
                expected: result.expectedTerminals,
                recovery: nil,
                recoverySymbol: nil,
                recoveryDetail: nil
            )]
        } else {
            syntaxDiagnostics = []
        }
        let forest = GrammarGeneralizedParseForest(trees: alternatives)
        return .init(
            status: status, tokens: lexed.tokens, alternatives: alternatives, diagnostics: [],
            metrics: result.metrics, wasTruncated: !result.reachedLimits.isEmpty,
            reachedLimits: result.reachedLimits.sorted { $0.rawValue < $1.rawValue },
            syntaxDiagnostics: syntaxDiagnostics,
            forest: forest
        )
    }

    /// Cooperative asynchronous entry point for editor, server, and build
    /// integrations. Cancelling the surrounding task stops exploration at the
    /// next configuration boundary and returns a `.cancelled` result.
    func parseGeneralizedCancellable(
        _ input: String,
        options: GrammarGeneralizedParseOptions = .init()
    ) async -> GrammarGeneralizedParseResult {
        await Task.yield()
        return parseGeneralized(input, options: options)
    }
}

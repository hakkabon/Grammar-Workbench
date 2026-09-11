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
    case forestNodes
    case packedFamilies
}

public struct GrammarGeneralizedParseOptions: Hashable, Codable, Sendable {
    public var maximumConfigurations: Int
    public var maximumSteps: Int
    public var maximumTrees: Int
    public var maximumForestNodes: Int
    public var maximumPackedFamilies: Int
    /// Also explores candidates suppressed by precedence or associativity.
    public var exploresResolvedConflicts: Bool
    /// Breadth-first is useful when callers want shallow derivations first;
    /// depth-first retains the historical discovery order and lower peak memory.
    public var searchStrategy: GrammarGeneralizedSearchStrategy

    public init(
        maximumConfigurations: Int = 4_096,
        maximumSteps: Int = 100_000,
        maximumTrees: Int = 32,
        maximumForestNodes: Int = 50_000,
        maximumPackedFamilies: Int = 100_000,
        exploresResolvedConflicts: Bool = false,
        searchStrategy: GrammarGeneralizedSearchStrategy = .depthFirst
    ) {
        self.maximumConfigurations = max(1, maximumConfigurations)
        self.maximumSteps = max(1, maximumSteps)
        self.maximumTrees = max(1, maximumTrees)
        self.maximumForestNodes = max(1, maximumForestNodes)
        self.maximumPackedFamilies = max(1, maximumPackedFamilies)
        self.exploresResolvedConflicts = exploresResolvedConflicts
        self.searchStrategy = searchStrategy
    }

    private enum CodingKeys: String, CodingKey {
        case maximumConfigurations, maximumSteps, maximumTrees, maximumForestNodes, maximumPackedFamilies
        case exploresResolvedConflicts, searchStrategy
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maximumConfigurations: try values.decodeIfPresent(Int.self, forKey: .maximumConfigurations) ?? 4_096,
            maximumSteps: try values.decodeIfPresent(Int.self, forKey: .maximumSteps) ?? 100_000,
            maximumTrees: try values.decodeIfPresent(Int.self, forKey: .maximumTrees) ?? 32,
            maximumForestNodes: try values.decodeIfPresent(Int.self, forKey: .maximumForestNodes) ?? 50_000,
            maximumPackedFamilies: try values.decodeIfPresent(Int.self, forKey: .maximumPackedFamilies) ?? 100_000,
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

public struct GrammarForestSpan: Hashable, Codable, Sendable {
    public let lowerBound: Int
    public let upperBound: Int

    public init(lowerBound: Int, upperBound: Int) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}

/// One derivation of a shared forest node. Equal symbol/span nodes share their
/// identity while distinct reductions are retained as packed families.
public struct GrammarPackedForestFamily: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let production: Int?
    public let children: [String]

    public init(id: String, production: Int?, children: [String]) {
        self.id = id; self.production = production; self.children = children
    }
}

public struct GrammarSharedForestNode: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let symbol: String
    public let span: GrammarForestSpan
    public let families: [GrammarPackedForestFamily]

    public var isPacked: Bool { families.count > 1 }
}

/// A compact shared-packed parse forest (SPPF). Nodes are keyed by symbol and
/// token span; ambiguity is represented by multiple families instead of by
/// duplicating complete subtrees.
public struct GrammarSharedParseForest: Hashable, Codable, Sendable {
    public let roots: [String]
    public let nodes: [GrammarSharedForestNode]

    public init(roots: [String], nodes: [GrammarSharedForestNode]) {
        self.roots = roots
        self.nodes = nodes
    }

    public static let empty = Self(roots: [], nodes: [])
    public var packedFamilyCount: Int { nodes.reduce(0) { $0 + $1.families.count } }
    public var ambiguousNodeCount: Int { nodes.count { $0.isPacked } }
    public var isAmbiguous: Bool { roots.count > 1 || ambiguousNodeCount > 0 }
    public func node(id: String) -> GrammarSharedForestNode? { nodes.first { $0.id == id } }

    /// Counts represented derivations without materializing them. The result
    /// saturates at `limit`, making it safe for highly ambiguous forests.
    public func derivationCount(upTo limit: Int = Int.max) -> Int {
        let ceiling = max(1, limit)
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var memo: [String: Int] = [:]
        var active = Set<String>()
        func count(_ id: String) -> Int {
            if let value = memo[id] { return value }
            guard let node = byID[id], active.insert(id).inserted else { return ceiling }
            var total = 0
            for family in node.families {
                var product = 1
                for child in family.children {
                    product = saturatingMultiply(product, count(child), ceiling: ceiling)
                }
                total = saturatingAdd(total, product, ceiling: ceiling)
            }
            active.remove(id)
            memo[id] = total
            return total
        }
        return roots.reduce(0) { saturatingAdd($0, count($1), ceiling: ceiling) }
    }

    private func saturatingAdd(_ lhs: Int, _ rhs: Int, ceiling: Int) -> Int {
        if lhs >= ceiling || rhs >= ceiling - lhs { return ceiling }
        return lhs + rhs
    }

    private func saturatingMultiply(_ lhs: Int, _ rhs: Int, ceiling: Int) -> Int {
        if lhs == 0 || rhs == 0 { return 0 }
        if lhs >= ceiling || rhs > ceiling / lhs { return ceiling }
        return lhs * rhs
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
    public let sharedForest: GrammarSharedParseForest

    public var isAccepted: Bool { !alternatives.isEmpty }
    public var isAmbiguous: Bool { sharedForest.isAmbiguous || alternatives.count > 1 }
    public var wasCancelled: Bool { status == .cancelled }

    public func alternative(id: String) -> GrammarGeneralizedAlternative? {
        forest.alternative(id: id)
    }

    init(
        status: GrammarGeneralizedParseStatus, tokens: [GrammarInputTokenSnapshot],
        alternatives: [GrammarSyntaxNode], diagnostics: [GrammarInputDiagnostic],
        metrics: GrammarGeneralizedParseMetrics, wasTruncated: Bool,
        reachedLimits: [GrammarGeneralizedLimit], syntaxDiagnostics: [GrammarSyntaxDiagnostic],
        forest: GrammarGeneralizedParseForest, sharedForest: GrammarSharedParseForest = .empty
    ) {
        self.status = status; self.tokens = tokens; self.alternatives = alternatives
        self.diagnostics = diagnostics; self.metrics = metrics; self.wasTruncated = wasTruncated
        self.reachedLimits = reachedLimits; self.syntaxDiagnostics = syntaxDiagnostics
        self.forest = forest; self.sharedForest = sharedForest
    }

    private enum CodingKeys: String, CodingKey {
        case status, tokens, alternatives, diagnostics, metrics, wasTruncated
        case reachedLimits, syntaxDiagnostics, forest, sharedForest
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            status: try values.decode(GrammarGeneralizedParseStatus.self, forKey: .status),
            tokens: try values.decode([GrammarInputTokenSnapshot].self, forKey: .tokens),
            alternatives: try values.decode([GrammarSyntaxNode].self, forKey: .alternatives),
            diagnostics: try values.decode([GrammarInputDiagnostic].self, forKey: .diagnostics),
            metrics: try values.decode(GrammarGeneralizedParseMetrics.self, forKey: .metrics),
            wasTruncated: try values.decode(Bool.self, forKey: .wasTruncated),
            reachedLimits: try values.decode([GrammarGeneralizedLimit].self, forKey: .reachedLimits),
            syntaxDiagnostics: try values.decode([GrammarSyntaxDiagnostic].self, forKey: .syntaxDiagnostics),
            forest: try values.decode(GrammarGeneralizedParseForest.self, forKey: .forest),
            sharedForest: try values.decodeIfPresent(GrammarSharedParseForest.self, forKey: .sharedForest) ?? .empty
        )
    }
}

enum GeneralizedLRParser {
    private struct Configuration: Hashable {
        var states: [StateID]
        var nodes: [Int]
        var cursor: Int
    }

    private struct NodeKey: Hashable { let symbol: String; let start: Int; let end: Int }
    private struct Family: Hashable { let production: ProductionID?; let children: [Int] }
    private struct ForestNode { let key: NodeKey; var families: [Family] }

    private struct ForestArena {
        var nodes: [ForestNode] = []
        var ids: [NodeKey: Int] = [:]
        var familyCount = 0
        let maximumNodes: Int
        let maximumFamilies: Int
        var reachedLimits = Set<GrammarGeneralizedLimit>()

        mutating func intern(
            symbol: String, start: Int, end: Int, production: ProductionID?, children: [Int]
        ) -> Int? {
            let key = NodeKey(symbol: symbol, start: start, end: end)
            let family = Family(production: production, children: children)
            if let id = ids[key] {
                if !nodes[id].families.contains(family) {
                    guard familyCount < maximumFamilies else {
                        reachedLimits.insert(.packedFamilies); return nil
                    }
                    nodes[id].families.append(family)
                    familyCount += 1
                }
                return id
            }
            guard nodes.count < maximumNodes else {
                reachedLimits.insert(.forestNodes); return nil
            }
            guard familyCount < maximumFamilies else {
                reachedLimits.insert(.packedFamilies); return nil
            }
            let id = nodes.count
            nodes.append(.init(key: key, families: [family]))
            ids[key] = id
            familyCount += 1
            return id
        }

        func start(of id: Int, fallback: Int) -> Int {
            nodes.indices.contains(id) ? nodes[id].key.start : fallback
        }

        func publicForest(roots: [Int]) -> GrammarSharedParseForest {
            var reachable = Set<Int>()
            var pending = roots
            while let id = pending.popLast() {
                guard nodes.indices.contains(id), reachable.insert(id).inserted else { continue }
                pending.append(contentsOf: nodes[id].families.flatMap(\.children))
            }
            let publicNodes = reachable.map { index in
                let node = nodes[index]
                let nodeID = stableNodeID(index)
                let families = node.families.map { family in
                    let children = family.children.map(stableNodeID)
                    let familyID = "\(nodeID):p\(family.production?.rawValue.description ?? "terminal"):\(children.joined(separator: ","))"
                    return GrammarPackedForestFamily(
                        id: familyID, production: family.production?.rawValue, children: children
                    )
                }.sorted { $0.id < $1.id }
                return GrammarSharedForestNode(
                    id: nodeID, symbol: node.key.symbol,
                    span: .init(lowerBound: node.key.start, upperBound: node.key.end),
                    families: families
                )
            }.sorted { $0.id < $1.id }
            return .init(roots: roots.map(stableNodeID).sorted(), nodes: publicNodes)
        }

        func materialize(roots: [Int], maximumTrees: Int) -> (trees: [ParseTreeNode], truncated: Bool) {
            let limit = maximumTrees + 1
            var memo: [Int: [ParseTreeNode]] = [:]
            var active = Set<Int>()
            func expand(_ id: Int) -> [ParseTreeNode] {
                if let value = memo[id] { return value }
                guard nodes.indices.contains(id), active.insert(id).inserted else { return [] }
                let node = nodes[id]
                var results: [ParseTreeNode] = []
                for family in node.families {
                    var combinations: [[ParseTreeNode]] = [[]]
                    for child in family.children {
                        let childTrees = expand(child)
                        var next: [[ParseTreeNode]] = []
                        for prefix in combinations {
                            for tree in childTrees {
                                next.append(prefix + [tree])
                                if next.count >= limit { break }
                            }
                            if next.count >= limit { break }
                        }
                        combinations = next
                        if combinations.isEmpty || combinations.count >= limit { break }
                    }
                    if family.children.isEmpty { combinations = [[]] }
                    for children in combinations {
                        results.append(.init(
                            symbol: node.key.symbol, children: children, production: family.production
                        ))
                        if results.count >= limit { break }
                    }
                    if results.count >= limit { break }
                }
                active.remove(id)
                memo[id] = results
                return results
            }
            var trees: [ParseTreeNode] = []
            for root in roots {
                for tree in expand(root) where !trees.contains(tree) {
                    trees.append(tree)
                    if trees.count >= limit { break }
                }
                if trees.count >= limit { break }
            }
            let truncated = trees.count > maximumTrees
            return (Array(trees.prefix(maximumTrees)), truncated)
        }

        func derivationCount(root: Int, upTo limit: Int) -> Int {
            var memo: [Int: Int] = [:]
            var active = Set<Int>()
            func count(_ id: Int) -> Int {
                if let value = memo[id] { return value }
                guard nodes.indices.contains(id), active.insert(id).inserted else { return limit }
                var total = 0
                for family in nodes[id].families {
                    var product = 1
                    for child in family.children {
                        let value = count(child)
                        product = product >= limit || value > limit / max(1, product)
                            ? limit : product * value
                    }
                    total = total >= limit - product ? limit : total + product
                }
                active.remove(id)
                memo[id] = total
                return total
            }
            return count(root)
        }

        private func stableNodeID(_ id: Int) -> String {
            guard nodes.indices.contains(id) else { return "missing:\(id)" }
            let key = nodes[id].key
            return "\(key.symbol)@\(key.start)..<\(key.end)"
        }
    }

    struct Result {
        let trees: [ParseTreeNode]
        let sharedForest: GrammarSharedParseForest
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
        var acceptedRoots: [Int] = []
        var acceptedRootSet = Set<Int>()
        var arena = ForestArena(
            maximumNodes: options.maximumForestNodes,
            maximumFamilies: options.maximumPackedFamilies
        )
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
                    guard let node = arena.intern(
                        symbol: input[configuration.cursor], start: configuration.cursor,
                        end: configuration.cursor + 1, production: nil, children: []
                    ) else { discarded += 1; continue }
                    next.nodes.append(node)
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
                    let start = children.first.map { arena.start(of: $0, fallback: configuration.cursor) }
                        ?? configuration.cursor
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
                    guard let node = arena.intern(
                        symbol: production.lhs, start: start, end: configuration.cursor,
                        production: productionID, children: children
                    ) else { discarded += 1; continue }
                    next.nodes.append(node)
                    reductions += 1
                    enqueue(next)
                case .accept:
                    if let root = configuration.nodes.last,
                       acceptedRootSet.insert(root).inserted {
                        acceptedRoots.append(root)
                    }
                case .goTo: break
                }
            }
        }

        reachedLimits.formUnion(arena.reachedLimits)
        let materialized = arena.materialize(roots: acceptedRoots, maximumTrees: options.maximumTrees)
        if materialized.truncated { reachedLimits.insert(.trees) }
        let accepts = acceptedRoots.reduce(0) {
            $0 + arena.derivationCount(root: $1, upTo: options.maximumTrees + 1)
        }

        return .init(
            trees: materialized.trees,
            sharedForest: arena.publicForest(roots: acceptedRoots),
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
            forest: forest,
            sharedForest: result.sharedForest
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

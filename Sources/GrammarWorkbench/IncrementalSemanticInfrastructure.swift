import Foundation

/// One searchable entry in the reducer-neutral index attached to an
/// incremental analysis snapshot. Entries use the same stable identities as
/// the snapshot's syntax tree, allowing editor state to survive revisions.
public struct GrammarIncrementalIndexEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: GrammarIncrementalIdentity
    public let parentID: GrammarIncrementalIdentity?
    public let symbol: String
    public let production: Int?
    public let tokenKind: String?
    public let lexeme: String?
    public let range: SourceRange?
    public let depth: Int
    public let isTerminal: Bool
    public let isMissing: Bool

    public init(
        id: GrammarIncrementalIdentity,
        parentID: GrammarIncrementalIdentity?,
        symbol: String,
        production: Int?,
        tokenKind: String?,
        lexeme: String?,
        range: SourceRange?,
        depth: Int,
        isTerminal: Bool,
        isMissing: Bool
    ) {
        self.id = id
        self.parentID = parentID
        self.symbol = symbol
        self.production = production
        self.tokenKind = tokenKind
        self.lexeme = lexeme
        self.range = range
        self.depth = depth
        self.isTerminal = isTerminal
        self.isMissing = isMissing
    }
}

/// A flat, source-ordered view of an incremental syntax tree suitable for
/// document symbols, navigation, semantic-token classification, and custom
/// symbol-index construction.
public struct GrammarIncrementalSemanticIndex: Hashable, Codable, Sendable {
    public let entries: [GrammarIncrementalIndexEntry]

    public init(entries: [GrammarIncrementalIndexEntry]) {
        self.entries = entries
    }

    public func entries(named symbol: String) -> [GrammarIncrementalIndexEntry] {
        entries.filter { $0.symbol == symbol }
    }

    public func entries(productionID: Int) -> [GrammarIncrementalIndexEntry] {
        entries.filter { $0.production == productionID }
    }

    public func entry(id: GrammarIncrementalIdentity) -> GrammarIncrementalIndexEntry? {
        entries.first { $0.id == id }
    }

    /// Returns the most deeply nested entry containing a UTF-16 source offset.
    public func entry(atUTF16Offset offset: Int) -> GrammarIncrementalIndexEntry? {
        entries
            .filter { entry in
                guard let range = entry.range else { return false }
                if range.start.offset == range.end.offset {
                    return offset == range.start.offset
                }
                return range.start.offset <= offset && offset < range.end.offset
            }
            .max { $0.depth < $1.depth }
    }

    static func make(from root: GrammarIncrementalSyntaxNode?) -> Self {
        guard let root else { return .init(entries: []) }
        var entries: [GrammarIncrementalIndexEntry] = []
        func visit(
            _ node: GrammarIncrementalSyntaxNode,
            parentID: GrammarIncrementalIdentity?,
            depth: Int
        ) {
            entries.append(.init(
                id: node.id,
                parentID: parentID,
                symbol: node.node.symbol,
                production: node.node.production,
                tokenKind: node.node.token?.kind,
                lexeme: node.node.token?.lexeme,
                range: node.node.range,
                depth: depth,
                isTerminal: node.node.isTerminal,
                isMissing: node.node.isMissing
            ))
            node.children.forEach { visit($0, parentID: node.id, depth: depth + 1) }
        }
        visit(root, parentID: nil, depth: 0)
        return .init(entries: entries)
    }
}

public struct GrammarIncrementalIndexingMetrics: Hashable, Codable, Sendable {
    public let reusedEntries: Int
    public let updatedEntries: Int
    public let createdEntries: Int
    public let removedEntries: Int
}

public struct GrammarIncrementalSemanticMetrics: Hashable, Codable, Sendable {
    public let reusedValues: Int
    public let evaluatedValues: Int
    public let removedValues: Int
    public let invalidatedByGrammarChange: Bool
}

public struct GrammarIncrementalSemanticResult<Value: Sendable>: Sendable {
    public let analysis: GrammarIncrementalAnalysisSnapshot
    public let value: Value
    public let metrics: GrammarIncrementalSemanticMetrics
}

/// Incrementally evaluates source-aware syntax trees with an application
/// reducer. The evaluator is deliberately separate from the non-generic
/// language session so arbitrary Sendable application values remain strongly
/// typed.
public actor GrammarIncrementalSemanticEvaluator<Reducer: GrammarSemanticReducer> {
    private struct CachedValue: Sendable {
        let node: GrammarSyntaxNode
        let value: Reducer.Value
    }

    private let reducer: Reducer
    private var productions: [Int: GrammarProductionSnapshot]
    private var cache: [GrammarIncrementalIdentity: CachedValue] = [:]
    private var grammarRevision: Int?
    private var pendingGrammarInvalidation = false

    public init(compilation: GrammarCompilation, reducer: Reducer) throws {
        guard compilation.succeeded, let artifact = compilation.artifact else {
            throw GrammarWorkbenchAPIError.compilationFailed(
                compilation.diagnostics.first?.message ?? "The grammar did not compile."
            )
        }
        self.reducer = reducer
        productions = Dictionary(uniqueKeysWithValues: artifact.productions.map { ($0.id, $0) })
    }

    /// Replaces production metadata and invalidates all cached semantic values.
    /// Call this alongside the language session's `updateCompilation`.
    public func updateCompilation(_ compilation: GrammarCompilation) throws {
        guard compilation.succeeded, let artifact = compilation.artifact else {
            throw GrammarWorkbenchAPIError.compilationFailed(
                compilation.diagnostics.first?.message ?? "The grammar did not compile."
            )
        }
        productions = Dictionary(uniqueKeysWithValues: artifact.productions.map { ($0.id, $0) })
        cache.removeAll(keepingCapacity: true)
        grammarRevision = nil
        pendingGrammarInvalidation = true
    }

    public func evaluate(
        _ analysis: GrammarIncrementalAnalysisSnapshot
    ) throws -> GrammarIncrementalSemanticResult<Reducer.Value> {
        guard analysis.parse.status == .accepted || analysis.parse.status == .acceptedWithRecovery else {
            throw GrammarSemanticError.parseDidNotComplete(analysis.parse.status)
        }
        guard let root = analysis.syntaxTree else { throw GrammarSemanticError.missingSyntaxTree }

        let grammarChanged = pendingGrammarInvalidation
            || (grammarRevision.map { $0 != analysis.grammarRevision } ?? false)
        let oldCount = cache.count
        let sourceCache = grammarChanged ? [:] : cache
        var nextCache: [GrammarIncrementalIdentity: CachedValue] = [:]
        var reused = 0
        var evaluated = 0

        func retainCachedSubtree(_ node: GrammarIncrementalSyntaxNode) {
            if let cached = sourceCache[node.id], cached.node == node.node {
                nextCache[node.id] = cached
                reused += 1
            }
            node.children.forEach(retainCachedSubtree)
        }

        func visit(_ node: GrammarIncrementalSyntaxNode) throws -> Reducer.Value {
            if let cached = sourceCache[node.id], cached.node == node.node {
                retainCachedSubtree(node)
                return cached.value
            }
            let value: Reducer.Value
            if node.node.isMissing {
                value = try reducer.missing(symbol: node.node.symbol, node: node.node)
            } else if let token = node.node.token {
                value = try reducer.terminal(token, node: node.node)
            } else {
                guard let id = node.node.production, let production = productions[id] else {
                    throw GrammarSemanticError.unknownProduction(node.node.production ?? -1)
                }
                value = try reducer.reduce(
                    production: production,
                    children: try node.children.map(visit),
                    node: node.node
                )
            }
            nextCache[node.id] = .init(node: node.node, value: value)
            evaluated += 1
            return value
        }

        let value = try visit(root)
        let removed = grammarChanged
            ? oldCount
            : sourceCache.keys.filter { nextCache[$0] == nil }.count
        cache = nextCache
        grammarRevision = analysis.grammarRevision
        pendingGrammarInvalidation = false
        return .init(
            analysis: analysis,
            value: value,
            metrics: .init(
                reusedValues: reused,
                evaluatedValues: evaluated,
                removedValues: removed,
                invalidatedByGrammarChange: grammarChanged
            )
        )
    }

    public func removeAllCachedValues() {
        cache.removeAll(keepingCapacity: true)
        grammarRevision = nil
        pendingGrammarInvalidation = false
    }
}

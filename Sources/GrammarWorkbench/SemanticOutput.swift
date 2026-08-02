import Foundation

/// A stable, Codable concrete-syntax tree retaining production identities,
/// token lexemes, source locations, and recovery insertions.
public struct GrammarSyntaxNode: Hashable, Codable, Sendable {
    public let symbol: String
    public let production: Int?
    public let token: GrammarInputTokenSnapshot?
    public let children: [GrammarSyntaxNode]
    public let range: SourceRange?
    public let isMissing: Bool

    public var isTerminal: Bool { production == nil && children.isEmpty }

    public func descendants(named symbol: String) -> [GrammarSyntaxNode] {
        (self.symbol == symbol ? [self] : []) + children.flatMap { $0.descendants(named: symbol) }
    }
}

/// Converts a concrete syntax tree into an application-defined semantic value.
/// Reducers can build ASTs, evaluate expressions, populate indexes, or bridge
/// into another compiler framework without depending on engine implementation types.
public protocol GrammarSemanticReducer: Sendable {
    associatedtype Value: Sendable
    func terminal(_ token: GrammarInputTokenSnapshot, node: GrammarSyntaxNode) throws -> Value
    func missing(symbol: String, node: GrammarSyntaxNode) throws -> Value
    func reduce(
        production: GrammarProductionSnapshot,
        children: [Value],
        node: GrammarSyntaxNode
    ) throws -> Value
}

public struct GrammarSemanticResult<Value: Sendable>: Sendable {
    public let parse: GrammarParseResult
    public let value: Value
}

public enum GrammarSemanticError: Error, LocalizedError, Sendable {
    case parseDidNotComplete(GrammarParseStatus)
    case missingSyntaxTree
    case unknownProduction(Int)

    public var errorDescription: String? {
        switch self {
        case .parseDidNotComplete(let status):
            "Semantic evaluation requires an accepted parse, not ‘\(status.rawValue)’."
        case .missingSyntaxTree: "The accepted parse did not produce a syntax tree."
        case .unknownProduction(let id): "The syntax tree refers to unknown production \(id)."
        }
    }
}

/// Tool-neutral grammar metadata for AST generators, language servers, and
/// documentation tools. Production IDs match syntax-tree reduction identities.
public struct GrammarSemanticModel: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let startSymbol: String
    public let terminals: [String]
    public let nonterminals: [String]
    public let productions: [GrammarProductionSnapshot]

    public init(compilation: GrammarCompilation) throws {
        guard let grammar = compilation.grammar else {
            throw GrammarWorkbenchAPIError.compilationFailed(
                compilation.diagnostics.first?.message ?? "The grammar did not compile."
            )
        }
        schemaVersion = Self.currentSchemaVersion
        startSymbol = grammar.startSymbol
        terminals = grammar.terminals
        nonterminals = grammar.nonterminals
        // Artifact production IDs are the identities emitted by parser reductions.
        // Production zero is the construction engine's augmented start rule.
        productions = compilation.artifact?.productions.filter { $0.id != 0 } ?? []
    }
}

extension GrammarSyntaxNode {
    static func make(from tree: ParseTreeNode, tokens: [GrammarInputTokenSnapshot]) -> Self {
        var tokenCursor = 0
        return make(from: tree, tokens: tokens, tokenCursor: &tokenCursor)
    }

    private static func make(
        from tree: ParseTreeNode,
        tokens: [GrammarInputTokenSnapshot],
        tokenCursor: inout Int
    ) -> Self {
        if tree.children.isEmpty {
            let token = tree.isMissing || !tokens.indices.contains(tokenCursor) ? nil : tokens[tokenCursor]
            if !tree.isMissing { tokenCursor += 1 }
            return .init(
                symbol: tree.isMissing ? tree.symbol.replacingOccurrences(of: "⟨missing ", with: "").replacingOccurrences(of: "⟩", with: "") : tree.symbol,
                production: nil, token: token, children: [], range: token?.range,
                isMissing: tree.isMissing
            )
        }
        let children = tree.children.map { make(from: $0, tokens: tokens, tokenCursor: &tokenCursor) }
        let located = children.compactMap(\.range)
        let range = located.first.flatMap { first in
            located.last.map { SourceRange(start: first.start, end: $0.end) }
        }
        return .init(
            symbol: tree.symbol, production: tree.production?.rawValue, token: nil,
            children: children, range: range, isMissing: false
        )
    }
}

public extension GrammarCompilation {
    func parse<R: GrammarSemanticReducer>(
        _ input: String,
        using reducer: R,
        options: GrammarParseOptions = .init()
    ) throws -> GrammarSemanticResult<R.Value> {
        let parsed = parse(input, options: options)
        guard parsed.status == .accepted || parsed.status == .acceptedWithRecovery else {
            throw GrammarSemanticError.parseDidNotComplete(parsed.status)
        }
        guard let root = parsed.syntaxTree else { throw GrammarSemanticError.missingSyntaxTree }
        let productions = Dictionary(uniqueKeysWithValues: (artifact?.productions ?? []).map { ($0.id, $0) })

        func evaluate(_ node: GrammarSyntaxNode) throws -> R.Value {
            if node.isMissing { return try reducer.missing(symbol: node.symbol, node: node) }
            if let token = node.token { return try reducer.terminal(token, node: node) }
            guard let id = node.production, let production = productions[id] else {
                throw GrammarSemanticError.unknownProduction(node.production ?? -1)
            }
            return try reducer.reduce(
                production: production,
                children: try node.children.map(evaluate),
                node: node
            )
        }

        return .init(parse: parsed, value: try evaluate(root))
    }
}

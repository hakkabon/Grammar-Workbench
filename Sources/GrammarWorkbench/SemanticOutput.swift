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

    public func rendered() -> String {
        func lines(_ node: Self, prefix: String) -> [String] {
            node.children.enumerated().flatMap { index, child in
                let last = index == node.children.count - 1
                let label = child.isMissing ? "⟨missing \(child.symbol)⟩" : child.symbol
                return ["\(prefix)\(last ? "└─ " : "├─ ")\(label)"]
                    + lines(child, prefix: prefix + (last ? "   " : "│  "))
            }
        }
        return ([symbol] + lines(self, prefix: "")).joined(separator: "\n")
    }

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

public struct GrammarGeneralizedSemanticAlternative<Value: Sendable>: Sendable {
    public let id: String
    public let tree: GrammarSyntaxNode
    public let value: Value
}

public struct GrammarGeneralizedSemanticResult<Value: Sendable>: Sendable {
    public let parse: GrammarGeneralizedParseResult
    public let alternatives: [GrammarGeneralizedSemanticAlternative<Value>]
}

/// The input supplied to a declarative production action.
public struct GrammarSemanticReduction<Value: Sendable>: Sendable {
    public let production: GrammarProductionSnapshot
    public let children: [Value]
    public let node: GrammarSyntaxNode
}

/// A production handler identified by the same ID exposed by
/// ``GrammarSemanticModel`` and syntax-tree nodes.
public struct GrammarSemanticProductionAction<Value: Sendable>: Sendable {
    public typealias Handler = @Sendable (GrammarSemanticReduction<Value>) throws -> Value

    public let productionID: Int
    let handler: Handler

    public init(_ productionID: Int, _ handler: @escaping Handler) {
        self.productionID = productionID
        self.handler = handler
    }
}

/// A declarative reducer that makes production coverage explicit and testable.
/// Use ``GrammarSemanticModel/validate(_:)`` before parsing to catch missing or
/// stale handlers without needing representative input for every production.
public struct GrammarSemanticActions<Value: Sendable>: GrammarSemanticReducer {
    public typealias TerminalHandler = @Sendable (GrammarInputTokenSnapshot, GrammarSyntaxNode) throws -> Value
    public typealias MissingHandler = @Sendable (String, GrammarSyntaxNode) throws -> Value

    public let productionIDs: Set<Int>
    private let terminalHandler: TerminalHandler
    private let missingHandler: MissingHandler
    private let handlers: [Int: GrammarSemanticProductionAction<Value>.Handler]

    public init(
        terminal: @escaping TerminalHandler,
        missing: @escaping MissingHandler,
        productions: [GrammarSemanticProductionAction<Value>]
    ) throws {
        var handlers: [Int: GrammarSemanticProductionAction<Value>.Handler] = [:]
        for action in productions {
            guard handlers[action.productionID] == nil else {
                throw GrammarSemanticError.duplicateProductionAction(action.productionID)
            }
            handlers[action.productionID] = action.handler
        }
        self.terminalHandler = terminal
        self.missingHandler = missing
        self.handlers = handlers
        productionIDs = Set(handlers.keys)
    }

    public func terminal(_ token: GrammarInputTokenSnapshot, node: GrammarSyntaxNode) throws -> Value {
        try terminalHandler(token, node)
    }

    public func missing(symbol: String, node: GrammarSyntaxNode) throws -> Value {
        try missingHandler(symbol, node)
    }

    public func reduce(
        production: GrammarProductionSnapshot, children: [Value], node: GrammarSyntaxNode
    ) throws -> Value {
        guard let handler = handlers[production.id] else {
            throw GrammarSemanticError.unhandledProduction(production)
        }
        return try handler(.init(production: production, children: children, node: node))
    }
}

public enum GrammarSemanticError: Error, LocalizedError, Sendable {
    case parseDidNotComplete(GrammarParseStatus)
    case missingSyntaxTree
    case unknownProduction(Int)
    case duplicateProductionAction(Int)
    case unhandledProduction(GrammarProductionSnapshot)
    case incompleteProductionCoverage(missing: [GrammarProductionSnapshot], unknown: [Int])
    case generalizedParseDidNotComplete(GrammarGeneralizedParseStatus)

    public var errorDescription: String? {
        return switch self {
        case .parseDidNotComplete(let status):
            "Semantic evaluation requires an accepted parse, not ‘\(status.rawValue)’."
        case .missingSyntaxTree: "The accepted parse did not produce a syntax tree."
        case .unknownProduction(let id): "The syntax tree refers to unknown production \(id)."
        case .duplicateProductionAction(let id): "Semantic production \(id) has more than one action."
        case .unhandledProduction(let production): "No semantic action handles production \(production.id) (‘\(production.text)’)."
        case .incompleteProductionCoverage(let missing, let unknown):
            coverageDescription(missing: missing, unknown: unknown)
        case .generalizedParseDidNotComplete(let status):
            "Generalized semantic evaluation requires an accepted forest, not ‘\(status.rawValue)’."
        }
    }

    private func coverageDescription(
        missing: [GrammarProductionSnapshot], unknown: [Int]
    ) -> String {
        let missingIDs = missing.map { String($0.id) }.joined(separator: ", ")
        let unknownIDs = unknown.map(String.init).joined(separator: ", ")
        return "Semantic action coverage is incomplete (missing: [\(missingIDs)]; unknown: [\(unknownIDs)])."
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

    public func production(id: Int) -> GrammarProductionSnapshot? {
        productions.first { $0.id == id }
    }

    public func productions(lhs: String, rhs: [String]? = nil) -> [GrammarProductionSnapshot] {
        productions.filter { $0.lhs == lhs && (rhs == nil || $0.rhs == rhs) }
    }

    /// Ensures a declarative reducer covers every current grammar production and
    /// does not retain handlers for production IDs removed by a grammar edit.
    public func validate<Value>(_ actions: GrammarSemanticActions<Value>) throws {
        let known = Set(productions.map(\.id))
        let missing = productions.filter { !actions.productionIDs.contains($0.id) }
        let unknown = actions.productionIDs.subtracting(known).sorted()
        guard missing.isEmpty, unknown.isEmpty else {
            throw GrammarSemanticError.incompleteProductionCoverage(missing: missing, unknown: unknown)
        }
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
        return .init(parse: parsed, value: try evaluate(root, using: reducer))
    }

    /// Evaluates every accepted generalized alternative with the same semantic
    /// reducer used by deterministic parsing. Stable forest IDs remain attached
    /// to the resulting values so callers can present or select an ambiguity.
    func parseGeneralized<R: GrammarSemanticReducer>(
        _ input: String,
        using reducer: R,
        options: GrammarGeneralizedParseOptions = .init()
    ) throws -> GrammarGeneralizedSemanticResult<R.Value> {
        let parsed = parseGeneralized(input, options: options)
        guard parsed.isAccepted else {
            throw GrammarSemanticError.generalizedParseDidNotComplete(parsed.status)
        }
        let alternatives = try parsed.forest.alternatives.map { alternative in
            GrammarGeneralizedSemanticAlternative(
                id: alternative.id,
                tree: alternative.tree,
                value: try evaluate(alternative.tree, using: reducer)
            )
        }
        return .init(parse: parsed, alternatives: alternatives)
    }

    private func evaluate<R: GrammarSemanticReducer>(
        _ node: GrammarSyntaxNode,
        using reducer: R
    ) throws -> R.Value {
        let productions = Dictionary(uniqueKeysWithValues: (artifact?.productions ?? []).map { ($0.id, $0) })
        return try evaluate(node, using: reducer, productions: productions)
    }

    private func evaluate<R: GrammarSemanticReducer>(
        _ node: GrammarSyntaxNode,
        using reducer: R,
        productions: [Int: GrammarProductionSnapshot]
    ) throws -> R.Value {
        if node.isMissing { return try reducer.missing(symbol: node.symbol, node: node) }
        if let token = node.token { return try reducer.terminal(token, node: node) }
        guard let id = node.production, let production = productions[id] else {
            throw GrammarSemanticError.unknownProduction(node.production ?? -1)
        }
        return try reducer.reduce(
            production: production,
            children: try node.children.map {
                try evaluate($0, using: reducer, productions: productions)
            },
            node: node
        )
    }
}

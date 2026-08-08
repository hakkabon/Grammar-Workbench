import GrammarWorkbench

enum Expression: Sendable, Equatable {
    case number(Int)
    indirect case addition(Expression, Expression)
}

struct ExpressionReducer: GrammarSemanticReducer {
    func terminal(_ token: GrammarInputTokenSnapshot, node: GrammarSyntaxNode) throws -> Expression {
        .number(Int(token.lexeme) ?? 0)
    }

    func missing(symbol: String, node: GrammarSyntaxNode) throws -> Expression { .number(0) }

    func reduce(
        production: GrammarProductionSnapshot,
        children: [Expression],
        node: GrammarSyntaxNode
    ) throws -> Expression {
        if production.rhs == ["Expr", "+", "NUMBER"], children.count == 3 {
            return .addition(children[0], children[2])
        }
        return children.first ?? .number(0)
    }
}

let source = #"""
%token NUMBER /[0-9]+/
%skip /\s+/
%start Expr
Expr : Expr '+' NUMBER | NUMBER ;
"""#

let compilation = GrammarWorkbenchAPI.compile(.init(source: source, algorithm: .lalr))
guard compilation.succeeded else { fatalError("Compilation failed: \(compilation.diagnostics)") }
let semantic = try compilation.parse("1 + 2", using: ExpressionReducer())
guard semantic.parse.status == .accepted,
      semantic.value == .addition(.number(1), .number(2)),
      semantic.parse.syntaxTree?.range?.end.offset == 5 else {
    fatalError("Unexpected semantic output")
}
let model = try GrammarSemanticModel(compilation: compilation)
guard model.startSymbol == "Expr", !model.productions.isEmpty else {
    fatalError("Unexpected semantic model")
}
let declarative = try GrammarSemanticActions<String>(
    terminal: { token, _ in token.lexeme },
    missing: { symbol, _ in "<missing \(symbol)>" },
    productions: model.productions.map { production in
        .init(production.id) { $0.children.joined() }
    }
)
try model.validate(declarative)
guard try compilation.parse("1 + 2", using: declarative).value == "1+2" else {
    fatalError("Unexpected declarative semantic output")
}
let ebnf = try GrammarWorkbenchAPI.lowerEBNF("root = \"ok\" ;")
guard ebnf.productionOrigins.first?.sourceNonterminal == "root",
      ebnf.productionOrigins.first?.sourceRange.start.line == 1 else {
    fatalError("Unexpected EBNF production origins")
}
print("library-consumer-ok")

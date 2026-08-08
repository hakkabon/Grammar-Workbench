import Foundation
import Testing
import GrammarWorkbench

private let semanticGrammar = """
%token NUMBER /[0-9]+/
%skip /\\s+/
%start Expr
Expr : Expr '+' NUMBER | NUMBER ;
"""

@Test func declarativeSemanticActionsEvaluateAndValidateCoverage() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: semanticGrammar))
    let model = try GrammarSemanticModel(compilation: compilation)
    let addition = try #require(model.productions(lhs: "Expr", rhs: ["Expr", "+", "NUMBER"]).only)
    let number = try #require(model.productions(lhs: "Expr", rhs: ["NUMBER"]).only)
    #expect(model.production(id: addition.id) == addition)

    let actions = try GrammarSemanticActions<Int>(
        terminal: { token, _ in Int(token.lexeme) ?? 0 },
        missing: { _, _ in 0 },
        productions: [
            .init(addition.id) { $0.children[0] + $0.children[2] },
            .init(number.id) { $0.children[0] }
        ]
    )
    try model.validate(actions)
    #expect(try compilation.parse("20 + 22", using: actions).value == 42)
}

@Test func semanticCoverageReportsGrammarDriftBeforeParsing() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: semanticGrammar))
    let model = try GrammarSemanticModel(compilation: compilation)
    let incomplete = try GrammarSemanticActions<String>(
        terminal: { token, _ in token.lexeme }, missing: { symbol, _ in symbol },
        productions: [.init(999) { $0.children.joined() }]
    )
    #expect(throws: GrammarSemanticError.self) { try model.validate(incomplete) }
    #expect(throws: GrammarSemanticError.self) {
        _ = try GrammarSemanticActions<String>(
            terminal: { token, _ in token.lexeme }, missing: { symbol, _ in symbol },
            productions: [.init(1) { _ in "" }, .init(1) { _ in "" }]
        )
    }
}

@Test func semanticSwiftGeneratorProducesCoverageCompleteStarter() async throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: semanticGrammar))
    let result = try await GrammarGeneratorRegistry().generate(
        identifier: "semantic-swift", from: compilation,
        options: .init(["typeName": "ExpressionSemantics"])
    )
    let source = try #require(result.files.only?.text)
    let model = try GrammarSemanticModel(compilation: compilation)
    #expect(result.files.only?.suggestedFilename == "ExpressionSemantics.swift")
    #expect(source.contains("public enum ExpressionSemantics"))
    #expect(source.contains("GrammarSemanticActions<String>"))
    for production in model.productions {
        #expect(source.contains(".init(\(production.id))"))
        #expect(source.contains(production.text))
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}

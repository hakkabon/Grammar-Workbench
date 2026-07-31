import Testing
@testable import GrammarWorkbench

@Test func parsesGrammarAndComputesFirstAndFollow() throws {
    let source = """
    %start List
    List : Item Tail ;
    Tail : ',' Item Tail | ;
    Item : 'id' ;
    """
    let result = GrammarFrontEnd.process(source)
    #expect(result.diagnostics.isEmpty)
    let grammar = try #require(result.grammar)
    let analysis = try #require(result.analysis)
    #expect(grammar.startSymbol == "List")
    #expect(grammar.nonterminals == ["List", "Tail", "Item"])
    #expect(Set(grammar.terminals) == [",", "id"])
    #expect(analysis.nullable == ["Tail"])
    #expect(analysis.first["List"] == ["id"])
    #expect(analysis.first["Tail"] == [","])
    #expect(analysis.follow["Item"] == [",", "$"])
}

@Test func precedenceDeclarationsPreserveOrder() throws {
    let result = GrammarFrontEnd.process("""
    %start E
    %left '+'
    %left '*'
    E : E '+' E | E '*' E | 'id' ;
    """)
    let grammar = try #require(result.grammar)
    #expect(grammar.precedence.map(\.level) == [1, 2])
    #expect(grammar.precedence.map(\.associativity) == [.left, .left])
    #expect(grammar.precedence.map(\.symbols) == [["+"], ["*"]])
}

@Test func malformedGrammarHasSourceLocatedDiagnostics() {
    let result = GrammarFrontEnd.process("""
    %start Missing
    Rule 'id' ;
    """)
    #expect(result.hasErrors)
    #expect(result.grammar == nil)
    #expect(result.diagnostics.contains { $0.message.contains("Expected ‘:’") && $0.range.start.line == 2 })
}

@Test func emptyAlternativeIsNullable() throws {
    let result = GrammarFrontEnd.process("Optional : 'value' | ;")
    let analysis = try #require(result.analysis)
    #expect(analysis.nullable.contains("Optional"))
}

@Test func legacyGrammarStillInfersUnquotedTerminals() throws {
    let result = GrammarFrontEnd.process("%start S\nS : identifier ;")
    let grammar = try #require(result.grammar)
    #expect(!result.hasErrors)
    #expect(!grammar.usesExplicitTokens)
    #expect(grammar.terminals == ["identifier"])
}

@Test func explicitTokensEnableUndefinedSymbolValidation() throws {
    let result = GrammarFrontEnd.process("""
    %start S
    %token ID
    S : ID Missing ;
    """)
    let grammar = try #require(result.grammar)
    #expect(grammar.usesExplicitTokens)
    #expect(grammar.terminals == ["ID"])
    let diagnostic = try #require(result.diagnostics.first { $0.code == "undefined-symbol" })
    #expect(diagnostic.severity == .error)
    #expect(diagnostic.range.start.line == 3)
}

@Test func tokenDeclarationValidationFindsDuplicatesUnusedAndCollisions() {
    let result = GrammarFrontEnd.process("""
    %start S
    %token ID ID UNUSED S
    S : ID ;
    """)
    #expect(result.diagnostics.contains { $0.code == "duplicate-token" })
    #expect(result.diagnostics.contains { $0.code == "unused-token" })
    #expect(result.diagnostics.contains { $0.code == "symbol-collision" && $0.severity == .error })
}

@Test func validationFindsNullableCyclesAndPrecedenceProblems() {
    let result = GrammarFrontEnd.process("""
    %start S
    %token ID
    %left MISSING
    %right MISSING
    S : A ;
    A : B | ;
    B : A ;
    """)
    #expect(result.diagnostics.contains { $0.code == "nullable-cycle" && $0.message.contains("‘A’") })
    #expect(result.diagnostics.contains { $0.code == "nullable-cycle" && $0.message.contains("‘B’") })
    #expect(result.diagnostics.contains { $0.code == "duplicate-precedence" })
    #expect(result.diagnostics.contains { $0.code == "invalid-precedence-symbol" })
}

@Test func tokenDeclarationsRejectEmptyAndReservedNames() {
    let result = GrammarFrontEnd.process("""
    %start S
    %token '' '$'
    S : ;
    """)
    #expect(result.diagnostics.contains { $0.code == "empty-terminal" && $0.severity == .error })
    #expect(result.diagnostics.contains { $0.code == "reserved-symbol" })
}

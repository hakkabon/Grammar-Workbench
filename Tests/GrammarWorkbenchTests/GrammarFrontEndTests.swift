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

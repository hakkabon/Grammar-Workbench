import Testing
@testable import GrammarWorkbench

private let lexerGrammarSource = #"""
%start Assignment
%token ID /[A-Za-z_][A-Za-z0-9_]*/
%token EQ /==/
%skip /\s+/

Assignment : ID EQ ID ;
"""#

private func lexerGrammar(_ source: String = lexerGrammarSource) throws -> ParsedGrammar {
    let result = GrammarFrontEnd.process(source)
    return try #require(result.grammar)
}

@Test func lexerUsesPatternsSkipsTriviaAndPreservesRanges() throws {
    let result = GrammarLexerRuntime.lex("left ==\n right", grammar: try lexerGrammar())

    #expect(result.diagnostics.isEmpty)
    #expect(result.tokens.map(\.kind) == ["ID", "EQ", "ID"])
    #expect(result.tokens.map(\.lexeme) == ["left", "==", "right"])
    #expect(result.tokens.last?.range.start.line == 2)
    #expect(result.tokens.last?.range.start.column == 2)
}

@Test func lexerUsesMaximalMunchThenDeclarationOrder() throws {
    let source = #"""
    %start S
    %token ASSIGN /=/
    %token EQ /==/
    %skip /\s+/
    S : EQ | ASSIGN ;
    """#
    let result = GrammarLexerRuntime.lex("== =", grammar: try lexerGrammar(source))
    #expect(result.tokens.map(\.kind) == ["EQ", "ASSIGN"])
}

@Test func unpatternedTerminalsUseLiteralFallbackRules() throws {
    let source = #"""
    %start Sum
    %token ID /[a-z]+/
    %skip /\s+/
    Sum : ID '+' ID ;
    """#
    let result = GrammarLexerRuntime.lex("one + two", grammar: try lexerGrammar(source))
    #expect(result.tokens.map(\.kind) == ["ID", "+", "ID"])
    #expect(result.diagnostics.isEmpty)
}

@Test func lexicalFailureIsSourceLocatedAndScanningContinues() throws {
    let result = GrammarLexerRuntime.lex("ok @ next", grammar: try lexerGrammar())
    let diagnostic = try #require(result.diagnostics.first)
    #expect(diagnostic.message.contains("@"))
    #expect(diagnostic.range.start.line == 1)
    #expect(diagnostic.range.start.column == 4)
    #expect(result.tokens.map(\.lexeme) == ["ok", "next"])
}

@Test func invalidAndEmptyMatchingPatternsAreGrammarErrors() {
    let malformed = GrammarFrontEnd.process("%start S\n%token ID /[/\nS : ID ;")
    #expect(malformed.diagnostics.contains { $0.code == "invalid-lexer-pattern" })

    let empty = GrammarFrontEnd.process("%start S\n%token ID /a*/\nS : ID ;")
    #expect(empty.diagnostics.contains { $0.code == "empty-lexer-match" })
}

@Test func lexedTokenIdentitiesFeedTheLRParser() throws {
    let frontEnd = GrammarFrontEnd.process(lexerGrammarSource)
    let grammar = try #require(frontEnd.grammar)
    let artifact = LRConstructionEngine.construct(
        grammar: grammar,
        analysis: try #require(frontEnd.analysis),
        source: lexerGrammarSource,
        algorithm: .lalr
    )
    let lexer = GrammarLexerRuntime.lex("target == value", grammar: grammar)
    let runtime = LRParserRuntime.parse(lexer.tokens.map(\.kind), artifact: artifact)
    #expect(runtime.outcome == .accepted)
    #expect(runtime.tree?.rendered().contains("Assignment") == true)
}

@Test func standaloneExportIncludesRawLexemesAndTokenLocations() throws {
    let frontEnd = GrammarFrontEnd.process(lexerGrammarSource)
    let grammar = try #require(frontEnd.grammar)
    let artifact = LRConstructionEngine.construct(
        grammar: grammar,
        analysis: try #require(frontEnd.analysis),
        source: lexerGrammarSource,
        algorithm: .lalr
    )
    let lexer = GrammarLexerRuntime.lex("left == right", grammar: grammar)
    let runtime = LRParserRuntime.parse(lexer.tokens.map(\.kind), artifact: artifact)
    let html = HTMLExporter.render(artifact, runtime: runtime, lexer: lexer)
    #expect(html.contains("Lexer tokens"))
    #expect(html.contains("left"))
    #expect(html.contains("1:1"))
}

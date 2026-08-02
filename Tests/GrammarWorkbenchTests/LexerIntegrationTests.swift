import Foundation
import Testing
@testable import GrammarWorkbench

private let lexerGrammarSource = #"""
%start Assignment
%token ID /[A-Za-z_][A-Za-z0-9_]*/
%token EQ /==/
%skip /\s+/

Assignment : ID EQ ID ;
"""#

private let modeLexerGrammarSource = #"""
%token ID /[a-z]+/
%token QUOTE /"/ %push STRING
%skip /\s+/
%mode STRING
%token TEXT /[^"]+/
%token QUOTE /"/ %pop
%start S
S : ID QUOTE TEXT QUOTE ;
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

@Test func lexerModesPushPopAndPreserveTokenOrigins() throws {
    let frontEnd = GrammarFrontEnd.process(modeLexerGrammarSource)
    let grammar = try #require(frontEnd.grammar)
    #expect(!frontEnd.hasErrors)
    #expect(frontEnd.lexerAnalysis?.modes == ["DEFAULT", "STRING"])
    #expect(frontEnd.lexerAnalysis?.reachableModes == ["DEFAULT", "STRING"])
    #expect(frontEnd.lexerAnalysis?.transitions["DEFAULT"] == ["STRING"])

    let lexed = GrammarLexerRuntime.lex("say \"hello world\"", grammar: grammar)
    #expect(!lexed.hasErrors)
    #expect(lexed.tokens.map(\.kind) == ["ID", "QUOTE", "TEXT", "QUOTE"])
    #expect(lexed.tokens.map(\.mode) == ["DEFAULT", "DEFAULT", "STRING", "STRING"])
    #expect(lexed.tokens[2].lexeme == "hello world")
    #expect(lexed.finalModeStack == ["DEFAULT"])
}

@Test func lexerModeAnalysisFindsTransitionAndShadowingProblems() {
    let source = #"""
    %token ID /[a-z]+/ %push MISSING
    %mode UNUSED
    %token A /a/
    %token B /a/
    %start S
    S : ID ;
    """#
    let result = GrammarFrontEnd.process(source)
    #expect(result.diagnostics.contains { $0.code == "unknown-lexer-mode" && $0.severity == .error })
    #expect(result.diagnostics.contains { $0.code == "unreachable-lexer-mode" })
    #expect(result.diagnostics.contains { $0.code == "shadowed-lexer-rule" })
    #expect(result.lexerAnalysis?.shadowedRuleIDs.count == 1)
}

@Test func lexerReportsUnterminatedModeAtEndOfInput() throws {
    let grammar = try #require(GrammarFrontEnd.process(modeLexerGrammarSource).grammar)
    let result = GrammarLexerRuntime.lex("say \"hello", grammar: grammar)
    #expect(result.diagnostics.last?.mode == "STRING")
    #expect(result.diagnostics.last?.message.contains("ended in lexer mode") == true)
}

@Test func lexerCoverageDiagnosticsNameTheActiveModeAndContinue() throws {
    let source = #"""
    %token QUOTE /"/ %push STRING
    %mode STRING
    %token TEXT /[a-z]+/
    %token QUOTE /"/ %pop
    %start S
    S : QUOTE TEXT QUOTE ;
    """#
    let grammar = try #require(GrammarFrontEnd.process(source).grammar)
    let result = GrammarLexerRuntime.lex("\"hello@\"", grammar: grammar)
    let diagnostic = try #require(result.diagnostics.first)
    #expect(diagnostic.mode == "STRING")
    #expect(diagnostic.message.contains("mode ‘STRING’"))
    #expect(result.tokens.map(\.kind) == ["QUOTE", "TEXT", "QUOTE"])
    #expect(result.finalModeStack == ["DEFAULT"])
}

@Test func modeDirectiveCanReturnRuleDeclarationsToDefault() throws {
    let source = #"""
    %token OPEN /</ %begin TAG
    %mode TAG
    %token NAME /[a-z]+/
    %token CLOSE />/ %begin DEFAULT
    %mode DEFAULT
    %token TEXT /[a-z]+/
    %start S
    S : OPEN NAME CLOSE TEXT ;
    """#
    let frontEnd = GrammarFrontEnd.process(source)
    let grammar = try #require(frontEnd.grammar)
    #expect(!frontEnd.hasErrors)
    let result = GrammarLexerRuntime.lex("<tag>text", grammar: grammar)
    #expect(result.tokens.map(\.kind) == ["OPEN", "NAME", "CLOSE", "TEXT"])
    #expect(result.tokens.map(\.mode) == ["DEFAULT", "TAG", "TAG", "DEFAULT"])
}

@Test func legacyLexerRuleJSONDefaultsToDefaultModeWithoutAction() throws {
    let rule = try #require(try lexerGrammar().lexerRules.first)
    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(rule)) as? [String: Any]
    )
    object.removeValue(forKey: "mode")
    object.removeValue(forKey: "action")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(LexerRuleDeclaration.self, from: legacy)
    #expect(decoded.mode == "DEFAULT")
    #expect(decoded.action == .none)
}

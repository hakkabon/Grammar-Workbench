import Testing
@testable import GrammarWorkbench

@Test func semanticValidationFindsStructuralGrammarProblems() {
    let result = GrammarFrontEnd.process("""
    %start S
    %left 'unused'
    S : 'ok' ;
    S : 'ok' ;
    Dead : Dead ;
    """)
    #expect(!result.hasErrors)
    #expect(result.diagnostics.contains { $0.message.contains("Duplicate production") })
    #expect(result.diagnostics.contains { $0.message.contains("‘Dead’ is unreachable") })
    #expect(result.diagnostics.contains { $0.message.contains("‘Dead’ cannot derive") })
    #expect(result.diagnostics.contains { $0.message.contains("‘unused’ is never used") })
    #expect(result.diagnostics.allSatisfy { $0.severity == .warning })
}

@Test func editorCompletionsIncludeDirectivesAndGrammarSymbols() {
    let result = GrammarFrontEnd.process("%start List\nList : 'item' ;")
    let completions = GrammarEditorIntelligence.completions(for: result)
    #expect(completions.contains("%start"))
    #expect(completions.contains("%nonassoc"))
    #expect(completions.contains("List"))
    #expect(completions.contains("item"))
}

@Test func missingSemicolonQuickFixProducesValidGrammar() throws {
    let source = "%start S\nS : 'id'"
    let result = GrammarFrontEnd.process(source)
    let diagnostic = try #require(result.diagnostics.first { $0.message.hasPrefix("Expected ‘;’") })
    let fix = try #require(GrammarEditorIntelligence.quickFixes(for: diagnostic, source: source).first)
    let fixedSource = fix.applying(to: source)
    #expect(fixedSource.hasSuffix(";"))
    #expect(!GrammarFrontEnd.process(fixedSource).hasErrors)
}

@Test func missingColonQuickFixProducesValidGrammar() throws {
    let source = "%start S\nS 'id' ;"
    let result = GrammarFrontEnd.process(source)
    let diagnostic = try #require(result.diagnostics.first { $0.message.hasPrefix("Expected ‘:’") })
    let fix = try #require(GrammarEditorIntelligence.quickFixes(for: diagnostic, source: source).first)
    #expect(!GrammarFrontEnd.process(fix.applying(to: source)).hasErrors)
}

@MainActor
@Test func artifactSelectionResolvesToProductionSourceRange() {
    let source = "%start S\nS : A ;\nA : 'id' ;"
    let store = ExplorerStore(source: source)
    store.select(.production(.init(rawValue: 2)))
    #expect(store.sourceSelection?.start.line == 3)
    store.select(.state(.init(rawValue: 0)))
    #expect(store.sourceSelection != nil)
}

@Test func undefinedSymbolQuickFixAddsTokenDeclaration() throws {
    let source = "%start S\n%token ID\nS : ID Missing ;"
    let result = GrammarFrontEnd.process(source)
    let diagnostic = try #require(result.diagnostics.first { $0.code == "undefined-symbol" })
    let fix = try #require(GrammarEditorIntelligence.quickFixes(for: diagnostic, source: source).first)
    let fixed = fix.applying(to: source)
    #expect(fixed.hasPrefix("%token Missing\n"))
    #expect(!GrammarFrontEnd.process(fixed).hasErrors)
}

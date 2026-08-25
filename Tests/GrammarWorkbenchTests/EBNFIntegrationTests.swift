import Foundation
import Testing
import GrammarWorkbench

private let expressionEBNF = """
lexical {
    NUMBER = /[0-9]+/ ;
}
expression = term { "+" term } ;
term = NUMBER | "(" expression ")" ;
"""

@Test func existingGrammarModuleLowersEBNFForLRConstruction() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(
        source: expressionEBNF, algorithm: .lalr, notation: .ebnf
    ))

    #expect(compilation.succeeded)
    #expect(compilation.grammar?.startSymbol == "expression")
    #expect(compilation.grammar?.nonterminals.contains("__ebnf_1") == true)
    #expect(compilation.parse("1 + (2 + 3)", options: .init(enablesRecovery: false)).status == .accepted)
    #expect(compilation.parse("1 +", options: .init(enablesRecovery: false)).status == .rejected)
}

@Test func EBNFLoweringIsStableAcrossRepeatedCompilations() throws {
    let first = GrammarWorkbenchAPI.compile(.init(source: expressionEBNF, notation: .ebnf))
    let second = GrammarWorkbenchAPI.compile(.init(source: expressionEBNF, notation: .ebnf))
    let lowering = try GrammarWorkbenchAPI.lowerEBNF(expressionEBNF)

    #expect(first.artifact == second.artifact)
    #expect(lowering.syntheticNonterminals == ["__ebnf_1"])
    #expect(lowering.loweredSource.contains("__ebnf_1"))
    #expect(lowering.loweredSource.contains("%token NUMBER /[0-9]+/"))
    #expect(lowering.productionOrigins.count == first.grammar?.productions.count)
    #expect(lowering.productionOrigins.allSatisfy { $0.sourceRange.start.line <= 5 })
    let repetition = try #require(lowering.productionOrigins.first { $0.isSynthetic })
    #expect(repetition.sourceNonterminal == "expression")
    #expect(repetition.sourceRange.start.line == 4)
}

@Test func EBNFReportsUndefinedReferencesAtNativeSourceLocations() throws {
    let source = "expression = missing ;"
    let compilation = GrammarWorkbenchAPI.compile(.init(source: source, notation: .ebnf))
    let diagnostic = try #require(compilation.diagnostics.first { $0.code == "undefined-ebnf-symbol" })

    #expect(!compilation.succeeded)
    #expect(diagnostic.range.start.offset == 13)
    #expect(diagnostic.range.end.offset == 20)
    #expect(diagnostic.range.start.line == 1)
}

@Test func legacyLoweringJSONDefaultsToNoOriginMap() throws {
    let data = Data(#"{"notation":"EBNF","loweredSource":"%start S\nS : ;","syntheticNonterminals":[]}"#.utf8)
    let lowering = try JSONDecoder().decode(GrammarLoweringSnapshot.self, from: data)
    #expect(lowering.productionOrigins.isEmpty)
}

@Test func malformedEBNFProducesLocatedDiagnostics() {
    let compilation = GrammarWorkbenchAPI.compile(.init(
        source: "expression = [ term ;", notation: .ebnf
    ))

    #expect(!compilation.succeeded)
    #expect(compilation.diagnostics.first?.code == "invalid-ebnf")
    #expect(compilation.diagnostics.first?.range.start.line == 1)
}

@Test func legacyCompilationRequestsDefaultToWorkbenchNotation() throws {
    let data = Data(#"{"source":"%start S\nS : 'ok' ;","algorithm":"LALR(1)"}"#.utf8)
    let request = try JSONDecoder().decode(GrammarCompilationRequest.self, from: data)

    #expect(request.notation == .workbench)
    #expect(GrammarWorkbenchAPI.compile(request).succeeded)
}

@Test func notationPresentationUsesClearUIWordsWithoutChangingWireValues() throws {
    #expect(GrammarSourceNotation.workbench.displayName == "Yacc-like")
    #expect(GrammarSourceNotation.ebnf.displayName == "EBNF")
    #expect(GrammarSourceNotation.workbench.rawValue == "Workbench")
    let encoded = try JSONEncoder().encode(GrammarSourceNotation.workbench)
    #expect(String(decoding: encoded, as: UTF8.self) == "\"Workbench\"")
}

@Test func artifactDiffExplainsGrammarEvolution() throws {
    let previous = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'a' ;"))
    let current = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'a' | 'b' ;"))
    let difference = try current.diff(from: previous)

    #expect(difference.addedProductions == ["S → b"])
    #expect(difference.removedProductions.isEmpty)
    #expect(difference.addedTerminals == ["b"])
    #expect(difference.stateDelta > 0)
}

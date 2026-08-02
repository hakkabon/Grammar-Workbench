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

@Test func artifactDiffExplainsGrammarEvolution() throws {
    let previous = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'a' ;"))
    let current = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'a' | 'b' ;"))
    let difference = try current.diff(from: previous)

    #expect(difference.addedProductions == ["S → b"])
    #expect(difference.removedProductions.isEmpty)
    #expect(difference.addedTerminals == ["b"])
    #expect(difference.stateDelta > 0)
}

import Testing
@testable import GrammarWorkbench

private func artifact(_ source: String, algorithm: LRAlgorithm) throws -> GrammarArtifact {
    let result = GrammarFrontEnd.process(source)
    let grammar = try #require(result.grammar)
    let analysis = try #require(result.analysis)
    return LRConstructionEngine.construct(
        grammar: grammar,
        analysis: analysis,
        source: source,
        algorithm: algorithm
    )
}

@Test func canonicalLRHasMoreStatesThanMergedLALR() throws {
    let source = """
    %start S
    S : C C ;
    C : 'c' C | 'd' ;
    """
    let slr = try artifact(source, algorithm: .slr)
    let lalr = try artifact(source, algorithm: .lalr)
    let canonical = try artifact(source, algorithm: .canonical)
    #expect(slr.states.count == 7)
    #expect(lalr.states.count == 7)
    #expect(canonical.states.count == 10)
    #expect(canonical.states.flatMap(\.items).contains { $0.text.contains(", $") })
}

@Test func eachAlgorithmBuildsAnAcceptAction() throws {
    let source = "%start S\nS : 'id' ;"
    for algorithm in LRAlgorithm.allCases {
        let result = try artifact(source, algorithm: algorithm)
        #expect(result.cells.contains { $0.id.symbol == "$" && $0.actions == [.accept] })
    }
}

@Test func lalrMergingCanIntroduceReduceReduceConflict() throws {
    let source = """
    %start S
    S : 'a' A 'd' | 'b' A 'e' | 'a' B 'e' | 'b' B 'd' ;
    A : 'c' ;
    B : 'c' ;
    """
    let canonical = try artifact(source, algorithm: .canonical)
    let lalr = try artifact(source, algorithm: .lalr)
    #expect(!canonical.cells.contains { $0.isConflict })
    #expect(lalr.cells.contains { $0.isConflict })
    #expect(lalr.decisions.contains { $0.title.contains("Conflict") })
}

@Test func precedenceResolvesExpressionConflicts() throws {
    let source = """
    %start E
    %left '+'
    %left '*'
    E : E '+' E | E '*' E | 'id' ;
    """
    let result = try artifact(source, algorithm: .lalr)
    #expect(!result.cells.contains { $0.isConflict })
    #expect(result.decisions.count == 4)
    #expect(result.decisions.allSatisfy { $0.title.contains("Resolved decision") })
    #expect(result.decisions.contains { $0.explanation.contains("higher precedence") })
    #expect(result.decisions.contains { $0.explanation.contains("left associativity") })
}

@Test func nonassociativeOperatorCreatesErrorEntry() throws {
    let source = """
    %start E
    %nonassoc '<'
    E : E '<' E | 'id' ;
    """
    let result = try artifact(source, algorithm: .slr)
    let decision = try #require(result.decisions.first { $0.explanation.contains("nonassociativity") })
    #expect(result.cell(decision.cell) == nil)
}

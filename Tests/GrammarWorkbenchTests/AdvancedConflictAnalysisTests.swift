import Testing
@testable import GrammarWorkbench

private func conflictArtifact(_ source: String, algorithm: LRAlgorithm = .lalr) throws -> GrammarArtifact {
    let frontEnd = GrammarFrontEnd.process(source)
    return try LRConstructionEngine.construct(
        grammar: #require(frontEnd.grammar),
        analysis: #require(frontEnd.analysis),
        source: source,
        algorithm: algorithm
    )
}

@Test func expectDirectiveMarksExactConflictCountAsExpected() throws {
    let artifact = try conflictArtifact("""
    %start E
    %expect 1
    E : E '+' E | 'id' ;
    """)
    let expectation = try #require(artifact.conflictExpectation)
    #expect(expectation.expected == 1)
    #expect(expectation.actual == 1)
    #expect(expectation.matches)
    #expect(artifact.decisions.filter { artifact.cell($0.cell)?.isConflict == true }.allSatisfy { $0.isExpected })
}

@Test func expectMismatchReportsExpectedAndActualCounts() throws {
    let artifact = try conflictArtifact("""
    %start E
    %expect 0
    E : E '+' E | 'id' ;
    """)
    let expectation = try #require(artifact.conflictExpectation)
    #expect(!expectation.matches)
    #expect(expectation.expected == 0)
    #expect(expectation.actual == 1)
    #expect(!artifact.decisions.contains { $0.isExpected })
}

@Test func minimalCounterexampleAcceptsBothAmbiguousBranchesWithDifferentTrees() throws {
    let artifact = try conflictArtifact("""
    %start E
    E : E '+' E | 'id' ;
    """)
    let decision = try #require(artifact.decisions.first { artifact.cell($0.cell)?.isConflict == true })
    #expect(decision.witness == ["id", "+", "id", "+", "id"])
    #expect(decision.branchAnalyses.count == 2)
    #expect(decision.branchAnalyses.allSatisfy { $0.outcome == "Accepted branch" })
    let trees = Set(decision.branchAnalyses.compactMap(\.tree))
    #expect(trees.count == 2)
    #expect(decision.branchAnalyses.allSatisfy { !$0.trace.isEmpty })
}

@Test func precedenceProvenanceRecordsBothSidesAndSelectedAction() throws {
    let artifact = try conflictArtifact("""
    %start E
    %left '+'
    %left '*'
    E : E '+' E | E '*' E | 'id' ;
    """)
    let higherLookahead = try #require(artifact.decisions.first {
        $0.provenance?.lookahead == "*" && $0.provenance?.productionSymbol == "+"
    }?.provenance)
    #expect(higherLookahead.kind == .shift)
    #expect(higherLookahead.lookaheadLevel == 2)
    #expect(higherLookahead.productionLevel == 1)
    guard case .shift = higherLookahead.selectedAction else {
        Issue.record("Expected selected shift action")
        return
    }

    let leftAssociative = try #require(artifact.decisions.first {
        $0.provenance?.lookahead == "+" && $0.provenance?.productionSymbol == "+"
    }?.provenance)
    #expect(leftAssociative.kind == .reduce)
    #expect(leftAssociative.associativity == .left)
}

@Test func nonassociativeProvenanceRecordsErrorResolution() throws {
    let artifact = try conflictArtifact("""
    %start E
    %nonassoc '<'
    E : E '<' E | 'id' ;
    """)
    let provenance = try #require(artifact.decisions.first?.provenance)
    #expect(provenance.kind == .nonassociativeError)
    #expect(provenance.selectedAction == nil)
}

@Test func invalidExpectDirectiveIsSourceLocated() {
    let result = GrammarFrontEnd.process("%start S\n%expect many\nS : 'id' ;")
    #expect(result.diagnostics.contains {
        $0.code == "invalid-expect" && $0.range.start.line == 2
    })
}

@Test func standaloneExportIncludesExpectationProvenanceAndBranchTrees() throws {
    let artifact = try conflictArtifact("""
    %start E
    %expect 1
    E : E '+' E | 'id' ;
    """)
    let html = HTMLExporter.render(artifact)
    #expect(html.contains("%expect 1"))
    #expect(html.contains("Minimal counterexample"))
    #expect(html.contains("<strong>Resolution:</strong>"))
    #expect(html.contains("Action r1"))
    #expect(html.contains("Action s"))
}

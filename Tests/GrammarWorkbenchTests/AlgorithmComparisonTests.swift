import Foundation
import Testing
import GrammarWorkbench

@Test func comparisonReportsMetricsAndCanonicalMergeGroups() throws {
    let source = """
    %start S
    S : C C ;
    C : 'c' C | 'd' ;
    """
    let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
    let comparison = try compilation.compareAlgorithms()

    #expect(comparison.metric(for: .slr)?.states == 7)
    #expect(comparison.metric(for: .lalr)?.states == 7)
    #expect(comparison.metric(for: .canonical)?.states == 10)
    #expect(comparison.stateCorrespondences.contains { $0.isCanonicalMerge })
    #expect(comparison.stateCorrespondences.flatMap(\.canonicalStates).count == 10)
    #expect(comparison.recommendedAlgorithm == .slr)

    let data = try JSONEncoder().encode(comparison)
    #expect(try JSONDecoder().decode(GrammarAlgorithmComparison.self, from: data) == comparison)
}

@Test func comparisonExplainsLALRMergeInducedConflict() throws {
    let source = """
    %start S
    S : 'a' A 'd' | 'b' A 'e' | 'a' B 'e' | 'b' B 'd' ;
    A : 'c' ;
    B : 'c' ;
    """
    let comparison = try GrammarWorkbenchAPI.compile(.init(source: source)).compareAlgorithms()
    let lalr = try #require(comparison.metric(for: .lalr))
    let canonical = try #require(comparison.metric(for: .canonical))
    #expect(lalr.unresolvedConflicts > canonical.unresolvedConflicts)
    #expect(comparison.recommendedAlgorithm == .canonical)
    #expect(comparison.tableDifferences.contains { difference in
        difference.kind == .conflict
            && difference.lalr.contains(where: \.isConflict)
            && !difference.canonical.contains(where: \.isConflict)
    })
}

@Test func comparisonIsStableAcrossSelectedStartingAlgorithm() throws {
    let source = "%start E\n%left '+'\nE : E '+' E | 'id' ;"
    let lalr = try GrammarWorkbenchAPI.compile(.init(source: source, algorithm: .lalr)).compareAlgorithms()
    let canonical = try GrammarWorkbenchAPI.compile(.init(source: source, algorithm: .canonical)).compareAlgorithms()
    #expect(lalr == canonical)
}

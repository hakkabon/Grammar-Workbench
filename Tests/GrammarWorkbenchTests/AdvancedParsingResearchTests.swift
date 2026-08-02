import Testing
import GrammarWorkbench

private let ambiguousExpressionGrammar = """
%start E
E : E '+' E | 'id' ;
"""

@Test func generalizedParserPreservesAmbiguousAlternatives() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: ambiguousExpressionGrammar))
    #expect(compilation.parse("id + id + id", options: .init(enablesRecovery: false)).status == .conflict)

    let result = compilation.parseGeneralized("id + id + id")
    #expect(result.status == .ambiguous)
    #expect(result.alternatives.count == 2)
    #expect(Set(result.alternatives.map { $0.rendered() }).count == 2)
    #expect(result.metrics.branchPoints > 0)
    #expect(!result.wasTruncated)
}

@Test func generalizedParserCanExposeAmbiguityHiddenByPrecedence() {
    let grammar = """
    %start E
    %left '+'
    E : E '+' E | 'id' ;
    """
    let compilation = GrammarWorkbenchAPI.compile(.init(source: grammar))
    let deterministic = compilation.parseGeneralized("id + id + id")
    let research = compilation.parseGeneralized(
        "id + id + id", options: .init(exploresResolvedConflicts: true)
    )
    #expect(deterministic.status == .accepted)
    #expect(deterministic.alternatives.count == 1)
    #expect(research.status == .ambiguous)
    #expect(research.alternatives.count == 2)
}

@Test func generalizedParserReportsBoundsWithoutLosingAcceptedWork() {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: ambiguousExpressionGrammar))
    let result = compilation.parseGeneralized(
        "id + id + id + id", options: .init(maximumTrees: 1)
    )
    #expect(result.status == .truncated)
    #expect(result.wasTruncated)
    #expect(result.alternatives.count == 1)
}

@Test func treeLimitDoesNotTruncateAnExactlySizedForest() {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'id' ;"))
    let result = compilation.parseGeneralized("id", options: .init(maximumTrees: 1))
    #expect(result.status == .accepted)
    #expect(!result.wasTruncated)
}

@Test func generalizedParserPreservesLexemesAndRanges() {
    let grammar = "%token ID /[a-z]+/\n%skip /\\s+/\n%start S\nS : ID ;"
    let result = GrammarWorkbenchAPI.compile(.init(source: grammar)).parseGeneralized("hello")
    #expect(result.status == .accepted)
    #expect(result.alternatives.first?.descendants(named: "ID").first?.token?.lexeme == "hello")
    #expect(result.alternatives.first?.range?.start.offset == 0)
    #expect(result.alternatives.first?.range?.end.offset == 5)
}

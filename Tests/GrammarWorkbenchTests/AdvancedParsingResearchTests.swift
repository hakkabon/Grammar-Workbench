import Foundation
import Testing
import GrammarWorkbench

private let ambiguousExpressionGrammar = """
%start E
E : E '+' E | 'id' ;
"""

private struct ForestReducer: GrammarSemanticReducer {
    func terminal(_ token: GrammarInputTokenSnapshot, node: GrammarSyntaxNode) -> String {
        token.lexeme
    }

    func missing(symbol: String, node: GrammarSyntaxNode) -> String { "<\(symbol)>" }

    func reduce(
        production: GrammarProductionSnapshot,
        children: [String],
        node: GrammarSyntaxNode
    ) -> String {
        production.rhs.count == 3 ? "(\(children.joined()))" : children.joined()
    }
}

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

@Test func generalizedForestHasStableAlternativeIdentitiesAndLookup() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: ambiguousExpressionGrammar))
    let first = compilation.parseGeneralized("id + id + id")
    let second = compilation.parseGeneralized("id + id + id")

    #expect(first.forest.isAmbiguous)
    #expect(first.forest.alternatives.map(\.id) == second.forest.alternatives.map(\.id))
    let alternative = try #require(first.forest.alternatives.first)
    #expect(first.alternative(id: alternative.id)?.tree == alternative.tree)
}

@Test func generalizedRejectionReportsFurthestExpectedTerminals() throws {
    let grammar = "%start S\nS : 'a' 'b' ;"
    let result = GrammarWorkbenchAPI.compile(.init(source: grammar)).parseGeneralized("a a")

    #expect(result.status == .rejected)
    #expect(result.metrics.furthestTokenIndex == 1)
    let diagnostic = try #require(result.syntaxDiagnostics.first)
    #expect(diagnostic.tokenIndex == 1)
    #expect(diagnostic.unexpected == "a")
    #expect(diagnostic.expected == ["b"])
}

@Test func generalizedLimitsReportTheirExactCause() {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: ambiguousExpressionGrammar))
    let steps = compilation.parseGeneralized(
        "id + id + id", options: .init(maximumSteps: 1)
    )
    let configurations = compilation.parseGeneralized(
        "id + id + id", options: .init(maximumConfigurations: 1)
    )

    #expect(steps.status == .truncated)
    #expect(steps.reachedLimits == [.steps])
    #expect(configurations.status == .truncated)
    #expect(configurations.reachedLimits.contains(.configurations))
}

@Test func generalizedSearchStrategiesPreserveTheAcceptedForest() {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: ambiguousExpressionGrammar))
    let depthFirst = compilation.parseGeneralized(
        "id + id + id", options: .init(searchStrategy: .depthFirst)
    )
    let breadthFirst = compilation.parseGeneralized(
        "id + id + id", options: .init(searchStrategy: .breadthFirst)
    )

    #expect(Set(depthFirst.forest.alternatives.map(\.id)) == Set(breadthFirst.forest.alternatives.map(\.id)))
    #expect(depthFirst.metrics.shiftActions > 0)
    #expect(depthFirst.metrics.reductionActions > 0)
    #expect(depthFirst.metrics.acceptActions == 2)
}

@Test func generalizedResultRoundTripsItsEngineeringMetadata() throws {
    let result = GrammarWorkbenchAPI.compile(.init(source: ambiguousExpressionGrammar))
        .parseGeneralized("id + id + id")
    let decoded = try JSONDecoder().decode(
        GrammarGeneralizedParseResult.self,
        from: JSONEncoder().encode(result)
    )

    #expect(decoded == result)
    #expect(decoded.forest.alternatives.count == 2)
}

@Test func legacyGeneralizedOptionsDefaultToDepthFirstSearch() throws {
    let data = Data(#"{"maximumConfigurations":12,"maximumSteps":34,"maximumTrees":5,"exploresResolvedConflicts":true}"#.utf8)
    let options = try JSONDecoder().decode(GrammarGeneralizedParseOptions.self, from: data)

    #expect(options.maximumConfigurations == 12)
    #expect(options.exploresResolvedConflicts)
    #expect(options.searchStrategy == .depthFirst)
}

@Test func generalizedCancellableEntryPointHonorsTaskCancellation() async {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: ambiguousExpressionGrammar))
    let task = Task {
        await compilation.parseGeneralizedCancellable(
            Array(repeating: "id", count: 30).joined(separator: " + "),
            options: .init(maximumConfigurations: 100_000, maximumSteps: 1_000_000)
        )
    }
    task.cancel()
    let result = await task.value

    #expect(result.status == .cancelled)
    #expect(result.wasCancelled)
    #expect(!result.wasTruncated)
}

@Test func generalizedForestEvaluatesEverySemanticAlternative() throws {
    let semantic = try GrammarWorkbenchAPI.compile(.init(source: ambiguousExpressionGrammar))
        .parseGeneralized("id + id + id", using: ForestReducer())

    #expect(semantic.parse.status == .ambiguous)
    #expect(semantic.alternatives.count == 2)
    #expect(Set(semantic.alternatives.map(\.value)).count == 2)
    #expect(semantic.alternatives.map(\.id) == semantic.parse.forest.alternatives.map(\.id))
}

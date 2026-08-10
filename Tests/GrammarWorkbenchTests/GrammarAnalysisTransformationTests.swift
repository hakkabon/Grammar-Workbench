import Foundation
import Testing
@testable import GrammarWorkbench

@Test func structuralAnalysisExplainsHygieneCyclesAndLeftRecursion() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: """
    %start S
    %token UNUSED
    S : A ;
    A : B | 'a' ;
    B : A | ;
    Dead : Dead ;
    """))
    let analysis = try GrammarEngineering.analyze(compilation)

    #expect(analysis.reachableNonterminals == ["A", "B", "S"])
    #expect(analysis.unreachableNonterminals == ["Dead"])
    #expect(analysis.unproductiveNonterminals == ["Dead"])
    #expect(analysis.nullableNonterminals.contains("B"))
    #expect(analysis.indirectlyLeftRecursiveComponents.contains(["A", "B"]))
    #expect(analysis.stronglyConnectedComponents.contains(["A", "B"]))
    #expect(analysis.unusedTerminals.contains("UNUSED"))
    #expect(analysis.first["S"]?.contains("a") == true)
}

@Test func duplicateAnalysisRetainsEveryProductionIdentity() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: """
    %start S
    S : 'ok' ;
    S : 'ok' ;
    S : 'ok' ;
    """))
    let analysis = try GrammarEngineering.analyze(compilation)
    let duplicate = try #require(analysis.duplicateProductions.first)

    #expect(duplicate.text == "S → ok")
    #expect(duplicate.productionIDs == [0, 1, 2])
    #expect(analysis.statistics.duplicateProductions == 2)
}

@Test func transformationPlansAreExplainableAndRejectStaleSource() throws {
    let source = "%start S\nS : 'ok' ;\nUnused : 'no' ;"
    let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
    let plan = try GrammarEngineering.plan(.removeUnreachableProductions, for: compilation)

    #expect(plan.hasChanges)
    #expect(plan.affectedLines == [3])
    #expect(plan.operations.allSatisfy { $0.assurance == .languagePreserving })
    #expect(plan.operations.first?.reason.contains("start symbol") == true)
    #expect(throws: GrammarTransformationError.self) {
        try GrammarEngineering.apply(plan, to: source + "\n")
    }
}

@Test func transformationExecutionChecksGeneratedAndRecordedBehavior() throws {
    let source = "%start S\nS : 'ok' | 'other' ;\nUnused : 'no' ;"
    let request = GrammarCompilationRequest(source: source)
    let compilation = GrammarWorkbenchAPI.compile(request)
    let plan = try GrammarEngineering.plan(.removeUnreachableProductions, for: compilation)
    let result = try GrammarEngineering.execute(
        plan,
        request: request,
        corpus: [.init(input: "ok", origin: "sample")],
        tests: [
            .init(name: "ok", input: "ok", expectation: .accept),
            .init(name: "bad", input: "bad", expectation: .reject)
        ]
    )

    #expect(result.isSafeToApply)
    #expect(result.behavior.agreesOnCorpus)
    #expect(result.behavior.generatedInputs >= 2)
    #expect(result.testsAfter?.allPassed == true)
    #expect(result.artifactDiff?.removedProductions.contains("Unused → no") == true)
    #expect(!result.proposedSource.contains("Unused"))
}

@Test func boundedComparisonFindsAConcreteLanguageDifference() {
    let before = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'a' ;"))
    let after = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'b' ;"))
    let comparison = GrammarEngineering.compare(
        before, after,
        corpus: [.init(input: "a", origin: "regression"), .init(input: "b", origin: "regression")]
    )

    #expect(!comparison.agreesOnCorpus)
    #expect(comparison.discrepancies.map(\.input).sorted() == ["a", "b"])
    #expect(comparison.conclusion.contains("differ"))
}

@Test func unproductiveCleanupNeverSilentlyDeletesTheStartSymbol() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: """
    %start S
    S : S ;
    Dead : Dead ;
    """))
    let plan = try GrammarEngineering.plan(.removeUnproductiveProductions, for: compilation)

    #expect(plan.operations.flatMap(\.symbols) == ["Dead"])
    #expect(!plan.affectedLines.contains(2))
}

@Test func unproductiveCleanupRemovesSeparateReferencesButProtectsMixedDeclarations() throws {
    let separateSource = "%start S\nS : Dead ;\nS : 'ok' ;\nDead : Dead ;"
    let separate = GrammarWorkbenchAPI.compile(.init(source: separateSource))
    let separatePlan = try separate.transformationPlan(.removeUnproductiveProductions)
    let separateResult = try GrammarEngineering.execute(
        separatePlan, request: .init(source: separateSource), corpus: [.init(input: "ok")]
    )
    #expect(separatePlan.affectedLines == [2, 4])
    #expect(separateResult.isSafeToApply)

    let mixedSource = "%start S\nS : Dead | 'ok' ;\nDead : Dead ;"
    let mixed = GrammarWorkbenchAPI.compile(.init(source: mixedSource))
    let mixedPlan = try mixed.transformationPlan(.removeUnproductiveProductions)
    #expect(!mixedPlan.hasChanges)
    let proposed = try GrammarEngineering.apply(mixedPlan, to: mixedSource)
    #expect(proposed == mixedSource)
}

@Test func sourceTransformationRequiresNativeWorkbenchNotation() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(
        source: "root = \"ok\" ;", notation: .ebnf
    ))
    #expect(throws: GrammarTransformationError.self) {
        try GrammarEngineering.plan(.removeDuplicateProductions, for: compilation)
    }
}

@Test func multilineDeclarationsAreRemovedAsOneSourceOperation() throws {
    let source = """
    %start S
    S : 'ok' ;
    Dead :
        'unused'
      | 'other'
      ;
    """
    let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
    let plan = try compilation.transformationPlan(.removeUnreachableProductions)
    let proposed = try GrammarEngineering.apply(plan, to: source)

    #expect(plan.affectedLines == [3, 4, 5, 6])
    #expect(!proposed.contains("unused"))
    #expect(GrammarWorkbenchAPI.compile(.init(source: proposed)).succeeded)
}

@Test func sameLineDuplicateAlternativeIsReportedButNotDestructivelyPlanned() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'ok' | 'ok' ;"))
    let analysis = try compilation.structuralAnalysis()
    let plan = try compilation.transformationPlan(.removeDuplicateProductions)

    #expect(analysis.duplicateProductions.count == 1)
    #expect(!plan.hasChanges)
}

@Test func structuralReportsAndPlansHaveStableCodableForms() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'ok' ;"))
    let analysis = try GrammarEngineering.analyze(compilation)
    let plan = try GrammarEngineering.plan(.removeDuplicateProductions, for: compilation)

    let encodedAnalysis = try JSONEncoder().encode(analysis)
    let encodedPlan = try JSONEncoder().encode(plan)
    #expect(try JSONDecoder().decode(GrammarStructuralAnalysis.self, from: encodedAnalysis) == analysis)
    #expect(try JSONDecoder().decode(GrammarTransformationPlan.self, from: encodedPlan) == plan)
}

@Test func projectWorkspaceValidatesGrammarCleanupAgainstProjectSourcesAndTests() async throws {
    let workspace = try GrammarProjectWorkspace(manifest: .init(
        name: "Cleanup",
        grammar: .init(source: "%start S\nS : 'ok' ;\nDead : 'unused' ;"),
        sources: [.init(id: "main", path: "Sources/main.txt", text: "ok")],
        tests: [.init(name: "accept", input: "ok", expectation: .accept)]
    ))

    let analysis = try await workspace.structuralGrammarAnalysis()
    let preview = try await workspace.previewGrammarTransformation(.removeUnreachableProductions)

    #expect(analysis.unreachableNonterminals == ["Dead"])
    #expect(preview.isSafeToApply)
    #expect(preview.behavior.cases.contains { $0.origin == "Sources/main.txt" })
}

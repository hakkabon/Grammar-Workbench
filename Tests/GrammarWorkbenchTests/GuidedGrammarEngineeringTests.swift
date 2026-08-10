import Testing
@testable import GrammarWorkbench

@Test func guidancePrioritizesErrorsInPlainLanguage() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(
        source: "%start S\n%token ID\nS : Missing ;"
    ))
    let report = GrammarGuidanceEngine.assess(compilation)

    #expect(report.summary.errors == 1)
    #expect(report.summary.healthScore < 100)
    #expect(report.nextAction?.severity == .critical)
    #expect(report.nextAction?.title == "Define a referenced symbol")
    #expect(report.nextAction?.destination == .editor)
    #expect(report.nextAction?.sourceRange != nil)
}

@Test func healthyGrammarOffersTestsAndParserReadiness() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'ok' ;"))
    let report = GrammarGuidanceEngine.assess(compilation, sampleInput: "ok")

    #expect(report.summary.healthScore == 100)
    #expect(report.summary.headline.contains("healthy"))
    #expect(report.findings.contains { $0.id == "add-tests" && $0.destination == .tests })
    #expect(report.findings.contains { $0.id == "ready" && $0.severity == .ready })
}

@Test func unresolvedConflictBecomesAnInterpretationTask() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(
        source: "%start E\nE : E '+' E | 'id' ;"
    ))
    let report = GrammarGuidanceEngine.assess(compilation, sampleInput: "id + id + id")

    #expect(report.summary.unresolvedConflicts == 1)
    #expect(report.nextAction?.destination == .decisions)
    #expect(report.nextAction?.title.contains("interpreted") == true)
}

@Test func duplicateCleanupPreviewRecompilesAndProtectsBehavior() throws {
    let source = """
    %start S
    S : 'ok' ;
    S : 'ok' ;
    """
    let preview = GrammarGuidanceEngine.preview(
        .removeDuplicateProductionLines,
        request: .init(source: source),
        examples: [.init(name: "Valid", input: "ok")],
        tests: [.init(name: "Accept ok", input: "ok", expectation: .accept)]
    )

    #expect(preview.hasChanges)
    #expect(preview.removedLines == [3])
    #expect(preview.isSafeToApply)
    #expect(preview.regressedExamples.isEmpty)
    #expect(preview.changedExamples.count == 1)
    #expect(preview.testsAfter?.allPassed == true)
    #expect(GrammarWorkbenchAPI.compile(.init(source: preview.proposedSource)).succeeded)
}

@Test func unreachableCleanupReportsItsArtifactImpact() throws {
    let source = """
    %start S
    S : 'ok' ;
    Dead : 'unused' ;
    """
    let preview = GrammarGuidanceEngine.preview(
        .removeUnreachableProductionLines,
        request: .init(source: source),
        examples: [.init(name: "Valid", input: "ok")]
    )

    #expect(preview.isSafeToApply)
    #expect(preview.artifactDiff?.removedProductions.contains("Dead → unused") == true)
    #expect(!preview.proposedSource.contains("Dead"))
}

@MainActor @Test func explorerStoreSharesGuidanceWithTheNativeWorkspace() {
    let store = ExplorerStore(source: "%start E\nE : E '+' E | 'id' ;")
    let report = store.guidance(tests: [])

    #expect(report.summary.unresolvedConflicts == 1)
    store.selectGuidance(report.nextAction!)
}

import Foundation
import Testing
@testable import GrammarWorkbenchCore
@testable import GrammarWorkbench

@Test func selectedResearchCatalogHasFocusedStableStudies() {
    let studies = GrammarSelectedResearchCatalog.studies
    #expect(studies.map(\.id) == [
        "ambiguity-growth", "precedence-hidden-ambiguity", "search-reproducibility"
    ])
    #expect(Set(studies.map(\.category)).count == 3)
    #expect(studies.allSatisfy { !$0.question.isEmpty && !$0.context.isEmpty })
    #expect(studies.allSatisfy { GrammarSelectedResearchCatalog.study(id: $0.id) == $0 })
}

@Test(arguments: GrammarSelectedResearchCatalog.studies)
func selectedResearchStudiesProducePlainLanguagePassingPreviews(
    study: GrammarSelectedResearchStudy
) throws {
    let preview = try GrammarSelectedResearchPreviewEngine.run(study)
    #expect(preview.passed)
    #expect(preview.studyID == study.id)
    #expect(preview.report.passed)
    #expect(preview.observations.count >= preview.report.cases.count * 2 + 1)
    #expect(preview.observations.allSatisfy { $0.passed })
    #expect(preview.observations.last?.id == "reproducibility")
    #expect(preview.limitations.count == 3)
}

@Test func selectedResearchPreviewRoundTripsWithInspectableEvidence() throws {
    let preview = try GrammarSelectedResearchPreviewEngine.run(
        GrammarSelectedResearchCatalog.precedence
    )
    let decoded = try JSONDecoder().decode(
        GrammarSelectedResearchPreview.self, from: JSONEncoder().encode(preview)
    )
    #expect(decoded == preview)
    #expect(decoded.report.cases.first?.deterministicStatus == .accepted)
    #expect(decoded.report.cases.first?.generalizedStatus == .ambiguous)
    #expect(decoded.report.cases.first?.derivationCount == 2)
}

@Test func selectedResearchPreviewRejectsUnknownStudyIdentifiers() {
    #expect(throws: GrammarSelectedResearchPreviewError.self) {
        try GrammarSelectedResearchPreviewEngine.run(studyID: "unknown")
    }
}

@Test func researchStudyExplorerRunsAndRoundTripsTheCompleteCatalog() throws {
    let report = try GrammarResearchStudyExplorerEngine.runCatalog()
    #expect(report.passed)
    #expect(report.reproducible)
    #expect(report.studies.map(\.studyID) == GrammarSelectedResearchCatalog.studies.map(\.id))
    #expect(report.supportedStudies == report.studies.count)
    #expect(report.totalCases == report.studies.reduce(0) { $0 + $1.report.cases.count })
    #expect(report.representedDerivations > 0)

    let decoded = try GrammarResearchStudyExplorerCodec.decode(
        GrammarResearchStudyExplorerCodec.encode(report)
    )
    #expect(decoded == report)
    #expect(decoded.evidenceFingerprint == report.evidenceFingerprint)
}

@Test func researchStudyExplorerRejectsTamperedAggregateEvidence() throws {
    let data = try GrammarResearchStudyExplorerCodec.encode(
        GrammarResearchStudyExplorerEngine.runCatalog()
    )
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["evidenceFingerprint"] = "0000000000000000"
    let tampered = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: GrammarResearchStudyExplorerError.self) {
        try GrammarResearchStudyExplorerCodec.decode(tampered)
    }
}

#if os(macOS)
@MainActor
@Test func explorerStoreRunsAndResetsSelectedResearchPreviews() async throws {
    let store = ExplorerStore()
    store.selectResearchStudy("precedence-hidden-ambiguity")
    #expect(store.selectedResearchPreview == nil)
    store.runSelectedResearchPreview()
    #expect(store.activeOperations.contains { $0.kind == .previewingResearch })
    for _ in 0..<100 where store.isRunningSelectedResearch {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(store.selectedResearchPreview?.studyID == "precedence-hidden-ambiguity")
    #expect(store.selectedResearchPreview?.passed == true)
    store.selectResearchStudy("search-reproducibility")
    #expect(store.selectedResearchPreview == nil)
    #expect(store.selectedResearchError == nil)

    store.runResearchStudyExplorer()
    for _ in 0..<200 where store.isRunningSelectedResearch {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(store.researchStudyReport?.passed == true)
    #expect(store.selectedResearchPreview?.studyID == "search-reproducibility")
}
#endif

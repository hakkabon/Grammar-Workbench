import Foundation
import Testing
@testable import GrammarWorkbench

private func researchProgramme() -> GrammarResearchProgramme {
    .init(
        id: "org.grammar-workbench.parser-baseline",
        title: "Parser validation baseline",
        rationale: "Falsify regressions in recognition, ambiguity preservation, and search invariance.",
        repetitions: 3,
        cases: [
            .init(
                id: "unambiguous", name: "Unambiguous recognition",
                hypothesis: "Both engines recognize one derivation.",
                grammar: .init(source: "%start S\nS : 'ok' ;"), input: "ok",
                expectation: .init(
                    deterministicStatus: .accepted, generalizedStatus: .accepted,
                    minimumDerivations: 1, maximumDerivations: 1
                )
            ),
            .init(
                id: "ambiguous", name: "Catalan ambiguity",
                hypothesis: "Three operands retain exactly two derivations regardless of search order.",
                grammar: .init(source: "%start E\nE : E '+' E | 'id' ;"),
                input: "id + id + id",
                expectation: .init(
                    deterministicStatus: .conflict, generalizedStatus: .ambiguous,
                    minimumDerivations: 2, maximumDerivations: 2
                )
            ),
            .init(
                id: "rejected", name: "Rejection agreement",
                hypothesis: "Both engines reject an incomplete sentence.",
                grammar: .init(source: "%start S\nS : 'a' 'b' ;"), input: "a a",
                expectation: .init(
                    deterministicStatus: .rejected, generalizedStatus: .rejected,
                    minimumDerivations: 0, maximumDerivations: 0
                )
            )
        ]
    )
}

@Test func researchProgrammeProducesStablePassingEvidence() throws {
    let programme = researchProgramme()
    let first = try GrammarResearchValidator.run(programme)
    let second = try GrammarResearchValidator.run(programme)
    #expect(first.passed)
    #expect(first.passedCases == 3)
    #expect(first.programmeFingerprint == second.programmeFingerprint)
    #expect(first.evidenceFingerprint == second.evidenceFingerprint)
    #expect(first.cases.map(\.evidenceFingerprint) == second.cases.map(\.evidenceFingerprint))
    #expect(first.cases.allSatisfy { $0.searchStrategiesAgree })
    #expect(first.cases.allSatisfy { $0.repetitionsStable })
    #expect(first.cases.allSatisfy { $0.timing.samples == 3 })
}

@Test func researchProgrammeReportsFalsifiedHypothesesWithoutTrapping() throws {
    let programme = GrammarResearchProgramme(
        id: "falsified", title: "Falsified", rationale: "Test failure evidence.",
        cases: [.init(
            id: "wrong", name: "Wrong expectation", hypothesis: "An ambiguous grammar is unique.",
            grammar: .init(source: "%start E\nE : E '+' E | 'id' ;"),
            input: "id + id + id",
            expectation: .init(generalizedStatus: .accepted, maximumDerivations: 1)
        )]
    )
    let report = try GrammarResearchValidator.run(programme)
    #expect(!report.passed)
    #expect(report.cases.first?.failures.count == 2)
}

@Test func researchProgrammeAndReportRoundTripThroughValidatedCodecs() throws {
    let programme = researchProgramme()
    let decoded = try GrammarResearchProgrammeCodec.decode(
        GrammarResearchProgrammeCodec.encode(programme)
    )
    #expect(decoded == programme)
    let report = try GrammarResearchValidator.run(decoded)
    #expect(try GrammarResearchProgrammeCodec.decodeReport(
        GrammarResearchProgrammeCodec.encode(report)
    ) == report)
}

@Test func researchProgrammeRejectsDuplicateCasesAndInvertedRanges() {
    let item = GrammarResearchCase(
        id: "same", name: "Same", hypothesis: "Invalid fixture.",
        grammar: .init(source: "%start S\nS : 'ok' ;"), input: "ok",
        expectation: .init(minimumDerivations: 2, maximumDerivations: 1)
    )
    let programme = GrammarResearchProgramme(
        id: "invalid", title: "Invalid", rationale: "Invalid fixture.", cases: [item, item]
    )
    #expect(throws: GrammarResearchValidationError.self) {
        try GrammarResearchProgrammeCodec.encode(programme)
    }
}

@Test func packagedResearchProgrammePassesAndComparisonSeparatesEvidenceFromTiming() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let programme = try GrammarResearchProgrammeCodec.decode(
        Data(contentsOf: root.appendingPathComponent("Examples/ResearchValidationProgramme.json"))
    )
    let baseline = try GrammarResearchValidator.run(programme)
    let candidate = try GrammarResearchValidator.run(programme)
    #expect(baseline.passed)
    #expect(baseline.cases.count == 4)
    let comparison = GrammarResearchValidator.compare(baseline: baseline, candidate: candidate)
    #expect(comparison.compatibleProgramme)
    #expect(comparison.regressions.isEmpty)
    #expect(comparison.evidenceChanges.isEmpty)
}

@Test func researchReportCodecRejectsTamperedEvidence() throws {
    let report = try GrammarResearchValidator.run(researchProgramme())
    var object = try #require(JSONSerialization.jsonObject(
        with: GrammarResearchProgrammeCodec.encode(report)
    ) as? [String: Any])
    object["evidenceFingerprint"] = "tampered"
    #expect(throws: GrammarResearchValidationError.self) {
        try GrammarResearchProgrammeCodec.decodeReport(
            JSONSerialization.data(withJSONObject: object)
        )
    }
}

import Foundation
import Parser
import Testing
@testable import GrammarWorkbenchCore

@Test func recoveryTruthProgrammeCoversEveryDeterministicOutcome() throws {
    let report = try GrammarRecoveryTruthProgramme.run()

    #expect(report.schemaVersion == 1)
    #expect(report.kind == "grammar-workbench-recovery-truth-report")
    #expect(report.parserContractSchemaVersion == ParseContractSnapshot.currentSchemaVersion)
    #expect(report.passed)
    #expect(report.cases.map(\.id) == [
        "insert-missing-terminal",
        "delete-unexpected-terminal",
        "skip-to-synchronization",
        "diagnostic-limit-remains-rejected",
    ])
    #expect(report.cases.dropLast().allSatisfy {
        $0.parseStatus == .acceptedWithRecovery
            && $0.strictReparseStatus == .accepted
            && $0.contract.status == .recovered
            && !$0.contract.recoveryEdits.isEmpty
    })
    #expect(report.cases.last?.parseStatus == .rejected)
    #expect(report.cases.last?.contract.status == .rejected)
}

@Test func publicParseResultCarriesReplayableRecoveryEdits() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(
        source: "%start S\nS : 'id' '+' 'id' ;"
    ))

    let insertion = compilation.parse("id id")
    #expect(insertion.recoveryEdits == [.insert(terminal: "+", atToken: 1)])
    #expect(try insertion.recoveryEdits.applying(to: insertion.tokens.map(\.kind)) == ["id", "+", "id"])

    let deletion = compilation.parse("id extra + id")
    #expect(deletion.recoveryEdits == [.delete(terminal: "extra", atToken: 1)])
    #expect(try deletion.recoveryEdits.applying(to: deletion.tokens.map(\.kind)) == ["id", "+", "id"])

    let synchronization = GrammarWorkbenchAPI.compile(.init(
        source: "%start S\nS : 'id' ;"
    )).parse("id junk more")
    #expect(synchronization.recoveryEdits == [
        .skip(terminals: ["junk", "more"], fromToken: 1)
    ])
    #expect(try synchronization.recoveryEdits.applying(to: synchronization.tokens.map(\.kind)) == ["id"])

    let multiple = compilation.parse("junk id junk id")
    #expect(multiple.recoveryEdits == [
        .delete(terminal: "junk", atToken: 0),
        .insert(terminal: "+", atToken: 2),
        .delete(terminal: "junk", atToken: 2),
    ])
    #expect(try multiple.recoveryEdits.applying(to: multiple.tokens.map(\.kind)) == ["id", "+", "id"])
}

@Test func recoveryReplayRejectsEvidenceThatDoesNotMatchInput() {
    #expect(throws: GrammarRecoveryReplayError.deletionMismatch(expected: "other", actual: "junk")) {
        try [GrammarRecoveryEdit.delete(terminal: "other", atToken: 1)]
            .applying(to: ["id", "junk"])
    }
    #expect(throws: GrammarRecoveryReplayError.skipMismatch(
        expected: ["wrong"], actual: ["junk"]
    )) {
        try [GrammarRecoveryEdit.skip(terminals: ["wrong"], fromToken: 1)]
            .applying(to: ["id", "junk"])
    }
}

@Test func verifierRejectsRecoveredStatusWithoutRecoveryEvidence() {
    let result = GrammarParseResult(
        status: .acceptedWithRecovery, message: "Accepted", tokens: [],
        expectedTerminals: [], tree: nil, syntaxTree: nil, trace: [],
        conflictState: nil, conflictSymbol: nil, diagnostics: [], recoveryEdits: []
    )

    let checked = GrammarRecoveryTruthVerifier.verify(
        id: "false-claim", input: "", result: result
    )
    #expect(!checked.passed)
    #expect(checked.violations.map(\.code).contains("recovered-without-edit"))
    #expect(checked.violations.map(\.code).contains("strict-reparse-missing"))
}

@Test func recoveryEditsRoundTripAndLegacyResultsDefaultToNoEdits() throws {
    let report = try GrammarRecoveryTruthProgramme.run()
    let data = try JSONEncoder().encode(report)
    #expect(try JSONDecoder().decode(GrammarRecoveryTruthProgrammeReport.self, from: data) == report)

    let legacy = Data(#"{"status":"accepted","message":"Accepted","tokens":[],"expectedTerminals":[],"trace":[],"diagnostics":[]}"#.utf8)
    let decoded = try JSONDecoder().decode(GrammarParseResult.self, from: legacy)
    #expect(decoded.recoveryEdits.isEmpty)
}

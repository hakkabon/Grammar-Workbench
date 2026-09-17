import Foundation
import Testing
@testable import GrammarWorkbenchCore

@Test func counterexampleCandidatesAreBoundedBreadthFirstAndDeterministic() throws {
    let candidates = try GrammarParserCounterexampleDiscovery.breadthFirstCandidates(
        alphabet: ["b", "a", "a"], maximumTokens: 2
    )
    #expect(candidates == [
        [], ["a"], ["b"], ["a", "a"], ["a", "b"], ["b", "a"], ["b", "b"],
    ])
}

@Test func counterexampleProgrammeSearchesRealLawsAndMinimizesCalibration() throws {
    let report = try GrammarParserCounterexampleProgramme.run()
    #expect(report.passed)
    #expect(report.searches.count == 2)
    #expect(report.searches.allSatisfy { !$0.result.foundCounterexample })
    #expect(report.searches.allSatisfy { $0.result.exhaustedCandidates })

    let counterexample = try #require(report.calibration.counterexample)
    #expect(counterexample.initialTokens == ["x", "a", "b", "a", "x"])
    #expect(counterexample.minimizedTokens == ["a", "b", "a"])
    #expect(counterexample.oneMinimal)
    #expect(counterexample.minimizedDiscrepancy.input == "a b a")

    let encoded = try JSONEncoder().encode(report)
    #expect(
        try JSONDecoder().decode(
            GrammarParserCounterexampleProgrammeReport.self, from: encoded
        ) == report
    )
}

@Test func counterexampleDiscoveryRejectsUnboundedOrMalformedCandidates() throws {
    #expect(throws: GrammarParserCounterexampleError.invalidLimits) {
        try GrammarParserCounterexampleDiscovery.discover(
            candidates: [[]], limits: .init(maximumCandidates: 0)
        ) { _ in nil }
    }
    #expect(throws: GrammarParserCounterexampleError.emptyToken) {
        try GrammarParserCounterexampleDiscovery.discover(candidates: [[""]]) { _ in nil }
    }
    #expect(throws: GrammarParserCounterexampleError.candidateTooLong(9)) {
        try GrammarParserCounterexampleDiscovery.discover(
            candidates: [Array(repeating: "a", count: 9)]
        ) { _ in nil }
    }
}

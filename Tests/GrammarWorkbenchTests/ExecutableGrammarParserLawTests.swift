import Foundation
import Testing
@testable import GrammarWorkbenchCore

@Test func workbenchRunsGrammarAndParserOwnedLawsThroughItsRealRuntime() throws {
    let report = try GrammarParserLawProgramme.run()
    #expect(report.passed)
    #expect(report.cases.count == 2)
    #expect(report.cases.map(\.id) == ["production-order", "alpha-renaming"])
    #expect(report.cases.allSatisfy { $0.evaluation.observationsEquivalent })
    let data = try JSONEncoder().encode(report)
    #expect(try JSONDecoder().decode(GrammarParserLawProgrammeReport.self, from: data) == report)
}

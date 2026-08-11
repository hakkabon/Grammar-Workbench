import Foundation
import Testing
@testable import GrammarWorkbench

@Test func bootstrapLaboratoryReachesCanonicalFixedPoint() throws {
    let report = try GrammarBootstrapLaboratory.run()
    #expect(report.reachedFixedPoint)
    #expect(report.fixedPointGeneration == 2)
    #expect(report.generations.count == 3)
    #expect(report.generations.last?.stableWithPrevious == true)
    #expect(report.differentialValidationPassed)
    #expect(report.succeeded)
}

@Test func bootstrapSpecificationIsIndependentOfProductionOrder() throws {
    let first = try GrammarBootstrapLaboratory.parseProfileBNF(
        "<start> ::= <item>\n<item> ::= 'x' | 'y'\n", start: "start"
    )
    let second = try GrammarBootstrapLaboratory.parseProfileBNF(
        "<item> ::= 'y' | 'x'\n<start> ::= <item>\n", start: "start"
    )
    #expect(first == second)
    #expect(first.fingerprint == second.fingerprint)
}

@Test func bootstrapReportRoundTripsAsStableJSON() throws {
    let report = try GrammarBootstrapLaboratory.run(options: .init(maximumGenerations: 3))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(report)
    let decoded = try JSONDecoder().decode(GrammarBootstrapReport.self, from: data)
    #expect(decoded == report)
}

@Test func bootstrapProfileRejectsImplicitEmptyAlternatives() {
    #expect(throws: GrammarBootstrapError.self) {
        try GrammarBootstrapLaboratory.parseProfileBNF("<start> ::= 'x' |\n", start: "start")
    }
}

import Foundation
import Testing
import GrammarWorkbench

struct CorpusFixture: Sendable, CustomTestStringConvertible {
    let filename: String
    let algorithms: [GrammarAlgorithm]
    let accepted: [String]
    let rejected: [String]

    var testDescription: String { filename }
}

private let corpusFixtures: [CorpusFixture] = [
    .init(
        filename: "JSONSubset.grammar",
        algorithms: [.lalr, .canonical],
        accepted: ["null", "{\"name\": [true, false, -2.5]}", "[1, {\"ok\": true}]"] ,
        rejected: ["{\"name\":}", "[1, 2"]
    ),
    .init(
        filename: "MiniLanguage.grammar",
        algorithms: [.slr, .lalr, .canonical],
        accepted: ["", "let total = 2 + 3 * 4; print total;"],
        rejected: ["let = 1;", "print (1 + 2;"]
    ),
    .init(
        filename: "InterpolatedString.grammar",
        algorithms: [.lalr, .canonical],
        accepted: ["plain text", "before \"hello {name}\" after"],
        rejected: ["\"unterminated", "\"hello {name\""]
    )
]

private func corpusURL(_ filename: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Examples/Corpus")
        .appendingPathComponent(filename)
}

@Test(arguments: corpusFixtures)
func productionCorpusCompilesAndParses(fixture: CorpusFixture) throws {
    let source = try String(contentsOf: corpusURL(fixture.filename), encoding: .utf8)
    for algorithm in fixture.algorithms {
        let compilation = GrammarWorkbenchAPI.compile(.init(source: source, algorithm: algorithm))
        #expect(compilation.succeeded, "\(fixture.filename) failed with \(algorithm.rawValue)")
        #expect(compilation.artifact?.decisions.allSatisfy { $0.disposition != .unresolved } == true)
        for input in fixture.accepted {
            #expect(
                compilation.parse(input, options: .init(enablesRecovery: false)).status == .accepted,
                "\(fixture.filename) should accept: \(input)"
            )
        }
        for input in fixture.rejected {
            #expect(
                compilation.parse(input, options: .init(enablesRecovery: false)).status != .accepted,
                "\(fixture.filename) should reject: \(input)"
            )
        }
    }
}

@Test func productionCorpusPreservesIntentionalConflict() throws {
    let source = try String(contentsOf: corpusURL("ExpectedConflict.grammar"), encoding: .utf8)
    let compilation = GrammarWorkbenchAPI.compile(.init(source: source, algorithm: .lalr))

    #expect(compilation.succeeded)
    #expect(compilation.artifact?.decisions.count == 1)
    #expect(compilation.artifact?.decisions.first?.disposition == .expected)
}

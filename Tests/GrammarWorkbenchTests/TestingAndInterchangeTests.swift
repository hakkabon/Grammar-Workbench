import Foundation
import Testing
@testable import GrammarWorkbench

private let testingGrammar = #"""
%start E
%token ID /[a-z]+/
%skip /\s+/
E : E '+' ID | ID ;
"""#

@Test func batchRunnerHandlesAcceptRejectAndLexerInput() {
    let tests = [
        WorkbenchTestCase(name: "valid", input: "one + two", expectation: .accept),
        WorkbenchTestCase(name: "invalid", input: "one +", expectation: .reject)
    ]
    let report = GrammarTestRunner.run(tests, source: testingGrammar)
    #expect(report.results.map(\.status) == [.passed, .passed])
    #expect(report.results[0].tokens == ["ID", "+", "ID"])
    #expect(report.allPassed)
}

@Test func batchRunnerReportsExpectationAndLexicalFailures() {
    let tests = [
        WorkbenchTestCase(name: "wrong outcome", input: "one", expectation: .reject),
        WorkbenchTestCase(name: "bad character", input: "one @ two", expectation: .accept)
    ]
    let report = GrammarTestRunner.run(tests, source: testingGrammar)
    #expect(report.failed == 2)
    #expect(report.results[0].message.contains("Expected reject"))
    #expect(report.results[1].actual == "Lexical error")
    #expect(report.results[1].message.contains("1:5"))
}

@Test func batchRunnerComparesExactTreeSnapshots() throws {
    let baseline = GrammarTestRunner.run(
        [.init(name: "tree", input: "one", expectation: .accept)], source: testingGrammar
    )
    let tree = try #require(baseline.results.first?.tree)
    let matching = GrammarTestRunner.run(
        [.init(name: "tree", input: "one", expectation: .accept, expectedTree: tree)], source: testingGrammar
    )
    let differing = GrammarTestRunner.run(
        [.init(name: "tree", input: "one", expectation: .accept, expectedTree: "different")], source: testingGrammar
    )
    #expect(matching.allPassed)
    #expect(differing.results.first?.status == .failed)
    #expect(differing.results.first?.message.contains("tree differs") == true)
}

@Test func invalidGrammarMarksEveryTestInvalid() {
    let report = GrammarTestRunner.run(
        [.init(name: "cannot run", input: "", expectation: .accept)],
        source: "S : missing"
    )
    #expect(report.results.first?.status == .invalid)
    #expect(report.results.first?.actual == "Not run")
}

@Test func projectInterchangeRoundTripsAllEditableState() throws {
    let selected = UUID()
    let document = GrammarWorkbenchDocument(
        source: testingGrammar,
        algorithm: "Canonical LR(1)",
        samples: [
            .init(name: "first", input: "one"),
            .init(id: selected, name: "selected", input: "one + two")
        ],
        selectedSampleID: selected,
        tests: [.init(name: "accept", input: "one", expectation: .accept, expectedTree: "E")]
    )
    let data = try GrammarInterchangeCodec.encode(document)
    let decoded = try GrammarInterchangeCodec.decode(data)
    #expect(decoded.source == document.source)
    #expect(decoded.algorithm == document.algorithm)
    #expect(decoded.samples == document.samples)
    #expect(decoded.selectedSampleID == selected)
    #expect(decoded.tests == document.tests)
    #expect(String(decoding: data, as: UTF8.self).contains("\"schemaVersion\" : 1"))
}

@Test func projectInterchangeRejectsUnsupportedVersionsAndInvalidGrammar() throws {
    let valid = try GrammarInterchangeCodec.encode(.init(source: testingGrammar))
    var object = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
    object["schemaVersion"] = 99
    let future = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: GrammarInterchangeError.self) { try GrammarInterchangeCodec.decode(future) }

    object["schemaVersion"] = 1
    object["source"] = "Broken :"
    let invalid = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: GrammarInterchangeError.self) { try GrammarInterchangeCodec.decode(invalid) }
}

@Test func artifactInterchangeContainsVersionedGeneratedSnapshot() throws {
    let data = try GrammarInterchangeCodec.encodeArtifact(source: testingGrammar, algorithm: "SLR(1)")
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["schemaVersion"] as? Int == 1)
    #expect(object["kind"] as? String == "grammar-workbench-artifact")
    let artifact = try #require(object["artifact"] as? [String: Any])
    #expect(artifact["algorithm"] as? String == "SLR(1)")
    #expect((artifact["states"] as? [Any])?.isEmpty == false)
}

@Test func standaloneHTMLCanIncludeBatchTestResults() throws {
    let frontEnd = GrammarFrontEnd.process(testingGrammar)
    let artifact = LRConstructionEngine.construct(
        grammar: try #require(frontEnd.grammar), analysis: try #require(frontEnd.analysis),
        source: testingGrammar, algorithm: .lalr
    )
    let report = GrammarTestRunner.run(
        [.init(name: "HTML-safe <case>", input: "one", expectation: .accept)], source: testingGrammar
    )
    let html = HTMLExporter.render(artifact, testReport: report)
    #expect(html.contains("Test suite"))
    #expect(html.contains("1 passed · 0 failed"))
    #expect(html.contains("HTML-safe &lt;case&gt;"))
}

@Test func legacyDocumentsDecodeWithoutTests() throws {
    let sampleID = UUID()
    let legacy = """
    {
      "source": "S : 'id' ;",
      "algorithm": "LALR(1)",
      "samples": [{"id":"\(sampleID.uuidString)","name":"Legacy","input":"id"}],
      "selectedSampleID": "\(sampleID.uuidString)"
    }
    """
    let document = try JSONDecoder().decode(GrammarWorkbenchDocument.self, from: Data(legacy.utf8))
    #expect(document.tests.isEmpty)
    #expect(document.selectedSampleID == sampleID)
}

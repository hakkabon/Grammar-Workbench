import Foundation
import Testing
@testable import GrammarWorkbenchCore

private let benchmarkEcosystem = Data("""
{
  "schemaVersion": 1,
  "contractVersion": "0.12.0",
  "repositories": [{
    "name": "Grammar-Workbench",
    "version": "1.0.27",
    "revision": "0123456789abcdef0123456789abcdef01234567"
  }]
}
""".utf8)

private func testBenchmarkProtocol(studies: [String] = ["precedence-hidden-ambiguity"])
    -> GrammarResearchBenchmarkProtocol
{
    .init(
        id: "benchmark-test", title: "Benchmark test",
        rationale: "Exercise the versioned benchmark boundary.",
        buildConfiguration: "release", warmupIterations: 0,
        measurementIterations: 3, studyIDs: studies
    )
}

@Test func benchmarkProtocolRunsRawSamplesAndRetainsSemanticEvidence() throws {
    let protocolValue = testBenchmarkProtocol()
    let report = try GrammarResearchBenchmarkRunner.run(protocolValue)
    #expect(report.passed)
    #expect(report.results.count == 1)
    #expect(report.results[0].durationsNanoseconds.count == 3)
    #expect(report.results[0].timing.samples == 3)
    #expect(report.results[0].evidenceFingerprint == report.studyReport.studies.first {
        $0.studyID == report.results[0].id
    }?.report.evidenceFingerprint)

    let decoded = try GrammarResearchBenchmarkCodec.decodeReport(
        GrammarResearchBenchmarkCodec.encode(report)
    )
    #expect(decoded == report)
}

@Test func benchmarkProtocolRejectsUnknownStudiesAndTooFewSamples() throws {
    let unknown = testBenchmarkProtocol(studies: ["not-a-study"])
    #expect(throws: GrammarResearchBenchmarkError.self) {
        try GrammarResearchBenchmarkCodec.encode(unknown)
    }
    let object: [String: Any] = [
        "schemaVersion": 1, "kind": GrammarResearchBenchmarkProtocol.kindIdentifier,
        "id": "short", "title": "Short", "rationale": "Invalid sample count",
        "buildConfiguration": "release", "warmupIterations": 0,
        "measurementIterations": 2, "studyIDs": ["ambiguity-growth"],
    ]
    #expect(throws: GrammarResearchBenchmarkError.self) {
        try GrammarResearchBenchmarkCodec.decodeProtocol(
            JSONSerialization.data(withJSONObject: object)
        )
    }
}

@Test func benchmarkComparisonRequiresMatchingProtocolAndEnvironment() throws {
    let report = try GrammarResearchBenchmarkRunner.run(testBenchmarkProtocol())
    let matching = GrammarResearchBenchmarkRunner.compare(baseline: report, candidate: report)
    #expect(matching.comparable)
    #expect(matching.results.first?.medianRatio == 1)

    let other = try GrammarResearchBenchmarkRunner.run(.init(
        id: "other", title: "Other", rationale: "Different protocol.",
        buildConfiguration: "debug", warmupIterations: 0,
        measurementIterations: 3, studyIDs: ["precedence-hidden-ambiguity"]
    ))
    let incompatible = GrammarResearchBenchmarkRunner.compare(
        baseline: report, candidate: other
    )
    #expect(!incompatible.comparable)
    #expect(incompatible.results.first?.medianRatio == nil)
}

@Test func benchmarkPublicationLinksAndVerifiesEveryArtifact() throws {
    let bundle = try GrammarResearchBenchmarkPublication.create(
        protocolData: GrammarResearchBenchmarkCodec.encode(testBenchmarkProtocol()),
        ecosystemData: benchmarkEcosystem, licenseData: Data("MIT".utf8)
    )
    #expect(bundle.manifest.files.map(\.path)
        == GrammarResearchBenchmarkPublicationManifest.requiredFiles)
    #expect(bundle.manifest.studyEvidenceFingerprint.count == 16)
    let verified = try GrammarResearchBenchmarkPublication.verify(
        manifestData: bundle.manifestData(), files: bundle.files
    )
    #expect(verified.measurementFingerprint == bundle.manifest.measurementFingerprint)

    var tampered = bundle.files
    tampered["benchmark-report.json"]?.append(0x20)
    #expect(throws: GrammarResearchBenchmarkError.self) {
        try GrammarResearchBenchmarkPublication.verify(
            manifestData: bundle.manifestData(), files: tampered
        )
    }
}

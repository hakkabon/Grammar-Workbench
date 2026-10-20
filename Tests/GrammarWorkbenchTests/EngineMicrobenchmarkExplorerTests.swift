import Foundation
import Parser
import Testing
@testable import GrammarWorkbenchCore

private let microbenchmarkEnvironment = ParserEngineMicrobenchmarkEnvironment(
    operatingSystem: "test-os", architecture: "test-arch",
    processorCount: 4, physicalMemoryBytes: 16_000_000_000
)

private func microbenchmarkReport(
    owner: String = "Earley-Parser", engine: String = "earley"
) throws -> ParserEngineMicrobenchmarkReport {
    let suite = ParserEngineMicrobenchmarkSuite(
        owner: .init(repository: owner, version: "0.2.1"),
        engineID: engine, id: "core-v1", title: "Core",
        buildConfiguration: .release, warmupIterations: 0, measurementIterations: 3,
        cases: [.init(
            id: "forest", title: "Forest", operation: .forestConstruction,
            boundary: "Construct one native forest with a pre-built parser.",
            workloadFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint([owner, engine]),
            scale: 8
        )]
    )
    return try ParserEngineMicrobenchmarkRunner.run(
        suite, environment: microbenchmarkEnvironment
    ) { _ in
        .init(
            evidenceFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint(["accepted", "8"]),
            counters: ["accepted": 1, "forestNodeCount": 8]
        )
    }
}

@Suite("Engine-owned microbenchmark explorer")
struct EngineMicrobenchmarkExplorerTests {
    @Test("Workbench projects reports without taking workload ownership")
    func reportProjection() throws {
        let earley = try microbenchmarkReport()
        let rnglr = try microbenchmarkReport(owner: "RNGLR-Parser", engine: "rnglr")
        let report = try GrammarEngineMicrobenchmarkExplorer.inspect([rnglr, earley])
        #expect(report.ownerCount == 2)
        #expect(report.engineCount == 2)
        #expect(report.environmentCount == 1)
        #expect(report.reports.map(\.engineID) == ["earley", "rnglr"])
        #expect(report.reports.first?.cases.first?.sampleCount == 3)
        #expect(report.ratioPolicy.contains("cross-engine rows remain descriptive"))
    }

    @Test("Only compatible longitudinal reports produce ratios")
    func comparisonTruthfulness() throws {
        let report = try microbenchmarkReport()
        let matching = GrammarEngineMicrobenchmarkExplorer.compare(
            baseline: report, candidate: report
        )
        #expect(matching.compatible)
        #expect(matching.medianRatios["forest"] == 1)

        let otherEngine = try microbenchmarkReport(owner: "RNGLR-Parser", engine: "rnglr")
        let crossEngine = GrammarEngineMicrobenchmarkExplorer.compare(
            baseline: report, candidate: otherEngine
        )
        #expect(!crossEngine.compatible)
        #expect(crossEngine.reason == "suite-fingerprint-mismatch")
        #expect(crossEngine.medianRatios.isEmpty)
    }

    @Test("Duplicate measurements fail closed")
    func duplicateMeasurements() throws {
        let report = try microbenchmarkReport()
        #expect(throws: GrammarEngineMicrobenchmarkExplorerError.self) {
            try GrammarEngineMicrobenchmarkExplorer.inspect([report, report])
        }
    }
}

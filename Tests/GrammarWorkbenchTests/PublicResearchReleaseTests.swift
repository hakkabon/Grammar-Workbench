import Foundation
import Testing
@testable import GrammarWorkbenchCore

private func publicResearchRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private func lightweightPublicResearchProtocol() throws -> Data {
    let data = try Data(contentsOf: publicResearchRoot().appendingPathComponent(
        "Examples/ResearchBenchmarkProtocol.json"
    ))
    let published = try GrammarResearchBenchmarkCodec.decodeProtocol(data)
    return try GrammarResearchBenchmarkCodec.encode(.init(
        id: published.id, title: published.title, rationale: published.rationale,
        buildConfiguration: published.buildConfiguration,
        warmupIterations: 0, measurementIterations: 3, studyIDs: published.studyIDs
    ))
}

private func publicResearchBundle() throws -> GrammarPublicResearchReleaseBundle {
    let root = publicResearchRoot()
    return try GrammarPublicResearchRelease.create(
        programmeData: Data(contentsOf: root.appendingPathComponent(
            "Examples/ResearchValidationProgramme.json"
        )),
        benchmarkProtocolData: lightweightPublicResearchProtocol(),
        ecosystemData: Data(contentsOf: root.appendingPathComponent(
            "Packaging/EcosystemCompatibility.json"
        )),
        capabilityLedgerData: Data(contentsOf: root.appendingPathComponent(
            "Packaging/EcosystemCapabilities.json"
        )),
        corpusData: Data(contentsOf: root.appendingPathComponent(
            "Validation/Ecosystem/Corpus.json"
        )),
        licenseData: Data(contentsOf: root.appendingPathComponent("LICENSE")),
        sourceRevision: "0123456789abcdef0123456789abcdef01234567"
    )
}

@Suite("Public research release")
struct PublicResearchReleaseTests {
    @Test("Release binds claims, evidence, measurements, corpus, and provenance")
    func linkedRelease() throws {
        let bundle = try publicResearchBundle()
        #expect(bundle.manifest.softwareVersion == GrammarWorkbenchRelease.version)
        #expect(bundle.manifest.corpusVersion == 5)
        #expect(bundle.manifest.files.map(\.path)
            == GrammarPublicResearchReleaseManifest.requiredFiles)
        let verified = try GrammarPublicResearchRelease.verify(
            manifestData: bundle.manifestData(), files: bundle.files
        )
        #expect(verified == bundle.manifest)
        let index = try JSONDecoder().decode(
            GrammarPublicResearchIndex.self, from: bundle.files["research-index.json"]!
        )
        #expect(index.claims.count == 3)
        #expect(index.nonClaims.contains { $0.contains("formal proof") })
    }

    @Test("Tampering and incomplete provenance fail closed")
    func tampering() throws {
        let bundle = try publicResearchBundle()
        var files = bundle.files
        files["corpus.json"]?.append(0x20)
        #expect(throws: GrammarPublicResearchReleaseError.self) {
            try GrammarPublicResearchRelease.verify(
                manifestData: bundle.manifestData(), files: files
            )
        }
        let root = publicResearchRoot()
        #expect(throws: GrammarPublicResearchReleaseError.self) {
            try GrammarPublicResearchRelease.create(
                programmeData: Data(contentsOf: root.appendingPathComponent(
                    "Examples/ResearchValidationProgramme.json"
                )),
                benchmarkProtocolData: lightweightPublicResearchProtocol(),
                ecosystemData: Data(contentsOf: root.appendingPathComponent(
                    "Packaging/EcosystemCompatibility.json"
                )),
                capabilityLedgerData: Data(contentsOf: root.appendingPathComponent(
                    "Packaging/EcosystemCapabilities.json"
                )),
                corpusData: Data(contentsOf: root.appendingPathComponent(
                    "Validation/Ecosystem/Corpus.json"
                )),
                licenseData: Data("MIT".utf8), sourceRevision: "short"
            )
        }
    }
}

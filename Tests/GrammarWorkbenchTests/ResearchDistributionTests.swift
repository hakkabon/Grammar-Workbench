import Foundation
import Testing
@testable import GrammarWorkbenchCore

private func distributionProgramme() -> GrammarResearchProgramme {
    .init(
        id: "org.grammar-workbench.distribution-test",
        title: "Research distribution test",
        rationale: "Exercise the archival boundary.", repetitions: 1,
        cases: [.init(
            id: "accepted", name: "Accepted", hypothesis: "Both engines accept one derivation.",
            grammar: .init(source: "%start S\nS : 'ok' ;"), input: "ok",
            expectation: .init(
                deterministicStatus: .accepted, generalizedStatus: .accepted,
                minimumDerivations: 1, maximumDerivations: 1
            )
        )]
    )
}

private let distributionEcosystem = Data("""
{
  "schemaVersion": 1,
  "contractVersion": "0.11.0",
  "repositories": [{
    "name": "Grammar-Workbench",
    "version": "1.0.18",
    "revision": "0123456789abcdef0123456789abcdef01234567"
  }]
}
""".utf8)

@Test func researchDistributionLinksEvidenceEcosystemCitationAndLicense() throws {
    let bundle = try GrammarResearchDistribution.create(
        programmeData: GrammarResearchProgrammeCodec.encode(distributionProgramme()),
        ecosystemData: distributionEcosystem,
        licenseData: Data("abc".utf8)
    )

    #expect(bundle.manifest.kind == "grammar-workbench-research-distribution")
    #expect(bundle.manifest.ecosystemContractVersion == "0.11.0")
    #expect(bundle.manifest.files.map(\.path) == GrammarResearchDistributionManifest.requiredFiles)
    #expect(bundle.manifest.files.first { $0.path == "LICENSE.txt" }?.sha256
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(String(decoding: bundle.files["CITATION.cff"]!, as: UTF8.self)
        .contains("repository-code: \"https://github.com/hakkabon/Grammar-Workbench\""))

    let verified = try GrammarResearchDistribution.verify(
        manifestData: bundle.manifestData(), files: bundle.files
    )
    #expect(verified.evidenceFingerprint == bundle.manifest.evidenceFingerprint)
}

@Test func researchDistributionRejectsTamperingAndUnpinnedEcosystems() throws {
    let programmeData = try GrammarResearchProgrammeCodec.encode(distributionProgramme())
    let bundle = try GrammarResearchDistribution.create(
        programmeData: programmeData,
        ecosystemData: distributionEcosystem,
        licenseData: Data("MIT".utf8)
    )
    var files = bundle.files
    files["report.json"]?.append(0x20)
    #expect(throws: GrammarResearchDistributionError.self) {
        try GrammarResearchDistribution.verify(
            manifestData: bundle.manifestData(), files: files
        )
    }
    #expect(throws: GrammarResearchDistributionError.self) {
        try GrammarResearchDistribution.create(
            programmeData: programmeData,
            ecosystemData: Data(#"{"schemaVersion":1,"contractVersion":"0.11.0","repositories":[]}"#.utf8),
            licenseData: Data("MIT".utf8)
        )
    }
}

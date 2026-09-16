import Foundation
import Testing
@testable import GrammarWorkbenchCore
@testable import GrammarWorkbench

private func releaseSource(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

@Test func stableReleaseVersionAdvancesWithTheHardenedArtifactContract() {
    #expect(GrammarWorkbenchRelease.version == "1.0.19")
}

@Test func releaseToolReadsTheCoreOwnedVersionDeclaration() throws {
    let source = try releaseSource("Scripts/release-artifacts.mjs")
    #expect(source.contains("Sources/GrammarWorkbenchCore/ProductionContracts.swift"))
    #expect(!source.contains("Sources/GrammarWorkbench/ProductionSupport.swift"))
}

@Test func platformPackagersCreateAndVerifyProvenanceManifests() throws {
    for path in ["Scripts/package-release.sh", "Scripts/package-linux.sh"] {
        let source = try releaseSource(path)
        #expect(source.contains("release-artifacts.mjs"))
        #expect(source.contains("create --directory"))
        #expect(source.contains(" verify "))
        #expect(source.contains("RELEASE_REQUIRE_CLEAN"))
        #expect(source.contains("research-package"))
        #expect(source.contains("research-package-verify"))
    }
}

@Test func releaseWorkflowAcceptsRepositoryTagConventionAndPublishesManifests() throws {
    let workflow = try releaseSource(".github/workflows/release.yml")
    #expect(workflow.contains("[0-9]*.[0-9]*.[0-9]*"))
    #expect(workflow.contains("--tag \"${{ github.ref_name }}\""))
    #expect(workflow.contains("--revision \"${{ github.sha }}\""))
    #expect(workflow.contains("ReleaseManifest.json.sha256"))
    #expect(workflow.contains("*-manifest.json"))
}

@Test func committedReleaseLockMatchesReviewedEcosystemRevisions() throws {
    let lockData = try #require(releaseSource("Package.resolved").data(using: .utf8))
    let ecosystemData = try #require(
        releaseSource("Packaging/EcosystemCompatibility.json").data(using: .utf8)
    )
    let lock = try #require(
        JSONSerialization.jsonObject(with: lockData) as? [String: Any]
    )
    let ecosystem = try #require(
        JSONSerialization.jsonObject(with: ecosystemData) as? [String: Any]
    )
    #expect(lock["version"] as? Int == 3)

    let pins = try #require(lock["pins"] as? [[String: Any]])
    let repositories = try #require(ecosystem["repositories"] as? [[String: Any]])
    for name in ["Grammar", "Parser", "LR-Parsing"] {
        let expected = try #require(repositories.first { $0["name"] as? String == name })
        let pin = try #require(pins.first { $0["identity"] as? String == name.lowercased() })
        let state = try #require(pin["state"] as? [String: Any])
        #expect(state["version"] as? String == expected["version"] as? String)
        #expect(state["revision"] as? String == expected["revision"] as? String)
    }
}

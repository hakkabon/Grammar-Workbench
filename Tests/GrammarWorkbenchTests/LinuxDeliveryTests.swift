import Foundation
@testable import GrammarWorkbench
import Testing

@Test func runtimePlatformReportIsStablePortableAndComplete() throws {
    let report = GrammarRuntimePlatformReport.current
    #expect(report.schemaVersion == 1)
    #expect(report.releaseVersion == GrammarWorkbenchRelease.version)
    #expect(report.apiVersion == GrammarWorkbenchAPIVersion.current)
    #expect(report.deliveredProducts.contains("GrammarWorkbenchCore"))
    #expect(report.deliveredProducts.contains("grammar-workbench"))
    #expect(report.deliveredProducts.contains("grammar-workbench-lsp"))
    #expect(report.deliveredProducts.contains("grammar-workbench-service"))
#if os(macOS)
    #expect(report.operatingSystem == .macOS)
#elseif os(Linux)
    #expect(report.operatingSystem == .linux)
    #expect(report.graphLayoutAvailability == .interchangeOnly)
#endif
    let data = try JSONEncoder().encode(report)
    #expect(try JSONDecoder().decode(GrammarRuntimePlatformReport.self, from: data) == report)
}

@Test func linuxDeliveryAssetsCoverPackagingContainerAndCI() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    let package = try source("Scripts/package-linux.sh")
    #expect(package.contains("grammar-workbench-lsp"))
    #expect(package.contains("grammar-workbench-service"))
    #expect(package.contains("platform-info"))
    #expect(package.contains("sha256sum"))

    let validation = try source("Scripts/validate-linux-delivery.sh")
    #expect(validation.contains("smoke-release.sh"))
    #expect(validation.contains("smoke-lsp.sh"))
    #expect(validation.contains("smoke-tooling-service.sh"))

    let manifest = try source("Package.swift")
    #expect(manifest.contains("#if os(macOS)"))
    #expect(manifest.contains("nativeAppProducts"))
    #expect(manifest.contains("nativeAppTargets"))

    let dockerfile = try source("Dockerfile")
    #expect(dockerfile.contains("FROM swift:6.0-jammy AS builder"))
    #expect(dockerfile.contains("ENTRYPOINT [\"grammar-workbench\"]"))

    let ci = try source(".github/workflows/ci.yml")
    #expect(ci.contains("Scripts/validate-linux-delivery.sh"))
    #expect(ci.contains("docker build"))
    let release = try source(".github/workflows/release.yml")
    #expect(release.contains("Grammar-Workbench-Linux-x86_64"))
    #expect(release.contains("Scripts/package-linux.sh"))
}

import Foundation
@testable import GrammarWorkbenchCore
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
    #expect(package.contains("install-workbench-resources.sh"))

    let validation = try source("Scripts/validate-linux-delivery.sh")
    #expect(validation.contains("smoke-release.sh"))
    #expect(validation.contains("smoke-lsp.sh"))
    #expect(validation.contains("smoke-tooling-service.sh"))

    let smoke = try source("Scripts/smoke-release.sh")
    #expect(smoke.contains("graphLayoutAvailability"))
    #expect(smoke.contains("interchangeOnly"))
    #expect(smoke.contains("graph-dot"))

    let manifest = try source("Package.swift")
    #expect(manifest.contains("#if os(macOS)"))
    #expect(manifest.contains("nativeAppProducts"))
    #expect(manifest.contains("nativeAppTargets"))

    let dockerfile = try source("Dockerfile")
    #expect(dockerfile.contains("FROM swift:6.0-jammy AS builder"))
    #expect(dockerfile.contains("ENTRYPOINT [\"grammar-workbench\"]"))
    #expect(dockerfile.contains("ARG SWIFT_BUILD_JOBS=2"))
    #expect(dockerfile.contains("Scripts/install-workbench-resources.sh"))
    #expect(dockerfile.contains("COPY --from=builder /runtime/ /usr/local/bin/"))
    #expect(!dockerfile.contains(
        "COPY --from=builder /src/.build/release/GrammarWorkbench_GrammarWorkbench.resources"
    ))

    let ci = try source(".github/workflows/ci.yml")
    #expect(ci.contains("Scripts/validate-linux-delivery.sh"))
    #expect(ci.contains("docker build --build-arg SWIFT_BUILD_JOBS="))
    let release = try source(".github/workflows/release.yml")
    #expect(release.contains("Grammar-Workbench-Linux-x86_64"))
    #expect(release.contains("Scripts/package-linux.sh"))
}

@Test func portableResourceInstallerTracksCoreOwnershipAndFailsClosed() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let sourceDirectory = root.appendingPathComponent("source")
    let destination = root.appendingPathComponent("destination")
    let coreResources = sourceDirectory.appendingPathComponent(
        "GrammarWorkbench_GrammarWorkbenchCore.bundle"
    )
    try manager.createDirectory(at: coreResources, withIntermediateDirectories: true)
    try Data("privacy".utf8).write(to: coreResources.appendingPathComponent("PrivacyInfo.xcprivacy"))
    defer { try? manager.removeItem(at: root) }

    let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Scripts/install-workbench-resources.sh")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path, sourceDirectory.path, destination.path]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    #expect(manager.fileExists(atPath: destination.appendingPathComponent(
        "GrammarWorkbench_GrammarWorkbenchCore.bundle/PrivacyInfo.xcprivacy"
    ).path))

    let emptySource = root.appendingPathComponent("empty")
    try manager.createDirectory(at: emptySource, withIntermediateDirectories: true)
    let missing = Process()
    missing.executableURL = URL(fileURLWithPath: "/bin/bash")
    missing.arguments = [script.path, emptySource.path, root.appendingPathComponent("none").path]
    try missing.run()
    missing.waitUntilExit()
    #expect(missing.terminationStatus != 0)
}

import Foundation
@testable import GrammarWorkbench
import Testing

@Test func wasmFeasibilityReportStatesTheExecutableAndBrowserBoundaries() throws {
    let report = GrammarWASMFeasibilityReport.current
    #expect(report.schemaVersion == 1)
    #expect(report.maturity == .experimental)
    #expect(report.profiles == [.wasiCommand, .browserInterchange])
    #expect(report.wasiProduct == "grammar-workbench-wasi")
    #expect(report.transport == "newline-delimited-json")
    #expect(report.browserDemoUsesPrecomputedArtifact)
    #expect(!report.nativeGraphLayoutAvailable)
    #expect(report.constraints.contains { $0.contains("do not run directly in a browser") })
    let data = try JSONEncoder().encode(report)
    #expect(try JSONDecoder().decode(GrammarWASMFeasibilityReport.self, from: data) == report)
}

@Test func portableWASMDemonstrationHasBuildRuntimeAndValidationAssets() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
    let package = try source("Package.swift")
    #expect(package.contains("grammar-workbench-wasi"))
    #expect(package.contains("GrammarWorkbenchWASIDemo"))
    let host = try source("Sources/GrammarWorkbenchWASIDemo/GrammarWorkbenchWASIMain.swift")
    #expect(host.contains("GrammarToolingCodec.decodeRequest"))
    #expect(host.contains("GrammarLanguageToolingService"))
    let build = try source("Scripts/build-wasm-demo.sh")
    #expect(build.contains("--swift-sdk"))
    #expect(build.contains("--require-sdk"))
    let validation = try source("Scripts/validate-wasm-feasibility.sh")
    #expect(validation.contains("test-wasm-demo.mjs"))
    #expect(try source("Examples/WASM/index.html").contains("Portable parser demonstration"))
    #expect(try source("Examples/WASM/parser-core.mjs").contains("export function parse"))
}

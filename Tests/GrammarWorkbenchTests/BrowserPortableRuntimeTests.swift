import Foundation
@testable import GrammarWorkbench
import Testing

@Test func browserRuntimeDecisionSelectsTheWorkerArtifactProfile() throws {
    let decision = GrammarBrowserRuntimeDecision.current
    #expect(decision.schemaVersion == 1)
    #expect(decision.maturity == .stable)
    #expect(decision.selectedProfile == .portableArtifactWorker)
    #expect(decision.unsupportedProfiles == [.swiftWASIAdapter])
    #expect(decision.artifactKind == "grammar-workbench-portable-lr")
    #expect(decision.artifactSchemaVersion == 2)
    #expect(decision.runtimeVersion == 1)
    #expect(decision.executionIsolation.contains("worker"))
    #expect(decision.cancellation == "worker-termination")
    #expect(decision.resourceLimits.count == 4)
    let data = try JSONEncoder().encode(decision)
    #expect(try JSONDecoder().decode(GrammarBrowserRuntimeDecision.self, from: data) == decision)
}

@Test func browserRuntimeAssetsAndReleaseGateAreComplete() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
    let artifact = try JSONSerialization.jsonObject(
        with: Data(contentsOf: root.appendingPathComponent("Examples/WASM/expression-parser.json"))
    ) as? [String: Any]
    #expect(artifact?["kind"] as? String == GrammarBrowserRuntimeDecision.current.artifactKind)
    #expect(artifact?["schemaVersion"] as? Int == GrammarBrowserRuntimeDecision.current.artifactSchemaVersion)
    #expect(try source("Examples/WASM/runtime-worker.mjs").contains("self.onmessage"))
    #expect(try source("Examples/WASM/runtime-client.mjs").contains("worker.terminate()"))
    #expect(try source("Scripts/test-wasm-demo.mjs").contains("unsupported-runtime"))
    #expect(try source("Scripts/build-wasm-demo.sh").contains("runtime-worker.mjs"))
    #expect(try source("Sources/GrammarWorkbenchCLI/WorkbenchCLI.swift").contains("browser-runtime"))
}

@Test func portableBrowserGeneratorPublishesTheVersionedRuntimeArtifact() async throws {
    let source = "%token ID /[A-Za-z]+/\n%token PLUS /\\+/\n%skip /[ \\t]+/\n%start E\nE: E PLUS ID | ID ;"
    let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
    let registry = GrammarGeneratorRegistry()
    let result = try await registry.generate(identifier: "portable-browser", from: compilation)
    let file = try #require(result.files.first)
    let artifact = try #require(JSONSerialization.jsonObject(with: file.contents) as? [String: Any])
    #expect(artifact["kind"] as? String == "grammar-workbench-portable-lr")
    #expect(artifact["schemaVersion"] as? Int == 2)
    #expect((artifact["actions"] as? [String: Any])?.isEmpty == false)
    #expect((artifact["tokens"] as? [[String: Any]])?.contains { $0["skip"] as? Bool == true } == true)
}

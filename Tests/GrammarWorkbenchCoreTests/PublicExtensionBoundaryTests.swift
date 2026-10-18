import Foundation
import Testing
@testable import GrammarWorkbenchCore

private let extensionGrammar = "%start S\nS : 'extension' ;"

private struct GrammarShapeExtension: GrammarWorkbenchExtension {
    let manifest = GrammarWorkbenchExtensionManifest(
        id: "org.grammar-workbench.tests.shape",
        displayName: "Grammar shape",
        version: "1.2.0",
        summary: "Reports the production count through the public snapshot boundary.",
        commands: [
            .init(
                id: "summarize",
                displayName: "Summarize grammar",
                summary: "Returns an immutable grammar summary.",
                kind: .analysis,
                options: [
                    .init(
                        name: "detail", summary: "Amount of detail.",
                        defaultValue: "brief", allowedValues: ["brief", "full"]
                    )
                ]
            )
        ]
    )

    func run(_ request: GrammarExtensionRequest) async throws -> GrammarExtensionResult {
        let count = request.context.grammar?.productions.count ?? 0
        return .init(
            extensionIdentifier: request.extensionIdentifier,
            commandIdentifier: request.commandIdentifier,
            summary: "\(count) productions",
            findings: [
                .init(
                    id: "production-count", severity: .information,
                    title: "Production count", message: "The grammar has \(count) productions."
                )
            ],
            properties: [
                "detail": request.options["detail"] ?? "missing",
                "privateEngineVisible": "false"
            ]
        )
    }
}

private struct ConfigurableExtension: GrammarWorkbenchExtension {
    let manifest: GrammarWorkbenchExtensionManifest
    let result: GrammarExtensionResult?

    func run(_ request: GrammarExtensionRequest) async throws -> GrammarExtensionResult {
        result ?? .init(
            extensionIdentifier: request.extensionIdentifier,
            commandIdentifier: request.commandIdentifier,
            summary: "ok"
        )
    }
}

private func extensionManifest(
    schemaVersion: Int = 1,
    id: String = "org.grammar-workbench.tests.fixture",
    version: String = "1.0.0",
    minimumHostAPIVersion: Int = 1,
    commands: [GrammarExtensionCommandDescriptor] = [
        .init(id: "inspect", displayName: "Inspect", summary: "Inspect grammar.", kind: .analysis)
    ]
) -> GrammarWorkbenchExtensionManifest {
    .init(
        schemaVersion: schemaVersion, id: id, displayName: "Fixture", version: version,
        summary: "Test fixture.", minimumHostAPIVersion: minimumHostAPIVersion,
        commands: commands
    )
}

@Test func extensionRegistryDiscoversAndRunsAgainstPortableSnapshots() async throws {
    let registry = GrammarWorkbenchExtensionRegistry()
    try await registry.register(GrammarShapeExtension())
    let compilation = GrammarWorkbenchAPI.compile(.init(source: extensionGrammar, algorithm: .lalr))

    let snapshot = await registry.snapshot()
    #expect(snapshot.schemaVersion == 1)
    #expect(snapshot.hostAPIVersion == GrammarWorkbenchAPI.version)
    #expect(snapshot.extensions.map(\.id) == ["org.grammar-workbench.tests.shape"])
    let decoded = try JSONDecoder().decode(
        GrammarExtensionRegistrySnapshot.self,
        from: JSONEncoder().encode(snapshot)
    )
    #expect(decoded == snapshot)

    let result = try await registry.run(
        extensionIdentifier: "org.grammar-workbench.tests.shape",
        commandIdentifier: "summarize",
        compilation: compilation
    )
    #expect(result.summary == "1 productions")
    #expect(result.findings.map(\.id) == ["production-count"])
    #expect(result.properties["detail"] == "brief")
    #expect(result.properties["privateEngineVisible"] == "false")
    #expect(try JSONDecoder().decode(
        GrammarExtensionResult.self, from: JSONEncoder().encode(result)
    ) == result)
}

@Test func extensionRegistrationIsExplicitValidatedAndReplaceable() async throws {
    let registry = GrammarWorkbenchExtensionRegistry()
    let first = ConfigurableExtension(manifest: extensionManifest(), result: nil)
    try await registry.register(first)
    await #expect(throws: GrammarExtensionRegistryError.self) {
        try await registry.register(first)
    }
    try await registry.register(first, replacingExisting: true)
    #expect(await registry.unregister(identifier: first.manifest.id))
    #expect(!(await registry.unregister(identifier: first.manifest.id)))

    for manifest in [
        extensionManifest(schemaVersion: 2),
        extensionManifest(id: "not-namespaced"),
        extensionManifest(version: "1.0"),
        extensionManifest(minimumHostAPIVersion: GrammarWorkbenchAPI.version + 1),
        extensionManifest(commands: [])
    ] {
        await #expect(throws: GrammarExtensionRegistryError.self) {
            try await registry.register(ConfigurableExtension(manifest: manifest, result: nil))
        }
    }
    let prerelease = ConfigurableExtension(
        manifest: extensionManifest(
            id: "org.grammar-workbench.tests.prerelease", version: "1.0.0-beta.1+sha.123"
        ),
        result: nil
    )
    try await registry.register(prerelease)
}

@Test func extensionHostValidatesOptionsResultIdentityAndBoundedOutputs() async throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: extensionGrammar))
    let registry = GrammarWorkbenchExtensionRegistry(
        limits: .init(maximumFindingsPerResult: 1, maximumFilesPerResult: 1, maximumOutputBytesPerResult: 3)
    )
    try await registry.register(GrammarShapeExtension())
    await #expect(throws: GrammarExtensionRegistryError.self) {
        try await registry.run(
            extensionIdentifier: "org.grammar-workbench.tests.shape",
            commandIdentifier: "summarize", compilation: compilation,
            options: .init(["unknown": "value"])
        )
    }
    await #expect(throws: GrammarExtensionRegistryError.self) {
        try await registry.run(
            extensionIdentifier: "org.grammar-workbench.tests.shape",
            commandIdentifier: "summarize", compilation: compilation,
            options: .init(["detail": "invalid"])
        )
    }

    let id = "org.grammar-workbench.tests.bad-result"
    let mismatched = ConfigurableExtension(
        manifest: extensionManifest(id: id),
        result: .init(extensionIdentifier: "org.example.other", commandIdentifier: "inspect", summary: "bad")
    )
    try await registry.register(mismatched)
    await #expect(throws: GrammarExtensionRegistryError.self) {
        try await registry.run(extensionIdentifier: id, commandIdentifier: "inspect", compilation: compilation)
    }

    let oversized = ConfigurableExtension(
        manifest: extensionManifest(id: id),
        result: .init(
            extensionIdentifier: id, commandIdentifier: "inspect", summary: "large",
            files: [.init(suggestedFilename: "result.txt", mediaType: "text/plain", text: "four")]
        )
    )
    try await registry.register(oversized, replacingExisting: true)
    await #expect(throws: GrammarExtensionRegistryError.self) {
        try await registry.run(extensionIdentifier: id, commandIdentifier: "inspect", compilation: compilation)
    }
}


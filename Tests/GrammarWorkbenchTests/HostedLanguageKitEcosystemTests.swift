import Foundation
import GrammarWorkbench
import Testing

private func hostedPackage(
    _ identifier: String, _ version: String,
    dependencies: [GrammarLanguageKitDependency] = []
) throws -> GrammarLanguageKitPackageManifest {
    let parsed = try GrammarLanguageKitVersion(version)
    let kit = GrammarSemanticLanguageKitManifest(
        identifier: identifier, name: "\(identifier) Language", version: version,
        fileExtensions: ["hosted"],
        grammar: .init(source: "%token ID /[A-Za-z]+/\n%start Document\nDocument : ID ;"),
        semantics: .init(rules: []),
        tests: [.init(name: "identifier", input: "example", expectation: .accept)]
    )
    return .init(identifier: identifier, version: parsed, languageKit: kit, dependencies: dependencies)
}

private actor FailingHostedKitStore: GrammarHostedLanguageKitArchiveStore {
    private var data: Data?
    private var shouldFail = false
    func load() -> Data? { data }
    func save(_ data: Data) throws {
        if shouldFail { shouldFail = false; throw CocoaError(.fileWriteUnknown) }
        self.data = data
    }
    func failNextSave() { shouldFail = true }
}

@Suite("Hosted language-kit ecosystem")
struct HostedLanguageKitEcosystemTests {
    @Test("Publication is immutable, idempotent, discoverable, and auditable")
    func publication() async throws {
        let service = GrammarHostedLanguageKitService()
        let package = try hostedPackage("org.example.hosted", "1.0.0")
        let result = try await service.publish(package, publisherID: "publisher", operationID: "publish")
        let replay = try await service.publish(package, publisherID: "publisher", operationID: "publish")

        #expect(!result.record.withdrawn)
        #expect(!result.record.fingerprint.isEmpty)
        #expect(replay.replayedOperation)
        #expect(await service.catalog(includeWithdrawn: false).packages.count == 1)
        #expect(try await service.events(after: -1).map(\.kind) == [.packagePublished])
        await #expect(throws: GrammarHostedLanguageKitError.self) {
            try await service.publish(
                try hostedPackage("org.example.other", "1.0.0"),
                publisherID: "publisher", operationID: "publish"
            )
        }

        var changed = package
        changed.metadata["changed"] = "true"
        await #expect(throws: GrammarHostedLanguageKitError.self) {
            try await service.publish(changed, publisherID: "publisher", operationID: "replace")
        }
    }

    @Test("Resolution selects active versions and withdrawal preserves records")
    func resolutionAndWithdrawal() async throws {
        let service = GrammarHostedLanguageKitService()
        let core10 = try hostedPackage("org.example.core", "1.0.0")
        let core12 = try hostedPackage("org.example.core", "1.2.0")
        let requirement = GrammarLanguageKitDependency(
            identifier: "org.example.core",
            requirement: .compatible(with: try GrammarLanguageKitVersion("1.0.0"))
        )
        let app = try hostedPackage("org.example.app", "1.0.0", dependencies: [requirement])
        _ = try await service.publish(core10, publisherID: "publisher", operationID: "core-10")
        _ = try await service.publish(core12, publisherID: "publisher", operationID: "core-12")
        _ = try await service.publish(app, publisherID: "publisher", operationID: "app")
        #expect(try await service.resolve([requirement]).packages.first?.version == core12.version)

        _ = try await service.setWithdrawn(
            identifier: core12.identifier, version: core12.version, withdrawn: true,
            publisherID: "publisher", operationID: "withdraw"
        )
        #expect(try await service.resolve([requirement]).packages.first?.version == core10.version)
        await #expect(throws: GrammarHostedLanguageKitError.self) {
            try await service.package(identifier: core12.identifier, version: core12.version, includeWithdrawn: false)
        }
        #expect(try await service.package(identifier: core12.identifier, version: core12.version, includeWithdrawn: true).withdrawn)
        #expect(await service.catalog(includeWithdrawn: true).packages.count == 3)
    }

    @Test("Durable service recovers audit, replay, and package state")
    func durableRecovery() async throws {
        let store = GrammarHostedLanguageKitMemoryStore()
        let first = try await GrammarHostedLanguageKitService.open(store: store)
        let package = try hostedPackage("org.example.durable", "1.0.0")
        let published = try await first.publish(package, publisherID: "publisher", operationID: "publish")
        let second = try await GrammarHostedLanguageKitService.open(store: store)

        #expect(try await second.package(identifier: package.identifier, version: package.version, includeWithdrawn: false) == published.record)
        #expect(try await second.events(after: -1).count == 1)
        #expect(try await second.publish(package, publisherID: "publisher", operationID: "publish").replayedOperation)
    }

    @Test("Failed saves roll back and corrupt archives fail closed")
    func durabilityFailure() async throws {
        let store = FailingHostedKitStore()
        let service = try await GrammarHostedLanguageKitService.open(store: store)
        let first = try hostedPackage("org.example.first", "1.0.0")
        _ = try await service.publish(first, publisherID: "publisher", operationID: "first")
        await store.failNextSave()
        await #expect(throws: GrammarHostedLanguageKitError.self) {
            try await service.publish(
                try hostedPackage("org.example.lost", "1.0.0"),
                publisherID: "publisher", operationID: "lost"
            )
        }
        #expect(await service.catalog(includeWithdrawn: true).packages.map(\.identifier) == ["org.example.first"])

        await #expect(throws: GrammarHostedLanguageKitError.self) {
            try await GrammarHostedLanguageKitService.open(
                store: GrammarHostedLanguageKitMemoryStore(data: Data("not-json".utf8))
            )
        }
        let future = GrammarHostedLanguageKitArchive(
            schemaVersion: 99, revision: 0, records: [], events: [], replay: [:], nextEventSequence: 0
        )
        await #expect(throws: GrammarHostedLanguageKitError.self) {
            try await GrammarHostedLanguageKitService.open(
                store: GrammarHostedLanguageKitMemoryStore(data: try JSONEncoder().encode(future))
            )
        }
    }
}

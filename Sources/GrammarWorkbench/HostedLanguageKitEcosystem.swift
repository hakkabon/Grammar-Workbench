import Foundation

public struct GrammarHostedLanguageKitRecord: Hashable, Codable, Sendable {
    public let package: GrammarLanguageKitPackageManifest
    public let publisherID: String
    public let fingerprint: String
    public let publishedSequence: Int
    public var withdrawn: Bool

    public init(
        package: GrammarLanguageKitPackageManifest, publisherID: String,
        fingerprint: String, publishedSequence: Int, withdrawn: Bool = false
    ) {
        self.package = package; self.publisherID = publisherID
        self.fingerprint = fingerprint; self.publishedSequence = publishedSequence
        self.withdrawn = withdrawn
    }
}

public struct GrammarHostedLanguageKitSummary: Hashable, Codable, Sendable {
    public let identifier: String
    public let version: GrammarLanguageKitVersion
    public let name: String
    public let publisherID: String
    public let fingerprint: String
    public let withdrawn: Bool
}

public struct GrammarHostedLanguageKitCatalogSnapshot: Hashable, Codable, Sendable {
    public let revision: Int
    public let packages: [GrammarHostedLanguageKitSummary]
    public let nextEventSequence: Int
    public let oldestAvailableEventSequence: Int
}

public enum GrammarHostedLanguageKitEventKind: String, Hashable, Codable, Sendable {
    case packagePublished
    case packageWithdrawn
    case packageRestored
}

public struct GrammarHostedLanguageKitEvent: Identifiable, Hashable, Codable, Sendable {
    public let sequence: Int
    public let operationID: String
    public let kind: GrammarHostedLanguageKitEventKind
    public let identifier: String
    public let version: GrammarLanguageKitVersion
    public let publisherID: String
    public let fingerprint: String
    public var id: Int { sequence }
}

public struct GrammarHostedLanguageKitResult: Hashable, Codable, Sendable {
    public let record: GrammarHostedLanguageKitRecord
    public let event: GrammarHostedLanguageKitEvent
    public let replayedOperation: Bool
}

public struct GrammarHostedLanguageKitArchive: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let revision: Int
    public let records: [GrammarHostedLanguageKitRecord]
    public let events: [GrammarHostedLanguageKitEvent]
    public let replay: [String: GrammarHostedLanguageKitResult]
    public let nextEventSequence: Int

    public init(
        schemaVersion: Int = Self.currentSchemaVersion, revision: Int,
        records: [GrammarHostedLanguageKitRecord], events: [GrammarHostedLanguageKitEvent],
        replay: [String: GrammarHostedLanguageKitResult], nextEventSequence: Int
    ) {
        self.schemaVersion = schemaVersion; self.revision = revision
        self.records = records; self.events = events; self.replay = replay
        self.nextEventSequence = nextEventSequence
    }
}

public struct GrammarHostedLanguageKitLimits: Hashable, Codable, Sendable {
    public var maximumPackages: Int
    public var maximumPackageBytes: Int
    public var maximumRetainedEvents: Int

    public init(
        maximumPackages: Int = 4_096, maximumPackageBytes: Int = 5_000_000,
        maximumRetainedEvents: Int = 4_096
    ) {
        self.maximumPackages = max(1, maximumPackages)
        self.maximumPackageBytes = max(1, maximumPackageBytes)
        self.maximumRetainedEvents = max(1, maximumRetainedEvents)
    }
}

public enum GrammarHostedLanguageKitError: Error, LocalizedError, Sendable {
    case invalidIdentity(String)
    case operationConflict(String)
    case unknownPackage(String, String)
    case immutableVersion(String, String)
    case publisherMismatch(expected: String, actual: String)
    case eventHistoryUnavailable(requested: Int, oldest: Int)
    case unsupportedSchema(Int)
    case invalidArchive(String)
    case resourceLimit(String)
    case loadFailed(String)
    case saveFailed(String)

    public var code: String {
        switch self {
        case .invalidIdentity: "invalid-language-kit-host-identity"
        case .operationConflict: "language-kit-operation-conflict"
        case .unknownPackage: "unknown-hosted-language-kit"
        case .immutableVersion: "immutable-language-kit-version"
        case .publisherMismatch: "language-kit-publisher-mismatch"
        case .eventHistoryUnavailable: "language-kit-event-history-unavailable"
        case .unsupportedSchema: "unsupported-language-kit-host-archive"
        case .invalidArchive: "invalid-language-kit-host-archive"
        case .resourceLimit: "language-kit-host-resource-limit"
        case .loadFailed: "language-kit-host-load-failed"
        case .saveFailed: "language-kit-host-save-failed"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidIdentity(let value): "Hosted language-kit identity ‘\(value)’ is empty or invalid."
        case .operationConflict(let value): "Hosted language-kit operation ‘\(value)’ was already used for different input."
        case .unknownPackage(let id, let version): "No hosted language-kit package ‘\(id)@\(version)’ exists."
        case .immutableVersion(let id, let version): "Hosted package ‘\(id)@\(version)’ already exists with different content. Publish a new version."
        case .publisherMismatch(let expected, let actual): "Publisher ‘\(actual)’ cannot change a package owned by ‘\(expected)’."
        case .eventHistoryUnavailable(let requested, let oldest): "Language-kit event \(requested) is no longer retained; the oldest available event is \(oldest)."
        case .unsupportedSchema(let value): "Hosted language-kit archive schema \(value) is unsupported."
        case .invalidArchive(let message), .resourceLimit(let message): message
        case .loadFailed(let message): "Could not load hosted language kits: \(message)"
        case .saveFailed(let message): "Could not save hosted language kits: \(message)"
        }
    }
}

public protocol GrammarHostedLanguageKitArchiveStore: Sendable {
    func load() async throws -> Data?
    func save(_ data: Data) async throws
}

public struct GrammarHostedLanguageKitFileStore: GrammarHostedLanguageKitArchiveStore, Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }
    public func load() async throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL, options: .mappedIfSafe)
    }
    public func save(_ data: Data) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

public actor GrammarHostedLanguageKitMemoryStore: GrammarHostedLanguageKitArchiveStore {
    private var data: Data?
    public init(data: Data? = nil) { self.data = data }
    public func load() -> Data? { data }
    public func save(_ data: Data) { self.data = data }
}

public protocol GrammarHostedLanguageKitServing: Actor {
    func publish(_ package: GrammarLanguageKitPackageManifest, publisherID: String, operationID: String) async throws -> GrammarHostedLanguageKitResult
    func setWithdrawn(identifier: String, version: GrammarLanguageKitVersion, withdrawn: Bool, publisherID: String, operationID: String) async throws -> GrammarHostedLanguageKitResult
    func package(identifier: String, version: GrammarLanguageKitVersion, includeWithdrawn: Bool) async throws -> GrammarHostedLanguageKitRecord
    func catalog(includeWithdrawn: Bool) async -> GrammarHostedLanguageKitCatalogSnapshot
    func resolve(_ roots: [GrammarLanguageKitDependency]) async throws -> GrammarLanguageKitResolution
    func events(after sequence: Int) async throws -> [GrammarHostedLanguageKitEvent]
}

/// Transport-neutral, single-writer hosted registry. Published versions are
/// immutable; withdrawal changes discoverability without deleting audit data.
public actor GrammarHostedLanguageKitService: GrammarHostedLanguageKitServing {
    private struct Key: Hashable { let identifier: String; let version: GrammarLanguageKitVersion }
    private struct State {
        var revision = 0
        var records: [Key: GrammarHostedLanguageKitRecord] = [:]
        var events: [GrammarHostedLanguageKitEvent] = []
        var replay: [String: GrammarHostedLanguageKitResult] = [:]
        var nextSequence = 0
    }

    private var state: State
    private let store: (any GrammarHostedLanguageKitArchiveStore)?
    public let limits: GrammarHostedLanguageKitLimits

    public init(limits: GrammarHostedLanguageKitLimits = .init()) {
        state = State(); store = nil; self.limits = limits
    }

    private init(state: State, store: any GrammarHostedLanguageKitArchiveStore, limits: GrammarHostedLanguageKitLimits) {
        self.state = state; self.store = store; self.limits = limits
    }

    public static func open(
        store: any GrammarHostedLanguageKitArchiveStore,
        limits: GrammarHostedLanguageKitLimits = .init()
    ) async throws -> GrammarHostedLanguageKitService {
        do {
            guard let data = try await store.load() else {
                return .init(state: State(), store: store, limits: limits)
            }
            let archive: GrammarHostedLanguageKitArchive
            do { archive = try JSONDecoder().decode(GrammarHostedLanguageKitArchive.self, from: data) }
            catch { throw GrammarHostedLanguageKitError.loadFailed(error.localizedDescription) }
            let state = try restore(archive, limits: limits)
            return .init(state: state, store: store, limits: limits)
        } catch let error as GrammarHostedLanguageKitError { throw error }
        catch { throw GrammarHostedLanguageKitError.loadFailed(error.localizedDescription) }
    }

    public func publish(
        _ package: GrammarLanguageKitPackageManifest, publisherID: String, operationID: String
    ) async throws -> GrammarHostedLanguageKitResult {
        try validateIdentity(publisherID); try validateIdentity(operationID)
        _ = try GrammarLanguageKitPackageCodec.validate(package)
        let data = try GrammarLanguageKitPackageCodec.encode(package)
        guard data.count <= limits.maximumPackageBytes else {
            throw GrammarHostedLanguageKitError.resourceLimit("The hosted language-kit package exceeds the byte limit.")
        }
        let key = Key(identifier: package.identifier, version: package.version)
        let fingerprint = Self.fingerprint(data)
        if let value = state.replay[operationID] {
            guard value.event.kind == .packagePublished,
                  value.event.identifier == package.identifier,
                  value.event.version == package.version,
                  value.event.publisherID == publisherID,
                  value.event.fingerprint == fingerprint else {
                throw GrammarHostedLanguageKitError.operationConflict(operationID)
            }
            return replay(value)
        }
        if let current = state.records[key] {
            guard current.fingerprint == fingerprint else {
                throw GrammarHostedLanguageKitError.immutableVersion(package.identifier, package.version.description)
            }
            guard current.publisherID == publisherID else {
                throw GrammarHostedLanguageKitError.publisherMismatch(expected: current.publisherID, actual: publisherID)
            }
            throw GrammarLanguageKitEcosystemError.duplicatePackage(package.identifier, package.version.description)
        }
        guard state.records.count < limits.maximumPackages else {
            throw GrammarHostedLanguageKitError.resourceLimit("The hosted language-kit package limit was reached.")
        }
        let before = state
        let event = makeEvent(
            kind: .packagePublished, key: key, publisherID: publisherID,
            operationID: operationID, fingerprint: fingerprint
        )
        let record = GrammarHostedLanguageKitRecord(
            package: package, publisherID: publisherID, fingerprint: fingerprint,
            publishedSequence: event.sequence
        )
        state.records[key] = record; state.revision += 1
        let result = GrammarHostedLanguageKitResult(record: record, event: event, replayedOperation: false)
        state.replay[operationID] = result; trimReplay()
        try await persistOrRollback(before)
        return result
    }

    public func setWithdrawn(
        identifier: String, version: GrammarLanguageKitVersion, withdrawn: Bool,
        publisherID: String, operationID: String
    ) async throws -> GrammarHostedLanguageKitResult {
        try validateIdentity(publisherID); try validateIdentity(operationID)
        let key = Key(identifier: identifier, version: version)
        let expectedKind: GrammarHostedLanguageKitEventKind = withdrawn
            ? .packageWithdrawn : .packageRestored
        if let value = state.replay[operationID] {
            guard value.event.kind == expectedKind,
                  value.event.identifier == identifier, value.event.version == version,
                  value.event.publisherID == publisherID else {
                throw GrammarHostedLanguageKitError.operationConflict(operationID)
            }
            return replay(value)
        }
        guard var record = state.records[key] else {
            throw GrammarHostedLanguageKitError.unknownPackage(identifier, version.description)
        }
        guard record.publisherID == publisherID else {
            throw GrammarHostedLanguageKitError.publisherMismatch(expected: record.publisherID, actual: publisherID)
        }
        let before = state
        record.withdrawn = withdrawn
        let event = makeEvent(
            kind: expectedKind, key: key,
            publisherID: publisherID, operationID: operationID, fingerprint: record.fingerprint
        )
        state.records[key] = record; state.revision += 1
        let result = GrammarHostedLanguageKitResult(record: record, event: event, replayedOperation: false)
        state.replay[operationID] = result; trimReplay()
        try await persistOrRollback(before)
        return result
    }

    public func package(
        identifier: String, version: GrammarLanguageKitVersion, includeWithdrawn: Bool = false
    ) throws -> GrammarHostedLanguageKitRecord {
        guard let value = state.records[.init(identifier: identifier, version: version)],
              includeWithdrawn || !value.withdrawn else {
            throw GrammarHostedLanguageKitError.unknownPackage(identifier, version.description)
        }
        return value
    }

    public func catalog(includeWithdrawn: Bool = false) -> GrammarHostedLanguageKitCatalogSnapshot {
        let records = state.records.values.filter { includeWithdrawn || !$0.withdrawn }
        return .init(
            revision: state.revision,
            packages: records.map { value in
                .init(
                    identifier: value.package.identifier, version: value.package.version,
                    name: value.package.languageKit.name, publisherID: value.publisherID,
                    fingerprint: value.fingerprint, withdrawn: value.withdrawn
                )
            }.sorted { ($0.identifier, $0.version) < ($1.identifier, $1.version) },
            nextEventSequence: state.nextSequence,
            oldestAvailableEventSequence: state.events.first?.sequence ?? state.nextSequence
        )
    }

    public func resolve(_ roots: [GrammarLanguageKitDependency]) async throws -> GrammarLanguageKitResolution {
        let registry = GrammarLanguageKitPackageRegistry()
        for record in state.records.values where !record.withdrawn { try await registry.add(record.package) }
        return try await registry.resolve(roots: roots)
    }

    public func events(after sequence: Int) throws -> [GrammarHostedLanguageKitEvent] {
        let oldest = state.events.first?.sequence ?? state.nextSequence
        guard sequence >= oldest - 1 else {
            throw GrammarHostedLanguageKitError.eventHistoryUnavailable(requested: sequence, oldest: oldest)
        }
        return state.events.filter { $0.sequence > sequence }
    }

    public func archive() -> GrammarHostedLanguageKitArchive {
        .init(
            revision: state.revision,
            records: state.records.values.sorted { ($0.package.identifier, $0.package.version) < ($1.package.identifier, $1.package.version) },
            events: state.events, replay: state.replay, nextEventSequence: state.nextSequence
        )
    }

    private func makeEvent(
        kind: GrammarHostedLanguageKitEventKind, key: Key, publisherID: String,
        operationID: String, fingerprint: String
    ) -> GrammarHostedLanguageKitEvent {
        let event = GrammarHostedLanguageKitEvent(
            sequence: state.nextSequence, operationID: operationID, kind: kind,
            identifier: key.identifier, version: key.version, publisherID: publisherID,
            fingerprint: fingerprint
        )
        state.nextSequence += 1; state.events.append(event)
        if state.events.count > limits.maximumRetainedEvents {
            state.events.removeFirst(state.events.count - limits.maximumRetainedEvents)
        }
        return event
    }

    private func trimReplay() {
        if state.replay.count > limits.maximumRetainedEvents {
            let retained = Set(state.events.map(\.operationID))
            state.replay = state.replay.filter { retained.contains($0.key) }
        }
    }

    private func replay(_ value: GrammarHostedLanguageKitResult) -> GrammarHostedLanguageKitResult {
        .init(record: value.record, event: value.event, replayedOperation: true)
    }

    private func persistOrRollback(_ before: State) async throws {
        guard let store else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            try await store.save(encoder.encode(archive()))
        } catch {
            state = before
            throw GrammarHostedLanguageKitError.saveFailed(error.localizedDescription)
        }
    }

    private func validateIdentity(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.utf8.count <= 256 else {
            throw GrammarHostedLanguageKitError.invalidIdentity(value)
        }
    }

    private static func restore(
        _ archive: GrammarHostedLanguageKitArchive, limits: GrammarHostedLanguageKitLimits
    ) throws -> State {
        guard archive.schemaVersion == GrammarHostedLanguageKitArchive.currentSchemaVersion else {
            throw GrammarHostedLanguageKitError.unsupportedSchema(archive.schemaVersion)
        }
        guard archive.revision >= 0, archive.records.count <= limits.maximumPackages,
              archive.events.count <= limits.maximumRetainedEvents,
              archive.replay.count <= limits.maximumRetainedEvents else {
            throw GrammarHostedLanguageKitError.invalidArchive("The hosted language-kit archive exceeds configured limits.")
        }
        var records: [Key: GrammarHostedLanguageKitRecord] = [:]
        for record in archive.records {
            _ = try GrammarLanguageKitPackageCodec.validate(record.package)
            let data = try GrammarLanguageKitPackageCodec.encode(record.package)
            guard data.count <= limits.maximumPackageBytes,
                  fingerprint(data) == record.fingerprint,
                  !record.publisherID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GrammarHostedLanguageKitError.invalidArchive("A hosted language-kit record is invalid.")
            }
            let key = Key(identifier: record.package.identifier, version: record.package.version)
            guard records[key] == nil else {
                throw GrammarHostedLanguageKitError.invalidArchive("A hosted language-kit version is duplicated.")
            }
            records[key] = record
        }
        let sequences = archive.events.map(\.sequence)
        guard zip(sequences, sequences.dropFirst()).allSatisfy({ $1 == $0 + 1 }),
              (sequences.last.map { archive.nextEventSequence == $0 + 1 }
                  ?? (archive.nextEventSequence == 0)),
              archive.events.allSatisfy({ event in
                  records[.init(identifier: event.identifier, version: event.version)]?.fingerprint == event.fingerprint
              }),
              archive.replay.allSatisfy({ $0.key == $0.value.event.operationID }) else {
            throw GrammarHostedLanguageKitError.invalidArchive("Hosted language-kit event or replay state is inconsistent.")
        }
        return .init(
            revision: archive.revision, records: records, events: archive.events,
            replay: archive.replay, nextSequence: archive.nextEventSequence
        )
    }

    private static func fingerprint(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
}

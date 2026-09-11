import Foundation

public enum GrammarCollaborationDurabilityError: Error, LocalizedError, Sendable {
    case unsupportedSchema(Int)
    case invalidArchive(String)
    case loadFailed(String)
    case saveFailed(String)

    public var code: String {
        switch self {
        case .unsupportedSchema: "unsupported-collaboration-archive"
        case .invalidArchive: "invalid-collaboration-archive"
        case .loadFailed: "collaboration-load-failed"
        case .saveFailed: "collaboration-save-failed"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "Collaboration archive schema \(version) is unsupported."
        case .invalidArchive(let message): message
        case .loadFailed(let message): "Could not load collaborative workspaces: \(message)"
        case .saveFailed(let message): "Could not durably save collaborative workspaces: \(message)"
        }
    }
}

public protocol GrammarCollaborationArchiveStore: Sendable {
    func load() async throws -> Data?
    func save(_ data: Data) async throws
}

/// Atomic single-file storage. The containing directory is created on first
/// save; writes use Foundation's replacement-file atomicity.
public struct GrammarCollaborationFileStore: GrammarCollaborationArchiveStore, Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() async throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL, options: .mappedIfSafe)
    }

    public func save(_ data: Data) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

/// Useful for embedding and tests where the durable bytes are managed by the
/// caller rather than the filesystem.
public actor GrammarCollaborationMemoryStore: GrammarCollaborationArchiveStore {
    private var data: Data?
    public init(data: Data? = nil) { self.data = data }
    public func load() -> Data? { data }
    public func save(_ data: Data) { self.data = data }
}

/// Transactional durability facade over the Phase 34 host. A mutation becomes
/// visible only if its archive save succeeds; failed saves restore the exact
/// pre-operation host state, including retained retry records and event order.
public actor GrammarDurableCollaborativeWorkbenchHost: GrammarCollaborationHosting {
    private var host: GrammarCollaborativeWorkbenchHost
    private let store: any GrammarCollaborationArchiveStore
    public let limits: GrammarCollaborationLimits

    private init(
        host: GrammarCollaborativeWorkbenchHost,
        store: any GrammarCollaborationArchiveStore,
        limits: GrammarCollaborationLimits
    ) {
        self.host = host; self.store = store; self.limits = limits
    }

    public static func open(
        store: any GrammarCollaborationArchiveStore,
        limits: GrammarCollaborationLimits = .init()
    ) async throws -> GrammarDurableCollaborativeWorkbenchHost {
        let host: GrammarCollaborativeWorkbenchHost
        do {
            if let data = try await store.load() {
                let archive: GrammarCollaborationArchive
                do { archive = try JSONDecoder().decode(GrammarCollaborationArchive.self, from: data) }
                catch { throw GrammarCollaborationDurabilityError.loadFailed(error.localizedDescription) }
                host = try GrammarCollaborativeWorkbenchHost(restoring: archive, limits: limits)
            } else {
                host = GrammarCollaborativeWorkbenchHost(limits: limits)
            }
        } catch let error as GrammarCollaborationDurabilityError {
            throw error
        } catch {
            throw GrammarCollaborationDurabilityError.loadFailed(error.localizedDescription)
        }
        return .init(host: host, store: store, limits: limits)
    }

    public func createWorkspace(
        id: String, owner: GrammarCollaborationParticipant,
        documents: [GrammarCollaborationDocument], operationID: String
    ) async throws -> GrammarCollaborationResult {
        try await transaction { host in
            try await host.createWorkspace(
                id: id, owner: owner, documents: documents, operationID: operationID
            )
        }
    }

    public func join(
        workspaceID: String, participant: GrammarCollaborationParticipant,
        operationID: String
    ) async throws -> GrammarCollaborationResult {
        try await transaction { host in
            try await host.join(
                workspaceID: workspaceID, participant: participant, operationID: operationID
            )
        }
    }

    public func leave(
        workspaceID: String, participantID: String, operationID: String
    ) async throws -> GrammarCollaborationResult {
        try await transaction { host in
            try await host.leave(
                workspaceID: workspaceID, participantID: participantID, operationID: operationID
            )
        }
    }

    public func apply(
        workspaceID: String, participantID: String, documentID: String,
        expectedRevision: Int, edits: [GrammarTextEdit], operationID: String
    ) async throws -> GrammarCollaborationResult {
        try await transaction { host in
            try await host.apply(
                workspaceID: workspaceID, participantID: participantID,
                documentID: documentID, expectedRevision: expectedRevision,
                edits: edits, operationID: operationID
            )
        }
    }

    public func status(_ workspaceID: String) async throws -> GrammarCollaborationWorkspaceSnapshot {
        try await host.status(workspaceID)
    }

    public func events(
        workspaceID: String, after sequence: Int
    ) async throws -> [GrammarCollaborationEvent] {
        try await host.events(workspaceID: workspaceID, after: sequence)
    }

    public var workspaceIDs: [String] { get async { await host.workspaceIDs } }

    public func archive() async -> GrammarCollaborationArchive { await host.archive() }

    private func transaction<Value: Sendable>(
        _ operation: @Sendable (GrammarCollaborativeWorkbenchHost) async throws -> Value
    ) async throws -> Value {
        let before = await host.archive()
        let value = try await operation(host)
        do {
            try await persist()
            return value
        } catch {
            host = try GrammarCollaborativeWorkbenchHost(restoring: before, limits: limits)
            if let durability = error as? GrammarCollaborationDurabilityError { throw durability }
            throw GrammarCollaborationDurabilityError.saveFailed(error.localizedDescription)
        }
    }

    private func persist() async throws {
        let archive = await host.archive()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do { try await store.save(encoder.encode(archive)) }
        catch { throw GrammarCollaborationDurabilityError.saveFailed(error.localizedDescription) }
    }
}

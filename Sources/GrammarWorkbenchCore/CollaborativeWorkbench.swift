import Foundation

public struct GrammarCollaborationParticipant: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct GrammarCollaborationDocument: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let text: GrammarTextSnapshot

    public init(id: String, text: String, revision: Int = 0) {
        self.id = id
        self.text = .init(revision: revision, text: text)
    }

    init(id: String, snapshot: GrammarTextSnapshot) {
        self.id = id
        text = snapshot
    }
}

public enum GrammarCollaborationEventKind: String, Hashable, Codable, Sendable {
    case workspaceCreated
    case participantJoined
    case participantLeft
    case documentChanged
}

public struct GrammarCollaborationEvent: Identifiable, Hashable, Codable, Sendable {
    public let sequence: Int
    public let operationID: String
    public let kind: GrammarCollaborationEventKind
    public let workspaceID: String
    public let participantID: String
    public let documentID: String?
    public let documentRevision: Int?
    public let change: GrammarTextChangeSummary?
    public var id: String { "\(workspaceID):\(sequence)" }
}

public struct GrammarCollaborationWorkspaceSnapshot: Hashable, Codable, Sendable {
    public let id: String
    public let revision: Int
    public let documents: [GrammarCollaborationDocument]
    public let participants: [GrammarCollaborationParticipant]
    public let nextEventSequence: Int
    public let oldestAvailableEventSequence: Int
}

public struct GrammarCollaborationResult: Hashable, Codable, Sendable {
    public let workspace: GrammarCollaborationWorkspaceSnapshot
    public let events: [GrammarCollaborationEvent]
    public let replayedOperation: Bool
}

public struct GrammarCollaborationWorkspaceArchive: Hashable, Codable, Sendable {
    public let id: String
    public let revision: Int
    public let documents: [GrammarCollaborationDocument]
    public let participants: [GrammarCollaborationParticipant]
    public let events: [GrammarCollaborationEvent]
    public let replay: [String: GrammarCollaborationResult]
    public let nextEventSequence: Int

    public init(
        id: String, revision: Int, documents: [GrammarCollaborationDocument],
        participants: [GrammarCollaborationParticipant], events: [GrammarCollaborationEvent],
        replay: [String: GrammarCollaborationResult], nextEventSequence: Int
    ) {
        self.id = id; self.revision = revision; self.documents = documents
        self.participants = participants; self.events = events; self.replay = replay
        self.nextEventSequence = nextEventSequence
    }
}

public struct GrammarCollaborationArchive: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let workspaces: [GrammarCollaborationWorkspaceArchive]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        workspaces: [GrammarCollaborationWorkspaceArchive]
    ) {
        self.schemaVersion = schemaVersion; self.workspaces = workspaces
    }
}

public struct GrammarCollaborationLimits: Hashable, Codable, Sendable {
    public var maximumWorkspaces: Int
    public var maximumParticipantsPerWorkspace: Int
    public var maximumDocumentsPerWorkspace: Int
    public var maximumDocumentUTF16Length: Int
    public var maximumRetainedEvents: Int
    public var maximumEditsPerOperation: Int

    public init(
        maximumWorkspaces: Int = 64,
        maximumParticipantsPerWorkspace: Int = 64,
        maximumDocumentsPerWorkspace: Int = 256,
        maximumDocumentUTF16Length: Int = 10_000_000,
        maximumRetainedEvents: Int = 2_048,
        maximumEditsPerOperation: Int = 256
    ) {
        self.maximumWorkspaces = max(1, maximumWorkspaces)
        self.maximumParticipantsPerWorkspace = max(1, maximumParticipantsPerWorkspace)
        self.maximumDocumentsPerWorkspace = max(1, maximumDocumentsPerWorkspace)
        self.maximumDocumentUTF16Length = max(1, maximumDocumentUTF16Length)
        self.maximumRetainedEvents = max(1, maximumRetainedEvents)
        self.maximumEditsPerOperation = max(1, maximumEditsPerOperation)
    }
}

public enum GrammarCollaborationError: Error, LocalizedError, Sendable {
    case invalidIdentity(String)
    case duplicateWorkspace(String)
    case unknownWorkspace(String)
    case duplicateDocument(String)
    case unknownDocument(String)
    case unknownParticipant(String)
    case staleDocument(documentID: String, expected: Int, actual: Int)
    case eventHistoryUnavailable(requested: Int, oldest: Int)
    case resourceLimit(String)

    public var code: String {
        switch self {
        case .invalidIdentity: "invalid-identity"
        case .duplicateWorkspace: "duplicate-workspace"
        case .unknownWorkspace: "unknown-workspace"
        case .duplicateDocument: "duplicate-document"
        case .unknownDocument: "unknown-document"
        case .unknownParticipant: "unknown-participant"
        case .staleDocument: "stale-document"
        case .eventHistoryUnavailable: "event-history-unavailable"
        case .resourceLimit: "resource-limit"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidIdentity(let value): "Collaboration identity ‘\(value)’ is empty or invalid."
        case .duplicateWorkspace(let id): "Collaborative workspace ‘\(id)’ already exists."
        case .unknownWorkspace(let id): "No collaborative workspace named ‘\(id)’ exists."
        case .duplicateDocument(let id): "Collaborative document ‘\(id)’ is duplicated."
        case .unknownDocument(let id): "No collaborative document named ‘\(id)’ exists."
        case .unknownParticipant(let id): "Participant ‘\(id)’ has not joined this workspace."
        case .staleDocument(let id, let expected, let actual):
            "Document ‘\(id)’ revision is \(actual), not expected revision \(expected)."
        case .eventHistoryUnavailable(let requested, let oldest):
            "Event sequence \(requested) is no longer retained; the oldest available sequence is \(oldest)."
        case .resourceLimit(let message): message
        }
    }
}

public protocol GrammarCollaborationHosting: Actor {
    func createWorkspace(
        id: String, owner: GrammarCollaborationParticipant,
        documents: [GrammarCollaborationDocument], operationID: String
    ) async throws -> GrammarCollaborationResult
    func join(
        workspaceID: String, participant: GrammarCollaborationParticipant,
        operationID: String
    ) async throws -> GrammarCollaborationResult
    func leave(
        workspaceID: String, participantID: String, operationID: String
    ) async throws -> GrammarCollaborationResult
    func apply(
        workspaceID: String, participantID: String, documentID: String,
        expectedRevision: Int, edits: [GrammarTextEdit], operationID: String
    ) async throws -> GrammarCollaborationResult
    func status(_ workspaceID: String) async throws -> GrammarCollaborationWorkspaceSnapshot
    func events(workspaceID: String, after sequence: Int) async throws -> [GrammarCollaborationEvent]
}

/// Transport-neutral hosted workspace state. The actor provides one total event
/// order per workspace, optimistic document concurrency, and operation replay.
public actor GrammarCollaborativeWorkbenchHost: GrammarCollaborationHosting {
    private struct Workspace {
        var revision = 0
        var documents: [String: GrammarTextSnapshot]
        var participants: [String: GrammarCollaborationParticipant]
        var events: [GrammarCollaborationEvent]
        var replay: [String: GrammarCollaborationResult]
        var nextSequence: Int
    }

    private var workspaces: [String: Workspace] = [:]
    public let limits: GrammarCollaborationLimits

    public init(limits: GrammarCollaborationLimits = .init()) { self.limits = limits }

    public init(
        restoring archive: GrammarCollaborationArchive,
        limits: GrammarCollaborationLimits = .init()
    ) throws {
        self.limits = limits
        guard archive.schemaVersion == GrammarCollaborationArchive.currentSchemaVersion else {
            throw GrammarCollaborationDurabilityError.unsupportedSchema(archive.schemaVersion)
        }
        guard archive.workspaces.count <= limits.maximumWorkspaces else {
            throw GrammarCollaborationDurabilityError.invalidArchive("The archive exceeds the workspace limit.")
        }
        var restored: [String: Workspace] = [:]
        for value in archive.workspaces {
            try Self.validate(value, limits: limits)
            guard restored[value.id] == nil else {
                throw GrammarCollaborationDurabilityError.invalidArchive("Workspace ‘\(value.id)’ is duplicated.")
            }
            restored[value.id] = Workspace(
                revision: value.revision,
                documents: Dictionary(uniqueKeysWithValues: value.documents.map { ($0.id, $0.text) }),
                participants: Dictionary(uniqueKeysWithValues: value.participants.map { ($0.id, $0) }),
                events: value.events, replay: value.replay,
                nextSequence: value.nextEventSequence
            )
        }
        workspaces = restored
    }

    public func createWorkspace(
        id: String, owner: GrammarCollaborationParticipant,
        documents: [GrammarCollaborationDocument], operationID: String
    ) throws -> GrammarCollaborationResult {
        try validateIdentity(id); try validateParticipant(owner); try validateIdentity(operationID)
        if let workspace = workspaces[id], let value = workspace.replay[operationID] {
            return .init(workspace: value.workspace, events: value.events, replayedOperation: true)
        }
        guard workspaces[id] == nil else { throw GrammarCollaborationError.duplicateWorkspace(id) }
        guard workspaces.count < limits.maximumWorkspaces else {
            throw GrammarCollaborationError.resourceLimit("The collaborative workspace limit was reached.")
        }
        guard documents.count <= limits.maximumDocumentsPerWorkspace else {
            throw GrammarCollaborationError.resourceLimit("The workspace document limit was reached.")
        }
        var stored: [String: GrammarTextSnapshot] = [:]
        for document in documents {
            try validateIdentity(document.id)
            guard stored[document.id] == nil else { throw GrammarCollaborationError.duplicateDocument(document.id) }
            try validateLength(document.text.text, id: document.id)
            stored[document.id] = document.text
        }
        let event = GrammarCollaborationEvent(
            sequence: 0, operationID: operationID, kind: .workspaceCreated,
            workspaceID: id, participantID: owner.id, documentID: nil,
            documentRevision: nil, change: nil
        )
        workspaces[id] = .init(
            documents: stored, participants: [owner.id: owner], events: [event],
            replay: [:], nextSequence: 1
        )
        let value = result(for: id, events: [event])
        workspaces[id]?.replay[operationID] = value
        return value
    }

    public func join(
        workspaceID: String, participant: GrammarCollaborationParticipant,
        operationID: String
    ) throws -> GrammarCollaborationResult {
        try validateParticipant(participant); try validateIdentity(operationID)
        if let replayed = try replay(workspaceID, operationID) { return replayed }
        guard var workspace = workspaces[workspaceID] else { throw GrammarCollaborationError.unknownWorkspace(workspaceID) }
        if workspace.participants[participant.id] == participant {
            return result(for: workspaceID, events: [], replayed: true)
        }
        guard workspace.participants.count < limits.maximumParticipantsPerWorkspace else {
            throw GrammarCollaborationError.resourceLimit("The workspace participant limit was reached.")
        }
        workspace.participants[participant.id] = participant
        workspace.revision += 1
        let event = makeEvent(
            workspaceID: workspaceID, workspace: &workspace, operationID: operationID,
            kind: .participantJoined, participantID: participant.id
        )
        workspaces[workspaceID] = workspace
        return storeReplay(workspaceID, operationID, events: [event])
    }

    public func leave(
        workspaceID: String, participantID: String, operationID: String
    ) throws -> GrammarCollaborationResult {
        if let replayed = try replay(workspaceID, operationID) { return replayed }
        guard var workspace = workspaces[workspaceID] else { throw GrammarCollaborationError.unknownWorkspace(workspaceID) }
        guard workspace.participants.removeValue(forKey: participantID) != nil else {
            throw GrammarCollaborationError.unknownParticipant(participantID)
        }
        workspace.revision += 1
        let event = makeEvent(
            workspaceID: workspaceID, workspace: &workspace, operationID: operationID,
            kind: .participantLeft, participantID: participantID
        )
        workspaces[workspaceID] = workspace
        return storeReplay(workspaceID, operationID, events: [event])
    }

    public func apply(
        workspaceID: String, participantID: String, documentID: String,
        expectedRevision: Int, edits: [GrammarTextEdit], operationID: String
    ) throws -> GrammarCollaborationResult {
        if let replayed = try replay(workspaceID, operationID) { return replayed }
        guard var workspace = workspaces[workspaceID] else { throw GrammarCollaborationError.unknownWorkspace(workspaceID) }
        guard workspace.participants[participantID] != nil else { throw GrammarCollaborationError.unknownParticipant(participantID) }
        guard let current = workspace.documents[documentID] else { throw GrammarCollaborationError.unknownDocument(documentID) }
        guard current.revision == expectedRevision else {
            throw GrammarCollaborationError.staleDocument(
                documentID: documentID, expected: expectedRevision, actual: current.revision
            )
        }
        guard !edits.isEmpty, edits.count <= limits.maximumEditsPerOperation else {
            throw GrammarCollaborationError.resourceLimit("A collaboration operation must contain 1...\(limits.maximumEditsPerOperation) edits.")
        }
        let applied = try current.applying(edits, revision: current.revision + 1)
        try validateLength(applied.snapshot.text, id: documentID)
        workspace.documents[documentID] = applied.snapshot
        workspace.revision += 1
        let event = makeEvent(
            workspaceID: workspaceID, workspace: &workspace, operationID: operationID,
            kind: .documentChanged, participantID: participantID,
            documentID: documentID, documentRevision: applied.snapshot.revision,
            change: applied.change
        )
        workspaces[workspaceID] = workspace
        return storeReplay(workspaceID, operationID, events: [event])
    }

    public func status(_ workspaceID: String) throws -> GrammarCollaborationWorkspaceSnapshot {
        guard workspaces[workspaceID] != nil else { throw GrammarCollaborationError.unknownWorkspace(workspaceID) }
        return snapshot(workspaceID)
    }

    public func events(
        workspaceID: String, after sequence: Int
    ) throws -> [GrammarCollaborationEvent] {
        guard let workspace = workspaces[workspaceID] else { throw GrammarCollaborationError.unknownWorkspace(workspaceID) }
        let oldest = workspace.events.first?.sequence ?? workspace.nextSequence
        guard sequence >= oldest - 1 else {
            throw GrammarCollaborationError.eventHistoryUnavailable(requested: sequence, oldest: oldest)
        }
        return workspace.events.filter { $0.sequence > sequence }
    }

    public var workspaceIDs: [String] { workspaces.keys.sorted() }

    public func archive() -> GrammarCollaborationArchive {
        .init(workspaces: workspaces.map { id, workspace in
            GrammarCollaborationWorkspaceArchive(
                id: id, revision: workspace.revision,
                documents: workspace.documents.map { .init(id: $0.key, snapshot: $0.value) }.sorted { $0.id < $1.id },
                participants: workspace.participants.values.sorted { $0.id < $1.id },
                events: workspace.events, replay: workspace.replay,
                nextEventSequence: workspace.nextSequence
            )
        }.sorted { $0.id < $1.id })
    }

    private func makeEvent(
        workspaceID: String, workspace: inout Workspace, operationID: String,
        kind: GrammarCollaborationEventKind, participantID: String,
        documentID: String? = nil, documentRevision: Int? = nil,
        change: GrammarTextChangeSummary? = nil
    ) -> GrammarCollaborationEvent {
        let event = GrammarCollaborationEvent(
            sequence: workspace.nextSequence, operationID: operationID, kind: kind,
            workspaceID: workspaceID, participantID: participantID,
            documentID: documentID, documentRevision: documentRevision, change: change
        )
        workspace.nextSequence += 1
        workspace.events.append(event)
        if workspace.events.count > limits.maximumRetainedEvents {
            workspace.events.removeFirst(workspace.events.count - limits.maximumRetainedEvents)
        }
        return event
    }

    private func storeReplay(
        _ workspaceID: String, _ operationID: String,
        events: [GrammarCollaborationEvent]
    ) -> GrammarCollaborationResult {
        let value = result(for: workspaceID, events: events)
        workspaces[workspaceID]?.replay[operationID] = value
        if let workspace = workspaces[workspaceID], workspace.replay.count > limits.maximumRetainedEvents {
            let retained = Set(workspace.events.map(\.operationID))
            workspaces[workspaceID]?.replay = workspace.replay.filter { retained.contains($0.key) }
        }
        return value
    }

    private func replay(_ workspaceID: String, _ operationID: String) throws -> GrammarCollaborationResult? {
        guard let workspace = workspaces[workspaceID] else { throw GrammarCollaborationError.unknownWorkspace(workspaceID) }
        guard let value = workspace.replay[operationID] else { return nil }
        return .init(workspace: value.workspace, events: value.events, replayedOperation: true)
    }

    private func result(
        for workspaceID: String, events: [GrammarCollaborationEvent], replayed: Bool = false
    ) -> GrammarCollaborationResult {
        .init(workspace: snapshot(workspaceID), events: events, replayedOperation: replayed)
    }

    private func snapshot(_ id: String) -> GrammarCollaborationWorkspaceSnapshot {
        let workspace = workspaces[id]!
        return .init(
            id: id, revision: workspace.revision,
            documents: workspace.documents.map { .init(id: $0.key, snapshot: $0.value) }.sorted { $0.id < $1.id },
            participants: workspace.participants.values.sorted { $0.id < $1.id },
            nextEventSequence: workspace.nextSequence,
            oldestAvailableEventSequence: workspace.events.first?.sequence ?? workspace.nextSequence
        )
    }

    private func validateIdentity(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= 256 else { throw GrammarCollaborationError.invalidIdentity(value) }
    }

    private func validateParticipant(_ value: GrammarCollaborationParticipant) throws {
        try validateIdentity(value.id); try validateIdentity(value.displayName)
    }

    private func validateLength(_ text: String, id: String) throws {
        guard text.utf16.count <= limits.maximumDocumentUTF16Length else {
            throw GrammarCollaborationError.resourceLimit("Document ‘\(id)’ exceeds the UTF-16 length limit.")
        }
    }

    private static func validate(
        _ value: GrammarCollaborationWorkspaceArchive,
        limits: GrammarCollaborationLimits
    ) throws {
        func validIdentity(_ string: String) -> Bool {
            !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && string.utf8.count <= 256
        }
        guard validIdentity(value.id), value.revision >= 0, value.nextEventSequence >= 0 else {
            throw GrammarCollaborationDurabilityError.invalidArchive("Workspace identity, revision, or event sequence is invalid.")
        }
        guard value.documents.count <= limits.maximumDocumentsPerWorkspace,
              value.participants.count <= limits.maximumParticipantsPerWorkspace,
              value.events.count <= limits.maximumRetainedEvents,
              value.replay.count <= limits.maximumRetainedEvents else {
            throw GrammarCollaborationDurabilityError.invalidArchive("Workspace ‘\(value.id)’ exceeds configured limits.")
        }
        guard Set(value.documents.map(\.id)).count == value.documents.count,
              Set(value.participants.map(\.id)).count == value.participants.count else {
            throw GrammarCollaborationDurabilityError.invalidArchive("Workspace ‘\(value.id)’ contains duplicate identities.")
        }
        for document in value.documents {
            guard validIdentity(document.id), document.text.revision >= 0,
                  document.text.text.utf16.count <= limits.maximumDocumentUTF16Length else {
                throw GrammarCollaborationDurabilityError.invalidArchive("Workspace ‘\(value.id)’ contains an invalid document.")
            }
        }
        guard value.participants.allSatisfy({ validIdentity($0.id) && validIdentity($0.displayName) }) else {
            throw GrammarCollaborationDurabilityError.invalidArchive("Workspace ‘\(value.id)’ contains an invalid participant.")
        }
        let sequences = value.events.map(\.sequence)
        let contiguous = zip(sequences, sequences.dropFirst()).allSatisfy { $1 == $0 + 1 }
        guard sequences.allSatisfy({ $0 >= 0 }), contiguous,
              value.events.allSatisfy({ $0.workspaceID == value.id && validIdentity($0.operationID) }),
              (sequences.last.map { value.nextEventSequence == $0 + 1 } ?? true),
              value.replay.allSatisfy({ operationID, result in
                  validIdentity(operationID)
                      && result.workspace.id == value.id
                      && result.events.allSatisfy { $0.workspaceID == value.id && $0.operationID == operationID }
              }) else {
            throw GrammarCollaborationDurabilityError.invalidArchive("Workspace ‘\(value.id)’ has inconsistent event or replay state.")
        }
    }
}

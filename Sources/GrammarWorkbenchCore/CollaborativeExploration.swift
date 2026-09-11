import Foundation

public struct GrammarCollaborativeExplorationPresence: Identifiable, Hashable, Codable, Sendable {
    public let participantID: String
    public let selectedRule: String
    public let documentRevision: Int
    public var id: String { participantID }

    public init(participantID: String, selectedRule: String, documentRevision: Int) {
        self.participantID = participantID
        self.selectedRule = selectedRule
        self.documentRevision = documentRevision
    }
}

public struct GrammarExplorationBookmark: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let rule: String
    public let note: String
    public let authorID: String
    public let documentRevision: Int

    public init(id: String, rule: String, note: String, authorID: String, documentRevision: Int) {
        self.id = id; self.rule = rule; self.note = note
        self.authorID = authorID; self.documentRevision = documentRevision
    }
}

public struct GrammarExplorationBookmarkProjection: Hashable, Codable, Sendable {
    public let bookmark: GrammarExplorationBookmark
    public let ruleExists: Bool
    public let isCurrentDocumentRevision: Bool
}

public enum GrammarCollaborativeExplorationEventKind: String, Hashable, Codable, Sendable {
    case focusChanged
    case bookmarkUpserted
    case bookmarkRemoved
}

public struct GrammarCollaborativeExplorationEvent: Identifiable, Hashable, Codable, Sendable {
    public let sequence: Int
    public let operationID: String
    public let kind: GrammarCollaborativeExplorationEventKind
    public let workspaceID: String
    public let documentID: String
    public let participantID: String
    public let documentRevision: Int
    public let selectedRule: String?
    public let bookmarkID: String?
    public var id: String { "\(workspaceID):\(documentID):\(sequence)" }
}

public struct GrammarCollaborativeExplorationSnapshot: Hashable, Codable, Sendable {
    public let workspaceID: String
    public let documentID: String
    public let documentRevision: Int
    public let exploration: GrammarExplorationSnapshot
    public let presences: [GrammarCollaborativeExplorationPresence]
    public let bookmarks: [GrammarExplorationBookmarkProjection]
    public let nextEventSequence: Int
    public let oldestAvailableEventSequence: Int
}

public struct GrammarCollaborativeExplorationResult: Hashable, Codable, Sendable {
    public let snapshot: GrammarCollaborativeExplorationSnapshot
    public let events: [GrammarCollaborativeExplorationEvent]
    public let replayedOperation: Bool
}

public enum GrammarCollaborativeExplorationError: Error, LocalizedError, Sendable {
    case staleDocument(expected: Int, actual: Int)
    case unknownRule(String)
    case unknownBookmark(String)
    case eventHistoryUnavailable(requested: Int, oldest: Int)
    case invalidValue(String)
    case resourceLimit(String)

    public var code: String {
        switch self {
        case .staleDocument: "stale-exploration-document"
        case .unknownRule: "unknown-exploration-rule"
        case .unknownBookmark: "unknown-exploration-bookmark"
        case .eventHistoryUnavailable: "exploration-history-unavailable"
        case .invalidValue: "invalid-exploration-value"
        case .resourceLimit: "exploration-resource-limit"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .staleDocument(let expected, let actual):
            "Exploration targets document revision \(actual), not expected revision \(expected)."
        case .unknownRule(let rule): "No grammar rule named ‘\(rule)’ exists."
        case .unknownBookmark(let id): "No exploration bookmark named ‘\(id)’ exists."
        case .eventHistoryUnavailable(let requested, let oldest):
            "Exploration event \(requested) is no longer retained; the oldest available sequence is \(oldest)."
        case .invalidValue(let message), .resourceLimit(let message): message
        }
    }
}

public struct GrammarCollaborativeExplorationLimits: Hashable, Codable, Sendable {
    public var maximumBookmarksPerDocument: Int
    public var maximumNoteUTF16Length: Int
    public var maximumRetainedEvents: Int

    public init(
        maximumBookmarksPerDocument: Int = 256,
        maximumNoteUTF16Length: Int = 4_096,
        maximumRetainedEvents: Int = 2_048
    ) {
        self.maximumBookmarksPerDocument = max(1, maximumBookmarksPerDocument)
        self.maximumNoteUTF16Length = max(1, maximumNoteUTF16Length)
        self.maximumRetainedEvents = max(1, maximumRetainedEvents)
    }
}

/// Shares navigation intent and review bookmarks over an authoritative
/// collaborative document. Derived grammar analysis is always rebuilt from the
/// current document and is never retained as mutable collaborative state.
public actor GrammarCollaborativeExplorer {
    private struct Key: Hashable { let workspaceID: String; let documentID: String }
    private struct State {
        var presences: [String: GrammarCollaborativeExplorationPresence] = [:]
        var bookmarks: [String: GrammarExplorationBookmark] = [:]
        var events: [GrammarCollaborativeExplorationEvent] = []
        var replay: [String: GrammarCollaborativeExplorationResult] = [:]
        var nextSequence = 0
    }

    private let collaboration: any GrammarCollaborationHosting
    private var states: [Key: State] = [:]
    public let limits: GrammarCollaborativeExplorationLimits

    public init(
        collaboration: any GrammarCollaborationHosting,
        limits: GrammarCollaborativeExplorationLimits = .init()
    ) {
        self.collaboration = collaboration; self.limits = limits
    }

    public func snapshot(
        workspaceID: String, documentID: String, participantID: String
    ) async throws -> GrammarCollaborativeExplorationSnapshot {
        let context = try await context(workspaceID, documentID, participantID)
        let key = Key(workspaceID: workspaceID, documentID: documentID)
        return try makeSnapshot(
            key: key, context: context,
            selectedRule: states[key]?.presences[participantID]?.selectedRule
        )
    }

    public func select(
        workspaceID: String, documentID: String, participantID: String,
        expectedDocumentRevision: Int, rule: String, operationID: String
    ) async throws -> GrammarCollaborativeExplorationResult {
        let key = Key(workspaceID: workspaceID, documentID: documentID)
        if let replay = states[key]?.replay[operationID] {
            return .init(snapshot: replay.snapshot, events: replay.events, replayedOperation: true)
        }
        try validateIdentity(operationID)
        let context = try await context(workspaceID, documentID, participantID)
        try validateRevision(expectedDocumentRevision, context.document.text.revision)
        let exploration = try GrammarInteractiveExplorer.snapshot(context.compilation, selectedRule: rule)
        guard exploration.selectedRule == rule else { throw GrammarCollaborativeExplorationError.unknownRule(rule) }
        var state = states[key] ?? State()
        state.presences[participantID] = .init(
            participantID: participantID, selectedRule: rule,
            documentRevision: context.document.text.revision
        )
        let event = appendEvent(
            to: &state, key: key, operationID: operationID, kind: .focusChanged,
            participantID: participantID, documentRevision: context.document.text.revision,
            selectedRule: rule, bookmarkID: nil
        )
        states[key] = state
        return try storeResult(key: key, operationID: operationID, events: [event], context: context)
    }

    public func upsertBookmark(
        workspaceID: String, documentID: String, participantID: String,
        expectedDocumentRevision: Int, bookmarkID: String, rule: String,
        note: String, operationID: String
    ) async throws -> GrammarCollaborativeExplorationResult {
        let key = Key(workspaceID: workspaceID, documentID: documentID)
        if let replay = states[key]?.replay[operationID] {
            return .init(snapshot: replay.snapshot, events: replay.events, replayedOperation: true)
        }
        try validateIdentity(operationID); try validateIdentity(bookmarkID)
        guard note.utf16.count <= limits.maximumNoteUTF16Length else {
            throw GrammarCollaborativeExplorationError.resourceLimit("The exploration bookmark note is too long.")
        }
        let context = try await context(workspaceID, documentID, participantID)
        try validateRevision(expectedDocumentRevision, context.document.text.revision)
        let exploration = try GrammarInteractiveExplorer.snapshot(context.compilation, selectedRule: rule)
        guard exploration.selectedRule == rule else { throw GrammarCollaborativeExplorationError.unknownRule(rule) }
        var state = states[key] ?? State()
        guard state.bookmarks[bookmarkID] != nil || state.bookmarks.count < limits.maximumBookmarksPerDocument else {
            throw GrammarCollaborativeExplorationError.resourceLimit("The exploration bookmark limit was reached.")
        }
        state.bookmarks[bookmarkID] = .init(
            id: bookmarkID, rule: rule, note: note, authorID: participantID,
            documentRevision: context.document.text.revision
        )
        let event = appendEvent(
            to: &state, key: key, operationID: operationID, kind: .bookmarkUpserted,
            participantID: participantID, documentRevision: context.document.text.revision,
            selectedRule: rule, bookmarkID: bookmarkID
        )
        states[key] = state
        return try storeResult(key: key, operationID: operationID, events: [event], context: context)
    }

    public func removeBookmark(
        workspaceID: String, documentID: String, participantID: String,
        expectedDocumentRevision: Int, bookmarkID: String, operationID: String
    ) async throws -> GrammarCollaborativeExplorationResult {
        let key = Key(workspaceID: workspaceID, documentID: documentID)
        if let replay = states[key]?.replay[operationID] {
            return .init(snapshot: replay.snapshot, events: replay.events, replayedOperation: true)
        }
        try validateIdentity(operationID)
        let context = try await context(workspaceID, documentID, participantID)
        try validateRevision(expectedDocumentRevision, context.document.text.revision)
        var state = states[key] ?? State()
        guard state.bookmarks.removeValue(forKey: bookmarkID) != nil else {
            throw GrammarCollaborativeExplorationError.unknownBookmark(bookmarkID)
        }
        let event = appendEvent(
            to: &state, key: key, operationID: operationID, kind: .bookmarkRemoved,
            participantID: participantID, documentRevision: context.document.text.revision,
            selectedRule: nil, bookmarkID: bookmarkID
        )
        states[key] = state
        return try storeResult(key: key, operationID: operationID, events: [event], context: context)
    }

    public func events(
        workspaceID: String, documentID: String, after sequence: Int
    ) throws -> [GrammarCollaborativeExplorationEvent] {
        let state = states[.init(workspaceID: workspaceID, documentID: documentID)] ?? State()
        let oldest = state.events.first?.sequence ?? state.nextSequence
        guard sequence >= oldest - 1 else {
            throw GrammarCollaborativeExplorationError.eventHistoryUnavailable(requested: sequence, oldest: oldest)
        }
        return state.events.filter { $0.sequence > sequence }
    }

    private typealias Context = (
        workspace: GrammarCollaborationWorkspaceSnapshot,
        document: GrammarCollaborationDocument,
        compilation: GrammarCompilation
    )

    private func context(_ workspaceID: String, _ documentID: String, _ participantID: String) async throws -> Context {
        let workspace = try await collaboration.status(workspaceID)
        guard workspace.participants.contains(where: { $0.id == participantID }) else {
            throw GrammarCollaborationError.unknownParticipant(participantID)
        }
        guard let document = workspace.documents.first(where: { $0.id == documentID }) else {
            throw GrammarCollaborationError.unknownDocument(documentID)
        }
        let compilation = GrammarWorkbenchAPI.compile(.init(source: document.text.text))
        _ = try GrammarInteractiveExplorer.snapshot(compilation)
        return (workspace, document, compilation)
    }

    private func makeSnapshot(
        key: Key, context: Context, selectedRule: String? = nil
    ) throws -> GrammarCollaborativeExplorationSnapshot {
        let state = states[key] ?? State()
        let currentRevision = context.document.text.revision
        let exploration = try GrammarInteractiveExplorer.snapshot(context.compilation, selectedRule: selectedRule)
        let rules = Set(exploration.rules.map(\.id))
        return .init(
            workspaceID: key.workspaceID, documentID: key.documentID,
            documentRevision: currentRevision, exploration: exploration,
            presences: state.presences.values.sorted { $0.participantID < $1.participantID },
            bookmarks: state.bookmarks.values.sorted { $0.id < $1.id }.map {
                .init(
                    bookmark: $0, ruleExists: rules.contains($0.rule),
                    isCurrentDocumentRevision: $0.documentRevision == currentRevision
                )
            },
            nextEventSequence: state.nextSequence,
            oldestAvailableEventSequence: state.events.first?.sequence ?? state.nextSequence
        )
    }

    private func storeResult(key: Key, operationID: String, events: [GrammarCollaborativeExplorationEvent], context: Context) throws -> GrammarCollaborativeExplorationResult {
        var state = states[key]!
        let value = GrammarCollaborativeExplorationResult(
            snapshot: try makeSnapshot(
                key: key, context: context, selectedRule: events.last?.selectedRule
            ), events: events,
            replayedOperation: false
        )
        state.replay[operationID] = value
        if state.replay.count > limits.maximumRetainedEvents {
            let retained = Set(state.events.map(\.operationID))
            state.replay = state.replay.filter { retained.contains($0.key) }
        }
        states[key] = state
        return value
    }

    private func appendEvent(
        to state: inout State, key: Key, operationID: String,
        kind: GrammarCollaborativeExplorationEventKind, participantID: String,
        documentRevision: Int, selectedRule: String?, bookmarkID: String?
    ) -> GrammarCollaborativeExplorationEvent {
        let event = GrammarCollaborativeExplorationEvent(
            sequence: state.nextSequence, operationID: operationID, kind: kind,
            workspaceID: key.workspaceID, documentID: key.documentID,
            participantID: participantID, documentRevision: documentRevision,
            selectedRule: selectedRule, bookmarkID: bookmarkID
        )
        state.nextSequence += 1; state.events.append(event)
        if state.events.count > limits.maximumRetainedEvents {
            state.events.removeFirst(state.events.count - limits.maximumRetainedEvents)
        }
        return event
    }

    private func validateRevision(_ expected: Int, _ actual: Int) throws {
        guard expected == actual else {
            throw GrammarCollaborativeExplorationError.staleDocument(expected: expected, actual: actual)
        }
    }

    private func validateIdentity(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.utf8.count <= 256 else {
            throw GrammarCollaborativeExplorationError.invalidValue("An exploration identity is empty or invalid.")
        }
    }
}

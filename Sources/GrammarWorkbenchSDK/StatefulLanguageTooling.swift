import Foundation
import GrammarWorkbench

public enum GrammarToolingEventKind: String, Hashable, Codable, Sendable {
    case sessionOpened
    case sessionClosed
    case grammarReplaced
    case documentAnalyzed
    case documentClosed
    case requestCancelled
}

public struct GrammarToolingEvent: Identifiable, Hashable, Codable, Sendable {
    public let sequence: Int
    public let kind: GrammarToolingEventKind
    public let sessionID: String?
    public let documentID: String?
    public let revision: Int?
    public let message: String
    public var id: String { "\(sessionID ?? "host"):\(sequence):\(kind.rawValue)" }

    public init(
        sequence: Int, kind: GrammarToolingEventKind, sessionID: String? = nil,
        documentID: String? = nil, revision: Int? = nil, message: String
    ) {
        self.sequence = sequence
        self.kind = kind
        self.sessionID = sessionID
        self.documentID = documentID
        self.revision = revision
        self.message = message
    }
}

public struct GrammarToolingSessionDocument: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let revision: Int
    public let parseStatus: GrammarParseStatus
    public let lexicalDiagnosticCount: Int
    public let syntaxDiagnosticCount: Int
    public let tokenCount: Int
    public let semanticEntryCount: Int

    init(_ snapshot: GrammarIncrementalAnalysisSnapshot) {
        id = snapshot.documentID
        revision = snapshot.text.revision
        parseStatus = snapshot.parse.status
        lexicalDiagnosticCount = snapshot.lexing.diagnostics.count
        syntaxDiagnosticCount = snapshot.parse.diagnostics.count
        tokenCount = snapshot.lexing.tokens.count
        semanticEntryCount = snapshot.semanticIndex.entries.count
    }
}

public struct GrammarToolingSessionSnapshot: Hashable, Codable, Sendable {
    public let id: String
    public let apiVersion: Int
    public let grammar: GrammarCompilationRequest
    public let grammarRevision: Int
    public let documents: [GrammarToolingSessionDocument]
    public let nextEventSequence: Int
    public let languageKitIdentifier: String?
}

public struct GrammarStatefulToolingLimits: Hashable, Codable, Sendable {
    public var maximumSessions: Int
    public var maximumDocumentsPerSession: Int
    public var maximumDocumentUTF16Length: Int

    public init(
        maximumSessions: Int = 32,
        maximumDocumentsPerSession: Int = 256,
        maximumDocumentUTF16Length: Int = 10_000_000
    ) {
        self.maximumSessions = max(1, maximumSessions)
        self.maximumDocumentsPerSession = max(1, maximumDocumentsPerSession)
        self.maximumDocumentUTF16Length = max(1, maximumDocumentUTF16Length)
    }
}

private actor GrammarToolingSessionState {
    let id: String
    private var compilation: GrammarCompilation
    private var coordinator: GrammarIncrementalAnalysisCoordinator
    private var documents: [String: GrammarIncrementalAnalysisSnapshot] = [:]
    private var grammarRevision = 0
    private var eventSequence = 0
    private var operationIsActive = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []
    private let limits: GrammarStatefulToolingLimits
    private var languageKitIdentifier: String?

    init(
        id: String, compilation: GrammarCompilation, limits: GrammarStatefulToolingLimits,
        languageKitIdentifier: String? = nil
    ) throws {
        self.id = id
        self.compilation = compilation
        self.limits = limits
        self.languageKitIdentifier = languageKitIdentifier
        coordinator = try GrammarIncrementalAnalysisCoordinator(compilation: compilation)
    }

    func opened() -> (GrammarToolingSessionSnapshot, GrammarToolingEvent) {
        let value = event(.sessionOpened, message: "Opened tooling session ‘\(id)’")
        return (snapshot(), value)
    }

    func status() async -> GrammarToolingSessionSnapshot {
        await acquireOperation()
        defer { releaseOperation() }
        return snapshot()
    }

    func openDocument(
        id documentID: String, text: String, revision: Int?
    ) async throws -> (GrammarToolingSessionSnapshot, GrammarIncrementalAnalysisSnapshot, GrammarToolingEvent) {
        await acquireOperation()
        defer { releaseOperation() }
        guard documents[documentID] == nil else { throw StatefulToolingError.duplicateDocument(documentID) }
        guard documents.count < limits.maximumDocumentsPerSession else {
            throw StatefulToolingError.resourceLimit("The session document limit was reached.")
        }
        guard text.utf16.count <= limits.maximumDocumentUTF16Length else {
            throw StatefulToolingError.resourceLimit("Document ‘\(documentID)’ exceeds the UTF-16 length limit.")
        }
        let value = try await coordinator.synchronizeDocument(
            id: documentID, text: text, externalRevision: revision
        )
        documents[documentID] = value
        let notification = event(
            .documentAnalyzed, documentID: documentID, revision: value.text.revision,
            message: "Opened and analyzed document ‘\(documentID)’"
        )
        return (snapshot(), value, notification)
    }

    func changeDocument(
        id documentID: String, edits: [GrammarTextEdit], revision: Int?
    ) async throws -> (GrammarToolingSessionSnapshot, GrammarIncrementalAnalysisSnapshot, GrammarToolingEvent) {
        await acquireOperation()
        defer { releaseOperation() }
        guard let current = documents[documentID] else { throw StatefulToolingError.unknownDocument(documentID) }
        let nextRevision = max(current.text.revision + 1, revision ?? 0)
        let preview = try current.text.applying(edits, revision: nextRevision)
        guard preview.snapshot.text.utf16.count <= limits.maximumDocumentUTF16Length else {
            throw StatefulToolingError.resourceLimit("Document ‘\(documentID)’ exceeds the UTF-16 length limit.")
        }
        let value = try await coordinator.apply(
            documentID: documentID, edits: edits, externalRevision: revision
        )
        documents[documentID] = value
        let notification = event(
            .documentAnalyzed, documentID: documentID, revision: value.text.revision,
            message: "Incrementally analyzed document ‘\(documentID)’"
        )
        return (snapshot(), value, notification)
    }

    func closeDocument(
        id documentID: String
    ) async throws -> (GrammarToolingSessionSnapshot, GrammarToolingEvent) {
        await acquireOperation()
        defer { releaseOperation() }
        guard documents.removeValue(forKey: documentID) != nil else {
            throw StatefulToolingError.unknownDocument(documentID)
        }
        await coordinator.closeDocument(id: documentID)
        let notification = event(
            .documentClosed, documentID: documentID,
            message: "Closed document ‘\(documentID)’"
        )
        return (snapshot(), notification)
    }

    func replaceGrammar(
        _ replacement: GrammarCompilation
    ) async throws -> (GrammarToolingSessionSnapshot, GrammarToolingEvent) {
        await acquireOperation()
        defer { releaseOperation() }
        let refreshed = try await coordinator.updateCompilation(replacement)
        compilation = replacement
        languageKitIdentifier = nil
        grammarRevision += 1
        documents = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.documentID, $0) })
        let notification = event(
            .grammarReplaced,
            message: "Recompiled \(documents.count) open document(s) against grammar revision \(grammarRevision)"
        )
        return (snapshot(), notification)
    }

    func closed() async -> (GrammarToolingSessionSnapshot, GrammarToolingEvent) {
        await acquireOperation()
        defer { releaseOperation() }
        let value = event(.sessionClosed, message: "Closed tooling session ‘\(id)’")
        return (snapshot(), value)
    }

    private func snapshot() -> GrammarToolingSessionSnapshot {
        .init(
            id: id, apiVersion: GrammarWorkbenchAPIVersion.current,
            grammar: compilation.request, grammarRevision: grammarRevision,
            documents: documents.values.map(GrammarToolingSessionDocument.init).sorted { $0.id < $1.id },
            nextEventSequence: eventSequence,
            languageKitIdentifier: languageKitIdentifier
        )
    }

    private func event(
        _ kind: GrammarToolingEventKind, documentID: String? = nil,
        revision: Int? = nil, message: String
    ) -> GrammarToolingEvent {
        defer { eventSequence += 1 }
        return .init(
            sequence: eventSequence, kind: kind, sessionID: id,
            documentID: documentID, revision: revision, message: message
        )
    }

    private func acquireOperation() async {
        if !operationIsActive {
            operationIsActive = true
            return
        }
        await withCheckedContinuation { operationWaiters.append($0) }
    }

    private func releaseOperation() {
        if operationWaiters.isEmpty {
            operationIsActive = false
        } else {
            operationWaiters.removeFirst().resume()
        }
    }
}

public actor GrammarStatefulLanguageToolingService {
    private var sessions: [String: GrammarToolingSessionState] = [:]
    private let stateless = GrammarLanguageToolingService()
    private let collaborationHost: any GrammarCollaborationHosting
    private let collaborativeExplorer: GrammarCollaborativeExplorer
    private let hostedLanguageKits: any GrammarHostedLanguageKitServing
    public let limits: GrammarStatefulToolingLimits

    public init(
        limits: GrammarStatefulToolingLimits = .init(),
        collaborationHost: any GrammarCollaborationHosting = GrammarCollaborativeWorkbenchHost(),
        hostedLanguageKits: any GrammarHostedLanguageKitServing = GrammarHostedLanguageKitService()
    ) {
        self.limits = limits
        self.collaborationHost = collaborationHost
        self.collaborativeExplorer = GrammarCollaborativeExplorer(collaboration: collaborationHost)
        self.hostedLanguageKits = hostedLanguageKits
    }

    public func handle(_ request: GrammarToolingRequest) async -> GrammarToolingResponse {
        guard request.schemaVersion == GrammarToolingSchema.current else {
            return failure(request, "unsupported-schema", "Unsupported tooling schema version \(request.schemaVersion).")
        }
        guard request.apiVersion == GrammarWorkbenchAPIVersion.current else {
            return failure(request, "unsupported-api", "Unsupported Grammar Workbench API version \(request.apiVersion).")
        }
        do {
            try Task.checkCancellation()
            switch request.operation {
            case .capabilities:
                return .init(requestID: request.requestID, capabilities: .current)
            case .sessionOpen:
                let kit = try request.languageKit.map {
                    try GrammarSemanticLanguageKit.compile($0)
                }
                let compilation: GrammarCompilation
                if let kit {
                    compilation = kit.compilation
                } else {
                    compilation = GrammarWorkbenchAPI.compile(
                        try required(request.compilation, "compilation or languageKit")
                    )
                }
                guard compilation.succeeded else {
                    return failure(
                        request, "compilation-failed",
                        compilation.diagnostics.first?.message ?? "The session grammar did not compile."
                    )
                }
                let id = request.sessionID ?? UUID().uuidString
                guard sessions[id] == nil else { throw StatefulToolingError.duplicateSession(id) }
                guard sessions.count < limits.maximumSessions else {
                    throw StatefulToolingError.resourceLimit("The tooling session limit was reached.")
                }
                let state = try GrammarToolingSessionState(
                    id: id, compilation: compilation, limits: limits,
                    languageKitIdentifier: kit?.manifest.identifier
                )
                sessions[id] = state
                let (session, event) = await state.opened()
                return .init(
                    requestID: request.requestID, compilation: compilationSnapshot(compilation),
                    session: session, events: [event]
                )
            case .sessionClose:
                let id = try required(request.sessionID, "sessionID")
                guard let state = sessions.removeValue(forKey: id) else {
                    throw StatefulToolingError.unknownSession(id)
                }
                let (session, event) = await state.closed()
                return .init(requestID: request.requestID, session: session, events: [event])
            case .sessionStatus:
                let state = try session(for: request)
                return .init(requestID: request.requestID, session: await state.status())
            case .sessionReplaceGrammar:
                let state = try session(for: request)
                let compilation = GrammarWorkbenchAPI.compile(try required(request.compilation, "compilation"))
                guard compilation.succeeded else {
                    return failure(
                        request, "compilation-failed",
                        compilation.diagnostics.first?.message ?? "The replacement grammar did not compile."
                    )
                }
                let (session, event) = try await state.replaceGrammar(compilation)
                return .init(
                    requestID: request.requestID, compilation: compilationSnapshot(compilation),
                    session: session, events: [event]
                )
            case .documentOpen:
                let state = try session(for: request)
                let (session, document, event) = try await state.openDocument(
                    id: required(request.documentID, "documentID"),
                    text: required(request.input, "input"), revision: request.revision
                )
                return .init(
                    requestID: request.requestID, session: session,
                    document: document, events: [event]
                )
            case .documentChange:
                let state = try session(for: request)
                let (session, document, event) = try await state.changeDocument(
                    id: required(request.documentID, "documentID"),
                    edits: required(request.edits, "edits"), revision: request.revision
                )
                return .init(
                    requestID: request.requestID, session: session,
                    document: document, events: [event]
                )
            case .documentClose:
                let state = try session(for: request)
                let (session, event) = try await state.closeDocument(
                    id: required(request.documentID, "documentID")
                )
                return .init(requestID: request.requestID, session: session, events: [event])
            case .collaborationCreate:
                let value = try await collaborationHost.createWorkspace(
                    id: required(request.workspaceID, "workspaceID"),
                    owner: required(request.participant, "participant"),
                    documents: request.collaborationDocuments ?? [],
                    operationID: required(request.operationID, "operationID")
                )
                return .init(requestID: request.requestID, collaboration: value)
            case .collaborationJoin:
                let value = try await collaborationHost.join(
                    workspaceID: required(request.workspaceID, "workspaceID"),
                    participant: required(request.participant, "participant"),
                    operationID: required(request.operationID, "operationID")
                )
                return .init(requestID: request.requestID, collaboration: value)
            case .collaborationLeave:
                let value = try await collaborationHost.leave(
                    workspaceID: required(request.workspaceID, "workspaceID"),
                    participantID: required(request.participant, "participant").id,
                    operationID: required(request.operationID, "operationID")
                )
                return .init(requestID: request.requestID, collaboration: value)
            case .collaborationStatus:
                let value = try await collaborationHost.status(
                    required(request.workspaceID, "workspaceID")
                )
                return .init(requestID: request.requestID, collaborationWorkspace: value)
            case .collaborationChange:
                let value = try await collaborationHost.apply(
                    workspaceID: required(request.workspaceID, "workspaceID"),
                    participantID: required(request.participant, "participant").id,
                    documentID: required(request.documentID, "documentID"),
                    expectedRevision: required(request.expectedRevision, "expectedRevision"),
                    edits: required(request.edits, "edits"),
                    operationID: required(request.operationID, "operationID")
                )
                return .init(requestID: request.requestID, collaboration: value)
            case .collaborationEvents:
                let value = try await collaborationHost.events(
                    workspaceID: required(request.workspaceID, "workspaceID"),
                    after: request.afterEventSequence ?? -1
                )
                return .init(requestID: request.requestID, collaborationEvents: value)
            case .collaborationExplore:
                let value = try await collaborativeExplorer.snapshot(
                    workspaceID: required(request.workspaceID, "workspaceID"),
                    documentID: required(request.documentID, "documentID"),
                    participantID: required(request.participant, "participant").id
                )
                return .init(requestID: request.requestID, collaborativeExplorationSnapshot: value)
            case .collaborationExploreSelect:
                let value = try await collaborativeExplorer.select(
                    workspaceID: required(request.workspaceID, "workspaceID"),
                    documentID: required(request.documentID, "documentID"),
                    participantID: required(request.participant, "participant").id,
                    expectedDocumentRevision: required(request.expectedRevision, "expectedRevision"),
                    rule: required(request.selectedRule, "selectedRule"),
                    operationID: required(request.operationID, "operationID")
                )
                return .init(requestID: request.requestID, collaborativeExploration: value)
            case .collaborationBookmarkUpsert:
                let value = try await collaborativeExplorer.upsertBookmark(
                    workspaceID: required(request.workspaceID, "workspaceID"),
                    documentID: required(request.documentID, "documentID"),
                    participantID: required(request.participant, "participant").id,
                    expectedDocumentRevision: required(request.expectedRevision, "expectedRevision"),
                    bookmarkID: required(request.bookmarkID, "bookmarkID"),
                    rule: required(request.selectedRule, "selectedRule"),
                    note: request.bookmarkNote ?? "",
                    operationID: required(request.operationID, "operationID")
                )
                return .init(requestID: request.requestID, collaborativeExploration: value)
            case .collaborationBookmarkRemove:
                let value = try await collaborativeExplorer.removeBookmark(
                    workspaceID: required(request.workspaceID, "workspaceID"),
                    documentID: required(request.documentID, "documentID"),
                    participantID: required(request.participant, "participant").id,
                    expectedDocumentRevision: required(request.expectedRevision, "expectedRevision"),
                    bookmarkID: required(request.bookmarkID, "bookmarkID"),
                    operationID: required(request.operationID, "operationID")
                )
                return .init(requestID: request.requestID, collaborativeExploration: value)
            case .collaborationExplorationEvents:
                let value = try await collaborativeExplorer.events(
                    workspaceID: required(request.workspaceID, "workspaceID"),
                    documentID: required(request.documentID, "documentID"),
                    after: request.afterEventSequence ?? -1
                )
                return .init(requestID: request.requestID, collaborativeExplorationEvents: value)
            case .languageKitHostPublish:
                let value = try await hostedLanguageKits.publish(
                    try required(request.languageKitPackage, "languageKitPackage"),
                    publisherID: try required(request.publisherID, "publisherID"),
                    operationID: try required(request.operationID, "operationID")
                )
                return .init(requestID: request.requestID, hostedLanguageKit: value)
            case .languageKitHostWithdraw, .languageKitHostRestore:
                let version = try GrammarLanguageKitVersion(
                    try required(request.packageVersion, "packageVersion")
                )
                let value = try await hostedLanguageKits.setWithdrawn(
                    identifier: try required(request.packageIdentifier, "packageIdentifier"),
                    version: version, withdrawn: request.operation == .languageKitHostWithdraw,
                    publisherID: try required(request.publisherID, "publisherID"),
                    operationID: try required(request.operationID, "operationID")
                )
                return .init(requestID: request.requestID, hostedLanguageKit: value)
            case .languageKitHostPackage:
                let value = try await hostedLanguageKits.package(
                    identifier: try required(request.packageIdentifier, "packageIdentifier"),
                    version: try GrammarLanguageKitVersion(
                        try required(request.packageVersion, "packageVersion")
                    ),
                    includeWithdrawn: request.includeWithdrawn ?? false
                )
                return .init(requestID: request.requestID, hostedLanguageKitRecord: value)
            case .languageKitHostCatalog:
                let value = await hostedLanguageKits.catalog(
                    includeWithdrawn: request.includeWithdrawn ?? false
                )
                return .init(requestID: request.requestID, hostedLanguageKitCatalog: value)
            case .languageKitHostResolve:
                let value = try await hostedLanguageKits.resolve(
                    try required(request.languageKitRoots, "languageKitRoots")
                )
                return .init(requestID: request.requestID, hostedLanguageKitResolution: value)
            case .languageKitHostEvents:
                let value = try await hostedLanguageKits.events(after: request.afterEventSequence ?? -1)
                return .init(requestID: request.requestID, hostedLanguageKitEvents: value)
            case .cancel:
                return failure(
                    request, "request-registry-required",
                    "Cancellation must be sent through GrammarToolingRequestRegistry."
                )
            case .generalizedParse:
                let compilation = GrammarWorkbenchAPI.compile(try required(request.compilation, "compilation"))
                let result = await compilation.parseGeneralizedCancellable(
                    try required(request.input, "input"), options: request.generalizedOptions ?? .init()
                )
                try Task.checkCancellation()
                return .init(
                    requestID: request.requestID, compilation: compilationSnapshot(compilation),
                    generalizedParse: result
                )
            default:
                return await stateless.handle(request)
            }
        } catch is CancellationError {
            return failure(request, "cancelled", "Request ‘\(request.requestID)’ was cancelled.")
        } catch let error as StatefulToolingError {
            return failure(request, error.code, error.localizedDescription)
        } catch let error as GrammarCollaborationError {
            return failure(request, error.code, error.localizedDescription)
        } catch let error as GrammarCollaborationDurabilityError {
            return failure(request, error.code, error.localizedDescription)
        } catch let error as GrammarCollaborativeExplorationError {
            return failure(request, error.code, error.localizedDescription)
        } catch let error as GrammarHostedLanguageKitError {
            return failure(request, error.code, error.localizedDescription)
        } catch {
            return failure(request, "invalid-request", error.localizedDescription)
        }
    }

    public var openSessionIDs: [String] { sessions.keys.sorted() }

    private func session(for request: GrammarToolingRequest) throws -> GrammarToolingSessionState {
        let id = try required(request.sessionID, "sessionID")
        guard let value = sessions[id] else { throw StatefulToolingError.unknownSession(id) }
        return value
    }

    private func required<Value>(_ value: Value?, _ name: String) throws -> Value {
        guard let value else { throw MissingStatefulPayload(name: name) }
        return value
    }

    private func failure(
        _ request: GrammarToolingRequest, _ code: String, _ message: String
    ) -> GrammarToolingResponse {
        .init(
            requestID: request.requestID, status: .failure,
            error: .init(code: code, message: message)
        )
    }

    private func compilationSnapshot(_ value: GrammarCompilation) -> GrammarToolingCompilationResult {
        .init(
            succeeded: value.succeeded, diagnostics: value.diagnostics,
            grammar: value.grammar, analysis: value.analysis,
            artifact: value.artifact, performance: value.performance
        )
    }
}

/// Tracks in-flight requests so a concurrent `cancel` envelope can terminate a
/// cooperative operation by its public request identifier.
public actor GrammarToolingRequestRegistry {
    private let service: GrammarStatefulLanguageToolingService
    private var requests: [String: Task<GrammarToolingResponse, Never>] = [:]
    private var hostEventSequence = 0

    public init(service: GrammarStatefulLanguageToolingService = .init()) {
        self.service = service
    }

    public var activeRequestIDs: [String] { requests.keys.sorted() }

    public func handle(_ request: GrammarToolingRequest) async -> GrammarToolingResponse {
        if request.operation == .cancel {
            guard let target = request.targetRequestID else {
                return .init(
                    requestID: request.requestID, status: .failure,
                    error: .init(code: "invalid-request", message: "The ‘targetRequestID’ payload is required for cancellation.")
                )
            }
            let existed = requests[target] != nil
            requests[target]?.cancel()
            let event = GrammarToolingEvent(
                sequence: hostEventSequence, kind: .requestCancelled,
                message: existed ? "Cancelled request ‘\(target)’" : "Request ‘\(target)’ was not active"
            )
            hostEventSequence += 1
            return .init(requestID: request.requestID, events: [event])
        }
        guard requests[request.requestID] == nil else {
            return .init(
                requestID: request.requestID, status: .failure,
                error: .init(code: "duplicate-request", message: "Request ‘\(request.requestID)’ is already active.")
            )
        }
        let task = Task { await service.handle(request) }
        requests[request.requestID] = task
        let response = await task.value
        requests[request.requestID] = nil
        return response
    }
}

public struct GrammarStatefulInProcessToolingTransport: GrammarToolingTransport {
    private let registry: GrammarToolingRequestRegistry

    public init(registry: GrammarToolingRequestRegistry = .init()) { self.registry = registry }

    public func send(_ request: Data) async throws -> Data {
        try await GrammarToolingCodec.encode(
            registry.handle(GrammarToolingCodec.decodeRequest(request))
        )
    }
}

private struct MissingStatefulPayload: LocalizedError {
    let name: String
    var errorDescription: String? { "The ‘\(name)’ payload is required for this operation." }
}

private enum StatefulToolingError: LocalizedError {
    case duplicateSession(String)
    case unknownSession(String)
    case duplicateDocument(String)
    case unknownDocument(String)
    case resourceLimit(String)

    var code: String {
        switch self {
        case .duplicateSession: "duplicate-session"
        case .unknownSession: "unknown-session"
        case .duplicateDocument: "duplicate-document"
        case .unknownDocument: "unknown-document"
        case .resourceLimit: "resource-limit"
        }
    }

    var errorDescription: String? {
        switch self {
        case .duplicateSession(let id): "Tooling session ‘\(id)’ is already open."
        case .unknownSession(let id): "No tooling session named ‘\(id)’ is open."
        case .duplicateDocument(let id): "Document ‘\(id)’ is already open."
        case .unknownDocument(let id): "Document ‘\(id)’ is not open."
        case .resourceLimit(let message): message
        }
    }
}

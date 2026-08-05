import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport

/// A `Connection` that can also be closed, as required for server shutdown.
///
/// The LSP `Connection` protocol only defines message sending; the concrete
/// connections additionally expose `close()`. This protocol preserves the
/// ability to close from code that only holds an existential.
public protocol ServerConnection: Connection {
    func close()
}

extension JSONRPCConnection: ServerConnection {}
extension LocalConnection: ServerConnection {}

/// The Grammar Workbench language server.
///
/// This is the generic LSP front-end for the Grammar Workbench parser
/// ecosystem: a developer supplies a grammar and the server instantly provides
/// IDE services for the resulting language.
///
/// M0 (this milestone) establishes the protocol skeleton: `initialize`,
/// `shutdown`/`exit` handling, and full-document text synchronization. Later
/// milestones add diagnostics, folding ranges, document symbols, and
/// completion powered by `GrammarCompilation`.
public actor GrammarWorkbenchLSPServer: MessageHandler {
    /// Storage of open documents, mirroring client editor contents.
    public let documentStore: DocumentStore

    /// The connection to the client, used to send notifications.
    private let connection: any ServerConnection

    /// Whether the client has sent a `shutdown` request. Drives the process
    /// exit code: the LSP spec requires exit code 0 only if shutdown was
    /// received.
    private var shutdownReceived: Bool = false

    public init(connection: any ServerConnection, documentStore: DocumentStore = DocumentStore()) {
        self.connection = connection
        self.documentStore = documentStore
    }

    /// Whether the client has sent the LSP `shutdown` request.
    public var hasReceivedShutdown: Bool { shutdownReceived }

    // MARK: - MessageHandler

    public nonisolated func handle(_ notification: some NotificationType) {
        if let didOpen = notification as? DidOpenTextDocumentNotification {
            Task { await self.didOpen(didOpen) }
        } else if let didChange = notification as? DidChangeTextDocumentNotification {
            Task { await self.didChange(didChange) }
        } else if let didClose = notification as? DidCloseTextDocumentNotification {
            Task { await self.didClose(didClose) }
        } else if notification is InitializedNotification {
            // The client has fully initialized; nothing to do in M0.
        } else if notification is ExitNotification {
            Task { await self.handleExit() }
        }
        // Other notifications are intentionally ignored in M0.
    }

    public nonisolated func handle<Request: RequestType>(
        _ request: Request,
        id: RequestID,
        reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
    ) {
        if let initialize = request as? InitializeRequest {
            Task { reply(.success(await self.initialize(initialize) as! Request.Response)) }
        } else if let shutdown = request as? ShutdownRequest {
            Task { reply(.success(await self.shutdown(shutdown) as! Request.Response)) }
        } else {
            reply(.failure(.methodNotFound(Request.method)))
        }
    }

    // MARK: - Requests

    private func initialize(_ request: InitializeRequest) -> InitializeResult {
        let syncOptions = TextDocumentSyncOptions(openClose: true, change: .full)
        return InitializeResult(
            capabilities: ServerCapabilities(textDocumentSync: .options(syncOptions))
        )
    }

    private func shutdown(_ request: ShutdownRequest) -> ShutdownRequest.Response {
        shutdownReceived = true
        return ShutdownRequest.Response()
    }

    // MARK: - Notifications

    private func didOpen(_ notification: DidOpenTextDocumentNotification) async {
        let item = notification.textDocument
        await documentStore.open(
            uri: item.uri,
            language: item.language,
            version: item.version,
            text: item.text
        )
    }

    private func didChange(_ notification: DidChangeTextDocumentNotification) async {
        let identifier = notification.textDocument
        await documentStore.updateFull(
            uri: identifier.uri,
            version: identifier.version,
            contentChanges: notification.contentChanges
        )
    }

    private func didClose(_ notification: DidCloseTextDocumentNotification) async {
        await documentStore.close(uri: notification.textDocument.uri)
    }

    private func handleExit() async {
        connection.close()
    }
}

import Foundation
import GrammarWorkbench
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
/// M0 established the protocol skeleton: `initialize`, `shutdown`/`exit`
/// handling, and full-document text synchronization. M1 adds
/// `textDocument/publishDiagnostics` for grammar documents (compile errors)
/// and source documents (lexical and parse errors) using the open grammars.
/// Later milestones add folding ranges, document symbols, and completion
/// powered by `GrammarCompilation`.
public actor GrammarWorkbenchLSPServer: MessageHandler {
    /// Storage of open documents, mirroring client editor contents.
    public let documentStore: DocumentStore

    /// The connection to the client, used to send notifications.
    private let connection: any ServerConnection

    /// Compiles open grammars and produces diagnostics for both grammar and
    /// source documents.
    private let diagnosticsManager: DiagnosticsManager

    /// Whether the client has sent a `shutdown` request. Drives the process
    /// exit code: the LSP spec requires exit code 0 only if shutdown was
    /// received.
    private var shutdownReceived: Bool = false

    /// Debounced diagnostics after document changes: each keystroke produces a
    /// `didChange`, and re-analyzing the document for every one of them is
    /// wasteful. Changes schedule a publish that supersedes any pending one.
    private var pendingPublishes: [DocumentURI: Task<Void, Never>] = [:]

    /// How long to wait after the last change before re-analyzing a document.
    private let publishDebounce: Duration = .milliseconds(150)

    public init(
        connection: any ServerConnection,
        documentStore: DocumentStore = DocumentStore(),
        diagnosticsManager: DiagnosticsManager = DiagnosticsManager()
    ) {
        self.connection = connection
        self.documentStore = documentStore
        self.diagnosticsManager = diagnosticsManager
    }

    /// Whether the client has sent the LSP `shutdown` request.
    public var hasReceivedShutdown: Bool { shutdownReceived }

    // MARK: - MessageHandler

    public nonisolated func handle(_ notification: some NotificationType) {
        if let didOpen = notification as? DidOpenTextDocumentNotification {
            Task { await self.didOpen(didOpen) }
        } else if let didChange = notification as? DidChangeTextDocumentNotification {
            Task { await self.didChange(didChange) }
        } else if let didSave = notification as? DidSaveTextDocumentNotification {
            Task { await self.didSave(didSave) }
        } else if let didClose = notification as? DidCloseTextDocumentNotification {
            Task { await self.didClose(didClose) }
        } else if notification is InitializedNotification {
            // The client has fully initialized; nothing to do here.
        } else if notification is ExitNotification {
            Task { await self.handleExit() }
        }
        // Other notifications are intentionally ignored.
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
        } else if let folding = request as? FoldingRangeRequest {
            Task { reply(.success(await self.foldingRanges(folding) as! Request.Response)) }
        } else if let symbols = request as? DocumentSymbolRequest {
            Task { reply(.success(await self.documentSymbols(symbols) as! Request.Response)) }
        } else if let completion = request as? CompletionRequest {
            Task { reply(.success(await self.completions(completion) as! Request.Response)) }
        } else if let hover = request as? HoverRequest {
            Task { reply(.success(await self.hover(hover) as! Request.Response)) }
        } else if let definition = request as? DefinitionRequest {
            Task { reply(.success(await self.definitions(definition) as! Request.Response)) }
        } else {
            reply(.failure(.methodNotFound(Request.method)))
        }
    }

    // MARK: - Requests

    /// Folding ranges for the document at `request`'s URI, derived from the
    /// parse tree of the document's grammar.
    private func foldingRanges(_ request: FoldingRangeRequest) async -> [FoldingRange]? {
        guard let (tree, text) = await syntaxTree(for: request.textDocument.uri) else { return nil }
        return SyntaxTreeOutline(tree: tree, text: text).foldingRanges
    }

    /// Hierarchical document symbols for the document at `request`'s URI,
    /// derived from the parse tree of the document's grammar.
    private func documentSymbols(_ request: DocumentSymbolRequest) async -> DocumentSymbolResponse? {
        guard let (tree, text) = await syntaxTree(for: request.textDocument.uri) else { return nil }
        return .documentSymbols(SyntaxTreeOutline(tree: tree, text: text).documentSymbols)
    }

    /// Completion items for the document at `request`'s URI. Grammar documents
    /// complete directives and grammar symbols; source documents complete the
    /// terminals the parser expects at the cursor position.
    private func completions(_ request: CompletionRequest) async -> CompletionList {
        guard let document = await documentStore.document(for: request.textDocument.uri) else {
            return CompletionList(isIncomplete: false, items: [])
        }
        switch document.uri.grammarWorkbenchKind {
        case .grammar(let notation):
            guard notation == .workbench,
                  let compilation = await diagnosticsManager.compilation(for: document.uri),
                  let grammar = compilation.parsedGrammar
            else {
                return CompletionList(isIncomplete: false, items: [])
            }
            return GrammarDocumentProvider.completions(
                in: document.text, at: request.position, grammar: grammar
            )
        case .source:
            guard let compilation = await diagnosticsManager.exactGrammarCompilation(for: document.language.rawValue) else {
                return CompletionList(isIncomplete: false, items: [])
            }
            return CompletionProvider.completions(in: document.text, at: request.position, compilation: compilation)
        }
    }

    /// Hover information for the token at `request`'s position: productions
    /// and rules in grammar documents, token + matched production in source
    /// documents.
    private func hover(_ request: HoverRequest) async -> HoverResponse? {
        guard let document = await documentStore.document(for: request.textDocument.uri) else { return nil }
        switch document.uri.grammarWorkbenchKind {
        case .grammar(let notation):
            guard notation == .workbench,
                  let compilation = await diagnosticsManager.compilation(for: document.uri),
                  let grammar = compilation.parsedGrammar
            else {
                return nil
            }
            return GrammarDocumentProvider.hover(
                in: document.text, at: request.position, grammar: grammar
            )
        case .source:
            guard let compilation = await diagnosticsManager.exactGrammarCompilation(for: document.language.rawValue) else {
                return nil
            }
            return HoverProvider.hover(in: document.text, at: request.position, compilation: compilation)
        }
    }

    /// Go-to-definition for the symbol under `request`'s position. Grammar
    /// documents jump between symbols; source documents jump to the token's
    /// rule in the grammar document.
    private func definitions(_ request: DefinitionRequest) async -> LocationsOrLocationLinksResponse? {
        guard let document = await documentStore.document(for: request.textDocument.uri) else { return nil }
        switch document.uri.grammarWorkbenchKind {
        case .grammar(let notation):
            guard notation == .workbench,
                  let compilation = await diagnosticsManager.compilation(for: document.uri),
                  let grammar = compilation.parsedGrammar
            else {
                return nil
            }
            return GrammarDocumentProvider.definitions(
                in: document.text, at: request.position, grammar: grammar, uri: document.uri
            )
        case .source:
            guard let compilation = await diagnosticsManager.exactGrammarCompilation(for: document.language.rawValue),
                  let grammarURI = await diagnosticsManager.grammarDocumentURI(for: document.language.rawValue)
            else {
                return nil
            }
            return GrammarDocumentProvider.definitions(
                in: document.text, at: request.position,
                compilation: compilation, grammarURI: grammarURI
            )
        }
    }

    /// Parses the source document at `uri` with its associated grammar and
    /// returns the syntax tree together with the document text, used to
    /// resolve token positions for grammars without lexer rules.
    private func syntaxTree(for uri: DocumentURI) async -> (tree: GrammarSyntaxNode, text: String)? {
        guard let document = await documentStore.document(for: uri),
              uri.grammarWorkbenchKind == .source,
              let compilation = await diagnosticsManager.grammarCompilation(for: document.language.rawValue),
              let tree = compilation.parse(document.text).syntaxTree
        else {
            return nil
        }
        return (tree, document.text)
    }

    private func initialize(_ request: InitializeRequest) -> InitializeResult {
        let syncOptions = TextDocumentSyncOptions(
            openClose: true,
            change: .full,
            willSave: false,
            willSaveWaitUntil: false,
            save: .value(TextDocumentSyncOptions.SaveOptions(includeText: true))
        )
        return InitializeResult(
            capabilities: ServerCapabilities(
                textDocumentSync: .options(syncOptions),
                hoverProvider: .bool(true),
                completionProvider: CompletionOptions(),
                definitionProvider: .bool(true),
                documentSymbolProvider: .bool(true),
                foldingRangeProvider: .bool(true)
            )
        )
    }

    private func shutdown(_ request: ShutdownRequest) -> ShutdownRequest.Response {
        shutdownReceived = true
        for pending in pendingPublishes.values {
            pending.cancel()
        }
        pendingPublishes.removeAll()
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
        await publishDiagnostics(for: item.uri)
    }

    private func didChange(_ notification: DidChangeTextDocumentNotification) async {
        let identifier = notification.textDocument
        await documentStore.updateFull(
            uri: identifier.uri,
            version: identifier.version,
            contentChanges: notification.contentChanges
        )
        schedulePublish(for: identifier.uri)
    }

    private func didSave(_ notification: DidSaveTextDocumentNotification) async {
        let identifier = notification.textDocument
        if let text = notification.text {
            // `didSave` carries no version; the document is replaced in place.
            await documentStore.updateSavedText(uri: identifier.uri, text: text)
        }
        // A save is the natural settle point for any pending change analysis.
        pendingPublishes[identifier.uri]?.cancel()
        pendingPublishes[identifier.uri] = nil
        await publishDiagnostics(for: identifier.uri)
    }

    private func didClose(_ notification: DidCloseTextDocumentNotification) async {
        let uri = notification.textDocument.uri
        let kind = uri.grammarWorkbenchKind
        pendingPublishes[uri]?.cancel()
        pendingPublishes[uri] = nil
        await documentStore.close(uri: uri)
        // Publish an empty set so the client clears diagnostics for the
        // document, as required by the LSP spec.
        connection.send(PublishDiagnosticsNotification(uri: uri, diagnostics: []))
        guard case .grammar = kind else { return }
        await diagnosticsManager.removeGrammar(uri: uri)
        // Source documents lose (or change) their grammar; re-analyze them all.
        await republishSourceDiagnostics()
    }

    /// Computes and publishes diagnostics for the document at `uri`. Grammar
    /// documents are compiled, source documents are parsed with the grammar
    /// associated with their language id. Source documents are also re-analyzed
    /// whenever a grammar document changes.
    private func publishDiagnostics(for uri: DocumentURI) async {
        guard let document = await documentStore.document(for: uri) else { return }
        switch uri.grammarWorkbenchKind {
        case .grammar(let notation):
            let compilation = await diagnosticsManager.compileGrammar(
                uri: uri, source: document.text, notation: notation
            )
            let diagnostics = await diagnosticsManager.lspDiagnostics(
                compilation: compilation, grammarSource: document.text
            )
            connection.send(PublishDiagnosticsNotification(
                uri: uri, version: document.version, diagnostics: diagnostics
            ))
            await republishSourceDiagnostics()
        case .source:
            guard let compilation = await diagnosticsManager.grammarCompilation(for: document.language.rawValue) else {
                // No grammar is open; clear any stale diagnostics.
                connection.send(PublishDiagnosticsNotification(uri: uri, version: document.version, diagnostics: []))
                return
            }
            let diagnostics = await diagnosticsManager.lspDiagnostics(
                compilation: compilation, sourceText: document.text
            )
            connection.send(PublishDiagnosticsNotification(
                uri: uri, version: document.version, diagnostics: diagnostics
            ))
        }
    }

    /// Schedules a debounced re-analysis of the document at `uri`, superseding
    /// any pending one. Changes that arrive in quick succession (typing)
    /// therefore only trigger one analysis once the text settles.
    private func schedulePublish(for uri: DocumentURI) {
        pendingPublishes[uri]?.cancel()
        let task = Task {
            try? await Task.sleep(for: self.publishDebounce)
            guard !Task.isCancelled else { return }
            await self.publishDiagnostics(for: uri)
            self.clearPendingPublish(for: uri)
        }
        pendingPublishes[uri] = task
    }

    private func clearPendingPublish(for uri: DocumentURI) {
        pendingPublishes[uri] = nil
    }

    private func republishSourceDiagnostics() async {
        for uri in await documentStore.openURIs where uri.grammarWorkbenchKind == .source {
            await publishDiagnostics(for: uri)
        }
    }

    private func handleExit() async {
        connection.close()
    }
}

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
/// Later milestones add folding ranges, document symbols, completion, hover,
/// definitions, semantic tokens, references, rename, quick fixes, progress
/// reporting and request cancellation, and — most recently — document
/// highlights, formatting, and document links, all powered by
/// `GrammarCompilation`.
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

    /// Requests that are still being processed, keyed by request id, so a
    /// `$/cancelRequest` can cancel them.
    private var inFlightRequests: [RequestID: Task<Void, Never>] = [:]

    /// A test seam: when set, every request handler awaits it before doing
    /// work, which lets tests cancel requests deterministically.
    private var requestGate: (@Sendable () async -> Void)?

    /// Sequence number for the server's own progress tokens.
    private var progressCounter = 0

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

    /// Test seam: requests await `gate` before doing work.
    internal func setRequestGate(_ gate: (@Sendable () async -> Void)?) {
        requestGate = gate
    }

    /// Whether the request `id` is still being processed. Test seam.
    internal func isRequestInFlight(_ id: RequestID) -> Bool {
        inFlightRequests[id] != nil
    }

    /// The tokens of every work-done progress notification sent so far,
    /// in arrival order. Test seam.
    internal private(set) var workDoneProgressNotifications: [ProgressToken] = []

    // MARK: - MessageHandler

    public nonisolated func handle(_ notification: some NotificationType) {
        if let cancel = notification as? CancelRequestNotification {
            Task { await self.cancelRequest(id: cancel.id) }
        } else if let didOpen = notification as? DidOpenTextDocumentNotification {
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
            respond(id: id, gated: false, reply: reply) { .success(await self.initialize(initialize) as! Request.Response) }
        } else if let shutdown = request as? ShutdownRequest {
            respond(id: id, gated: false, reply: reply) { .success(await self.shutdown(shutdown) as! Request.Response) }
        } else if let folding = request as? FoldingRangeRequest {
            respond(id: id, reply: reply) { .success(await self.foldingRanges(folding) as! Request.Response) }
        } else if let symbols = request as? DocumentSymbolRequest {
            respond(id: id, reply: reply) { .success(await self.documentSymbols(symbols) as! Request.Response) }
        } else if let completion = request as? CompletionRequest {
            respond(id: id, reply: reply) { .success(await self.completions(completion) as! Request.Response) }
        } else if let hover = request as? HoverRequest {
            respond(id: id, reply: reply) { .success(await self.hover(hover) as! Request.Response) }
        } else if let definition = request as? DefinitionRequest {
            respond(id: id, reply: reply) { .success(await self.definitions(definition) as! Request.Response) }
        } else if let tokens = request as? DocumentSemanticTokensRequest {
            respond(id: id, reply: reply) { .success(await self.semanticTokens(tokens) as! Request.Response) }
        } else if let references = request as? ReferencesRequest {
            respond(id: id, reply: reply) { .success(await self.references(references) as! Request.Response) }
        } else if let rename = request as? RenameRequest {
            respond(id: id, reply: reply) { await self.rename(rename) as! LSPResult<Request.Response> }
        } else if let codeActions = request as? CodeActionRequest {
            respond(id: id, reply: reply) { .success(await self.codeActions(codeActions) as! Request.Response) }
        } else if let highlights = request as? DocumentHighlightRequest {
            respond(id: id, reply: reply) { .success(await self.documentHighlights(highlights) as! Request.Response) }
        } else if let formatting = request as? DocumentFormattingRequest {
            respond(id: id, reply: reply) { .success(await self.formatting(formatting) as! Request.Response) }
        } else if let rangeFormatting = request as? DocumentRangeFormattingRequest {
            respond(id: id, reply: reply) { .success(await self.rangeFormatting(rangeFormatting) as! Request.Response) }
        } else if let links = request as? DocumentLinkRequest {
            respond(id: id, reply: reply) { .success(await self.documentLinks(links) as! Request.Response) }
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
            Task { reply(.success(await self.definition(definition) as! Request.Response)) }
        } else if let action = request as? CodeActionRequest {
            Task { reply(.success(await self.codeActions(action) as! Request.Response)) }
        } else {
            reply(.failure(.methodNotFound(Request.method)))
        }
    }

    /// Runs `body` in a tracked task: the task is registered under `id` so
    /// `$/cancelRequest` can cancel it, awaits the request gate (a test seam),
    /// and replies with `.cancelled` when the request was cancelled before
    /// the work completed.
    private nonisolated func respond<Response>(
        id: RequestID,
        gated: Bool = true,
        reply: @escaping @Sendable (LSPResult<Response>) -> Void,
        body: @escaping @Sendable () async -> LSPResult<Response>
    ) {
        let task = Task {
            if gated {
                await self.waitIfGated()
            }
            guard !Task.isCancelled else {
                reply(.failure(.cancelled))
                return
            }
            reply(await body())
            await self.untrack(id: id)
        }
        Task { await self.track(id: id, task: task) }
    }

    private func track(id: RequestID, task: Task<Void, Never>) {
        inFlightRequests[id] = task
    }

    private func untrack(id: RequestID) {
        inFlightRequests[id] = nil
    }

    private func cancelRequest(id: RequestID) {
        inFlightRequests.removeValue(forKey: id)?.cancel()
    }

    private func waitIfGated() async {
        await requestGate?()
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

    /// Semantic tokens for the document at `request`'s URI. Grammar documents
    /// tokenize directives, symbols, and punctuation; source documents
    /// classify the parse tree's terminals by their token rule.
    private func semanticTokens(_ request: DocumentSemanticTokensRequest) async -> DocumentSemanticTokensResponse? {
        guard let document = await documentStore.document(for: request.textDocument.uri) else { return nil }
        switch document.uri.grammarWorkbenchKind {
        case .grammar(let notation):
            guard notation == .workbench,
                  let compilation = await diagnosticsManager.compilation(for: document.uri),
                  let grammar = compilation.parsedGrammar
            else {
                return nil
            }
            return SemanticTokensProvider.semanticTokens(in: document.text, grammar: grammar)
        case .source:
            guard let compilation = await diagnosticsManager.exactGrammarCompilation(for: document.language.rawValue) else {
                return nil
            }
            return SemanticTokensProvider.semanticTokens(in: document.text, compilation: compilation)
        }
    }

    /// References to the nonterminal (or token name) under `request`'s
    /// position within the grammar document: production left-hand sides and
    /// body uses, `%token` declarations and rule uses.
    private func references(_ request: ReferencesRequest) async -> [Location] {
        guard let document = await documentStore.document(for: request.textDocument.uri),
              document.uri.grammarWorkbenchKind == .grammar(notation: .workbench),
              let compilation = await diagnosticsManager.compilation(for: document.uri),
              let grammar = compilation.parsedGrammar
        else {
            return []
        }
        return GrammarDocumentProvider.references(
            in: document.text,
            at: request.position,
            grammar: grammar,
            uri: document.uri,
            includeDeclaration: request.context.includeDeclaration
        )
    }

    /// Renames the nonterminal (or token name) under `request`'s position in
    /// the grammar document, replacing every occurrence.
    private func rename(_ request: RenameRequest) async -> LSPResult<WorkspaceEdit?> {
        guard let document = await documentStore.document(for: request.textDocument.uri),
              document.uri.grammarWorkbenchKind == .grammar(notation: .workbench),
              let compilation = await diagnosticsManager.compilation(for: document.uri),
              let grammar = compilation.parsedGrammar
        else {
            return .success(nil)
        }
        return GrammarDocumentProvider.rename(
            in: document.text,
            at: request.position,
            newName: request.newName,
            grammar: grammar,
            uri: document.uri
        )
    }

    /// Quick fixes for the diagnostics under `request`'s range: recovery
    /// actions for source documents (insert or delete the recovered token),
    /// syntax fixes for grammar documents.
    private func codeActions(_ request: CodeActionRequest) async -> CodeActionRequestResponse? {
        guard let document = await documentStore.document(for: request.textDocument.uri) else { return nil }
        switch document.uri.grammarWorkbenchKind {
        case .grammar(let notation):
            guard notation == .workbench,
                  let compilation = await diagnosticsManager.compilation(for: document.uri)
            else {
                return nil
            }
            return .codeActions(RecoveryCodeActionProvider.grammarCodeActions(
                in: document.text, range: request.range, compilation: compilation, uri: document.uri
            ))
        case .source:
            guard let compilation = await diagnosticsManager.exactGrammarCompilation(for: document.language.rawValue) else {
                return nil
            }
            return .codeActions(RecoveryCodeActionProvider.recoveryCodeActions(
                in: document.text, range: request.range, compilation: compilation, uri: document.uri
            ))
        }
        if case .grammar(let notation) = document.uri.grammarWorkbenchKind {
            return GrammarDocumentService.completions(
                text: document.text, position: request.position, notation: notation
            )
        }
        guard document.uri.grammarWorkbenchKind == .source,
              let compilation = await diagnosticsManager.exactGrammarCompilation(for: document.language.rawValue)
        else {
            return CompletionList(isIncomplete: false, items: [])
        }
        return CompletionProvider.completions(in: document.text, at: request.position, compilation: compilation)
    }

    private func definition(_ request: DefinitionRequest) async -> LocationsOrLocationLinksResponse? {
        guard let document = await documentStore.document(for: request.textDocument.uri),
              case .grammar(let notation) = document.uri.grammarWorkbenchKind else { return nil }
        return GrammarDocumentService.definition(
            uri: document.uri, text: document.text, position: request.position, notation: notation
        )
    }

    private func codeActions(_ request: CodeActionRequest) async -> CodeActionRequestResponse? {
        guard let document = await documentStore.document(for: request.textDocument.uri),
              case .grammar(let notation) = document.uri.grammarWorkbenchKind else { return nil }
        return GrammarDocumentService.codeActions(
            uri: document.uri, text: document.text, notation: notation,
            requestedRange: request.range
        )
    }

    /// Hover information for the token at `request`'s position, derived from
    /// the parse tree and the productions that matched it.
    private func hover(_ request: HoverRequest) async -> HoverResponse? {
        guard let document = await documentStore.document(for: request.textDocument.uri),
              document.uri.grammarWorkbenchKind == .source,
              let compilation = await diagnosticsManager.exactGrammarCompilation(for: document.language.rawValue)
        else {
            return nil
        }
        return HoverProvider.hover(in: document.text, at: request.position, compilation: compilation)
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

    /// The ranges to highlight for the symbol under `request`'s position.
    /// Grammar documents highlight every occurrence of a nonterminal, token
    /// name, or terminal literal; source documents highlight tokens with the
    /// same kind and lexeme.
    private func documentHighlights(_ request: DocumentHighlightRequest) async -> [DocumentHighlight]? {
        guard let document = await documentStore.document(for: request.textDocument.uri) else { return nil }
        switch document.uri.grammarWorkbenchKind {
        case .grammar(let notation):
            guard notation == .workbench,
                  let compilation = await diagnosticsManager.compilation(for: document.uri),
                  let grammar = compilation.parsedGrammar
            else {
                return nil
            }
            return DocumentHighlightProvider.highlights(
                in: document.text, at: request.position, grammar: grammar
            )
        case .source:
            guard let compilation = await diagnosticsManager.exactGrammarCompilation(for: document.language.rawValue) else {
                return nil
            }
            return DocumentHighlightProvider.highlights(
                in: document.text, at: request.position, compilation: compilation
            )
        }
    }

    /// The edits that canonicalize the grammar document at `request`'s URI.
    /// Other document kinds and notations are not formatted.
    private func formatting(_ request: DocumentFormattingRequest) async -> [TextEdit]? {
        guard let document = await documentStore.document(for: request.textDocument.uri),
              document.uri.grammarWorkbenchKind == .grammar(notation: .workbench)
        else {
            return nil
        }
        return GrammarDocumentFormatter.format(document.text, options: request.options)
    }

    /// The edits that canonicalize the lines of the grammar document inside
    /// `request`'s range. Other document kinds and notations are not
    /// formatted.
    private func rangeFormatting(_ request: DocumentRangeFormattingRequest) async -> [TextEdit]? {
        guard let document = await documentStore.document(for: request.textDocument.uri),
              document.uri.grammarWorkbenchKind == .grammar(notation: .workbench)
        else {
            return nil
        }
        return GrammarDocumentFormatter.format(document.text, options: request.options, range: request.range)
    }

    /// Document links for the document at `request`'s URI: source tokens link
    /// to their rules in the grammar document; grammar documents have no
    /// external targets.
    private func documentLinks(_ request: DocumentLinkRequest) async -> [DocumentLink]? {
        guard let document = await documentStore.document(for: request.textDocument.uri) else { return nil }
        switch document.uri.grammarWorkbenchKind {
        case .grammar:
            return []
        case .source:
            guard let compilation = await diagnosticsManager.exactGrammarCompilation(for: document.language.rawValue),
                  let grammarURI = await diagnosticsManager.grammarDocumentURI(for: document.language.rawValue)
            else {
                return nil
            }
            return DocumentLinkProvider.links(
                in: document.text, compilation: compilation, grammarURI: grammarURI
            )
        }
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
                referencesProvider: .value(ReferenceOptions()),
                documentHighlightProvider: .bool(true),
                documentSymbolProvider: .bool(true),
                codeActionProvider: .value(CodeActionServerCapabilities(
                    clientCapabilities: request.capabilities.textDocument?.codeAction,
                    codeActionOptions: CodeActionOptions(codeActionKinds: [.quickFix]),
                    supportsCodeActions: true
                )),
                documentFormattingProvider: .bool(true),
                documentRangeFormattingProvider: .bool(true),
                renameProvider: .value(RenameOptions()),
                documentLinkProvider: DocumentLinkOptions(),
                foldingRangeProvider: .bool(true),
                semanticTokensProvider: SemanticTokensOptions(
                    legend: SemanticTokensProvider.legend,
                    full: .value(SemanticTokensOptions.SemanticTokensFullOptions())
                ),
                documentSymbolProvider: .bool(true),
                codeActionProvider: .bool(true),
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

    /// Re-analyzes every open source document, reporting progress. Called
    /// whenever a grammar document is compiled or closed, since either can
    /// change the diagnostics of every associated source document.
    private func republishSourceDiagnostics() async {
        let sources = await documentStore.openURIs.filter { $0.grammarWorkbenchKind == .source }
        guard !sources.isEmpty else { return }
        let token = await beginWorkDone(title: "Grammar Workbench", message: "Analyzing source documents")
        for (index, uri) in sources.enumerated() {
            await publishDiagnostics(for: uri)
            if let token {
                reportWorkDone(
                    token,
                    message: "Analyzed \(index + 1)/\(sources.count) documents",
                    percentage: Int(Double(index + 1) / Double(sources.count) * 100)
                )
            }
        }
        if let token {
            endWorkDone(token, message: "\(sources.count) document(s) analyzed")
        }
    }

    // MARK: - Work done progress

    /// Asks the client to create a work-done progress token. Returns `nil`
    /// when the client does not support progress.
    private func beginWorkDone(title: String, message: String?) async -> ProgressToken? {
        progressCounter += 1
        let token = ProgressToken.string("grammar-workbench-\(progressCounter)")
        let created = await withCheckedContinuation { continuation in
            connection.send(CreateWorkDoneProgressRequest(token: token)) { result in
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case .failure:
                    continuation.resume(returning: false)
                }
            }
        }
        guard created else { return nil }
        workDoneProgressNotifications.append(token)
        connection.send(WorkDoneProgress(
            token: token,
            value: .begin(WorkDoneProgressBegin(title: title, message: message))
        ))
        return token
    }

    private func reportWorkDone(_ token: ProgressToken, message: String, percentage: Int) {
        workDoneProgressNotifications.append(token)
        connection.send(WorkDoneProgress(
            token: token,
            value: .report(WorkDoneProgressReport(message: message, percentage: percentage))
        ))
    }

    private func endWorkDone(_ token: ProgressToken, message: String) {
        workDoneProgressNotifications.append(token)
        connection.send(WorkDoneProgress(
            token: token,
            value: .end(WorkDoneProgressEnd(message: message))
        ))
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

import Foundation
import XCTest
import LanguageServerProtocol
import LanguageServerProtocolTransport
@testable import GrammarWorkbenchLSP

final class GrammarWorkbenchLSPServerTests: XCTestCase {
    private var client: TestClient!
    private var server: GrammarWorkbenchLSPServer!
    /// The connection the client uses to send messages to the server.
    private var connection: LocalConnection!
    /// The connection the server uses to send messages back to the client.
    private var clientConnection: LocalConnection!

    override func setUp() {
        super.setUp()
        client = TestClient()
        clientConnection = LocalConnection(receiverName: "client")
        clientConnection.start(handler: client)
        server = GrammarWorkbenchLSPServer(connection: clientConnection)
        connection = LocalConnection(receiverName: "server")
        connection.start(handler: server)
    }

    override func tearDown() {
        connection.close()
        clientConnection.close()
        server = nil
        client = nil
        connection = nil
        clientConnection = nil
        super.tearDown()
    }

    private var mockURI: DocumentURI {
        DocumentURI(filePath: "/tmp/mock-document.txt", isDirectory: false)
    }

    /// Sends `request` from the client to the server and awaits the reply.
    private func send<Request: RequestType>(
        _ request: Request,
        id: Int = 1
    ) async -> LSPResult<Request.Response> {
        await withCheckedContinuation { continuation in
            connection.send(request, id: .number(id)) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// Polls `condition` until it returns true or `timeout` elapses. Notifications
    /// are handled by the server in separate tasks, so tests must wait for them.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    func testInitializeReturnsFullTextSyncCapabilities() async {
        let result = await send(InitializeRequest(
            processId: nil,
            rootPath: nil,
            rootURI: nil,
            capabilities: ClientCapabilities(),
            workspaceFolders: nil
        ))
        guard case .success(let initializeResult) = result else {
            return XCTFail("initialize failed: \(result)")
        }
        guard case .options(let sync) = initializeResult.capabilities.textDocumentSync else {
            return XCTFail(
                "expected textDocumentSync options, got \(String(describing: initializeResult.capabilities.textDocumentSync))"
            )
        }
        XCTAssertEqual(sync.openClose, true)
        XCTAssertEqual(sync.change, .full)
        XCTAssertEqual(sync.willSave, false)
        XCTAssertEqual(sync.willSaveWaitUntil, false)
        if case .value(let save) = sync.save {
            XCTAssertEqual(save.includeText, true)
        } else {
            XCTFail("expected didSave sync options with included text, got \(String(describing: sync.save))")
        }
    }

    func testShutdownRepliesAndSetsExitState() async {
        _ = await send(InitializeRequest(
            processId: nil,
            rootURI: nil,
            capabilities: ClientCapabilities(),
            workspaceFolders: nil
        ))
        let result = await send(ShutdownRequest())
        guard case .success = result else {
            return XCTFail("shutdown failed: \(result)")
        }
        let hasReceivedShutdown = await server.hasReceivedShutdown
        XCTAssertTrue(hasReceivedShutdown)
    }

    func testUnknownRequestRepliesMethodNotFound() async {
        let result: LSPResult<WorkspaceFoldersRequest.Response> = await send(WorkspaceFoldersRequest())
        guard case .failure(let error) = result else {
            return XCTFail("expected methodNotFound failure, got \(result)")
        }
        XCTAssertEqual(error.code, .methodNotFound)
    }

    func testDidOpenStoresDocument() async {
        let uri = DocumentURI(filePath: "/tmp/test.grammar", isDirectory: false)
        connection.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
            uri: uri,
            language: Language(rawValue: "mygrammar"),
            version: 1,
            text: "hello world"
        )))
        let stored = await waitUntil { await self.server.documentStore.text(for: uri) == "hello world" }
        XCTAssertTrue(stored, "server did not store the opened document")
    }

    func testDidChangeFullSyncReplacesDocument() async {
        let uri = DocumentURI(filePath: "/tmp/test.grammar", isDirectory: false)
        connection.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
            uri: uri,
            language: Language(rawValue: "grammar"),
            version: 1,
            text: "first version"
        )))
        connection.send(DidChangeTextDocumentNotification(
            textDocument: VersionedTextDocumentIdentifier(uri, version: 2),
            contentChanges: [TextDocumentContentChangeEvent(range: nil, rangeLength: nil, text: "second version")]
        ))
        let replaced = await waitUntil { await self.server.documentStore.text(for: uri) == "second version" }
        XCTAssertTrue(replaced, "server did not apply the full-sync change")
        let version = await server.documentStore.document(for: uri)?.version
        XCTAssertEqual(version, 2)
    }

    func testDidCloseRemovesDocument() async {
        let uri = DocumentURI(filePath: "/tmp/test.txt", isDirectory: false)
        connection.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
            uri: uri,
            language: Language(rawValue: "grammar"),
            version: 1,
            text: "content"
        )))
        connection.send(DidCloseTextDocumentNotification(textDocument: TextDocumentIdentifier(uri)))
        let removed = await waitUntil { await self.server.documentStore.text(for: uri) == nil }
        XCTAssertTrue(removed, "server did not remove the closed document")
    }

    func testUnknownNotificationIsIgnored() async throws {
        // A notification our server does not handle must not crash the server.
        connection.send(SetTraceNotification(value: .off))
        try await Task.sleep(for: .milliseconds(50))
        let uris = await server.documentStore.openURIs
        XCTAssertTrue(uris.isEmpty)
    }

    // MARK: - M1: publishDiagnostics

    private func openDocument(uri: DocumentURI, language: String, text: String) {
        connection.send(DidOpenTextDocumentNotification(textDocument: TextDocumentItem(
            uri: uri,
            language: Language(rawValue: language),
            version: 1,
            text: text
        )))
    }

    private func changeDocument(uri: DocumentURI, version: Int, text: String) {
        connection.send(DidChangeTextDocumentNotification(
            textDocument: VersionedTextDocumentIdentifier(uri, version: version),
            contentChanges: [TextDocumentContentChangeEvent(range: nil, rangeLength: nil, text: text)]
        ))
    }

    func testGrammarDocumentWithSyntaxErrorPublishesDiagnostics() async {
        let uri = DocumentURI(filePath: "/tmp/expr.grammarworkbench", isDirectory: false)
        // `'b ;` opens a terminal literal that is never closed.
        openDocument(uri: uri, language: "grammar", text: "%start S\nS : 'a' 'b ;\n")
        let published = await waitUntil { !self.client.publishDiagnostics(uri: uri).isEmpty }
        XCTAssertTrue(published, "server did not publish grammar diagnostics")
        let notification = client.publishDiagnostics(uri: uri).last!
        XCTAssertEqual(notification.version, 1)
        guard let diagnostic = notification.diagnostics.first(where: { $0.message == "Unterminated terminal literal." }) else {
            return XCTFail("expected unterminated-terminal diagnostic, got \(notification.diagnostics)")
        }
        XCTAssertEqual(diagnostic.severity, .error)
        XCTAssertEqual(diagnostic.source, "grammar-workbench")
        XCTAssertEqual(diagnostic.range.lowerBound.line, 1)
        XCTAssertEqual(diagnostic.range.lowerBound.utf16index, 8)
    }

    func testValidGrammarPublishesEmptyDiagnostics() async {
        let uri = DocumentURI(filePath: "/tmp/expr.grammarworkbench", isDirectory: false)
        openDocument(uri: uri, language: "grammar", text: "%start S\nS : 'hello' 'world' ;\n")
        let published = await waitUntil { !self.client.publishDiagnostics(uri: uri).isEmpty }
        XCTAssertTrue(published, "server did not publish diagnostics for the grammar")
        let notification = client.publishDiagnostics(uri: uri).last!
        XCTAssertTrue(notification.diagnostics.isEmpty, "valid grammar reported diagnostics: \(notification.diagnostics)")
    }

    func testGrammarDidChangeRepublishesDiagnostics() async {
        let uri = DocumentURI(filePath: "/tmp/expr.grammarworkbench", isDirectory: false)
        openDocument(uri: uri, language: "grammar", text: "%start S\nS : 'hello' 'world' ;\n")
        let validPublished = await waitUntil { !self.client.publishDiagnostics(uri: uri).isEmpty }
        XCTAssertTrue(validPublished)
        XCTAssertTrue(client.publishDiagnostics(uri: uri).last?.diagnostics.isEmpty ?? false)

        changeDocument(uri: uri, version: 2, text: "%start S\nS : 'hello' 'world ;\n")
        let broken = await waitUntil {
            guard let notification = self.client.publishDiagnostics(uri: uri).last else { return false }
            return !notification.diagnostics.isEmpty
        }
        XCTAssertTrue(broken, "server did not republish diagnostics after the grammar broke")

        changeDocument(uri: uri, version: 3, text: "%start S\nS : 'hello' 'world' ;\n")
        let fixed = await waitUntil {
            let diagnostics = self.client.publishDiagnostics(uri: uri).last?.diagnostics
            return diagnostics?.isEmpty ?? false
        }
        XCTAssertTrue(fixed, "server did not clear diagnostics after the grammar was fixed")
    }

    func testSourceDocumentPublishesSyntaxDiagnostics() async {
        let grammarURI = DocumentURI(filePath: "/tmp/expr.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: "%start S\nS : 'hello' 'world' ;\n")

        // The source language id `expr` matches the grammar's base name.
        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "expr", text: "hello")
        let published = await waitUntil {
            guard let notification = self.client.publishDiagnostics(uri: sourceURI).last else { return false }
            return !notification.diagnostics.isEmpty
        }
        XCTAssertTrue(published, "server did not publish source diagnostics")
        guard let firstDiagnostic = client.publishDiagnostics(uri: sourceURI).last?.diagnostics.first else {
            return XCTFail("expected a source diagnostic")
        }
        let diagnostic = firstDiagnostic
        XCTAssertEqual(diagnostic.severity, .error)
        XCTAssertEqual(diagnostic.code, .string("syntax"))
        XCTAssertTrue(
            diagnostic.message.contains("Unexpected"),
            "expected an unexpected-token diagnostic, got '\(diagnostic.message)'"
        )
    }

    func testSourceDocumentDidChangeUpdatesDiagnostics() async {
        let grammarURI = DocumentURI(filePath: "/tmp/expr.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: "%start S\nS : 'hello' 'world' ;\n")
        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "expr", text: "hello")
        let published = await waitUntil {
            guard let notification = self.client.publishDiagnostics(uri: sourceURI).last else { return false }
            return !notification.diagnostics.isEmpty
        }
        XCTAssertTrue(published)

        changeDocument(uri: sourceURI, version: 2, text: "hello world")
        let fixed = await waitUntil {
            self.client.publishDiagnostics(uri: sourceURI).last?.diagnostics.isEmpty ?? false
        }
        XCTAssertTrue(fixed, "server did not clear source diagnostics after the input was fixed")
    }

    func testSourceDocumentWithoutGrammarPublishesEmptyDiagnostics() async {
        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "expr", text: "hello")
        let published = await waitUntil { !self.client.publishDiagnostics(uri: sourceURI).isEmpty }
        XCTAssertTrue(published)
        XCTAssertTrue(client.publishDiagnostics(uri: sourceURI).last!.diagnostics.isEmpty)
    }

    // MARK: - M5: didSave and diagnostic hints

    func testSyntaxDiagnosticsIncludeExpectedTerminals() async {
        let grammarURI = DocumentURI(filePath: "/tmp/expr.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: "%start S\nS : 'hello' 'world' ;\n")
        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "expr", text: "hello")
        let published = await waitUntil {
            guard let notification = self.client.publishDiagnostics(uri: sourceURI).last else { return false }
            return !notification.diagnostics.isEmpty
        }
        XCTAssertTrue(published)
        let diagnostics = client.publishDiagnostics(uri: sourceURI).last!.diagnostics
        XCTAssertTrue(
            diagnostics.last!.message.hasSuffix("Expected: world."),
            "expected a terminal hint on the last diagnostic, got '\(diagnostics.last!.message)'"
        )
    }

    func testDidSaveWithTextAppliesAndReanalyzes() async {
        let grammarURI = DocumentURI(filePath: "/tmp/expr.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: "%start S\nS : 'hello' 'world' ;\n")
        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "expr", text: "hello")
        let published = await waitUntil {
            guard let notification = self.client.publishDiagnostics(uri: sourceURI).last else { return false }
            return !notification.diagnostics.isEmpty
        }
        XCTAssertTrue(published)

        // Saving with the corrected content re-analyzes the document.
        connection.send(DidSaveTextDocumentNotification(
            textDocument: TextDocumentIdentifier(sourceURI),
            text: "hello world"
        ))
        let fixed = await waitUntil {
            guard let stored = await self.server.documentStore.text(for: sourceURI) else { return false }
            return stored == "hello world"
                && (self.client.publishDiagnostics(uri: sourceURI).last?.diagnostics.isEmpty ?? false)
        }
        XCTAssertTrue(fixed, "server did not apply and re-analyze the saved content")
    }

    func testDidSaveWithoutTextRepublishesStoredText() async {
        let grammarURI = DocumentURI(filePath: "/tmp/expr.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: "%start S\nS : 'hello' 'world' ;\n")
        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "expr", text: "hello")
        let published = await waitUntil {
            guard let notification = self.client.publishDiagnostics(uri: sourceURI).last else { return false }
            return !notification.diagnostics.isEmpty
        }
        XCTAssertTrue(published)

        connection.send(DidSaveTextDocumentNotification(textDocument: TextDocumentIdentifier(sourceURI)))
        let republished = await waitUntil {
            guard let notification = self.client.publishDiagnostics(uri: sourceURI).last else { return false }
            return !notification.diagnostics.isEmpty
        }
        XCTAssertTrue(republished, "server did not republish diagnostics for the saved document")
        XCTAssertTrue(
            client.publishDiagnostics(uri: sourceURI).last!.diagnostics.last!.message.contains("Expected: world"),
            "stored text was not re-analyzed after save"
        )
    }

    func testRapidChangesSettleOnFinalText() async {
        let grammarURI = DocumentURI(filePath: "/tmp/expr.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: "%start S\nS : 'hello' 'world' ;\n")
        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "expr", text: "hello")
        let published = await waitUntil { !self.client.publishDiagnostics(uri: sourceURI).isEmpty }
        XCTAssertTrue(published)
        let publishesAfterOpen = client.publishDiagnostics(uri: sourceURI).count

        // Two changes back-to-back; the debounce must coalesce them into a
        // single re-analysis of the final text.
        changeDocument(uri: sourceURI, version: 2, text: "hello ")
        changeDocument(uri: sourceURI, version: 3, text: "hello world")
        let settled = await waitUntil {
            guard let notification = self.client.publishDiagnostics(uri: sourceURI).last else { return false }
            return notification.diagnostics.isEmpty
        }
        XCTAssertTrue(settled, "server did not re-analyze after the rapid changes")
        XCTAssertEqual(
            client.publishDiagnostics(uri: sourceURI).count,
            publishesAfterOpen + 1,
            "rapid changes should coalesce into a single re-analysis"
        )
    }

<<<<<<< HEAD
    // MARK: - M6: definition and grammar-document services

    private static let twoRuleGrammar = """
    %start S
    S : A 'b' ;
    A : 'a' ;
    """

    private func openGrammar(_ uri: DocumentURI, _ text: String) async -> Bool {
        openDocument(uri: uri, language: "grammar", text: text)
        return await waitUntil { !self.client.publishDiagnostics(uri: uri).isEmpty }
    }

    func testGrammarDocumentDefinitionJumpsToDefiningProduction() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)

        // `A` in the first production's body refers to the production on line 2.
        let result: LSPResult<DefinitionRequest.Response> = await send(DefinitionRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 1, utf16index: 4)
        ))
        guard case .success(let response) = result,
              case .locations(let locations)? = response,
              let location = locations.first
        else {
            return XCTFail("expected a definition location, got \(result)")
        }
        XCTAssertEqual(location.uri, grammarURI)
        XCTAssertEqual(location.range.lowerBound.line, 2)
        XCTAssertEqual(location.range.lowerBound.utf16index, 0)
        XCTAssertEqual(location.range.upperBound.line, 2)
    }

    func testSourceDocumentDefinitionJumpsToTokenRule() async {
        let grammarURI = DocumentURI(filePath: "/tmp/num.grammarworkbench", isDirectory: false)
        let grammar = """
        %token NUMBER /[0-9]+/
        %token PRINT /print\\b/
        %skip /\\s+/
        %start S
        S : PRINT NUMBER ;
        """
        let opened = await openGrammar(grammarURI, grammar)
        XCTAssertTrue(opened)

        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "num", text: "print 42")
        let published = await waitUntil {
            guard let notification = self.client.publishDiagnostics(uri: sourceURI).last else { return false }
            return notification.diagnostics.isEmpty
        }
        XCTAssertTrue(published, "valid source document reported diagnostics")

        // `42` is a NUMBER token; its rule is the first line of the grammar.
        let result: LSPResult<DefinitionRequest.Response> = await send(DefinitionRequest(
            textDocument: TextDocumentIdentifier(sourceURI),
            position: Position(line: 0, utf16index: 7)
        ))
        guard case .success(let response) = result,
              case .locations(let locations)? = response,
              let location = locations.first
        else {
            return XCTFail("expected a definition location, got \(result)")
        }
        XCTAssertEqual(location.uri, grammarURI)
        XCTAssertEqual(location.range.lowerBound.line, 0)
    }

    func testGrammarDocumentCompletionOffersDirectivesAndSymbols() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)

        // On a directive, prefix-matched directives are offered.
        let result: LSPResult<CompletionRequest.Response> = await send(CompletionRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 0, utf16index: 1)
        ))
        guard case .success(let list) = result else {
            return XCTFail("completion failed: \(result)")
        }
        let directives = list.items.map(\.label)
        XCTAssertEqual(directives, ["%start"])

        // At the end of a production line, grammar symbols are offered.
        let symbolsResult: LSPResult<CompletionRequest.Response> = await send(CompletionRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 1, utf16index: 11)
        ))
        guard case .success(let symbolList) = symbolsResult else {
            return XCTFail("completion failed: \(symbolsResult)")
        }
        let symbols = symbolList.items.map(\.label)
        XCTAssertTrue(symbols.contains("S"))
        XCTAssertTrue(symbols.contains("A"))
        XCTAssertFalse(symbols.contains("%start"), "non-directive context should not offer directives")
    }

    func testGrammarDocumentHoverShowsProductionAndDirective() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)

        // Hover on the `%start` directive.
        let directiveHover: LSPResult<HoverRequest.Response> = await send(HoverRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 0, utf16index: 3)
        ))
        guard case .success(let directiveResponse) = directiveHover,
              let directiveHoverResponse = directiveResponse,
              case .markupContent(let directiveContents) = directiveHoverResponse.contents else {
            return XCTFail("expected a directive hover, got \(directiveHover)")
        }
        XCTAssertTrue(directiveContents.value.contains("start symbol"))

        // Hover on `A`'s defining production.
        let symbolHover: LSPResult<HoverRequest.Response> = await send(HoverRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 2, utf16index: 0)
        ))
        guard case .success(let symbolResponse) = symbolHover,
              let symbolHoverResponse = symbolResponse,
              case .markupContent(let contents) = symbolHoverResponse.contents else {
            return XCTFail("expected a symbol hover, got \(symbolHover)")
        }
        XCTAssertTrue(contents.value.contains("A → a"), contents.value)
        XCTAssertTrue(contents.value.contains("Nonterminal"))
    }

=======
>>>>>>> dev-branch
    func testClosingSourceDocumentClearsDiagnostics() async {
        let grammarURI = DocumentURI(filePath: "/tmp/expr.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: "%start S\nS : 'hello' 'world' ;\n")
        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "expr", text: "hello")
        let published = await waitUntil {
            guard let notification = self.client.publishDiagnostics(uri: sourceURI).last else { return false }
            return !notification.diagnostics.isEmpty
        }
        XCTAssertTrue(published)

        connection.send(DidCloseTextDocumentNotification(textDocument: TextDocumentIdentifier(sourceURI)))
        let cleared = await waitUntil {
            self.client.publishDiagnostics(uri: sourceURI).last?.diagnostics.isEmpty ?? false
        }
        XCTAssertTrue(cleared, "server did not clear diagnostics for the closed document")
    }

    func testClosingGrammarReanalyzesSourceDocuments() async {
        let grammarURI = DocumentURI(filePath: "/tmp/expr.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: "%start S\nS : 'hello' 'world' ;\n")
        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "expr", text: "hello")
        let published = await waitUntil {
            guard let notification = self.client.publishDiagnostics(uri: sourceURI).last else { return false }
            return !notification.diagnostics.isEmpty
        }
        XCTAssertTrue(published)

        connection.send(DidCloseTextDocumentNotification(textDocument: TextDocumentIdentifier(grammarURI)))
        let cleared = await waitUntil {
            self.client.publishDiagnostics(uri: sourceURI).last?.diagnostics.isEmpty ?? false
        }
        XCTAssertTrue(cleared, "server did not re-analyze sources after the grammar closed")
    }

    // MARK: - M2: folding ranges and document symbols

    func testInitializeAdvertisesFoldingAndSymbolCapabilities() async {
        let result = await send(InitializeRequest(
            processId: nil,
            rootPath: nil,
            rootURI: nil,
            capabilities: ClientCapabilities(),
            workspaceFolders: nil
        ))
        guard case .success(let initializeResult) = result else {
            return XCTFail("initialize failed: \(result)")
        }
        XCTAssertTrue(initializeResult.capabilities.foldingRangeProvider?.isSupported ?? false)
        XCTAssertTrue(initializeResult.capabilities.documentSymbolProvider?.isSupported ?? false)
    }

    /// Waits until the server has published diagnostics for `uri`, which
    /// implies the document was opened and analyzed before requests run.
    private func waitForPublish(uri: DocumentURI) async -> Bool {
        await waitUntil { !self.client.publishDiagnostics(uri: uri).isEmpty }
    }

    func testDocumentSymbolsForSourceDocument() async {
        let grammarURI = DocumentURI(filePath: "/tmp/prog.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: """
            %start Program
            Program : Stmt Program | Stmt ;
            Stmt : 'print' Expr ;
            Expr : 'number' | 'string' ;
            """)
        let sourceURI = DocumentURI(filePath: "/tmp/program.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "prog", text: "print number\nprint string\n")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<DocumentSymbolRequest.Response> = await send(
            DocumentSymbolRequest(textDocument: TextDocumentIdentifier(sourceURI))
        )
        guard case .success(let response) = result, case .documentSymbols(let symbols) = response else {
            return XCTFail("documentSymbol request failed: \(result)")
        }
        XCTAssertEqual(symbols.map(\.name), ["Stmt", "Program"])
        XCTAssertEqual(symbols[0].range.lowerBound.line, 0)
        XCTAssertEqual(symbols[0].children?.first?.name, "Expr")
        XCTAssertEqual(symbols[1].children?.first?.name, "Stmt")
        XCTAssertEqual(symbols[1].range.lowerBound.line, 1)
        XCTAssertEqual(symbols[0].selectionRange.lowerBound.utf16index, 0)
        XCTAssertEqual(symbols[0].selectionRange.upperBound.utf16index, 5)
    }

    func testFoldingRangesForSourceDocument() async {
        let grammarURI = DocumentURI(filePath: "/tmp/list.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: """
            %start List
            List : 'item' List | 'item' ;
            """)
        let sourceURI = DocumentURI(filePath: "/tmp/list.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "list", text: "item\nitem\nitem\n")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<FoldingRangeRequest.Response> = await send(
            FoldingRangeRequest(textDocument: TextDocumentIdentifier(sourceURI))
        )
        guard case .success(let ranges) = result, let ranges else {
            return XCTFail("foldingRange request failed: \(result)")
        }
        // The root is not folded; only the middle `List` spans multiple lines.
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].startLine, 1)
        XCTAssertEqual(ranges[0].endLine, 2)
        XCTAssertEqual(ranges[0].collapsedText, "List")
    }

    func testDocumentSymbolsForLexerRuleGrammar() async {
        let grammarURI = DocumentURI(filePath: "/tmp/list.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: """
            %token ITEM /item/
            %skip /[ \\t\\n]+/
            %start List
            List : ITEM List | ITEM ;
            """)
        let sourceURI = DocumentURI(filePath: "/tmp/list.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "list", text: "item\nitem\nitem\n")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<DocumentSymbolRequest.Response> = await send(
            DocumentSymbolRequest(textDocument: TextDocumentIdentifier(sourceURI))
        )
        guard case .success(let response) = result, case .documentSymbols(let symbols) = response else {
            return XCTFail("documentSymbol request failed: \(result)")
        }
        XCTAssertEqual(symbols.map(\.name), ["List"])
        XCTAssertEqual(symbols[0].range.lowerBound.line, 1)
        XCTAssertEqual(symbols[0].range.upperBound.line, 2)
    }

    func testOutlineRequestsReturnNilForGrammarDocument() async {
        let grammarURI = DocumentURI(filePath: "/tmp/list.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: """
            %start List
            List : 'item' List | 'item' ;
            """)
        let analyzed = await waitForPublish(uri: grammarURI)
        XCTAssertTrue(analyzed, "server did not compile the grammar document")

        let symbolsResult: LSPResult<DocumentSymbolRequest.Response> = await send(
            DocumentSymbolRequest(textDocument: TextDocumentIdentifier(grammarURI))
        )
        guard case .success(let response) = symbolsResult else {
            return XCTFail("documentSymbol request failed: \(symbolsResult)")
        }
        XCTAssertNil(response)

        let foldingResult: LSPResult<FoldingRangeRequest.Response> = await send(
            FoldingRangeRequest(textDocument: TextDocumentIdentifier(grammarURI))
        )
        guard case .success(let ranges) = foldingResult else {
            return XCTFail("foldingRange request failed: \(foldingResult)")
        }
        XCTAssertNil(ranges)
    }

    func testOutlineRequestsReturnNilWithoutGrammar() async {
        let sourceURI = DocumentURI(filePath: "/tmp/list.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "list", text: "item\nitem\nitem\n")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let symbolsResult: LSPResult<DocumentSymbolRequest.Response> = await send(
            DocumentSymbolRequest(textDocument: TextDocumentIdentifier(sourceURI))
        )
        guard case .success(let response) = symbolsResult else {
            return XCTFail("documentSymbol request failed: \(symbolsResult)")
        }
        XCTAssertNil(response)

        let foldingResult: LSPResult<FoldingRangeRequest.Response> = await send(
            FoldingRangeRequest(textDocument: TextDocumentIdentifier(sourceURI))
        )
        guard case .success(let ranges) = foldingResult else {
            return XCTFail("foldingRange request failed: \(foldingResult)")
        }
        XCTAssertNil(ranges)
    }

    // MARK: - M3: completion and hover

    private func progGrammarURI() -> DocumentURI {
        DocumentURI(filePath: "/tmp/prog.grammarworkbench", isDirectory: false)
    }

    private func openProgGrammar() async {
        openDocument(uri: progGrammarURI(), language: "grammar", text: """
            %start Program
            Program : Stmt Program | Stmt ;
            Stmt : 'print' Expr ;
            Expr : 'number' | 'string' ;
            """)
        let published = await waitForPublish(uri: progGrammarURI())
        XCTAssertTrue(published, "server did not compile the grammar document")
    }

    func testInitializeAdvertisesCompletionAndHoverCapabilities() async {
        let result = await send(InitializeRequest(
            processId: nil,
            rootPath: nil,
            rootURI: nil,
            capabilities: ClientCapabilities(),
            workspaceFolders: nil
        ))
        guard case .success(let initializeResult) = result else {
            return XCTFail("initialize failed: \(result)")
        }
        XCTAssertNotNil(initializeResult.capabilities.completionProvider)
        XCTAssertEqual(initializeResult.capabilities.hoverProvider, .bool(true))
<<<<<<< HEAD
=======
        XCTAssertTrue(initializeResult.capabilities.definitionProvider?.isSupported ?? false)
        XCTAssertTrue(initializeResult.capabilities.codeActionProvider?.isSupported ?? false)
>>>>>>> dev-branch
    }

    func testCompletionOffersExpectedTokensFilteredByPrefix() async {
        await openProgGrammar()
        let sourceURI = DocumentURI(filePath: "/tmp/program.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "prog", text: "print nu")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<CompletionRequest.Response> = await send(
            CompletionRequest(textDocument: TextDocumentIdentifier(sourceURI), position: Position(line: 0, utf16index: 8))
        )
        guard case .success(let list) = result else {
            return XCTFail("completion request failed: \(result)")
        }
        XCTAssertFalse(list.isIncomplete)
        XCTAssertEqual(list.items.map(\.label), ["number"])
        let item = list.items[0]
        XCTAssertEqual(item.kind, .keyword)
        guard case .textEdit(let edit) = item.textEdit else {
            return XCTFail("expected a textEdit, got \(String(describing: item.textEdit))")
        }
        XCTAssertEqual(edit.newText, "number")
        XCTAssertEqual(edit.range, Position(line: 0, utf16index: 6)..<Position(line: 0, utf16index: 8))
    }

    func testCompletionAtDocumentStartOffersReachableTerminals() async {
        await openProgGrammar()
        let sourceURI = DocumentURI(filePath: "/tmp/program.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "prog", text: "")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        // State 0's closure includes every production's first symbol, so all
        // reachable terminals are expected at the start of the document.
        let result: LSPResult<CompletionRequest.Response> = await send(
            CompletionRequest(textDocument: TextDocumentIdentifier(sourceURI), position: Position(line: 0, utf16index: 0))
        )
        guard case .success(let list) = result else {
            return XCTFail("completion request failed: \(result)")
        }
        XCTAssertEqual(list.items.map(\.label), ["number", "print", "string"])
        guard case .textEdit(let edit) = list.items[0].textEdit else {
            return XCTFail("expected a textEdit, got \(String(describing: list.items[0].textEdit))")
        }
        XCTAssertEqual(edit.range, Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0))
    }

    func testCompletionAtEndOfValidDocumentOffersContinuation() async {
        await openProgGrammar()
        let sourceURI = DocumentURI(filePath: "/tmp/program.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "prog", text: "print number ")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<CompletionRequest.Response> = await send(
            CompletionRequest(textDocument: TextDocumentIdentifier(sourceURI), position: Position(line: 0, utf16index: 13))
        )
        guard case .success(let list) = result else {
            return XCTFail("completion request failed: \(result)")
        }
        // After a complete Stmt the parser can continue the Program list
        // ('print') or begin a new Expr inside the list's closure.
        XCTAssertEqual(list.items.map(\.label), ["number", "print", "string"])
    }

    func testCompletionMatchesFuzzySubsequence() async {
        await openProgGrammar()
        let sourceURI = DocumentURI(filePath: "/tmp/program.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "prog", text: "print srg")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<CompletionRequest.Response> = await send(
            CompletionRequest(textDocument: TextDocumentIdentifier(sourceURI), position: Position(line: 0, utf16index: 10))
        )
        guard case .success(let list) = result else {
            return XCTFail("completion request failed: \(result)")
        }
        XCTAssertEqual(list.items.map(\.label), ["string"])
    }

    func testCompletionRanksPrefixMatchAboveSubsequenceMatch() async {
        await openProgGrammar()
        let sourceURI = DocumentURI(filePath: "/tmp/program.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "prog", text: "print n")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<CompletionRequest.Response> = await send(
            CompletionRequest(textDocument: TextDocumentIdentifier(sourceURI), position: Position(line: 0, utf16index: 7))
        )
        guard case .success(let list) = result else {
            return XCTFail("completion request failed: \(result)")
        }
        // 'number' is a prefix match, 'print' and 'string' are subsequence
        // matches ('n' occurs inside both); the prefix match ranks first.
        XCTAssertEqual(list.items.map(\.label), ["number", "print", "string"])
    }

    func testCompletionForLexerRuleGrammarUsesTokenPattern() async {
        let grammarURI = DocumentURI(filePath: "/tmp/list.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: """
            %token ITEM /item/
            %skip /[ \\t\\n]+/
            %start List
            List : ITEM List | ITEM ;
            """)
        let published = await waitForPublish(uri: grammarURI)
        XCTAssertTrue(published, "server did not compile the grammar document")
        let sourceURI = DocumentURI(filePath: "/tmp/list.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "list", text: "item\nite")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<CompletionRequest.Response> = await send(
            CompletionRequest(textDocument: TextDocumentIdentifier(sourceURI), position: Position(line: 1, utf16index: 3))
        )
        guard case .success(let list) = result else {
            return XCTFail("completion request failed: \(result)")
        }
        XCTAssertEqual(list.items.map(\.label), ["ITEM"])
        let item = list.items[0]
        XCTAssertEqual(item.kind, .class)
        guard case .textEdit(let edit) = item.textEdit else {
            return XCTFail("expected a textEdit, got \(String(describing: item.textEdit))")
        }
        XCTAssertEqual(edit.newText, "item")
        XCTAssertEqual(edit.range, Position(line: 1, utf16index: 0)..<Position(line: 1, utf16index: 3))
    }

<<<<<<< HEAD
    func testGrammarDocumentCompletionOffersDirectives() async {
        await openProgGrammar()
        let result: LSPResult<CompletionRequest.Response> = await send(
            CompletionRequest(textDocument: TextDocumentIdentifier(progGrammarURI()), position: Position(line: 0, utf16index: 1))
=======
    func testCompletionForGrammarDocumentUsesEditorIntelligence() async {
        await openProgGrammar()
        let result: LSPResult<CompletionRequest.Response> = await send(
            CompletionRequest(textDocument: TextDocumentIdentifier(progGrammarURI()), position: Position(line: 0, utf16index: 3))
>>>>>>> dev-branch
        )
        guard case .success(let list) = result else {
            return XCTFail("completion request failed: \(result)")
        }
        XCTAssertEqual(list.items.map(\.label), ["%start"])
    }

<<<<<<< HEAD
=======
    func testGrammarDefinitionNavigatesToNonterminalDeclaration() async {
        let uri = DocumentURI(filePath: "/tmp/definition.grammarworkbench", isDirectory: false)
        openDocument(uri: uri, language: "grammar", text: "%start Root\nRoot : Item ;\nItem : 'x' ;")
        let published = await waitForPublish(uri: uri)
        XCTAssertTrue(published)
        let result: LSPResult<DefinitionRequest.Response> = await send(DefinitionRequest(
            textDocument: TextDocumentIdentifier(uri), position: .init(line: 1, utf16index: 8)
        ))
        guard case .success(.locations(let locations)?) = result else {
            return XCTFail("definition request failed: \(result)")
        }
        XCTAssertEqual(locations.count, 1)
        XCTAssertEqual(locations[0].uri, uri)
        XCTAssertEqual(locations[0].range.lowerBound.line, 2)
    }

    func testGrammarCodeActionUsesNativeQuickFix() async {
        let uri = DocumentURI(filePath: "/tmp/fix.grammarworkbench", isDirectory: false)
        openDocument(uri: uri, language: "grammar", text: "%start S\nS 'x' ;")
        let published = await waitForPublish(uri: uri)
        XCTAssertTrue(published)
        let range = Position(line: 1, utf16index: 0)..<Position(line: 1, utf16index: 7)
        let result: LSPResult<CodeActionRequest.Response> = await send(CodeActionRequest(
            range: range, context: .init(), textDocument: TextDocumentIdentifier(uri)
        ))
        guard case .success(.codeActions(let actions)?) = result else {
            return XCTFail("code action request failed: \(result)")
        }
        XCTAssertEqual(actions.first?.title, "Insert missing ‘:’")
        XCTAssertEqual(actions.first?.kind, .quickFix)
    }

>>>>>>> dev-branch
    func testHoverOnTerminalShowsTokenAndProduction() async {
        await openProgGrammar()
        let sourceURI = DocumentURI(filePath: "/tmp/program.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "prog", text: "print number")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<HoverRequest.Response> = await send(
            HoverRequest(textDocument: TextDocumentIdentifier(sourceURI), position: Position(line: 0, utf16index: 6))
        )
        guard case .success(let response) = result, let response else {
            return XCTFail("hover request failed: \(result)")
        }
        guard case .markupContent(let contents) = response.contents else {
            return XCTFail("expected markup content, got \(response.contents)")
        }
        XCTAssertEqual(contents.kind, .markdown)
        XCTAssertTrue(contents.value.contains("Token `number`"), contents.value)
        XCTAssertTrue(contents.value.contains("Expr → 'number'"), contents.value)
        XCTAssertEqual(response.range, Position(line: 0, utf16index: 6)..<Position(line: 0, utf16index: 12))
    }

    func testHoverShowsLexerTokenProduction() async {
        let grammarURI = DocumentURI(filePath: "/tmp/list.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: """
            %token ITEM /item/
            %skip /[ \\t\\n]+/
            %start List
            List : ITEM List | ITEM ;
            """)
        let published = await waitForPublish(uri: grammarURI)
        XCTAssertTrue(published, "server did not compile the grammar document")
        let sourceURI = DocumentURI(filePath: "/tmp/list.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "list", text: "item\nitem\n")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<HoverRequest.Response> = await send(
            HoverRequest(textDocument: TextDocumentIdentifier(sourceURI), position: Position(line: 0, utf16index: 2))
        )
        guard case .success(let response) = result, let response else {
            return XCTFail("hover request failed: \(result)")
        }
        guard case .markupContent(let contents) = response.contents else {
            return XCTFail("expected markup content, got \(response.contents)")
        }
        XCTAssertTrue(contents.value.contains("Token `ITEM`"), contents.value)
        XCTAssertTrue(contents.value.contains("List → ITEM List"), contents.value)
    }

    func testHoverOverWhitespaceShowsEnclosingProduction() async {
        await openProgGrammar()
        let sourceURI = DocumentURI(filePath: "/tmp/program.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "prog", text: "print number")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        // Whitespace between tokens is inside the enclosing statement, so the
        // hover shows its production without a token line.
        let whitespaceResult: LSPResult<HoverRequest.Response> = await send(
            HoverRequest(textDocument: TextDocumentIdentifier(sourceURI), position: Position(line: 0, utf16index: 5))
        )
        guard case .success(let response) = whitespaceResult else {
            return XCTFail("hover request failed: \(whitespaceResult)")
        }
        guard let response else {
            return XCTFail("expected the enclosing production, got nil")
        }
        guard case .markupContent(let contents) = response.contents else {
            return XCTFail("expected markup content, got \(response.contents)")
        }
        XCTAssertTrue(contents.value.contains("Stmt → 'print' Expr"), contents.value)
    }

    func testHoverReturnsNilWithoutGrammar() async {
        await openProgGrammar()
        let sourceURI = DocumentURI(filePath: "/tmp/other.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "other", text: "print number")
        let result: LSPResult<HoverRequest.Response> = await send(
            HoverRequest(textDocument: TextDocumentIdentifier(sourceURI), position: Position(line: 0, utf16index: 0))
        )
        guard case .success(let response) = result else {
            return XCTFail("hover request failed: \(result)")
        }
        XCTAssertNil(response)
    }
<<<<<<< HEAD

    // MARK: - M7: semantic tokens, references, rename, code actions, progress

    private static let numGrammar = """
    %token NUMBER /[0-9]+/
    %token PRINT /print\\b/
    %skip /\\s+/
    %start S
    S : PRINT NUMBER ;
    """

    private struct DecodedToken: Equatable {
        let line: Int
        let start: Int
        let length: Int
        let type: Int
    }

    /// Decodes relative-encoded `data` into absolute tokens.
    private func decodeTokens(_ data: [UInt32]) -> [DecodedToken] {
        var tokens: [DecodedToken] = []
        var line = 0
        var start = 0
        for index in stride(from: 0, to: data.count, by: 5) {
            line += Int(data[index])
            start = data[index] == 0 ? start + Int(data[index + 1]) : Int(data[index + 1])
            tokens.append(DecodedToken(
                line: line,
                start: start,
                length: Int(data[index + 2]),
                type: Int(data[index + 3])
            ))
        }
        return tokens
    }

    func testInitializeAdvertisesM7Capabilities() async {
        let result = await send(InitializeRequest(
            processId: nil,
            rootPath: nil,
            rootURI: nil,
            capabilities: ClientCapabilities(),
            workspaceFolders: nil
        ))
        guard case .success(let initializeResult) = result else {
            return XCTFail("initialize failed: \(result)")
        }
        XCTAssertEqual(
            initializeResult.capabilities.semanticTokensProvider?.legend.tokenTypes,
            ["keyword", "string", "number", "regexp", "comment", "operator", "type", "enumMember", "variable"]
        )
        XCTAssertEqual(initializeResult.capabilities.semanticTokensProvider?.legend.tokenModifiers, [])
        XCTAssertTrue(initializeResult.capabilities.referencesProvider?.isSupported ?? false)
        XCTAssertTrue(initializeResult.capabilities.renameProvider?.isSupported ?? false)
        XCTAssertTrue(initializeResult.capabilities.codeActionProvider?.isSupported ?? false)
    }

    func testSemanticTokensForGrammarDocument() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)

        let result: LSPResult<DocumentSemanticTokensRequest.Response> = await send(
            DocumentSemanticTokensRequest(textDocument: TextDocumentIdentifier(grammarURI))
        )
        guard case .success(let response) = result, let response else {
            return XCTFail("semanticTokens request failed: \(result)")
        }
        let tokens = decodeTokens(response.data)
        XCTAssertEqual(tokens, [
            DecodedToken(line: 0, start: 0, length: 6, type: 0),   // %start
            DecodedToken(line: 0, start: 7, length: 1, type: 6),   // S
            DecodedToken(line: 1, start: 0, length: 1, type: 6),   // S
            DecodedToken(line: 1, start: 2, length: 1, type: 5),   // :
            DecodedToken(line: 1, start: 4, length: 1, type: 6),   // A
            DecodedToken(line: 1, start: 6, length: 3, type: 1),   // 'b'
            DecodedToken(line: 1, start: 10, length: 1, type: 5),  // ;
            DecodedToken(line: 2, start: 0, length: 1, type: 6),   // A
            DecodedToken(line: 2, start: 2, length: 1, type: 5),   // :
            DecodedToken(line: 2, start: 4, length: 3, type: 1),   // 'a'
            DecodedToken(line: 2, start: 8, length: 1, type: 5),   // ;
        ])
    }

    func testSemanticTokensForSourceDocument() async {
        let grammarURI = DocumentURI(filePath: "/tmp/num.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.numGrammar)
        XCTAssertTrue(opened)

        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "num", text: "print 42")
        let analyzed = await waitUntil {
            guard let notification = self.client.publishDiagnostics(uri: sourceURI).last else { return false }
            return notification.diagnostics.isEmpty
        }
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<DocumentSemanticTokensRequest.Response> = await send(
            DocumentSemanticTokensRequest(textDocument: TextDocumentIdentifier(sourceURI))
        )
        guard case .success(let response) = result, let response else {
            return XCTFail("semanticTokens request failed: \(result)")
        }
        let tokens = decodeTokens(response.data)
        XCTAssertEqual(tokens, [
            DecodedToken(line: 0, start: 0, length: 5, type: 0),  // print → PRINT → keyword
            DecodedToken(line: 0, start: 6, length: 2, type: 2),  // 42 → NUMBER → number
        ])
    }

    func testSemanticTokensReturnNilWithoutGrammar() async {
        let sourceURI = DocumentURI(filePath: "/tmp/orphan.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "orphan", text: "print 42")
        let result: LSPResult<DocumentSemanticTokensRequest.Response> = await send(
            DocumentSemanticTokensRequest(textDocument: TextDocumentIdentifier(sourceURI))
        )
        guard case .success(let response) = result else {
            return XCTFail("semanticTokens request failed: \(result)")
        }
        XCTAssertNil(response)
    }

    func testReferencesForNonterminalIncludesDeclarationByDefault() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)

        // `A` at (1,4) is used in the first production and defined on line 2.
        let result: LSPResult<ReferencesRequest.Response> = await send(ReferencesRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 1, utf16index: 4),
            context: ReferencesContext(includeDeclaration: true)
        ))
        guard case .success(let locations) = result else {
            return XCTFail("references request failed: \(result)")
        }
        XCTAssertEqual(locations.map(\.range.lowerBound), [
            Position(line: 1, utf16index: 4),
            Position(line: 2, utf16index: 0),
        ])
        XCTAssertTrue(locations.allSatisfy { $0.uri == grammarURI })
    }

    func testReferencesForNonterminalCanExcludeDeclaration() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)

        let result: LSPResult<ReferencesRequest.Response> = await send(ReferencesRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 1, utf16index: 4),
            context: ReferencesContext(includeDeclaration: false)
        ))
        guard case .success(let locations) = result else {
            return XCTFail("references request failed: \(result)")
        }
        XCTAssertEqual(locations.map(\.range.lowerBound), [Position(line: 1, utf16index: 4)])
    }

    func testReferencesReturnEmptyForSourceDocument() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)
        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "two", text: "a")

        let result: LSPResult<ReferencesRequest.Response> = await send(ReferencesRequest(
            textDocument: TextDocumentIdentifier(sourceURI),
            position: Position(line: 0, utf16index: 0),
            context: ReferencesContext(includeDeclaration: true)
        ))
        guard case .success(let locations) = result else {
            return XCTFail("references request failed: \(result)")
        }
        XCTAssertTrue(locations.isEmpty)
    }

    func testRenameNonterminalReplacesEveryOccurrence() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)

        let result: LSPResult<RenameRequest.Response> = await send(RenameRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 1, utf16index: 4),
            newName: "B"
        ))
        guard case .success(let edit) = result, let edit else {
            return XCTFail("rename failed: \(result)")
        }
        XCTAssertEqual(edit.changes?[grammarURI], [
            TextEdit(range: Position(line: 1, utf16index: 4)..<Position(line: 1, utf16index: 5), newText: "B"),
            TextEdit(range: Position(line: 2, utf16index: 0)..<Position(line: 2, utf16index: 1), newText: "B"),
        ])
    }

    func testRenameRejectsInvalidNamesAndTerminalLiterals() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)

        let invalidName: LSPResult<RenameRequest.Response> = await send(RenameRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 1, utf16index: 4),
            newName: "1B"
        ))
        guard case .failure(let error) = invalidName else {
            return XCTFail("expected invalidParams failure, got \(invalidName)")
        }
        XCTAssertEqual(error.code, .invalidParams)

        let literal: LSPResult<RenameRequest.Response> = await send(RenameRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 1, utf16index: 7),
            newName: "B"
        ))
        guard case .failure(let literalError) = literal else {
            return XCTFail("expected invalidParams failure, got \(literal)")
        }
        XCTAssertEqual(literalError.code, .invalidParams)
    }

    func testRenameReturnsNilOutsideGrammarDocument() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)
        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "two", text: "a")

        let result: LSPResult<RenameRequest.Response> = await send(RenameRequest(
            textDocument: TextDocumentIdentifier(sourceURI),
            position: Position(line: 0, utf16index: 0),
            newName: "B"
        ))
        guard case .success(let edit) = result else {
            return XCTFail("rename failed: \(result)")
        }
        XCTAssertNil(edit)
    }

    func testRecoveryCodeActionInsertsMissingTerminal() async {
        await openProgGrammar()
        let sourceURI = DocumentURI(filePath: "/tmp/program.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "prog", text: "print nu")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        // `nu` at (0,6)-(0,8) is unexpected; the first recovery inserts the
        // preferred terminal before it.
        let result: LSPResult<CodeActionRequest.Response> = await send(CodeActionRequest(
            range: Position(line: 0, utf16index: 6)..<Position(line: 0, utf16index: 8),
            context: CodeActionContext(diagnostics: []),
            textDocument: TextDocumentIdentifier(sourceURI)
        ))
        guard case .success(let response) = result, let response else {
            return XCTFail("codeAction request failed: \(result)")
        }
        guard case .codeActions(let actions) = response else {
            return XCTFail("expected code actions, got \(response)")
        }
        XCTAssertEqual(actions.map(\.title), ["Insert missing ‘number’"])
        XCTAssertEqual(actions.map(\.kind), [.quickFix])
        XCTAssertEqual(actions.map(\.isPreferred), [true])
        guard let changes = actions[0].edit?.changes?[sourceURI] else {
            return XCTFail("expected a workspace edit for the source document")
        }
        XCTAssertEqual(changes, [
            TextEdit(range: Position(line: 0, utf16index: 6)..<Position(line: 0, utf16index: 6), newText: "number "),
        ])
    }

    func testGrammarCodeActionDeclaresUndefinedSymbol() async {
        let grammarURI = DocumentURI(filePath: "/tmp/undef.grammarworkbench", isDirectory: false)
        let grammar = "%token B /b/\n%start S\nS : B A ;\n"
        let opened = await openGrammar(grammarURI, grammar)
        XCTAssertTrue(opened)

        let result: LSPResult<CodeActionRequest.Response> = await send(CodeActionRequest(
            range: Position(line: 0, utf16index: 0)..<Position(line: 2, utf16index: 8),
            context: CodeActionContext(diagnostics: []),
            textDocument: TextDocumentIdentifier(grammarURI)
        ))
        guard case .success(let response) = result, let response else {
            return XCTFail("codeAction request failed: \(result)")
        }
        guard case .codeActions(let actions) = response else {
            return XCTFail("expected code actions, got \(response)")
        }
        XCTAssertEqual(actions.map(\.title), ["Declare ‘A’ with %token"])
        let action = actions[0]
        XCTAssertEqual(action.kind, .quickFix)
        XCTAssertEqual(action.isPreferred, true)
        guard let changes = action.edit?.changes?[grammarURI] else {
            return XCTFail("expected a workspace edit for the grammar document")
        }
        XCTAssertEqual(changes, [
            TextEdit(range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0), newText: "%token A\n"),
        ])
    }

    func testCancelRequestCancelsInFlightRequest() async {
        final class Gate: @unchecked Sendable {
            private var continuation: CheckedContinuation<Void, Never>?
            func wait() async {
                await withCheckedContinuation { self.continuation = $0 }
            }
            func open() {
                continuation?.resume()
                continuation = nil
            }
        }
        let gate = Gate()
        await server.setRequestGate({ await gate.wait() })

        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)

        // The request id 2 starts and parks at the gate.
        let connection = self.connection
        let resultTask = Task {
            await withCheckedContinuation { continuation in
                connection!.send(DocumentSemanticTokensRequest(
                    textDocument: TextDocumentIdentifier(grammarURI)
                ), id: .number(2)) { (result: LSPResult<DocumentSemanticTokensRequest.Response>) in
                    continuation.resume(returning: result)
                }
            }
        }
        let tracked = await waitUntil { await self.server.isRequestInFlight(.number(2)) }
        XCTAssertTrue(tracked, "request id 2 was not tracked")

        connection!.send(CancelRequestNotification(id: .number(2)))
        gate.open()
        let result = await resultTask.value
        guard case .failure(let error) = result else {
            return XCTFail("expected a cancelled failure, got \(result)")
        }
        XCTAssertEqual(error.code, .cancelled)
        let inFlight = await server.isRequestInFlight(.number(2))
        XCTAssertFalse(inFlight, "cancelled request was not untracked")
        await server.setRequestGate(nil)
    }

    func testRepublishingReportsWorkDoneProgress() async {
        let grammarURI = DocumentURI(filePath: "/tmp/expr.grammarworkbench", isDirectory: false)
        openDocument(uri: grammarURI, language: "grammar", text: "%start S\nS : 'hello' 'world' ;\n")
        let firstURI = DocumentURI(filePath: "/tmp/first.txt", isDirectory: false)
        let secondURI = DocumentURI(filePath: "/tmp/second.txt", isDirectory: false)
        openDocument(uri: firstURI, language: "expr", text: "hello")
        openDocument(uri: secondURI, language: "expr", text: "hello")
        let analyzed = await waitUntil {
            !self.client.publishDiagnostics(uri: firstURI).isEmpty
                && !self.client.publishDiagnostics(uri: secondURI).isEmpty
        }
        XCTAssertTrue(analyzed)

        // Changing the grammar re-analyzes every source document with progress.
        changeDocument(uri: grammarURI, version: 2, text: "%start S\nS : 'hi' 'world' ;\n")
        let progressed = await waitUntil {
            await self.server.workDoneProgressNotifications.count >= 4
        }
        XCTAssertTrue(progressed, "server did not report work-done progress")

        let tokens = await server.workDoneProgressNotifications
        let sent = client.progressNotifications
        XCTAssertEqual(sent.map(\.token), tokens)

        let first = sent[0]
        XCTAssertEqual(first.token, .string("grammar-workbench-1"))
        guard case .begin(let begin) = first.value else {
            return XCTFail("expected a begin event, got \(first.value)")
        }
        XCTAssertEqual(begin.title, "Grammar Workbench")

        let reports = sent[1...2]
        let percentages = reports.map { progress -> Int? in
            guard case .report(let report) = progress.value else { return nil }
            return report.percentage
        }
        XCTAssertEqual(percentages, [50, 100])

        guard case .end(let end) = sent[3].value else {
            return XCTFail("expected an end event, got \(sent[3].value)")
        }
        XCTAssertEqual(end.message, "2 document(s) analyzed")
    }

    // MARK: - M8: document highlights, formatting, and document links

    func testInitializeAdvertisesM8Capabilities() async {
        let result = await send(InitializeRequest(
            processId: nil,
            rootPath: nil,
            rootURI: nil,
            capabilities: ClientCapabilities(),
            workspaceFolders: nil
        ))
        guard case .success(let initializeResult) = result else {
            return XCTFail("initialize failed: \(result)")
        }
        XCTAssertTrue(initializeResult.capabilities.documentHighlightProvider?.isSupported ?? false)
        XCTAssertTrue(initializeResult.capabilities.documentFormattingProvider?.isSupported ?? false)
        XCTAssertTrue(initializeResult.capabilities.documentRangeFormattingProvider?.isSupported ?? false)
        XCTAssertNotNil(initializeResult.capabilities.documentLinkProvider)
    }

    func testDocumentHighlightsForNonterminalMarkDeclarationsAsWrites() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)

        // `A` at (1,4) is used in the first production and defined on line 2;
        // the declaration is a write, the use a read.
        let result: LSPResult<DocumentHighlightRequest.Response> = await send(DocumentHighlightRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 1, utf16index: 4)
        ))
        guard case .success(let highlights) = result, let highlights else {
            return XCTFail("documentHighlight request failed: \(result)")
        }
        XCTAssertEqual(highlights.map(\.range), [
            Position(line: 1, utf16index: 4)..<Position(line: 1, utf16index: 5),
            Position(line: 2, utf16index: 0)..<Position(line: 2, utf16index: 1),
        ])
        XCTAssertEqual(highlights.map(\.kind), [.read, .write])
    }

    func testDocumentHighlightsForTerminalLiteralHighlightEveryUse() async {
        let grammarURI = DocumentURI(filePath: "/tmp/lit.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, "%start S\nS : 'a' 'a' 'b' ;\n")
        XCTAssertTrue(opened)

        let result: LSPResult<DocumentHighlightRequest.Response> = await send(DocumentHighlightRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 1, utf16index: 4)
        ))
        guard case .success(let highlights) = result, let highlights else {
            return XCTFail("documentHighlight request failed: \(result)")
        }
        XCTAssertEqual(highlights.map(\.range), [
            Position(line: 1, utf16index: 4)..<Position(line: 1, utf16index: 7),
            Position(line: 1, utf16index: 8)..<Position(line: 1, utf16index: 11),
        ])
        XCTAssertTrue(highlights.allSatisfy { $0.kind == .read })
    }

    func testDocumentHighlightsForTokenNameIncludeDeclaration() async {
        let grammarURI = DocumentURI(filePath: "/tmp/num.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.numGrammar)
        XCTAssertTrue(opened)

        // `NUMBER` in the `%token` declaration is a write; its use in the
        // production is a read.
        let result: LSPResult<DocumentHighlightRequest.Response> = await send(DocumentHighlightRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 4, utf16index: 10)
        ))
        guard case .success(let highlights) = result, let highlights else {
            return XCTFail("documentHighlight request failed: \(result)")
        }
        XCTAssertEqual(highlights.map(\.range), [
            Position(line: 0, utf16index: 7)..<Position(line: 0, utf16index: 13),
            Position(line: 4, utf16index: 10)..<Position(line: 4, utf16index: 16),
        ])
        XCTAssertEqual(highlights.map(\.kind), [.write, .read])
    }

    func testDocumentHighlightsForSourceDocumentHighlightExactTokens() async {
        let grammarURI = DocumentURI(filePath: "/tmp/num.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.numGrammar)
        XCTAssertTrue(opened)
        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "num", text: "print 42\nprint 42\n")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        // On `print`: every PRINT token; on the number: only the `42`s.
        let printResult: LSPResult<DocumentHighlightRequest.Response> = await send(DocumentHighlightRequest(
            textDocument: TextDocumentIdentifier(sourceURI),
            position: Position(line: 0, utf16index: 0)
        ))
        guard case .success(let printHighlights) = printResult, let printHighlights else {
            return XCTFail("documentHighlight request failed: \(printResult)")
        }
        XCTAssertEqual(printHighlights.map(\.range), [
            Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 5),
            Position(line: 1, utf16index: 0)..<Position(line: 1, utf16index: 5),
        ])

        let numberResult: LSPResult<DocumentHighlightRequest.Response> = await send(DocumentHighlightRequest(
            textDocument: TextDocumentIdentifier(sourceURI),
            position: Position(line: 0, utf16index: 6)
        ))
        guard case .success(let numberHighlights) = numberResult, let numberHighlights else {
            return XCTFail("documentHighlight request failed: \(numberResult)")
        }
        XCTAssertEqual(numberHighlights.map(\.range), [
            Position(line: 0, utf16index: 6)..<Position(line: 0, utf16index: 8),
            Position(line: 1, utf16index: 6)..<Position(line: 1, utf16index: 8),
        ])
        XCTAssertTrue(numberHighlights.allSatisfy { $0.kind == .read })
    }

    func testDocumentHighlightsForSourceDocumentWithoutLexerRules() async {
        await openProgGrammar()
        let sourceURI = DocumentURI(filePath: "/tmp/program.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "prog", text: "print number\nprint number\n")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<DocumentHighlightRequest.Response> = await send(DocumentHighlightRequest(
            textDocument: TextDocumentIdentifier(sourceURI),
            position: Position(line: 0, utf16index: 0)
        ))
        guard case .success(let highlights) = result, let highlights else {
            return XCTFail("documentHighlight request failed: \(result)")
        }
        XCTAssertEqual(highlights.map(\.range), [
            Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 5),
            Position(line: 1, utf16index: 0)..<Position(line: 1, utf16index: 5),
        ])
    }

    func testDocumentHighlightsReturnNilOnWhitespaceOrWithoutGrammar() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)

        let whitespaceResult: LSPResult<DocumentHighlightRequest.Response> = await send(DocumentHighlightRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            position: Position(line: 1, utf16index: 1)
        ))
        guard case .success(let highlights) = whitespaceResult else {
            return XCTFail("documentHighlight request failed: \(whitespaceResult)")
        }
        XCTAssertNil(highlights)

        let orphanURI = DocumentURI(filePath: "/tmp/orphan.txt", isDirectory: false)
        openDocument(uri: orphanURI, language: "orphan", text: "print 42")
        let orphanResult: LSPResult<DocumentHighlightRequest.Response> = await send(DocumentHighlightRequest(
            textDocument: TextDocumentIdentifier(orphanURI),
            position: Position(line: 0, utf16index: 0)
        ))
        guard case .success(let orphanHighlights) = orphanResult else {
            return XCTFail("documentHighlight request failed: \(orphanResult)")
        }
        XCTAssertNil(orphanHighlights)
    }

    func testFormattingCanonicalizesSpacingIndentationAndComments() async {
        let grammarURI = DocumentURI(filePath: "/tmp/messy.grammarworkbench", isDirectory: false)
        let messy = "%start  S\n\nS : A |   B ;\n  A : 'a' ;  \nB : 'b' ;\t// comment\n"
        let opened = await openGrammar(grammarURI, messy)
        XCTAssertTrue(opened)

        let result: LSPResult<DocumentFormattingRequest.Response> = await send(DocumentFormattingRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            options: FormattingOptions(tabSize: 4, insertSpaces: true)
        ))
        guard case .success(let edits) = result, let edits else {
            return XCTFail("formatting request failed: \(result)")
        }
        XCTAssertEqual(applying(edits, to: messy), "%start S\n\nS : A | B ;\nA : 'a' ;\nB : 'b' ; // comment\n")
    }

    func testFormattingReturnsNoEditsForCanonicalDocument() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)

        let result: LSPResult<DocumentFormattingRequest.Response> = await send(DocumentFormattingRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            options: FormattingOptions(tabSize: 4, insertSpaces: true)
        ))
        guard case .success(let edits) = result else {
            return XCTFail("formatting request failed: \(result)")
        }
        XCTAssertEqual(edits, [])
    }

    func testFormattingPreservesMultiLineProductions() async {
        let grammarURI = DocumentURI(filePath: "/tmp/multiline.grammarworkbench", isDirectory: false)
        let grammar = "%start S\nS : A\n  | B ; // alternatives\nA : 'a' ;\n"
        let opened = await openGrammar(grammarURI, grammar)
        XCTAssertTrue(opened)

        let result: LSPResult<DocumentFormattingRequest.Response> = await send(DocumentFormattingRequest(
            textDocument: TextDocumentIdentifier(grammarURI),
            options: FormattingOptions(tabSize: 4, insertSpaces: true)
        ))
        guard case .success(let edits) = result, let edits else {
            return XCTFail("formatting request failed: \(result)")
        }
        XCTAssertEqual(applying(edits, to: grammar), "%start S\nS : A\n| B ; // alternatives\nA : 'a' ;\n")
    }

    func testRangeFormattingFormatsOnlyRequestedLines() async {
        let grammarURI = DocumentURI(filePath: "/tmp/messy.grammarworkbench", isDirectory: false)
        let messy = "%start S\nS : A |  B ;\nA  : 'a' ;\nB : 'b' ;\n"
        let opened = await openGrammar(grammarURI, messy)
        XCTAssertTrue(opened)

        let result: LSPResult<DocumentRangeFormattingRequest.Response> = await send(
            DocumentRangeFormattingRequest(
                textDocument: TextDocumentIdentifier(grammarURI),
                range: Position(line: 1, utf16index: 0)..<Position(line: 3, utf16index: 0),
                options: FormattingOptions(tabSize: 4, insertSpaces: true)
            )
        )
        guard case .success(let edits) = result, let edits else {
            return XCTFail("rangeFormatting request failed: \(result)")
        }
        XCTAssertEqual(edits.map(\.range.lowerBound.line), [1, 2])
        XCTAssertEqual(applying(edits, to: messy), "%start S\nS : A | B ;\nA : 'a' ;\nB : 'b' ;\n")
    }

    func testFormattingReturnsNilForSourceAndEbnfDocuments() async {
        await openProgGrammar()
        let sourceURI = DocumentURI(filePath: "/tmp/program.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "prog", text: "print number")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let sourceResult: LSPResult<DocumentFormattingRequest.Response> = await send(DocumentFormattingRequest(
            textDocument: TextDocumentIdentifier(sourceURI),
            options: FormattingOptions(tabSize: 4, insertSpaces: true)
        ))
        guard case .success(let edits) = sourceResult else {
            return XCTFail("formatting request failed: \(sourceResult)")
        }
        XCTAssertNil(edits)

        let ebnfURI = DocumentURI(filePath: "/tmp/expr.ebnf", isDirectory: false)
        openDocument(uri: ebnfURI, language: "ebnf", text: "S = 'a' ;")
        let ebnfResult: LSPResult<DocumentFormattingRequest.Response> = await send(DocumentFormattingRequest(
            textDocument: TextDocumentIdentifier(ebnfURI),
            options: FormattingOptions(tabSize: 4, insertSpaces: true)
        ))
        guard case .success(let ebnfEdits) = ebnfResult else {
            return XCTFail("formatting request failed: \(ebnfResult)")
        }
        XCTAssertNil(ebnfEdits)
    }

    func testDocumentLinksForSourceDocumentPointToGrammarRules() async {
        let grammarURI = DocumentURI(filePath: "/tmp/num.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.numGrammar)
        XCTAssertTrue(opened)
        let sourceURI = DocumentURI(filePath: "/tmp/input.txt", isDirectory: false)
        openDocument(uri: sourceURI, language: "num", text: "print 42")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<DocumentLinkRequest.Response> = await send(
            DocumentLinkRequest(textDocument: TextDocumentIdentifier(sourceURI))
        )
        guard case .success(let links) = result, let links else {
            return XCTFail("documentLink request failed: \(result)")
        }
        XCTAssertEqual(links.map(\.range), [
            Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 5),
            Position(line: 0, utf16index: 6)..<Position(line: 0, utf16index: 8),
        ])
        XCTAssertEqual(links.map(\.target), [grammarURI, grammarURI])
        XCTAssertEqual(links.map(\.tooltip), ["Go to rule for PRINT", "Go to rule for NUMBER"])
    }

    func testDocumentLinksForLiteralTerminalsPointToContainingProduction() async {
        let grammarURI = DocumentURI(filePath: "/tmp/block.grammarworkbench", isDirectory: false)
        let grammar = "%start Program\nProgram : Stmt Program | Stmt ;\nStmt : '{' Stmt '}' | 'expr' ;\n"
        let opened = await openGrammar(grammarURI, grammar)
        XCTAssertTrue(opened)
        let sourceURI = DocumentURI(filePath: "/tmp/sample.blk", isDirectory: false)
        openDocument(uri: sourceURI, language: "block", text: "expr\n{\nexpr }")
        let analyzed = await waitForPublish(uri: sourceURI)
        XCTAssertTrue(analyzed, "server did not analyze the source document")

        let result: LSPResult<DocumentLinkRequest.Response> = await send(
            DocumentLinkRequest(textDocument: TextDocumentIdentifier(sourceURI))
        )
        guard case .success(let links) = result, let links else {
            return XCTFail("documentLink request failed: \(result)")
        }
        XCTAssertEqual(links.map(\.range), [
            Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 4),
            Position(line: 1, utf16index: 0)..<Position(line: 1, utf16index: 1),
            Position(line: 2, utf16index: 0)..<Position(line: 2, utf16index: 4),
            Position(line: 2, utf16index: 5)..<Position(line: 2, utf16index: 6),
        ])
        XCTAssertEqual(links.map(\.target), [grammarURI, grammarURI, grammarURI, grammarURI])
    }

    func testDocumentLinksForGrammarDocumentAreEmpty() async {
        let grammarURI = DocumentURI(filePath: "/tmp/two.grammarworkbench", isDirectory: false)
        let opened = await openGrammar(grammarURI, Self.twoRuleGrammar)
        XCTAssertTrue(opened)

        let result: LSPResult<DocumentLinkRequest.Response> = await send(
            DocumentLinkRequest(textDocument: TextDocumentIdentifier(grammarURI))
        )
        guard case .success(let links) = result else {
            return XCTFail("documentLink request failed: \(result)")
        }
        XCTAssertEqual(links, [])
    }

    func testDocumentLinksReturnNilWithoutGrammar() async {
        let orphanURI = DocumentURI(filePath: "/tmp/orphan.txt", isDirectory: false)
        openDocument(uri: orphanURI, language: "orphan", text: "print 42")

        let result: LSPResult<DocumentLinkRequest.Response> = await send(
            DocumentLinkRequest(textDocument: TextDocumentIdentifier(orphanURI))
        )
        guard case .success(let links) = result else {
            return XCTFail("documentLink request failed: \(result)")
        }
        XCTAssertNil(links)
    }

    /// Applies line-scoped `edits` to `text` and returns the result.
    private func applying(_ edits: [TextEdit], to text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        for edit in edits.sorted(by: { $0.range.lowerBound.line > $1.range.lowerBound.line }) {
            let index = edit.range.lowerBound.line
            let start = edit.range.lowerBound.utf16index
            let end = edit.range.upperBound.utf16index
            let line = lines[index]
            lines[index] = String(line.prefix(start)) + edit.newText + String(line.dropFirst(end))
        }
        return lines.joined(separator: "\n")
    }
=======
>>>>>>> dev-branch
}

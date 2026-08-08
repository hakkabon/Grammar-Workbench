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
        XCTAssertTrue(initializeResult.capabilities.definitionProvider?.isSupported ?? false)
        XCTAssertTrue(initializeResult.capabilities.codeActionProvider?.isSupported ?? false)
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

    func testCompletionForGrammarDocumentUsesEditorIntelligence() async {
        await openProgGrammar()
        let result: LSPResult<CompletionRequest.Response> = await send(
            CompletionRequest(textDocument: TextDocumentIdentifier(progGrammarURI()), position: Position(line: 0, utf16index: 3))
        )
        guard case .success(let list) = result else {
            return XCTFail("completion request failed: \(result)")
        }
        XCTAssertEqual(list.items.map(\.label), ["%start"])
    }

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
}

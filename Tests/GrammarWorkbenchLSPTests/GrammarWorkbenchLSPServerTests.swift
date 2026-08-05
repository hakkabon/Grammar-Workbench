import Foundation
import XCTest
import LanguageServerProtocol
import LanguageServerProtocolTransport
@testable import grammar_workbench_lsp

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
        let result: LSPResult<DocumentSymbolRequest.Response> = await send(
            DocumentSymbolRequest(textDocument: TextDocumentIdentifier(mockURI))
        )
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
}

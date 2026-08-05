import Foundation
import XCTest
import LanguageServerProtocol
import LanguageServerProtocolTransport
@testable import GrammarWorkbenchLSP

final class GrammarWorkbenchLSPServerTests: XCTestCase {
    private var client: TestClient!
    private var server: GrammarWorkbenchLSPServer!
    private var connection: LocalConnection!

    override func setUp() {
        super.setUp()
        client = TestClient()
        let conn = LocalConnection(receiverName: "server")
        server = GrammarWorkbenchLSPServer(connection: conn)
        conn.start(handler: server)
        connection = conn
    }

    override func tearDown() {
        connection.close()
        server = nil
        client = nil
        connection = nil
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
}

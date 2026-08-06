import Dispatch
import Darwin
import Foundation
import GrammarWorkbenchLSP
import LanguageServerProtocol
import LanguageServerProtocolTransport

/// Entry point for the `grammar-workbench-lsp` server.
///
/// Speaks JSON-RPC 2.0 over stdio as a Language Server Protocol server.
/// Usage:
///
///     grammar-workbench-lsp [--log-file PATH]
@main
enum GrammarWorkbenchLSPMain {
    static func main() {
        let registry = MessageRegistry(
            requests: [
                InitializeRequest.self,
                ShutdownRequest.self,
                FoldingRangeRequest.self,
                DocumentSymbolRequest.self,
                CompletionRequest.self,
                HoverRequest.self,
            ],
            notifications: [
                DidOpenTextDocumentNotification.self,
                DidChangeTextDocumentNotification.self,
                DidCloseTextDocumentNotification.self,
                InitializedNotification.self,
                ExitNotification.self,
            ]
        )

        let connection = JSONRPCConnection(
            name: "grammar-workbench-lsp",
            protocol: registry,
            receiveFD: FileHandle.standardInput,
            sendFD: FileHandle.standardOutput
        )

        let server = GrammarWorkbenchLSPServer(connection: connection)

        connection.start(receiveHandler: server) {
            // The input stream ended (client exited or the `exit` notification
            // closed the connection). Per the LSP spec, exit with success only
            // if a `shutdown` request was received beforehand.
            let code: Int32 = await server.hasReceivedShutdown ? 0 : 1
            exit(code)
        }

        // Keep the process alive; the connection's read loop drives everything.
        dispatchMain()
    }
}

import Foundation
import LanguageServerProtocol

/// A recording `MessageHandler` that plays the role of the LSP client in tests.
///
/// It records notifications sent by the server under test and replies to any
<<<<<<< HEAD
/// request it receives with a `methodNotFound` error, except for
/// `window/workDoneProgress/create`, which it honors so the server's progress
/// reporting can be verified.
=======
/// request it receives with a `methodNotFound` error (tests do not ask the
/// client to implement requests).
>>>>>>> dev-branch
public final class TestClient: MessageHandler, @unchecked Sendable {
    public private(set) var notifications: [any NotificationType] = []

    public init() {}

    public func handle(_ notification: some NotificationType) {
        notifications.append(notification)
    }

    /// `PublishDiagnosticsNotification`s received for `uri`, in arrival order.
    public func publishDiagnostics(uri: DocumentURI) -> [PublishDiagnosticsNotification] {
        notifications
            .compactMap { $0 as? PublishDiagnosticsNotification }
            .filter { $0.uri == uri }
    }

<<<<<<< HEAD
    /// `WorkDoneProgress` notifications (`$/progress`) received, in arrival
    /// order.
    public var progressNotifications: [WorkDoneProgress] {
        notifications.compactMap { $0 as? WorkDoneProgress }
    }

=======
>>>>>>> dev-branch
    public func handle<Request: RequestType>(
        _ request: Request,
        id: RequestID,
        reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
    ) {
<<<<<<< HEAD
        if Request.self == CreateWorkDoneProgressRequest.self {
            reply(.success(VoidResponse() as! Request.Response))
            return
        }
        reply(.failure(.methodNotFound(Request.method)))
    }
}
=======
        reply(.failure(.methodNotFound(Request.method)))
    }
}
>>>>>>> dev-branch

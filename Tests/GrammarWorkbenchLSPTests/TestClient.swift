import Foundation
import LanguageServerProtocol

/// A recording `MessageHandler` that plays the role of the LSP client in tests.
///
/// It records notifications sent by the server under test and replies to any
/// request it receives with a `methodNotFound` error (tests do not ask the
/// client to implement requests).
public final class TestClient: MessageHandler, @unchecked Sendable {
    public private(set) var notifications: [any NotificationType] = []

    public init() {}

    public func handle(_ notification: some NotificationType) {
        notifications.append(notification)
    }

    public func handle<Request: RequestType>(
        _ request: Request,
        id: RequestID,
        reply: @escaping @Sendable (LSPResult<Request.Response>) -> Void
    ) {
        reply(.failure(.methodNotFound(Request.method)))
    }
}
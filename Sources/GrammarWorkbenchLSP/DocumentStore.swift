import Foundation
import LanguageServerProtocol

/// The content of a single open text document managed by the server.
public struct OpenDocument: Sendable {
    public let uri: DocumentURI
    public let language: Language
    public var version: Int
    public var text: String

    public init(uri: DocumentURI, language: Language, version: Int, text: String) {
        self.uri = uri
        self.language = language
        self.version = version
        self.text = text
    }
}

/// Stores the text of all open documents, mirroring the client's editor
/// contents so language services can work on the in-memory snapshot instead of
/// the file on disk.
///
/// M0 uses full-document synchronization: the client sends the entire text on
/// every `didChange`, so the store only ever replaces whole documents.
public actor DocumentStore {
    private var documents: [DocumentURI: OpenDocument] = [:]

    public init() {}

    public func open(
        uri: DocumentURI,
        language: Language,
        version: Int,
        text: String
    ) {
        documents[uri] = OpenDocument(uri: uri, language: language, version: version, text: text)
    }

    /// Replaces the document's full text, as sent with a full-sync
    /// `textDocument/didChange` notification.
    ///
    /// - Parameter contentChanges: The change events from the notification. For
    ///   full synchronization the first change event carries the entire new
    ///   text (its range is `nil`).
    public func updateFull(uri: DocumentURI, version: Int, contentChanges: [TextDocumentContentChangeEvent]) {
        guard var document = documents[uri] else { return }
        document.version = version
        if let text = contentChanges.first?.text {
            document.text = text
        }
        documents[uri] = document
    }

    public func close(uri: DocumentURI) {
        documents[uri] = nil
    }

    public func text(for uri: DocumentURI) -> String? {
        documents[uri]?.text
    }

    public func document(for uri: DocumentURI) -> OpenDocument? {
        documents[uri]
    }

    public var openURIs: [DocumentURI] {
        Array(documents.keys)
    }
}

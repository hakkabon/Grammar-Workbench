import Foundation
import GrammarWorkbench
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
/// Both incremental range edits and full-document replacements are accepted.
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

    /// Applies LSP changes sequentially using the shared UTF-16 text snapshot
    /// model. Invalid or stale changes leave the previous snapshot untouched.
    @discardableResult
    public func update(
        uri: DocumentURI,
        version: Int,
        contentChanges: [TextDocumentContentChangeEvent]
    ) -> Bool {
        guard var document = documents[uri] else { return false }
        let edits = contentChanges.map { change in
            GrammarTextEdit(
                range: change.range.map {
                    GrammarTextRange(
                        start: .init(line: $0.lowerBound.line, utf16Column: $0.lowerBound.utf16index),
                        end: .init(line: $0.upperBound.line, utf16Column: $0.upperBound.utf16index)
                    )
                },
                replacement: change.text
            )
        }
        guard let updated = try? GrammarTextSnapshot(
            revision: document.version, text: document.text
        ).applying(edits, revision: version) else { return false }
        document.version = version
        document.text = updated.snapshot.text
        documents[uri] = document
        return true
    }

    /// Compatibility spelling retained for existing full-sync clients.
    public func updateFull(uri: DocumentURI, version: Int, contentChanges: [TextDocumentContentChangeEvent]) {
        update(uri: uri, version: version, contentChanges: contentChanges)
    }

    /// Replaces the document's text as sent with `textDocument/didSave`, which
    /// carries no version, so the document's version is left unchanged.
    public func updateSavedText(uri: DocumentURI, text: String) {
        guard var document = documents[uri] else { return }
        document.text = text
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

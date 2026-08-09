import Foundation

public struct GrammarTextPosition: Hashable, Codable, Sendable {
    public let line: Int
    public let utf16Column: Int

    public init(line: Int, utf16Column: Int) {
        self.line = line
        self.utf16Column = utf16Column
    }
}

public struct GrammarTextRange: Hashable, Codable, Sendable {
    public let start: GrammarTextPosition
    public let end: GrammarTextPosition

    public init(start: GrammarTextPosition, end: GrammarTextPosition) {
        self.start = start
        self.end = end
    }
}

public struct GrammarTextEdit: Hashable, Codable, Sendable {
    /// A nil range replaces the complete document.
    public let range: GrammarTextRange?
    public let replacement: String

    public init(range: GrammarTextRange?, replacement: String) {
        self.range = range
        self.replacement = replacement
    }
}

public enum GrammarIncrementalLanguageError: Error, LocalizedError, Sendable {
    case unknownDocument(String)
    case duplicateDocument(String)
    case staleRevision(current: Int, proposed: Int)
    case invalidPosition(GrammarTextPosition)
    case invalidRange(GrammarTextRange)

    public var errorDescription: String? {
        switch self {
        case .unknownDocument(let id): "No incremental document named ‘\(id)’ is open."
        case .duplicateDocument(let id): "An incremental document named ‘\(id)’ is already open."
        case .staleRevision(let current, let proposed):
            "Document revision \(proposed) is not newer than revision \(current)."
        case .invalidPosition(let position):
            "Invalid text position \(position.line):\(position.utf16Column)."
        case .invalidRange: "The text edit range is reversed or outside the document."
        }
    }
}

public struct GrammarTextChangeSummary: Hashable, Codable, Sendable {
    public let editCount: Int
    public let replacedUTF16Length: Int
    public let insertedUTF16Length: Int
    public var utf16Delta: Int { insertedUTF16Length - replacedUTF16Length }
}

public struct GrammarTextSnapshot: Hashable, Codable, Sendable {
    public let revision: Int
    public let text: String

    public init(revision: Int, text: String) {
        self.revision = revision
        self.text = text
    }

    public func applying(
        _ edits: [GrammarTextEdit],
        revision newRevision: Int
    ) throws -> (snapshot: GrammarTextSnapshot, change: GrammarTextChangeSummary) {
        guard newRevision > revision else {
            throw GrammarIncrementalLanguageError.staleRevision(current: revision, proposed: newRevision)
        }
        var value = text
        var replaced = 0
        var inserted = 0
        for edit in edits {
            let source = value as NSString
            let range: NSRange
            if let requested = edit.range {
                let lower = try Self.utf16Offset(requested.start, in: source)
                let upper = try Self.utf16Offset(requested.end, in: source)
                guard lower <= upper else { throw GrammarIncrementalLanguageError.invalidRange(requested) }
                range = NSRange(location: lower, length: upper - lower)
            } else {
                range = NSRange(location: 0, length: source.length)
            }
            replaced += range.length
            inserted += edit.replacement.utf16.count
            value = source.replacingCharacters(in: range, with: edit.replacement)
        }
        return (
            .init(revision: newRevision, text: value),
            .init(editCount: edits.count, replacedUTF16Length: replaced, insertedUTF16Length: inserted)
        )
    }

    private static func utf16Offset(_ position: GrammarTextPosition, in text: NSString) throws -> Int {
        guard position.line >= 0, position.utf16Column >= 0 else {
            throw GrammarIncrementalLanguageError.invalidPosition(position)
        }
        var line = 0
        var lineStart = 0
        while line < position.line {
            guard lineStart < text.length else {
                throw GrammarIncrementalLanguageError.invalidPosition(position)
            }
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = NSMaxRange(lineRange)
            line += 1
        }
        let lineRange = text.lineRange(for: NSRange(location: min(lineStart, text.length), length: 0))
        var contentEnd = NSMaxRange(lineRange)
        while contentEnd > lineStart {
            let character = text.character(at: contentEnd - 1)
            if character == 0x0A || character == 0x0D { contentEnd -= 1 } else { break }
        }
        let offset = lineStart + position.utf16Column
        guard offset <= contentEnd else {
            throw GrammarIncrementalLanguageError.invalidPosition(position)
        }
        return offset
    }
}

public struct GrammarIncrementalIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public var description: String { "i\(rawValue)" }
}

public struct GrammarIncrementalToken: Identifiable, Hashable, Codable, Sendable {
    public let id: GrammarIncrementalIdentity
    public let token: GrammarInputTokenSnapshot
}

public struct GrammarIncrementalSyntaxNode: Identifiable, Hashable, Codable, Sendable {
    public let id: GrammarIncrementalIdentity
    public let node: GrammarSyntaxNode
    public let children: [GrammarIncrementalSyntaxNode]

    public func descendants(named symbol: String) -> [GrammarIncrementalSyntaxNode] {
        (node.symbol == symbol ? [self] : []) + children.flatMap { $0.descendants(named: symbol) }
    }
}

public struct GrammarIncrementalReuseMetrics: Hashable, Codable, Sendable {
    public let reusedTokens: Int
    public let createdTokens: Int
    public let removedTokens: Int
    public let reusedNodes: Int
    public let createdNodes: Int
    public let removedNodes: Int
}

public struct GrammarIncrementalAnalysisSnapshot: Hashable, Codable, Sendable {
    public let documentID: String
    public let text: GrammarTextSnapshot
    public let grammarRevision: Int
    public let change: GrammarTextChangeSummary?
    public let lexing: GrammarLexingResult
    public let parse: GrammarParseResult
    public let tokens: [GrammarIncrementalToken]
    public let syntaxTree: GrammarIncrementalSyntaxNode?
    public let reuse: GrammarIncrementalReuseMetrics
}

/// A versioned multi-document analysis session. Edits are applied with UTF-16
/// positions (matching LSP and native text systems), while unchanged tokens and
/// syntax subtrees retain stable session-local identities across revisions.
public actor GrammarIncrementalLanguageSession {
    private struct DocumentState {
        var snapshot: GrammarIncrementalAnalysisSnapshot
    }

    private var compilation: GrammarCompilation
    private var grammarRevision = 0
    private var documents: [String: DocumentState] = [:]
    private var nextIdentity = 0

    public init(compilation: GrammarCompilation) throws {
        guard compilation.succeeded else {
            throw GrammarWorkbenchAPIError.compilationFailed(
                compilation.diagnostics.first?.message ?? "The grammar did not compile."
            )
        }
        self.compilation = compilation
    }

    @discardableResult
    public func openDocument(
        id: String,
        text: String,
        revision: Int = 0
    ) throws -> GrammarIncrementalAnalysisSnapshot {
        guard documents[id] == nil else { throw GrammarIncrementalLanguageError.duplicateDocument(id) }
        let snapshot = analyze(
            documentID: id,
            text: .init(revision: revision, text: text),
            previous: nil,
            change: nil
        )
        documents[id] = .init(snapshot: snapshot)
        return snapshot
    }

    @discardableResult
    public func apply(
        documentID: String,
        edits: [GrammarTextEdit],
        revision: Int
    ) throws -> GrammarIncrementalAnalysisSnapshot {
        guard let previous = documents[documentID]?.snapshot else {
            throw GrammarIncrementalLanguageError.unknownDocument(documentID)
        }
        let updated = try previous.text.applying(edits, revision: revision)
        let snapshot = analyze(
            documentID: documentID,
            text: updated.snapshot,
            previous: previous,
            change: updated.change
        )
        documents[documentID] = .init(snapshot: snapshot)
        return snapshot
    }

    public func snapshot(documentID: String) -> GrammarIncrementalAnalysisSnapshot? {
        documents[documentID]?.snapshot
    }

    public var openDocumentIDs: [String] { documents.keys.sorted() }

    public func closeDocument(id: String) { documents[id] = nil }

    /// Reanalyzes all documents against a replacement grammar while retaining
    /// identities for structurally unchanged tokens and syntax subtrees.
    @discardableResult
    public func updateCompilation(
        _ replacement: GrammarCompilation
    ) throws -> [GrammarIncrementalAnalysisSnapshot] {
        guard replacement.succeeded else {
            throw GrammarWorkbenchAPIError.compilationFailed(
                replacement.diagnostics.first?.message ?? "The grammar did not compile."
            )
        }
        compilation = replacement
        grammarRevision += 1
        var results: [GrammarIncrementalAnalysisSnapshot] = []
        for id in documents.keys.sorted() {
            guard let previous = documents[id]?.snapshot else { continue }
            let snapshot = analyze(
                documentID: id,
                text: previous.text,
                previous: previous,
                change: nil
            )
            documents[id] = .init(snapshot: snapshot)
            results.append(snapshot)
        }
        return results
    }

    private func analyze(
        documentID: String,
        text: GrammarTextSnapshot,
        previous: GrammarIncrementalAnalysisSnapshot?,
        change: GrammarTextChangeSummary?
    ) -> GrammarIncrementalAnalysisSnapshot {
        let lexing = compilation.lex(text.text)
        let parse = compilation.parse(text.text)
        let tokenResult = reconcileTokens(lexing.tokens, previous: previous?.tokens ?? [])
        let nodeResult = reconcileTree(parse.syntaxTree, previous: previous?.syntaxTree)
        return .init(
            documentID: documentID,
            text: text,
            grammarRevision: grammarRevision,
            change: change,
            lexing: lexing,
            parse: parse,
            tokens: tokenResult.values,
            syntaxTree: nodeResult.value,
            reuse: .init(
                reusedTokens: tokenResult.reused,
                createdTokens: tokenResult.created,
                removedTokens: tokenResult.removed,
                reusedNodes: nodeResult.reused,
                createdNodes: nodeResult.created,
                removedNodes: nodeResult.removed
            )
        )
    }

    private func reconcileTokens(
        _ tokens: [GrammarInputTokenSnapshot],
        previous: [GrammarIncrementalToken]
    ) -> (values: [GrammarIncrementalToken], reused: Int, created: Int, removed: Int) {
        var available: [String: [GrammarIncrementalIdentity]] = [:]
        for token in previous { available[tokenKey(token.token), default: []].append(token.id) }
        var reused = 0
        let values = tokens.map { token in
            let key = tokenKey(token)
            let id: GrammarIncrementalIdentity
            if var matches = available[key], !matches.isEmpty {
                id = matches.removeFirst()
                available[key] = matches
                reused += 1
            } else {
                id = allocateIdentity()
            }
            return GrammarIncrementalToken(id: id, token: token)
        }
        return (values, reused, values.count - reused, max(0, previous.count - reused))
    }

    private func reconcileTree(
        _ tree: GrammarSyntaxNode?,
        previous: GrammarIncrementalSyntaxNode?
    ) -> (value: GrammarIncrementalSyntaxNode?, reused: Int, created: Int, removed: Int) {
        var available: [String: [GrammarIncrementalIdentity]] = [:]
        var previousCount = 0
        func collect(_ node: GrammarIncrementalSyntaxNode) {
            available[nodeKey(node.node), default: []].append(node.id)
            previousCount += 1
            node.children.forEach(collect)
        }
        if let previous { collect(previous) }
        var reused = 0
        var created = 0
        func rebuild(_ node: GrammarSyntaxNode) -> GrammarIncrementalSyntaxNode {
            let key = nodeKey(node)
            let id: GrammarIncrementalIdentity
            if var matches = available[key], !matches.isEmpty {
                id = matches.removeFirst()
                available[key] = matches
                reused += 1
            } else {
                id = allocateIdentity()
                created += 1
            }
            return .init(id: id, node: node, children: node.children.map(rebuild))
        }
        let value = tree.map(rebuild)
        return (value, reused, created, max(0, previousCount - reused))
    }

    private func allocateIdentity() -> GrammarIncrementalIdentity {
        defer { nextIdentity += 1 }
        return .init(rawValue: nextIdentity)
    }

    private func tokenKey(_ token: GrammarInputTokenSnapshot) -> String {
        "\(token.kind)\u{1F}\(token.lexeme)\u{1F}\(token.mode ?? "")"
    }

    private func nodeKey(_ node: GrammarSyntaxNode) -> String {
        let token = node.token.map { tokenKey($0) } ?? ""
        let children = node.children.map(nodeKey).joined(separator: "\u{1E}")
        return "\(node.symbol)\u{1F}\(node.production.map(String.init) ?? "")\u{1F}\(token)\u{1F}\(children)"
    }
}

/// Owns one incremental language session and reconciles external document
/// versions with its strictly increasing internal revisions. This is the
/// preferred integration boundary for editors, language servers, and build
/// daemons that may receive unversioned saves or repeated snapshots.
public actor GrammarIncrementalAnalysisCoordinator {
    private var session: GrammarIncrementalLanguageSession

    public init(compilation: GrammarCompilation) throws {
        session = try GrammarIncrementalLanguageSession(compilation: compilation)
    }

    /// Returns the current analysis for `text`, reusing the existing snapshot
    /// when it is unchanged. A changed snapshot is installed atomically with a
    /// full replacement edit; ranged edits can still be sent directly to the
    /// underlying language session when an integration already owns them.
    @discardableResult
    public func synchronizeDocument(
        id: String,
        text: String,
        externalRevision: Int? = nil
    ) async throws -> GrammarIncrementalAnalysisSnapshot {
        try Task.checkCancellation()
        if let current = await session.snapshot(documentID: id) {
            guard current.text.text != text else { return current }
            let proposed = max(current.text.revision + 1, externalRevision ?? 0)
            return try await session.apply(
                documentID: id,
                edits: [.init(range: nil, replacement: text)],
                revision: proposed
            )
        }
        return try await session.openDocument(
            id: id,
            text: text,
            revision: max(0, externalRevision ?? 0)
        )
    }

    @discardableResult
    public func updateCompilation(
        _ compilation: GrammarCompilation
    ) async throws -> [GrammarIncrementalAnalysisSnapshot] {
        try Task.checkCancellation()
        return try await session.updateCompilation(compilation)
    }

    public func snapshot(documentID: String) async -> GrammarIncrementalAnalysisSnapshot? {
        await session.snapshot(documentID: documentID)
    }

    public var openDocumentIDs: [String] {
        get async { await session.openDocumentIDs }
    }

    public func closeDocument(id: String) async {
        await session.closeDocument(id: id)
    }
}

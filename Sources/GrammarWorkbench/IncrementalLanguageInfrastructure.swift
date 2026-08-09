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

    static func utf16Offset(_ position: GrammarTextPosition, in text: NSString) throws -> Int {
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

public enum GrammarIncrementalLexingStrategy: String, Hashable, Codable, Sendable {
    case full
    case incremental
    case fallback
}

public struct GrammarIncrementalLexingMetrics: Hashable, Codable, Sendable {
    public let strategy: GrammarIncrementalLexingStrategy
    public let relexedUTF16Start: Int
    public let relexedUTF16End: Int
    public let reusedPrefixTokens: Int
    public let reusedSuffixTokens: Int
    public let fallbackReason: String?

    public var relexedUTF16Length: Int {
        max(0, relexedUTF16End - relexedUTF16Start)
    }
}

public enum GrammarIncrementalParsingStrategy: String, Hashable, Codable, Sendable {
    case full
    case incremental
    case fallback
}

public struct GrammarIncrementalParsingMetrics: Hashable, Codable, Sendable {
    public let strategy: GrammarIncrementalParsingStrategy
    public let resumedTokenIndex: Int
    public let reparsedTokenCount: Int
    public let reusedPrefixTokens: Int
    public let availableCheckpoints: Int
    public let fallbackReason: String?
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
    public let incrementalLexing: GrammarIncrementalLexingMetrics
    public let incrementalParsing: GrammarIncrementalParsingMetrics

    init(
        documentID: String,
        text: GrammarTextSnapshot,
        grammarRevision: Int,
        change: GrammarTextChangeSummary?,
        lexing: GrammarLexingResult,
        parse: GrammarParseResult,
        tokens: [GrammarIncrementalToken],
        syntaxTree: GrammarIncrementalSyntaxNode?,
        reuse: GrammarIncrementalReuseMetrics,
        incrementalLexing: GrammarIncrementalLexingMetrics,
        incrementalParsing: GrammarIncrementalParsingMetrics
    ) {
        self.documentID = documentID; self.text = text
        self.grammarRevision = grammarRevision; self.change = change
        self.lexing = lexing; self.parse = parse; self.tokens = tokens
        self.syntaxTree = syntaxTree; self.reuse = reuse
        self.incrementalLexing = incrementalLexing
        self.incrementalParsing = incrementalParsing
    }

    private enum CodingKeys: String, CodingKey {
        case documentID, text, grammarRevision, change, lexing, parse, tokens
        case syntaxTree, reuse, incrementalLexing, incrementalParsing
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        documentID = try values.decode(String.self, forKey: .documentID)
        text = try values.decode(GrammarTextSnapshot.self, forKey: .text)
        grammarRevision = try values.decode(Int.self, forKey: .grammarRevision)
        change = try values.decodeIfPresent(GrammarTextChangeSummary.self, forKey: .change)
        lexing = try values.decode(GrammarLexingResult.self, forKey: .lexing)
        parse = try values.decode(GrammarParseResult.self, forKey: .parse)
        tokens = try values.decode([GrammarIncrementalToken].self, forKey: .tokens)
        syntaxTree = try values.decodeIfPresent(GrammarIncrementalSyntaxNode.self, forKey: .syntaxTree)
        reuse = try values.decode(GrammarIncrementalReuseMetrics.self, forKey: .reuse)
        incrementalLexing = try values.decodeIfPresent(
            GrammarIncrementalLexingMetrics.self, forKey: .incrementalLexing
        ) ?? .init(
            strategy: .full,
            relexedUTF16Start: 0,
            relexedUTF16End: text.text.utf16.count,
            reusedPrefixTokens: 0,
            reusedSuffixTokens: 0,
            fallbackReason: "Decoded from a snapshot created before incremental lexing metrics."
        )
        incrementalParsing = try values.decodeIfPresent(
            GrammarIncrementalParsingMetrics.self, forKey: .incrementalParsing
        ) ?? .init(
            strategy: .full,
            resumedTokenIndex: 0,
            reparsedTokenCount: lexing.tokens.count,
            reusedPrefixTokens: 0,
            availableCheckpoints: 0,
            fallbackReason: "Decoded from a snapshot created before incremental parsing metrics."
        )
    }
}

/// A versioned multi-document analysis session. Edits are applied with UTF-16
/// positions (matching LSP and native text systems), while unchanged tokens and
/// syntax subtrees retain stable session-local identities across revisions.
public actor GrammarIncrementalLanguageSession {
    private struct DocumentState {
        var snapshot: GrammarIncrementalAnalysisSnapshot
        var lexerCheckpoints: [LexerCheckpoint]
        var parserCheckpoints: [ParserCheckpoint]
        var parserFrames: [ReplayFrame]
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
        let analyzed = analyze(
            documentID: id,
            text: .init(revision: revision, text: text),
            previous: nil,
            previousCheckpoints: [],
            change: nil,
            edits: nil
        )
        documents[id] = .init(
            snapshot: analyzed.snapshot,
            lexerCheckpoints: analyzed.lexerCheckpoints,
            parserCheckpoints: analyzed.parserCheckpoints,
            parserFrames: analyzed.parserFrames
        )
        return analyzed.snapshot
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
        let analyzed = analyze(
            documentID: documentID,
            text: updated.snapshot,
            previous: previous,
            previousCheckpoints: documents[documentID]?.lexerCheckpoints ?? [],
            previousParserCheckpoints: documents[documentID]?.parserCheckpoints ?? [],
            previousParserFrames: documents[documentID]?.parserFrames ?? [],
            change: updated.change,
            edits: edits
        )
        documents[documentID] = .init(
            snapshot: analyzed.snapshot,
            lexerCheckpoints: analyzed.lexerCheckpoints,
            parserCheckpoints: analyzed.parserCheckpoints,
            parserFrames: analyzed.parserFrames
        )
        return analyzed.snapshot
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
            let analyzed = analyze(
                documentID: id,
                text: previous.text,
                previous: previous,
                previousCheckpoints: documents[id]?.lexerCheckpoints ?? [],
                // LR states belong to the compiled artifact and cannot cross
                // a grammar replacement, even when token text is unchanged.
                previousParserCheckpoints: [],
                previousParserFrames: [],
                change: nil,
                edits: nil
            )
            documents[id] = .init(
                snapshot: analyzed.snapshot,
                lexerCheckpoints: analyzed.lexerCheckpoints,
                parserCheckpoints: analyzed.parserCheckpoints,
                parserFrames: analyzed.parserFrames
            )
            results.append(analyzed.snapshot)
        }
        return results
    }

    private func analyze(
        documentID: String,
        text: GrammarTextSnapshot,
        previous: GrammarIncrementalAnalysisSnapshot?,
        previousCheckpoints: [LexerCheckpoint],
        previousParserCheckpoints: [ParserCheckpoint] = [],
        previousParserFrames: [ReplayFrame] = [],
        change: GrammarTextChangeSummary?,
        edits: [GrammarTextEdit]?
    ) -> (
        snapshot: GrammarIncrementalAnalysisSnapshot,
        lexerCheckpoints: [LexerCheckpoint],
        parserCheckpoints: [ParserCheckpoint],
        parserFrames: [ReplayFrame]
    ) {
        let lexed = incrementalLex(
            text: text.text,
            previous: previous,
            previousCheckpoints: previousCheckpoints,
            edits: edits
        )
        let parsed = incrementalParse(
            text: text.text,
            lexing: lexed.result,
            previous: previous,
            previousCheckpoints: previousParserCheckpoints,
            previousFrames: previousParserFrames
        )
        let tokenResult = reconcileTokens(lexed.result.tokens, previous: previous?.tokens ?? [])
        let nodeResult = reconcileTree(parsed.result.syntaxTree, previous: previous?.syntaxTree)
        return (.init(
            documentID: documentID,
            text: text,
            grammarRevision: grammarRevision,
            change: change,
            lexing: lexed.result,
            parse: parsed.result,
            tokens: tokenResult.values,
            syntaxTree: nodeResult.value,
            reuse: .init(
                reusedTokens: tokenResult.reused,
                createdTokens: tokenResult.created,
                removedTokens: tokenResult.removed,
                reusedNodes: nodeResult.reused,
                createdNodes: nodeResult.created,
                removedNodes: nodeResult.removed
            ),
            incrementalLexing: lexed.metrics,
            incrementalParsing: parsed.metrics
        ), lexed.checkpoints, parsed.checkpoints, parsed.frames)
    }

    private func incrementalLex(
        text: String,
        previous: GrammarIncrementalAnalysisSnapshot?,
        previousCheckpoints: [LexerCheckpoint],
        edits: [GrammarTextEdit]?
    ) -> (result: GrammarLexingResult, checkpoints: [LexerCheckpoint], metrics: GrammarIncrementalLexingMetrics) {
        guard let grammar = compilation.compiledGrammar, !grammar.lexerRules.isEmpty else {
            let result = compilation.lex(text)
            return (result, [], .init(
                strategy: previous == nil ? .full : .fallback,
                relexedUTF16Start: 0, relexedUTF16End: text.utf16.count,
                reusedPrefixTokens: 0, reusedSuffixTokens: 0,
                fallbackReason: previous == nil ? nil : "The grammar uses the legacy token-input lexer."
            ))
        }
        let contextSensitivePattern = grammar.lexerRules.first { rule in
            ["(?=", "(?!", "(?<=", "(?<!", "\\z", "\\Z", "$"].contains { rule.pattern.contains($0) }
        }
        if let contextSensitivePattern, previous != nil {
            let full = GrammarLexerRuntime.lex(text, grammar: grammar)
            return (Self.snapshot(full), full.checkpoints, .init(
                strategy: .fallback,
                relexedUTF16Start: 0, relexedUTF16End: text.utf16.count,
                reusedPrefixTokens: 0, reusedSuffixTokens: 0,
                fallbackReason: "Lexer rule \(contextSensitivePattern.id) uses context outside its matched range."
            ))
        }
        guard let previous, let edits, edits.count == 1, let edit = edits.first,
              let range = edit.range, !previousCheckpoints.isEmpty,
              previous.lexing.diagnostics.isEmpty else {
            let full = GrammarLexerRuntime.lex(text, grammar: grammar)
            return (Self.snapshot(full), full.checkpoints, .init(
                strategy: previous == nil ? .full : .fallback,
                relexedUTF16Start: 0, relexedUTF16End: text.utf16.count,
                reusedPrefixTokens: 0, reusedSuffixTokens: 0,
                fallbackReason: previous == nil ? nil : "Incremental lexing requires one ranged edit and a clean previous lex."
            ))
        }

        let oldText = previous.text.text as NSString
        guard let oldStart = try? GrammarTextSnapshot.utf16Offset(range.start, in: oldText),
              let oldEnd = try? GrammarTextSnapshot.utf16Offset(range.end, in: oldText),
              let restart = previousCheckpoints.last(where: { $0.utf16Offset <= oldStart }) else {
            let full = GrammarLexerRuntime.lex(text, grammar: grammar)
            return (Self.snapshot(full), full.checkpoints, .init(
                strategy: .fallback, relexedUTF16Start: 0, relexedUTF16End: text.utf16.count,
                reusedPrefixTokens: 0, reusedSuffixTokens: 0,
                fallbackReason: "No safe lexer checkpoint precedes the edit."
            ))
        }
        let delta = edit.replacement.utf16.count - (oldEnd - oldStart)
        let newChangedEnd = oldStart + edit.replacement.utf16.count
        let oldCheckpoints = Dictionary(uniqueKeysWithValues: previousCheckpoints.map {
            ($0.utf16Offset, $0.modeStack)
        })
        let partial = GrammarLexerRuntime.lex(
            text,
            grammar: grammar,
            startingAt: restart.utf16Offset,
            initialModeStack: restart.modeStack
        ) { checkpoint in
            guard checkpoint.utf16Offset >= newChangedEnd else { return false }
            let oldOffset = checkpoint.utf16Offset - delta
            guard oldOffset >= oldEnd else { return false }
            return oldCheckpoints[oldOffset] == checkpoint.modeStack
        }
        let stop = partial.stoppedAtUTF16Offset ?? text.utf16.count
        let oldStop = stop - delta
        let prefix = previous.lexing.tokens.filter {
            ($0.range?.end.offset ?? Int.max) <= restart.utf16Offset
        }
        let suffix: [GrammarInputTokenSnapshot]
        if partial.stoppedAtUTF16Offset != nil {
            suffix = previous.lexing.tokens.filter {
                ($0.range?.start.offset ?? Int.min) >= oldStop
            }.map { Self.shifted($0, by: delta, in: text) }
        } else {
            suffix = []
        }
        let middle = Self.snapshot(partial).tokens
        let tokens = (prefix + middle + suffix).enumerated().map { index, token in
            GrammarInputTokenSnapshot(
                index: index, kind: token.kind, lexeme: token.lexeme,
                mode: token.mode, range: token.range
            )
        }
        let diagnostics = Self.snapshot(partial).diagnostics.enumerated().map { index, value in
            GrammarInputDiagnostic(
                id: index, message: value.message, mode: value.mode, range: value.range
            )
        }
        var checkpoints = previousCheckpoints.filter { $0.utf16Offset < restart.utf16Offset }
        checkpoints.append(contentsOf: partial.checkpoints)
        if partial.stoppedAtUTF16Offset != nil {
            checkpoints.append(contentsOf: previousCheckpoints.filter { $0.utf16Offset > oldStop }.map {
                .init(utf16Offset: $0.utf16Offset + delta, modeStack: $0.modeStack)
            })
        }
        return (.init(
            tokens: tokens,
            diagnostics: diagnostics,
            finalModeStack: partial.stoppedAtUTF16Offset == nil
                ? partial.finalModeStack : previous.lexing.finalModeStack
        ), checkpoints, .init(
            strategy: .incremental,
            relexedUTF16Start: restart.utf16Offset,
            relexedUTF16End: stop,
            reusedPrefixTokens: prefix.count,
            reusedSuffixTokens: suffix.count,
            fallbackReason: nil
        ))
    }

    private func incrementalParse(
        text: String,
        lexing: GrammarLexingResult,
        previous: GrammarIncrementalAnalysisSnapshot?,
        previousCheckpoints: [ParserCheckpoint],
        previousFrames: [ReplayFrame]
    ) -> (
        result: GrammarParseResult,
        checkpoints: [ParserCheckpoint],
        frames: [ReplayFrame],
        metrics: GrammarIncrementalParsingMetrics
    ) {
        guard !lexing.hasErrors, let artifact = compilation.compiledArtifact else {
            return (compilation.parse(text), [], [], .init(
                strategy: previous == nil ? .full : .fallback,
                resumedTokenIndex: 0,
                reparsedTokenCount: lexing.tokens.count,
                reusedPrefixTokens: 0,
                availableCheckpoints: 0,
                fallbackReason: previous == nil ? nil : "Incremental parsing requires a clean lex and compiled artifact."
            ))
        }

        let kinds = lexing.tokens.map(\.kind)
        guard let previous else {
            let runtime = LRParserRuntime.parse(kinds, artifact: artifact, recovery: .diagnostic)
            return (Self.snapshot(runtime, lexing: lexing), runtime.checkpoints, runtime.frames, .init(
                strategy: .full,
                resumedTokenIndex: 0,
                reparsedTokenCount: kinds.count,
                reusedPrefixTokens: 0,
                availableCheckpoints: runtime.checkpoints.count,
                fallbackReason: nil
            ))
        }

        guard previous.parse.status == .accepted,
              previous.lexing.diagnostics.isEmpty,
              !previousCheckpoints.isEmpty else {
            let runtime = LRParserRuntime.parse(kinds, artifact: artifact, recovery: .diagnostic)
            return (Self.snapshot(runtime, lexing: lexing), runtime.checkpoints, runtime.frames, .init(
                strategy: .fallback,
                resumedTokenIndex: 0,
                reparsedTokenCount: kinds.count,
                reusedPrefixTokens: 0,
                availableCheckpoints: runtime.checkpoints.count,
                fallbackReason: "The previous parse was recovered, rejected, conflicted, or has no checkpoints."
            ))
        }

        var commonPrefix = 0
        while commonPrefix < previous.lexing.tokens.count,
              commonPrefix < lexing.tokens.count,
              Self.sameParserToken(
                previous.lexing.tokens[commonPrefix], lexing.tokens[commonPrefix]
              ) {
            commonPrefix += 1
        }
        guard let checkpoint = previousCheckpoints.first(where: { $0.tokenIndex == commonPrefix }) else {
            let runtime = LRParserRuntime.parse(kinds, artifact: artifact, recovery: .diagnostic)
            return (Self.snapshot(runtime, lexing: lexing), runtime.checkpoints, runtime.frames, .init(
                strategy: .fallback,
                resumedTokenIndex: 0,
                reparsedTokenCount: kinds.count,
                reusedPrefixTokens: 0,
                availableCheckpoints: runtime.checkpoints.count,
                fallbackReason: "No parser checkpoint matches the unchanged token prefix."
            ))
        }

        let newInput = kinds + ["$"]
        let oldInputCount = previous.lexing.tokens.count + 1
        let rebasedFrames = previousFrames.prefix(checkpoint.frameCount).map { frame in
            let consumed = max(0, oldInputCount - frame.remainingInput.count)
            return ReplayFrame(
                index: frame.index,
                stack: frame.stack,
                remainingInput: consumed <= newInput.count
                    ? Array(newInput.dropFirst(consumed)) : [],
                action: frame.action,
                state: frame.state,
                cell: frame.cell,
                production: frame.production
            )
        }
        let rebasedCheckpoint = ParserCheckpoint(
            tokenIndex: checkpoint.tokenIndex,
            steps: checkpoint.steps,
            states: checkpoint.states,
            symbols: checkpoint.symbols,
            nodes: checkpoint.nodes,
            frameCount: rebasedFrames.count
        )
        let runtime = LRParserRuntime.parse(
            kinds, artifact: artifact, recovery: .diagnostic,
            resuming: rebasedCheckpoint, prefixFrames: rebasedFrames
        )
        let prefixCheckpoints = previousCheckpoints.filter { $0.tokenIndex < commonPrefix }
        let checkpoints = prefixCheckpoints + runtime.checkpoints
        return (Self.snapshot(runtime, lexing: lexing), checkpoints, runtime.frames, .init(
            strategy: .incremental,
            resumedTokenIndex: commonPrefix,
            reparsedTokenCount: max(0, kinds.count - commonPrefix),
            reusedPrefixTokens: commonPrefix,
            availableCheckpoints: checkpoints.count,
            fallbackReason: nil
        ))
    }

    private static func sameParserToken(
        _ lhs: GrammarInputTokenSnapshot,
        _ rhs: GrammarInputTokenSnapshot
    ) -> Bool {
        lhs.kind == rhs.kind && lhs.lexeme == rhs.lexeme && lhs.mode == rhs.mode
    }

    private static func snapshot(
        _ runtime: ParserRuntimeResult,
        lexing: GrammarLexingResult
    ) -> GrammarParseResult {
        let syntaxDiagnostics = runtime.diagnostics.map { diagnostic in
            GrammarSyntaxDiagnostic(
                id: diagnostic.index,
                message: diagnostic.message,
                tokenIndex: diagnostic.tokenIndex,
                range: lexing.tokens.indices.contains(diagnostic.tokenIndex)
                    ? lexing.tokens[diagnostic.tokenIndex].range : nil,
                state: diagnostic.state.rawValue,
                unexpected: diagnostic.unexpected,
                expected: diagnostic.expected,
                recovery: diagnostic.recovery.flatMap { GrammarRecoveryKind(rawValue: $0.rawValue) },
                recoverySymbol: diagnostic.recoverySymbol,
                recoveryDetail: diagnostic.recoveryDetail
            )
        }
        let status: GrammarParseStatus
        let expected: [String]
        let conflictState: Int?
        let conflictSymbol: String?
        switch runtime.outcome {
        case .accepted:
            status = syntaxDiagnostics.isEmpty ? .accepted : .acceptedWithRecovery
            expected = syntaxDiagnostics.last?.expected ?? []
            conflictState = nil; conflictSymbol = nil
        case .rejected(_, let values):
            status = .rejected; expected = values
            conflictState = nil; conflictSymbol = nil
        case .conflict(let cell):
            status = .conflict; expected = []
            conflictState = cell.state.rawValue; conflictSymbol = cell.symbol
        case .looping:
            status = .looping; expected = []
            conflictState = nil; conflictSymbol = nil
        }
        return .init(
            status: status,
            message: runtime.outcome.label,
            tokens: lexing.tokens,
            expectedTerminals: expected,
            tree: runtime.tree?.rendered(),
            syntaxTree: runtime.tree.map { GrammarSyntaxNode.make(from: $0, tokens: lexing.tokens) },
            trace: runtime.frames.map { frame in
                GrammarTraceFrameSnapshot(
                    index: frame.index,
                    stack: frame.stack,
                    remainingInput: frame.remainingInput,
                    action: frame.action,
                    state: frame.state?.rawValue,
                    cellSymbol: frame.cell?.symbol,
                    production: frame.production?.rawValue
                )
            },
            conflictState: conflictState,
            conflictSymbol: conflictSymbol,
            diagnostics: syntaxDiagnostics
        )
    }

    private static func snapshot(_ result: LexerResult) -> GrammarLexingResult {
        .init(
            tokens: result.tokens.map {
                .init(index: $0.index, kind: $0.kind, lexeme: $0.lexeme, mode: $0.mode, range: $0.range)
            },
            diagnostics: result.diagnostics.map {
                .init(id: $0.id, message: $0.message, mode: $0.mode, range: $0.range)
            },
            finalModeStack: result.finalModeStack
        )
    }

    private static func shifted(
        _ token: GrammarInputTokenSnapshot,
        by delta: Int,
        in source: String
    ) -> GrammarInputTokenSnapshot {
        guard let range = token.range else { return token }
        return .init(
            index: token.index, kind: token.kind, lexeme: token.lexeme, mode: token.mode,
            range: .init(
                start: sourcePosition(range.start.offset + delta, in: source),
                end: sourcePosition(range.end.offset + delta, in: source)
            )
        )
    }

    private static func sourcePosition(_ offset: Int, in source: String) -> SourcePosition {
        let prefix = (source as NSString).substring(to: offset)
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        return .init(offset: offset, line: lines.count, column: (lines.last?.utf16.count ?? 0) + 1)
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

    /// Applies editor-native ranged edits without first materializing a full
    /// replacement request, enabling the session's incremental lexer path.
    @discardableResult
    public func apply(
        documentID: String,
        edits: [GrammarTextEdit],
        externalRevision: Int? = nil
    ) async throws -> GrammarIncrementalAnalysisSnapshot {
        try Task.checkCancellation()
        guard let current = await session.snapshot(documentID: documentID) else {
            throw GrammarIncrementalLanguageError.unknownDocument(documentID)
        }
        return try await session.apply(
            documentID: documentID,
            edits: edits,
            revision: max(current.text.revision + 1, externalRevision ?? 0)
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

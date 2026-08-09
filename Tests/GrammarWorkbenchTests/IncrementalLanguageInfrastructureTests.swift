import Foundation
import Testing
import GrammarWorkbench

private let incrementalLanguageGrammar = #"""
%token ID /[a-z]+/
%skip /\s+/
%start List
List : List ',' ID | ID ;
"""#

@Test func textSnapshotsApplyUTF16AndSequentialEdits() throws {
    let original = GrammarTextSnapshot(revision: 1, text: "a😀b\nc")
    let updated = try original.applying([
        .init(
            range: .init(
                start: .init(line: 0, utf16Column: 3),
                end: .init(line: 0, utf16Column: 4)
            ),
            replacement: "B"
        ),
        .init(
            range: .init(
                start: .init(line: 1, utf16Column: 1),
                end: .init(line: 1, utf16Column: 1)
            ),
            replacement: "!"
        )
    ], revision: 2)

    #expect(updated.snapshot.text == "a😀B\nc!")
    #expect(updated.change.editCount == 2)
    #expect(updated.change.replacedUTF16Length == 1)
    #expect(updated.change.insertedUTF16Length == 2)
    #expect(updated.change.utf16Delta == 1)
}

@Test func textSnapshotsRejectStaleVersionsAndInvalidPositions() throws {
    let snapshot = GrammarTextSnapshot(revision: 4, text: "abc")
    #expect(throws: GrammarIncrementalLanguageError.self) {
        try snapshot.applying([.init(range: nil, replacement: "x")], revision: 4)
    }
    #expect(throws: GrammarIncrementalLanguageError.self) {
        try snapshot.applying([
            .init(
                range: .init(
                    start: .init(line: 0, utf16Column: 4),
                    end: .init(line: 0, utf16Column: 4)
                ),
                replacement: "x"
            )
        ], revision: 5)
    }
}

@Test func incrementalSessionRetainsTokenAndNodeIdentitiesAcrossEdits() async throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: incrementalLanguageGrammar))
    let session = try GrammarIncrementalLanguageSession(compilation: compilation)
    let opened = try await session.openDocument(id: "main", text: "one, two, three", revision: 1)
    let oldTokenIDs = Dictionary(uniqueKeysWithValues: opened.tokens
        .filter { $0.token.kind == "ID" }
        .map { ($0.token.lexeme, $0.id) })
    let oldNodeIDs = Set(opened.syntaxTree?.descendants(named: "List").map(\.id) ?? [])

    let updated = try await session.apply(
        documentID: "main",
        edits: [.init(
            range: .init(
                start: .init(line: 0, utf16Column: 15),
                end: .init(line: 0, utf16Column: 15)
            ),
            replacement: ", four"
        )],
        revision: 2
    )

    #expect(updated.parse.status == .accepted)
    #expect(updated.tokens.first { $0.token.lexeme == "one" }?.id == oldTokenIDs["one"])
    #expect(updated.tokens.first { $0.token.lexeme == "three" }?.id == oldTokenIDs["three"])
    #expect(updated.reuse.reusedTokens == 5)
    #expect(updated.reuse.createdTokens == 2)
    let newNodeIDs = Set(updated.syntaxTree?.descendants(named: "List").map(\.id) ?? [])
    #expect(!oldNodeIDs.intersection(newNodeIDs).isEmpty)
    #expect(updated.reuse.reusedNodes > 0)
}

@Test func incrementalSessionIsolatesDocumentsAndRejectsOldRevisions() async throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: incrementalLanguageGrammar))
    let session = try GrammarIncrementalLanguageSession(compilation: compilation)
    _ = try await session.openDocument(id: "a", text: "one", revision: 1)
    _ = try await session.openDocument(id: "b", text: "two", revision: 7)

    #expect(await session.openDocumentIDs == ["a", "b"])
    await #expect(throws: GrammarIncrementalLanguageError.self) {
        try await session.apply(
            documentID: "b", edits: [.init(range: nil, replacement: "three")], revision: 7
        )
    }
    #expect(await session.snapshot(documentID: "a")?.text.text == "one")
    await session.closeDocument(id: "a")
    #expect(await session.openDocumentIDs == ["b"])
}

@Test func incrementalSessionReanalyzesDocumentsAfterGrammarReplacement() async throws {
    let first = GrammarWorkbenchAPI.compile(.init(source: incrementalLanguageGrammar))
    let session = try GrammarIncrementalLanguageSession(compilation: first)
    let opened = try await session.openDocument(id: "main", text: "one, two", revision: 1)
    let replacement = GrammarWorkbenchAPI.compile(.init(source: incrementalLanguageGrammar + "\nUnused : 'unused' ;"))
    let refreshed = try await session.updateCompilation(replacement)

    #expect(refreshed.count == 1)
    #expect(refreshed[0].grammarRevision == 1)
    #expect(refreshed[0].text.revision == opened.text.revision)
    #expect(refreshed[0].reuse.reusedTokens == opened.tokens.count)
    #expect(refreshed[0].parse.status == .accepted)
}

@Test func coordinatorIncrementalSnapshotsEqualCleanFullAnalysis() async throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: incrementalLanguageGrammar))
    let coordinator = try GrammarIncrementalAnalysisCoordinator(compilation: compilation)
    let inputs = [
        "one",
        "one, two",
        "one, two, three",
        "zero, one, two, three",
        "zero, one, three",
    ]

    for (revision, input) in inputs.enumerated() {
        let snapshot = try await coordinator.synchronizeDocument(
            id: "main", text: input, externalRevision: revision
        )
        #expect(snapshot.lexing == compilation.lex(input))
        #expect(snapshot.parse == compilation.parse(input))
    }
}

@Test func coordinatorCancellationDoesNotOpenDocument() async throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: incrementalLanguageGrammar))
    let coordinator = try GrammarIncrementalAnalysisCoordinator(compilation: compilation)
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await coordinator.synchronizeDocument(id: "cancelled", text: "one")
    }

    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await coordinator.openDocumentIDs.isEmpty)
}

@Test func coordinatorRapidUpdatesSettleOnLatestEquivalentSnapshot() async throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: incrementalLanguageGrammar))
    let coordinator = try GrammarIncrementalAnalysisCoordinator(compilation: compilation)
    for revision in 1...100 {
        _ = try await coordinator.synchronizeDocument(
            id: "rapid", text: "item\(revision)", externalRevision: revision
        )
    }

    let settled = try #require(await coordinator.snapshot(documentID: "rapid"))
    #expect(settled.text.text == "item100")
    #expect(settled.text.revision == 100)
    #expect(settled.parse == compilation.parse("item100"))
}

@Test func coordinatorDocumentLifecycleReleasesAllSessionState() async throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: incrementalLanguageGrammar))
    let coordinator = try GrammarIncrementalAnalysisCoordinator(compilation: compilation)
    for index in 0..<256 {
        _ = try await coordinator.synchronizeDocument(id: "doc-\(index)", text: "item")
    }
    #expect(await coordinator.openDocumentIDs.count == 256)

    for index in 0..<256 {
        await coordinator.closeDocument(id: "doc-\(index)")
    }
    #expect(await coordinator.openDocumentIDs.isEmpty)
    #expect(await coordinator.snapshot(documentID: "doc-0") == nil)
}

@Test func coordinatorPreservesIdentitiesAcrossGrammarReplacement() async throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: incrementalLanguageGrammar))
    let coordinator = try GrammarIncrementalAnalysisCoordinator(compilation: compilation)
    let before = try await coordinator.synchronizeDocument(id: "main", text: "one, two")
    let replacement = GrammarWorkbenchAPI.compile(.init(
        source: incrementalLanguageGrammar + "\nUnused : 'unused' ;"
    ))

    let refreshed = try await coordinator.updateCompilation(replacement)
    #expect(refreshed.count == 1)
    #expect(refreshed[0].tokens.map(\.id) == before.tokens.map(\.id))
    #expect(refreshed[0].parse == replacement.parse("one, two"))
}

@Test func incrementalLexerReusesStableSuffixAndMatchesCleanLex() async throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: incrementalLanguageGrammar))
    let session = try GrammarIncrementalLanguageSession(compilation: compilation)
    _ = try await session.openDocument(id: "main", text: "one, two, three", revision: 1)
    let updated = try await session.apply(
        documentID: "main",
        edits: [.init(
            range: .init(
                start: .init(line: 0, utf16Column: 0),
                end: .init(line: 0, utf16Column: 3)
            ),
            replacement: "zero"
        )],
        revision: 2
    )

    #expect(updated.lexing == compilation.lex("zero, two, three"))
    #expect(updated.incrementalLexing.strategy == .incremental)
    #expect(updated.incrementalLexing.relexedUTF16Length < updated.text.text.utf16.count)
    #expect(updated.incrementalLexing.reusedSuffixTokens >= 4)
}

@Test func incrementalLexerHandlesUnicodeDamageAndDiagnostics() async throws {
    let grammar = #"""
%token WORD /[a-z]+/
%token FACE /😀/
%skip /\s+/
%start S
S : WORD FACE WORD ;
"""#
    let compilation = GrammarWorkbenchAPI.compile(.init(source: grammar))
    let session = try GrammarIncrementalLanguageSession(compilation: compilation)
    _ = try await session.openDocument(id: "unicode", text: "one 😀 two", revision: 1)
    let updated = try await session.apply(
        documentID: "unicode",
        edits: [.init(
            range: .init(
                start: .init(line: 0, utf16Column: 4),
                end: .init(line: 0, utf16Column: 6)
            ),
            replacement: "😃"
        )],
        revision: 2
    )

    #expect(updated.lexing == compilation.lex("one 😃 two"))
    #expect(updated.incrementalLexing.strategy == .incremental)
    #expect(updated.lexing.diagnostics.count == 1)
    #expect(updated.incrementalLexing.reusedSuffixTokens == 1)
}

@Test func incrementalLexerRestartsBeforeMultilineToken() async throws {
    let grammar = #"""
%token BLOCK /(?s:\/\*.*?\*\/)/
%token ID /[a-z]+/
%skip /\s+/
%start S
S : BLOCK ID ;
"""#
    let compilation = GrammarWorkbenchAPI.compile(.init(source: grammar))
    let session = try GrammarIncrementalLanguageSession(compilation: compilation)
    _ = try await session.openDocument(id: "block", text: "/* first\nline */ tail", revision: 1)
    let updated = try await session.apply(
        documentID: "block",
        edits: [.init(
            range: .init(
                start: .init(line: 0, utf16Column: 3),
                end: .init(line: 0, utf16Column: 8)
            ),
            replacement: "changed"
        )],
        revision: 2
    )
    let expected = "/* changed\nline */ tail"

    #expect(updated.lexing == compilation.lex(expected))
    #expect(updated.incrementalLexing.strategy == .incremental)
    #expect(updated.incrementalLexing.reusedSuffixTokens == 1)
}

@Test func incrementalLexerStabilizesAcrossModeTransitions() async throws {
    let grammar = #"""
%token QUOTE /"/ %push STRING
%token ID /[a-z]+/
%skip /\s+/
%mode STRING
%token TEXT /[a-z ]+/
%token QUOTE /"/ %pop
%start S
S : QUOTE TEXT QUOTE ID ;
"""#
    let compilation = GrammarWorkbenchAPI.compile(.init(source: grammar))
    let session = try GrammarIncrementalLanguageSession(compilation: compilation)
    _ = try await session.openDocument(id: "mode", text: "\"hello world\" tail", revision: 1)
    let updated = try await session.apply(
        documentID: "mode",
        edits: [.init(
            range: .init(
                start: .init(line: 0, utf16Column: 1),
                end: .init(line: 0, utf16Column: 6)
            ),
            replacement: "goodbye"
        )],
        revision: 2
    )
    let expected = "\"goodbye world\" tail"

    #expect(updated.lexing == compilation.lex(expected))
    #expect(updated.incrementalLexing.strategy == .incremental)
    #expect(updated.incrementalLexing.reusedSuffixTokens >= 2)
    #expect(updated.lexing.finalModeStack == ["DEFAULT"])
}

@Test func incrementalLexerReportsExplicitFallbackForFullReplacement() async throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: incrementalLanguageGrammar))
    let session = try GrammarIncrementalLanguageSession(compilation: compilation)
    _ = try await session.openDocument(id: "fallback", text: "one", revision: 1)
    let updated = try await session.apply(
        documentID: "fallback",
        edits: [.init(range: nil, replacement: "two")],
        revision: 2
    )

    #expect(updated.lexing == compilation.lex("two"))
    #expect(updated.incrementalLexing.strategy == .fallback)
    #expect(updated.incrementalLexing.fallbackReason != nil)
}

@Test func incrementalLexerFallsBackForContextSensitiveRegularExpressions() async throws {
    let grammar = #"""
%token A /a(?=b)/
%token B /b/
%token C /c/
%start S
S : A B | C ;
"""#
    let compilation = GrammarWorkbenchAPI.compile(.init(source: grammar))
    let session = try GrammarIncrementalLanguageSession(compilation: compilation)
    _ = try await session.openDocument(id: "lookahead", text: "ab", revision: 1)
    let updated = try await session.apply(
        documentID: "lookahead",
        edits: [.init(
            range: .init(
                start: .init(line: 0, utf16Column: 1),
                end: .init(line: 0, utf16Column: 2)
            ),
            replacement: "c"
        )],
        revision: 2
    )

    #expect(updated.lexing == compilation.lex("ac"))
    #expect(updated.incrementalLexing.strategy == .fallback)
    #expect(updated.incrementalLexing.fallbackReason?.contains("outside") == true)
}

@Test func incrementalSnapshotDecodesPreLexingMetricsPayload() async throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: incrementalLanguageGrammar))
    let session = try GrammarIncrementalLanguageSession(compilation: compilation)
    let snapshot = try await session.openDocument(id: "legacy", text: "one", revision: 1)
    let encoded = try JSONEncoder().encode(snapshot)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["incrementalLexing"] = nil
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(GrammarIncrementalAnalysisSnapshot.self, from: legacy)

    #expect(decoded.lexing == snapshot.lexing)
    #expect(decoded.incrementalLexing.strategy == .full)
    #expect(decoded.incrementalLexing.fallbackReason != nil)
}

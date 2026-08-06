import Foundation
import GrammarWorkbench
import LanguageServerProtocol

/// Expected-token and fuzzy code completion for source documents.
///
/// Completion derives the terminals the parser accepts at the cursor position
/// and offers them as insertion items:
///
/// - A probe parse appends a marker token at the cursor; the parser rejects
///   the marker (or a partially typed token before it) and the rejection
///   reports the terminals valid at that point.
/// - Grammars with lexer rules cannot lex the marker, so the probe parse
///   bails during lexing; the completion falls back to a plain prefix parse,
///   and finally to terminals whose lexer patterns match the partial token.
/// - Candidates are filtered and ranked by a fuzzy match against the partial
///   token (prefix matches first, then character-subsequence matches).
public enum CompletionProvider {
    /// The marker token appended at the cursor to ask the parser what may
    /// follow. It is not a grammar terminal, so the parser always rejects it.
    private static let cursorMarker = "__grammar_workbench_cursor__"

    public static func completions(
        in text: String,
        at position: Position,
        compilation: GrammarCompilation
    ) -> CompletionList {
        guard compilation.succeeded else { return .init(isIncomplete: false, items: []) }
        let nsText = text as NSString
        let cursor = utf16Offset(of: position, in: nsText)
        let queryRange = queryRange(in: nsText, upTo: cursor)
        let query = nsText.substring(with: queryRange)

        var expected = expectedTerminals(
            parse(nsText.substring(to: cursor) + " \(cursorMarker)", compilation: compilation),
            excluding: [cursorMarker, "$"]
        )
        if expected.isEmpty {
            // The marker was not lexable (grammar with lexer rules). Parse the
            // prefix alone; the rejection still reports the expected set when
            // the prefix lexes but does not parse.
            expected = expectedTerminals(
                parse(nsText.substring(to: cursor), compilation: compilation),
                excluding: ["$"]
            )
        }
        var candidates = expected.compactMap { terminalCandidate($0, compilation: compilation) }
        if candidates.isEmpty, !query.isEmpty {
            // Neither parse produced expected terminals (e.g. the cursor is
            // inside a token that cannot be lexed yet). Fall back to terminals
            // whose lexer patterns match the partial token.
            let terminals = compilation.grammar?.terminals ?? []
            candidates = terminals.compactMap { terminalCandidate($0, compilation: compilation) }
                .filter { fuzzyScore(query: query, candidate: $0.insertText) != nil }
        }
        var scored: [(candidate: Candidate, score: Int)]
        if query.isEmpty {
            scored = candidates.map { ($0, 0) }
        } else {
            scored = candidates.compactMap { candidate in
                fuzzyScore(query: query, candidate: candidate.insertText).map { (candidate, $0) }
            }
        }
        scored.sort {
            $0.score == $1.score
                ? $0.candidate.insertText < $1.candidate.insertText
                : $0.score > $1.score
        }
        let editRange = lspRange(queryRange, in: nsText)
        let items = scored.enumerated().map { index, entry in
            CompletionItem(
                label: entry.candidate.display,
                kind: entry.candidate.kind,
                detail: entry.candidate.detail,
                sortText: String(format: "%04d", index),
                textEdit: .textEdit(TextEdit(range: editRange, newText: entry.candidate.insertText))
            )
        }
        return CompletionList(isIncomplete: false, items: items)
    }

    // MARK: - Candidates

    private struct Candidate {
        let display: String
        let insertText: String
        let kind: CompletionItemKind
        let detail: String?
    }

    /// Builds the completion candidate for an expected terminal. Literal
    /// terminals insert their text; named tokens insert their lexer pattern
    /// when it is a plain literal, or the token name otherwise.
    private static func terminalCandidate(_ terminal: String, compilation: GrammarCompilation) -> Candidate? {
        guard terminal != "$" else { return nil }
        let source = compilation.request.source
        if isQuotedLiteral(terminal, in: source) {
            return Candidate(display: terminal, insertText: terminal, kind: .keyword, detail: "'\(terminal)'")
        }
        let pattern = lexerPattern(for: terminal, in: source)
        let insertText = pattern.flatMap(plainLiteral) ?? terminal
        return Candidate(
            display: terminal,
            insertText: insertText,
            kind: .class,
            detail: pattern.map { "/\($0)/" }
        )
    }

    /// Whether `name` appears as a quoted literal terminal in the grammar
    /// source (the engine strips quotes from terminal names).
    private static func isQuotedLiteral(_ name: String, in grammarSource: String) -> Bool {
        grammarSource.contains("'\(name)'") || grammarSource.contains("\"\(name)\"")
    }

    /// The `/pattern/` of a `%token NAME /pattern/` declaration in the grammar
    /// source, or `nil` when the token has no lexer rule.
    ///
    /// Extraction is line-based: the pattern is the text between the first two
    /// slashes after the token name on its `%token` line. This is deliberate —
    /// a regular expression over the whole source can accidentally span lines
    /// (e.g. match the pattern of the next directive) because `\s` matches
    /// newlines.
    private static func lexerPattern(for token: String, in grammarSource: String) -> String? {
        guard let line = grammarSource.split(separator: "\n").first(where: { candidate in
            candidate.contains("%token")
                && candidate.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
                    .contains(Substring(token))
        }) else {
            return nil
        }
        guard let tokenRange = line.range(of: token),
              let slash = line[tokenRange.upperBound...].firstIndex(of: "/"),
              let endSlash = line[line.index(after: slash)...].firstIndex(of: "/")
        else {
            return nil
        }
        let pattern = line[line.index(after: slash)..<endSlash]
            .trimmingCharacters(in: CharacterSet.whitespaces)
        return pattern.isEmpty ? nil : pattern
    }

    /// The pattern's literal text, or `nil` when the pattern is a regular
    /// expression (not insertable as plain text).
    private static func plainLiteral(_ pattern: String) -> String? {
        let specials = Set("\\^$.|?*+()[]{}".utf16)
        guard !pattern.utf16.contains(where: specials.contains) else { return nil }
        return pattern
    }

    // MARK: - Scoring

    /// A prefix match outranks a subsequence match; within a class, longer
    /// candidates are preferred.
    private static func fuzzyScore(query: String, candidate: String) -> Int? {
        let query = query.lowercased()
        let candidate = candidate.lowercased()
        if candidate.hasPrefix(query) {
            return 1000 + candidate.utf16.count
        }
        var queryIndex = query.startIndex
        for character in candidate where queryIndex < query.endIndex {
            if character == query[queryIndex] {
                queryIndex = query.index(after: queryIndex)
            }
        }
        guard queryIndex == query.endIndex else { return nil }
        return 500 + query.utf16.count
    }

    // MARK: - Parsing helpers

    /// Parses without recovery so the first error stops the parse and the
    /// rejection reports the expected terminals at that exact point.
    private static func parse(_ input: String, compilation: GrammarCompilation) -> GrammarParseResult {
        compilation.parse(input, options: GrammarParseOptions(enablesRecovery: false))
    }

    private static func expectedTerminals(_ result: GrammarParseResult, excluding: [String]) -> [String] {
        let excluded = Set(excluding)
        var seen = Set<String>()
        return result.expectedTerminals.filter { !excluded.contains($0) && seen.insert($0).inserted }
    }

    // MARK: - Text helpers

    /// The UTF-16 offset of an LSP position, clamped to the document length.
    private static func utf16Offset(of position: Position, in nsText: NSString) -> Int {
        var offset = 0
        var line = 0
        while line < position.line {
            guard offset < nsText.length else { break }
            let range = nsText.lineRange(for: NSRange(location: offset, length: 0))
            offset = NSMaxRange(range)
            line += 1
        }
        return min(offset + position.utf16index, nsText.length)
    }

    /// The partial token before `cursor`: the characters since the last
    /// whitespace, replaced by the completion edit.
    private static func queryRange(in nsText: NSString, upTo cursor: Int) -> NSRange {
        var start = cursor
        while start > 0, !isWhitespace(nsText.character(at: start - 1)) {
            start -= 1
        }
        return NSRange(location: start, length: cursor - start)
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        switch character {
        case 0x20, 0x09, 0x0A, 0x0D: return true
        default: return false
        }
    }

    /// The LSP range of a UTF-16 range.
    private static func lspRange(_ range: NSRange, in nsText: NSString) -> Range<Position> {
        var line = 0
        var lineStart = 0
        var index = 0
        while index < range.location {
            if nsText.character(at: index) == 0x0A {
                line += 1
                lineStart = index + 1
            }
            index += 1
        }
        return Position(line: line, utf16index: range.location - lineStart)
            ..< Position(line: line, utf16index: range.location + range.length - lineStart)
    }
}

/// Hover information for source documents, derived from the parse tree.
///
/// The deepest node containing the hovered position is shown together with
/// the grammar production it was parsed by.
public enum HoverProvider {
    public static func hover(
        in text: String,
        at position: Position,
        compilation: GrammarCompilation
    ) -> HoverResponse? {
        guard compilation.succeeded,
              let tree = compilation.parse(text).syntaxTree
        else {
            return nil
        }
        guard let located = SyntaxTreeOutline(tree: tree, text: text).node(at: position) else { return nil }
        let productions = Dictionary(
            compilation.artifact?.productions.map { ($0.id, $0) } ?? [],
            uniquingKeysWith: { first, _ in first }
        )
        let production = located.node.production.flatMap { productions[$0] }
            ?? located.parent?.production.flatMap { productions[$0] }
        var parts: [String] = []
        if located.node.isMissing {
            parts.append("Missing `\(located.node.symbol)`")
        } else if let token = located.node.token {
            parts.append("Token `\(unquoted(token.kind))`")
        }
        if let production {
            parts.append("```grammar\n\(pretty(production, grammarSource: compilation.request.source))\n```")
        }
        guard !parts.isEmpty else { return nil }
        return HoverResponse(
            contents: .markupContent(MarkupContent(kind: .markdown, value: parts.joined(separator: "\n\n"))),
            range: DiagnosticsManager.position(located.range.start)..<DiagnosticsManager.position(located.range.end)
        )
    }

    private static func unquoted(_ symbol: String) -> String {
        if symbol.hasPrefix("'") || symbol.hasPrefix("\"") {
            return String(symbol.dropFirst().dropLast())
        }
        return symbol
    }

    /// The production with literal terminals re-quoted for readability.
    private static func pretty(_ production: GrammarProductionSnapshot, grammarSource: String) -> String {
        let rhs = production.rhs.map { symbol in
            grammarSource.contains("'\(symbol)'") ? "'\(symbol)'" : symbol
        }
        return "\(production.lhs) → \(rhs.isEmpty ? "ε" : rhs.joined(separator: " "))"
    }
}

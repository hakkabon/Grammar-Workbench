import Foundation
import GrammarWorkbench
import LanguageServerProtocol

/// Document highlights: the ranges that should be highlighted when the cursor
/// rests on a symbol.
///
/// Grammar documents highlight every occurrence of the symbol under the
/// cursor: nonterminals and token names get their declarations marked as
/// writes and their uses as reads, terminal literals get every use, and
/// directives, comments, and punctuation highlight only themselves.
///
/// Source documents highlight every token with the same kind and lexeme as
/// the token under the cursor (exact matches for identifiers and literals).
public enum DocumentHighlightProvider {
    // MARK: - Grammar documents

    public static func highlights(
        in text: String,
        at position: Position,
        grammar: ParsedGrammar
    ) -> [DocumentHighlight]? {
        let inspector = GrammarDocumentInspector(source: text, grammar: grammar)
        guard let symbol = inspector.symbol(at: position) else { return nil }
        let occurrences: [(range: SourceRange, isDeclaration: Bool)]
        switch symbol.kind {
        case .nonterminal, .tokenName:
            occurrences = inspector.occurrences(of: symbol)
        case .terminalLiteral:
            occurrences = inspector.occurrences(of: symbol.text, kind: .terminalLiteral)
                .map { ($0, false) }
        case .directive, .comment, .lexerPattern, .punctuation:
            occurrences = [(symbol.span, false)]
        }
        return occurrences.map { range, isDeclaration in
            DocumentHighlight(
                range: DiagnosticsManager.position(range.start)..<DiagnosticsManager.position(range.end),
                kind: isDeclaration ? .write : .read
            )
        }
    }

    // MARK: - Source documents

    /// Highlights every token with the same kind and lexeme as the token
    /// under `position`, parsed with `compilation`.
    public static func highlights(
        in text: String,
        at position: Position,
        compilation: GrammarCompilation
    ) -> [DocumentHighlight]? {
        guard compilation.succeeded else { return nil }
        let result = compilation.parse(text)
        let located = locatedTokens(result, text: text)
        guard let target = token(at: position, in: located) else { return nil }
        return located
            .filter { $0.kind == target.kind && $0.lexeme == target.lexeme }
            .map { token in
                DocumentHighlight(
                    range: DiagnosticsManager.position(token.range.start)..<DiagnosticsManager.position(token.range.end),
                    kind: .read
                )
            }
    }

    /// The tokens of `result` with source ranges. Grammars without lexer
    /// rules lex tokens without ranges, so the scanner walks the document in
    /// token order to recover them.
    private static func locatedTokens(
        _ result: GrammarParseResult,
        text: String
    ) -> [(kind: String, lexeme: String, range: SourceRange)] {
        if result.tokens.allSatisfy({ $0.range != nil }) {
            return result.tokens.map { token in
                (token.kind, token.lexeme, token.range ?? SourceRange(
                    start: SourcePosition(offset: 0, line: 1, column: 1),
                    end: SourcePosition(offset: 0, line: 1, column: 1)
                ))
            }
        }
        var scanner = TokenPositionScanner(text: text)
        return result.tokens.map { token in
            (token.kind, token.lexeme, scanner.consume(token.lexeme))
        }
    }

    /// The token whose range contains `position`, or `nil`.
    private static func token(
        at position: Position,
        in tokens: [(kind: String, lexeme: String, range: SourceRange)]
    ) -> (kind: String, lexeme: String, range: SourceRange)? {
        let target = SourcePosition(
            offset: 0, line: position.line + 1, column: position.utf16index + 1
        )
        return tokens.first { contains($0.range, target) }
    }

    private static func contains(_ range: SourceRange, _ position: SourcePosition) -> Bool {
        if range.start == range.end { return position == range.start }
        return (range.start.line < position.line
            || (range.start.line == position.line && range.start.column <= position.column))
            && (range.end.line > position.line
            || (range.end.line == position.line && range.end.column > position.column))
    }
}

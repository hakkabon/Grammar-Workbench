import Foundation
import GrammarWorkbench
import LanguageServerProtocol

/// Quick fixes for diagnostics.
///
/// Source documents get recovery-based actions: the parser's own recovery
/// (an inserted or deleted token) becomes an edit that performs the same
/// fix, and when the parse rejected the input the expected terminals are
/// offered as insertions.
///
/// Grammar documents get syntax actions mirroring the app's quick fixes:
/// declaring an undefined symbol with `%token`, inserting a missing `;` or
/// `:`, and replacing unknown directives with known ones.
public enum RecoveryCodeActionProvider {
    // MARK: - Source documents

    /// Quick fixes for the parse of `sourceText` whose range intersects
    /// `range`, located in the document at `uri`.
    public static func recoveryCodeActions(
        in sourceText: String,
        range: Range<Position>,
        compilation: GrammarCompilation,
        uri: DocumentURI
    ) -> [CodeAction] {
        guard compilation.succeeded else { return [] }
        let lexed = compilation.lex(sourceText)
        if lexed.hasErrors {
            // Lexical errors have no deterministic fix.
            return []
        }
        let result = compilation.parse(sourceText)
        // Non-lexer grammars lex tokens without ranges, so parse diagnostics
        // arrive without positions; the scanner walks the lexed tokens in
        // document order to recover them.
        var scanner = TokenPositionScanner(text: sourceText)
        var scannedTokens = 0
        var actions: [CodeAction] = []
        for diagnostic in result.diagnostics {
            let diagnosticRange: SourceRange
            if let range = diagnostic.range {
                diagnosticRange = range
            } else {
                let index = diagnostic.tokenIndex
                while scannedTokens < index, scannedTokens < result.tokens.count {
                    _ = scanner.consume(result.tokens[scannedTokens].lexeme)
                    scannedTokens += 1
                }
                if result.tokens.indices.contains(index) {
                    diagnosticRange = scanner.consume(result.tokens[index].lexeme)
                    scannedTokens = index + 1
                } else {
                    // Beyond the input (e.g. end-of-input): a zero-width range
                    // at the current cursor.
                    diagnosticRange = scanner.consume(diagnostic.unexpected)
                }
            }
            guard intersects(diagnosticRange, request: range)
            else {
                continue
            }
            let lspDiagnostic = lspDiagnostic(diagnostic, code: "syntax")
            let at = DiagnosticsManager.position(diagnosticRange.start)
            switch diagnostic.recovery {
            case .insertedToken?:
                if let symbol = diagnostic.recoverySymbol {
                    actions.append(insert(
                        symbol,
                        at: at,
                        title: "Insert missing ‘\(symbol)’",
                        diagnostic: lspDiagnostic,
                        uri: uri
                    ))
                }
            case .deletedToken?:
                if let symbol = diagnostic.recoverySymbol {
                    actions.append(delete(
                        range: DiagnosticsManager.position(diagnosticRange.start)..<DiagnosticsManager.position(diagnosticRange.end),
                        title: "Delete ‘\(symbol)’",
                        diagnostic: lspDiagnostic,
                        uri: uri
                    ))
                }
            case .synchronized?, .none:
                // Synchronization discards a run of tokens; no deterministic
                // edit. A rejected parse (no recovery) offers its expected
                // terminals as insertions.
                for terminal in diagnostic.expected.prefix(3) {
                    actions.append(insert(
                        terminal,
                        at: at,
                        title: "Insert ‘\(terminal)’",
                        diagnostic: lspDiagnostic,
                        uri: uri
                    ))
                }
            }
        }
        return actions
    }

    // MARK: - Grammar documents

    /// Quick fixes for the diagnostics of a compiled grammar document.
    public static func grammarCodeActions(
        in grammarSource: String,
        range: Range<Position>,
        compilation: GrammarCompilation,
        uri: DocumentURI
    ) -> [CodeAction] {
        var actions: [CodeAction] = []
        for diagnostic in compilation.diagnostics {
            let diagnosticRange = diagnostic.range
            guard intersects(diagnosticRange, request: range) else {
                continue
            }
            let lspDiagnostic = lspDiagnostic(diagnostic, code: diagnostic.code)
            if diagnostic.code == "undefined-symbol",
               diagnosticRange.end.offset > diagnosticRange.start.offset,
               diagnosticRange.end.offset <= grammarSource.count {
                let start = grammarSource.index(
                    grammarSource.startIndex,
                    offsetBy: diagnosticRange.start.offset,
                    limitedBy: grammarSource.endIndex
                )
                let end = grammarSource.index(
                    grammarSource.startIndex,
                    offsetBy: diagnosticRange.end.offset,
                    limitedBy: grammarSource.endIndex
                )
                if let start, let end {
                    let symbol = String(grammarSource[start..<end])
                    actions.append(CodeAction(
                        title: "Declare ‘\(symbol)’ with %token",
                        kind: .quickFix,
                        diagnostics: [lspDiagnostic],
                        isPreferred: true,
                        edit: WorkspaceEdit(changes: [uri: [
                            TextEdit(range: Position(line: 0, utf16index: 0)..<Position(line: 0, utf16index: 0), newText: "%token \(symbol)\n")
                        ]])
                    ))
                }
            } else if diagnostic.message.hasPrefix("Expected ‘;’") {
                let at = DiagnosticsManager.position(diagnosticRange.start)
                actions.append(insert(";", at: at, title: "Insert missing ‘;’", diagnostic: lspDiagnostic, uri: uri))
            } else if diagnostic.message.hasPrefix("Expected ‘:’ after nonterminal") {
                let at = DiagnosticsManager.position(diagnosticRange.start)
                actions.append(insert(": ", at: at, title: "Insert missing ‘:’", diagnostic: lspDiagnostic, uri: uri))
            } else if diagnostic.message.hasPrefix("Unknown directive") {
                let editRange = DiagnosticsManager.position(diagnosticRange.start)..<DiagnosticsManager.position(diagnosticRange.end)
                for directive in GrammarDocumentInspector.directiveSummaries.keys.sorted() {
                    actions.append(CodeAction(
                        title: "Replace with \(directive)",
                        kind: .quickFix,
                        diagnostics: [lspDiagnostic],
                        edit: WorkspaceEdit(changes: [uri: [TextEdit(range: editRange, newText: directive)]])
                    ))
                }
            }
        }
        return actions
    }

    // MARK: - Helpers

    private static func insert(
        _ text: String,
        at position: Position,
        title: String,
        diagnostic: Diagnostic,
        uri: DocumentURI
    ) -> CodeAction {
        CodeAction(
            title: title,
            kind: .quickFix,
            diagnostics: [diagnostic],
            isPreferred: true,
            edit: WorkspaceEdit(changes: [uri: [
                TextEdit(range: position..<position, newText: "\(text) ")
            ]])
        )
    }

    private static func delete(
        range: Range<Position>,
        title: String,
        diagnostic: Diagnostic,
        uri: DocumentURI
    ) -> CodeAction {
        CodeAction(
            title: title,
            kind: .quickFix,
            diagnostics: [diagnostic],
            isPreferred: true,
            edit: WorkspaceEdit(changes: [uri: [TextEdit(range: range, newText: "")]])
        )
    }

    private static func lspDiagnostic(
        _ diagnostic: GrammarDiagnostic,
        code: String
    ) -> Diagnostic {
        return Diagnostic(
            range: DiagnosticsManager.position(diagnostic.range.start)..<DiagnosticsManager.position(diagnostic.range.end),
            severity: diagnostic.severity == .error ? .error : .warning,
            code: .string(code),
            source: "grammar-workbench",
            message: diagnostic.message
        )
    }

    private static func lspDiagnostic(
        _ diagnostic: GrammarSyntaxDiagnostic,
        code: String
    ) -> Diagnostic {
        let range = diagnostic.range ?? SourceRange(
            start: SourcePosition(offset: 0, line: 1, column: 1),
            end: SourcePosition(offset: 0, line: 1, column: 1)
        )
        return Diagnostic(
            range: DiagnosticsManager.position(range.start)..<DiagnosticsManager.position(range.end),
            severity: .error,
            code: .string(code),
            source: "grammar-workbench",
            message: diagnostic.message
        )
    }

    private static func intersects(_ range: SourceRange, request: Range<Position>) -> Bool {
        let start = DiagnosticsManager.position(range.start)
        let end = DiagnosticsManager.position(range.end)
        return !(end <= request.lowerBound || request.upperBound <= start)
    }
}

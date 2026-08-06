import Foundation
import GrammarWorkbench
import LanguageServerProtocol

/// How the server treats a document: grammar definitions are compiled with the
/// Grammar Workbench engine; everything else is a source document parsed with
/// an open grammar.
public enum GrammarDocumentKind: Equatable {
    case grammar(notation: GrammarSourceNotation)
    case source
}

public extension DocumentURI {
    /// The Workbench notation is used for `.grammarworkbench` and `.grammar`
    /// files, the ISO EBNF notation for `.ebnf` files, and every other
    /// extension is treated as a source document.
    var grammarWorkbenchKind: GrammarDocumentKind {
        switch arbitrarySchemeURL.pathExtension.lowercased() {
        case "grammarworkbench", "grammar":
            return .grammar(notation: .workbench)
        case "ebnf":
            return .grammar(notation: .ebnf)
        default:
            return .source
        }
    }
}

/// Compiles open grammar documents and converts engine diagnostics into LSP
/// diagnostics.
///
/// A source document is parsed with the grammar whose file base name matches
/// the source document's language identifier (e.g. a document with language
/// `expr` uses `expr.grammarworkbench`); when no grammar matches, the most
/// recently updated grammar document is used as a fallback.
public actor DiagnosticsManager {
    private struct GrammarDocument {
        let uri: DocumentURI
        let compilation: GrammarCompilation
    }

    private let compiler = GrammarWorkbenchIncrementalCompiler()
    private var grammarDocuments: [DocumentURI: GrammarDocument] = [:]
    private var mostRecentGrammarURI: DocumentURI?

    public init() {}

    /// Recompiles the grammar document at `uri` with the given source text and
    /// stores the result for source-document analysis. Identical requests are
    /// served from the compiler's cache.
    @discardableResult
    public func compileGrammar(
        uri: DocumentURI,
        source: String,
        notation: GrammarSourceNotation
    ) async -> GrammarCompilation {
        let compilation = await compiler.compile(GrammarCompilationRequest(source: source, notation: notation))
        grammarDocuments[uri] = GrammarDocument(uri: uri, compilation: compilation)
        mostRecentGrammarURI = uri
        return compilation
    }

    public func removeGrammar(uri: DocumentURI) {
        grammarDocuments[uri] = nil
        if mostRecentGrammarURI == uri {
            mostRecentGrammarURI = grammarDocuments.keys.sorted { $0.stringValue < $1.stringValue }.last
        }
    }

    /// The compilation used for source documents with the given language id.
    public func grammarCompilation(for languageId: String) -> GrammarCompilation? {
        if let match = grammarDocuments.values.first(where: { $0.uri.grammarFileBaseName == languageId }) {
            return match.compilation
        }
        return mostRecentGrammarURI.flatMap { grammarDocuments[$0]?.compilation }
    }

    /// The compilation for a source document whose language id matches a
    /// grammar exactly, or `nil` when no grammar declares that language.
    /// Unlike `grammarCompilation(for:)` this never falls back to another
    /// grammar, so a source document is never completed or hovered with the
    /// wrong grammar.
    public func exactGrammarCompilation(for languageId: String) -> GrammarCompilation? {
        grammarDocuments.values.first { $0.uri.grammarFileBaseName == languageId }?.compilation
    }

    /// LSP diagnostics for a grammar document compiled from `grammarSource`.
    public func lspDiagnostics(compilation: GrammarCompilation, grammarSource: String) -> [Diagnostic] {
        compilation.diagnostics.map(lspDiagnostic)
    }

    /// LSP diagnostics for a source document parsed with `compilation`.
    ///
    /// Lexical errors are reported as `lexical` diagnostics; when the input
    /// lexes cleanly, parse errors are reported as `syntax` diagnostics.
    public func lspDiagnostics(compilation: GrammarCompilation, sourceText: String) -> [Diagnostic] {
        guard compilation.succeeded else { return [] }
        let lexed = compilation.lex(sourceText)
        if !lexed.diagnostics.isEmpty {
            return lexed.diagnostics.map { diagnostic in
                lspDiagnostic(severity: .error, code: "lexical", message: diagnostic.message, range: diagnostic.range)
            }
        }
        return compilation.parse(sourceText).diagnostics.map { diagnostic in
            lspDiagnostic(severity: .error, code: "syntax", message: diagnostic.message, range: diagnostic.range)
        }
    }

    // MARK: - Conversion

    /// Converts an engine position to an LSP position. The engine reports
    /// one-based lines and columns measured in characters; LSP positions are
    /// zero-based with UTF-16 code-unit columns, which coincide for ASCII
    /// content.
    public static func position(_ position: SourcePosition) -> Position {
        Position(line: max(0, position.line - 1), utf16index: max(0, position.column - 1))
    }

    private func lspDiagnostic(_ diagnostic: GrammarDiagnostic) -> Diagnostic {
        lspDiagnostic(
            severity: diagnostic.severity == .error ? .error : .warning,
            code: diagnostic.code,
            message: diagnostic.message,
            range: diagnostic.range
        )
    }

    private func lspDiagnostic(
        severity: DiagnosticSeverity,
        code: String,
        message: String,
        range: SourceRange?
    ) -> Diagnostic {
        // LSP requires a range; diagnostics without one (e.g. at end of input)
        // are reported as a zero-width range at the start of the document.
        let resolved = range ?? SourceRange(
            start: SourcePosition(offset: 0, line: 1, column: 1),
            end: SourcePosition(offset: 0, line: 1, column: 1)
        )
        return Diagnostic(
            range: Self.position(resolved.start)..<Self.position(resolved.end),
            severity: severity,
            code: .string(code),
            source: "grammar-workbench",
            message: message
        )
    }
}

private extension DocumentURI {
    /// The file's base name without its extension, used to associate source
    /// documents with grammars by language id.
    var grammarFileBaseName: String {
        arbitrarySchemeURL.deletingPathExtension().lastPathComponent
    }
}

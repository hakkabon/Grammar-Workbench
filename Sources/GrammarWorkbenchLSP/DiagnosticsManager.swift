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
    /// The Workbench notation is used for `.gwb`, legacy `.grammarworkbench`,
    /// and Yacc-like source files, the ISO EBNF front end for `.bnf` and
    /// `.ebnf` files, and every other
    /// extension is treated as a source document.
    var grammarWorkbenchKind: GrammarDocumentKind {
        switch arbitrarySchemeURL.pathExtension.lowercased() {
        case "gwb", "grammarworkbench", "grammar", "y", "yacc", "yy":
            return .grammar(notation: .workbench)
        case "bnf", "ebnf":
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
        let coordinator: GrammarIncrementalAnalysisCoordinator?
    }

    private let compiler = GrammarWorkbenchIncrementalCompiler()
    private var grammarDocuments: [DocumentURI: GrammarDocument] = [:]
    private var explicitGrammarURIs: [String: DocumentURI] = [:]
    private var mostRecentGrammarURI: DocumentURI?

    public init() {}

    /// Registers a project-declared language identifier independently of the
    /// grammar filename. Editor clients provide these mappings during LSP
    /// initialization from the shared source-project descriptor.
    public func registerGrammar(languageID: String, uri: DocumentURI) {
        explicitGrammarURIs[languageID] = uri
    }

    private func exactGrammarDocument(for languageID: String) -> GrammarDocument? {
        if let uri = explicitGrammarURIs[languageID], let document = grammarDocuments[uri] {
            return document
        }
        return grammarDocuments.values.first {
            $0.uri.grammarFileBaseName.caseInsensitiveCompare(languageID) == .orderedSame
        }
    }

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
        let coordinator: GrammarIncrementalAnalysisCoordinator?
        if compilation.succeeded {
            if let existing = grammarDocuments[uri]?.coordinator {
                _ = try? await existing.updateCompilation(compilation)
                coordinator = existing
            } else {
                coordinator = try? GrammarIncrementalAnalysisCoordinator(compilation: compilation)
            }
        } else {
            coordinator = nil
        }
        grammarDocuments[uri] = GrammarDocument(
            uri: uri, compilation: compilation, coordinator: coordinator
        )
        mostRecentGrammarURI = uri
        return compilation
    }

    public func removeGrammar(uri: DocumentURI) {
        grammarDocuments[uri] = nil
        if mostRecentGrammarURI == uri {
            mostRecentGrammarURI = grammarDocuments.keys.sorted { $0.stringValue < $1.stringValue }.last
        }
    }

    /// Removes a source document from every grammar-owned analysis session.
    public func removeSourceDocument(uri: DocumentURI) async {
        for document in grammarDocuments.values {
            await document.coordinator?.closeDocument(id: uri.stringValue)
        }
    }

    /// Analyzes a source document through the shared incremental coordinator.
    /// The selected grammar follows the same exact-match/fallback policy as
    /// `grammarCompilation(for:)`.
    public func sourceAnalysis(
        uri: DocumentURI,
        languageId: String,
        text: String,
        version: Int
    ) async -> GrammarIncrementalAnalysisSnapshot? {
        let selected = exactGrammarDocument(for: languageId)
            ?? mostRecentGrammarURI.flatMap { grammarDocuments[$0] }
        guard let coordinator = selected?.coordinator else { return nil }
        return try? await coordinator.synchronizeDocument(
            id: uri.stringValue,
            text: text,
            externalRevision: version
        )
    }

    /// Applies the editor's original ranged changes to an already-open source
    /// analysis. The later debounced publish observes this exact snapshot.
    public func applySourceEdits(
        uri: DocumentURI,
        languageId: String,
        edits: [GrammarTextEdit],
        version: Int
    ) async {
        let selected = exactGrammarDocument(for: languageId)
            ?? mostRecentGrammarURI.flatMap { grammarDocuments[$0] }
        guard let coordinator = selected?.coordinator else { return }
        _ = try? await coordinator.apply(
            documentID: uri.stringValue,
            edits: edits,
            externalRevision: version
        )
    }

    /// The compilation used for source documents with the given language id.
    public func grammarCompilation(for languageId: String) -> GrammarCompilation? {
        if let match = exactGrammarDocument(for: languageId) {
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
        exactGrammarDocument(for: languageId)?.compilation
    }

    /// The compilation stored for the grammar document at `uri`, if open.
    public func compilation(for uri: DocumentURI) -> GrammarCompilation? {
        grammarDocuments[uri]?.compilation
    }

    /// The URI of the grammar document that declares the given language id.
    public func grammarDocumentURI(for languageId: String) -> DocumentURI? {
        exactGrammarDocument(for: languageId)?.uri
    }

    /// LSP diagnostics for a grammar document compiled from `grammarSource`.
    public func lspDiagnostics(compilation: GrammarCompilation, grammarSource: String) -> [Diagnostic] {
        compilation.diagnostics.map(lspDiagnostic)
    }

    /// LSP diagnostics for a source document parsed with `compilation`.
    ///
    /// Lexical errors are reported as `lexical` diagnostics; when the input
    /// lexes cleanly, parse errors are reported as `syntax` diagnostics. The
    /// terminals the parser expected at the point of failure are appended to
    /// the last syntax diagnostic, mirroring the engine's own recovery state.
    public func lspDiagnostics(compilation: GrammarCompilation, sourceText: String) -> [Diagnostic] {
        guard compilation.succeeded else { return [] }
        let lexed = compilation.lex(sourceText)
        if !lexed.diagnostics.isEmpty {
            return lexed.diagnostics.map { diagnostic in
                lspDiagnostic(severity: .error, code: "lexical", message: diagnostic.message, range: diagnostic.range)
            }
        }
        let result = compilation.parse(sourceText)
        let expected = result.expectedTerminals
        return result.diagnostics.enumerated().map { index, diagnostic in
            var message = diagnostic.message
            if index == result.diagnostics.count - 1, !expected.isEmpty {
                let listed = expected.count > 6
                    ? expected.prefix(6).joined(separator: ", ") + ", …"
                    : expected.joined(separator: ", ")
                message += " Expected: \(listed)."
            }
            return lspDiagnostic(severity: .error, code: "syntax", message: message, range: diagnostic.range)
        }
    }

    /// Converts a shared incremental analysis snapshot into LSP diagnostics.
    public func lspDiagnostics(snapshot: GrammarIncrementalAnalysisSnapshot) -> [Diagnostic] {
        if !snapshot.lexing.diagnostics.isEmpty {
            return snapshot.lexing.diagnostics.map { diagnostic in
                lspDiagnostic(severity: .error, code: "lexical", message: diagnostic.message, range: diagnostic.range)
            }
        }
        let expected = snapshot.parse.expectedTerminals
        return snapshot.parse.diagnostics.enumerated().map { index, diagnostic in
            var message = diagnostic.message
            if index == snapshot.parse.diagnostics.count - 1, !expected.isEmpty {
                let listed = expected.count > 6
                    ? expected.prefix(6).joined(separator: ", ") + ", …"
                    : expected.joined(separator: ", ")
                message += " Expected: \(listed)."
            }
            return lspDiagnostic(
                severity: .error, code: "syntax", message: message, range: diagnostic.range
            )
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

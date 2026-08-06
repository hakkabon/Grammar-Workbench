import Foundation
import GrammarWorkbench
import LanguageServerProtocol

/// Semantic tokens for grammar and source documents.
///
/// Grammar documents are scanned into spans (directives, terminals, lexer
/// patterns, comments, punctuation, nonterminals, token names); source
/// documents are parsed and every terminal token is classified by its name
/// and the grammar that matched it. Tokens are encoded in the relative form
/// (delta line, delta start, length, type index, modifier bitfield).
public enum SemanticTokensProvider {
    /// The legend advertised in the server capabilities; token type indices
    /// are indexes into this array.
    public static let legend = SemanticTokensLegend(
        tokenTypes: [
            "keyword", "string", "number", "regexp", "comment",
            "operator", "type", "enumMember", "variable",
        ],
        tokenModifiers: []
    )

    private static let keyword = 0
    private static let string = 1
    private static let number = 2
    private static let regexp = 3
    private static let comment = 4
    private static let `operator` = 5
    private static let type = 6
    private static let enumMember = 7
    private static let variable = 8

    // MARK: - Grammar documents

    public static func semanticTokens(
        in text: String,
        grammar: ParsedGrammar
    ) -> DocumentSemanticTokensResponse? {
        let inspector = GrammarDocumentInspector(source: text, grammar: grammar)
        let tokens: [(range: SourceRange, type: Int)] = inspector.tokenSpans().compactMap { span in
            guard let type = typeIndex(for: span.kind) else { return nil }
            return (span.range, type)
        }
        return DocumentSemanticTokensResponse(data: encode(tokens))
    }

    /// The token type for a grammar-document span kind, or `nil` when the
    /// span (e.g. whitespace-adjacent punctuation) carries no semantic role.
    private static func typeIndex(for kind: GrammarDocumentInspector.Symbol.Kind) -> Int? {
        switch kind {
        case .directive: return keyword
        case .terminalLiteral: return string
        case .tokenName: return enumMember
        case .nonterminal: return type
        case .lexerPattern: return regexp
        case .comment: return comment
        case .punctuation: return `operator`
        }
    }

    // MARK: - Source documents

    public static func semanticTokens(
        in text: String,
        compilation: GrammarCompilation
    ) -> DocumentSemanticTokensResponse? {
        guard compilation.succeeded,
              let grammar = compilation.parsedGrammar,
              let tree = compilation.parse(text).syntaxTree
        else {
            return nil
        }
        var terminals: [(range: SourceRange?, kind: String)] = []
        collectTerminals(tree, into: &terminals)
        var scanner = TokenPositionScanner(text: text)
        let tokens: [(range: SourceRange, type: Int)] = terminals.compactMap { terminal in
            let range = terminal.range ?? scanner.consume(terminal.kind)
            guard let type = typeIndex(for: terminal.kind, grammar: grammar) else { return nil }
            return (range, type)
        }
        return DocumentSemanticTokensResponse(data: encode(tokens))
    }

    /// Collects every terminal token of the parse tree in document order.
    private static func collectTerminals(
        _ node: GrammarSyntaxNode,
        into tokens: inout [(range: SourceRange?, kind: String)]
    ) {
        if node.isTerminal {
            tokens.append((node.token?.range, node.token?.kind ?? node.symbol))
            return
        }
        for child in node.children {
            collectTerminals(child, into: &tokens)
        }
    }

    /// The token type for a source-document terminal: terminals declared by a
    /// lexer rule are classified by their rule name, and literal terminals are
    /// keywords.
    private static func typeIndex(for kind: String, grammar: ParsedGrammar) -> Int? {
        if grammar.lexerRules.contains(where: { $0.token == kind }) {
            return typeIndex(forNamedToken: kind)
        }
        guard grammar.terminals.contains(kind) else { return nil }
        return keyword
    }

    /// Classifies a token declared by a lexer rule by its name: names with a
    /// numeric connotation are numbers, textual ones strings, identifiers
    /// variables, and everything else a keyword.
    private static func typeIndex(forNamedToken name: String) -> Int {
        let normalized = name.uppercased()
        if normalized.contains("NUM") {
            return number
        }
        if normalized.contains("STRING") || normalized.contains("TEXT") {
            return string
        }
        if normalized.hasSuffix("ID") || normalized.contains("IDENT") {
            return variable
        }
        return keyword
    }

    // MARK: - Encoding

    /// Encodes tokens (sorted by position) into the relative LSP format:
    /// five `UInt32` entries per token: delta line, delta start, length,
    /// token type index, modifier bitfield.
    public static func encode(_ tokens: [(range: SourceRange, type: Int)]) -> [UInt32] {
        var result: [UInt32] = []
        result.reserveCapacity(tokens.count * 5)
        var previousLine = 0
        var previousStart = 0
        for token in tokens {
            let line = max(0, token.range.start.line - 1)
            let start = max(0, token.range.start.column - 1)
            let end = max(0, token.range.end.column - 1)
            let deltaLine = line - previousLine
            result.append(UInt32(deltaLine))
            result.append(UInt32(deltaLine == 0 ? start - previousStart : start))
            result.append(UInt32(max(0, end - start)))
            result.append(UInt32(token.type))
            result.append(0)
            previousLine = line
            previousStart = start
        }
        return result
    }
}

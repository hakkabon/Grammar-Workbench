import Foundation
import GrammarWorkbench
import LanguageServerProtocol

/// Language services for grammar documents: completion of directives and
/// grammar symbols, hover with production/rule details, and go-to-definition
/// for nonterminals, terminals, and token names.
///
/// Source documents additionally resolve go-to-definition: a token in a source
/// document jumps to its `%token` rule (or first use of a literal terminal) in
/// the grammar document.
public enum GrammarDocumentProvider {
    // MARK: - Grammar document completion

    public static func completions(
        in text: String,
        at position: Position,
        grammar: ParsedGrammar
    ) -> CompletionList {
        let inspector = GrammarDocumentInspector(source: text, grammar: grammar)
        let candidates = inspector.completions(at: position)
        let editRange = inspector.partialWordRange(at: position)
        let items = candidates.enumerated().map { index, candidate in
            CompletionItem(
                label: candidate.name,
                kind: candidate.isDirective ? .keyword : .class,
                detail: candidate.isDirective
                    ? GrammarDocumentInspector.directiveSummaries[candidate.name]
                    : nil,
                sortText: String(format: "%04d", index),
                textEdit: .textEdit(TextEdit(range: editRange, newText: candidate.name))
            )
        }
        return CompletionList(isIncomplete: false, items: items)
    }

    // MARK: - Grammar document hover

    public static func hover(
        in text: String,
        at position: Position,
        grammar: ParsedGrammar
    ) -> HoverResponse? {
        let inspector = GrammarDocumentInspector(source: text, grammar: grammar)
        guard let symbol = inspector.symbol(at: position) else { return nil }
        let value: String
        switch symbol.kind {
        case .nonterminal:
            let productions = symbol.productions.map(\.text)
            guard !productions.isEmpty else { return nil }
            value = "**Nonterminal `\(symbol.text)`**\n\n"
                + productions.map { "`\($0)`" }.joined(separator: "\n")
        case .tokenName:
            guard let rule = symbol.lexerRule else { return nil }
            var parts = ["**Token `\(symbol.text)`**", "`/\(rule.pattern)/`"]
            if rule.mode != "DEFAULT" {
                parts.append("Mode `\(rule.mode)`")
            }
            switch rule.action {
            case .begin(let mode): parts.append("Begin mode `\(mode)` after match")
            case .push(let mode): parts.append("Push mode `\(mode)` after match")
            case .pop: parts.append("Pop mode after match")
            case .none: break
            }
            value = parts.joined(separator: "\n\n")
        case .terminalLiteral:
            let productions = symbol.productions.map(\.text)
            guard !productions.isEmpty else { return nil }
            value = "**Terminal `'\(symbol.text)'`**\n\n"
                + productions.prefix(5).map { "`\($0)`" }.joined(separator: "\n")
        case .directive:
            guard let summary = symbol.directiveSummary else { return nil }
            value = "**`\(symbol.text)`** — \(summary)"
        case .comment:
            return nil
        case .punctuation:
            return nil
        }
        let start = DiagnosticsManager.position(symbol.span.start)
        let end = DiagnosticsManager.position(symbol.span.end)
        return HoverResponse(
            contents: .markupContent(MarkupContent(kind: .markdown, value: value)),
            range: start..<end
        )
    }

    // MARK: - Definition

    /// The definition of the symbol under `position` inside the grammar
    /// document at `uri`.
    public static func definitions(
        in text: String,
        at position: Position,
        grammar: ParsedGrammar,
        uri: DocumentURI
    ) -> LocationsOrLocationLinksResponse? {
        let inspector = GrammarDocumentInspector(source: text, grammar: grammar)
        guard let symbol = inspector.symbol(at: position), let range = symbol.definitionRange else {
            return nil
        }
        let start = DiagnosticsManager.position(range.start)
        let end = DiagnosticsManager.position(range.end)
        return .locations([Location(uri: uri, range: start..<end)])
    }

    /// The definition of the token under `position` in a source document: the
    /// `%token` rule for named tokens, or the first production using a literal
    /// terminal, located in the grammar document at `grammarURI`.
    public static func definitions(
        in text: String,
        at position: Position,
        compilation: GrammarCompilation,
        grammarURI: DocumentURI
    ) -> LocationsOrLocationLinksResponse? {
        guard compilation.succeeded,
              let grammar = compilation.parsedGrammar,
              let tree = compilation.parse(text).syntaxTree,
              let located = SyntaxTreeOutline(tree: tree, text: text).node(at: position)
        else {
            return nil
        }
        guard let token = located.node.token else { return nil }
        let name = token.kind
        let range: SourceRange?
        if let rule = grammar.lexerRules.first(where: { $0.token == name }) {
            range = rule.range
        } else if let production = grammar.productions.first(where: { $0.rhs.contains(name) }) {
            range = production.range
        } else {
            range = nil
        }
        guard let range else { return nil }
        let start = DiagnosticsManager.position(range.start)
        let end = DiagnosticsManager.position(range.end)
        return .locations([Location(uri: grammarURI, range: start..<end)])
    }
}

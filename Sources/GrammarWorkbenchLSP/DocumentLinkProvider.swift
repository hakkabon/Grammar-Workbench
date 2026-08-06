import Foundation
import GrammarWorkbench
import LanguageServerProtocol

/// Document links for source documents: every token links to its rule in the
/// grammar document (the `%token` rule for named tokens, the first production
/// using a literal terminal).
///
/// Grammar documents produce no links: their symbols have no external
/// targets.
public enum DocumentLinkProvider {
    /// The links for every token in `text` parsed with `compilation`, each
    /// pointing at the grammar document at `grammarURI`.
    public static func links(
        in text: String,
        compilation: GrammarCompilation,
        grammarURI: DocumentURI
    ) -> [DocumentLink] {
        guard compilation.succeeded, let grammar = compilation.parsedGrammar else { return [] }
        let result = compilation.parse(text)
        var rulesByToken: [String: SourceRange] = [:]
        for rule in grammar.lexerRules {
            guard let token = rule.token, rulesByToken[token] == nil else { continue }
            rulesByToken[token] = rule.range
        }
        var productionRangesByTerminal: [String: SourceRange] = [:]
        for production in grammar.productions {
            for symbol in production.rhs where productionRangesByTerminal[symbol] == nil {
                productionRangesByTerminal[symbol] = production.range
            }
        }
        var scanner = TokenPositionScanner(text: text)
        let walkTokens = result.tokens.allSatisfy { $0.range == nil }
        return result.tokens.compactMap { token -> DocumentLink? in
            let range = walkTokens ? scanner.consume(token.lexeme) : token.range
            let target: SourceRange?
            if let ruleRange = rulesByToken[token.kind] {
                target = ruleRange
            } else if let productionRange = productionRangesByTerminal[token.kind] {
                target = productionRange
            } else {
                target = nil
            }
            guard let range, let target else { return nil }
            return DocumentLink(
                range: DiagnosticsManager.position(range.start)..<DiagnosticsManager.position(range.end),
                target: grammarURI,
                tooltip: "Go to rule for \(token.kind)"
            )
        }
    }
}

import Foundation
import GrammarWorkbench
import LanguageServerProtocol

/// Language services for workbench-notation grammar documents: resolving the
/// symbol under the cursor (nonterminal, terminal, token name, or directive)
/// and offering completions for directives and grammar symbols.
///
/// The compiled grammar carries ranges for productions and lexer rules but not
/// for individual symbols inside production bodies, so the document is scanned
/// independently to locate spans. The scan mirrors the notation's lexing:
/// comments (`//`, `#`), directives (`%name`), terminal literals (`'...'`,
/// `"..."`), lexer patterns (`/.../`), identifiers, and punctuation.
public struct GrammarDocumentInspector {
    /// A single span in the grammar document and what it refers to.
    public struct Symbol {
        public enum Kind {
            case nonterminal
            case terminalLiteral
            case tokenName
            case directive
            case comment
            case punctuation
        }

        /// The span as it appears in the document.
        public let span: SourceRange
        public let kind: Kind
        /// The raw text of the span (without surrounding quotes).
        public let text: String

        /// Productions that define a nonterminal, or that use a terminal
        /// literal.
        public let productions: [GrammarProduction]
        /// The lexer rule for a token name.
        public let lexerRule: LexerRuleDeclaration?
        /// The explanation for a directive.
        public let directiveSummary: String?

        /// The definition target for this symbol: the defining production
        /// (for nonterminals), the lexer rule (for token names), or the first
        /// production that uses a terminal literal.
        public var definitionRange: SourceRange? {
            if let production = productions.first {
                return production.range
            }
            if let lexerRule {
                return lexerRule.range
            }
            return nil
        }

        public init(
            span: SourceRange,
            kind: Kind,
            text: String,
            productions: [GrammarProduction] = [],
            lexerRule: LexerRuleDeclaration? = nil,
            directiveSummary: String? = nil
        ) {
            self.span = span
            self.kind = kind
            self.text = text
            self.productions = productions
            self.lexerRule = lexerRule
            self.directiveSummary = directiveSummary
        }
    }

    private let source: NSString
    private let grammar: ParsedGrammar
    private let productionsByNonterminal: [String: [GrammarProduction]]
    private let productionsByTerminal: [String: [GrammarProduction]]
    private let ruleByToken: [String: LexerRuleDeclaration]
    private let spans: [Span]

    private struct Span {
        let range: SourceRange
        let text: String
        let kind: Symbol.Kind
    }

    /// Descriptions for the workbench notation's directives.
    public static let directiveSummaries: [String: String] = [
        "%start": "Declares the grammar's start symbol.",
        "%token": "Declares a named token matched by a regex pattern.",
        "%skip": "Declares a pattern that is skipped by the lexer (whitespace, comments).",
        "%mode": "Declares a lexer mode; subsequent rules belong to it.",
        "%begin": "Begins a lexer mode after a rule's pattern.",
        "%push": "Pushes a lexer mode after a rule's pattern.",
        "%pop": "Pops the current lexer mode after a rule's pattern.",
        "%left": "Declares left-associative precedence for the listed symbols.",
        "%right": "Declares right-associative precedence for the listed symbols.",
        "%nonassoc": "Declares non-associative precedence for the listed symbols.",
        "%expect": "Declares the expected number of parser conflicts.",
    ]

    public init(source: String, grammar: ParsedGrammar) {
        self.source = source as NSString
        self.grammar = grammar
        productionsByNonterminal = Dictionary(
            grouping: grammar.productions, by: \.lhs
        )
        var byTerminal: [String: [GrammarProduction]] = [:]
        for production in grammar.productions {
            for symbol in production.rhs {
                byTerminal[symbol, default: []].append(production)
            }
        }
        productionsByTerminal = byTerminal
        var byToken: [String: LexerRuleDeclaration] = [:]
        for rule in grammar.lexerRules {
            if let token = rule.token {
                byToken[token] = rule
            }
        }
        ruleByToken = byToken
        spans = Self.scan(source as NSString)
    }

    /// The symbol under `position`, or `nil` when the position is on
    /// whitespace or outside any meaningful span.
    public func symbol(at position: Position) -> Symbol? {
        let target = SourcePosition(
            offset: 0, line: position.line + 1, column: position.utf16index + 1
        )
        guard let span = spans.first(where: { contains($0.range, target) }) else { return nil }
        return resolve(span)
    }

    /// Completion candidates at `position`: directive names when the partial
    /// token starts with `%`, otherwise nonterminals and terminals.
    public func completions(at position: Position) -> [(name: String, isDirective: Bool)] {
        let word = partialWord(at: position)
        if word.text.hasPrefix("%") {
            let query = String(word.text.dropFirst()).lowercased()
            return Self.directiveSummaries.keys.sorted().compactMap { directive in
                let name = String(directive.dropFirst())
                guard query.isEmpty || name.lowercased().hasPrefix(query) else { return nil }
                return (directive, true)
            }
        }
        let query = word.text.lowercased()
        var names: Set<String> = []
        for symbol in grammar.nonterminals + grammar.terminals + grammar.tokenDeclarations.map(\.name) {
            if query.isEmpty || symbol.lowercased().hasPrefix(query) {
                names.insert(symbol)
            }
        }
        return names.sorted().map { ($0, false) }
    }

    /// The range of the partial word at `position` (used for the completion
    /// text edit), or the position itself when it sits on whitespace.
    public func partialWordRange(at position: Position) -> Range<Position> {
        let span = partialWord(at: position)
        let start = DiagnosticsManager.position(span.range.start)
        let end = DiagnosticsManager.position(span.range.end)
        return start..<end
    }

    // MARK: - Resolution

    private func resolve(_ span: Span) -> Symbol {
        switch span.kind {
        case .directive:
            return Symbol(
                span: span.range,
                kind: .directive,
                text: span.text,
                directiveSummary: Self.directiveSummaries[span.text]
                    ?? "Unknown directive."
            )
        case .comment, .punctuation:
            return Symbol(span: span.range, kind: span.kind, text: span.text)
        case .terminalLiteral:
            return Symbol(
                span: span.range,
                kind: .terminalLiteral,
                text: span.text,
                productions: productionsByTerminal[span.text] ?? []
            )
        case .nonterminal:
            // A bare identifier is a token name when a lexer rule declares it,
            // otherwise a nonterminal.
            if let rule = ruleByToken[span.text] {
                return Symbol(
                    span: span.range,
                    kind: .tokenName,
                    text: span.text,
                    lexerRule: rule
                )
            }
            return Symbol(
                span: span.range,
                kind: .nonterminal,
                text: span.text,
                productions: productionsByNonterminal[span.text] ?? []
            )
        case .tokenName:
            return Symbol(
                span: span.range,
                kind: .tokenName,
                text: span.text,
                lexerRule: ruleByToken[span.text]
            )
        }
    }

    /// The identifier or directive token at (or immediately before) the cursor,
    /// used to scope completions.
    private func partialWord(at position: Position) -> (text: String, range: SourceRange) {
        let target = SourcePosition(
            offset: 0, line: position.line + 1, column: position.utf16index + 1
        )
        if let span = spans.first(where: {
            ($0.kind == .directive || $0.kind == .nonterminal || $0.kind == .tokenName)
                && contains($0.range, target)
        }) {
            return (span.text, span.range)
        }
        // Not on a word; grow a word from the cursor position.
        let index = utf16Offset(of: position)
        var begin = index
        var end = index
        while begin > 0, isWordCharacter(source.character(at: begin - 1)) {
            begin -= 1
        }
        while end < source.length, isWordCharacter(source.character(at: end)) {
            end += 1
        }
        let nsRange = NSRange(location: begin, length: end - begin)
        let text = nsRange.location == NSNotFound ? "" : source.substring(with: nsRange)
        return (text, sourceRange(of: nsRange))
    }

    private func utf16Offset(of position: Position) -> Int {
        var offset = 0
        var line = 0
        while line < position.line {
            guard offset < source.length else { break }
            offset = NSMaxRange(source.lineRange(for: NSRange(location: offset, length: 0)))
            line += 1
        }
        return min(offset + position.utf16index, source.length)
    }

    private func isWordCharacter(_ character: unichar) -> Bool {
        switch character {
        case 0x25: return true // %
        default:
            guard let scalar = UnicodeScalar(character) else { return false }
            let char = Character(scalar)
            return char.isLetter || char.isNumber || character == 0x5F // _
        }
    }

    private func sourceRange(of nsRange: NSRange) -> SourceRange {
        Self.engineRange(of: nsRange, in: source)
    }

    // MARK: - Scanning

    /// Scans the document into spans using the notation's token shapes.
    /// Bare identifiers are classified as nonterminals here; whether one is a
    /// token name is decided during resolution using the compiled grammar.
    private static func scan(_ source: NSString) -> [Span] {
        let pattern = #"(//[^\n]*|#[^\n]*|%[A-Za-z]+|'(?:\\.|[^'])*'|"(?:\\.|[^"])*"|/[^/\s]+/|[A-Za-z_][A-Za-z0-9_′]*|[:|;=\[\]{}()])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        var spans: [Span] = []
        let matches = expression.matches(in: source as String, range: NSRange(location: 0, length: source.length))
        for match in matches {
            let nsRange = match.range
            let text = source.substring(with: nsRange)
            let kind: Symbol.Kind
            if text.hasPrefix("//") || text.hasPrefix("#") || text.hasPrefix("/") {
                kind = .comment
            } else if text.hasPrefix("%") {
                kind = .directive
            } else if text.hasPrefix("'") || text.hasPrefix("\"") {
                kind = .terminalLiteral
            } else if text.rangeOfCharacter(from: .alphanumerics) != nil {
                kind = .nonterminal
            } else {
                kind = .punctuation
            }
            spans.append(Span(
                range: engineRange(of: nsRange, in: source),
                text: text,
                kind: kind
            ))
        }
        return spans
    }

    private static func engineRange(of nsRange: NSRange, in source: NSString) -> SourceRange {
        var line = 0
        var lineStart = 0
        var index = 0
        while index < nsRange.location {
            if source.character(at: index) == 0x0A {
                line += 1
                lineStart = index + 1
            }
            index += 1
        }
        let start = SourcePosition(
            offset: nsRange.location, line: line + 1, column: nsRange.location - lineStart + 1
        )
        var endLine = line
        var endLineStart = lineStart
        index = nsRange.location
        while index < nsRange.location + nsRange.length {
            if source.character(at: index) == 0x0A {
                endLine += 1
                endLineStart = index + 1
            }
            index += 1
        }
        let end = SourcePosition(
            offset: nsRange.location + nsRange.length,
            line: endLine + 1,
            column: nsRange.location + nsRange.length - endLineStart + 1
        )
        return SourceRange(start: start, end: end)
    }

    private func contains(_ range: SourceRange, _ position: SourcePosition) -> Bool {
        if range.start == range.end { return position == range.start }
        return (range.start.line < position.line
            || (range.start.line == position.line && range.start.column <= position.column))
            && (range.end.line > position.line
            || (range.end.line == position.line && range.end.column > position.column))
    }
}

import Foundation
import Grammar

public struct GrammarLoweringSnapshot: Hashable, Codable, Sendable {
    public let notation: GrammarSourceNotation
    public let loweredSource: String
    public let syntheticNonterminals: [String]
}

enum EBNFGrammarAdapter {
    struct Result: Sendable {
        let frontEnd: GrammarFrontEndResult
        let lowering: GrammarLoweringSnapshot?
    }

    static func process(_ source: String) -> GrammarFrontEndResult {
        lower(source).frontEnd
    }

    static func lower(_ source: String) -> Result {
        let parser = GrammarParser(grammar: source)
        let syntax = parser.parse()
        guard parser.diagnostics.isEmpty else {
            let diagnostics = parser.diagnostics.enumerated().map { index, diagnostic in
                grammarDiagnostic(index: index, description: diagnostic.description, source: source)
            }
            return .init(
                frontEnd: .init(source: source, grammar: nil, analysis: nil, diagnostics: diagnostics, lexerAnalysis: nil),
                lowering: nil
            )
        }

        let converted = StandardNotation().rewriteToStandardNotation(syntax: syntax)
        guard !converted.0.isEmpty else {
            let position = SourcePosition(offset: 0, line: 1, column: 1)
            let diagnostic = GrammarDiagnostic(
                id: 0, severity: .error, code: "empty-ebnf",
                message: "An EBNF grammar must contain at least one production.",
                range: .init(start: position, end: position)
            )
            return .init(
                frontEnd: .init(source: source, grammar: nil, analysis: nil, diagnostics: [diagnostic], lexerAnalysis: nil),
                lowering: nil
            )
        }

        let originalGoals = originalProductionGoals(in: syntax)
        let generated = converted.1.map { $0.name }.sorted()
        var canonicalNames: [String: String] = [:]
        for production in converted.0 {
            let names = [production.goal.name] + production.generatedNonTerminals.map { $0.name }
            for name in names where generated.contains(name) && canonicalNames[name] == nil {
                canonicalNames[name] = "__ebnf_\(canonicalNames.count + 1)"
            }
        }
        func canonical(_ name: String) -> String { canonicalNames[name] ?? name }

        let lexicalNames = converted.4.keys.sorted()
        var lines = ["%start \(canonical(converted.2.isEmpty ? (originalGoals.first ?? converted.0[0].goal.name) : converted.2))"]
        for name in lexicalNames {
            guard let terminal = converted.4[name], let pattern = regexPattern(for: terminal) else { continue }
            lines.append("%token \(name) /\(escapePatternDelimiter(pattern))/")
        }
        if !lexicalNames.isEmpty { lines.append("%skip /\\s+/") }
        lines.append("")

        for production in converted.0 {
            let rhs = production.rule.compactMap { symbol -> String? in
                switch symbol {
                case .nonTerminal(let value): return canonical(value.name)
                case .terminal(let terminal):
                    if let name = lexicalNames.first(where: { converted.4[$0] == terminal }) { return name }
                    return literal(for: terminal)
                case .metaSymbol: return nil
                }
            }.joined(separator: " ")
            lines.append("\(canonical(production.goal.name)) : \(rhs) ;")
        }

        let lowered = lines.joined(separator: "\n")
        let frontEnd = GrammarFrontEnd.process(lowered)
        return .init(
            frontEnd: frontEnd,
            lowering: .init(
                notation: .ebnf,
                loweredSource: lowered,
                syntheticNonterminals: canonicalNames.values.sorted()
            )
        )
    }

    private static func originalProductionGoals(in syntax: BnfExpression) -> [String] {
        guard case .syntax(let expressions) = syntax else { return [] }
        return expressions.compactMap {
            if case .production(let goal, _) = $0 { return goal }
            return nil
        }
    }

    private static func regexPattern(for terminal: Terminal) -> String? {
        switch terminal {
        case .regularExpression(let expression): return expression.pattern
        case .characterRange(let range):
            return "[\(NSRegularExpression.escapedPattern(for: String(range.lowerBound)))-\(NSRegularExpression.escapedPattern(for: String(range.upperBound)))]"
        case .stringList(let values):
            return "(?:\(values.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")))"
        case .string(let value): return NSRegularExpression.escapedPattern(for: value)
        case .meta: return nil
        }
    }

    private static func literal(for terminal: Terminal) -> String? {
        switch terminal {
        case .string(let value): return "'\(value.replacingOccurrences(of: "'", with: "\\'"))'"
        case .meta(let value) where value == .eps || value == .lambda || value == .empty: return nil
        default: return nil
        }
    }

    private static func escapePatternDelimiter(_ pattern: String) -> String {
        pattern.replacingOccurrences(of: "/", with: "\\/")
    }

    private static func grammarDiagnostic(index: Int, description: String, source: String) -> GrammarDiagnostic {
        let expression = try? NSRegularExpression(pattern: #"^\[(\d+):(\d+)\] Error: (.*)$"#)
        let match = expression?.firstMatch(in: description, range: NSRange(description.startIndex..., in: description))
        let values = (description as NSString)
        let line = match.map { Int(values.substring(with: $0.range(at: 1))) ?? 1 } ?? 1
        let column = match.map { Int(values.substring(with: $0.range(at: 2))) ?? 1 } ?? 1
        let message = match.map { values.substring(with: $0.range(at: 3)) } ?? description
        let position = position(line: line, column: column, in: source)
        return .init(
            id: index, severity: .error, code: "invalid-ebnf", message: message,
            range: .init(start: position, end: position)
        )
    }

    private static func position(line: Int, column: Int, in source: String) -> SourcePosition {
        var currentLine = 1
        var currentColumn = 1
        var offset = 0
        for character in source {
            if currentLine == line && currentColumn == column { break }
            offset += 1
            if character == "\n" { currentLine += 1; currentColumn = 1 } else { currentColumn += 1 }
        }
        return .init(offset: offset, line: currentLine, column: currentColumn)
    }
}

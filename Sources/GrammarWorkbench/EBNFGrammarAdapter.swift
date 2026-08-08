import Foundation
import Grammar

public struct GrammarLoweringSnapshot: Hashable, Codable, Sendable {
    public let notation: GrammarSourceNotation
    public let loweredSource: String
    public let syntheticNonterminals: [String]
    public let productionOrigins: [GrammarLoweredProductionOrigin]

    private enum CodingKeys: String, CodingKey {
        case notation, loweredSource, syntheticNonterminals, productionOrigins
    }

    public init(
        notation: GrammarSourceNotation, loweredSource: String,
        syntheticNonterminals: [String], productionOrigins: [GrammarLoweredProductionOrigin] = []
    ) {
        self.notation = notation
        self.loweredSource = loweredSource
        self.syntheticNonterminals = syntheticNonterminals
        self.productionOrigins = productionOrigins
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        notation = try values.decode(GrammarSourceNotation.self, forKey: .notation)
        loweredSource = try values.decode(String.self, forKey: .loweredSource)
        syntheticNonterminals = try values.decode([String].self, forKey: .syntheticNonterminals)
        productionOrigins = try values.decodeIfPresent(
            [GrammarLoweredProductionOrigin].self, forKey: .productionOrigins
        ) ?? []
    }
}

/// Connects a lowered BNF production identity to the EBNF declaration that
/// produced it. IDs match `GrammarSemanticModel` and parser reduction nodes.
public struct GrammarLoweredProductionOrigin: Hashable, Codable, Sendable {
    public let productionID: Int
    public let loweredNonterminal: String
    public let sourceNonterminal: String
    public let sourceRange: SourceRange
    public let isSynthetic: Bool
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
        let sourceIndex = EBNFSourceIndex(source: source)
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
        let fallbackRange = sourceIndex.range(for: originalGoals.first ?? "") ?? .zero
        let graph = Dictionary(grouping: converted.0, by: { $0.goal.name }).mapValues {
            Set($0.flatMap { $0.generatedNonTerminals.map(\.name) })
        }
        func sourceGoal(for loweredGoal: String) -> String {
            if originalGoals.contains(loweredGoal) { return loweredGoal }
            func reaches(_ target: String, from current: String, visited: inout Set<String>) -> Bool {
                guard visited.insert(current).inserted else { return false }
                if graph[current, default: []].contains(target) { return true }
                return graph[current, default: []].contains { reaches(target, from: $0, visited: &visited) }
            }
            return originalGoals.first { goal in
                var visited: Set<String> = []
                return reaches(loweredGoal, from: goal, visited: &visited)
            } ?? originalGoals.first ?? loweredGoal
        }

        var lines: [String] = []
        var lineOrigins: [SourceRange] = []
        func append(_ line: String, origin: SourceRange) {
            lines.append(line); lineOrigins.append(origin)
        }
        let startName = converted.2.isEmpty ? (originalGoals.first ?? converted.0[0].goal.name) : converted.2
        append("%start \(canonical(startName))", origin: sourceIndex.range(for: startName) ?? fallbackRange)
        for name in lexicalNames {
            guard let terminal = converted.4[name], let pattern = regexPattern(for: terminal) else { continue }
            append("%token \(name) /\(escapePatternDelimiter(pattern))/", origin: sourceIndex.range(for: name) ?? fallbackRange)
        }
        if !lexicalNames.isEmpty { append("%skip /\\s+/", origin: sourceIndex.lexicalBlockRange ?? fallbackRange) }
        append("", origin: fallbackRange)

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
            let sourceGoal = sourceGoal(for: production.goal.name)
            append("\(canonical(production.goal.name)) : \(rhs) ;", origin: sourceIndex.range(for: sourceGoal) ?? fallbackRange)
        }

        let lowered = lines.joined(separator: "\n")
        let compiled = GrammarFrontEnd.process(lowered)
        let nativeDiagnostics = ebnfSemanticDiagnostics(
            syntax: syntax, originalGoals: originalGoals, lexicalNames: Set(lexicalNames),
            sourceIndex: sourceIndex, startingAt: compiled.diagnostics.count
        )
        let displayNames = Dictionary(uniqueKeysWithValues: canonicalNames.map { original, lowered in
            (lowered, sourceGoal(for: original))
        })
        let frontEnd = remap(
            compiled, source: source, lineOrigins: lineOrigins,
            syntheticDisplayNames: displayNames, additionalDiagnostics: nativeDiagnostics
        )
        let origins = (frontEnd.grammar?.productions ?? []).map { production in
            let loweredName = production.lhs
            let originalName = sourceGoal(for: canonicalNames.first(where: { $0.value == loweredName })?.key ?? loweredName)
            return GrammarLoweredProductionOrigin(
                productionID: production.id + 1, loweredNonterminal: loweredName,
                sourceNonterminal: originalName, sourceRange: production.range,
                isSynthetic: loweredName.hasPrefix("__ebnf_")
            )
        }
        return .init(
            frontEnd: frontEnd,
            lowering: .init(
                notation: .ebnf,
                loweredSource: lowered,
                syntheticNonterminals: canonicalNames.values.sorted(),
                productionOrigins: origins
            )
        )
    }

    private static func remap(
        _ result: GrammarFrontEndResult, source: String, lineOrigins: [SourceRange],
        syntheticDisplayNames: [String: String],
        additionalDiagnostics: [GrammarDiagnostic]
    ) -> GrammarFrontEndResult {
        func origin(_ range: SourceRange) -> SourceRange {
            lineOrigins.indices.contains(range.start.line - 1) ? lineOrigins[range.start.line - 1] : .zero
        }
        let grammar = result.grammar.map { grammar in
            ParsedGrammar(
                startSymbol: grammar.startSymbol, nonterminals: grammar.nonterminals,
                terminals: grammar.terminals,
                productions: grammar.productions.map { .init(id: $0.id, lhs: $0.lhs, rhs: $0.rhs, range: origin($0.range)) },
                precedence: grammar.precedence,
                tokenDeclarations: grammar.tokenDeclarations.map { .init(id: $0.id, name: $0.name, range: origin($0.range)) },
                lexerRules: grammar.lexerRules.map {
                    .init(id: $0.id, token: $0.token, pattern: $0.pattern, mode: $0.mode, action: $0.action, range: origin($0.range))
                },
                lexerModes: grammar.lexerModes, undeclaredSymbols: grammar.undeclaredSymbols,
                conflictExpectation: grammar.conflictExpectation
            )
        }
        let diagnostics = result.diagnostics.map {
            var message = $0.message
            for (synthetic, original) in syntheticDisplayNames {
                message = message.replacingOccurrences(
                    of: "‘\(synthetic)’", with: "generated EBNF construct in ‘\(original)’"
                ).replacingOccurrences(of: synthetic, with: original)
            }
            return GrammarDiagnostic(
                id: $0.id, severity: $0.severity, code: $0.code,
                message: message, range: origin($0.range)
            )
        } + additionalDiagnostics
        return .init(source: source, grammar: grammar, analysis: result.analysis,
                     diagnostics: diagnostics, lexerAnalysis: result.lexerAnalysis)
    }

    private static func ebnfSemanticDiagnostics(
        syntax: BnfExpression, originalGoals: [String], lexicalNames: Set<String>,
        sourceIndex: EBNFSourceIndex, startingAt firstID: Int
    ) -> [GrammarDiagnostic] {
        var references: [String] = []
        func visit(_ expression: BnfExpression) {
            switch expression {
            case .syntax(let values), .sequence(let values), .alternative(let values): values.forEach(visit)
            case .production(_, let value), .optional(let value), .repetition(let value),
                 .repetitionOnePlus(let value), .grouping(let value): visit(value)
            case .nonterminal(let name): references.append(name)
            default: break
            }
        }
        visit(syntax)
        let defined = Set(originalGoals).union(lexicalNames)
        var diagnostics: [GrammarDiagnostic] = []
        for name in Set(references).subtracting(defined).sorted() {
            diagnostics.append(.init(
                id: firstID + diagnostics.count, severity: .error, code: "undefined-ebnf-symbol",
                message: "EBNF nonterminal ‘\(name)’ has no production.",
                range: sourceIndex.referenceRange(for: name) ?? .zero
            ))
        }
        for (name, count) in Dictionary(grouping: originalGoals, by: { $0 }).mapValues(\.count)
            .filter({ $0.value > 1 }).sorted(by: { $0.key < $1.key }) {
            diagnostics.append(.init(
                id: firstID + diagnostics.count, severity: .warning, code: "duplicate-ebnf-production",
                message: "EBNF nonterminal ‘\(name)’ is declared \(count) times; combine its alternatives into one production.",
                range: sourceIndex.range(for: name) ?? .zero
            ))
        }
        return diagnostics
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

private struct EBNFSourceIndex {
    let source: String
    let declarations: [String: [SourceRange]]
    let lexicalBlockRange: SourceRange?

    init(source: String) {
        self.source = source
        let expression = try? NSRegularExpression(
            pattern: #"(?m)^[ \t]*([A-Za-z_][A-Za-z0-9_′]*)[ \t]*="#
        )
        var declarations: [String: [SourceRange]] = [:]
        for match in expression?.matches(in: source, range: NSRange(source.startIndex..., in: source)) ?? [] {
            guard let range = Range(match.range(at: 1), in: source) else { continue }
            declarations[String(source[range]), default: []].append(Self.sourceRange(range, in: source))
        }
        self.declarations = declarations
        if let expression = try? NSRegularExpression(pattern: #"\blexical\b"#),
           let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
           let range = Range(match.range, in: source) {
            lexicalBlockRange = Self.sourceRange(range, in: source)
        } else {
            lexicalBlockRange = nil
        }
    }

    func range(for declaration: String) -> SourceRange? {
        declarations[declaration]?.first
    }

    func referenceRange(for name: String) -> SourceRange? {
        guard let expression = try? NSRegularExpression(
            pattern: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b"
        ) else { return nil }
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        let declarationRanges = Set(declarations[name, default: []].map { $0.start.offset..<$0.end.offset })
        for match in matches {
            guard let range = Range(match.range, in: source) else { continue }
            let located = Self.sourceRange(range, in: source)
            if !declarationRanges.contains(located.start.offset..<located.end.offset) { return located }
        }
        return nil
    }

    private static func sourceRange(_ range: Range<String.Index>, in source: String) -> SourceRange {
        .init(start: position(range.lowerBound, in: source), end: position(range.upperBound, in: source))
    }

    private static func position(_ index: String.Index, in source: String) -> SourcePosition {
        let prefix = source[..<index]
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        return .init(offset: prefix.count, line: lines.count, column: (lines.last?.count ?? 0) + 1)
    }
}

private extension SourceRange {
    static var zero: Self {
        let position = SourcePosition(offset: 0, line: 1, column: 1)
        return .init(start: position, end: position)
    }
}

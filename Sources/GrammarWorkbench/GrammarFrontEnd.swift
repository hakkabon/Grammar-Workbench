import Foundation

public struct SourcePosition: Hashable, Codable, Sendable {
    public let offset: Int
    public let line: Int
    public let column: Int

    public init(offset: Int, line: Int, column: Int) {
        self.offset = offset
        self.line = line
        self.column = column
    }
}

public struct SourceRange: Hashable, Codable, Sendable {
    public let start: SourcePosition
    public let end: SourcePosition

    public init(start: SourcePosition, end: SourcePosition) {
        self.start = start
        self.end = end
    }
}

public struct GrammarDiagnostic: Identifiable, Hashable, Codable, Sendable {
    public enum Severity: String, Codable, Sendable {
        case error
        case warning
    }

    public let id: Int
    public let severity: Severity
    public let code: String
    public let message: String
    public let range: SourceRange

    public init(id: Int, severity: Severity, code: String = "syntax", message: String, range: SourceRange) {
        self.id = id
        self.severity = severity
        self.code = code
        self.message = message
        self.range = range
    }
}

public enum Associativity: String, Codable, Sendable {
    case left
    case right
    case nonassociative
}

public struct PrecedenceDeclaration: Hashable, Codable, Sendable {
    public let associativity: Associativity
    public let symbols: [String]
    public let level: Int
    public let range: SourceRange
}

public struct GrammarProduction: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let lhs: String
    public let rhs: [String]
    public let range: SourceRange

    public var text: String {
        "\(lhs) → \(rhs.isEmpty ? "ε" : rhs.joined(separator: " "))"
    }
}

public struct TokenDeclaration: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let name: String
    public let range: SourceRange
}

public struct GrammarSymbolReference: Hashable, Codable, Sendable {
    public let name: String
    public let range: SourceRange
}

public struct ConflictExpectationDeclaration: Hashable, Codable, Sendable {
    public let count: Int
    public let range: SourceRange
}

public struct ParsedGrammar: Hashable, Codable, Sendable {
    public let startSymbol: String
    public let nonterminals: [String]
    public let terminals: [String]
    public let productions: [GrammarProduction]
    public let precedence: [PrecedenceDeclaration]
    public let tokenDeclarations: [TokenDeclaration]
    public let undeclaredSymbols: [GrammarSymbolReference]
    public let conflictExpectation: ConflictExpectationDeclaration?

    public var usesExplicitTokens: Bool { !tokenDeclarations.isEmpty }
}

public struct GrammarAnalysis: Hashable, Codable, Sendable {
    public let nullable: Set<String>
    public let first: [String: Set<String>]
    public let follow: [String: Set<String>]
}

public struct GrammarFrontEndResult: Sendable {
    public let source: String
    public let grammar: ParsedGrammar?
    public let analysis: GrammarAnalysis?
    public let diagnostics: [GrammarDiagnostic]

    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}

public enum GrammarFrontEnd {
    public static func process(_ source: String) -> GrammarFrontEndResult {
        let lexed = GrammarLexer(source: source).scan()
        var parser = GrammarParser(tokens: lexed.tokens, diagnostics: lexed.diagnostics)
        let parsed = parser.parse()
        let syntacticallyValidGrammar = parser.diagnostics.contains { $0.severity == .error } ? nil : parsed
        let analysis = syntacticallyValidGrammar.map(GrammarAnalyzer.analyze)
        let semanticDiagnostics = syntacticallyValidGrammar.map {
            GrammarValidator.validate($0, startingAt: parser.diagnostics.count)
        } ?? []
        return GrammarFrontEndResult(
            source: source,
            grammar: syntacticallyValidGrammar,
            analysis: analysis,
            diagnostics: parser.diagnostics + semanticDiagnostics
        )
    }
}

private enum GrammarValidator {
    static func validate(_ grammar: ParsedGrammar, startingAt firstID: Int) -> [GrammarDiagnostic] {
        var diagnostics: [GrammarDiagnostic] = []
        let nonterminals = Set(grammar.nonterminals)
        let productionsByLHS = Dictionary(grouping: grammar.productions, by: \.lhs)

        var reachable: Set<String> = [grammar.startSymbol]
        var changed = true
        while changed {
            changed = false
            for symbol in reachable {
                for production in productionsByLHS[symbol, default: []] {
                    for referenced in production.rhs where nonterminals.contains(referenced) {
                        changed = reachable.insert(referenced).inserted || changed
                    }
                }
            }
        }
        for symbol in grammar.nonterminals where !reachable.contains(symbol) {
            if let range = productionsByLHS[symbol]?.first?.range {
                append(.warning, "unreachable-nonterminal", "Nonterminal ‘\(symbol)’ is unreachable from the start symbol.", range, to: &diagnostics, firstID: firstID)
            }
        }

        var productive: Set<String> = []
        changed = true
        while changed {
            changed = false
            for production in grammar.productions
            where production.rhs.allSatisfy({ !nonterminals.contains($0) || productive.contains($0) }) {
                changed = productive.insert(production.lhs).inserted || changed
            }
        }
        for symbol in grammar.nonterminals where !productive.contains(symbol) {
            if let range = productionsByLHS[symbol]?.first?.range {
                append(.warning, "unproductive-nonterminal", "Nonterminal ‘\(symbol)’ cannot derive a terminal string.", range, to: &diagnostics, firstID: firstID)
            }
        }

        var seenProductions: Set<String> = []
        for production in grammar.productions {
            let key = "\(production.lhs)\u{0}\(production.rhs.joined(separator: "\u{0}"))"
            if !seenProductions.insert(key).inserted {
                append(.warning, "duplicate-production", "Duplicate production ‘\(production.text)’.", production.range, to: &diagnostics, firstID: firstID)
            }
        }

        let usedSymbols = Set(grammar.productions.flatMap(\.rhs))
        let declaredTokens = Set(grammar.tokenDeclarations.map(\.name))
        for reference in grammar.undeclaredSymbols {
            append(.error, "undefined-symbol", "Symbol ‘\(reference.name)’ is neither a nonterminal nor declared with %token.", reference.range, to: &diagnostics, firstID: firstID)
        }
        var seenTokens: Set<String> = []
        for declaration in grammar.tokenDeclarations {
            if declaration.name.isEmpty {
                append(.error, "empty-terminal", "Token names cannot be empty.", declaration.range, to: &diagnostics, firstID: firstID)
            }
            if declaration.name == "$" {
                append(.warning, "reserved-symbol", "‘$’ is reserved for end-of-input.", declaration.range, to: &diagnostics, firstID: firstID)
            }
            if !seenTokens.insert(declaration.name).inserted {
                append(.warning, "duplicate-token", "Token ‘\(declaration.name)’ is declared more than once.", declaration.range, to: &diagnostics, firstID: firstID)
            }
            if nonterminals.contains(declaration.name) {
                append(.error, "symbol-collision", "Symbol ‘\(declaration.name)’ is declared as both a token and a nonterminal.", declaration.range, to: &diagnostics, firstID: firstID)
            } else if !usedSymbols.contains(declaration.name) {
                append(.warning, "unused-token", "Declared token ‘\(declaration.name)’ is never used.", declaration.range, to: &diagnostics, firstID: firstID)
            }
        }

        var precedenceOwners: [String: PrecedenceDeclaration] = [:]
        for declaration in grammar.precedence {
            for symbol in declaration.symbols {
                if precedenceOwners.updateValue(declaration, forKey: symbol) != nil {
                    append(.warning, "duplicate-precedence", "Precedence for ‘\(symbol)’ is declared more than once.", declaration.range, to: &diagnostics, firstID: firstID)
                }
                if !usedSymbols.contains(symbol) {
                    append(.warning, "unused-precedence", "Precedence symbol ‘\(symbol)’ is never used in a production.", declaration.range, to: &diagnostics, firstID: firstID)
                }
                if grammar.usesExplicitTokens && !declaredTokens.contains(symbol) && !grammar.terminals.contains(symbol) {
                    append(.error, "invalid-precedence-symbol", "Precedence symbol ‘\(symbol)’ is not a declared terminal.", declaration.range, to: &diagnostics, firstID: firstID)
                }
            }
        }
        if grammar.terminals.contains("$"),
           let production = grammar.productions.first(where: { $0.rhs.contains("$") }) {
            append(.warning, "reserved-symbol", "‘$’ is reserved for end-of-input.", production.range, to: &diagnostics, firstID: firstID)
        }
        if grammar.terminals.contains(""),
           let production = grammar.productions.first(where: { $0.rhs.contains("") }) {
            append(.error, "empty-terminal", "Terminal literals cannot be empty; use an empty alternative for ε.", production.range, to: &diagnostics, firstID: firstID)
        }

        let nullable = nullableSymbols(grammar)
        let nullableGraph = nullableDependencyGraph(grammar, nullable: nullable)
        for symbol in grammar.nonterminals where participatesInCycle(symbol, graph: nullableGraph) {
            if let range = productionsByLHS[symbol]?.first?.range {
                append(.warning, "nullable-cycle", "Nonterminal ‘\(symbol)’ participates in a nullable cycle.", range, to: &diagnostics, firstID: firstID)
            }
        }
        return diagnostics
    }

    private static func nullableSymbols(_ grammar: ParsedGrammar) -> Set<String> {
        let nonterminals = Set(grammar.nonterminals)
        var nullable: Set<String> = []
        var changed = true
        while changed {
            changed = false
            for production in grammar.productions
            where production.rhs.allSatisfy({ nonterminals.contains($0) && nullable.contains($0) }) {
                changed = nullable.insert(production.lhs).inserted || changed
            }
        }
        return nullable
    }

    private static func nullableDependencyGraph(
        _ grammar: ParsedGrammar,
        nullable: Set<String>
    ) -> [String: Set<String>] {
        let nonterminals = Set(grammar.nonterminals)
        var graph: [String: Set<String>] = [:]
        for production in grammar.productions
        where !production.rhs.isEmpty
            && production.rhs.allSatisfy({ nonterminals.contains($0) && nullable.contains($0) }) {
            graph[production.lhs, default: []].formUnion(production.rhs)
        }
        return graph
    }

    private static func participatesInCycle(_ origin: String, graph: [String: Set<String>]) -> Bool {
        var pending = Array(graph[origin, default: []])
        var visited: Set<String> = []
        while let symbol = pending.popLast() {
            if symbol == origin { return true }
            if visited.insert(symbol).inserted {
                pending.append(contentsOf: graph[symbol, default: []])
            }
        }
        return false
    }

    private static func append(
        _ severity: GrammarDiagnostic.Severity,
        _ code: String,
        _ message: String,
        _ range: SourceRange,
        to diagnostics: inout [GrammarDiagnostic],
        firstID: Int
    ) {
        diagnostics.append(.init(
            id: firstID + diagnostics.count,
            severity: severity,
            code: code,
            message: message,
            range: range
        ))
    }
}

private struct GrammarToken {
    enum Kind: Equatable {
        case identifier(String)
        case terminal(String)
        case directive(String)
        case colon
        case pipe
        case semicolon
        case newline
        case eof
    }

    let kind: Kind
    let range: SourceRange
}

private struct GrammarLexer {
    let source: String

    func scan() -> (tokens: [GrammarToken], diagnostics: [GrammarDiagnostic]) {
        let characters = Array(source)
        var index = 0
        var line = 1
        var column = 1
        var tokens: [GrammarToken] = []
        var diagnostics: [GrammarDiagnostic] = []

        func position() -> SourcePosition {
            SourcePosition(offset: index, line: line, column: column)
        }
        func range(from start: SourcePosition) -> SourceRange {
            SourceRange(start: start, end: position())
        }
        func isIdentifierCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "′"
        }
        func peek(_ distance: Int = 0) -> Character? {
            let target = index + distance
            return characters.indices.contains(target) ? characters[target] : nil
        }
        func advance() {
            guard index < characters.count else { return }
            if characters[index] == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
            index += 1
        }

        while index < characters.count {
            let start = position()
            guard let character = peek() else { break }
            if character == " " || character == "\t" || character == "\r" {
                advance()
            } else if character == "\n" {
                advance()
                tokens.append(GrammarToken(kind: .newline, range: range(from: start)))
            } else if character == "#"
                        || (character == "/" && peek(1) == "/") {
                while let current = peek(), current != "\n" { advance() }
            } else if character == ":" {
                advance(); tokens.append(.init(kind: .colon, range: range(from: start)))
            } else if character == "|" {
                advance(); tokens.append(.init(kind: .pipe, range: range(from: start)))
            } else if character == ";" {
                advance(); tokens.append(.init(kind: .semicolon, range: range(from: start)))
            } else if character == "%" {
                advance()
                var value = ""
                while let current = peek(), current.isLetter {
                    value.append(current); advance()
                }
                if value.isEmpty {
                    diagnostics.append(.init(id: diagnostics.count, severity: .error, message: "Expected a directive name after ‘%’.", range: range(from: start)))
                } else {
                    tokens.append(.init(kind: .directive(value), range: range(from: start)))
                }
            } else if character == "'" || character == "\"" {
                let quote = character
                advance()
                var value = ""
                var terminated = false
                while let current = peek() {
                    if current == quote {
                        advance()
                        terminated = true
                        break
                    }
                    if current == "\n" { break }
                    if current == "\\", let escaped = peek(1) {
                        advance()
                        value.append(escaped)
                        advance()
                    } else {
                        value.append(current)
                        advance()
                    }
                }
                if terminated {
                    tokens.append(.init(kind: .terminal(value), range: range(from: start)))
                } else {
                    diagnostics.append(.init(id: diagnostics.count, severity: .error, message: "Unterminated terminal literal.", range: range(from: start)))
                }
            } else if isIdentifierCharacter(character) {
                var value = ""
                while let current = peek(), isIdentifierCharacter(current) {
                    value.append(current); advance()
                }
                tokens.append(.init(kind: .identifier(value), range: range(from: start)))
            } else {
                advance()
                diagnostics.append(.init(id: diagnostics.count, severity: .error, message: "Unexpected character ‘\(character)’.", range: range(from: start)))
            }
        }
        let end = position()
        tokens.append(.init(kind: .eof, range: .init(start: end, end: end)))
        return (tokens, diagnostics)
    }
}

private struct GrammarParser {
    let tokens: [GrammarToken]
    var diagnostics: [GrammarDiagnostic]
    private var index = 0
    private var requestedStart: String?
    private var precedence: [PrecedenceDeclaration] = []
    private var tokenDeclarations: [TokenDeclaration] = []
    private var conflictExpectation: ConflictExpectationDeclaration?
    private var drafts: [(lhs: String, rhs: [(name: String, explicitTerminal: Bool, range: SourceRange)], range: SourceRange)] = []

    init(tokens: [GrammarToken], diagnostics: [GrammarDiagnostic]) {
        self.tokens = tokens
        self.diagnostics = diagnostics
    }

    mutating func parse() -> ParsedGrammar? {
        skipNewlines()
        while !isEOF {
            if case .directive = current.kind {
                parseDirective()
            } else {
                parseRule()
            }
            skipNewlines()
        }

        guard !drafts.isEmpty else {
            report("A grammar must contain at least one production.", at: current.range)
            return nil
        }
        let nonterminals = unique(drafts.map(\.lhs))
        let nonterminalSet = Set(nonterminals)
        let explicitTerminals = drafts.flatMap(\.rhs).filter(\.explicitTerminal).map(\.name)
        let inferredTerminals = drafts.flatMap(\.rhs).filter {
            !$0.explicitTerminal && !nonterminalSet.contains($0.name)
        }
        let terminals = tokenDeclarations.isEmpty
            ? unique(explicitTerminals + inferredTerminals.map(\.name))
            : unique(tokenDeclarations.map(\.name) + explicitTerminals)
        let undeclaredSymbols = tokenDeclarations.isEmpty ? [] : inferredTerminals.map {
            GrammarSymbolReference(name: $0.name, range: $0.range)
        }.filter { reference in
            !tokenDeclarations.contains { $0.name == reference.name }
        }
        let start = requestedStart ?? nonterminals[0]
        if !nonterminalSet.contains(start) {
            report("Start symbol ‘\(start)’ has no production.", at: tokens.first?.range ?? current.range)
        }
        let productions = drafts.enumerated().map {
            GrammarProduction(id: $0.offset, lhs: $0.element.lhs, rhs: $0.element.rhs.map(\.name), range: $0.element.range)
        }
        return ParsedGrammar(
            startSymbol: start,
            nonterminals: nonterminals,
            terminals: terminals,
            productions: productions,
            precedence: precedence,
            tokenDeclarations: tokenDeclarations,
            undeclaredSymbols: undeclaredSymbols,
            conflictExpectation: conflictExpectation
        )
    }

    private mutating func parseDirective() {
        let directiveToken = advance()
        guard case .directive(let name) = directiveToken.kind else { return }
        if name == "start" {
            if requestedStart != nil {
                report("Duplicate %start directive; the last declaration is used.", at: directiveToken.range, severity: .warning, code: "duplicate-start")
            }
            if case .identifier(let symbol) = current.kind {
                requestedStart = symbol
                _ = advance()
            } else {
                report("Expected a nonterminal after %start.", at: current.range)
            }
        } else if name == "token" {
            var foundToken = false
            while !isNewline && !isEOF {
                switch current.kind {
                case .identifier(let value), .terminal(let value):
                    tokenDeclarations.append(.init(id: tokenDeclarations.count, name: value, range: current.range))
                    foundToken = true
                    _ = advance()
                default:
                    report("Expected a token name in %token declaration.", at: current.range)
                    _ = advance()
                }
            }
            if !foundToken {
                report("%token requires at least one token name.", at: directiveToken.range)
            }
        } else if name == "expect" {
            if conflictExpectation != nil {
                report("Duplicate %expect directive; the last declaration is used.", at: directiveToken.range, severity: .warning, code: "duplicate-expect")
            }
            if case .identifier(let value) = current.kind, let count = Int(value), count >= 0 {
                let range = SourceRange(start: directiveToken.range.start, end: current.range.end)
                conflictExpectation = .init(count: count, range: range)
                _ = advance()
            } else {
                report("Expected a non-negative integer after %expect.", at: current.range, code: "invalid-expect")
            }
        } else if ["left", "right", "nonassoc"].contains(name) {
            let associativity: Associativity = name == "left" ? .left : (name == "right" ? .right : .nonassociative)
            var symbols: [String] = []
            var end = directiveToken.range.end
            while !isNewline && !isEOF {
                switch current.kind {
                case .identifier(let value), .terminal(let value):
                    symbols.append(value)
                    end = current.range.end
                    _ = advance()
                default:
                    report("Expected a symbol in precedence declaration.", at: current.range)
                    _ = advance()
                }
            }
            if symbols.isEmpty {
                report("Precedence declaration requires at least one symbol.", at: directiveToken.range)
            } else {
                precedence.append(.init(associativity: associativity, symbols: symbols, level: precedence.count + 1, range: .init(start: directiveToken.range.start, end: end)))
            }
        } else {
            report("Unknown directive ‘%\(name)’.", at: directiveToken.range)
            skipToNewline()
        }
        skipToNewline()
    }

    private mutating func parseRule() {
        guard case .identifier(let lhs) = current.kind else {
            report("Expected a nonterminal or directive.", at: current.range)
            synchronizeRule()
            return
        }
        let start = current.range.start
        _ = advance()
        guard current.kind == .colon else {
            report("Expected ‘:’ after nonterminal ‘\(lhs)’.", at: current.range)
            synchronizeRule()
            return
        }
        _ = advance()
        var rhs: [(name: String, explicitTerminal: Bool, range: SourceRange)] = []
        var alternativeStart = start
        var lastEnd = current.range.end
        while true {
            switch current.kind {
            case .identifier(let value):
                rhs.append((value, false, current.range)); lastEnd = current.range.end; _ = advance()
            case .terminal(let value):
                rhs.append((value, true, current.range)); lastEnd = current.range.end; _ = advance()
            case .newline:
                _ = advance()
            case .pipe:
                drafts.append((lhs, rhs, .init(start: alternativeStart, end: lastEnd)))
                rhs = []
                alternativeStart = current.range.end
                lastEnd = current.range.end
                _ = advance()
            case .semicolon:
                lastEnd = current.range.end
                _ = advance()
                drafts.append((lhs, rhs, .init(start: alternativeStart, end: lastEnd)))
                return
            case .directive, .colon:
                report("Unexpected token in production.", at: current.range)
                _ = advance()
            case .eof:
                report("Expected ‘;’ to end production for ‘\(lhs)’.", at: current.range)
                drafts.append((lhs, rhs, .init(start: alternativeStart, end: lastEnd)))
                return
            }
        }
    }

    private var current: GrammarToken { tokens[min(index, tokens.count - 1)] }
    private var isEOF: Bool { current.kind == .eof }
    private var isNewline: Bool { current.kind == .newline }
    private mutating func advance() -> GrammarToken {
        let token = current
        if index < tokens.count - 1 { index += 1 }
        return token
    }
    private mutating func skipNewlines() {
        while isNewline { _ = advance() }
    }
    private mutating func skipToNewline() {
        while !isNewline && !isEOF { _ = advance() }
    }
    private mutating func synchronizeRule() {
        while current.kind != .semicolon && !isEOF { _ = advance() }
        if current.kind == .semicolon { _ = advance() }
    }
    private mutating func report(
        _ message: String,
        at range: SourceRange,
        severity: GrammarDiagnostic.Severity = .error,
        code: String = "syntax"
    ) {
        diagnostics.append(.init(id: diagnostics.count, severity: severity, code: code, message: message, range: range))
    }
    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

private enum GrammarAnalyzer {
    static func analyze(_ grammar: ParsedGrammar) -> GrammarAnalysis {
        let nonterminals = Set(grammar.nonterminals)
        var nullable: Set<String> = []
        var changed = true
        while changed {
            changed = false
            for production in grammar.productions
            where production.rhs.isEmpty || production.rhs.allSatisfy({ nullable.contains($0) }) {
                changed = nullable.insert(production.lhs).inserted || changed
            }
        }

        var first = Dictionary(uniqueKeysWithValues: grammar.nonterminals.map { ($0, Set<String>()) })
        changed = true
        while changed {
            changed = false
            for production in grammar.productions {
                for symbol in production.rhs {
                    if nonterminals.contains(symbol) {
                        let before = first[production.lhs, default: []].count
                        first[production.lhs, default: []].formUnion(first[symbol, default: []])
                        changed = changed || first[production.lhs, default: []].count != before
                        if !nullable.contains(symbol) { break }
                    } else {
                        changed = first[production.lhs, default: []].insert(symbol).inserted || changed
                        break
                    }
                }
            }
        }

        var follow = Dictionary(uniqueKeysWithValues: grammar.nonterminals.map { ($0, Set<String>()) })
        follow[grammar.startSymbol, default: []].insert("$")
        changed = true
        while changed {
            changed = false
            for production in grammar.productions {
                for (offset, symbol) in production.rhs.enumerated() where nonterminals.contains(symbol) {
                    let suffix = production.rhs.dropFirst(offset + 1)
                    var suffixNullable = true
                    for next in suffix {
                        if nonterminals.contains(next) {
                            let before = follow[symbol, default: []].count
                            follow[symbol, default: []].formUnion(first[next, default: []])
                            changed = changed || follow[symbol, default: []].count != before
                            if !nullable.contains(next) { suffixNullable = false; break }
                        } else {
                            changed = follow[symbol, default: []].insert(next).inserted || changed
                            suffixNullable = false
                            break
                        }
                    }
                    if suffixNullable {
                        let before = follow[symbol, default: []].count
                        follow[symbol, default: []].formUnion(follow[production.lhs, default: []])
                        changed = changed || follow[symbol, default: []].count != before
                    }
                }
            }
        }
        return GrammarAnalysis(nullable: nullable, first: first, follow: follow)
    }
}

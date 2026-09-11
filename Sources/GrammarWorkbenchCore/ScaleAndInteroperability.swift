import Foundation

/// Resource policy for validating large canonical grammar exchanges before a
/// host commits parser-construction memory.
public struct GrammarPortableScaleLimits: Hashable, Codable, Sendable {
    public var maximumSourceBytes: Int
    public var maximumProductions: Int
    public var maximumSymbols: Int
    public var maximumRightHandSideSymbols: Int

    public init(
        maximumSourceBytes: Int = 8_000_000,
        maximumProductions: Int = 20_000,
        maximumSymbols: Int = 20_000,
        maximumRightHandSideSymbols: Int = 250_000
    ) {
        self.maximumSourceBytes = maximumSourceBytes
        self.maximumProductions = maximumProductions
        self.maximumSymbols = maximumSymbols
        self.maximumRightHandSideSymbols = maximumRightHandSideSymbols
    }
}

public struct GrammarPortableScaleReport: Hashable, Codable, Sendable {
    public let sourceBytes: Int
    public let productions: Int
    public let nonterminals: Int
    public let terminals: Int
    public let rightHandSideSymbols: Int
    public let maximumProductionWidth: Int
    public let fingerprint: String
}

public enum GrammarPortableScaleError: Error, LocalizedError, Sendable {
    case limitExceeded(resource: String, actual: Int, maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .limitExceeded(let resource, let actual, let maximum):
            "Portable grammar \(resource) is \(actual), exceeding the limit of \(maximum)."
        }
    }
}

public enum GrammarPortableScaleValidator {
    public static func validate(
        _ interchange: GrammarPortableInterchange,
        sourceBytes: Int = 0,
        limits: GrammarPortableScaleLimits = .init()
    ) throws -> GrammarPortableScaleReport {
        let productions = interchange.specification.productions
        let nonterminals = Set(productions.map(\.lhs))
        var terminals: Set<String> = []
        var rhsCount = 0
        var maximumWidth = 0
        for production in productions {
            rhsCount += production.rhs.count
            maximumWidth = max(maximumWidth, production.rhs.count)
            for symbol in production.rhs {
                switch symbol {
                case .terminal(let value), .literal(let value): terminals.insert(value)
                case .nonterminal: break
                }
            }
        }
        let checks = [
            ("source bytes", sourceBytes, limits.maximumSourceBytes),
            ("production count", productions.count, limits.maximumProductions),
            ("symbol count", nonterminals.count + terminals.count, limits.maximumSymbols),
            ("right-hand-side symbol count", rhsCount, limits.maximumRightHandSideSymbols)
        ]
        if let failed = checks.first(where: { $0.1 > $0.2 }) {
            throw GrammarPortableScaleError.limitExceeded(
                resource: failed.0, actual: failed.1, maximum: failed.2
            )
        }
        return .init(
            sourceBytes: sourceBytes, productions: productions.count,
            nonterminals: nonterminals.count, terminals: terminals.count,
            rightHandSideSymbols: rhsCount, maximumProductionWidth: maximumWidth,
            fingerprint: interchange.fingerprint
        )
    }
}

enum GrammarYaccInterchange {
    private struct RawProduction {
        let lhs: String
        let alternatives: [[RawSymbol]]
    }

    private enum RawSymbol {
        case name(String)
        case literal(String)
    }

    static func parse(
        _ source: String, startSymbol requestedStart: String?
    ) throws -> GrammarBootstrapSpecification {
        let bytes = Data(source.utf8).count
        guard bytes <= GrammarPortableScaleLimits().maximumSourceBytes else {
            throw GrammarPortableScaleError.limitExceeded(
                resource: "source bytes", actual: bytes,
                maximum: GrammarPortableScaleLimits().maximumSourceBytes
            )
        }
        let cleaned = try removeCommentsAndActions(source)
        let sections = cleaned.components(separatedBy: "%%")
        guard sections.count >= 2 else {
            throw GrammarPortableInterchangeError.invalidGrammar(
                "Yacc input must contain a declaration/grammar ‘%%’ separator."
            )
        }
        let declarations = sections[0]
        let grammar = sections[1]
        var declaredStart: String?
        for line in declarations.split(whereSeparator: \Character.isNewline) {
            let fields = line.split(whereSeparator: \Character.isWhitespace).map(String.init)
            guard let directive = fields.first else { continue }
            if directive == "%start", fields.count == 2 {
                declaredStart = fields[1]
            }
        }

        let rawProductions = try parseProductions(grammar)
        guard let first = rawProductions.first else {
            throw GrammarPortableInterchangeError.invalidGrammar("The Yacc production set is empty.")
        }
        let nonterminals = Set(rawProductions.map(\.lhs))
        let start = requestedStart ?? declaredStart ?? first.lhs
        guard nonterminals.contains(start) else {
            throw GrammarPortableInterchangeError.invalidGrammar(
                "The Yacc start symbol ‘\(start)’ is not defined."
            )
        }
        let productions = rawProductions.flatMap { production in
            production.alternatives.map { alternative in
                GrammarBootstrapProduction(lhs: production.lhs, rhs: alternative.map { symbol -> GrammarBootstrapSymbol in
                    switch symbol {
                    case .literal(let value): return .literal(value)
                    case .name(let value):
                        if nonterminals.contains(value) { return .nonterminal(value) }
                        return .terminal(value)
                    }
                })
            }
        }
        let interchange = GrammarPortableInterchange(
            sourceNotation: .yacc,
            specification: .init(startSymbol: start, productions: productions)
        )
        _ = try GrammarPortableScaleValidator.validate(interchange, sourceBytes: bytes)
        return interchange.specification
    }

    static func render(_ specification: GrammarBootstrapSpecification) -> String {
        let terminals = Set(specification.productions.flatMap(\.rhs).compactMap { symbol -> String? in
            if case .terminal(let value) = symbol { return value }
            return nil
        }).sorted()
        var lines: [String] = []
        if !terminals.isEmpty { lines.append("%token " + terminals.joined(separator: " ")) }
        lines.append("%start \(specification.startSymbol)")
        lines.append("%%")
        let grouped = Dictionary(grouping: specification.productions, by: \.lhs)
        for lhs in grouped.keys.sorted() {
            let alternatives = grouped[lhs, default: []].map { production in
                production.rhs.isEmpty ? "%empty" : production.rhs.map(renderSymbol).joined(separator: " ")
            }
            lines.append("\(lhs) : \(alternatives.joined(separator: "\n    | "))\n    ;")
        }
        lines.append("%%")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderSymbol(_ symbol: GrammarBootstrapSymbol) -> String {
        switch symbol {
        case .nonterminal(let value), .terminal(let value): value
        case .literal(let value): "'\(value.replacingOccurrences(of: "'", with: "\\'"))'"
        }
    }

    private static func parseProductions(_ source: String) throws -> [RawProduction] {
        let tokens = try tokenize(source)
        var index = 0
        var result: [RawProduction] = []
        while index < tokens.count {
            guard case .name(let lhs) = tokens[index] else {
                throw GrammarPortableInterchangeError.invalidGrammar("Expected a Yacc production name.")
            }
            index += 1
            guard index < tokens.count, case .literal(":") = tokens[index] else {
                throw GrammarPortableInterchangeError.invalidGrammar("Expected ‘:’ after Yacc production ‘\(lhs)’.")
            }
            index += 1
            var alternatives: [[RawSymbol]] = [[]]
            while index < tokens.count {
                let token = tokens[index]; index += 1
                switch token {
                case .literal("|"): alternatives.append([])
                case .literal(";"):
                    result.append(.init(
                        lhs: lhs,
                        alternatives: alternatives.map { alternative in
                            alternative.filter { symbol in
                                if case .name("%empty") = symbol { return false }
                                return true
                            }
                        }
                    ))
                    break
                case .name("%prec"):
                    if index < tokens.count { index += 1 }
                default: alternatives[alternatives.count - 1].append(token)
                }
                if case .literal(";") = token { break }
            }
            guard result.last?.lhs == lhs else {
                throw GrammarPortableInterchangeError.invalidGrammar("Yacc production ‘\(lhs)’ is missing ‘;’.")
            }
        }
        return result
    }

    private static func tokenize(_ source: String) throws -> [RawSymbol] {
        var result: [RawSymbol] = []
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            if character.isWhitespace { index = source.index(after: index); continue }
            if character == ":" || character == "|" || character == ";" {
                result.append(.literal(String(character))); index = source.index(after: index); continue
            }
            if character == "'" || character == "\"" {
                let quote = character; index = source.index(after: index); var value = ""
                while index < source.endIndex, source[index] != quote {
                    if source[index] == "\\" {
                        index = source.index(after: index)
                        guard index < source.endIndex else { break }
                    }
                    value.append(source[index]); index = source.index(after: index)
                }
                guard index < source.endIndex else {
                    throw GrammarPortableInterchangeError.invalidGrammar("Unterminated Yacc literal.")
                }
                index = source.index(after: index); result.append(.literal(value)); continue
            }
            let start = index
            while index < source.endIndex,
                  !source[index].isWhitespace,
                  ![":", "|", ";", "'", "\""].contains(source[index]) {
                index = source.index(after: index)
            }
            result.append(.name(String(source[start..<index])))
        }
        return result
    }

    private static func removeCommentsAndActions(_ source: String) throws -> String {
        var output = "", index = source.startIndex, blockDepth = 0
        var quote: Character?
        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)
            if let activeQuote = quote {
                output.append(character)
                if character == "\\", next < source.endIndex {
                    output.append(source[next]); index = source.index(after: next); continue
                }
                if character == activeQuote { quote = nil }
                index = next; continue
            }
            if character == "'" || character == "\"" { quote = character; output.append(character); index = next; continue }
            if blockDepth == 0, character == "/", next < source.endIndex, source[next] == "*" {
                let end = source.range(of: "*/", range: source.index(after: next)..<source.endIndex)
                guard let end else { throw GrammarPortableInterchangeError.invalidGrammar("Unterminated Yacc comment.") }
                output.append(" "); index = end.upperBound; continue
            }
            if blockDepth == 0, character == "/", next < source.endIndex, source[next] == "/" {
                index = source[next...].firstIndex(of: "\n") ?? source.endIndex; output.append("\n"); continue
            }
            if character == "{" { blockDepth += 1; output.append(" "); index = next; continue }
            if character == "}", blockDepth > 0 { blockDepth -= 1; index = next; continue }
            if blockDepth == 0 { output.append(character) }
            index = next
        }
        guard blockDepth == 0 else { throw GrammarPortableInterchangeError.invalidGrammar("Unterminated Yacc action.") }
        return output
    }
}

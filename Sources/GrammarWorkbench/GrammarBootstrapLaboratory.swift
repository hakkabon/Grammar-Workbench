import Foundation
import Grammar

public enum GrammarBootstrapSymbol: Hashable, Codable, Sendable {
    case nonterminal(String)
    case terminal(String)
    case literal(String)
}

public struct GrammarBootstrapProduction: Hashable, Codable, Sendable {
    public let lhs: String
    public let rhs: [GrammarBootstrapSymbol]

    public init(lhs: String, rhs: [GrammarBootstrapSymbol]) {
        self.lhs = lhs
        self.rhs = rhs
    }
}

/// A notation-neutral grammar value used as the fixed-point contract between
/// bootstrap generations. Production and alternative order are canonicalized.
public struct GrammarBootstrapSpecification: Hashable, Codable, Sendable {
    public let startSymbol: String
    public let productions: [GrammarBootstrapProduction]

    public init(startSymbol: String, productions: [GrammarBootstrapProduction]) {
        self.startSymbol = startSymbol
        self.productions = Self.canonicalize(productions)
    }

    public var canonicalDescription: String {
        (["start:\(startSymbol)"] + productions.map { production in
            let rhs = production.rhs.map { symbol in
                switch symbol {
                case .nonterminal(let name): return "N:\(name)"
                case .terminal(let name): return "T:\(name)"
                case .literal(let value): return "L:\(String(reflecting: value))"
                }
            }.joined(separator: " ")
            return "\(production.lhs)->\(rhs)"
        }).joined(separator: "\n")
    }

    public var fingerprint: String { BootstrapFingerprint.make(canonicalDescription) }

    private static func canonicalize(
        _ productions: [GrammarBootstrapProduction]
    ) -> [GrammarBootstrapProduction] {
        Array(Set(productions)).sorted {
            let left = canonicalKey($0)
            let right = canonicalKey($1)
            return left < right
        }
    }

    private static func canonicalKey(_ production: GrammarBootstrapProduction) -> String {
        let rhs = production.rhs.map { symbol in
            switch symbol {
            case .nonterminal(let value): "0\(value)"
            case .terminal(let value): "1\(value)"
            case .literal(let value): "2\(value)"
            }
        }.joined(separator: "\u{1f}")
        return "\(production.lhs)\u{1e}\(rhs)"
    }
}

public struct GrammarBootstrapGeneration: Hashable, Codable, Sendable, Identifiable {
    public let generation: Int
    public let sourceFingerprint: String
    public let grammarFingerprint: String
    public let artifactFingerprint: String
    public let productionCount: Int
    public let stateCount: Int
    public let tableEntryCount: Int
    public let stableWithPrevious: Bool
    public var id: Int { generation }
}

public struct GrammarBootstrapCorpusCase: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let bootstrapAccepted: Bool
    public let trustedAccepted: Bool
    public let bootstrapFingerprint: String?
    public let trustedFingerprint: String?
    public let matches: Bool
    public let detail: String
}

public struct GrammarBootstrapReport: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let profile: String
    public let generations: [GrammarBootstrapGeneration]
    public let reachedFixedPoint: Bool
    public let fixedPointGeneration: Int?
    public let corpus: [GrammarBootstrapCorpusCase]
    public let limitations: [String]

    public var differentialValidationPassed: Bool { corpus.allSatisfy(\.matches) }
    public var succeeded: Bool { reachedFixedPoint && differentialValidationPassed }
}

public struct GrammarBootstrapOptions: Hashable, Codable, Sendable {
    public var maximumGenerations: Int

    public init(maximumGenerations: Int = 4) {
        self.maximumGenerations = max(3, maximumGenerations)
    }
}

public enum GrammarBootstrapError: Error, LocalizedError, Sendable {
    case compilationFailed(generation: Int, message: String)
    case parseFailed(generation: Int, message: String)
    case invalidBNF(line: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .compilationFailed(let generation, let message):
            "Bootstrap generation \(generation) did not compile: \(message)"
        case .parseFailed(let generation, let message):
            "Bootstrap generation \(generation) rejected its meta-grammar: \(message)"
        case .invalidBNF(let line, let message):
            "Invalid laboratory BNF on line \(line): \(message)"
        }
    }
}

/// A reproducible self-hosting experiment. Stage 0 is intentionally retained
/// as a small trusted seed; later stages must reproduce a canonical grammar
/// model and independently compiled LR artifact before they are considered stable.
public enum GrammarBootstrapLaboratory {
    private enum RawSymbol { case reference(String), literal(String) }

    public static let profileName = "Grammar Workbench BNF bootstrap profile 1"

    public static let metaGrammar = """
    <syntax> ::= <rule> <syntax> | <rule>
    <rule> ::= <LANGLE> <IDENT> <RANGLE> <DEFINE> <expression> <eols>
    <expression> ::= <list> <PIPE> <expression> | <list>
    <list> ::= <term> <list> | <term>
    <term> ::= <LANGLE> <IDENT> <RANGLE> | <LITERAL>
    <eols> ::= <EOL> <eols> | <EOL>
    """ + "\n"

    public static func run(
        options: GrammarBootstrapOptions = .init(),
        corpus: [(name: String, source: String)] = defaultCorpus
    ) throws -> GrammarBootstrapReport {
        var parserSource = seedParserSource
        var previousGrammarFingerprint: String?
        var previousSourceFingerprint: String?
        var previousArtifactFingerprint: String?
        var generations: [GrammarBootstrapGeneration] = []
        var fixedPoint: Int?

        for generation in 0..<options.maximumGenerations {
            let compilation = GrammarWorkbenchAPI.compile(.init(source: parserSource))
            guard compilation.succeeded, let artifact = compilation.artifact else {
                throw GrammarBootstrapError.compilationFailed(
                    generation: generation,
                    message: compilation.diagnostics.first(where: { $0.severity == .error })?.message
                        ?? "The grammar did not compile."
                )
            }
            let parsed = compilation.parse(metaGrammar)
            guard parsed.status == .accepted else {
                throw GrammarBootstrapError.parseFailed(
                    generation: generation, message: parsed.message
                )
            }
            let specification = try parseProfileBNF(metaGrammar, start: "syntax")
            let grammarFingerprint = specification.fingerprint
            let sourceFingerprint = BootstrapFingerprint.make(parserSource)
            let artifactFingerprint = BootstrapFingerprint.make(canonicalArtifact(artifact))
            let stable = previousGrammarFingerprint == grammarFingerprint
                && previousSourceFingerprint == sourceFingerprint
                && previousArtifactFingerprint == artifactFingerprint
            generations.append(.init(
                generation: generation,
                sourceFingerprint: sourceFingerprint,
                grammarFingerprint: grammarFingerprint,
                artifactFingerprint: artifactFingerprint,
                productionCount: artifact.productions.count,
                stateCount: artifact.states.count,
                tableEntryCount: artifact.table.count,
                stableWithPrevious: stable
            ))
            if stable { fixedPoint = generation; break }
            previousGrammarFingerprint = grammarFingerprint
            previousSourceFingerprint = sourceFingerprint
            previousArtifactFingerprint = artifactFingerprint
            parserSource = renderParserSource(specification)
        }

        let validationParser = GrammarWorkbenchAPI.compile(.init(source: parserSource))
        let comparisons = corpus.enumerated().map { index, item in
            compareCorpusCase(id: "bnf-\(index + 1)", name: item.name, source: item.source,
                              parser: validationParser)
        }
        return .init(
            schemaVersion: GrammarBootstrapReport.currentSchemaVersion,
            profile: profileName,
            generations: generations,
            reachedFixedPoint: fixedPoint != nil,
            fixedPointGeneration: fixedPoint,
            corpus: comparisons,
            limitations: [
                "The laboratory BNF profile requires one complete production per line.",
                "It supports angle-bracket nonterminals, quoted literals, alternatives, and no explicit epsilon spelling.",
                "The handwritten Grammar reader remains the trusted implementation; bootstrap artifacts do not replace it."
            ]
        )
    }

    public static let defaultCorpus: [(name: String, source: String)] = [
        ("single literal", "<start> ::= \"hello\"\n"),
        ("alternatives", "<value> ::= \"yes\" | \"no\"\n"),
        ("references", "<start> ::= <item> <start> | <item>\n<item> ::= 'x'\n"),
        ("meta grammar", metaGrammar)
    ]

    static func parseProfileBNF(_ source: String, start: String) throws -> GrammarBootstrapSpecification {
        struct RawProduction { let lhs: String; let alternatives: [[RawSymbol]] }
        var raw: [RawProduction] = []

        for (offset, originalLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = offset + 1
            let line = String(originalLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard line.first == "<", let closing = line.firstIndex(of: ">") else {
                throw GrammarBootstrapError.invalidBNF(line: lineNumber, message: "expected <nonterminal> on the left-hand side")
            }
            let lhs = String(line[line.index(after: line.startIndex)..<closing])
            let afterLHS = line[line.index(after: closing)...].trimmingCharacters(in: .whitespaces)
            guard afterLHS.hasPrefix("::=") else {
                throw GrammarBootstrapError.invalidBNF(line: lineNumber, message: "expected ::= after <\(lhs)>")
            }
            let rhs = String(afterLHS.dropFirst(3))
            let alternatives = try tokenizeRHS(rhs, line: lineNumber)
            raw.append(.init(lhs: lhs, alternatives: alternatives))
        }
        guard !raw.isEmpty else {
            throw GrammarBootstrapError.invalidBNF(line: 1, message: "the grammar is empty")
        }
        let defined = Set(raw.map(\.lhs))
        let productions = raw.flatMap { production in
            production.alternatives.map { alternative in
                GrammarBootstrapProduction(lhs: production.lhs, rhs: alternative.map { symbol in
                    switch symbol {
                    case .literal(let value): return .literal(value)
                    case .reference(let name):
                        return defined.contains(name) ? .nonterminal(name) : .terminal(name)
                    }
                })
            }
        }
        return .init(startSymbol: start, productions: productions)
    }

    private static func tokenizeRHS(_ source: String, line: Int) throws -> [[RawSymbol]] {
        var alternatives: [[RawSymbol]] = [[]]
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            if character.isWhitespace { index = source.index(after: index); continue }
            if character == "|" { alternatives.append([]); index = source.index(after: index); continue }
            if character == "<" {
                guard let close = source[index...].firstIndex(of: ">") else {
                    throw GrammarBootstrapError.invalidBNF(line: line, message: "unterminated nonterminal reference")
                }
                alternatives[alternatives.count - 1].append(.reference(String(source[source.index(after: index)..<close])))
                index = source.index(after: close)
                continue
            }
            if character == "\"" || character == "'" {
                let quote = character
                var cursor = source.index(after: index)
                var value = ""
                var escaped = false
                while cursor < source.endIndex {
                    let next = source[cursor]
                    if escaped { value.append(next); escaped = false }
                    else if next == "\\" { escaped = true }
                    else if next == quote { break }
                    else { value.append(next) }
                    cursor = source.index(after: cursor)
                }
                guard cursor < source.endIndex else {
                    throw GrammarBootstrapError.invalidBNF(line: line, message: "unterminated quoted literal")
                }
                alternatives[alternatives.count - 1].append(.literal(value))
                index = source.index(after: cursor)
                continue
            }
            throw GrammarBootstrapError.invalidBNF(line: line, message: "unexpected character ‘\(character)’")
        }
        guard alternatives.allSatisfy({ !$0.isEmpty }) else {
            throw GrammarBootstrapError.invalidBNF(line: line, message: "empty alternatives are not in this profile")
        }
        return alternatives
    }

    private static func compareCorpusCase(
        id: String, name: String, source: String, parser: GrammarCompilation
    ) -> GrammarBootstrapCorpusCase {
        let parsed = parser.parse(source)
        let bootstrapAccepted = parsed.status == .accepted
        let bootstrap = try? parseProfileBNF(source, start: inferredStart(source))
        let trusted = try? trustedSpecification(source, start: inferredStart(source))
        let matches = bootstrapAccepted && bootstrap?.fingerprint == trusted?.fingerprint
        return .init(
            id: id, name: name,
            bootstrapAccepted: bootstrapAccepted, trustedAccepted: trusted != nil,
            bootstrapFingerprint: bootstrap?.fingerprint,
            trustedFingerprint: trusted?.fingerprint,
            matches: matches,
            detail: matches ? "Canonical grammar models agree." : "Bootstrap and trusted grammar models differ."
        )
    }

    private static func trustedSpecification(_ source: String, start: String) throws -> GrammarBootstrapSpecification {
        let grammar = try Grammar(bnf: source, start: start)
        let defined = Set(grammar.productions.map { $0.goal.name })
        let productions = grammar.productions.map { production in
            GrammarBootstrapProduction(lhs: production.goal.name, rhs: production.rule.compactMap { symbol in
                switch symbol {
                case .nonTerminal(let value):
                    return defined.contains(value.name) ? .nonterminal(value.name) : .terminal(value.name)
                case .terminal(let value):
                    switch value {
                    case .string(let string): return .literal(string)
                    case .meta(let meta) where meta == .eps || meta == .lambda || meta == .empty: return nil
                    default: return .literal(value.description)
                    }
                case .metaSymbol: return nil
                }
            })
        }
        return .init(startSymbol: start, productions: productions)
    }

    private static func inferredStart(_ source: String) -> String {
        guard let open = source.firstIndex(of: "<"), let close = source[open...].firstIndex(of: ">") else { return "syntax" }
        return String(source[source.index(after: open)..<close])
    }

    private static func renderParserSource(_ specification: GrammarBootstrapSpecification) -> String {
        let grouped = Dictionary(grouping: specification.productions, by: \.lhs)
        let productions = grouped.keys.sorted().map { lhs in
            let alternatives = grouped[lhs, default: []].map { production in
                production.rhs.map { symbol in
                    switch symbol {
                    case .nonterminal(let value), .terminal(let value): return value
                    case .literal(let value): return "'\(value.replacingOccurrences(of: "'", with: "\\'"))'"
                    }
                }.joined(separator: " ")
            }.sorted().joined(separator: " | ")
            return "\(lhs) : \(alternatives) ;"
        }.joined(separator: "\n")
        return lexerPreamble + "\n%start \(specification.startSymbol)\n" + productions + "\n"
    }

    private static func canonicalArtifact(_ artifact: GrammarArtifactSnapshot) -> String {
        let productions = artifact.productions.map { "\($0.lhs)->\($0.rhs.joined(separator: " "))" }.sorted()
        let states = artifact.states.map { $0.items.sorted().joined(separator: "|") }.sorted()
        let transitions = artifact.transitions.map { "\($0.from):\($0.symbol):\($0.to)" }.sorted()
        let table = artifact.table.map { cell in
            let actions = cell.actions.map { action in
                "\(action.kind.rawValue):\(action.targetState.map(String.init) ?? "-"):\(action.production.map(String.init) ?? "-")"
            }.sorted().joined(separator: ",")
            return "\(cell.state):\(cell.symbol):\(actions)"
        }.sorted()
        var lines = productions
        lines.append("--states--")
        lines.append(contentsOf: states)
        lines.append("--transitions--")
        lines.append(contentsOf: transitions)
        lines.append("--table--")
        lines.append(contentsOf: table)
        return lines.joined(separator: "\n")
    }

    private static let seedParserSource = lexerPreamble + """

    %start syntax
    syntax : rule syntax | rule ;
    rule : LANGLE IDENT RANGLE DEFINE expression eols ;
    expression : list PIPE expression | list ;
    list : term list | term ;
    term : LANGLE IDENT RANGLE | LITERAL ;
    eols : EOL eols | EOL ;
    """

    private static let lexerPreamble = #"""
    %token LANGLE /</
    %token RANGLE />/
    %token DEFINE /::=/
    %token PIPE /\|/
    %token LITERAL /"([^"\\]|\\.)*"|'([^'\\]|\\.)*'/
    %token IDENT /[A-Za-z][A-Za-z0-9-]*/
    %token EOL /\r?\n/
    %skip /[ \t]+/
    """#
}

private enum BootstrapFingerprint {
    static func make(_ value: String) -> String { make(Data(value.utf8)) }

    static func make(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(format: "%016llx", hash)
    }
}

import Foundation

public enum GrammarPortableNotation: String, CaseIterable, Codable, Sendable {
    case bnfProfile
    case workbench
    case ebnf
    case yacc
}

public enum GrammarPortableRenderFormat: String, CaseIterable, Codable, Sendable {
    case bnfProfile
    case workbench
    case yacc
}

/// Canonical grammar exchange independent of parser tables and UI documents.
public struct GrammarPortableInterchange: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-portable-grammar"

    public let schemaVersion: Int
    public let kind: String
    public let producer: String
    public let sourceNotation: GrammarPortableNotation
    public let specification: GrammarBootstrapSpecification
    public let fingerprint: String

    public init(
        sourceNotation: GrammarPortableNotation,
        specification: GrammarBootstrapSpecification,
        producer: String = "Grammar Workbench \(GrammarWorkbenchRelease.version)"
    ) {
        schemaVersion = Self.currentSchemaVersion
        kind = Self.kindIdentifier
        self.producer = producer
        self.sourceNotation = sourceNotation
        self.specification = specification
        fingerprint = specification.fingerprint
    }
}

public enum GrammarPortableInterchangeError: Error, LocalizedError, Sendable {
    case unsupportedVersion(Int)
    case invalidKind(String)
    case invalidFingerprint(expected: String, actual: String)
    case invalidGrammar(String)
    case unsupportedNotation(GrammarPortableNotation)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "Unsupported portable grammar schema version \(version)."
        case .invalidKind(let kind):
            "Unexpected portable grammar kind ‘\(kind)’."
        case .invalidFingerprint(let expected, let actual):
            "Portable grammar fingerprint mismatch: expected \(expected), found \(actual)."
        case .invalidGrammar(let message):
            "The portable grammar is invalid: \(message)"
        case .unsupportedNotation(let notation):
            "Portable import does not support \(notation.rawValue)."
        }
    }
}

public struct GrammarPortableRoundTripReport: Hashable, Codable, Sendable {
    public let sourceFingerprint: String
    public let renderedFormat: GrammarPortableRenderFormat
    public let importedFingerprint: String
    public let matches: Bool
}

public enum GrammarPortableInterchangeCodec {
    public static func importGrammar(
        _ source: String,
        notation: GrammarPortableNotation,
        startSymbol: String? = nil
    ) throws -> GrammarPortableInterchange {
        let specification: GrammarBootstrapSpecification
        switch notation {
        case .bnfProfile:
            let start = startSymbol ?? inferredBNFStart(source)
            specification = try GrammarBootstrapLaboratory.parseProfileBNF(source, start: start)
        case .workbench, .ebnf:
            let request = GrammarCompilationRequest(
                source: source,
                notation: notation == .ebnf ? .ebnf : .workbench
            )
            let compilation = GrammarWorkbenchAPI.compile(request)
            guard let grammar = compilation.grammar else {
                throw GrammarPortableInterchangeError.invalidGrammar(
                    compilation.diagnostics.first(where: { $0.severity == .error })?.message
                        ?? "Compilation failed."
                )
            }
            let nonterminals = Set(grammar.nonterminals)
            specification = .init(
                startSymbol: grammar.startSymbol,
                productions: grammar.productions.map { production in
                    .init(lhs: production.lhs, rhs: production.rhs.map { symbol in
                        nonterminals.contains(symbol) ? .nonterminal(symbol) : .terminal(symbol)
                    })
                }
            )
        case .yacc:
            specification = try GrammarYaccInterchange.parse(source, startSymbol: startSymbol)
        }
        return .init(sourceNotation: notation, specification: specification)
    }

    public static func encode(_ value: GrammarPortableInterchange) throws -> Data {
        try validate(value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func decode(_ data: Data) throws -> GrammarPortableInterchange {
        let value = try JSONDecoder().decode(GrammarPortableInterchange.self, from: data)
        try validate(value)
        return value
    }

    public static func render(
        _ value: GrammarPortableInterchange,
        as format: GrammarPortableRenderFormat
    ) throws -> String {
        try validate(value)
        if format == .bnfProfile,
           let production = value.specification.productions.first(where: { $0.rhs.isEmpty }) {
            throw GrammarPortableInterchangeError.invalidGrammar(
                "The bootstrap BNF profile cannot represent epsilon production ‘\(production.lhs)’."
            )
        }
        return switch format {
        case .bnfProfile: renderBNF(value.specification)
        case .workbench: renderWorkbench(value.specification)
        case .yacc: GrammarYaccInterchange.render(value.specification)
        }
    }

    public static func verifyRoundTrip(
        _ value: GrammarPortableInterchange,
        through format: GrammarPortableRenderFormat
    ) throws -> GrammarPortableRoundTripReport {
        let rendered = try render(value, as: format)
        let imported: GrammarPortableInterchange
        switch format {
        case .bnfProfile:
            imported = try importGrammar(
                rendered, notation: .bnfProfile, startSymbol: value.specification.startSymbol
            )
        case .workbench:
            imported = try importGrammar(rendered, notation: .workbench)
        case .yacc:
            imported = try importGrammar(rendered, notation: .yacc)
        }
        return .init(
            sourceFingerprint: value.fingerprint,
            renderedFormat: format,
            importedFingerprint: imported.fingerprint,
            matches: value.fingerprint == imported.fingerprint
        )
    }

    private static func validate(_ value: GrammarPortableInterchange) throws {
        guard value.schemaVersion == GrammarPortableInterchange.currentSchemaVersion else {
            throw GrammarPortableInterchangeError.unsupportedVersion(value.schemaVersion)
        }
        guard value.kind == GrammarPortableInterchange.kindIdentifier else {
            throw GrammarPortableInterchangeError.invalidKind(value.kind)
        }
        let productions = value.specification.productions
        guard !productions.isEmpty else {
            throw GrammarPortableInterchangeError.invalidGrammar("The production set is empty.")
        }
        let defined = Set(productions.map(\.lhs))
        guard !value.specification.startSymbol.isEmpty,
              defined.contains(value.specification.startSymbol) else {
            throw GrammarPortableInterchangeError.invalidGrammar(
                "The start symbol ‘\(value.specification.startSymbol)’ is not defined."
            )
        }
        guard productions.allSatisfy({ !$0.lhs.isEmpty && $0.rhs.allSatisfy { symbol in
            switch symbol {
            case .nonterminal(let value), .terminal(let value): !value.isEmpty
            case .literal: true
            }
        } }) else {
            throw GrammarPortableInterchangeError.invalidGrammar("A grammar symbol name is empty.")
        }
        let expected = value.specification.fingerprint
        guard value.fingerprint == expected else {
            throw GrammarPortableInterchangeError.invalidFingerprint(
                expected: expected, actual: value.fingerprint
            )
        }
    }

    private static func renderBNF(_ specification: GrammarBootstrapSpecification) -> String {
        let grouped = Dictionary(grouping: specification.productions, by: \.lhs)
        return grouped.keys.sorted().map { lhs in
            let alternatives = grouped[lhs, default: []].map { production in
                production.rhs.map { symbol in
                    switch symbol {
                    case .nonterminal(let value), .terminal(let value): "<\(value)>"
                    case .literal(let value): "\"\(quoted(value))\""
                    }
                }.joined(separator: " ")
            }.sorted().joined(separator: " | ")
            return "<\(lhs)> ::= \(alternatives)"
        }.joined(separator: "\n") + "\n"
    }

    private static func renderWorkbench(_ specification: GrammarBootstrapSpecification) -> String {
        let terminals = Set(specification.productions.flatMap(\.rhs).compactMap { symbol -> String? in
            if case .terminal(let value) = symbol { return value }
            return nil
        }).sorted()
        let declarations = terminals.map { terminal in
            "%token \(terminal) /\(regexEscaped(terminal))/"
        }
        let grouped = Dictionary(grouping: specification.productions, by: \.lhs)
        let productions = grouped.keys.sorted().map { lhs in
            let alternatives = grouped[lhs, default: []].map { production in
                production.rhs.map { symbol in
                    switch symbol {
                    case .nonterminal(let value), .terminal(let value): value
                    case .literal(let value): "'\(value.replacingOccurrences(of: "'", with: "\\'"))'"
                    }
                }.joined(separator: " ")
            }.sorted().joined(separator: " | ")
            return "\(lhs) : \(alternatives) ;"
        }
        return (["%start \(specification.startSymbol)"] + declarations + productions)
            .joined(separator: "\n") + "\n"
    }

    private static func inferredBNFStart(_ source: String) -> String {
        guard let open = source.firstIndex(of: "<"),
              let close = source[open...].firstIndex(of: ">") else { return "syntax" }
        return String(source[source.index(after: open)..<close])
    }

    private static func quoted(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func regexEscaped(_ value: String) -> String {
        NSRegularExpression.escapedPattern(for: value).replacingOccurrences(of: "/", with: "\\/")
    }
}

/// Reproducible package containing the canonical meta-grammar and the evidence
/// that its generated parser reached a differentially validated fixed point.
public struct GrammarBootstrapInterchangeBundle: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-bootstrap-bundle"

    public let schemaVersion: Int
    public let kind: String
    public let producer: String
    public let metaGrammar: GrammarPortableInterchange
    public let report: GrammarBootstrapReport

    public init(
        metaGrammar: GrammarPortableInterchange,
        report: GrammarBootstrapReport,
        producer: String = "Grammar Workbench \(GrammarWorkbenchRelease.version)"
    ) {
        schemaVersion = Self.currentSchemaVersion
        kind = Self.kindIdentifier
        self.producer = producer
        self.metaGrammar = metaGrammar
        self.report = report
    }
}

public enum GrammarBootstrapInterchangeCodec {
    public static func makeBundle(
        options: GrammarBootstrapOptions = .init()
    ) throws -> GrammarBootstrapInterchangeBundle {
        let grammar = try GrammarPortableInterchangeCodec.importGrammar(
            GrammarBootstrapLaboratory.metaGrammar,
            notation: .bnfProfile,
            startSymbol: "syntax"
        )
        return .init(metaGrammar: grammar, report: try GrammarBootstrapLaboratory.run(options: options))
    }

    public static func encode(_ bundle: GrammarBootstrapInterchangeBundle) throws -> Data {
        try validate(bundle)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(bundle)
    }

    public static func decode(_ data: Data) throws -> GrammarBootstrapInterchangeBundle {
        let bundle = try JSONDecoder().decode(GrammarBootstrapInterchangeBundle.self, from: data)
        try validate(bundle)
        return bundle
    }

    private static func validate(_ bundle: GrammarBootstrapInterchangeBundle) throws {
        guard bundle.schemaVersion == GrammarBootstrapInterchangeBundle.currentSchemaVersion else {
            throw GrammarPortableInterchangeError.unsupportedVersion(bundle.schemaVersion)
        }
        guard bundle.kind == GrammarBootstrapInterchangeBundle.kindIdentifier else {
            throw GrammarPortableInterchangeError.invalidKind(bundle.kind)
        }
        _ = try GrammarPortableInterchangeCodec.decode(
            GrammarPortableInterchangeCodec.encode(bundle.metaGrammar)
        )
        guard bundle.report.profile == GrammarBootstrapLaboratory.profileName,
              bundle.report.generations.contains(where: {
                  $0.grammarFingerprint == bundle.metaGrammar.fingerprint
              }) else {
            throw GrammarPortableInterchangeError.invalidGrammar(
                "The bootstrap report does not describe the bundled meta-grammar."
            )
        }
    }
}

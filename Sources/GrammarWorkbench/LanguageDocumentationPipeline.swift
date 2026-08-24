import Foundation
import GrammarDiagramKit

public enum GrammarLanguageDocumentationSymbolKind: String, Hashable, Codable, Sendable {
    case terminal, nonterminal
}

public struct GrammarLanguageDocumentationSymbol: Hashable, Codable, Sendable {
    public let name: String
    public let kind: GrammarLanguageDocumentationSymbolKind
}

public struct GrammarLanguageDocumentationProduction: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let text: String
    public let symbols: [GrammarLanguageDocumentationSymbol]
    public let sourceRange: SourceRange
}

public struct GrammarLanguageDocumentationRule: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let anchor: String
    public let productions: [GrammarLanguageDocumentationProduction]
    public let incomingRules: [String]
    public let outgoingRules: [String]
    public let first: [String]
    public let follow: [String]
    public let recursiveComponent: [String]
    public let isStart: Bool
    public let isReachable: Bool
    public let isProductive: Bool
    public let isNullable: Bool
    public let isRecursive: Bool
}

public struct GrammarLanguageDocumentation: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let title: String
    public let sourceFingerprint: String
    public let startRule: String
    public let terminals: [String]
    public let rules: [GrammarLanguageDocumentationRule]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion, title: String,
        sourceFingerprint: String, startRule: String, terminals: [String],
        rules: [GrammarLanguageDocumentationRule]
    ) {
        self.schemaVersion = schemaVersion; self.title = title
        self.sourceFingerprint = sourceFingerprint; self.startRule = startRule
        self.terminals = terminals; self.rules = rules
    }
}

public enum GrammarLanguageDocumentationError: Error, LocalizedError, Sendable {
    case unsupportedSchema(Int)
    case invalidDocument(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "Language documentation schema \(version) is unsupported."
        case .invalidDocument(let message): message
        }
    }
}

public enum GrammarLanguageDocumentationPipeline {
    public static func build(
        from compilation: GrammarCompilation, title: String = "Language Reference"
    ) throws -> GrammarLanguageDocumentation {
        guard let grammar = compilation.parsedGrammar else {
            throw GrammarGeneratorRegistryError.compilationFailed(
                compilation.diagnostics.first?.message ?? "The grammar did not compile."
            )
        }
        let exploration = try GrammarInteractiveExplorer.snapshot(compilation)
        _ = try GrammarEngineering.analyze(compilation)
        let terminals = Set(grammar.terminals)
        let productions = Dictionary(grouping: grammar.productions, by: \.lhs)
        let rules = exploration.rules.map { rule in
            GrammarLanguageDocumentationRule(
                id: rule.id, anchor: anchor(for: rule.id),
                productions: (productions[rule.id] ?? []).map { production in
                    .init(
                        id: production.id, text: production.text,
                        symbols: production.rhs.map {
                            .init(name: $0, kind: terminals.contains($0) ? .terminal : .nonterminal)
                        },
                        sourceRange: production.range
                    )
                },
                incomingRules: rule.incomingRules, outgoingRules: rule.outgoingRules,
                first: rule.first, follow: rule.follow,
                recursiveComponent: rule.recursiveComponent, isStart: rule.isStart,
                isReachable: rule.isReachable, isProductive: rule.isProductive,
                isNullable: rule.isNullable, isRecursive: rule.isRecursive
            )
        }
        let document = GrammarLanguageDocumentation(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Language Reference" : title,
            sourceFingerprint: fingerprint(compilation.request.source),
            startRule: grammar.startSymbol, terminals: grammar.terminals.sorted(), rules: rules
        )
        try validate(document)
        return document
    }

    public static func validate(_ document: GrammarLanguageDocumentation) throws {
        guard document.schemaVersion == GrammarLanguageDocumentation.currentSchemaVersion else {
            throw GrammarLanguageDocumentationError.unsupportedSchema(document.schemaVersion)
        }
        guard !document.title.isEmpty, !document.sourceFingerprint.isEmpty,
              !document.startRule.isEmpty, !document.rules.isEmpty else {
            throw GrammarLanguageDocumentationError.invalidDocument("Language documentation metadata is incomplete.")
        }
        let names = Set(document.rules.map(\.id))
        guard names.count == document.rules.count, names.contains(document.startRule),
              Set(document.rules.map(\.anchor)).count == document.rules.count else {
            throw GrammarLanguageDocumentationError.invalidDocument("Language documentation contains duplicate or unresolved rule identities.")
        }
        let terminalNames = Set(document.terminals)
        guard document.rules.allSatisfy({ rule in
            !rule.id.isEmpty && !rule.anchor.isEmpty
                && rule.productions.allSatisfy { production in
                    production.symbols.allSatisfy {
                        $0.kind == .terminal ? terminalNames.contains($0.name) : names.contains($0.name)
                    }
                }
                && rule.incomingRules.allSatisfy(names.contains)
                && rule.outgoingRules.allSatisfy(names.contains)
        }) else {
            throw GrammarLanguageDocumentationError.invalidDocument("Language documentation contains an unresolved symbol or rule link.")
        }
    }

    public static func encode(_ document: GrammarLanguageDocumentation) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> GrammarLanguageDocumentation {
        let value = try JSONDecoder().decode(GrammarLanguageDocumentation.self, from: data)
        try validate(value)
        return value
    }

    public static func renderMarkdown(
        _ document: GrammarLanguageDocumentation, includeDiagrams: Bool = true
    ) throws -> String {
        try validate(document)
        var output = "# \(document.title)\n\n"
        output += "Start rule: `\(markdown(document.startRule))`  \n"
        output += "Source fingerprint: `\(document.sourceFingerprint)`\n\n"
        output += "## Rules\n\n"
        output += document.rules.map { "- [\(markdown($0.id))](#\($0.anchor))" }.joined(separator: "\n") + "\n\n"
        for rule in document.rules {
            output += "<a id=\"\(rule.anchor)\"></a>\n\n## `\(markdown(rule.id))`\n\n"
            output += status(rule).joined(separator: " · ") + "\n\n"
            if includeDiagrams {
                output += "```text\n\(ascii(rule))\n```\n\n"
            }
            output += "### Productions\n\n"
            for production in rule.productions {
                output += "- `\(markdown(production.text))` (production \(production.id), line \(production.sourceRange.start.line))\n"
            }
            output += "\n"
            output += linkedList("References", values: rule.outgoingRules, document: document)
            output += linkedList("Referenced by", values: rule.incomingRules, document: document)
            output += "- FIRST: \(codeList(rule.first))\n- FOLLOW: \(codeList(rule.follow))\n\n"
        }
        return output
    }

    public static func renderHTML(
        _ document: GrammarLanguageDocumentation, includeDiagrams: Bool = true
    ) throws -> String {
        try validate(document)
        let navigation = document.rules.map {
            "<li><a href=\"#\($0.anchor)\">\(html($0.id))</a></li>"
        }.joined()
        let sections = document.rules.map { rule in
            let productions = rule.productions.map {
                "<li><code>\(html($0.text))</code> <small>production \($0.id), line \($0.sourceRange.start.line)</small></li>"
            }.joined()
            let outgoing = htmlLinks(rule.outgoingRules, document: document)
            let incoming = htmlLinks(rule.incomingRules, document: document)
            let diagram = includeDiagrams ? "<div class=\"diagram\" role=\"img\" aria-label=\"Railroad diagram for \(html(rule.id))\">\(svg(rule))</div>" : ""
            return """
            <section id="\(rule.anchor)"><h2><code>\(html(rule.id))</code></h2>
            <p>\(status(rule).map(html).joined(separator: " · "))</p>\(diagram)
            <h3>Productions</h3><ul>\(productions)</ul>
            <dl><dt>References</dt><dd>\(outgoing)</dd><dt>Referenced by</dt><dd>\(incoming)</dd>
            <dt>FIRST</dt><dd>\(htmlCodeList(rule.first))</dd><dt>FOLLOW</dt><dd>\(htmlCodeList(rule.follow))</dd></dl></section>
            """
        }.joined(separator: "\n")
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <title>\(html(document.title))</title><style>
        :root{color-scheme:light dark}body{font:16px system-ui;margin:auto;max-width:1100px;padding:24px;line-height:1.5}code{font-family:ui-monospace,monospace}nav ul{columns:3}section{border-top:1px solid #8886;padding:20px 0}.diagram{overflow:auto;padding:12px;border:1px solid #8886;border-radius:8px}.diagram svg{max-width:none}dt{font-weight:700;margin-top:8px}dd{margin-left:0}@media(max-width:700px){nav ul{columns:1}}
        </style></head><body><header><h1>\(html(document.title))</h1><p>Start rule: <code>\(html(document.startRule))</code><br><small>Source fingerprint: <code>\(html(document.sourceFingerprint))</code></small></p></header>
        <nav aria-label="Grammar rules"><h2>Rules</h2><ul>\(navigation)</ul></nav><main>\(sections)</main></body></html>
        """
    }

    private static func diagram(_ rule: GrammarLanguageDocumentationRule) -> any DiagramModel {
        let alternatives: [any DiagramModel] = rule.productions.map { production in
            guard !production.symbols.isEmpty else { return Sequence(elements: [Skip(content: "ε")]) }
            let symbols: [any DiagramModel] = production.symbols.map {
                if $0.kind == .terminal { return Terminal(name: $0.name) }
                return NonTerminal(name: $0.name)
            }
            return Sequence(elements: symbols)
        }
        let child: any DiagramModel = alternatives.count == 1 ? alternatives[0] : Choice(alternatives: alternatives)
        return Diagram(title: rule.id, child: child)
    }

    private static func ascii(_ rule: GrammarLanguageDocumentationRule) -> String {
        ASCIIRenderer().render(model: diagram(rule), maxWidth: 120)
    }

    private static func svg(_ rule: GrammarLanguageDocumentationRule) -> String {
        SVGRenderer().render(model: diagram(rule), maxWidth: 900)
    }

    private static func anchor(for value: String) -> String {
        "rule-" + value.utf8.map { String(format: "%02x", $0) }.joined()
    }

    private static func status(_ rule: GrammarLanguageDocumentationRule) -> [String] {
        let values = [rule.isStart ? "start rule" : nil, rule.isNullable ? "nullable" : nil,
                      rule.isRecursive ? "recursive" : nil, rule.isReachable ? "reachable" : "unreachable",
                      rule.isProductive ? "productive" : "unproductive"]
        return values.compactMap { $0 }
    }

    private static func linkedList(_ label: String, values: [String], document: GrammarLanguageDocumentation) -> String {
        let anchors = Dictionary(uniqueKeysWithValues: document.rules.map { ($0.id, $0.anchor) })
        let rendered = values.isEmpty ? "none" : values.map { "[\(markdown($0))](#\(anchors[$0]!))" }.joined(separator: ", ")
        return "- \(label): \(rendered)\n"
    }

    private static func htmlLinks(_ values: [String], document: GrammarLanguageDocumentation) -> String {
        let anchors = Dictionary(uniqueKeysWithValues: document.rules.map { ($0.id, $0.anchor) })
        return values.isEmpty ? "none" : values.map { "<a href=\"#\(anchors[$0]!)\"><code>\(html($0))</code></a>" }.joined(separator: ", ")
    }

    private static func codeList(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.map { "`\(markdown($0))`" }.joined(separator: ", ")
    }

    private static func htmlCodeList(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.map { "<code>\(html($0))</code>" }.joined(separator: ", ")
    }

    private static func markdown(_ value: String) -> String {
        value.replacingOccurrences(of: "`", with: "\\`")
    }

    private static func html(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func fingerprint(_ source: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in source.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
}

public struct LanguageDocumentationGrammarGenerator: GrammarGenerator {
    public let descriptor = GrammarGeneratorDescriptor(
        id: "language-documentation", displayName: "Language Documentation",
        summary: "A linked language reference with railroad diagrams and a versioned manifest.",
        defaultFileExtension: "html", mediaType: "text/html",
        options: [
            .init(name: "title", summary: "Document title.", defaultValue: "Language Reference"),
            .init(name: "format", summary: "Output format.", defaultValue: "bundle", allowedValues: ["html", "markdown", "json", "bundle"]),
            .init(name: "diagrams", summary: "Include railroad diagrams.", defaultValue: "true", allowedValues: ["true", "false"])
        ]
    )

    public init() {}

    public func generate(from compilation: GrammarCompilation, options: GrammarGeneratorOptions) throws -> GrammarGenerationResult {
        let document = try GrammarLanguageDocumentationPipeline.build(
            from: compilation, title: options["title"] ?? "Language Reference"
        )
        let format = options["format"] ?? "bundle"
        let diagrams = options["diagrams"] != "false"
        var files: [GrammarGeneratedFile] = []
        if format == "html" || format == "bundle" {
            files.append(.init(suggestedFilename: "LanguageReference.html", mediaType: "text/html", text: try GrammarLanguageDocumentationPipeline.renderHTML(document, includeDiagrams: diagrams)))
        }
        if format == "markdown" || format == "bundle" {
            files.append(.init(suggestedFilename: "LanguageReference.md", mediaType: "text/markdown", text: try GrammarLanguageDocumentationPipeline.renderMarkdown(document, includeDiagrams: diagrams)))
        }
        if format == "json" || format == "bundle" {
            files.append(.init(suggestedFilename: "LanguageReference.json", mediaType: "application/json", contents: try GrammarLanguageDocumentationPipeline.encode(document)))
        }
        return .init(generator: descriptor, files: files)
    }
}

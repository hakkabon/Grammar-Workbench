import Foundation
import GrammarDiagramKit

public struct GrammarDiagramElementSelection: Hashable, Sendable {
    public let elementID: DiagramElementID
    public let rule: String
    public let productionID: Int
    public let symbolIndex: Int?
    public let symbol: String?
    public let sourceRange: SourceRange

    public init(
        elementID: DiagramElementID, rule: String, productionID: Int,
        symbolIndex: Int?, symbol: String?, sourceRange: SourceRange
    ) {
        self.elementID = elementID; self.rule = rule; self.productionID = productionID
        self.symbolIndex = symbolIndex; self.symbol = symbol; self.sourceRange = sourceRange
    }
}

/// A DiagramKit model paired with the source identities needed by an editor.
/// The model remains renderer-neutral and can be sent to SVG, ASCII, HTML,
/// SwiftUI, UIKit, or PDF without rebuilding the grammar adapter.
public struct GrammarRuleDiagram: Sendable {
    public let rule: String
    public let model: any DiagramModel
    public let selections: [DiagramElementID: GrammarDiagramElementSelection]

    public func selection(for id: DiagramElementID) -> GrammarDiagramElementSelection? {
        selections[id]
    }
}

public enum GrammarDiagramAdapter {
    public static func availableRules(in compilation: GrammarCompilation) -> [String] {
        guard let grammar = compilation.parsedGrammar else { return [] }
        let declared = Set(grammar.productions.map(\.lhs))
        return grammar.nonterminals.filter(declared.contains)
            + declared.subtracting(grammar.nonterminals).sorted()
    }

    public static func diagram(
        for rule: String, in compilation: GrammarCompilation
    ) -> GrammarRuleDiagram? {
        guard let grammar = compilation.parsedGrammar else { return nil }
        let productions = grammar.productions.filter { $0.lhs == rule }
        guard !productions.isEmpty else { return nil }
        let terminals = Set(grammar.terminals)
        var selections: [DiagramElementID: GrammarDiagramElementSelection] = [:]
        let hasChoice = productions.count > 1

        func path(production: Int, symbol: Int?) -> DiagramElementID {
            var values = [0]
            if hasChoice { values.append(production) }
            if let symbol { values.append(symbol) }
            return DiagramElementID(path: values)
        }

        let alternatives: [any DiagramModel] = productions.enumerated().map { productionIndex, production in
            let productionPath = path(production: productionIndex, symbol: nil)
            selections[productionPath] = .init(
                elementID: productionPath, rule: rule, productionID: production.id,
                symbolIndex: nil, symbol: nil, sourceRange: production.range
            )
            guard !production.rhs.isEmpty else {
                let epsilonID = DiagramElementID(path: productionPath.path + [0])
                selections[epsilonID] = .init(
                    elementID: epsilonID, rule: rule, productionID: production.id,
                    symbolIndex: nil, symbol: "ε", sourceRange: production.range
                )
                return Sequence(elements: [Skip(content: "ε")])
            }
            let elements: [any DiagramModel] = production.rhs.enumerated().map { symbolIndex, symbol in
                let id = path(production: productionIndex, symbol: symbolIndex)
                selections[id] = .init(
                    elementID: id, rule: rule, productionID: production.id,
                    symbolIndex: symbolIndex, symbol: symbol, sourceRange: production.range
                )
                return terminals.contains(symbol)
                    ? Terminal(name: symbol)
                    : NonTerminal(name: symbol)
            }
            return Sequence(elements: elements)
        }
        let body: any DiagramModel = alternatives.count == 1
            ? alternatives[0]
            : Choice(alternatives: alternatives)
        return .init(
            rule: rule,
            model: Diagram(title: rule, child: body),
            selections: selections
        )
    }
}

public enum GrammarWorkbenchConsoleEntryKind: String, Hashable, Codable, Sendable {
    case input, result, information, error
}

public struct GrammarWorkbenchConsoleEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let kind: GrammarWorkbenchConsoleEntryKind
    public let text: String
    public let parse: GrammarParseResult?

    public init(id: Int, kind: GrammarWorkbenchConsoleEntryKind, text: String,
                parse: GrammarParseResult? = nil) {
        self.id = id; self.kind = kind; self.text = text; self.parse = parse
    }
}

/// Stateful parse console for the Workbench UI. This is not the ecosystem's
/// Grammar-REPL command or transcript model; Grammar-REPL owns those contracts.
/// Parsing delegates to the same immutable compilation used by the Workbench.
public struct GrammarWorkbenchConsoleSession: Sendable {
    public let compilation: GrammarCompilation
    public private(set) var entries: [GrammarWorkbenchConsoleEntry] = []
    public private(set) var selectedRule: String?
    private var nextID = 0

    public init(compilation: GrammarCompilation, selectedRule: String? = nil) {
        self.compilation = compilation
        let rules = GrammarDiagramAdapter.availableRules(in: compilation)
        self.selectedRule = selectedRule.flatMap { rules.contains($0) ? $0 : nil }
            ?? rules.first
    }

    @available(*, deprecated, renamed: "entries")
    public var transcript: [GrammarWorkbenchConsoleEntry] { entries }

    @discardableResult
    public mutating func submit(_ rawInput: String) -> [GrammarWorkbenchConsoleEntry] {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return [] }
        if input == ":clear" {
            entries.removeAll(keepingCapacity: true)
            return []
        }

        var emitted = [entry(.input, input)]
        if input.hasPrefix(":") {
            emitted.append(command(input))
        } else {
            let parse = compilation.parse(input)
            let kind: GrammarWorkbenchConsoleEntryKind = switch parse.status {
            case .accepted, .acceptedWithRecovery: .result
            case .rejected, .conflict, .looping, .invalidGrammar: .error
            }
            var lines = [parse.message]
            if !parse.tokens.isEmpty {
                lines.append("tokens: " + parse.tokens.map(\.kind).joined(separator: " "))
            }
            if !parse.expectedTerminals.isEmpty {
                lines.append("expected: " + parse.expectedTerminals.joined(separator: ", "))
            }
            if let tree = parse.tree { lines.append(tree) }
            emitted.append(entry(kind, lines.joined(separator: "\n"), parse: parse))
        }
        entries.append(contentsOf: emitted)
        return emitted
    }

    private mutating func command(_ input: String) -> GrammarWorkbenchConsoleEntry {
        let fields = input.split(maxSplits: 1, whereSeparator: \Character.isWhitespace)
        switch fields.first.map(String.init) {
        case ":help":
            return entry(.information, ":help · :rules · :rule <name> · :history · :clear")
        case ":rules":
            return entry(.information, GrammarDiagramAdapter.availableRules(in: compilation).joined(separator: "\n"))
        case ":history":
            let values = entries.filter { $0.kind == .input }.map(\.text)
            return entry(.information, values.isEmpty ? "No input history." : values.joined(separator: "\n"))
        case ":rule":
            guard fields.count == 2 else { return entry(.error, "Usage: :rule <name>") }
            let name = String(fields[1])
            guard GrammarDiagramAdapter.availableRules(in: compilation).contains(name) else {
                return entry(.error, "Unknown rule ‘\(name)’.")
            }
            selectedRule = name
            return entry(.information, "Selected rule ‘\(name)’.")
        default:
            return entry(.error, "Unknown command. Enter :help for available commands.")
        }
    }

    private mutating func entry(
        _ kind: GrammarWorkbenchConsoleEntryKind, _ text: String, parse: GrammarParseResult? = nil
    ) -> GrammarWorkbenchConsoleEntry {
        defer { nextID += 1 }
        return .init(id: nextID, kind: kind, text: text, parse: parse)
    }
}

@available(*, deprecated, renamed: "GrammarWorkbenchConsoleEntryKind")
public typealias GrammarREPLTranscriptKind = GrammarWorkbenchConsoleEntryKind

@available(*, deprecated, renamed: "GrammarWorkbenchConsoleEntry")
public typealias GrammarREPLTranscriptEntry = GrammarWorkbenchConsoleEntry

@available(*, deprecated, renamed: "GrammarWorkbenchConsoleSession")
public typealias GrammarREPLSession = GrammarWorkbenchConsoleSession

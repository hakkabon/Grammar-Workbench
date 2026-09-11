import Foundation

public struct GrammarQuickFix: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let replacementRange: Range<Int>
    public let replacement: String

    public init(id: String, title: String, replacementRange: Range<Int>, replacement: String) {
        self.id = id; self.title = title
        self.replacementRange = replacementRange; self.replacement = replacement
    }

    public func applying(to source: String) -> String {
        guard replacementRange.lowerBound >= 0,
              replacementRange.upperBound <= source.count,
              let lower = source.index(source.startIndex, offsetBy: replacementRange.lowerBound, limitedBy: source.endIndex),
              let upper = source.index(source.startIndex, offsetBy: replacementRange.upperBound, limitedBy: source.endIndex) else {
            return source
        }
        var result = source
        result.replaceSubrange(lower..<upper, with: replacement)
        return result
    }
}

public enum GrammarEditorIntelligence {
    public static func completions(
        for result: GrammarFrontEndResult,
        notation: GrammarSourceNotation = .workbench
    ) -> [String] {
        if notation == .ebnf {
            let nonterminals = (result.grammar?.nonterminals ?? []).filter { !$0.hasPrefix("__ebnf_") }
            return Array(Set(["lexical", "ε"] + nonterminals + (result.grammar?.terminals ?? []))).sorted()
        }
        let directives = ["%start", "%token", "%skip", "%mode", "%begin", "%push", "%pop", "%left", "%right", "%nonassoc", "%expect"]
        return Array(Set(directives + (result.grammar?.nonterminals ?? []) + (result.grammar?.terminals ?? []))).sorted()
    }

    public static func quickFixes(
        for diagnostic: GrammarDiagnostic, source: String,
        notation: GrammarSourceNotation = .workbench
    ) -> [GrammarQuickFix] {
        if notation == .ebnf {
            if diagnostic.code == "undefined-ebnf-symbol",
               let symbol = quotedSymbol(in: diagnostic.message) {
                let separator = source.isEmpty || source.hasSuffix("\n") ? "" : "\n"
                return [.init(
                    id: "define-ebnf-\(symbol)", title: "Add production for ‘\(symbol)’",
                    replacementRange: source.count..<source.count,
                    replacement: "\(separator)\(symbol) = ;\n"
                )]
            }
            let closers: [(String, String)] = [
                ("closing ']'", "]"), ("closing '}'", "}"), ("closing ')'", ")"),
                ("closing ‘]’", "]"), ("closing ‘}’", "}"), ("closing ‘)’", ")")
            ]
            if let closer = closers.first(where: { diagnostic.message.contains($0.0) })?.1 {
                var offset = min(diagnostic.range.start.offset, source.count)
                let prefix = String(source.prefix(offset))
                if let terminator = prefix.lastIndex(where: { !$0.isWhitespace }), prefix[terminator] == ";" {
                    offset = prefix.distance(from: prefix.startIndex, to: terminator)
                }
                return [.init(
                    id: "close-ebnf-\(closer)-\(offset)", title: "Insert missing ‘\(closer)’",
                    replacementRange: offset..<offset, replacement: closer
                )]
            }
            return []
        }
        if diagnostic.code == "undefined-symbol",
           diagnostic.range.start.offset < diagnostic.range.end.offset,
           diagnostic.range.end.offset <= source.count,
           let start = source.index(source.startIndex, offsetBy: diagnostic.range.start.offset, limitedBy: source.endIndex),
           let end = source.index(source.startIndex, offsetBy: diagnostic.range.end.offset, limitedBy: source.endIndex) {
            let symbol = String(source[start..<end])
            return [.init(
                id: "declare-token-\(symbol)",
                title: "Declare ‘\(symbol)’ with %token",
                replacementRange: 0..<0,
                replacement: "%token \(symbol)\n"
            )]
        }
        if diagnostic.message.hasPrefix("Expected ‘;’") {
            let offset = min(diagnostic.range.start.offset, source.count)
            return [.init(id: "insert-semicolon-\(offset)", title: "Insert missing ‘;’", replacementRange: offset..<offset, replacement: ";")]
        }
        if diagnostic.message.hasPrefix("Expected ‘:’ after nonterminal") {
            let offset = min(diagnostic.range.start.offset, source.count)
            return [.init(id: "insert-colon-\(offset)", title: "Insert missing ‘:’", replacementRange: offset..<offset, replacement: ": ")]
        }
        if diagnostic.message.hasPrefix("Unknown directive") {
            let range = diagnostic.range.start.offset..<diagnostic.range.end.offset
            return ["%start", "%token", "%skip", "%mode", "%begin", "%push", "%pop", "%left", "%right", "%nonassoc", "%expect"].map {
                .init(id: "replace-directive-\($0)", title: "Replace with \($0)", replacementRange: range, replacement: $0)
            }
        }
        return []
    }

    private static func quotedSymbol(in message: String) -> String? {
        guard let opening = message.firstIndex(of: "‘"),
              let closing = message[message.index(after: opening)...].firstIndex(of: "’") else { return nil }
        return String(message[message.index(after: opening)..<closing])
    }
}

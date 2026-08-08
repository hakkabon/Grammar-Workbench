import Foundation
import GrammarWorkbench
import LanguageServerProtocol

/// LSP features for grammar documents themselves. These deliberately reuse
/// the same notation-aware intelligence as the native editor.
public enum GrammarDocumentService {
    public static func completions(
        text: String, position: Position, notation: GrammarSourceNotation
    ) -> CompletionList {
        let result = GrammarFrontEnd.process(text, notation: notation)
        let values = GrammarEditorIntelligence.completions(for: result, notation: notation)
        let range = wordRange(text: text, position: position)
        let query = substring(text: text, range: range)
        let matches = values.filter {
            query.isEmpty || $0.range(of: query, options: [.anchored, .caseInsensitive]) != nil
        }
        return .init(isIncomplete: false, items: matches.map { value in
            CompletionItem(
                label: value,
                kind: value.hasPrefix("%") || value == "lexical" ? .keyword : .reference,
                textEdit: .textEdit(.init(range: range, newText: value))
            )
        })
    }

    public static func definition(
        uri: DocumentURI, text: String, position: Position, notation: GrammarSourceNotation
    ) -> LocationsOrLocationLinksResponse? {
        guard let name = word(at: position, in: text) else { return nil }
        let result = GrammarFrontEnd.process(text, notation: notation)
        let production = (result.grammar?.productions ?? []).first { $0.lhs == name }?.range
        let token = (result.grammar?.tokenDeclarations ?? []).first { $0.name == name }?.range
        let ranges = [production, token].compactMap { $0 }
        guard !ranges.isEmpty else { return nil }
        return .locations(ranges.map { Location(uri: uri, range: lspRange($0)) })
    }

    public static func codeActions(
        uri: DocumentURI, text: String, notation: GrammarSourceNotation,
        requestedRange: Range<Position>
    ) -> CodeActionRequestResponse? {
        let result = GrammarFrontEnd.process(text, notation: notation)
        let actions = result.diagnostics.flatMap { diagnostic -> [CodeAction] in
            let range = lspRange(diagnostic.range)
            guard overlaps(range, requestedRange) else { return [] }
            return GrammarEditorIntelligence.quickFixes(
                for: diagnostic, source: text, notation: notation
            ).map { fix in
                let edit = TextEdit(
                    range: lspRange(fix.replacementRange, in: text), newText: fix.replacement
                )
                return CodeAction(
                    title: fix.title, kind: .quickFix, isPreferred: true,
                    edit: WorkspaceEdit(changes: [uri: [edit]])
                )
            }
        }
        return actions.isEmpty ? nil : .codeActions(actions)
    }

    private static func word(at position: Position, in text: String) -> String? {
        let range = wordRange(text: text, position: position)
        let value = substring(text: text, range: range)
        return value.isEmpty ? nil : value
    }

    private static func wordRange(text: String, position: Position) -> Range<Position> {
        let nsText = text as NSString
        let cursor = utf16Offset(position, in: nsText)
        var lower = cursor
        var upper = cursor
        while lower > 0, isIdentifier(nsText.character(at: lower - 1)) { lower -= 1 }
        while upper < nsText.length, isIdentifier(nsText.character(at: upper)) { upper += 1 }
        return lspPosition(lower, in: nsText)..<lspPosition(upper, in: nsText)
    }

    private static func substring(text: String, range: Range<Position>) -> String {
        let nsText = text as NSString
        let lower = utf16Offset(range.lowerBound, in: nsText)
        let upper = utf16Offset(range.upperBound, in: nsText)
        return nsText.substring(with: NSRange(location: lower, length: upper - lower))
    }

    private static func isIdentifier(_ value: unichar) -> Bool {
        value == 0x25 || value == 0x5F || value >= 0x80
            || (value >= 0x30 && value <= 0x39)
            || (value >= 0x41 && value <= 0x5A)
            || (value >= 0x61 && value <= 0x7A)
    }

    private static func utf16Offset(_ position: Position, in text: NSString) -> Int {
        var line = 0
        var offset = 0
        while line < position.line, offset < text.length {
            offset = NSMaxRange(text.lineRange(for: NSRange(location: offset, length: 0)))
            line += 1
        }
        return min(offset + position.utf16index, text.length)
    }

    private static func lspPosition(_ offset: Int, in text: NSString) -> Position {
        var line = 0
        var lineStart = 0
        var index = 0
        while index < min(offset, text.length) {
            if text.character(at: index) == 0x0A { line += 1; lineStart = index + 1 }
            index += 1
        }
        return .init(line: line, utf16index: offset - lineStart)
    }

    private static func lspRange(_ range: SourceRange) -> Range<Position> {
        DiagnosticsManager.position(range.start)..<DiagnosticsManager.position(range.end)
    }

    private static func lspRange(_ range: Range<Int>, in text: String) -> Range<Position> {
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        let nsText = text as NSString
        return lspPosition(text[..<lower].utf16.count, in: nsText)
            ..< lspPosition(text[..<upper].utf16.count, in: nsText)
    }

    private static func overlaps(_ lhs: Range<Position>, _ rhs: Range<Position>) -> Bool {
        lhs.lowerBound <= rhs.upperBound && rhs.lowerBound <= lhs.upperBound
    }
}

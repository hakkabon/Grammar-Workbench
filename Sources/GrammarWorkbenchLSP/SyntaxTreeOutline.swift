import Foundation
import GrammarWorkbench
import LanguageServerProtocol

/// Folding ranges and document symbols derived from a concrete syntax tree.
///
/// Grammar documents are compiled, and source documents are parsed with the
/// grammar associated with their language id. The resulting `GrammarSyntaxNode`
/// tree is walked once, converting engine source ranges (one-based
/// lines/columns) into LSP positions (zero-based).
///
/// Trees produced by grammars without lexer rules carry no token ranges (the
/// sample tokenizer does not record positions). For those, the walk aligns each
/// terminal's lexeme with the document text and computes ranges on the fly, so
/// folding and symbols work for both lexer-based and plain grammars.
public struct SyntaxTreeOutline {
    /// Folding ranges for every non-terminal node spanning more than one line.
    public let foldingRanges: [FoldingRange]

    /// Hierarchical symbols for every non-terminal node, rooted at the
    /// start-symbol node's children.
    public let documentSymbols: [DocumentSymbol]

    private let tree: GrammarSyntaxNode
    private let text: String

    public init(tree: GrammarSyntaxNode, text: String) {
        self.tree = tree
        self.text = text
        var scanner = TokenPositionScanner(text: text)
        var ranges: [FoldingRange] = []
        var located: [(node: GrammarSyntaxNode, parent: GrammarSyntaxNode?, range: SourceRange, depth: Int)] = []
        let results = tree.children.map { $0.walk(scanner: &scanner, foldingRanges: &ranges, located: &located, parent: nil, depth: 0) }
        foldingRanges = ranges.sorted()
        documentSymbols = results.compactMap(\.symbol)
    }

    /// The deepest node whose source range contains `position`, together with
    /// its parent (for production context) and engine range. `nil` when the
    /// position falls outside the tree (whitespace, missing tokens, or a
    /// document that did not parse).
    public func node(at position: Position) -> (node: GrammarSyntaxNode, parent: GrammarSyntaxNode?, range: SourceRange)? {
        var scanner = TokenPositionScanner(text: text)
        var located: [(node: GrammarSyntaxNode, parent: GrammarSyntaxNode?, range: SourceRange, depth: Int)] = []
        var ignoredRanges: [FoldingRange] = []
        let target = SourcePosition(offset: 0, line: position.line + 1, column: position.utf16index + 1)
        _ = tree.walk(scanner: &scanner, foldingRanges: &ignoredRanges, located: &located, parent: nil, depth: 0)
        guard let match = located
            .filter({ contains($0.range, target) })
            .max(by: { $0.depth < $1.depth })
        else {
            return nil
        }
        return (match.node, match.parent, match.range)
    }
}

private func contains(_ range: SourceRange, _ position: SourcePosition) -> Bool {
    if range.start == range.end { return position == range.start }
    return positionIsLessThanOrEqualTo(range.start, position) && positionIsLessThan(position, range.end)
}

private func positionIsLessThanOrEqualTo(_ a: SourcePosition, _ b: SourcePosition) -> Bool {
    a.line < b.line || (a.line == b.line && a.column <= b.column)
}

private func positionIsLessThan(_ a: SourcePosition, _ b: SourcePosition) -> Bool {
    a.line < b.line || (a.line == b.line && a.column < b.column)
}

private extension GrammarSyntaxNode {
    /// Walks this subtree, aligning tokens with `text` when their ranges are
    /// missing. Appends folding ranges for multi-line non-terminals and every
    /// located node to `located`; returns this node's source range and
    /// document symbol.
    func walk(
        scanner: inout TokenPositionScanner,
        foldingRanges: inout [FoldingRange],
        located: inout [(node: GrammarSyntaxNode, parent: GrammarSyntaxNode?, range: SourceRange, depth: Int)],
        parent: GrammarSyntaxNode?,
        depth: Int
    ) -> (range: SourceRange?, symbol: DocumentSymbol?) {
        if isTerminal {
            let tokenRange: SourceRange?
            if let token, token.range == nil {
                tokenRange = scanner.consume(token.lexeme)
            } else {
                tokenRange = token?.range ?? range
            }
            if let tokenRange {
                located.append((node: self, parent: parent, range: tokenRange, depth: depth))
            }
            return (tokenRange, nil)
        }
        let results = children.map { $0.walk(scanner: &scanner, foldingRanges: &foldingRanges, located: &located, parent: self, depth: depth + 1) }
        let locatedChildren = results.compactMap(\.range)
        let nodeRange = locatedChildren.first.flatMap { first in
            locatedChildren.last.map { SourceRange(start: first.start, end: $0.end) }
        }
        if let nodeRange {
            let start = lspPosition(nodeRange.start)
            let end = lspPosition(nodeRange.end)
            if end.line > start.line {
                foldingRanges.append(FoldingRange(
                    startLine: start.line,
                    startUTF16Index: start.utf16index,
                    endLine: end.line,
                    endUTF16Index: end.utf16index,
                    collapsedText: symbol
                ))
            }
            located.append((node: self, parent: parent, range: nodeRange, depth: depth))
        }
        let childSymbols = results.compactMap(\.symbol)
        let documentSymbol = nodeRange.map { nodeRange in
            let range = lspRange(nodeRange)
            let selectionRange = locatedChildren.first.map(lspRange) ?? range
            return DocumentSymbol(
                name: symbol,
                kind: .struct,
                range: range,
                selectionRange: selectionRange,
                children: childSymbols.isEmpty ? nil : childSymbols
            )
        }
        return (nodeRange, documentSymbol)
    }
}

private func lspPosition(_ position: SourcePosition) -> Position {
    Position(line: max(0, position.line - 1), utf16index: max(0, position.column - 1))
}

private func lspRange(_ range: SourceRange) -> Range<Position> {
    lspPosition(range.start)..<lspPosition(range.end)
}

/// Aligns terminal lexemes with document text to recover source positions.
///
/// The engine's sample tokenizer yields whitespace-separated tokens without
/// ranges; the scanner consumes the document sequentially, skipping whitespace
/// and matching each lexeme (or its quoted form) at the current cursor.
struct TokenPositionScanner {
    private let characters: [Character]
    private var cursor = 0
    private var utf16Cursor = 0
    private var line = 1
    private var lineUTF16Start = 0

    init(text: String) {
        characters = Array(text)
    }

    /// Skips whitespace, matches the next occurrence of `lexeme` (or its
    /// quoted forms), and returns the token's engine-style range. When the
    /// lexeme cannot be aligned, a zero-width range at the cursor is returned.
    mutating func consume(_ lexeme: String) -> SourceRange {
        skipWhitespace()
        let start = position()
        let candidates = [lexeme, "'\(lexeme)'", "\"\(lexeme)\""]
        guard let match = candidates.first(where: { matches($0, at: cursor) }) else {
            return SourceRange(start: start, end: start)
        }
        advance(by: match)
        return SourceRange(start: start, end: position())
    }

    private func position() -> SourcePosition {
        SourcePosition(offset: cursor, line: line, column: utf16Cursor - lineUTF16Start + 1)
    }

    private func matches(_ candidate: String, at offset: Int) -> Bool {
        guard offset + candidate.count <= characters.count else { return false }
        return characters[offset..<(offset + candidate.count)].elementsEqual(candidate)
    }

    private mutating func skipWhitespace() {
        while cursor < characters.count, characters[cursor].isWhitespace {
            advanceOne()
        }
    }

    private mutating func advance(by candidate: String) {
        for _ in 0..<candidate.count {
            advanceOne()
        }
    }

    private mutating func advanceOne() {
        guard cursor < characters.count else { return }
        let character = characters[cursor]
        cursor += 1
        utf16Cursor += character.utf16.count
        if character == "\n" {
            line += 1
            lineUTF16Start = utf16Cursor
        }
    }
}

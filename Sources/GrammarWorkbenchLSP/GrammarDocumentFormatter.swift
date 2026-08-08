import Foundation
import GrammarWorkbench
import LanguageServerProtocol

/// Canonical formatting for workbench-notation grammar documents.
///
/// The formatter rewrites the document line by line, preserving the line
/// structure: every line's tokens are re-emitted with canonical spacing
/// (`S : A | B ;`, single spaces, directives at the start of the line),
/// leading indentation and trailing whitespace are removed, and comments are
/// kept. Lines that are already canonical produce no edit, so formatting is
/// idempotent and a canonical document formats to the empty edit set.
///
/// The tokenizer mirrors the notation's lexing rules so that terminal
/// literals (`'...'`, `"..."`), lexer patterns (`/.../`, which may contain
/// spaces), comments (`//`, `#`), and directives (`%name`) survive unchanged.
public enum GrammarDocumentFormatter {
    /// The edits that canonicalize `text`. When `range` is given (range
    /// formatting), only edits for lines within the range are returned.
    public static func format(
        _ text: String,
        options: FormattingOptions,
        range: Range<Position>? = nil
    ) -> [TextEdit] {
        let lines = text.components(separatedBy: "\n")
        var edits: [TextEdit] = []
        for (index, line) in lines.enumerated() {
            let canonical = canonicalLine(line)
            let length = (line as NSString).length
            if canonical != line, lineInRange(index, range: range, lastLine: lines.count - 1) {
                edits.append(TextEdit(
                    range: Position(line: index, utf16index: 0)..<Position(line: index, utf16index: length),
                    newText: canonical
                ))
            }
        }
        return edits
    }

    private static func lineInRange(_ line: Int, range: Range<Position>?, lastLine: Int) -> Bool {
        guard let range else { return true }
        let endLine = range.upperBound.utf16index == 0 && range.upperBound.line > range.lowerBound.line
            ? range.upperBound.line - 1
            : range.upperBound.line
        return line >= range.lowerBound.line && line <= min(endLine, lastLine)
    }

    // MARK: - Line canonicalization

    private enum Token {
        case directive(String)
        case word(String)
        case punctuation(String)
        case comment(String)
    }

    /// Re-emits the line's tokens with canonical spacing. Comments stay at
    /// the end of the line; a comment-only line is preserved as-is.
    private static func canonicalLine(_ line: String) -> String {
        let tokens = tokenize(line)
        guard !tokens.isEmpty else { return "" }
        var result = ""
        var comment: String?
        for token in tokens {
            switch token {
            case .comment(let text):
                comment = text.trimmingCharacters(in: .whitespaces)
            case .directive(let name):
                append("%\(name)", to: &result)
            case .word(let text):
                append(text, to: &result)
            case .punctuation(":"):
                appendPadded(":", to: &result)
            case .punctuation("|"):
                appendPadded("|", to: &result)
            case .punctuation(";"):
                append(";", to: &result)
            case .punctuation(let text):
                append(text, to: &result)
            }
        }
        result = result.trimmingCharacters(in: .whitespaces)
        if let comment {
            result = result.isEmpty ? comment : result + " \(comment)"
        }
        return result
    }

    /// Appends `text`, separated from the existing content by a single space.
    private static func append(_ text: String, to result: inout String) {
        if result.isEmpty || result.hasSuffix(" ") {
            result += text
        } else {
            result += " \(text)"
        }
    }

    /// Appends `text` surrounded by single spaces (` : `, ` | `).
    private static func appendPadded(_ text: String, to result: inout String) {
        append(text, to: &result)
        if !result.isEmpty, !result.hasSuffix(" ") {
            result += " "
        }
    }

    /// Tokenizes a single line with the notation's token shapes, preserving
    /// literal, pattern, and comment contents exactly.
    private static func tokenize(_ line: String) -> [Token] {
        let characters = Array(line)
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == " " || character == "\t" || character == "\r" {
                index += 1
            } else if character == "#" || (character == "/" && peek(1, at: index, in: characters) == "/") {
                tokens.append(.comment(String(characters[index...])))
                break
            } else if character == "/" {
                let start = index
                index += 1
                var escaped = false
                while index < characters.count {
                    if characters[index] == "/", !escaped { index += 1; break }
                    if characters[index] == "\\", !escaped { escaped = true } else { escaped = false }
                    index += 1
                }
                tokens.append(.word(String(characters[start..<index])))
            } else if character == "'" || character == "\"" {
                let quote = character
                let start = index
                index += 1
                var escaped = false
                while index < characters.count {
                    if characters[index] == quote, !escaped { index += 1; break }
                    if characters[index] == "\\", !escaped { escaped = true } else { escaped = false }
                    index += 1
                }
                tokens.append(.word(String(characters[start..<index])))
            } else if character == "%" {
                let start = index
                index += 1
                while index < characters.count, characters[index].isLetter { index += 1 }
                tokens.append(.directive(String(characters[(start + 1)..<index])))
            } else if isIdentifierStart(character) {
                let start = index
                index += 1
                while index < characters.count, isIdentifierCharacter(characters[index]) { index += 1 }
                tokens.append(.word(String(characters[start..<index])))
            } else if character == ":" || character == "|" || character == ";" {
                tokens.append(.punctuation(String(character)))
                index += 1
            } else {
                tokens.append(.word(String(character)))
                index += 1
            }
        }
        return tokens
    }

    private static func peek(_ offset: Int, at index: Int, in characters: [Character]) -> Character? {
        let target = index + offset
        return target < characters.count ? characters[target] : nil
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "′"
    }
}

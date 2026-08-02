import Foundation

public struct LexedToken: Identifiable, Hashable, Sendable {
    public let index: Int
    public let kind: String
    public let lexeme: String
    public let mode: String
    public let range: SourceRange
    public var id: Int { index }
}

public struct LexerDiagnostic: Identifiable, Hashable, Sendable {
    public let id: Int
    public let message: String
    public let mode: String
    public let range: SourceRange
}

public struct LexerResult: Sendable {
    public let source: String
    public let tokens: [LexedToken]
    public let diagnostics: [LexerDiagnostic]
    public let finalModeStack: [String]
    public var hasErrors: Bool { !diagnostics.isEmpty }
}

public enum GrammarLexerRuntime {
    private struct CompiledRule {
        let token: String?
        let expression: NSRegularExpression
        let order: Int
        let mode: String
        let action: LexerModeAction
    }

    public static func lex(_ source: String, grammar: ParsedGrammar) -> LexerResult {
        var rules: [CompiledRule] = grammar.lexerRules.enumerated().compactMap { offset, rule in
            guard let expression = try? NSRegularExpression(pattern: "(?:\(rule.pattern))") else { return nil }
            return CompiledRule(
                token: rule.token, expression: expression, order: offset,
                mode: rule.mode, action: rule.action
            )
        }
        let patternedTokens = Set(grammar.lexerRules.compactMap(\.token))
        for terminal in grammar.terminals where terminal != "$" && !patternedTokens.contains(terminal) {
            guard let expression = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: terminal)) else { continue }
            rules.append(.init(
                token: terminal, expression: expression, order: rules.count,
                mode: "DEFAULT", action: .none
            ))
        }

        let text = source as NSString
        var location = 0
        var output: [LexedToken] = []
        var diagnostics: [LexerDiagnostic] = []
        var modeStack = ["DEFAULT"]
        while location < text.length {
            let mode = modeStack.last ?? "DEFAULT"
            var best: (rule: CompiledRule, length: Int)?
            for rule in rules where rule.mode == mode {
                let available = NSRange(location: location, length: text.length - location)
                guard let match = rule.expression.firstMatch(in: source, options: [.anchored], range: available),
                      match.range.location == location, match.range.length > 0 else { continue }
                if best == nil || match.range.length > best!.length || (match.range.length == best!.length && rule.order < best!.rule.order) {
                    best = (rule, match.range.length)
                }
            }
            guard let best else {
                let length = max(1, text.rangeOfComposedCharacterSequence(at: location).length)
                let range = sourceRange(source, utf16Start: location, utf16End: min(text.length, location + length))
                let unexpected = text.substring(with: NSRange(location: location, length: length))
                diagnostics.append(.init(
                    id: diagnostics.count,
                    message: "No lexer rule in mode ‘\(mode)’ matches ‘\(unexpected)’.",
                    mode: mode, range: range
                ))
                location += length
                continue
            }
            let end = location + best.length
            if let token = best.rule.token {
                output.append(.init(
                    index: output.count,
                    kind: token,
                    lexeme: text.substring(with: NSRange(location: location, length: best.length)),
                    mode: mode,
                    range: sourceRange(source, utf16Start: location, utf16End: end)
                ))
            }
            switch best.rule.action {
            case .none:
                break
            case .begin(let target):
                modeStack[modeStack.count - 1] = target
            case .push(let target):
                modeStack.append(target)
            case .pop:
                if modeStack.count > 1 {
                    modeStack.removeLast()
                } else {
                    diagnostics.append(.init(
                        id: diagnostics.count,
                        message: "Lexer mode stack underflow while applying %pop.",
                        mode: mode, range: sourceRange(source, utf16Start: location, utf16End: end)
                    ))
                }
            }
            location = end
        }
        if modeStack != ["DEFAULT"] {
            diagnostics.append(.init(
                id: diagnostics.count,
                message: "Input ended in lexer mode ‘\(modeStack.last ?? "DEFAULT")’.",
                mode: modeStack.last ?? "DEFAULT",
                range: sourceRange(source, utf16Start: text.length, utf16End: text.length)
            ))
        }
        return LexerResult(
            source: source, tokens: output, diagnostics: diagnostics,
            finalModeStack: modeStack
        )
    }

    private static func sourceRange(_ source: String, utf16Start: Int, utf16End: Int) -> SourceRange {
        func position(_ offset: Int) -> SourcePosition {
            let prefix = (source as NSString).substring(to: offset)
            let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
            return SourcePosition(offset: offset, line: lines.count, column: (lines.last?.utf16.count ?? 0) + 1)
        }
        return SourceRange(start: position(utf16Start), end: position(utf16End))
    }
}

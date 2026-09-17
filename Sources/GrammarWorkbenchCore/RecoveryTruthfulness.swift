import Foundation
import Grammar
import Parser

enum GrammarRecoveryEvidence {
    /// LR-Parsing currently exposes recovery diagnostics rather than its edit
    /// buffer. Normalize their mutable-runtime positions back to positions in
    /// the original token stream at this boundary.
    static func edits(
        diagnostics: [ParserDiagnostic], frames: [ReplayFrame], originalTokens: [String]
    ) -> [GrammarRecoveryEdit] {
        var indexDelta = 0
        let recoveryFrames = frames.indices.filter { frames[$0].action.hasPrefix("recover:") }
        var recoveryFrameIndex = 0
        return diagnostics.compactMap { diagnostic in
            guard let recovery = diagnostic.recovery else { return nil }
            let frameIndex = recoveryFrames.indices.contains(recoveryFrameIndex)
                ? recoveryFrames[recoveryFrameIndex] : nil
            recoveryFrameIndex += 1
            switch recovery {
            case .insertedToken:
                let index = max(0, diagnostic.tokenIndex - indexDelta)
                indexDelta += 1
                guard let terminal = diagnostic.recoverySymbol else { return nil }
                return .insert(terminal: terminal, atToken: index)
            case .deletedToken:
                let index = max(0, diagnostic.tokenIndex - indexDelta)
                indexDelta -= 1
                let terminal = diagnostic.recoverySymbol ?? diagnostic.unexpected
                return .delete(terminal: terminal, atToken: index)
            case .synchronized:
                let count = frameIndex.flatMap { index -> Int? in
                    guard index > frames.startIndex else { return nil }
                    return max(
                        0,
                        frames[frames.index(before: index)].remainingInput.count
                            - frames[index].remainingInput.count
                    )
                } ?? 0
                let runtimeStart = max(0, diagnostic.tokenIndex - count)
                let start = max(0, runtimeStart - indexDelta)
                let end = min(originalTokens.count, start + count)
                return .skip(
                    terminals: start < end ? Array(originalTokens[start..<end]) : [],
                    fromToken: start
                )
            }
        }
    }
}

public enum GrammarRecoveryReplayError: Error, Equatable, LocalizedError, Sendable {
    case invalidInsertion(Int)
    case invalidDeletion(Int)
    case deletionMismatch(expected: String, actual: String)
    case invalidSkip(Int, Int)
    case skipMismatch(expected: [String], actual: [String])

    public var errorDescription: String? {
        switch self {
        case .invalidInsertion(let index): "Insertion position \(index) is outside the original token stream."
        case .invalidDeletion(let index): "Deletion position \(index) is outside the original token stream."
        case .deletionMismatch(let expected, let actual):
            "Deletion names ‘\(expected)’, but the original token is ‘\(actual)’."
        case .invalidSkip(let index, let count):
            "Skip of \(count) token(s) at \(index) is outside the original token stream."
        case .skipMismatch(let expected, let actual):
            "Skip names \(expected), but the original token slice is \(actual)."
        }
    }
}

public extension Array where Element == GrammarRecoveryEdit {
    /// Applies the edit script using its original-stream coordinates. This is
    /// deliberately strict: malformed evidence is rejected rather than made
    /// plausible by best-effort replay.
    func applying(to originalTokens: [String]) throws -> [String] {
        var repaired = originalTokens
        var offset = 0
        for edit in self {
            switch edit {
            case .insert(let terminal, let originalIndex):
                guard (0...originalTokens.count).contains(originalIndex) else {
                    throw GrammarRecoveryReplayError.invalidInsertion(originalIndex)
                }
                let index = originalIndex + offset
                guard (0...repaired.count).contains(index) else {
                    throw GrammarRecoveryReplayError.invalidInsertion(originalIndex)
                }
                repaired.insert(terminal, at: index)
                offset += 1
            case .delete(let terminal, let originalIndex):
                guard originalTokens.indices.contains(originalIndex) else {
                    throw GrammarRecoveryReplayError.invalidDeletion(originalIndex)
                }
                let actual = originalTokens[originalIndex]
                guard terminal == actual else {
                    throw GrammarRecoveryReplayError.deletionMismatch(
                        expected: terminal, actual: actual
                    )
                }
                let index = originalIndex + offset
                guard repaired.indices.contains(index) else {
                    throw GrammarRecoveryReplayError.invalidDeletion(originalIndex)
                }
                repaired.remove(at: index)
                offset -= 1
            case .skip(let terminals, let originalIndex):
                let end = originalIndex + terminals.count
                guard originalIndex >= 0, end <= originalTokens.count, !terminals.isEmpty else {
                    throw GrammarRecoveryReplayError.invalidSkip(originalIndex, terminals.count)
                }
                let actual: [String] = .init(originalTokens[originalIndex..<end])
                guard terminals == actual else {
                    throw GrammarRecoveryReplayError.skipMismatch(
                        expected: terminals, actual: actual
                    )
                }
                let index = originalIndex + offset
                guard index >= 0, index + terminals.count <= repaired.count else {
                    throw GrammarRecoveryReplayError.invalidSkip(originalIndex, terminals.count)
                }
                repaired.removeSubrange(index..<(index + terminals.count))
                offset -= terminals.count
            }
        }
        return repaired
    }
}

public struct GrammarRecoveryTruthViolation: Hashable, Codable, Sendable, Identifiable {
    public let code: String
    public let message: String
    public var id: String { code }
}

public struct GrammarRecoveryTruthCaseResult: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let input: String
    public let originalTokens: [String]
    public let repairedTokens: [String]?
    public let parseStatus: GrammarParseStatus
    public let strictReparseStatus: GrammarParseStatus?
    public let contract: ParseContractSnapshot
    public let missingTerminals: [String]
    public let recoveryTraceEvents: Int
    public let violations: [GrammarRecoveryTruthViolation]
    public var passed: Bool { violations.isEmpty }
}

public struct GrammarRecoveryTruthProgrammeReport: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-recovery-truth-report"

    public let schemaVersion: Int
    public let kind: String
    public let parserContractSchemaVersion: Int
    public let cases: [GrammarRecoveryTruthCaseResult]
    public var passed: Bool { !cases.isEmpty && cases.allSatisfy(\.passed) }
}

public enum GrammarRecoveryTruthVerifier {
    public static func verify(
        id: String,
        input: String,
        result: GrammarParseResult,
        strictReparse: GrammarParseResult? = nil
    ) -> GrammarRecoveryTruthCaseResult {
        let original = result.tokens.map(\.kind)
        var violations: [GrammarRecoveryTruthViolation] = []
        let repaired: [String]?
        do {
            repaired = try result.recoveryEdits.applying(to: original)
        } catch {
            repaired = nil
            violations.append(.init(code: "edit-replay", message: error.localizedDescription))
        }

        let recoveryDiagnostics = result.diagnostics.filter { $0.recovery != nil }
        if recoveryDiagnostics.count != result.recoveryEdits.count {
            violations.append(.init(
                code: "diagnostic-edit-cardinality",
                message: "\(recoveryDiagnostics.count) recovery diagnostics do not account for \(result.recoveryEdits.count) edits."
            ))
        }
        for (index, pair) in zip(recoveryDiagnostics, result.recoveryEdits).enumerated()
        where !diagnostic(pair.0, accountsFor: pair.1) {
            violations.append(.init(
                code: "diagnostic-edit-\(index)",
                message: "Recovery diagnostic \(index) does not describe edit \(index)."
            ))
        }
        let traceRecoveries = result.trace.filter { $0.action.hasPrefix("recover:") }.count
        if traceRecoveries != result.recoveryEdits.count {
            violations.append(.init(
                code: "trace-edit-cardinality",
                message: "\(traceRecoveries) recovery trace events do not account for \(result.recoveryEdits.count) edits."
            ))
        }
        if result.status == .acceptedWithRecovery && result.recoveryEdits.isEmpty {
            violations.append(.init(
                code: "recovered-without-edit",
                message: "The result claims successful recovery without a replayable edit."
            ))
        }
        if result.status == .accepted && !result.recoveryEdits.isEmpty {
            violations.append(.init(
                code: "accepted-hides-edit",
                message: "The result claims unmodified acceptance despite recovery edits."
            ))
        }

        let missing = missingTerminals(in: result.syntaxTree)
        let insertions = result.recoveryEdits.compactMap { edit -> String? in
            guard case .insert(let terminal, _) = edit else { return nil }
            return terminal
        }
        for terminal in insertions where !missing.contains(terminal) {
            violations.append(.init(
                code: "insertion-missing-node",
                message: "Inserted terminal ‘\(terminal)’ is absent from the recovered syntax tree."
            ))
        }

        if result.status == .acceptedWithRecovery {
            guard let strictReparse else {
                violations.append(.init(
                    code: "strict-reparse-missing",
                    message: "Successful recovery was not checked by reparsing its edited token stream."
                ))
                return makeResult()
            }
            if strictReparse.status != .accepted || !strictReparse.recoveryEdits.isEmpty {
                violations.append(.init(
                    code: "strict-reparse-failed",
                    message: "The replayed edit stream did not parse cleanly without recovery."
                ))
            }
        }

        return makeResult()

        func makeResult() -> GrammarRecoveryTruthCaseResult {
            let status: Parser.ParseStatus
            switch result.status {
            case .accepted: status = .accepted
            case .acceptedWithRecovery: status = .recovered
            case .rejected, .conflict, .looping, .invalidGrammar: status = .rejected
            }
            let parserEdits = result.recoveryEdits.map { edit -> ParseRecoveryEdit in
                switch edit {
                case .insert(let terminal, let index):
                    .insert(terminal: .literal(terminal), atToken: index)
                case .delete(let terminal, let index):
                    .delete(terminal: .literal(terminal), atToken: index)
                case .skip(let terminals, let index):
                    .skip(terminals: terminals.map(GrammarNormalizedTerminal.literal), fromToken: index)
                }
            }
            var replay = [ParseReplayEvent(step: 0, kind: .start, tokenIndex: 0)]
            for (index, edit) in result.recoveryEdits.enumerated() {
                replay.append(.init(
                    step: index + 1, kind: .recover, tokenIndex: tokenIndex(of: edit)
                ))
            }
            replay.append(.init(
                step: replay.count,
                kind: status == .rejected ? .reject : .accept,
                tokenIndex: original.count
            ))
            return .init(
                id: id, input: input, originalTokens: original, repairedTokens: repaired,
                parseStatus: result.status, strictReparseStatus: strictReparse?.status,
                contract: .init(
                    engine: .init(
                        identity: "grammar-workbench-lalr",
                        displayName: "Grammar Workbench LALR(1)", algorithm: "lalr"
                    ),
                    status: status, recoveryEdits: parserEdits, replay: replay
                ),
                missingTerminals: missing, recoveryTraceEvents: traceRecoveries,
                violations: violations
            )
        }
    }

    private static func missingTerminals(in node: GrammarSyntaxNode?) -> [String] {
        guard let node else { return [] }
        return (node.isMissing ? [node.symbol] : []) + node.children.flatMap { missingTerminals(in: $0) }
    }

    private static func tokenIndex(of edit: GrammarRecoveryEdit) -> Int {
        switch edit {
        case .insert(_, let index), .delete(_, let index), .skip(_, let index): index
        }
    }

    private static func diagnostic(
        _ diagnostic: GrammarSyntaxDiagnostic, accountsFor edit: GrammarRecoveryEdit
    ) -> Bool {
        switch edit {
        case .insert(let terminal, _):
            diagnostic.recovery == .insertedToken && diagnostic.recoverySymbol == terminal
        case .delete(let terminal, _):
            diagnostic.recovery == .deletedToken && diagnostic.recoverySymbol == terminal
        case .skip(let terminals, _):
            diagnostic.recovery == .synchronized
                && diagnostic.recoveryDetail?.contains("Discarded \(terminals.count) token") == true
        }
    }
}

public enum GrammarRecoveryTruthProgrammeError: Error, LocalizedError, Sendable {
    case compilationFailed(String)
    case editReplayFailed(String)

    public var errorDescription: String? {
        switch self {
        case .compilationFailed(let detail): "Recovery fixture did not compile: \(detail)"
        case .editReplayFailed(let detail): "Recovery edit replay failed: \(detail)"
        }
    }
}

/// Exercises insertion, deletion, panic synchronization, and a bounded failed
/// recovery through the production parser. Every successful repair is replayed
/// and reparsed with recovery disabled.
public enum GrammarRecoveryTruthProgramme {
    public static func run() throws -> GrammarRecoveryTruthProgrammeReport {
        let source = "%start S\nS : 'id' '+' 'id' ;"
        let compilation = try compile(source)
        let cases = try [
            recoveredCase(id: "insert-missing-terminal", input: "id id", compilation: compilation),
            recoveredCase(id: "delete-unexpected-terminal", input: "id extra + id", compilation: compilation),
            synchronizedCase(),
            boundedFailureCase(compilation: compilation),
        ]
        return .init(
            schemaVersion: GrammarRecoveryTruthProgrammeReport.currentSchemaVersion,
            kind: GrammarRecoveryTruthProgrammeReport.kindIdentifier,
            parserContractSchemaVersion: ParseContractSnapshot.currentSchemaVersion,
            cases: cases
        )
    }

    private static func recoveredCase(
        id: String, input: String, compilation: GrammarCompilation
    ) throws -> GrammarRecoveryTruthCaseResult {
        let result = compilation.parse(input)
        let repaired: [String]
        do { repaired = try result.recoveryEdits.applying(to: result.tokens.map(\.kind)) }
        catch { throw GrammarRecoveryTruthProgrammeError.editReplayFailed(error.localizedDescription) }
        let strict = compilation.parse(
            repaired.map(quotedToken).joined(separator: " "),
            options: .init(enablesRecovery: false)
        )
        return GrammarRecoveryTruthVerifier.verify(
            id: id, input: input, result: result, strictReparse: strict
        )
    }

    private static func synchronizedCase() throws -> GrammarRecoveryTruthCaseResult {
        let compilation = try compile("%start S\nS : 'id' ;")
        return try recoveredCase(
            id: "skip-to-synchronization", input: "id junk more", compilation: compilation
        )
    }

    private static func boundedFailureCase(
        compilation: GrammarCompilation
    ) -> GrammarRecoveryTruthCaseResult {
        let input = "junk id junk id"
        let result = compilation.parse(input, options: .init(maximumDiagnostics: 1))
        return GrammarRecoveryTruthVerifier.verify(
            id: "diagnostic-limit-remains-rejected", input: input, result: result
        )
    }

    private static func compile(_ source: String) throws -> GrammarCompilation {
        let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
        guard compilation.succeeded else {
            throw GrammarRecoveryTruthProgrammeError.compilationFailed(
                compilation.diagnostics.map(\.message).joined(separator: "; ")
            )
        }
        return compilation
    }

    private static func quotedToken(_ token: String) -> String {
        "'\(token.replacingOccurrences(of: "'", with: "\\'"))'"
    }
}

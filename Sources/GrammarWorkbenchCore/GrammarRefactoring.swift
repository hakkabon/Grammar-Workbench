import Foundation

public enum GrammarRefactoringKind: String, CaseIterable, Codable, Sendable {
    case renameSymbol
}

public struct GrammarRefactoringEdit: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let utf16Start: Int
    public let utf16Length: Int
    public let line: Int
    public let column: Int
    public let originalText: String
    public let replacementText: String
    public let reason: String
}

public struct GrammarRefactoringPlan: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let kind: GrammarRefactoringKind
    public let notation: GrammarSourceNotation
    public let sourceFingerprint: String
    public let oldName: String
    public let newName: String
    public let edits: [GrammarRefactoringEdit]
    public let explanation: String

    public var affectedOccurrences: Int { edits.count }
    public var affectedLines: [Int] { Array(Set(edits.map(\.line))).sorted() }
    public var hasChanges: Bool { !edits.isEmpty }
}

public enum GrammarRefactoringError: Error, LocalizedError, Equatable {
    case compilationFailed(String)
    case invalidIdentifier(String)
    case unknownSymbol(String)
    case symbolCollision(String)
    case sourceChanged
    case invalidEdit

    public var errorDescription: String? {
        switch self {
        case .compilationFailed(let message): message
        case .invalidIdentifier(let name): "‘\(name)’ is not a valid grammar identifier."
        case .unknownSymbol(let name): "The grammar has no renamable symbol named '\(name)'."
        case .symbolCollision(let name): "The grammar already declares a different symbol named '\(name)'."
        case .sourceChanged: "The grammar changed after this refactoring plan was created."
        case .invalidEdit: "The refactoring plan contains an invalid or overlapping source edit."
        }
    }
}

public struct GrammarRefactoringResult: Sendable {
    public let plan: GrammarRefactoringPlan
    public let proposedSource: String
    public let compilation: GrammarCompilation
    public let artifactDiff: GrammarArtifactDiff?
    public let behavior: GrammarBehaviorComparison
    public let testsBefore: WorkbenchTestReport?
    public let testsAfter: WorkbenchTestReport?

    public var isSafeToApply: Bool {
        compilation.succeeded && behavior.agreesOnCorpus && (testsAfter?.failed ?? 0) == 0
    }
}

public enum GrammarRefactoring {
    public static func planRename(
        from oldName: String,
        to newName: String,
        in compilation: GrammarCompilation
    ) throws -> GrammarRefactoringPlan {
        guard isIdentifier(oldName), isIdentifier(newName) else {
            throw GrammarRefactoringError.invalidIdentifier(isIdentifier(oldName) ? newName : oldName)
        }
        guard let grammar = compilation.parsedGrammar else {
            throw GrammarRefactoringError.compilationFailed(
                compilation.diagnostics.first(where: { $0.severity == .error })?.message ?? "The grammar did not compile."
            )
        }
        let nonterminals = Set(grammar.nonterminals)
        let terminals = Set(grammar.tokenDeclarations.map(\.name))
        guard nonterminals.contains(oldName) || terminals.contains(oldName) else {
            throw GrammarRefactoringError.unknownSymbol(oldName)
        }
        if oldName != newName,
           (nonterminals.contains(newName) || terminals.contains(newName)) {
            throw GrammarRefactoringError.symbolCollision(newName)
        }
        let source = compilation.request.source
        let occurrences = oldName == newName ? [] : identifierOccurrences(in: source).filter { $0.text == oldName }
        let edits = occurrences.map { occurrence in
            GrammarRefactoringEdit(
                id: "\(occurrence.location)-\(oldName)", utf16Start: occurrence.location,
                utf16Length: occurrence.length, line: occurrence.line, column: occurrence.column,
                originalText: oldName, replacementText: newName,
                reason: "Rename the grammar symbol consistently across declarations, references, and directives."
            )
        }
        return .init(
            id: "rename-\(oldName)-\(newName)-\(fingerprint(source))", kind: .renameSymbol,
            notation: compilation.request.notation, sourceFingerprint: fingerprint(source),
            oldName: oldName, newName: newName, edits: edits,
            explanation: "A source-preserving symbol rename. Terminal literals, lexer patterns, and comments are not changed."
        )
    }

    public static func apply(_ plan: GrammarRefactoringPlan, to source: String) throws -> String {
        guard fingerprint(source) == plan.sourceFingerprint else { throw GrammarRefactoringError.sourceChanged }
        let value = NSMutableString(string: source)
        let ordered = plan.edits.sorted { $0.utf16Start > $1.utf16Start }
        var previousStart = value.length
        for edit in ordered {
            let range = NSRange(location: edit.utf16Start, length: edit.utf16Length)
            guard range.location >= 0, NSMaxRange(range) <= value.length,
                  NSMaxRange(range) <= previousStart,
                  value.substring(with: range) == edit.originalText else {
                throw GrammarRefactoringError.invalidEdit
            }
            value.replaceCharacters(in: range, with: edit.replacementText)
            previousStart = range.location
        }
        return value as String
    }

    public static func execute(
        _ plan: GrammarRefactoringPlan,
        request: GrammarCompilationRequest,
        corpus: [GrammarBehaviorCorpusEntry] = [],
        tests: [WorkbenchTestCase] = [],
        options: GrammarBehaviorComparisonOptions = .init()
    ) throws -> GrammarRefactoringResult {
        let before = GrammarWorkbenchAPI.compile(request)
        let source = try apply(plan, to: request.source)
        let after = GrammarWorkbenchAPI.compile(.init(source: source, algorithm: request.algorithm, notation: request.notation))
        return .init(
            plan: plan, proposedSource: source, compilation: after,
            artifactDiff: try? after.diff(from: before),
            behavior: GrammarEngineering.compare(before, after, corpus: corpus, options: options),
            testsBefore: tests.isEmpty ? nil : before.runTests(tests),
            testsAfter: tests.isEmpty ? nil : after.runTests(tests)
        )
    }

    private struct Occurrence { let text: String; let location: Int; let length: Int; let line: Int; let column: Int }

    /// Scans identifiers while deliberately skipping quoted terminals, regex
    /// patterns, and line comments. Offsets use UTF-16 to match LSP and Cocoa.
    private static func identifierOccurrences(in source: String) -> [Occurrence] {
        let text = source as NSString
        var result: [Occurrence] = [], offset = 0, line = 1, column = 1
        func scalar(_ location: Int) -> unichar { text.character(at: location) }
        func isIdentifier(_ value: unichar) -> Bool {
            value == 95 || value == 0x2032 || UnicodeScalar(value).map { CharacterSet.alphanumerics.contains($0) } == true
        }
        while offset < text.length {
            let value = scalar(offset)
            if value == 10 { offset += 1; line += 1; column = 1; continue }
            if value == 35 || (value == 47 && offset + 1 < text.length && scalar(offset + 1) == 47) {
                while offset < text.length && scalar(offset) != 10 { offset += 1; column += 1 }
                continue
            }
            if offset + 1 < text.length,
               (value == 40 && scalar(offset + 1) == 42 || value == 47 && scalar(offset + 1) == 42) {
                let closingSecond: unichar = value == 40 ? 41 : 47
                offset += 2; column += 2
                while offset < text.length {
                    if offset + 1 < text.length,
                       scalar(offset) == 42, scalar(offset + 1) == closingSecond {
                        offset += 2; column += 2; break
                    }
                    if scalar(offset) == 10 { offset += 1; line += 1; column = 1 }
                    else { offset += 1; column += 1 }
                }
                continue
            }
            if value == 39 || value == 34 || value == 47 {
                let delimiter = value; offset += 1; column += 1; var escaped = false
                while offset < text.length {
                    let current = scalar(offset); offset += 1; column += 1
                    if current == 10 { line += 1; column = 1; break }
                    if current == delimiter && !escaped { break }
                    escaped = current == 92 && !escaped
                    if current != 92 { escaped = false }
                }
                continue
            }
            if isIdentifier(value) {
                let start = offset, startLine = line, startColumn = column
                while offset < text.length && isIdentifier(scalar(offset)) { offset += 1; column += 1 }
                result.append(.init(text: text.substring(with: NSRange(location: start, length: offset - start)), location: start, length: offset - start, line: startLine, column: startColumn))
                continue
            }
            offset += 1; column += 1
        }
        return result
    }

    private static func isIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[\p{L}_][\p{L}\p{N}_′]*$"#, options: .regularExpression) != nil
    }

    private static func fingerprint(_ source: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in source.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
}

public extension GrammarCompilation {
    func renameRefactoring(from oldName: String, to newName: String) throws -> GrammarRefactoringPlan {
        try GrammarRefactoring.planRename(from: oldName, to: newName, in: self)
    }
}

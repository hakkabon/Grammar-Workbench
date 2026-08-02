import Foundation

/// The stable, engine-independent API version exposed by Grammar Workbench.
public enum GrammarWorkbenchAPIVersion {
    public static let current = 1
}

public enum GrammarAlgorithm: String, CaseIterable, Codable, Identifiable, Sendable {
    case slr = "SLR(1)"
    case lalr = "LALR(1)"
    case canonical = "Canonical LR(1)"

    public var id: Self { self }
}

public struct GrammarCompilationRequest: Hashable, Codable, Sendable {
    public var source: String
    public var algorithm: GrammarAlgorithm

    public init(source: String, algorithm: GrammarAlgorithm = .lalr) {
        self.source = source
        self.algorithm = algorithm
    }
}

public struct GrammarSummary: Hashable, Codable, Sendable {
    public let startSymbol: String
    public let terminals: [String]
    public let nonterminals: [String]
    public let productions: [GrammarProductionSnapshot]
}

public struct GrammarProductionSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let lhs: String
    public let rhs: [String]
    public var text: String { "\(lhs) → \(rhs.isEmpty ? "ε" : rhs.joined(separator: " "))" }
}

public struct GrammarAnalysisSnapshot: Hashable, Codable, Sendable {
    public let nullable: [String]
    public let first: [String: [String]]
    public let follow: [String: [String]]
}

public enum GrammarActionKind: String, Codable, Sendable {
    case shift, reduce, accept, goTo
}

public struct GrammarActionSnapshot: Hashable, Codable, Sendable {
    public let kind: GrammarActionKind
    public let targetState: Int?
    public let production: Int?
    public let label: String
}

public struct GrammarStateSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let items: [String]
}

public struct GrammarTransitionSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let from: Int
    public let symbol: String
    public let to: Int
    public var id: String { "\(from):\(symbol):\(to)" }
}

public struct GrammarTableCellSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let state: Int
    public let symbol: String
    public let actions: [GrammarActionSnapshot]
    public var id: String { "\(state):\(symbol)" }
    public var isConflict: Bool { actions.count > 1 }
}

public enum GrammarDecisionDisposition: String, Codable, Sendable {
    case unresolved, expected, resolved
}

public struct GrammarDecisionSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let state: Int
    public let symbol: String
    public let title: String
    public let explanation: String
    public let disposition: GrammarDecisionDisposition
    public let candidateActions: [GrammarActionSnapshot]
    public let effectiveActions: [GrammarActionSnapshot]
    public let witness: [String]
    public let resolution: String?
}

public struct GrammarConflictExpectationSnapshot: Hashable, Codable, Sendable {
    public let expected: Int
    public let actual: Int
    public let matches: Bool
}

/// A Codable value snapshot. Its schema is identified by `apiVersion` and does not
/// expose the construction engine's internal model types.
public struct GrammarArtifactSnapshot: Hashable, Codable, Sendable {
    public let apiVersion: Int
    public let algorithm: GrammarAlgorithm
    public let source: String
    public let terminals: [String]
    public let nonterminals: [String]
    public let productions: [GrammarProductionSnapshot]
    public let states: [GrammarStateSnapshot]
    public let transitions: [GrammarTransitionSnapshot]
    public let table: [GrammarTableCellSnapshot]
    public let decisions: [GrammarDecisionSnapshot]
    public let conflictExpectation: GrammarConflictExpectationSnapshot?
}

public struct GrammarInputTokenSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let index: Int
    public let kind: String
    public let lexeme: String
    public let range: SourceRange?
    public var id: Int { index }
}

public struct GrammarInputDiagnostic: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let message: String
    public let range: SourceRange?
}

public struct GrammarLexingResult: Hashable, Codable, Sendable {
    public let tokens: [GrammarInputTokenSnapshot]
    public let diagnostics: [GrammarInputDiagnostic]
    public var hasErrors: Bool { !diagnostics.isEmpty }
}

public enum GrammarParseStatus: String, Codable, Sendable {
    case accepted, rejected, conflict, looping, invalidGrammar
}

public struct GrammarTraceFrameSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let index: Int
    public let stack: [String]
    public let remainingInput: [String]
    public let action: String
    public let state: Int?
    public let cellSymbol: String?
    public let production: Int?
    public var id: Int { index }
}

public struct GrammarParseResult: Hashable, Codable, Sendable {
    public let status: GrammarParseStatus
    public let message: String
    public let tokens: [GrammarInputTokenSnapshot]
    public let expectedTerminals: [String]
    public let tree: String?
    public let trace: [GrammarTraceFrameSnapshot]
    public let conflictState: Int?
    public let conflictSymbol: String?
}

/// The result of compilation. Public properties are immutable snapshots; the
/// private engine values permit efficient repeated lexing, parsing, and tests.
public struct GrammarCompilation: Sendable {
    public let apiVersion: Int
    public let request: GrammarCompilationRequest
    public let diagnostics: [GrammarDiagnostic]
    public let grammar: GrammarSummary?
    public let analysis: GrammarAnalysisSnapshot?
    public let artifact: GrammarArtifactSnapshot?

    let compiledGrammar: ParsedGrammar?
    let compiledArtifact: GrammarArtifact?

    public var succeeded: Bool { compiledArtifact != nil }

    public func lex(_ input: String) -> GrammarLexingResult {
        guard let compiledGrammar else {
            return .init(tokens: [], diagnostics: [.init(id: 0, message: firstError, range: nil)])
        }
        if !compiledGrammar.lexerRules.isEmpty {
            let result = GrammarLexerRuntime.lex(input, grammar: compiledGrammar)
            return .init(
                tokens: result.tokens.map { .init(index: $0.index, kind: $0.kind, lexeme: $0.lexeme, range: $0.range) },
                diagnostics: result.diagnostics.map { .init(id: $0.id, message: $0.message, range: $0.range) }
            )
        }
        switch SampleInputTokenizer.tokenize(input) {
        case .success(let tokens):
            return .init(tokens: tokens.enumerated().map {
                .init(index: $0.offset, kind: $0.element, lexeme: $0.element, range: nil)
            }, diagnostics: [])
        case .failure(let error):
            return .init(tokens: [], diagnostics: [.init(id: 0, message: error.message, range: nil)])
        }
    }

    public func parse(_ input: String) -> GrammarParseResult {
        guard let compiledArtifact else { return invalidParseResult(firstError) }
        let lexed = lex(input)
        guard !lexed.hasErrors else { return invalidParseResult(lexed.diagnostics[0].message, tokens: lexed.tokens) }
        let runtime = LRParserRuntime.parse(lexed.tokens.map(\.kind), artifact: compiledArtifact)
        let status: GrammarParseStatus
        let expected: [String]
        let conflictState: Int?
        let conflictSymbol: String?
        switch runtime.outcome {
        case .accepted:
            status = .accepted; expected = []; conflictState = nil; conflictSymbol = nil
        case .rejected(_, let values):
            status = .rejected; expected = values; conflictState = nil; conflictSymbol = nil
        case .conflict(let cell):
            status = .conflict; expected = []; conflictState = cell.state.rawValue; conflictSymbol = cell.symbol
        case .looping:
            status = .looping; expected = []; conflictState = nil; conflictSymbol = nil
        }
        return .init(
            status: status, message: runtime.outcome.label, tokens: lexed.tokens,
            expectedTerminals: expected, tree: runtime.tree?.rendered(),
            trace: runtime.frames.map(GrammarTraceFrameSnapshot.init),
            conflictState: conflictState, conflictSymbol: conflictSymbol
        )
    }

    public func runTests(_ tests: [WorkbenchTestCase]) -> WorkbenchTestReport {
        guard let compiledGrammar, let compiledArtifact else {
            return .init(results: tests.map {
                .init(id: $0.id, name: $0.name, status: .invalid, expected: $0.expectation,
                      actual: "Not run", message: firstError, tokens: [], tree: nil)
            })
        }
        return GrammarTestRunner.run(tests, grammar: compiledGrammar, artifact: compiledArtifact)
    }

    public func encodeArtifactSnapshot(prettyPrinted: Bool = true) throws -> Data {
        guard let artifact else { throw GrammarWorkbenchAPIError.compilationFailed(firstError) }
        let encoder = JSONEncoder()
        if prettyPrinted { encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] }
        return try encoder.encode(artifact)
    }

    /// Generates a dependency-free, table-driven Swift parser with the grammar's
    /// lexer rules embedded in declaration order.
    public func generateSwiftParser(
        options: SwiftParserGenerationOptions = .init()
    ) throws -> String {
        guard let compiledGrammar, let compiledArtifact else {
            throw GrammarWorkbenchAPIError.compilationFailed(firstError)
        }
        return try SwiftParserCodeGenerator.generate(
            grammar: compiledGrammar, artifact: compiledArtifact, options: options
        )
    }

    private var firstError: String {
        diagnostics.first(where: { $0.severity == .error })?.message ?? "The grammar did not compile."
    }

    private func invalidParseResult(_ message: String, tokens: [GrammarInputTokenSnapshot] = []) -> GrammarParseResult {
        .init(status: .invalidGrammar, message: message, tokens: tokens, expectedTerminals: [],
              tree: nil, trace: [], conflictState: nil, conflictSymbol: nil)
    }
}

public enum GrammarWorkbenchAPIError: Error, LocalizedError, Sendable {
    case compilationFailed(String)

    public var errorDescription: String? {
        switch self { case .compilationFailed(let message): message }
    }
}

/// Stable entry point for non-UI clients. All returned values are immutable and
/// `Sendable`, so a compilation may safely be passed between concurrency domains.
public enum GrammarWorkbenchAPI {
    public static let version = GrammarWorkbenchAPIVersion.current

    public static func compile(_ request: GrammarCompilationRequest) -> GrammarCompilation {
        let result = GrammarFrontEnd.process(request.source)
        guard !result.hasErrors, let grammar = result.grammar, let analysis = result.analysis else {
            return .init(apiVersion: version, request: request, diagnostics: result.diagnostics,
                         grammar: nil, analysis: nil, artifact: nil,
                         compiledGrammar: nil, compiledArtifact: nil)
        }
        let core = LRConstructionEngine.construct(
            grammar: grammar, analysis: analysis, source: request.source,
            algorithm: request.algorithm.coreValue
        )
        return .init(
            apiVersion: version, request: request, diagnostics: result.diagnostics,
            grammar: GrammarSummary(grammar), analysis: GrammarAnalysisSnapshot(analysis),
            artifact: GrammarArtifactSnapshot(core), compiledGrammar: grammar, compiledArtifact: core
        )
    }
}

private extension GrammarAlgorithm {
    var coreValue: LRAlgorithm { LRAlgorithm(rawValue: rawValue)! }
}

private extension GrammarSummary {
    init(_ grammar: ParsedGrammar) {
        self.init(startSymbol: grammar.startSymbol, terminals: grammar.terminals,
                  nonterminals: grammar.nonterminals,
                  productions: grammar.productions.map { .init(id: $0.id, lhs: $0.lhs, rhs: $0.rhs) })
    }
}

private extension GrammarAnalysisSnapshot {
    init(_ analysis: GrammarAnalysis) {
        self.init(nullable: analysis.nullable.sorted(),
                  first: analysis.first.mapValues { $0.sorted() },
                  follow: analysis.follow.mapValues { $0.sorted() })
    }
}

private extension GrammarActionSnapshot {
    init(_ action: TableAction) {
        switch action {
        case .shift(let state): self.init(kind: .shift, targetState: state.rawValue, production: nil, label: action.label)
        case .reduce(let production): self.init(kind: .reduce, targetState: nil, production: production.rawValue, label: action.label)
        case .accept: self.init(kind: .accept, targetState: nil, production: nil, label: action.label)
        case .goTo(let state): self.init(kind: .goTo, targetState: state.rawValue, production: nil, label: action.label)
        }
    }
}

private extension GrammarTraceFrameSnapshot {
    init(_ frame: ReplayFrame) {
        self.init(index: frame.index, stack: frame.stack, remainingInput: frame.remainingInput,
                  action: frame.action, state: frame.state?.rawValue,
                  cellSymbol: frame.cell?.symbol, production: frame.production?.rawValue)
    }
}

private extension GrammarArtifactSnapshot {
    init(_ artifact: GrammarArtifact) {
        self.init(
            apiVersion: GrammarWorkbenchAPIVersion.current,
            algorithm: GrammarAlgorithm(rawValue: artifact.algorithm.rawValue)!,
            source: artifact.grammarSource, terminals: artifact.terminals,
            nonterminals: artifact.nonterminals,
            productions: artifact.productions.map { .init(id: $0.id.rawValue, lhs: $0.lhs, rhs: $0.rhs) },
            states: artifact.states.map { .init(id: $0.id.rawValue, items: $0.items.map(\.text)) },
            transitions: artifact.transitions.map { .init(from: $0.from.rawValue, symbol: $0.symbol, to: $0.to.rawValue) },
            table: artifact.cells.map { .init(state: $0.id.state.rawValue, symbol: $0.id.symbol, actions: $0.actions.map(GrammarActionSnapshot.init)) },
            decisions: artifact.decisions.map { decision in
                .init(
                    id: decision.id.rawValue, state: decision.cell.state.rawValue, symbol: decision.cell.symbol,
                    title: decision.title, explanation: decision.explanation,
                    disposition: GrammarDecisionDisposition(rawValue: decision.disposition.rawValue)!,
                    candidateActions: artifact.candidateActions(for: decision).map(GrammarActionSnapshot.init),
                    effectiveActions: (artifact.cell(decision.cell)?.actions ?? []).map(GrammarActionSnapshot.init),
                    witness: decision.witness, resolution: decision.provenance?.kind.rawValue
                )
            },
            conflictExpectation: artifact.conflictExpectation.map {
                .init(expected: $0.expected, actual: $0.actual, matches: $0.matches)
            }
        )
    }
}

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

public enum GrammarSourceNotation: String, CaseIterable, Codable, Identifiable, Sendable {
    case workbench = "Workbench"
    case ebnf = "EBNF"

    public var id: Self { self }
}

public struct GrammarCompilationRequest: Hashable, Codable, Sendable {
    public var source: String
    public var algorithm: GrammarAlgorithm
    public var notation: GrammarSourceNotation

    public init(
        source: String,
        algorithm: GrammarAlgorithm = .lalr,
        notation: GrammarSourceNotation = .workbench
    ) {
        self.source = source
        self.algorithm = algorithm
        self.notation = notation
    }

    private enum CodingKeys: String, CodingKey { case source, algorithm, notation }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decode(String.self, forKey: .source)
        algorithm = try values.decodeIfPresent(GrammarAlgorithm.self, forKey: .algorithm) ?? .lalr
        notation = try values.decodeIfPresent(GrammarSourceNotation.self, forKey: .notation) ?? .workbench
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
    public let mode: String?
    public let range: SourceRange?
    public var id: Int { index }
}

public struct GrammarInputDiagnostic: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let message: String
    public let mode: String?
    public let range: SourceRange?
}

public struct GrammarLexingResult: Hashable, Codable, Sendable {
    public let tokens: [GrammarInputTokenSnapshot]
    public let diagnostics: [GrammarInputDiagnostic]
    public let finalModeStack: [String]
    public var hasErrors: Bool { !diagnostics.isEmpty }
}

public enum GrammarParseStatus: String, Codable, Sendable {
    case accepted, acceptedWithRecovery, rejected, conflict, looping, invalidGrammar
}

public enum GrammarRecoveryKind: String, Codable, Sendable {
    case deletedToken, insertedToken, synchronized
}

public struct GrammarParseOptions: Hashable, Codable, Sendable {
    public var enablesRecovery: Bool
    public var maximumDiagnostics: Int
    public var synchronizationTerminals: [String]
    public var preferredInsertions: [String]

    public init(
        enablesRecovery: Bool = true,
        maximumDiagnostics: Int = 8,
        synchronizationTerminals: [String] = [],
        preferredInsertions: [String] = []
    ) {
        self.enablesRecovery = enablesRecovery
        self.maximumDiagnostics = max(1, maximumDiagnostics)
        self.synchronizationTerminals = synchronizationTerminals
        self.preferredInsertions = preferredInsertions
    }

    private enum CodingKeys: String, CodingKey {
        case enablesRecovery, maximumDiagnostics, synchronizationTerminals, preferredInsertions
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enablesRecovery = try values.decodeIfPresent(Bool.self, forKey: .enablesRecovery) ?? true
        maximumDiagnostics = max(1, try values.decodeIfPresent(Int.self, forKey: .maximumDiagnostics) ?? 8)
        synchronizationTerminals = try values.decodeIfPresent([String].self, forKey: .synchronizationTerminals) ?? []
        preferredInsertions = try values.decodeIfPresent([String].self, forKey: .preferredInsertions) ?? []
    }
}

public struct GrammarSyntaxDiagnostic: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let message: String
    public let tokenIndex: Int
    public let range: SourceRange?
    public let state: Int
    public let unexpected: String
    public let expected: [String]
    public let recovery: GrammarRecoveryKind?
    public let recoverySymbol: String?
    public let recoveryDetail: String?
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
    public let syntaxTree: GrammarSyntaxNode?
    public let trace: [GrammarTraceFrameSnapshot]
    public let conflictState: Int?
    public let conflictSymbol: String?
    public let diagnostics: [GrammarSyntaxDiagnostic]

    init(
        status: GrammarParseStatus, message: String, tokens: [GrammarInputTokenSnapshot],
        expectedTerminals: [String], tree: String?, syntaxTree: GrammarSyntaxNode?,
        trace: [GrammarTraceFrameSnapshot], conflictState: Int?, conflictSymbol: String?,
        diagnostics: [GrammarSyntaxDiagnostic]
    ) {
        self.status = status; self.message = message; self.tokens = tokens
        self.expectedTerminals = expectedTerminals; self.tree = tree; self.syntaxTree = syntaxTree
        self.trace = trace; self.conflictState = conflictState; self.conflictSymbol = conflictSymbol
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case status, message, tokens, expectedTerminals, tree, syntaxTree, trace
        case conflictState, conflictSymbol, diagnostics
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            status: try values.decode(GrammarParseStatus.self, forKey: .status),
            message: try values.decode(String.self, forKey: .message),
            tokens: try values.decode([GrammarInputTokenSnapshot].self, forKey: .tokens),
            expectedTerminals: try values.decode([String].self, forKey: .expectedTerminals),
            tree: try values.decodeIfPresent(String.self, forKey: .tree),
            syntaxTree: try values.decodeIfPresent(GrammarSyntaxNode.self, forKey: .syntaxTree),
            trace: try values.decode([GrammarTraceFrameSnapshot].self, forKey: .trace),
            conflictState: try values.decodeIfPresent(Int.self, forKey: .conflictState),
            conflictSymbol: try values.decodeIfPresent(String.self, forKey: .conflictSymbol),
            diagnostics: try values.decode([GrammarSyntaxDiagnostic].self, forKey: .diagnostics)
        )
    }
}

/// The result of compilation. Public properties are immutable snapshots; the
/// private engine values permit efficient repeated lexing, parsing, and tests.
public struct GrammarCompilation: Sendable {
    public let apiVersion: Int
    public let request: GrammarCompilationRequest
    public let diagnostics: [GrammarDiagnostic]
    public let grammar: GrammarSummary?
    public let analysis: GrammarAnalysisSnapshot?
    public let lexerAnalysis: LexerModeAnalysis?
    public let artifact: GrammarArtifactSnapshot?
    public let performance: GrammarConstructionPerformance

    let frontEndResult: GrammarFrontEndResult
    let compiledGrammar: ParsedGrammar?
    let compiledAnalysis: GrammarAnalysis?
    let compiledArtifact: GrammarArtifact?

    public var succeeded: Bool { compiledArtifact != nil }

    /// The parsed grammar with source ranges for productions, token
    /// declarations, and lexer rules, used by language services that work
    /// inside grammar documents.
    public var parsedGrammar: ParsedGrammar? { compiledGrammar }

    public func lex(_ input: String) -> GrammarLexingResult {
        guard let compiledGrammar else {
            return .init(tokens: [], diagnostics: [.init(id: 0, message: firstError, mode: nil, range: nil)], finalModeStack: ["DEFAULT"])
        }
        if !compiledGrammar.lexerRules.isEmpty {
            let result = GrammarLexerRuntime.lex(input, grammar: compiledGrammar)
            return .init(
                tokens: result.tokens.map { .init(index: $0.index, kind: $0.kind, lexeme: $0.lexeme, mode: $0.mode, range: $0.range) },
                diagnostics: result.diagnostics.map { .init(id: $0.id, message: $0.message, mode: $0.mode, range: $0.range) },
                finalModeStack: result.finalModeStack
            )
        }
        switch SampleInputTokenizer.tokenize(input) {
        case .success(let tokens):
            return .init(tokens: tokens.enumerated().map {
                .init(index: $0.offset, kind: $0.element, lexeme: $0.element, mode: nil, range: nil)
            }, diagnostics: [], finalModeStack: ["DEFAULT"])
        case .failure(let error):
            return .init(tokens: [], diagnostics: [.init(id: 0, message: error.message, mode: nil, range: nil)], finalModeStack: ["DEFAULT"])
        }
    }

    public func parse(
        _ input: String,
        options: GrammarParseOptions = .init()
    ) -> GrammarParseResult {
        guard let compiledArtifact else { return invalidParseResult(firstError) }
        let lexed = lex(input)
        guard !lexed.hasErrors else { return invalidParseResult(lexed.diagnostics[0].message, tokens: lexed.tokens) }
        let recovery = options.enablesRecovery
            ? ParserRecoveryConfiguration(
                maximumDiagnostics: options.maximumDiagnostics,
                synchronizationTerminals: Set(options.synchronizationTerminals),
                preferredInsertions: options.preferredInsertions
            )
            : .disabled
        let runtime = LRParserRuntime.parse(
            lexed.tokens.map(\.kind), artifact: compiledArtifact, recovery: recovery
        )
        let syntaxDiagnostics = runtime.diagnostics.map { diagnostic in
            GrammarSyntaxDiagnostic(
                id: diagnostic.index, message: diagnostic.message,
                tokenIndex: diagnostic.tokenIndex,
                range: lexed.tokens.indices.contains(diagnostic.tokenIndex)
                    ? lexed.tokens[diagnostic.tokenIndex].range : nil,
                state: diagnostic.state.rawValue, unexpected: diagnostic.unexpected,
                expected: diagnostic.expected,
                recovery: diagnostic.recovery.flatMap { GrammarRecoveryKind(rawValue: $0.rawValue) },
                recoverySymbol: diagnostic.recoverySymbol,
                recoveryDetail: diagnostic.recoveryDetail
            )
        }
        let status: GrammarParseStatus
        let expected: [String]
        let conflictState: Int?
        let conflictSymbol: String?
        switch runtime.outcome {
        case .accepted:
            status = syntaxDiagnostics.isEmpty ? .accepted : .acceptedWithRecovery
            expected = syntaxDiagnostics.last?.expected ?? []
            conflictState = nil; conflictSymbol = nil
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
            syntaxTree: runtime.tree.map { GrammarSyntaxNode.make(from: $0, tokens: lexed.tokens) },
            trace: runtime.frames.map(GrammarTraceFrameSnapshot.init),
            conflictState: conflictState, conflictSymbol: conflictSymbol,
            diagnostics: syntaxDiagnostics
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

    /// Builds SLR(1), LALR(1), and canonical LR(1) artifacts from the same
    /// grammar and compares state cores, tables, and conflict behavior.
    public func compareAlgorithms() throws -> GrammarAlgorithmComparison {
        guard let compiledGrammar, let compiledAnalysis, let compiledArtifact else {
            throw GrammarWorkbenchAPIError.compilationFailed(firstError)
        }
        return AlgorithmComparisonEngine.compare(
            grammar: compiledGrammar, analysis: compiledAnalysis,
            source: request.source, reusing: compiledArtifact
        )
    }

    private var firstError: String {
        diagnostics.first(where: { $0.severity == .error })?.message ?? "The grammar did not compile."
    }

    private func invalidParseResult(_ message: String, tokens: [GrammarInputTokenSnapshot] = []) -> GrammarParseResult {
        .init(status: .invalidGrammar, message: message, tokens: tokens, expectedTerminals: [],
              tree: nil, syntaxTree: nil, trace: [], conflictState: nil, conflictSymbol: nil, diagnostics: [])
    }

    func withReuse(_ reuse: GrammarConstructionReuse, delivery: Double) -> GrammarCompilation {
        .init(
            apiVersion: apiVersion, request: request, diagnostics: diagnostics,
            grammar: grammar, analysis: analysis, lexerAnalysis: lexerAnalysis,
            artifact: artifact,
            performance: .init(
                frontEndMilliseconds: performance.frontEndMilliseconds,
                constructionMilliseconds: performance.constructionMilliseconds,
                totalMilliseconds: delivery, reuse: reuse,
                stateCount: performance.stateCount, itemCount: performance.itemCount,
                tableEntryCount: performance.tableEntryCount
            ),
            frontEndResult: frontEndResult, compiledGrammar: compiledGrammar,
            compiledAnalysis: compiledAnalysis, compiledArtifact: compiledArtifact
        )
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

    public static func lowerEBNF(_ source: String) throws -> GrammarLoweringSnapshot {
        let result = EBNFGrammarAdapter.lower(source)
        guard let lowering = result.lowering else {
            throw GrammarWorkbenchAPIError.compilationFailed(
                result.frontEnd.diagnostics.first?.message ?? "The EBNF grammar could not be lowered."
            )
        }
        return lowering
    }

    public static func compile(_ request: GrammarCompilationRequest) -> GrammarCompilation {
        let totalStart = ContinuousClock.now
        let frontEndStart = ContinuousClock.now
        let result = GrammarFrontEnd.process(request.source, notation: request.notation)
        let frontEndMilliseconds = elapsedMilliseconds(since: frontEndStart)
        guard !result.hasErrors, let grammar = result.grammar, let analysis = result.analysis else {
            return .init(apiVersion: version, request: request, diagnostics: result.diagnostics,
                         grammar: nil, analysis: nil, lexerAnalysis: result.lexerAnalysis, artifact: nil,
                         performance: .init(
                            frontEndMilliseconds: frontEndMilliseconds, constructionMilliseconds: 0,
                            totalMilliseconds: elapsedMilliseconds(since: totalStart), reuse: .none,
                            stateCount: 0, itemCount: 0, tableEntryCount: 0
                         ),
                         frontEndResult: result,
                         compiledGrammar: nil, compiledAnalysis: nil, compiledArtifact: nil)
        }
        let constructionStart = ContinuousClock.now
        let core = LRConstructionEngine.construct(
            grammar: grammar, analysis: analysis, source: request.source,
            algorithm: request.algorithm.coreValue
        )
        let constructionMilliseconds = elapsedMilliseconds(since: constructionStart)
        return .init(
            apiVersion: version, request: request, diagnostics: result.diagnostics,
            grammar: GrammarSummary(grammar), analysis: GrammarAnalysisSnapshot(analysis),
            lexerAnalysis: result.lexerAnalysis,
            artifact: GrammarArtifactSnapshot(core),
            performance: .init(
                frontEndMilliseconds: frontEndMilliseconds,
                constructionMilliseconds: constructionMilliseconds,
                totalMilliseconds: elapsedMilliseconds(since: totalStart), reuse: .none,
                stateCount: core.states.count,
                itemCount: core.states.reduce(0) { $0 + $1.items.count },
                tableEntryCount: core.cells.count
            ),
            frontEndResult: result, compiledGrammar: grammar,
            compiledAnalysis: analysis, compiledArtifact: core
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

extension GrammarActionSnapshot {
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

extension GrammarArtifactSnapshot {
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

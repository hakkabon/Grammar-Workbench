#if os(macOS)
import SwiftUI

@MainActor
@Observable
final class ExplorerStore {
    var algorithm: LRAlgorithm = .lalr { didSet { scheduleCompilation(source: sourceText) } }
    var notation: GrammarSourceNotation = .workbench { didSet { scheduleCompilation(source: sourceText) } }
    private var sourceText: String
    private(set) var frontEnd: GrammarFrontEndResult
    private(set) var artifact: GrammarArtifact
    private(set) var documentName = "Expression grammar"
    var sampleInput = "id + id * id"
    private(set) var runtimeResult: ParserRuntimeResult
    private(set) var lexerResult: LexerResult?
    private(set) var testReport: WorkbenchTestReport?
    private(set) var algorithmComparison: GrammarAlgorithmComparison?
    private(set) var isComparingAlgorithms = false
    private(set) var isRegenerating = false
    private(set) var constructionPerformance: GrammarConstructionPerformance?
    private(set) var latestArtifactDiff: GrammarArtifactDiff?
    private(set) var generalizedResult: GrammarGeneralizedParseResult?
    private(set) var isExploringGeneralizedParse = false
    private(set) var incrementalSampleAnalysis: GrammarIncrementalAnalysisSnapshot?
    private(set) var bootstrapReport: GrammarBootstrapReport?
    private(set) var bootstrapError: String?
    private(set) var isRunningBootstrap = false
    var selection: ArtifactIdentity? = .state(.init(rawValue: 0))
    private(set) var sourceSelection: SourceRange?
    var currentCompilationSnapshot: GrammarCompilation { currentCompilation }
    var selectedBranch = 0
    var replayIndex = 0

    @ObservationIgnored private var regenerationTask: Task<Void, Never>?
    @ObservationIgnored private var comparisonTask: Task<Void, Never>?
    @ObservationIgnored private var generalizedTask: Task<Void, Never>?
    @ObservationIgnored private var incrementalAnalysisTask: Task<Void, Never>?
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private let incrementalCompiler = GrammarWorkbenchIncrementalCompiler()
    @ObservationIgnored private var incrementalCoordinator: GrammarIncrementalAnalysisCoordinator?
    @ObservationIgnored private var currentCompilation: GrammarCompilation
    @ObservationIgnored private var latestCompilation: GrammarCompilation
    @ObservationIgnored private var constructionRevision = 0

    init(
        source: String = SampleArtifact.grammarSource,
        algorithm: LRAlgorithm = .lalr,
        notation: GrammarSourceNotation = .workbench,
        sampleInput: String = "id + id * id",
        documentName: String = "Expression grammar"
    ) {
        let compilation = GrammarWorkbenchAPI.compile(.init(
            source: source,
            algorithm: GrammarAlgorithm(rawValue: algorithm.rawValue) ?? .lalr,
            notation: notation
        ))
        let initialArtifact = compilation.compiledArtifact ?? SampleArtifact.make(algorithm: algorithm)
        self.frontEnd = compilation.frontEndResult
        self.artifact = initialArtifact
        self.algorithm = algorithm
        self.notation = notation
        self.sourceText = source
        self.sampleInput = sampleInput
        self.documentName = documentName
        self.constructionPerformance = compilation.performance
        self.latestArtifactDiff = nil
        self.generalizedResult = nil
        self.incrementalSampleAnalysis = nil
        self.bootstrapReport = nil
        self.bootstrapError = nil
        self.currentCompilation = compilation
        self.latestCompilation = compilation
        self.incrementalCoordinator = try? GrammarIncrementalAnalysisCoordinator(compilation: compilation)
        if let grammar = compilation.frontEndResult.grammar, !grammar.lexerRules.isEmpty {
            let lexed = GrammarLexerRuntime.lex(sampleInput, grammar: grammar)
            self.lexerResult = lexed
            self.runtimeResult = Self.runtimeResult(for: lexed, artifact: initialArtifact)
        } else {
            self.lexerResult = nil
            let tokens = (try? SampleInputTokenizer.tokenize(sampleInput).get()) ?? []
            self.runtimeResult = LRParserRuntime.parse(tokens, artifact: initialArtifact, recovery: .diagnostic)
        }
        self.testReport = nil
        self.algorithmComparison = nil
        scheduleIncrementalSampleAnalysis()
    }

    func select(_ identity: ArtifactIdentity) {
        var resolvedIdentity = identity
        replayIndex = 0
        if case .cell(let cell) = identity,
           let decision = artifact.decisions.first(where: { $0.cell == cell }) {
            resolvedIdentity = .decision(decision.id)
        }
        if case .decision = resolvedIdentity {
            selectedBranch = 0
        }
        selection = resolvedIdentity
        sourceSelection = sourceRange(for: resolvedIdentity)
    }

    func selectDiagnostic(_ diagnostic: GrammarDiagnostic) {
        sourceSelection = diagnostic.range
    }

    func selectProjectProblem(_ problem: GrammarProjectExperienceProblem) {
        if let range = problem.range { sourceSelection = range }
    }

    func selectGuidance(_ finding: GrammarGuidanceFinding) {
        if let range = finding.sourceRange { sourceSelection = range }
    }

    func guidance(tests: [WorkbenchTestCase]) -> GrammarGuidanceReport {
        GrammarGuidanceEngine.assess(
            latestCompilation, sampleInput: sampleInput,
            testReport: testReport, testCount: tests.count
        )
    }

    func projectExperience(
        samples: [WorkbenchSample], tests: [WorkbenchTestCase]
    ) -> GrammarProjectExperienceSnapshot {
        GrammarProjectExperience.snapshot(
            name: documentName, compilation: latestCompilation,
            samples: samples, tests: tests, testReport: testReport,
            operations: activeOperations
        )
    }

    var activeOperations: [GrammarProjectOperation] {
        var values: [GrammarProjectOperation] = []
        if isRegenerating {
            values.append(.init(
                kind: .compiling, title: "Compiling grammar",
                detail: "Updating diagnostics and parser artifacts"
            ))
        }
        if isComparingAlgorithms {
            values.append(.init(
                kind: .comparingAlgorithms, title: "Comparing algorithms",
                detail: "Constructing SLR, LALR, and canonical LR artifacts"
            ))
        }
        if isExploringGeneralizedParse {
            values.append(.init(
                kind: .exploringAmbiguity, title: "Exploring ambiguity",
                detail: "Building a bounded shared parse forest"
            ))
        }
        if isRunningBootstrap {
            values.append(.init(
                kind: .bootstrapping, title: "Running bootstrap laboratory",
                detail: "Checking fixed-point and differential validation"
            ))
        }
        return values
    }

    func structuralAnalysis() -> GrammarStructuralAnalysis? {
        try? GrammarEngineering.analyze(latestCompilation)
    }

    func availableGuidedTransformations() -> [GrammarGuidedTransformation] {
        let mappings: [(GrammarGuidedTransformation, GrammarTransformationKind)] = [
            (.removeDuplicateProductionLines, .removeDuplicateProductions),
            (.removeUnreachableProductionLines, .removeUnreachableProductions),
            (.removeUnproductiveProductionLines, .removeUnproductiveProductions)
        ]
        return mappings.compactMap { guided, kind in
            (try? GrammarEngineering.plan(kind, for: latestCompilation).hasChanges) == true ? guided : nil
        }
    }

    func preview(
        _ transformation: GrammarGuidedTransformation,
        examples: [GrammarGuidanceExample],
        tests: [WorkbenchTestCase]
    ) -> GrammarGuidedTransformationPreview {
        GrammarGuidanceEngine.preview(
            transformation,
            request: .init(
                source: sourceText,
                algorithm: GrammarAlgorithm(rawValue: algorithm.rawValue) ?? .lalr,
                notation: notation
            ),
            examples: examples,
            tests: tests
        )
    }

    func selectComparisonState(algorithm target: GrammarAlgorithm, state: Int) {
        if let value = LRAlgorithm(rawValue: target.rawValue), algorithm != value { algorithm = value }
        select(.state(.init(rawValue: state)))
    }

    func selectComparisonCell(algorithm target: GrammarAlgorithm, state: Int, symbol: String) {
        if let value = LRAlgorithm(rawValue: target.rawValue), algorithm != value { algorithm = value }
        select(.cell(.init(state: .init(rawValue: state), symbol: symbol)))
    }

    func load(source: String, documentName: String) {
        regenerationTask?.cancel()
        constructionRevision += 1
        let compilation = GrammarWorkbenchAPI.compile(.init(
            source: source,
            algorithm: GrammarAlgorithm(rawValue: algorithm.rawValue) ?? .lalr,
            notation: notation
        ))
        sourceText = source
        frontEnd = compilation.frontEndResult
        currentCompilation = compilation
        latestCompilation = compilation
        self.documentName = documentName
        if let compiledArtifact = compilation.compiledArtifact { artifact = compiledArtifact }
        constructionPerformance = compilation.performance
        latestArtifactDiff = nil
        sampleInput = compilation.frontEndResult.grammar?.terminals.first ?? ""
        parseSample()
        resetSelection()
        testReport = nil
        invalidateComparison()
        replaceIncrementalCompilation(compilation)
    }

    func runTests(_ tests: [WorkbenchTestCase]) {
        guard let grammar = frontEnd.grammar, !frontEnd.hasErrors else {
            testReport = GrammarTestRunner.run(tests, source: frontEnd.source, algorithm: algorithm.rawValue)
            return
        }
        testReport = GrammarTestRunner.run(tests, grammar: grammar, artifact: artifact)
    }

    func clearTestReport() { testReport = nil }

    func runBootstrapLaboratory() {
        guard !isRunningBootstrap else { return }
        bootstrapTask?.cancel()
        bootstrapError = nil
        isRunningBootstrap = true
        bootstrapTask = Task { [weak self] in
            let result = await Task.detached { Result { try GrammarBootstrapLaboratory.run() } }.value
            guard !Task.isCancelled, let self else { return }
            switch result {
            case .success(let report): self.bootstrapReport = report
            case .failure(let error): self.bootstrapError = error.localizedDescription
            }
            self.isRunningBootstrap = false
            self.bootstrapTask = nil
        }
    }

    func compareAlgorithms() {
        guard algorithmComparison == nil, !isComparingAlgorithms,
              !frontEnd.hasErrors, let grammar = frontEnd.grammar,
              let analysis = frontEnd.analysis else { return }
        let source = frontEnd.source
        let currentArtifact = artifact
        isComparingAlgorithms = true
        comparisonTask = Task { [weak self] in
            let comparison = await Task.detached {
                AlgorithmComparisonEngine.compare(
                    grammar: grammar, analysis: analysis, source: source,
                    reusing: currentArtifact
                )
            }.value
            guard !Task.isCancelled, let self else { return }
            if self.frontEnd.source == source { self.algorithmComparison = comparison }
            self.isComparingAlgorithms = false
        }
    }

    func updateSource(_ source: String, debounceNanoseconds: UInt64 = 350_000_000) {
        sourceText = source
        scheduleCompilation(source: source, debounceNanoseconds: debounceNanoseconds)
    }

    func parseSample() {
        generalizedTask?.cancel()
        generalizedTask = nil
        isExploringGeneralizedParse = false
        generalizedResult = nil
        scheduleIncrementalSampleAnalysis()
        if let grammar = frontEnd.grammar, !grammar.lexerRules.isEmpty {
            let result = GrammarLexerRuntime.lex(sampleInput, grammar: grammar)
            lexerResult = result
            runtimeResult = Self.runtimeResult(for: result, artifact: artifact)
            replayIndex = 0
            return
        }
        lexerResult = nil
        switch SampleInputTokenizer.tokenize(sampleInput) {
        case .success(let tokens):
            runtimeResult = LRParserRuntime.parse(tokens, artifact: artifact, recovery: .diagnostic)
        case .failure(let error):
            runtimeResult = ParserRuntimeResult(
                tokens: [],
                tree: nil,
                frames: [],
                outcome: .rejected(message: error.message, expected: [])
            )
        }
        replayIndex = 0
    }

    func exploreAmbiguity(includingResolvedConflicts: Bool) {
        generalizedTask?.cancel()
        let compilation = GrammarWorkbenchAPI.compile(.init(
            source: sourceText,
            algorithm: GrammarAlgorithm(rawValue: algorithm.rawValue) ?? .lalr,
            notation: notation
        ))
        let input = sampleInput
        let options = GrammarGeneralizedParseOptions(
            exploresResolvedConflicts: includingResolvedConflicts
        )
        isExploringGeneralizedParse = true
        generalizedTask = Task { [weak self] in
            let worker = Task.detached {
                await compilation.parseGeneralizedCancellable(input, options: options)
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let self else { return }
            self.generalizedResult = result
            self.isExploringGeneralizedParse = false
            self.generalizedTask = nil
        }
    }

    private static func runtimeResult(for lexer: LexerResult, artifact: GrammarArtifact) -> ParserRuntimeResult {
        guard let diagnostic = lexer.diagnostics.first else {
            return LRParserRuntime.parse(lexer.tokens.map(\.kind), artifact: artifact, recovery: .diagnostic)
        }
        return ParserRuntimeResult(
            tokens: lexer.tokens.map(\.kind), tree: nil, frames: [],
            outcome: .rejected(message: "Lexing failed at \(diagnostic.range.start.line):\(diagnostic.range.start.column): \(diagnostic.message)", expected: [])
        )
    }

    func selectReplayFrame(_ frame: ReplayFrame, index: Int) {
        if let production = frame.production {
            select(.production(production))
        } else if let cell = frame.cell {
            select(.cell(cell))
        } else if let state = frame.state {
            select(.state(state))
        }
        replayIndex = index
    }

    private func scheduleCompilation(source: String, debounceNanoseconds: UInt64? = nil) {
        regenerationTask?.cancel()
        constructionRevision += 1
        let revision = constructionRevision
        let selectedAlgorithm = GrammarAlgorithm(rawValue: algorithm.rawValue) ?? .lalr
        invalidateComparison()
        isRegenerating = true
        sourceSelection = nil
        regenerationTask = Task { [weak self] in
            if let debounceNanoseconds {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled, let self else { return }
            let compilation = await self.incrementalCompiler.compile(.init(
                source: source, algorithm: selectedAlgorithm, notation: self.notation
            ))
            guard !Task.isCancelled, revision == self.constructionRevision else { return }
            self.frontEnd = compilation.frontEndResult
            self.latestCompilation = compilation
            self.constructionPerformance = compilation.performance
            if let compiledArtifact = compilation.compiledArtifact {
                self.currentCompilation = compilation
                if let current = compilation.artifact {
                    self.latestArtifactDiff = GrammarArtifactDiff(
                        previous: GrammarArtifactSnapshot(self.artifact), current: current
                    )
                }
                self.artifact = compiledArtifact
                self.parseSample()
                self.replaceIncrementalCompilation(compilation)
                self.resetSelection()
            }
            self.isRegenerating = false
            self.testReport = nil
            self.regenerationTask = nil
        }
    }

    private func replaceIncrementalCompilation(_ compilation: GrammarCompilation) {
        guard compilation.succeeded else { return }
        incrementalAnalysisTask?.cancel()
        let input = sampleInput
        incrementalAnalysisTask = Task { [weak self] in
            guard let self else { return }
            let coordinator: GrammarIncrementalAnalysisCoordinator
            if let existing = self.incrementalCoordinator {
                coordinator = existing
                _ = try? await coordinator.updateCompilation(compilation)
            } else {
                guard let created = try? GrammarIncrementalAnalysisCoordinator(compilation: compilation) else { return }
                self.incrementalCoordinator = created
                coordinator = created
            }
            guard !Task.isCancelled,
                  let snapshot = try? await coordinator.synchronizeDocument(id: "sample", text: input),
                  !Task.isCancelled,
                  self.sampleInput == input else { return }
            self.incrementalSampleAnalysis = snapshot
        }
    }

    private func scheduleIncrementalSampleAnalysis() {
        guard currentCompilation.succeeded else { return }
        incrementalAnalysisTask?.cancel()
        let input = sampleInput
        let compilation = currentCompilation
        incrementalAnalysisTask = Task { [weak self] in
            guard let self else { return }
            let coordinator: GrammarIncrementalAnalysisCoordinator
            if let existing = self.incrementalCoordinator {
                coordinator = existing
            } else {
                guard let created = try? GrammarIncrementalAnalysisCoordinator(compilation: compilation) else { return }
                self.incrementalCoordinator = created
                coordinator = created
            }
            guard let snapshot = try? await coordinator.synchronizeDocument(id: "sample", text: input),
                  !Task.isCancelled,
                  self.sampleInput == input else { return }
            self.incrementalSampleAnalysis = snapshot
        }
    }

    private func resetSelection() {
        selection = .state(.init(rawValue: 0))
        sourceSelection = sourceRange(for: selection!)
        selectedBranch = 0
        replayIndex = 0
    }

    private func invalidateComparison() {
        comparisonTask?.cancel()
        comparisonTask = nil
        algorithmComparison = nil
        isComparingAlgorithms = false
    }

    private func sourceRange(for identity: ArtifactIdentity) -> SourceRange? {
        guard let grammar = frontEnd.grammar else { return nil }
        func productionRange(_ id: ProductionID) -> SourceRange? {
            guard id.rawValue > 0 else { return nil }
            return grammar.productions.first { $0.id == id.rawValue - 1 }?.range
        }
        func stateRange(_ id: StateID) -> SourceRange? {
            guard let state = artifact.state(id),
                  let production = state.items.map(\.production).first(where: { $0.rawValue > 0 }) else { return nil }
            return productionRange(production)
        }
        switch identity {
        case .production(let id):
            return productionRange(id)
        case .state(let id):
            return stateRange(id)
        case .cell(let id):
            return stateRange(id.state)
        case .decision(let id):
            return artifact.decision(id).flatMap { stateRange($0.cell.state) }
        case .traceStep:
            return nil
        }
    }
}
#endif

import SwiftUI

@MainActor
@Observable
final class ExplorerStore {
    var algorithm: LRAlgorithm = .lalr { didSet { reload() } }
    private(set) var frontEnd: GrammarFrontEndResult
    private(set) var artifact: GrammarArtifact
    private(set) var documentName = "Expression grammar"
    var sampleInput = "id + id * id"
    private(set) var runtimeResult: ParserRuntimeResult
    private(set) var isRegenerating = false
    var selection: ArtifactIdentity? = .state(.init(rawValue: 0))
    private(set) var sourceSelection: SourceRange?
    var selectedBranch = 0
    var replayIndex = 0

    @ObservationIgnored private var regenerationTask: Task<Void, Never>?

    init(
        source: String = SampleArtifact.grammarSource,
        algorithm: LRAlgorithm = .lalr,
        sampleInput: String = "id + id * id",
        documentName: String = "Expression grammar"
    ) {
        let frontEnd = GrammarFrontEnd.process(source)
        let artifact = FrontEndArtifact.make(result: frontEnd, algorithm: algorithm)
        self.frontEnd = frontEnd
        self.artifact = artifact
        self.algorithm = algorithm
        self.sampleInput = sampleInput
        self.documentName = documentName
        let tokens = (try? SampleInputTokenizer.tokenize(sampleInput).get()) ?? []
        self.runtimeResult = LRParserRuntime.parse(tokens, artifact: artifact)
    }

    func select(_ identity: ArtifactIdentity) {
        var resolvedIdentity = identity
        replayIndex = 0
        if case .cell(let cell) = identity,
           let decision = artifact.decisions.first(where: { $0.cell == cell }) {
            resolvedIdentity = .decision(decision.id)
        }
        selection = resolvedIdentity
        sourceSelection = sourceRange(for: resolvedIdentity)
    }

    func selectDiagnostic(_ diagnostic: GrammarDiagnostic) {
        sourceSelection = diagnostic.range
    }

    func load(source: String, documentName: String) {
        regenerationTask?.cancel()
        let result = GrammarFrontEnd.process(source)
        frontEnd = result
        self.documentName = documentName
        if !result.hasErrors {
            artifact = FrontEndArtifact.make(result: result, algorithm: algorithm)
        }
        sampleInput = result.grammar?.terminals.first ?? ""
        parseSample()
        resetSelection()
    }

    func updateSource(_ source: String, debounceNanoseconds: UInt64 = 350_000_000) {
        regenerationTask?.cancel()
        isRegenerating = true
        sourceSelection = nil
        regenerationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled, let self else { return }
            self.regenerate(source)
        }
    }

    func parseSample() {
        switch SampleInputTokenizer.tokenize(sampleInput) {
        case .success(let tokens):
            runtimeResult = LRParserRuntime.parse(tokens, artifact: artifact)
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

    private func reload() {
        guard !frontEnd.hasErrors else { return }
        artifact = FrontEndArtifact.make(result: frontEnd, algorithm: algorithm)
        parseSample()
        resetSelection()
    }

    private func regenerate(_ source: String) {
        let result = GrammarFrontEnd.process(source)
        frontEnd = result
        if !result.hasErrors {
            artifact = FrontEndArtifact.make(result: result, algorithm: algorithm)
            parseSample()
            resetSelection()
        }
        isRegenerating = false
    }

    private func resetSelection() {
        selection = .state(.init(rawValue: 0))
        sourceSelection = sourceRange(for: selection!)
        selectedBranch = 0
        replayIndex = 0
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

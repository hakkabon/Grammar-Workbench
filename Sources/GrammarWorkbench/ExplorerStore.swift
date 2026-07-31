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
        selection = identity
        replayIndex = 0
        if case .cell(let cell) = identity,
           let decision = artifact.decisions.first(where: { $0.cell == cell }) {
            selection = .decision(decision.id)
        }
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
        replayIndex = index
        if let production = frame.production {
            selection = .production(production)
        } else if let cell = frame.cell {
            selection = artifact.decisions.contains(where: { $0.cell == cell })
                ? .decision(artifact.decisions.first(where: { $0.cell == cell })!.id)
                : .cell(cell)
        } else if let state = frame.state {
            selection = .state(state)
        }
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
        selectedBranch = 0
        replayIndex = 0
    }
}

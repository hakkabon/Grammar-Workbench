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
    var selection: ArtifactIdentity? = .state(.init(rawValue: 0))
    var selectedBranch = 0
    var replayIndex = 0

    init() {
        let frontEnd = GrammarFrontEnd.process(SampleArtifact.grammarSource)
        let artifact = FrontEndArtifact.make(result: frontEnd, algorithm: .lalr)
        self.frontEnd = frontEnd
        self.artifact = artifact
        self.runtimeResult = LRParserRuntime.parse(["id", "+", "id", "*", "id"], artifact: artifact)
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
        let result = GrammarFrontEnd.process(source)
        frontEnd = result
        self.documentName = documentName
        artifact = FrontEndArtifact.make(result: result, algorithm: algorithm)
        sampleInput = result.grammar?.terminals.first ?? ""
        parseSample()
        resetSelection()
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
        artifact = FrontEndArtifact.make(result: frontEnd, algorithm: algorithm)
        parseSample()
        resetSelection()
    }

    private func resetSelection() {
        selection = .state(.init(rawValue: 0))
        selectedBranch = 0
        replayIndex = 0
    }
}

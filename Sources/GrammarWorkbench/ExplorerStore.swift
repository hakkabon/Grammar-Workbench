import SwiftUI

@MainActor
@Observable
final class ExplorerStore {
    var algorithm: LRAlgorithm = .lalr { didSet { reload() } }
    private(set) var frontEnd = GrammarFrontEnd.process(SampleArtifact.grammarSource)
    private(set) var artifact = SampleArtifact.make(algorithm: .lalr)
    private(set) var documentName = "Expression grammar"
    var selection: ArtifactIdentity? = .state(.init(rawValue: 0))
    var selectedBranch = 0
    var replayIndex = 0

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
        resetSelection()
    }

    private func reload() {
        artifact = documentName == "Expression grammar"
            ? SampleArtifact.make(algorithm: algorithm)
            : FrontEndArtifact.make(result: frontEnd, algorithm: algorithm)
        resetSelection()
    }

    private func resetSelection() {
        selection = .state(.init(rawValue: 0))
        selectedBranch = 0
        replayIndex = 0
    }
}

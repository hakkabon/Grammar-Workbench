import SwiftUI

@MainActor
@Observable
final class ExplorerStore {
    var algorithm: LRAlgorithm = .lalr { didSet { reload() } }
    private(set) var artifact = SampleArtifact.make(algorithm: .lalr)
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

    private func reload() {
        artifact = SampleArtifact.make(algorithm: algorithm)
        selection = .state(.init(rawValue: 0))
        selectedBranch = 0
        replayIndex = 0
    }
}

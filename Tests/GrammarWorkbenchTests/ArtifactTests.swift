import Testing
@testable import GrammarWorkbench

@Test func artifactIdentitiesRemainStableAcrossAlgorithms() {
    let slr = SampleArtifact.make(algorithm: .slr)
    let lalr = SampleArtifact.make(algorithm: .lalr)
    #expect(slr.states.map(\.id) == lalr.states.map(\.id))
    #expect(slr.productions.map(\.id) == lalr.productions.map(\.id))
}

@Test func conflictCellsHaveDecisionsAndReplayBranches() {
    let artifact = SampleArtifact.make(algorithm: .lalr)
    for cell in artifact.cells.filter(\.isConflict) {
        let decision = artifact.decisions.first { $0.cell == cell.id }
        #expect(decision != nil)
        #expect(decision?.branches.count == 2)
    }
}

@Test func exportIsStandaloneAndEscapesGrammar() {
    let html = HTMLExporter.render(SampleArtifact.make(algorithm: .lalr))
    #expect(html.contains("<!doctype html>"))
    #expect(html.contains("Grammar Artifact Explorer"))
    #expect(!html.contains("<script src="))
    #expect(html.contains("E → E + E"))
    #expect(html.contains("<svg"))
}

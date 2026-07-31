import Testing
@testable import GrammarWorkbench

private func visualizationArtifact(stateCount: Int) -> GrammarArtifact {
    let states = (0..<stateCount).map { index in
        AutomatonState(
            id: .init(rawValue: index),
            items: [LRItem(id: "item-\(index)", production: .init(rawValue: 0), text: "S → item\(index) •")]
        )
    }
    let transitions = (0..<max(0, stateCount - 1)).map {
        Transition(from: .init(rawValue: $0), symbol: "t\($0)", to: .init(rawValue: $0 + 1))
    } + (stateCount > 2 ? [
        Transition(from: .init(rawValue: 2), symbol: "back", to: .init(rawValue: 0)),
        Transition(from: .init(rawValue: 1), symbol: "loop", to: .init(rawValue: 1))
    ] : [])
    return GrammarArtifact(
        algorithm: .lalr,
        grammarSource: "",
        terminals: [],
        nonterminals: [],
        productions: [Production(id: .init(rawValue: 0), lhs: "S", rhs: [])],
        states: states,
        transitions: transitions,
        cells: [],
        decisions: [],
        sample: ParseSample(input: "", tree: "", trace: [])
    )
}

@Test func layeredLayoutIsDeterministicAndNonOverlapping() {
    let artifact = visualizationArtifact(stateCount: 18)
    let first = AutomatonLayoutEngine.layout(states: artifact.states, transitions: artifact.transitions, compact: false)
    let second = AutomatonLayoutEngine.layout(states: artifact.states, transitions: artifact.transitions, compact: false)
    #expect(first.nodes.count == 18)
    #expect(first.node(.init(rawValue: 0))?.layer == 0)
    #expect(first.nodes.map(\.frame) == second.nodes.map(\.frame))
    #expect(first.edges.map(\.path) == second.edges.map(\.path))
    for (index, node) in first.nodes.enumerated() {
        for other in first.nodes.dropFirst(index + 1) {
            #expect(!node.frame.intersects(other.frame))
        }
    }
}

@Test func layoutRoutesForwardBackAndSelfLoopEdges() {
    let artifact = visualizationArtifact(stateCount: 4)
    let layout = AutomatonLayoutEngine.layout(states: artifact.states, transitions: artifact.transitions, compact: false)
    #expect(layout.edges.contains { $0.transition.symbol == "t0" && $0.path.contains(" C ") })
    #expect(layout.edges.contains { $0.transition.symbol == "back" && $0.path.contains(" L ") })
    #expect(layout.edges.contains { $0.transition.symbol == "loop" && $0.path.contains(" C ") })
}

@Test func largeGraphFilterLimitsRenderingAndKeepsSelection() {
    let artifact = visualizationArtifact(stateCount: 600)
    let result = AutomatonFilter.apply(
        artifact: artifact,
        query: "",
        decisionStatesOnly: false,
        limit: 400,
        selected: .init(rawValue: 599)
    )
    #expect(result.totalMatches == 600)
    #expect(result.truncated)
    #expect(result.visible.count == 401)
    #expect(result.visible.contains(.init(rawValue: 599)))
}

@Test func graphSearchMatchesItemsAndTransitionLabels() {
    let artifact = visualizationArtifact(stateCount: 8)
    let itemMatch = AutomatonFilter.apply(artifact: artifact, query: "item6", decisionStatesOnly: false, limit: 400, selected: nil)
    let edgeMatch = AutomatonFilter.apply(artifact: artifact, query: "back", decisionStatesOnly: false, limit: 400, selected: nil)
    #expect(itemMatch.visible == [.init(rawValue: 6)])
    #expect(edgeMatch.visible == [.init(rawValue: 0), .init(rawValue: 2)])
}

@Test func interactiveSVGContainsMinimapAndGraphControls() {
    let artifact = visualizationArtifact(stateCount: 5)
    let svg = AutomatonSVG.render(artifact, selected: .init(rawValue: 2), detail: .compact, interactive: true)
    #expect(svg.contains("id='minimap'"))
    #expect(svg.contains("id='graph-controls'"))
    #expect(svg.contains("data-state='2'"))
    #expect(svg.contains("selected"))
}

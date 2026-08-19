import Foundation
@testable import GrammarWorkbench
import Testing

private let interactiveGrammar = #"""
%token ID /[a-z]+/
%token PLUS /\+/
%skip /\s+/
%start E
E : E PLUS ID | ID ;
"""#

private func interactiveTimeline() throws -> GrammarParserVisualizationTimeline {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: interactiveGrammar))
    let artifact = try #require(compilation.artifact)
    let parse = compilation.parse("a + b")
    #expect(parse.status == .accepted)
    return try GrammarParserVisualizationBuilder.make(artifact: artifact, parse: parse)
}

@Test func parserTimelineKeepsOneStableLayoutAcrossAllSteps() throws {
    let timeline = try interactiveTimeline()
    #expect(!timeline.frames.isEmpty)
    #expect(timeline.transitions.count == max(0, timeline.frames.count - 1))
    #expect(timeline.frames.last?.action == .accept)
    #expect(timeline.frames.filter { $0.action == .shift }.allSatisfy { $0.activeEdgeID != nil })
    #expect(timeline.frames.filter { $0.action == .reduce }.allSatisfy { $0.activeEdgeID == nil })
    #expect(timeline.frames.compactMap(\.activeStateID).allSatisfy { id in
        timeline.layout.nodes.contains { $0.id == id }
    })
    let encoded = try JSONEncoder().encode(timeline)
    #expect(try JSONDecoder().decode(GrammarParserVisualizationTimeline.self, from: encoded) == timeline)
}

@Test func viewportPansZoomsFitsAndConvertsCoordinates() {
    var viewport = GrammarGraphViewport()
    viewport.fit(
        content: .init(x: 0, y: 0, width: 400, height: 200),
        viewportWidth: 800, viewportHeight: 600, padding: 20
    )
    #expect(viewport.scale > 1)
    let anchor = GrammarGraphPoint(x: 400, y: 300)
    let before = viewport.worldPoint(fromScreen: anchor)
    viewport.zoom(by: 1.25, anchor: anchor)
    #expect(viewport.worldPoint(fromScreen: anchor) == before)
    let previous = viewport.translation
    viewport.pan(x: 12, y: -8)
    #expect(viewport.translation == .init(x: previous.x + 12, y: previous.y - 8))
}

@Test func syntaxTreeProjectionCollapsesStableSubtreeIdentities() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: interactiveGrammar))
    let tree = try #require(compilation.parse("a + b").syntaxTree)
    let expanded = GrammarInteractiveGraphProjection.syntaxTree(tree)
    let collapsed = GrammarInteractiveGraphProjection.syntaxTree(tree, collapsedNodeIDs: ["root"])
    #expect(expanded.graph.nodes.count > 1)
    #expect(collapsed.graph.nodes.map(\.id) == ["root"])
    #expect(collapsed.hiddenNodeCount == expanded.graph.nodes.count - 1)
    #expect(collapsed.graph.nodes[0].metadata["collapsed"] == "true")
}

@Test func sharedForestProjectionCollapsesPackedDescendants() {
    let forest = GrammarSharedParseForest(
        roots: ["root"],
        nodes: [
            .init(id: "root", symbol: "E", span: .init(lowerBound: 0, upperBound: 1), families: [
                .init(id: "family", production: 0, children: ["token"])
            ]),
            .init(id: "token", symbol: "ID", span: .init(lowerBound: 0, upperBound: 1), families: [
                .init(id: "leaf", production: nil, children: [])
            ])
        ]
    )
    let expanded = GrammarInteractiveGraphProjection.sharedForest(forest)
    let collapsed = GrammarInteractiveGraphProjection.sharedForest(
        forest, collapsedNodeIDs: ["symbol:root"]
    )
    #expect(expanded.graph.nodes.count == 4)
    #expect(collapsed.graph.nodes.map(\.id) == ["symbol:root"])
    #expect(collapsed.hiddenNodeCount == 3)
}

@Test func playbackStateClampsStepsAndInteractiveHTMLContainsControls() throws {
    let timeline = try interactiveTimeline()
    var state = GrammarParserVisualizationState()
    state.stepBackward()
    #expect(state.currentFrame == 0)
    state.seek(to: 10_000, frameCount: timeline.frames.count)
    #expect(state.currentFrame == timeline.frames.count - 1)
    state.toggleCollapsed("root")
    #expect(state.collapsedNodeIDs == ["root"])

    let html = try GrammarParserVisualizationHTMLRenderer.render(timeline)
    #expect(html.contains("id='play'"))
    #expect(html.contains("id='minimap'"))
    #expect(html.contains("function fit()"))
    #expect(html.contains("activeStateID"))
    #expect(html.contains("onpointermove"))
}

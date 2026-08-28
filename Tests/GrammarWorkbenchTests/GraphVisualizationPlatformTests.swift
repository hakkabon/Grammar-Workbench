import Foundation
@testable import GrammarWorkbench
import Testing

private func platformGraph() -> GrammarGraph {
    .init(
        id: "pipeline", title: "Pipeline",
        nodes: [
            .init(id: "start", label: "Start", kind: .state, width: 90, height: 48),
            .init(id: "parse", label: "Parse", kind: .state, width: 110, height: 54),
            .init(id: "finish", label: "Finish", kind: .state, width: 94, height: 48)
        ],
        edges: [
            .init(id: "start-parse", source: "start", target: "parse", label: "token"),
            .init(id: "parse-finish", source: "parse", target: "finish", label: "accept"),
            .init(id: "finish-start", source: "finish", target: "start", label: "retry"),
            .init(id: "parse-loop", source: "parse", target: "parse", label: "more")
        ]
    )
}

@Test func rustGraphLayoutIsDeterministicNonOverlappingAndComplete() throws {
    let graph = platformGraph()
    let first = try GrammarGraphLayoutEngine.layout(graph)
    let second = try GrammarGraphLayoutEngine.layout(graph)
    #expect(first.nodes.map(\.frame) == second.nodes.map(\.frame))
    #expect(first.routes.map(\.edge.id) == second.routes.map(\.edge.id))
    #expect(first.nodes.count == graph.nodes.count)
    #expect(first.routes.count == graph.edges.count)
    #expect(first.metrics.engine == "rust-sugiyama")
    #expect(first.metrics.reversedEdgeCount == 1)
    #expect(first.metrics.selfLoopCount == 1)
    for (index, node) in first.nodes.enumerated() {
        for other in first.nodes.dropFirst(index + 1) {
            let overlaps = node.frame.minX < other.frame.maxX
                && node.frame.maxX > other.frame.minX
                && node.frame.minY < other.frame.maxY
                && node.frame.maxY > other.frame.minY
            #expect(!overlaps)
        }
    }
}

@Test func graphLayoutSupportsBothDirectionsAlgorithmsAndRoutes() throws {
    let vertical = try GrammarGraphLayoutEngine.layout(platformGraph(), options: .init(
        algorithm: .medianRelaxation, routing: .orthogonal, direction: .topToBottom
    ))
    let horizontal = try GrammarGraphLayoutEngine.layout(platformGraph(), options: .init(
        algorithm: .balancedAlignment, routing: .straight, direction: .leftToRight
    ))
    let verticalByID = Dictionary(uniqueKeysWithValues: vertical.nodes.map { ($0.id, $0.frame) })
    let horizontalByID = Dictionary(uniqueKeysWithValues: horizontal.nodes.map { ($0.id, $0.frame) })
    #expect(verticalByID["start"]!.midY < verticalByID["parse"]!.midY)
    #expect(horizontalByID["start"]!.midX < horizontalByID["parse"]!.midX)
    #expect(vertical.routes.allSatisfy { !$0.points.isEmpty })
}

@Test func graphLayoutPreservesParallelEdgeIdentity() throws {
    let graph = GrammarGraph(
        id: "parallel", title: "Parallel edges",
        nodes: [.init(id: "a", label: "A"), .init(id: "b", label: "B")],
        edges: [
            .init(id: "second", source: "a", target: "b", label: "two"),
            .init(id: "first", source: "a", target: "b", label: "one")
        ]
    )

    let snapshot = try GrammarGraphLayoutEngine.layout(graph)

    #expect(Set(snapshot.routes.map(\.edge.id)) == ["first", "second"])
    #expect(Dictionary(uniqueKeysWithValues: snapshot.routes.map { ($0.edge.id, $0.edge.label) }) == [
        "first": "one", "second": "two"
    ])
}

@Test func graphPlatformRejectsMalformedInputsBeforeFFI() throws {
    let duplicate = GrammarGraph(
        id: "bad", title: "Bad",
        nodes: [.init(id: "same", label: "A"), .init(id: "same", label: "B")],
        edges: []
    )
    #expect(throws: GrammarGraphLayoutError.self) {
        try GrammarGraphLayoutEngine.layout(duplicate)
    }
    let dangling = GrammarGraph(
        id: "bad", title: "Bad", nodes: [.init(id: "a", label: "A")],
        edges: [.init(id: "missing", source: "a", target: "b")]
    )
    #expect(throws: GrammarGraphLayoutError.self) {
        try GrammarGraphLayoutEngine.layout(dangling)
    }
}

@Test func graphLayoutCacheIsBoundedAndReusesSnapshots() async throws {
    let service = GrammarGraphLayoutService(capacity: 1)
    let first = try await service.layout(platformGraph())
    let cached = try await service.layout(platformGraph())
    #expect(first == cached)
    #expect(await service.cachedLayoutCount == 1)
    _ = try await service.layout(.init(
        id: "other", title: "Other", nodes: [.init(id: "only", label: "Only")], edges: []
    ))
    #expect(await service.cachedLayoutCount == 1)
}

@Test func syntaxForestAndDependencyAdaptersPreserveDomainIdentity() throws {
    let syntax = GrammarSyntaxNode(
        symbol: "S", production: 1, token: nil,
        children: [
            .init(symbol: "ID", production: nil, token: nil, children: [], range: nil, isMissing: false)
        ], range: nil, isMissing: false
    )
    let syntaxGraph = GrammarGraph.syntaxTree(syntax)
    #expect(syntaxGraph.nodes.map(\.id) == ["root", "root.0"])
    #expect(syntaxGraph.edges.count == 1)

    let forest = GrammarSharedParseForest(
        roots: ["root"],
        nodes: [
            .init(
                id: "root", symbol: "S", span: .init(lowerBound: 0, upperBound: 1),
                families: [.init(id: "family", production: 1, children: ["token"])]
            ),
            .init(
                id: "token", symbol: "ID", span: .init(lowerBound: 0, upperBound: 1),
                families: [.init(id: "leaf", production: nil, children: [])]
            )
        ]
    )
    let forestGraph = GrammarGraph.sharedForest(forest)
    #expect(forestGraph.nodes.count == 4)
    #expect(forestGraph.nodes.count { $0.kind == .packed } == 2)
    #expect(try GrammarGraphLayoutEngine.layout(forestGraph, options: .init(direction: .topToBottom)).nodes.count == 4)
}

@Test func graphSnapshotsRoundTripAndExportAccessibleSVG() throws {
    let snapshot = try GrammarGraphLayoutEngine.layout(platformGraph())
    let data = try JSONEncoder().encode(snapshot)
    #expect(try JSONDecoder().decode(GrammarGraphLayoutSnapshot.self, from: data) == snapshot)
    let svg = GrammarGraphSVGRenderer.render(snapshot, selectedNodeID: "parse", interactive: true)
    #expect(svg.contains("id='grammar-graph'"))
    #expect(svg.contains("id='graph-controls'"))
    #expect(svg.contains("data-node='parse'"))
    #expect(svg.contains("selected"))
    #expect(svg.contains("token"))
}

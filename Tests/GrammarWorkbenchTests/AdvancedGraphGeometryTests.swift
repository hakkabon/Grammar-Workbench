import Foundation
@testable import GrammarWorkbench
import Testing

private func geometryGraph() -> GrammarGraph {
    .init(
        id: "geometry", title: "Advanced geometry",
        nodes: [
            .init(id: "root", label: "Root"),
            .init(id: "left", label: "A much longer terminal label", kind: .syntax),
            .init(id: "right", label: "Right", kind: .forest)
        ],
        edges: [
            .init(id: "root-left", source: "root", target: "left", label: "left branch"),
            .init(id: "root-right", source: "root", target: "right", label: "right branch")
        ]
    )
}

private func geometrySpecification() -> GrammarGraphGeometrySpecification {
    .init(
        nodeShapes: ["root": .diamond, "left": .roundedRectangle, "right": .ellipse],
        edgeArrowheads: ["root-left": .open, "root-right": .sweptBack],
        rankConstraints: [.init(id: "leaves", nodeIDs: ["left", "right"])],
        clusters: [.init(id: "tree", label: "Tree", nodeIDs: ["root", "left", "right"])],
        labelOrientation: .tangentAligned
    )
}

@Test func twoPassLayoutMeasuresTextAndHonorsGeometrySpecification() throws {
    let graph = geometryGraph()
    let prepared = GrammarGraphGeometryEngine.prepare(graph, measurer: GrammarGraphHeuristicTextMeasurer())
    #expect(prepared.graph.nodes.first { $0.id == "left" }!.width > graph.nodes.first { $0.id == "left" }!.width)
    #expect(prepared.graph.edges.first?.metadata["geometry.labelWidth"] != nil)
    #expect(prepared.graph.edges.first?.metadata["geometry.labelHeight"] != nil)

    let result = try GrammarGraphGeometryEngine.layout(
        graph, specification: geometrySpecification(), options: .init(direction: .topToBottom)
    )
    #expect(result.nodes.first { $0.id == "root" }?.shape == .diamond)
    #expect(result.routes.first { $0.id == "root-left" }?.arrowheadStyle == .open)
    #expect(result.routes.first { $0.id == "root-right" }?.arrowheadStyle == .sweptBack)
    #expect(result.routes.allSatisfy { $0.label != nil })
    #expect(result.clusters.map(\.id) == ["tree"])
    let leaves = result.nodes.filter { ["left", "right"].contains($0.id) }
    #expect(abs(leaves[0].frame.midY - leaves[1].frame.midY) < 0.001)
    #expect(result.width >= result.layout.width)
}

@Test func shapeAwareIntersectionsLandOnEveryBoundary() {
    let frame = GrammarGraphRect(x: 10, y: 20, width: 100, height: 60)
    let toward = GrammarGraphPoint(x: 200, y: 50)
    for shape in GrammarGraphNodeShape.allCases {
        let point = GrammarGraphGeometry.boundaryIntersection(frame: frame, shape: shape, toward: toward)
        #expect(abs(point.x - frame.maxX) < 0.001)
        #expect(abs(point.y - frame.midY) < 0.001)
    }
}

@Test func spatialIndexFindsNodesLabelsAndClusters() throws {
    let result = try GrammarGraphGeometryEngine.layout(
        geometryGraph(), specification: geometrySpecification(),
        options: .init(direction: .topToBottom)
    )
    let index = GrammarGraphSpatialIndex(snapshot: result, nodeCapacity: 2)
    let root = try #require(result.nodes.first { $0.id == "root" })
    #expect(index.query(point: .init(x: root.frame.midX, y: root.frame.midY)).contains { $0.id == "root" && $0.kind == .node })
    let cluster = try #require(result.clusters.first)
    #expect(index.query(cluster.frame).contains { $0.id == "tree" && $0.kind == .cluster })
    let label = try #require(result.routes.first?.label)
    #expect(index.query(point: label.position).contains { $0.kind == .edgeLabel })
}

@Test func advancedSVGAndDOTPreserveGeometrySemantics() throws {
    let specification = geometrySpecification()
    let result = try GrammarGraphGeometryEngine.layout(geometryGraph(), specification: specification)
    let svg = GrammarGraphAdvancedSVGRenderer.render(result)
    #expect(svg.contains("shape-diamond"))
    #expect(svg.contains("class='arrow open'"))
    #expect(svg.contains("id='clusters'"))
    #expect(svg.contains("transform='rotate("))
    let dot = GrammarGraphAdvancedDOTRenderer.render(geometryGraph(), specification: specification)
    #expect(dot.contains("rank=same"))
    #expect(dot.contains("subgraph \"cluster_tree\""))
    #expect(dot.contains("arrowhead=onormal"))
}

@Test func geometrySpecificationRejectsUnknownReferences() {
    let specification = GrammarGraphGeometrySpecification(
        rankConstraints: [.init(id: "bad", nodeIDs: ["missing"])]
    )
    #expect(throws: GrammarGraphGeometryError.self) {
        try GrammarGraphGeometryEngine.layout(geometryGraph(), specification: specification)
    }
}

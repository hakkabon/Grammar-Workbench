import Foundation
@testable import GrammarWorkbench
import Testing

private func correctnessGraph() -> GrammarGraph {
    .init(
        id: "correctness", title: "Correctness",
        nodes: [
            .init(id: "a", label: "A", width: 90, height: 44),
            .init(id: "b", label: "B", width: 110, height: 52),
            .init(id: "c", label: "C", width: 80, height: 40)
        ],
        edges: [
            .init(id: "ab", source: "a", target: "b", label: "next"),
            .init(id: "bc", source: "b", target: "c"),
            .init(id: "ca", source: "c", target: "a"),
            .init(id: "bb", source: "b", target: "b")
        ]
    )
}

@Test func validatorReportsStructuralAndPositionedFailures() throws {
    let malformed = GrammarGraph(
        id: "bad", title: "Bad",
        nodes: [.init(id: "same", label: "A"), .init(id: "same", label: "B", width: 0)],
        edges: [.init(id: "edge", source: "same", target: "missing")]
    )
    let structural = GrammarGraphValidator.validate(malformed)
    #expect(!structural.isValid)
    #expect(structural.issues.contains { $0.code == .duplicateNode })
    #expect(structural.issues.contains { $0.code == .invalidNodeSize })
    #expect(structural.issues.contains { $0.code == .danglingTarget })

    let graph = correctnessGraph()
    let layout = try GrammarGraphLayoutEngine.layout(graph)
    let report = GrammarGraphValidator.validate(layout, against: graph)
    #expect(report.isValid)
    #expect(!report.issues.contains { $0.code == .nodeOverlap })
}

@Test func measuredLayoutSeparatesBoundaryAndValidationTiming() throws {
    let result = try GrammarGraphMeasurementRunner.layout(correctnessGraph())
    #expect(result.correctness.isValid)
    #expect(result.measurement.totalNanoseconds > 0)
    #expect(result.measurement.layoutBoundaryNanoseconds >= result.measurement.engineReportedNanoseconds)
    #expect(result.snapshot.routes.count == 4)
    let roundTrip = try JSONDecoder().decode(
        GrammarGraphMeasuredLayout.self,
        from: JSONEncoder().encode(result)
    )
    #expect(roundTrip.snapshot == result.snapshot)
}

@Test func deterministicCorpusCoversPathologiesAndLayoutsCleanly() throws {
    let configuration = GrammarGraphCorpusConfiguration(
        seed: 42, caseCount: 10, maximumNodes: 12, edgeProbabilityPercent: 28
    )
    let first = GrammarGraphCorpus.generate(configuration)
    let second = GrammarGraphCorpus.generate(configuration)
    #expect(first == second)
    #expect(first.contains { $0.edges.contains { $0.source == $0.target } })
    #expect(first.contains { graph in
        Set(graph.edges.map { "\($0.source)->\($0.target)" }).count < graph.edges.count
    })
    for graph in first {
        let snapshot = try GrammarGraphLayoutEngine.layout(graph, options: .init(routing: .orthogonal))
        #expect(GrammarGraphValidator.validate(snapshot, against: graph).isValid)
    }
}

@Test func failureMinimizerAndDOTOutputAreStable() throws {
    let graph = correctnessGraph()
    let minimized = GrammarGraphFailureMinimizer.minimize(graph) { candidate in
        candidate.edges.contains { $0.id == "bb" }
    }
    #expect(minimized.edges.map(\.id) == ["bb"])
    #expect(minimized.nodes.map(\.id) == ["b"])

    let first = GrammarGraphDOTRenderer.render(graph)
    let second = GrammarGraphDOTRenderer.render(graph)
    #expect(first == second)
    #expect(first.contains("digraph \"correctness\""))
    #expect(first.contains("\"a\" -> \"b\" [id=\"ab\", label=\"next\"]"))
}

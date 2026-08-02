import Foundation
import Testing
@testable import GrammarWorkbench

private func decisionArtifact(_ source: String, algorithm: LRAlgorithm = .lalr) throws -> GrammarArtifact {
    let result = GrammarFrontEnd.process(source)
    return LRConstructionEngine.construct(
        grammar: try #require(result.grammar),
        analysis: try #require(result.analysis),
        source: source,
        algorithm: algorithm
    )
}

@Test func startupExpressionStatesAreClassifiedAsResolvedDecisions() throws {
    let artifact = try decisionArtifact(GrammarWorkbenchDocument.defaultSource)
    for rawState in [5, 6] {
        let summary = try #require(artifact.decisionSummary(for: .init(rawValue: rawState)))
        #expect(summary.disposition == .resolved)
        #expect(summary.decisions.count == 2)
        #expect(summary.decisions.allSatisfy { artifact.candidateActions(for: $0).count == 2 })
        #expect(summary.decisions.allSatisfy { artifact.cell($0.cell)?.actions.count == 1 })
    }
}

@Test func automatonSVGMarksResolvedStatesWithBadgesAndAccessibility() throws {
    let artifact = try decisionArtifact(GrammarWorkbenchDocument.defaultSource)
    let svg = AutomatonSVG.render(artifact, selected: nil)
    #expect(svg.contains("class='node decision-resolved' data-state='5'"))
    #expect(svg.contains("class='node decision-resolved' data-state='6'"))
    #expect(svg.contains("aria-label='I5, Resolved decision, 2 decisions'"))
    #expect(svg.contains("decision-badge resolved"))
    #expect(svg.contains("mini-resolved"))
}

@Test func decisionFiltersSeparateResolvedUnresolvedAndExpectedStates() throws {
    let resolved = try decisionArtifact(GrammarWorkbenchDocument.defaultSource)
    let resolvedFilter = AutomatonFilter.apply(
        artifact: resolved, query: "", decisionFilter: .resolved, limit: 400, selected: nil
    )
    #expect(resolvedFilter.visible == [.init(rawValue: 5), .init(rawValue: 6)])

    let unresolved = try decisionArtifact("%start E\nE : E '+' E | 'id' ;")
    let unresolvedFilter = AutomatonFilter.apply(
        artifact: unresolved, query: "", decisionFilter: .unresolved, limit: 400, selected: nil
    )
    #expect(unresolvedFilter.visible.count == 1)
    #expect(unresolvedFilter.visible.allSatisfy { unresolved.decisionSummary(for: $0)?.disposition == .unresolved })

    let expected = try decisionArtifact("%start E\n%expect 1\nE : E '+' E | 'id' ;")
    let expectedFilter = AutomatonFilter.apply(
        artifact: expected, query: "", decisionFilter: .expected, limit: 400, selected: nil
    )
    #expect(expectedFilter.visible.count == 1)
    #expect(expectedFilter.visible.allSatisfy { expected.decisionSummary(for: $0)?.disposition == .expected })
}

@Test func nonassociativeDecisionRetainsCandidatesAndEffectiveError() throws {
    let artifact = try decisionArtifact("%start E\n%nonassoc '<'\nE : E '<' E | 'id' ;")
    let decision = try #require(artifact.decisions.first)
    #expect(decision.disposition == .resolved)
    #expect(artifact.candidateActions(for: decision).count == 2)
    #expect(artifact.cell(decision.cell) == nil)
}

@Test func olderDecisionJSONWithoutCandidatesStillDecodes() throws {
    let artifact = try decisionArtifact(GrammarWorkbenchDocument.defaultSource)
    let decision = try #require(artifact.decisions.first)
    let encoded = try JSONEncoder().encode(decision)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "candidateActions")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(ConflictDecision.self, from: legacy)
    #expect(decoded.candidateActions.isEmpty)
    #expect(decoded.disposition == .resolved)
}

@Test func standaloneReportShowsCandidatesAndEffectiveResolvedActions() throws {
    let artifact = try decisionArtifact(GrammarWorkbenchDocument.defaultSource)
    let html = HTMLExporter.render(artifact)
    #expect(html.contains("class='decision-resolved'"))
    #expect(html.contains("Candidate actions:</strong>"))
    #expect(html.contains("Effective action:</strong>"))
    #expect(html.contains("Resolved decision: candidates"))
}

import Foundation
import Testing
@testable import GrammarWorkbench

private let integratedProjectGrammar = #"""
%token LET /let\b/
%token USE /use\b/
%token ID /[A-Za-z_][A-Za-z0-9_]*/
%token SEMI /;/
%skip /\s+/
%start Program
Program : Program Statement | Statement ;
Statement : LET ID SEMI | USE ID SEMI ;
"""#

@Test func documentExperienceUnifiesGrammarDecisionsTestsAndNavigation() {
    let compilation = GrammarWorkbenchAPI.compile(.init(
        source: "%start E\nE : E '+' E | 'id' ;"
    ))
    let tests: [WorkbenchTestCase] = [
        .init(name: "Wrong expectation", input: "id", expectation: .reject)
    ]
    let report = compilation.runTests(tests)
    let snapshot = GrammarProjectExperience.snapshot(
        name: "Expressions", compilation: compilation,
        samples: [.init(name: "Example", input: "id + id + id")],
        tests: tests, testReport: report,
        operations: [.init(kind: .comparingAlgorithms, title: "Comparing", detail: "Three artifacts")]
    )

    #expect(snapshot.navigator.map(\.area) == [.grammar, .sources, .tests, .semantics, .generation])
    #expect(snapshot.problems.contains { $0.destination == .decisions })
    #expect(snapshot.problems.contains { $0.destination == .tests })
    #expect(snapshot.problems.first?.severity == .error)
    #expect(snapshot.isBusy)
    #expect(snapshot.healthScore < 100)
}

@Test func multiDocumentExperienceIncludesSourceAndSemanticProblems() async throws {
    let manifest = GrammarProjectManifest(
        name: "Language project", grammar: .init(source: integratedProjectGrammar),
        sources: [
            .init(id: "definitions", path: "Definitions.lang", text: "let alpha;"),
            .init(id: "uses", path: "Uses.lang", text: "use missing;")
        ]
    )
    let workspace = try GrammarProjectWorkspace(manifest: manifest)
    let analysis = try await workspace.analyze()
    let model = try GrammarSemanticModel(compilation: analysis.compilation)
    let definition = try #require(model.productions(lhs: "Statement", rhs: ["LET", "ID", "SEMI"]).first)
    let reference = try #require(model.productions(lhs: "Statement", rhs: ["USE", "ID", "SEMI"]).first)
    let semantics = analysis.semanticWorkspace(schema: .init(rules: [
        .init(tokenKind: "ID", enclosingProduction: definition.id, kind: "variable", role: .definition),
        .init(tokenKind: "ID", enclosingProduction: reference.id, kind: "variable", role: .reference)
    ]))
    let snapshot = GrammarProjectExperience.snapshot(analysis: analysis, semantics: semantics)

    #expect(snapshot.navigator.first { $0.area == .sources }?.count == 2)
    #expect(snapshot.symbolCount == 1)
    #expect(snapshot.problems.contains {
        $0.area == .semantics && $0.documentID == "uses" && $0.path == "Uses.lang"
    })
    #expect(snapshot.errorCount == 1)
}

@Test func projectExperienceIsStableJSON() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'ok' ;"))
    let snapshot = GrammarProjectExperience.snapshot(
        name: "Small", compilation: compilation, samples: [], tests: []
    )
    let encoded = try JSONEncoder().encode(snapshot)
    #expect(try JSONDecoder().decode(GrammarProjectExperienceSnapshot.self, from: encoded) == snapshot)
}

#if os(macOS)
@MainActor @Test func explorerStorePublishesIntegratedOperationStatus() {
    let store = ExplorerStore(source: "%start S\nS : 'ok' ;")
    store.updateSource("%start S\nS : 'next' ;", debounceNanoseconds: 5_000_000_000)
    let snapshot = store.projectExperience(samples: [], tests: [])
    #expect(snapshot.operations.contains { $0.kind == .compiling })
}

@MainActor @Test func projectProblemsUseNewestInvalidEditWhileArtifactRemainsUsable() async throws {
    let store = ExplorerStore(source: "%start S\nS : 'ok' ;")
    let originalStates = store.artifact.states.count
    store.updateSource("%start S\n%token ID\nS : Missing ;", debounceNanoseconds: 0)
    for _ in 0..<100 where store.isRegenerating {
        try await Task.sleep(for: .milliseconds(10))
    }
    let snapshot = store.projectExperience(samples: [], tests: [])
    #expect(snapshot.problems.contains { $0.area == .grammar && $0.severity == .error })
    #expect(store.artifact.states.count == originalStates)
}
#endif

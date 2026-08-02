import Testing
@testable import GrammarWorkbench

private func runtimeArtifact(_ source: String, algorithm: LRAlgorithm = .lalr) throws -> GrammarArtifact {
    let frontEnd = GrammarFrontEnd.process(source)
    return try LRConstructionEngine.construct(
        grammar: #require(frontEnd.grammar),
        analysis: #require(frontEnd.analysis),
        source: source,
        algorithm: algorithm
    )
}

@Test func runtimeAcceptsInputAndBuildsTree() throws {
    let artifact = try runtimeArtifact("""
    %start List
    List : List ',' Item | Item ;
    Item : 'id' ;
    """)
    let result = LRParserRuntime.parse(["id", ",", "id"], artifact: artifact)
    #expect(result.outcome == .accepted)
    #expect(result.tree?.symbol == "List")
    #expect(result.tree?.rendered().contains("├─ List") == true)
    #expect(result.frames.last?.action == "accept")
    #expect(result.frames.contains { $0.production != nil })
    #expect(result.frames.allSatisfy { $0.state != nil && $0.cell != nil })
}

@Test func runtimeHandlesEmptyProductions() throws {
    let artifact = try runtimeArtifact("%start Optional\nOptional : 'value' | ;")
    let result = LRParserRuntime.parse([], artifact: artifact)
    #expect(result.outcome == .accepted)
    #expect(result.tree?.symbol == "Optional")
    #expect(result.frames.contains { $0.action.contains("Optional → ε") })
}

@Test func runtimeReportsUnknownAndExpectedTerminals() throws {
    let artifact = try runtimeArtifact("%start S\nS : 'id' '+' 'id' ;")
    let unknown = LRParserRuntime.parse(["number"], artifact: artifact)
    #expect(unknown.outcome.label.contains("Unknown terminal"))

    let incomplete = LRParserRuntime.parse(["id"], artifact: artifact)
    guard case .rejected(_, let expected) = incomplete.outcome else {
        Issue.record("Expected rejected outcome")
        return
    }
    #expect(expected == ["+"])
}

@Test func tokenizerSupportsQuotedWhitespaceSeparatedTokens() throws {
    let tokens = try SampleInputTokenizer.tokenize("'id' \"+\" value").get()
    #expect(tokens == ["id", "+", "value"])
    #expect(SampleInputTokenizer.tokenize("'unterminated").isFailure)
}

@Test func unresolvedConflictHasVerifiedWitnessAndClassifiedBranches() throws {
    let artifact = try runtimeArtifact("""
    %start E
    E : E '+' E | 'id' ;
    """)
    let decision = try #require(artifact.decisions.first { artifact.cell($0.cell)?.isConflict == true })
    #expect(decision.explanation.contains("verified by parser replay"))
    #expect(!decision.witness.isEmpty)
    #expect(LRParserRuntime.parse(decision.witness, artifact: artifact).outcome == .conflict(decision.cell))
    #expect(decision.branches.count == artifact.cell(decision.cell)?.actions.count)
    #expect(decision.branches.allSatisfy {
        guard let classification = $0.last?.action else { return false }
        return ["Accepted", "Rejected", "Incomplete", "Looping"].contains { classification.hasPrefix($0) }
    })
}

@Test func standaloneExportIncludesLiveTreeAndTrace() throws {
    let artifact = try runtimeArtifact("%start S\nS : 'id' ;")
    let runtime = LRParserRuntime.parse(["id"], artifact: artifact)
    let html = HTMLExporter.render(artifact, runtime: runtime)
    #expect(html.contains("Accepted"))
    #expect(html.contains("<h3>Trace</h3>"))
    #expect(html.contains("reduce S → id"))
}

@Test func diagnosticRuntimeDeletesAndInsertsTokensThenContinues() throws {
    let artifact = try runtimeArtifact("%start S\nS : 'id' '+' 'id' ;")

    let extra = LRParserRuntime.parse(
        ["id", "extra", "+", "id"], artifact: artifact, recovery: .diagnostic
    )
    #expect(extra.outcome == .accepted)
    #expect(extra.diagnostics.map(\.recovery) == [.deletedToken])
    #expect(extra.frames.contains { $0.action.contains("recover: delete") })

    let missing = LRParserRuntime.parse(["id", "id"], artifact: artifact, recovery: .diagnostic)
    #expect(missing.outcome == .accepted)
    #expect(missing.diagnostics.map(\.recovery) == [.insertedToken])
    #expect(missing.tree?.rendered().contains("⟨missing +⟩") == true)
}

@Test func diagnosticRuntimeReportsMultipleErrorsAndHonorsLimit() throws {
    let artifact = try runtimeArtifact("%start S\nS : 'id' '+' 'id' ;")
    let recovered = LRParserRuntime.parse(
        ["junk", "id", "junk", "id"], artifact: artifact, recovery: .diagnostic
    )
    #expect(recovered.outcome == .accepted)
    #expect(recovered.diagnostics.count == 3)

    let limited = LRParserRuntime.parse(
        ["junk", "id", "junk", "id"], artifact: artifact,
        recovery: .init(maximumDiagnostics: 1)
    )
    guard case .rejected = limited.outcome else {
        Issue.record("Expected recovery to stop at the diagnostic limit")
        return
    }
    #expect(limited.diagnostics.count == 1)
}

@Test func diagnosticRuntimeUsesPanicSynchronizationAndKeepsTraceIdentitiesUnique() throws {
    let artifact = try runtimeArtifact("%start S\nS : 'id' ;")
    let result = LRParserRuntime.parse(
        ["id", "junk", "more"], artifact: artifact, recovery: .diagnostic
    )
    #expect(result.outcome == .accepted)
    #expect(result.diagnostics.map(\.recovery) == [.synchronized])
    #expect(result.diagnostics[0].recoveryDetail?.contains("Discarded 2 token") == true)
    #expect(Set(result.frames.map(\.id)).count == result.frames.count)
}

@Test func standaloneExportIncludesSyntaxRecoveryDiagnostics() throws {
    let artifact = try runtimeArtifact("%start S\nS : 'id' '+' 'id' ;")
    let runtime = LRParserRuntime.parse(["id", "id"], artifact: artifact, recovery: .diagnostic)
    let html = HTMLExporter.render(artifact, runtime: runtime)
    #expect(html.contains("Syntax diagnostics and recovery"))
    #expect(html.contains("Inserted missing ‘+’"))
    #expect(html.contains("recover: insert missing"))
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { true } else { false }
    }
}

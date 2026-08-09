import Foundation
import GrammarWorkbench
import Testing

private let platformAmbiguousGrammar = "%start E\nE : E '+' E | 'id' ;"

private struct PlatformReducer: GrammarSemanticReducer {
    func terminal(_ token: GrammarInputTokenSnapshot, node: GrammarSyntaxNode) -> String {
        token.lexeme
    }
    func missing(symbol: String, node: GrammarSyntaxNode) -> String { "<\(symbol)>" }
    func reduce(
        production: GrammarProductionSnapshot, children: [String], node: GrammarSyntaxNode
    ) -> String {
        production.rhs.count == 3 ? "(\(children.joined()))" : children.joined()
    }
}

@Test func adaptivePlatformEscalatesOnlyAtAnUnresolvedConflict() throws {
    let ambiguous = GrammarWorkbenchAPI.compile(.init(source: platformAmbiguousGrammar))
    let platform = try GrammarParsingPlatform(compilation: ambiguous)
    let result = platform.parse(.init(id: "ambiguous", input: "id + id + id"))

    #expect(result.id == "ambiguous")
    #expect(result.engine == .generalized)
    #expect(result.status == .ambiguous)
    #expect(result.deterministic?.status == .conflict)
    #expect(result.generalized?.alternatives.count == 2)
    #expect(result.selectedTree == nil)
    #expect(result.metrics.deterministicAttempts == 1)
    #expect(result.decision.contains("escalated"))

    let deterministic = try GrammarParsingPlatform(compilation: GrammarWorkbenchAPI.compile(
        .init(source: "%start S\nS : 'id' ;")
    )).parse(.init(id: "unique", input: "id"))
    #expect(deterministic.engine == .deterministic)
    #expect(deterministic.status == .accepted)
    #expect(deterministic.selectedTree != nil)
}

@Test func platformAmbiguityPoliciesSelectReproducibleAlternatives() throws {
    let platform = try GrammarParsingPlatform(compilation: GrammarWorkbenchAPI.compile(
        .init(source: platformAmbiguousGrammar)
    ))
    let stable = platform.parse(.init(
        input: "id + id + id",
        options: .init(mode: .generalized, ambiguitySelection: .firstStable)
    ))
    let repeated = platform.parse(.init(
        input: "id + id + id",
        options: .init(mode: .generalized, ambiguitySelection: .firstStable)
    ))

    #expect(stable.status == .ambiguous)
    #expect(stable.isAccepted)
    #expect(stable.selectedAlternativeID == repeated.selectedAlternativeID)
    #expect(stable.selectedTree != nil)
    #expect(stable.decision.contains("Selected stable alternative"))

    let shallowest = platform.parse(.init(
        input: "id + id + id + id",
        options: .init(mode: .generalized, ambiguitySelection: .shallowest)
    ))
    let deepest = platform.parse(.init(
        input: "id + id + id + id",
        options: .init(mode: .generalized, ambiguitySelection: .deepest)
    ))
    #expect(shallowest.selectedAlternativeID != nil)
    #expect(deepest.selectedAlternativeID != nil)
}

@Test func platformPreservesRecoveryAndGeneralizedLimits() throws {
    let deterministic = try GrammarParsingPlatform(compilation: GrammarWorkbenchAPI.compile(
        .init(source: "%start S\nS : 'a' 'b' ;")
    )).parse(.init(input: "a"))
    #expect(deterministic.status == .recovered)
    #expect(deterministic.deterministic?.diagnostics.first?.recovery == .insertedToken)

    let generalized = try GrammarParsingPlatform(compilation: GrammarWorkbenchAPI.compile(
        .init(source: platformAmbiguousGrammar)
    )).parse(.init(
        input: "id + id + id + id",
        options: .init(
            mode: .generalized,
            generalized: .init(maximumTrees: 1),
            ambiguitySelection: .firstStable
        )
    ))
    #expect(generalized.status == .limited)
    #expect(generalized.metrics.reachedLimits == [.trees])
    #expect(generalized.selectedTree != nil)
}

@Test func platformBatchIsBoundedAndPreservesRequestOrder() async throws {
    let platform = try GrammarParsingPlatform(compilation: GrammarWorkbenchAPI.compile(
        .init(source: platformAmbiguousGrammar)
    ))
    let requests = (0..<20).map {
        GrammarPlatformParseRequest(
            id: "request-\($0)",
            input: $0.isMultiple(of: 2) ? "id" : "id + id + id",
            options: .init(ambiguitySelection: .firstStable)
        )
    }
    let batch = await platform.parseBatch(
        requests, options: .init(maximumConcurrentRequests: 3)
    )

    #expect(batch.results.map(\.id) == requests.map(\.id))
    #expect(batch.accepted == requests.count)
    #expect(batch.failed == 0)
    #expect(batch.metrics.maximumConcurrentRequests == 3)
    #expect(batch.metrics.completedRequests == requests.count)
    #expect(batch.results.contains { $0.engine == .deterministic })
    #expect(batch.results.contains { $0.engine == .generalized })
}

@Test func cancellablePlatformStopsBeforeParsingWhenAlreadyCancelled() async throws {
    let platform = try GrammarParsingPlatform(compilation: GrammarWorkbenchAPI.compile(
        .init(source: platformAmbiguousGrammar)
    ))
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await platform.parseCancellable(.init(input: "id + id + id"))
    }
    let result = await task.value
    #expect(result.status == .cancelled)
    #expect(result.selectedTree == nil)
}

@Test func platformEvaluatesTheSelectedAlternativeSemantically() throws {
    let platform = try GrammarParsingPlatform(compilation: GrammarWorkbenchAPI.compile(
        .init(source: platformAmbiguousGrammar)
    ))
    let semantic = try platform.parse(
        .init(
            input: "id + id + id",
            options: .init(ambiguitySelection: .firstStable)
        ),
        using: PlatformReducer()
    )
    #expect(semantic.parse.status == .ambiguous)
    #expect(semantic.value.contains("("))

    #expect(throws: GrammarSemanticError.self) {
        try platform.parse(.init(input: "id + id + id"), using: PlatformReducer())
    }
}

@Test func platformRequestsAndResultsHaveStableCodableContracts() throws {
    let legacyOptions = try JSONDecoder().decode(
        GrammarPlatformParseOptions.self, from: Data("{}".utf8)
    )
    #expect(legacyOptions.mode == .adaptive)
    #expect(legacyOptions.ambiguitySelection == .requireUnique)

    let platform = try GrammarParsingPlatform(compilation: GrammarWorkbenchAPI.compile(
        .init(source: platformAmbiguousGrammar)
    ))
    let result = platform.parse(.init(
        id: "encoded", input: "id + id + id",
        options: .init(ambiguitySelection: .firstStable)
    ))
    let decoded = try JSONDecoder().decode(
        GrammarPlatformParseResult.self, from: JSONEncoder().encode(result)
    )
    #expect(decoded == result)
}

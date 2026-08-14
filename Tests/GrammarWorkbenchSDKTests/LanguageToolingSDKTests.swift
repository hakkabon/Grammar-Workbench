import Foundation
import GrammarWorkbench
import GrammarWorkbenchSDK
import Testing

private let expressionGrammar = """
%start E
%token ID /[A-Za-z]+/
%skip /\\s+/
E : E '+' ID | ID ;
"""

@Test func capabilitiesRoundTripThroughInProcessTransport() async throws {
    let client = GrammarToolingClient(transport: GrammarInProcessToolingTransport())
    let response = try await client.send(.init(requestID: "cap-1", operation: .capabilities))
    #expect(response.status == .success)
    #expect(response.requestID == "cap-1")
    #expect(response.capabilities?.operations.contains(.semanticWorkspace) == true)
    #expect(response.capabilities?.transports == ["in-process", "json"])
}

@Test func deterministicParseReturnsCompilationAndParseSnapshots() async {
    let response = await GrammarLanguageToolingService().handle(.init(
        requestID: "parse-1", operation: .parse,
        compilation: .init(source: expressionGrammar), input: "alpha + beta"
    ))
    #expect(response.status == .success)
    #expect(response.compilation?.succeeded == true)
    #expect(response.parse?.status == .accepted)
}

@Test func missingPayloadAndVersionsProduceStableFailures() async {
    let missing = await GrammarLanguageToolingService().handle(.init(operation: .parse))
    #expect(missing.status == .failure)
    #expect(missing.error?.code == "invalid-request")
    let incompatible = await GrammarLanguageToolingService().handle(.init(
        operation: .capabilities, schemaVersion: 99
    ))
    #expect(incompatible.error?.code == "unsupported-schema")
}

@Test func projectAnalysisUsesPortableSummary() async {
    let manifest = GrammarProjectManifest(
        name: "SDK sample", grammar: .init(source: expressionGrammar),
        sources: [.init(id: "main", path: "Sources/main.expr", text: "alpha + beta")]
    )
    let response = await GrammarLanguageToolingService().handle(.init(
        operation: .projectAnalyze, project: manifest
    ))
    #expect(response.status == .success)
    #expect(response.project?.succeeded == true)
    #expect(response.project?.documents.first?.parseStatus == .accepted)
}

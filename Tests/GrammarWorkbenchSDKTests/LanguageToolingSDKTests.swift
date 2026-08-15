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

private struct StatefulReleasePolicy: Decodable {
    struct Budgets: Decodable {
        let statefulToolingMaximumSessions: Int
        let statefulToolingMaximumDocumentsPerSession: Int
    }
    let budgets: Budgets
}

@Test func capabilitiesRoundTripThroughInProcessTransport() async throws {
    let client = GrammarToolingClient(transport: GrammarInProcessToolingTransport())
    let response = try await client.send(.init(requestID: "cap-1", operation: .capabilities))
    #expect(response.status == .success)
    #expect(response.requestID == "cap-1")
    #expect(response.capabilities?.operations.contains(.semanticWorkspace) == true)
    #expect(response.capabilities?.transports == ["in-process", "json"])
    #expect(response.capabilities?.operations.contains(.sessionOpen) == false)
}

@Test func statefulCapabilitiesAdvertiseSessionsAndJSONLines() async throws {
    let client = GrammarToolingClient(transport: GrammarStatefulInProcessToolingTransport())
    let response = try await client.send(.init(operation: .capabilities))
    #expect(response.capabilities?.operations.contains(.sessionOpen) == true)
    #expect(response.capabilities?.operations.contains(.cancel) == true)
    #expect(response.capabilities?.transports.contains("json-lines") == true)
}

@Test func statefulSessionMaintainsIncrementalDocumentLifecycle() async throws {
    let client = GrammarToolingClient(transport: GrammarStatefulInProcessToolingTransport())
    let opened = try await client.send(.init(
        requestID: "session-open", operation: .sessionOpen,
        compilation: .init(source: expressionGrammar), sessionID: "editor"
    ))
    #expect(opened.status == .success)
    #expect(opened.session?.id == "editor")
    #expect(opened.events?.first?.kind == .sessionOpened)
    #expect(opened.session?.nextEventSequence == 1)

    let document = try await client.send(.init(
        requestID: "document-open", operation: .documentOpen,
        input: "alpha + beta", sessionID: "editor", documentID: "main", revision: 1
    ))
    #expect(document.document?.parse.status == .accepted)
    #expect(document.document?.text.revision == 1)
    #expect(document.session?.documents.map(\.id) == ["main"])

    let changed = try await client.send(.init(
        requestID: "document-change", operation: .documentChange,
        sessionID: "editor", documentID: "main", revision: 2,
        edits: [.init(
            range: .init(
                start: .init(line: 0, utf16Column: 8),
                end: .init(line: 0, utf16Column: 12)
            ),
            replacement: "gamma"
        )]
    ))
    #expect(changed.document?.text.text == "alpha + gamma")
    #expect(changed.document?.incrementalLexing.strategy == .incremental)
    #expect(changed.events?.first?.sequence == 2)

    let status = try await client.send(.init(
        operation: .sessionStatus, sessionID: "editor"
    ))
    #expect(status.session?.documents.first?.revision == 2)

    let closedDocument = try await client.send(.init(
        operation: .documentClose, sessionID: "editor", documentID: "main"
    ))
    #expect(closedDocument.session?.documents.isEmpty == true)
    let closedSession = try await client.send(.init(
        operation: .sessionClose, sessionID: "editor"
    ))
    #expect(closedSession.events?.first?.kind == .sessionClosed)
}

@Test func statefulSessionReanalyzesDocumentsAfterGrammarReplacement() async throws {
    let service = GrammarStatefulLanguageToolingService()
    _ = await service.handle(.init(
        operation: .sessionOpen, compilation: .init(source: expressionGrammar), sessionID: "replace"
    ))
    _ = await service.handle(.init(
        operation: .documentOpen, input: "alpha + beta",
        sessionID: "replace", documentID: "main", revision: 1
    ))
    let replacement = await service.handle(.init(
        operation: .sessionReplaceGrammar,
        compilation: .init(source: expressionGrammar + "\nUnused : 'unused' ;"),
        sessionID: "replace"
    ))
    #expect(replacement.status == .success)
    #expect(replacement.session?.grammarRevision == 1)
    #expect(replacement.session?.documents.first?.parseStatus == .accepted)
    #expect(replacement.events?.first?.kind == .grammarReplaced)
}

@Test func statefulServiceReturnsStableLifecycleErrors() async {
    let service = GrammarStatefulLanguageToolingService()
    let missing = await service.handle(.init(
        operation: .sessionStatus, sessionID: "missing"
    ))
    #expect(missing.error?.code == "unknown-session")

    _ = await service.handle(.init(
        operation: .sessionOpen, compilation: .init(source: expressionGrammar), sessionID: "same"
    ))
    let duplicate = await service.handle(.init(
        operation: .sessionOpen, compilation: .init(source: expressionGrammar), sessionID: "same"
    ))
    #expect(duplicate.error?.code == "duplicate-session")
}

@Test func statefulServiceEnforcesExplicitResourceLimits() async {
    let service = GrammarStatefulLanguageToolingService(limits: .init(
        maximumSessions: 1, maximumDocumentsPerSession: 1,
        maximumDocumentUTF16Length: 16
    ))
    _ = await service.handle(.init(
        operation: .sessionOpen, compilation: .init(source: expressionGrammar), sessionID: "one"
    ))
    let tooManySessions = await service.handle(.init(
        operation: .sessionOpen, compilation: .init(source: expressionGrammar), sessionID: "two"
    ))
    #expect(tooManySessions.error?.code == "resource-limit")
    _ = await service.handle(.init(
        operation: .documentOpen, input: "alpha", sessionID: "one", documentID: "first"
    ))
    let tooManyDocuments = await service.handle(.init(
        operation: .documentOpen, input: "beta", sessionID: "one", documentID: "second"
    ))
    #expect(tooManyDocuments.error?.code == "resource-limit")
    let smallService = GrammarStatefulLanguageToolingService(limits: .init(
        maximumDocumentUTF16Length: 3
    ))
    _ = await smallService.handle(.init(
        operation: .sessionOpen, compilation: .init(source: expressionGrammar), sessionID: "small"
    ))
    let tooLarge = await smallService.handle(.init(
        operation: .documentOpen, input: "four", sessionID: "small", documentID: "large"
    ))
    #expect(tooLarge.error?.code == "resource-limit")
}

@Test func statefulWireFieldsRoundTrip() throws {
    let request = GrammarToolingRequest(
        requestID: "change", operation: .documentChange,
        sessionID: "workspace", documentID: "main", revision: 4,
        edits: [.init(range: nil, replacement: "new text")]
    )
    let data = try GrammarToolingCodec.encodeLine(request)
    #expect(!String(decoding: data, as: UTF8.self).contains("\n"))
    #expect(try GrammarToolingCodec.decodeRequest(data) == request)
}

@Test func statefulServiceStaysWithinDeclaredReleaseBounds() async throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let policy = try JSONDecoder().decode(
        StatefulReleasePolicy.self,
        from: Data(contentsOf: root.appendingPathComponent("Packaging/ReleaseCandidate.json"))
    )
    let service = GrammarStatefulLanguageToolingService()
    for index in 0..<policy.budgets.statefulToolingMaximumSessions {
        let sessionID = "bounded-\(index)"
        let opened = await service.handle(.init(
            operation: .sessionOpen,
            compilation: .init(source: expressionGrammar), sessionID: sessionID
        ))
        #expect(opened.status == .success)
        for document in 0..<policy.budgets.statefulToolingMaximumDocumentsPerSession {
            let response = await service.handle(.init(
                operation: .documentOpen, input: "alpha + beta",
                sessionID: sessionID, documentID: "document-\(document)"
            ))
            #expect(response.status == .success)
        }
    }
    #expect(await service.openSessionIDs.count == policy.budgets.statefulToolingMaximumSessions)
}

@Test func requestRegistryCancelsCooperativeGeneralizedWork() async throws {
    let registry = GrammarToolingRequestRegistry()
    let grammar = "%start E\nE : E E | 'a' ;"
    let longRequest = GrammarToolingRequest(
        requestID: "long-generalized", operation: .generalizedParse,
        compilation: .init(source: grammar),
        input: Array(repeating: "a", count: 22).joined(separator: " "),
        generalizedOptions: .init(
            maximumConfigurations: 1_000_000, maximumSteps: 5_000_000,
            maximumTrees: 10_000, maximumForestNodes: 1_000_000,
            maximumPackedFamilies: 1_000_000
        )
    )
    let running = Task { await registry.handle(longRequest) }
    for _ in 0..<100 {
        if await registry.activeRequestIDs.contains("long-generalized") { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    let cancellation = await registry.handle(.init(
        requestID: "cancel-long", operation: .cancel,
        targetRequestID: "long-generalized"
    ))
    #expect(cancellation.events?.first?.kind == .requestCancelled)
    #expect((await running.value).error?.code == "cancelled")
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

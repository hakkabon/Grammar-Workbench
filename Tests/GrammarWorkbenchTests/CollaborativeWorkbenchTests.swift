import GrammarWorkbench
import Testing

private let owner = GrammarCollaborationParticipant(id: "owner", displayName: "Owner")
private let peer = GrammarCollaborationParticipant(id: "peer", displayName: "Peer")

@Test func collaborativeWorkspaceOrdersPresenceAndDocumentEvents() async throws {
    let host = GrammarCollaborativeWorkbenchHost()
    let created = try await host.createWorkspace(
        id: "shared", owner: owner,
        documents: [.init(id: "grammar", text: "%start S\nS : 'a' ;")],
        operationID: "create"
    )
    #expect(created.workspace.participants == [owner])
    #expect(created.events.map(\.sequence) == [0])

    let joined = try await host.join(
        workspaceID: "shared", participant: peer, operationID: "join"
    )
    #expect(joined.workspace.participants.map(\.id) == ["owner", "peer"])

    let changed = try await host.apply(
        workspaceID: "shared", participantID: peer.id, documentID: "grammar",
        expectedRevision: 0,
        edits: [.init(range: nil, replacement: "%start S\nS : 'b' ;")],
        operationID: "change"
    )
    #expect(changed.workspace.documents.first?.text.revision == 1)
    #expect(changed.events.first?.sequence == 2)
    #expect(changed.events.first?.change?.editCount == 1)
    #expect(try await host.events(workspaceID: "shared", after: 0).map(\.sequence) == [1, 2])
}

@Test func collaborationRejectsStaleEditsAndReplaysOperationIDs() async throws {
    let host = GrammarCollaborativeWorkbenchHost()
    _ = try await host.createWorkspace(
        id: "shared", owner: owner,
        documents: [.init(id: "grammar", text: "first")], operationID: "create"
    )
    let first = try await host.apply(
        workspaceID: "shared", participantID: owner.id, documentID: "grammar",
        expectedRevision: 0, edits: [.init(range: nil, replacement: "second")],
        operationID: "edit-1"
    )
    let replay = try await host.apply(
        workspaceID: "shared", participantID: owner.id, documentID: "grammar",
        expectedRevision: 0, edits: [.init(range: nil, replacement: "ignored")],
        operationID: "edit-1"
    )
    #expect(replay.replayedOperation)
    #expect(replay.workspace == first.workspace)
    await #expect(throws: GrammarCollaborationError.self) {
        try await host.apply(
            workspaceID: "shared", participantID: owner.id, documentID: "grammar",
            expectedRevision: 0, edits: [.init(range: nil, replacement: "third")],
            operationID: "edit-2"
        )
    }
}

@Test func collaborationBoundsResourcesAndDetectsHistoryGaps() async throws {
    let host = GrammarCollaborativeWorkbenchHost(limits: .init(
        maximumWorkspaces: 1, maximumParticipantsPerWorkspace: 2,
        maximumDocumentsPerWorkspace: 1, maximumDocumentUTF16Length: 32,
        maximumRetainedEvents: 2, maximumEditsPerOperation: 1
    ))
    _ = try await host.createWorkspace(
        id: "shared", owner: owner,
        documents: [.init(id: "grammar", text: "a")], operationID: "create"
    )
    _ = try await host.join(workspaceID: "shared", participant: peer, operationID: "join")
    _ = try await host.apply(
        workspaceID: "shared", participantID: peer.id, documentID: "grammar",
        expectedRevision: 0, edits: [.init(range: nil, replacement: "b")],
        operationID: "edit"
    )
    await #expect(throws: GrammarCollaborationError.self) {
        try await host.events(workspaceID: "shared", after: -1)
    }
    await #expect(throws: GrammarCollaborationError.self) {
        try await host.createWorkspace(id: "second", owner: owner, documents: [], operationID: "second")
    }
}

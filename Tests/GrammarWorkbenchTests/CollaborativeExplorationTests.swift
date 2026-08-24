import GrammarWorkbench
import Testing

@Suite("Collaborative exploration")
struct CollaborativeExplorationTests {
    private let source = """
    %start Root
    Root : Item Tail ;
    Item : 'id' ;
    Tail : ',' Item Tail | ;
    """
    private let owner = GrammarCollaborationParticipant(id: "owner", displayName: "Owner")
    private let peer = GrammarCollaborationParticipant(id: "peer", displayName: "Peer")

    private func fixture() async throws -> (GrammarCollaborativeWorkbenchHost, GrammarCollaborativeExplorer) {
        let host = GrammarCollaborativeWorkbenchHost()
        _ = try await host.createWorkspace(
            id: "shared", owner: owner,
            documents: [.init(id: "grammar", text: source)], operationID: "create"
        )
        _ = try await host.join(workspaceID: "shared", participant: peer, operationID: "join")
        return (host, GrammarCollaborativeExplorer(collaboration: host))
    }

    @Test("Participants share focus and revision-bound bookmarks")
    func sharedIntent() async throws {
        let (_, explorer) = try await fixture()
        _ = try await explorer.select(
            workspaceID: "shared", documentID: "grammar", participantID: owner.id,
            expectedDocumentRevision: 0, rule: "Item", operationID: "focus-owner"
        )
        let result = try await explorer.upsertBookmark(
            workspaceID: "shared", documentID: "grammar", participantID: peer.id,
            expectedDocumentRevision: 0, bookmarkID: "review-tail", rule: "Tail",
            note: "Check termination", operationID: "bookmark-tail"
        )

        #expect(result.snapshot.exploration.selectedRule == "Tail")
        #expect(result.snapshot.presences.map(\.selectedRule) == ["Item"])
        #expect(result.snapshot.bookmarks.first?.bookmark.note == "Check termination")
        #expect(result.snapshot.bookmarks.first?.ruleExists == true)
        #expect(result.events.first?.sequence == 1)

        let peerView = try await explorer.snapshot(
            workspaceID: "shared", documentID: "grammar", participantID: peer.id
        )
        #expect(peerView.exploration.selectedRule == "Root")
    }

    @Test("Operations replay and stale document revisions are rejected")
    func concurrencyAndReplay() async throws {
        let (host, explorer) = try await fixture()
        let first = try await explorer.select(
            workspaceID: "shared", documentID: "grammar", participantID: peer.id,
            expectedDocumentRevision: 0, rule: "Tail", operationID: "focus"
        )
        let replay = try await explorer.select(
            workspaceID: "shared", documentID: "grammar", participantID: peer.id,
            expectedDocumentRevision: 99, rule: "Root", operationID: "focus"
        )
        #expect(replay.replayedOperation)
        #expect(replay.snapshot == first.snapshot)

        _ = try await host.apply(
            workspaceID: "shared", participantID: owner.id, documentID: "grammar",
            expectedRevision: 0, edits: [.init(range: nil, replacement: source + "\nExtra : 'x' ;")],
            operationID: "edit"
        )
        await #expect(throws: GrammarCollaborativeExplorationError.self) {
            try await explorer.select(
                workspaceID: "shared", documentID: "grammar", participantID: peer.id,
                expectedDocumentRevision: 0, rule: "Extra", operationID: "stale-focus"
            )
        }
    }

    @Test("Document changes expose stale or removed bookmark context")
    func staleProjection() async throws {
        let (host, explorer) = try await fixture()
        _ = try await explorer.upsertBookmark(
            workspaceID: "shared", documentID: "grammar", participantID: owner.id,
            expectedDocumentRevision: 0, bookmarkID: "tail", rule: "Tail", note: "Review",
            operationID: "bookmark"
        )
        _ = try await host.apply(
            workspaceID: "shared", participantID: owner.id, documentID: "grammar",
            expectedRevision: 0,
            edits: [.init(range: nil, replacement: "%start Root\nRoot : 'done' ;")],
            operationID: "simplify"
        )
        let view = try await explorer.snapshot(
            workspaceID: "shared", documentID: "grammar", participantID: owner.id
        )
        #expect(view.documentRevision == 1)
        #expect(view.exploration.selectedRule == "Root")
        #expect(view.bookmarks.first?.ruleExists == false)
        #expect(view.bookmarks.first?.isCurrentDocumentRevision == false)
    }

    @Test("Membership, rule validity, bounds, removal, and event gaps are enforced")
    func validationAndBounds() async throws {
        let host = GrammarCollaborativeWorkbenchHost()
        _ = try await host.createWorkspace(
            id: "shared", owner: owner,
            documents: [.init(id: "grammar", text: source)], operationID: "create"
        )
        let explorer = GrammarCollaborativeExplorer(
            collaboration: host,
            limits: .init(maximumBookmarksPerDocument: 1, maximumNoteUTF16Length: 4, maximumRetainedEvents: 1)
        )
        await #expect(throws: GrammarCollaborationError.self) {
            try await explorer.snapshot(workspaceID: "shared", documentID: "grammar", participantID: "missing")
        }
        await #expect(throws: GrammarCollaborativeExplorationError.self) {
            try await explorer.select(
                workspaceID: "shared", documentID: "grammar", participantID: owner.id,
                expectedDocumentRevision: 0, rule: "Missing", operationID: "missing-rule"
            )
        }
        _ = try await explorer.upsertBookmark(
            workspaceID: "shared", documentID: "grammar", participantID: owner.id,
            expectedDocumentRevision: 0, bookmarkID: "one", rule: "Item", note: "ok",
            operationID: "one"
        )
        _ = try await explorer.removeBookmark(
            workspaceID: "shared", documentID: "grammar", participantID: owner.id,
            expectedDocumentRevision: 0, bookmarkID: "one", operationID: "remove"
        )
        await #expect(throws: GrammarCollaborativeExplorationError.self) {
            try await explorer.events(workspaceID: "shared", documentID: "grammar", after: -1)
        }
    }
}

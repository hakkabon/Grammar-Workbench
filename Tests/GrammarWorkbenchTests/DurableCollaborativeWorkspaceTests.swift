import Foundation
import GrammarWorkbench
import Testing

private actor FailingCollaborationStore: GrammarCollaborationArchiveStore {
    private var data: Data?
    private var failsNextSave = false
    func load() -> Data? { data }
    func save(_ data: Data) throws {
        if failsNextSave {
            failsNextSave = false
            throw CocoaError(.fileWriteUnknown)
        }
        self.data = data
    }
    func failNextSave() { failsNextSave = true }
}

@Suite("Durable collaborative workspaces")
struct DurableCollaborativeWorkspaceTests {
    private let owner = GrammarCollaborationParticipant(id: "owner", displayName: "Owner")
    private let peer = GrammarCollaborationParticipant(id: "peer", displayName: "Peer")

    @Test("Archive recovery preserves documents, events, participants, and retries")
    func memoryRecovery() async throws {
        let store = GrammarCollaborationMemoryStore()
        let first = try await GrammarDurableCollaborativeWorkbenchHost.open(store: store)
        _ = try await first.createWorkspace(
            id: "shared", owner: owner,
            documents: [.init(id: "grammar", text: "first")], operationID: "create"
        )
        _ = try await first.join(workspaceID: "shared", participant: peer, operationID: "join")
        let changed = try await first.apply(
            workspaceID: "shared", participantID: peer.id, documentID: "grammar",
            expectedRevision: 0, edits: [.init(range: nil, replacement: "second")],
            operationID: "edit"
        )

        let recovered = try await GrammarDurableCollaborativeWorkbenchHost.open(store: store)
        #expect(try await recovered.status("shared") == changed.workspace)
        #expect(try await recovered.events(workspaceID: "shared", after: -1).map(\.sequence) == [0, 1, 2])
        let replay = try await recovered.apply(
            workspaceID: "shared", participantID: peer.id, documentID: "grammar",
            expectedRevision: 0, edits: [.init(range: nil, replacement: "ignored")],
            operationID: "edit"
        )
        #expect(replay.replayedOperation)
        #expect(replay.workspace == changed.workspace)
    }

    @Test("Failed durable save rolls live state back atomically")
    func saveRollback() async throws {
        let store = FailingCollaborationStore()
        let host = try await GrammarDurableCollaborativeWorkbenchHost.open(store: store)
        _ = try await host.createWorkspace(
            id: "shared", owner: owner,
            documents: [.init(id: "grammar", text: "first")], operationID: "create"
        )
        await store.failNextSave()
        await #expect(throws: GrammarCollaborationDurabilityError.self) {
            try await host.apply(
                workspaceID: "shared", participantID: owner.id, documentID: "grammar",
                expectedRevision: 0, edits: [.init(range: nil, replacement: "lost")],
                operationID: "failed-edit"
            )
        }
        let status = try await host.status("shared")
        #expect(status.documents.first?.text.text == "first")
        #expect(status.documents.first?.text.revision == 0)
        #expect(status.nextEventSequence == 1)

        let reopened = try await GrammarDurableCollaborativeWorkbenchHost.open(store: store)
        #expect(try await reopened.status("shared") == status)
    }

    @Test("Atomic file store survives host replacement")
    func fileRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("grammar-workbench-durable-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GrammarCollaborationFileStore(fileURL: directory.appendingPathComponent("workspaces.json"))
        let first = try await GrammarDurableCollaborativeWorkbenchHost.open(store: store)
        _ = try await first.createWorkspace(
            id: "file", owner: owner,
            documents: [.init(id: "grammar", text: "durable")], operationID: "create"
        )
        let second = try await GrammarDurableCollaborativeWorkbenchHost.open(store: store)
        #expect(try await second.status("file").documents.first?.text.text == "durable")
    }

    @Test("Corrupt and future archives fail closed")
    func invalidArchives() async throws {
        await #expect(throws: GrammarCollaborationDurabilityError.self) {
            try await GrammarDurableCollaborativeWorkbenchHost.open(
                store: GrammarCollaborationMemoryStore(data: Data("not-json".utf8))
            )
        }
        let future = GrammarCollaborationArchive(schemaVersion: 99, workspaces: [])
        let encoded = try JSONEncoder().encode(future)
        await #expect(throws: GrammarCollaborationDurabilityError.self) {
            try await GrammarDurableCollaborativeWorkbenchHost.open(
                store: GrammarCollaborationMemoryStore(data: encoded)
            )
        }
    }
}

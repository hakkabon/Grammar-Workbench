# Collaborative or hosted workbench

Phase 34 introduces a transport-neutral shared-workspace protocol. It is the
foundation for team sessions and hosted deployments, while keeping storage,
identity providers, and network topology outside the parser core.

## Consistency model

`GrammarCollaborativeWorkbenchHost` is an actor that owns multiple workspaces.
Each workspace has a total event order, a monotonically increasing workspace
revision, independently revised documents, and an ordered participant set.
Changes carry an expected document revision and are applied atomically with the
existing UTF-16 text-edit contract. A stale edit is rejected with both expected
and actual revisions; the host never silently rebases or overwrites it.

Every mutation also carries a caller-supplied `operationID`. Retrying a retained
operation returns its original result without applying it twice. Replay records
and events share a bounded retention window; clients that fall behind receive
`event-history-unavailable` and must fetch a fresh workspace snapshot.

The model intentionally provides optimistic concurrency rather than a CRDT.
That keeps grammar edits deterministic and makes conflicts visible. A future
CRDT or operational-transformation adapter can translate its operations into
revision-checked edits without changing workspace snapshots or event polling.

## Persistent tooling protocol

The existing `grammar-workbench-service` JSON-lines process hosts collaboration
alongside stateful language sessions. `GrammarToolingOperation` adds
`collaborationCreate`, `collaborationJoin`, `collaborationLeave`,
`collaborationStatus`, `collaborationChange`, and `collaborationEvents`.

Requests use `workspaceID`, `participant`, `operationID`, document and edit
fields, and either `expectedRevision` or `afterEventSequence` where applicable.
Responses carry a collaboration result, snapshot, or ordered events. The
stateless SDK does not advertise these operations.

The service remains newline-delimited JSON over standard input/output. Hosted
products may put authentication and HTTP, WebSocket, SSH, or message-queue
transport in front of the same actor and Codable envelopes. Phase 34 does not
open a listening socket, accept untrusted identities, or imply multi-tenant
isolation.

## Resource and trust boundaries

`GrammarCollaborationLimits` bounds workspaces, participants, documents,
document length, retained events, and edits per operation. Identifiers and
display names are non-empty and bounded. The release gate fills the configured
workspace/document/participant capacity and verifies stable public capability
metadata.

Authentication, authorization roles, durable databases, encryption, audit-log
export, attachment storage, invitations, discovery, and deployment manifests
are deliberately future host concerns. Later hosted phases can add these behind
the protocol while retaining the revision, event, and retry semantics here.

Phase 37 adds versioned archive persistence and an atomic single-file service
adapter while retaining these semantics. See
[DurableCollaborativeWorkspaces.md](DurableCollaborativeWorkspaces.md).

# Durable collaborative workspaces

Phase 37 adds validated persistence and crash recovery to the transport-neutral
collaboration model from Phase 34. It preserves the existing optimistic
concurrency and event semantics; durability is an adapter around that host, not
a new editing algorithm.

## Versioned archive

`GrammarCollaborationArchive` is a Codable, schema-versioned representation of
all hosted workspaces. Each workspace archive retains:

- workspace and document revisions;
- document text;
- ordered participants;
- the bounded event window and next sequence;
- bounded operation replay results.

Restoration validates the schema, configured resource limits, identities,
duplicate documents and participants, document lengths, event ordering and
continuity, next sequence, workspace ownership of events, and retry-record
consistency. Unsupported, malformed, corrupt, or oversized archives fail closed
instead of partially restoring data.

`GrammarCollaborativeWorkbenchHost.archive()` exports the current state, and its
restoring initializer reconstructs the same event and idempotency boundary.
Retried retained operations therefore remain idempotent after process restart.

## Transactional durable host

`GrammarDurableCollaborativeWorkbenchHost` conforms to the same
`GrammarCollaborationHosting` actor protocol as the in-memory host. Each mutation:

1. captures the exact pre-operation archive;
2. applies the Phase 34 operation;
3. encodes a deterministic sorted-key archive;
4. saves it through the configured store;
5. restores the pre-operation host if saving fails.

A caller never observes an acknowledged edit that was not saved. Save failures
have stable `collaboration-save-failed` errors, and the operation can be retried.
Read-only status and event polling do not rewrite storage.

## Stores and service configuration

`GrammarCollaborationArchiveStore` is a small asynchronous byte-store protocol.
The package provides:

- `GrammarCollaborationFileStore`, which creates its parent directory and uses
  atomic replacement writes;
- `GrammarCollaborationMemoryStore`, for embedding, testing, or caller-managed
  persistence.

The JSON-lines `grammar-workbench-service` keeps its in-memory default. Setting
`GRAMMAR_WORKBENCH_COLLABORATION_STORE` to a file path enables the durable file
host. Startup loads and validates the entire archive before accepting requests;
an invalid store prevents the service loop from starting.

```sh
GRAMMAR_WORKBENCH_COLLABORATION_STORE=/var/lib/grammar-workbench/workspaces.json \
  grammar-workbench-service
```

## Trust and operational limits

Atomic file replacement protects against partial writes, not disk loss. Operators
remain responsible for filesystem permissions, backups, encryption at rest,
capacity monitoring, and single-writer process ownership. The file adapter is
not a distributed database and must not be shared concurrently by several host
processes.

Phase 37 persists participant membership as workspace state. Authentication,
authorization roles, audit signatures, multi-tenant isolation, database-backed
compare-and-swap, migrations beyond schema rejection, and distributed leader
election remain future hosted-product concerns.

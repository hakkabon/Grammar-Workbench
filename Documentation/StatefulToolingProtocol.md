# Stateful tooling protocol and service host

Phase 14 extends the version-one language-tooling envelope without changing the
existing stateless operations. Long-lived clients can retain compiled grammar
and incremental document state across requests.

## Session lifecycle

The service adds `sessionOpen`, `sessionStatus`, `sessionReplaceGrammar`,
`sessionClose`, `documentOpen`, `documentChange`, `documentClose`, and `cancel`.
Opening a document supplies complete text; changes carry ordered UTF-16
`GrammarTextEdit` values and an optional external revision. Responses include an
immutable session summary, the latest incremental snapshot when applicable, and
ordered lifecycle events.

Operations are serialized per session. Different sessions can progress
concurrently. Grammar replacement retains the session identity, increments its
grammar revision, and reanalyzes every open document through the shared
incremental coordinator.

`GrammarStatefulToolingLimits` bounds sessions, documents per session, and UTF-16
document length. Limit violations return `resource-limit` before mutating state;
hosts can select tighter values for constrained deployments.

## Embedding

Swift hosts use `GrammarStatefulLanguageToolingService` directly or a
`GrammarToolingClient` with `GrammarStatefulInProcessToolingTransport`.
`GrammarToolingRequestRegistry` tracks in-flight work and handles cooperative
cancellation by request identifier.

```swift
let client = GrammarToolingClient(
    transport: GrammarStatefulInProcessToolingTransport()
)
let opened = try await client.send(.init(
    operation: .sessionOpen,
    compilation: .init(source: grammar),
    sessionID: "editor"
))
let analyzed = try await client.send(.init(
    operation: .documentOpen,
    input: sourceText,
    sessionID: opened.session!.id,
    documentID: "main",
    revision: 1
))
```

## Persistent process host

`grammar-workbench-service` reads one compact JSON request per line and writes one
JSON response per line. Requests may complete out of order, so clients correlate
them through `requestID`. Malformed lines return an `invalid-json` failure.

```text
{"apiVersion":1,"operation":"capabilities","requestID":"cap-1","schemaVersion":1}
```

The JSON-lines transport complements rather than replaces LSP. It exposes the
complete typed compilation and incremental-analysis contracts to build daemons,
IDE extensions, test runners, and remote transport adapters.

## Errors and compatibility

Lifecycle errors use stable codes including `unknown-session`,
`duplicate-session`, `unknown-document`, `duplicate-document`,
`compilation-failed`, `duplicate-request`, and `cancelled`. Adding optional fields
or operations remains compatible within schema one; an incompatible envelope
change requires a new tooling schema version.

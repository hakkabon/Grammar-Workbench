# Language-tooling SDK and portability

`GrammarWorkbenchSDK` is the integration boundary for editors, build services,
test runners, and non-Swift hosts. It keeps engine implementation types behind a
small request/response protocol while preserving stable public snapshots.

Capability responses advertise `crossPlatformCoreSeparation`. Hosts that only need in-process grammar services can depend on `GrammarWorkbenchCore`; transport hosts may continue to use the SDK and receive the same portable value contracts.

## Swift integration

```swift
import GrammarWorkbenchSDK

let client = GrammarToolingClient(transport: GrammarInProcessToolingTransport())
let capabilities = try await client.send(.init(operation: .capabilities))
let parsed = try await client.send(.init(
    operation: .parse,
    compilation: .init(source: grammarSource),
    input: "alpha + beta"
))
```

The transport protocol exchanges `Data`, so adapters can use a subprocess,
socket, XPC service, WebSocket, or another host-specific channel without changing
the typed client. The included in-process transport is suitable for applications
and tests.

## JSON integration

Every envelope carries a tooling `schemaVersion`, Grammar Workbench `apiVersion`,
and caller-selected `requestID`. Begin with `capabilities`; its response lists
supported operations, schemas, transports, and feature maturity.

The CLI is the reference process bridge:

```text
grammar-workbench tooling-request request.json response.json
```

A minimal request is:

```json
{
  "apiVersion": 1,
  "operation": "capabilities",
  "requestID": "client-1",
  "schemaVersion": 1
}
```

Operations cover compilation, deterministic and generalized parsing, project
analysis, and semantic workspace construction. Invalid versions and missing
payloads produce failure envelopes with stable error codes.

## Compatibility policy

- Existing fields and operation meanings remain compatible throughout 1.x.
- New optional fields, operations, and capabilities may be added in minor releases.
- An incompatible wire change requires a new tooling schema version.
- Engine failures are operation results; malformed JSON and transport failures are thrown by the codec or transport.
- Project responses expose immutable, Codable summaries rather than actor or incremental-session state.

The `SDKConsumer` fixture compiles strictly through this product, and release
validation requires both the product and fixture.

For retained incremental documents, concurrent requests, lifecycle events, and
the persistent JSON-lines host, see
[StatefulToolingProtocol.md](StatefulToolingProtocol.md).

`languageKitValidate` compiles and conformance-tests a portable semantic language kit. `languageKitAnalyze` applies that kit to the sources carried by a project envelope and returns the project summary, semantic workspace, and validated kit identity together. Stateful clients may use the same `languageKit` payload in `sessionOpen` instead of supplying a standalone compilation request.

`graphLayout` accepts a portable `GrammarGraph` and optional `GrammarGraphLayoutOptions`, returning the complete positioned snapshot. The operation is available through in-process, JSON, and JSON-lines transports and does not expose Swift-Layout or UniFFI implementation types.

# Browser and portable runtime

Phase 30 selects the **portable LR artifact worker** as Grammar Workbench's
supported browser execution profile. The standalone Swift WASI command module
remains supported for WASI runtimes, but a browser WASI adapter is not a product
surface. `grammar-workbench browser-runtime` publishes this decision for tools.

## Artifact contract

The `portable-browser` generator emits
`grammar-workbench-portable-lr` schema 2. Every artifact declares its minimum
runtime version and bounded input-length, token-count, parser-step, and stack
depth limits. These artifact limits cannot exceed the runtime ceilings, and
per-request options may lower but never raise them. The runtime rejects unknown kinds, future schemas or runtime
versions, malformed productions and actions, unsafe unanchored token patterns,
and empty-matching token patterns before parsing.

The initial generator supports deterministic, conflict-free LR tables and
DEFAULT-mode lexer rules without mode transitions. Unsupported grammars fail
generation explicitly. This is narrower than the native parser contract and is
intentional: portable artifacts never silently discard conflicts or lexer
behavior.

Generate an artifact with:

```sh
swift run grammar-workbench generate portable-browser Grammar.grammar Grammar.portable-lr.json
```

## Worker runtime

`parser-core.mjs` contains the DOM-independent validator, tokenizer, and parser.
`runtime-worker.mjs` provides its request boundary. `runtime-client.mjs` creates
a dedicated module worker for each parse, validates the artifact inside that
worker, and terminates the worker when its `AbortSignal` fires. Per-operation
workers make cancellation reliable even during CPU-bound regular-expression or
parser work and prevent stale parse results from reaching the UI.

Failures use stable codes such as `unsupported-schema`, `unsupported-runtime`,
`lexical-error`, `syntax-error`, `token-limit`, `step-limit`, and `stack-limit`.
Syntax rejection is returned as a located diagnostic; invalid artifacts and
resource failures reject the operation.

## Compatibility and security boundary

Runtime 1 accepts artifact schema 2. A future artifact requiring newer behavior
must increase `minimumRuntimeVersion`; an incompatible envelope requires a new
schema. Worker isolation and bounded execution reduce UI impact, but portable
grammars remain code-like input and should be reviewed before publication.

The browser runtime does not compile grammars, run stateful tooling sessions,
load native graph layout, or claim parity with the complete Swift SDK. Those
operations remain available in native, service, LSP, and standalone WASI hosts.

# WASM feasibility and portable demonstration

Phase 28 established two deliberately separate WebAssembly paths. Phase 29
retains that boundary while pinning its release environment:

1. **WASI command module** — `grammar-workbench-wasi` hosts the existing stateless `GrammarWorkbenchSDK` JSON contract. It accepts one `GrammarToolingRequest` per input line and writes one correlated response per line.
2. **Browser interchange demonstration** — `Examples/WASM` executes a precomputed LR table in ordinary JavaScript and presents the trace and syntax tree. It proves that generated parser data can travel to a browser without requiring the Workbench implementation or a server.

This distinction matters. WASI provides the system interfaces expected by the Swift runtime, but browsers do not implement WASI directly. A browser wishing to run the Swift module needs an explicit WASI adapter. The included browser demonstration therefore does not misrepresent portable artifact execution as in-browser Swift grammar compilation.

Phase 30 resolves the browser product decision in favor of the portable LR
artifact worker. A browser WASI adapter is explicitly unsupported; the WASI
module remains a standalone-runtime and CI portability target. See
`Documentation/BrowserAndPortableRuntime.md`.

## Feasibility contract

`GrammarWASMFeasibilityReport.current` and `grammar-workbench wasm-feasibility`
publish the current status in machine-readable form. WASM remains
**experimental**, but `Packaging/PortabilityToolchain.json` now pins Swift
6.3, Node 22, the `swift-wasm-6.3-RELEASE-wasm32-unknown-wasip1` SDK, the WASI target, and the
Wasmtime runtime family.

The viable surface is:

- Stateless compilation and parsing through the SDK request/response schema
- Deterministic parser artifacts and traces
- Portable grammar and graph interchange
- Precomputed SVG/HTML visualization data
- WASI stdin/stdout hosting

Current exclusions are:

- Native SwiftUI/AppKit/WebKit interfaces
- The Swift-Layout binary backend
- Stateful OS/editor integration inside a browser
- Direct browser execution without a WASI adapter

## Build the WASI module

The build script prepares the pinned Grammar dependency for non-Apple platforms
before invoking SwiftPM. This applies the same revision-checked `OSLog`
compatibility patch used by Linux delivery; it can be retired after Grammar
publishes portable logging support.

Install the SDK declared by `Packaging/PortabilityToolchain.json`:

```sh
swift sdk install https://github.com/swiftwasm/swift/releases/download/swift-wasm-6.3-RELEASE/swift-wasm-6.3-RELEASE-wasm32-unknown-wasip1.artifactbundle.zip --checksum 6704d137e532f1ac31eafedd80658f9ee61239f2b6291216a02da32361ea9dcb
Scripts/build-wasm-demo.sh --require-sdk
```

The output directory defaults to `dist-wasm` and contains:

- `grammar-workbench-wasi.wasm`
- `browser/index.html` and its zero-dependency demonstration assets

Without the pinned SDK, the script still produces the browser demonstration
and toolchain manifest and clearly reports that the Swift module was not built.
It never substitutes a native executable with a `.wasm` filename.

Run the module using a WASI runtime by piping a tooling request to standard input. For example:

```json
{"schemaVersion":1,"requestID":"demo","apiVersion":1,"operation":"capabilities"}
```

## Run the browser demonstration

Because browser modules use `fetch`, serve the directory rather than opening the HTML file directly:

```sh
cd Examples/WASM
python3 -m http.server 8080
```

Then open `http://localhost:8080`. The sample recognizes identifiers separated by `+`, shows every shift/reduce action, constructs a syntax tree, and reports lexical or parser rejection without contacting a server.

The portable parser core has no DOM dependency and is regression-tested under Node:

```sh
node Scripts/test-wasm-demo.mjs
```

## Validation

`Scripts/validate-wasm-feasibility.sh` and the release-contract CI job perform
five levels of validation:

1. Builds the WASI host as a native executable, checking the complete SDK contract and target boundaries.
2. Sends capability and compile/parse requests through its newline-delimited transport.
3. Runs accepted, rejected, and lexical-error browser parser cases under Node.
4. Builds the actual `.wasm` module using the pinned SDK.
5. Executes the same golden requests with Wasmtime and requires native/WASI
   JSON equivalence.

CI always runs the first three. Its dedicated `wasm-release-contract` job
installs the pinned SDK and runtime and requires all five. See
`Documentation/ReproduciblePortabilityAndRelease.md` for the release policy.

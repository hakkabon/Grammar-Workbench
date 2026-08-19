# WASM feasibility and portable demonstration

Phase 28 establishes two deliberately separate WebAssembly paths:

1. **WASI command module** — `grammar-workbench-wasi` hosts the existing stateless `GrammarWorkbenchSDK` JSON contract. It accepts one `GrammarToolingRequest` per input line and writes one correlated response per line.
2. **Browser interchange demonstration** — `Examples/WASM` executes a precomputed LR table in ordinary JavaScript and presents the trace and syntax tree. It proves that generated parser data can travel to a browser without requiring the Workbench implementation or a server.

This distinction matters. WASI provides the system interfaces expected by the Swift runtime, but browsers do not implement WASI directly. A browser wishing to run the Swift module needs an explicit WASI adapter. The included browser demonstration therefore does not misrepresent portable artifact execution as in-browser Swift grammar compilation.

## Feasibility contract

`GrammarWASMFeasibilityReport.current` and `grammar-workbench wasm-feasibility` publish the current status in machine-readable form. Phase 28 remains **experimental** because reproducible WASM delivery still depends on an external Swift WASM SDK and runtime. The report records these constraints rather than silently degrading capabilities.

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

Install a Swift WASM SDK compatible with the repository's Swift toolchain, then either let the script discover it or provide its identifier explicitly:

```sh
export WASM_SDK_ID=YOUR_INSTALLED_WASM_SDK_ID
Scripts/build-wasm-demo.sh --require-sdk
```

The output directory defaults to `dist-wasm` and contains:

- `grammar-workbench-wasi.wasm`
- `browser/index.html` and its zero-dependency demonstration assets

Without a WASM SDK, the script still produces the browser demonstration and clearly reports that the Swift module was not built. It never substitutes a native executable with a `.wasm` filename.

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

`Scripts/validate-wasm-feasibility.sh` performs four levels of validation:

1. Builds the WASI host as a native executable, checking the complete SDK contract and target boundaries.
2. Sends a real capabilities request through its newline-delimited transport.
3. Runs accepted, rejected, and lexical-error browser parser cases under Node.
4. Builds the actual `.wasm` module when a compatible SDK is installed.

CI always runs the first three. The fourth is capability-sensitive until a WASM SDK version becomes part of the pinned release toolchain.


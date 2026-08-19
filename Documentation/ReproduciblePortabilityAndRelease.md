# Reproducible portability and release consolidation

Phase 29 turns the Phase 28 feasibility work into a reviewable release
contract. It does not change the product boundary: the native macOS app, Linux
headless tools, WASI stateless service, and browser table runtime remain
different hosts over shared versioned data.

## Pinned environment

`Packaging/PortabilityToolchain.json` is the machine-readable source of truth
for portability builds. It records the validated Swift and Node versions, the
exact Swift WASM SDK identifier and bundle, the WASI target, the runtime family,
and the browser execution model. Release changes to these values require code
review in the same way as release-budget changes.

`Scripts/validate-portability-toolchain.sh` fails when host versions differ
from the manifest. Pass `--require-wasm` to also require the pinned SDK. The
WASM builder selects that exact SDK instead of accepting the first installed
SDK whose name happens to contain `wasm`.

## Behavioral equivalence

The files under `Validation/WASM` are transport-neutral golden requests. The
equivalence gate sends capability negotiation and a representative compile and
parse operation through the native host and the real WASI module. Both must
succeed and decode to equivalent JSON values after construction timing fields,
which necessarily vary by runtime, are removed. Artifact identities, counts,
diagnostics, parse trees, traces, and capabilities remain exact. This checks
the SDK wire contract in addition to proving that a `.wasm` file was emitted.

The comparison is deliberately stateless. Browser execution continues to use
precomputed LR artifacts and is tested separately under Node. A future phase
may introduce a browser WASI adapter, but Phase 29 does not imply one.

## CI and artifacts

CI has two portability levels:

1. The feasibility job validates native host behavior and the dependency-free
   browser runtime on an ordinary Linux runner.
2. The release-contract job installs the pinned Swift SDK and Wasmtime, builds
   and executes the real module, compares it with the native host, and uploads
   both the module and `PortabilityToolchain.json`.

The normal release-candidate gate verifies that the portability manifest is
present and structurally valid. Platform packages continue to use their
existing smoke tests, consumer fixtures, checksums, and optional credentialed
macOS signing and notarization.

## Support policy

The deterministic SDK contract and the Phase 29 validation infrastructure are
stable 1.x surfaces. WASI delivery remains experimental until multiple pinned
toolchain upgrades have demonstrated compatibility. The browser profile is a
portable artifact runtime, not in-browser Swift compilation.

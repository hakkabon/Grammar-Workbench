# Ecosystem capability ledger

Phase 24 makes `Packaging/EcosystemCapabilities.json` the machine-readable
answer to three distinct questions: which repository owns a capability, which
repositories consume it, and which parser engines expose which observable
behavior. It complements rather than replaces `EcosystemCompatibility.json`:
the compatibility manifest is a reproducible commit snapshot, while the ledger
records capability ownership and minimum releases.

`Scripts/validate-ecosystem-contract.mjs` rejects duplicate capability owners,
unknown dependencies, repository drift, and any engine declaration that differs
from the shared corpus. A capability therefore cannot silently become a second
implementation or an optimistic UI claim.

## Reference extension

`Validation/Consumers/ReferenceExtension` is a separate Swift package depending
only on the public `GrammarWorkbenchCore` product. Its
`CapabilityReportExtension` registers through the Phase 22 host, reads immutable
grammar and analysis snapshots, and returns bounded portable JSON. The executable
fixture proves discovery, option validation, invocation, and output decoding.

Copy the library target as the starting point for a trusted in-process extension.
Extensions must not import application targets, mutate a compilation, write files
implicitly, or claim parser-engine capabilities absent from the ledger.

## Change protocol

1. Add or change the owning repository's public contract and tests.
2. Advance its minimum release in the ledger and update consumers explicitly.
3. Add engine behavior to the shared corpus when the capability is observable in
   parsing results.
4. Run `Scripts/validate-ecosystem-contract.mjs` and
   `Scripts/validate-downstream.sh` before publishing the Workbench release.

macOS application and Linux delivery archives include the ledger together with
its schema so installed tools can inspect the same reviewed capability surface.

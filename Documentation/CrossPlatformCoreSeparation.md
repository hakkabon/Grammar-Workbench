# Cross-platform core separation

`GrammarWorkbenchCore` is the portable SwiftPM entry point for grammar compilation, deterministic and generalized parsing, incremental analysis, semantic services, project infrastructure, generators, and interchange models. It re-exports the stable `GrammarWorkbench` API so adopting it does not introduce a second set of model types.

```swift
import GrammarWorkbenchCore

let compilation = GrammarWorkbenchAPI.compile(.init(
    source: "%start Greeting\nGreeting : 'hello' ;"
))
let result = compilation.parse("hello")
```

The native document, SwiftUI, AppKit, and WebKit surfaces are compile-time isolated to macOS. The CLI and LSP entry points select Darwin or Glibc explicitly. Linux CI builds and tests the core, CLI, LSP, and stateful service, then validates their distributable archive. See [Linux delivery](LinuxDelivery.md) for installation and release details.

## Graph portability

Graph models, layout options, snapshots, and SVG interchange remain portable. `GrammarGraphLayoutEngine.availability` reports whether the Swift-Layout backend is linked:

- `.swiftLayout` provides the Rust-backed Sugiyama implementation on supported platforms.
- `.interchangeOnly` preserves graph encoding, decoding, adapters, and precomputed layout consumption without pretending that native layout execution exists.

Attempting native layout in interchange-only mode returns `GrammarGraphLayoutError.unavailable`. This keeps the Rust binary boundary explicit and allows additional binary targets to be added later without changing graph schemas.

## Compatibility gate

`Scripts/validate-portable-core.sh` builds the dedicated target and exercises its public façade. `CoreConsumer` independently resolves the SwiftPM product, compiles a grammar, parses input, and round-trips portable graph data. The standard downstream validation includes this consumer.

The first separation milestone deliberately preserves the existing `GrammarWorkbench` imports. Future extraction can move implementation files into physically smaller engine modules behind this façade once those module boundaries provide a measurable build-time or deployment benefit.

# Cross-platform core separation

`GrammarWorkbenchCore` is the portable SwiftPM implementation and entry point for grammar compilation, deterministic and generalized parsing, incremental analysis, semantic services, project infrastructure, generators, and interchange models. The native `GrammarWorkbench` target depends on and re-exports Core, preserving existing imports without creating a second set of model types.

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

The physical split preserves existing `GrammarWorkbench` imports while reversing the old façade dependency. The [separation measurement](WorkbenchCoreMeasurement.md) records complete source ownership, the empty extraction queue, package-scoped native integration hooks, resource ownership, and an optional controlled Core-only build observation.

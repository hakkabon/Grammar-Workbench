# WorkbenchCore physical separation

`GrammarWorkbenchCore` now physically owns the portable implementation.
`GrammarWorkbench` contains the native SwiftUI, AppKit, WebKit, and document
integration and re-exports Core as a compatibility façade. Core has no dependency
on that façade.

The reviewed ownership plan and checked post-split baseline live in
`Validation/CoreSeparation/Plan.json` and
`Validation/CoreSeparation/Baseline.json`.

## Ownership result

The implementation contains 71 Swift sources:

- 58 Core-owned sources and 17,202 lines;
- 13 native/façade sources and 4,765 lines;
- no mixed or unassigned sources; and
- two resources owned by `GrammarWorkbenchCore`.

Core accounts for 78.31% of implementation lines. Package-scoped declarations
are used for implementation models and hooks shared with the native target;
they do not enlarge the public product API.

The split extracted portable editor intelligence, the Codable workbench document
model, release/capability declarations, and resource loading from the three
originally mixed files. CLI, SDK, LSP, and service targets now depend directly on
Core. Only the native app and compatibility consumers require
`GrammarWorkbench`.

## Structural gate

Run the checked ownership and dependency-direction gate:

```sh
node Scripts/measure-workbench-core.mjs --check
```

Generate a detailed report without changing the baseline:

```sh
node Scripts/measure-workbench-core.mjs \
  --report .build/core-separation-report.json
```

The report rejects ownership drift, native-framework imports in Core, native
files without a reviewed native framework, a non-empty mixed queue, loss of the
compatibility re-export, or any dependency from Core back to the native façade.

## Controlled Core build

To add a machine-specific Core-only build observation, use the same scratch
directory, job count, Swift toolchain, and hardware for comparisons:

```sh
node Scripts/measure-workbench-core.mjs --build --jobs 2 \
  --scratch-path .build/core-separation-measurement \
  --report .build/core-separation-build.json
```

Build duration remains outside the checked baseline because it is hardware-,
cache-, and toolchain-sensitive. The generated report records those inputs with
the duration.

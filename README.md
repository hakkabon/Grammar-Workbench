# Grammar Workbench

A native macOS SwiftUI foundation for inspecting generated LR parser artifacts.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%2014-blue.svg)](https://developer.apple.com/swift/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Run

```sh
swift run grammar-workbench-app
```

The automation-friendly executable is available with `swift run grammar-workbench --help`. It validates grammar files, runs persisted project test suites with CI-friendly exit codes, and exports versioned artifact JSON.

## Library API

Xcode host applications should use `GrammarWorkbenchAPI`, the versioned, concurrency-safe library façade. It provides a typed LR algorithm choice and immutable `Sendable` values for compilation diagnostics, grammar analysis, artifact inspection, lexing, parsing/replay, and batch tests. Engine model types remain an implementation detail, while existing lower-level public front-end and lexer APIs remain available for source compatibility.

```swift
import GrammarWorkbench

let compilation = GrammarWorkbenchAPI.compile(.init(
    source: grammarSource,
    algorithm: .lalr
))

guard compilation.succeeded else {
    print(compilation.diagnostics)
    return
}

let parse = compilation.parse("name + value")
print(parse.status, parse.tree ?? "")
let portableJSON = try compilation.encodeArtifactSnapshot()
let parserSource = try compilation.generateSwiftParser(options: .init(typeName: "ExpressionParser"))
```

`GrammarWorkbenchAPI.version` and `GrammarArtifactSnapshot.apiVersion` identify the public contract (currently version 1). Snapshot state and production identifiers are stable within one compiled artifact; clients should not persist them as identities across source edits. Additive fields and APIs may appear within a version, while incompatible Codable schema changes require a new API version.

Generated parsers are standalone Swift files with no Grammar Workbench dependency. They include deterministic ACTION/GOTO tables, lexer rules, typed tokens, parse-tree nodes, and structured lexical or syntax errors. Generation rejects unresolved conflicts by default; callers may explicitly select shift, reduce, or table-order preference through `SwiftParserConflictPolicy`. The app provides **Interchange → Generate Swift Parser…**, and automation can use `grammar-workbench generate-swift GRAMMAR OUTPUT [ALGORITHM] [TYPE]`.

`Examples/Expression.grammar` and `Examples/ExpressionTests.json` provide ready-to-run grammar and project-interchange fixtures for both the app and CLI.

## Production packaging

`Scripts/package-release.sh` builds the SwiftUI application and CLI, assembles a macOS 14 application bundle with document declarations, privacy manifest, and sandbox entitlements, and produces separate ZIP archives. It defaults to the host architecture; set `ARCHS="arm64 x86_64"` for a universal release. The declared source version, bundle metadata, CLI version, and archive name must agree.

For a local Developer ID release, provide `SIGNING_IDENTITY="Developer ID Application: …"`. Add `NOTARY_PROFILE` for an `xcrun notarytool` keychain profile; the script submits, waits, staples, rebuilds the archive, and validates the result. A deterministic default icon is included; `APP_ICON` may point to a replacement `.icns`. Regenerate the default and its inspectable PNG iconset with `swift Scripts/generate-app-icon.swift /tmp/GrammarWorkbench.iconset Packaging/AppIcon.icns`. Signing identities and notarization credentials are intentionally not stored in the repository. Tagged GitHub builds run the full suite and publish unsigned review artifacts; signed distribution can use the same script in a credentialed release environment.

The entitlement template grants only App Sandbox, user-selected read/write files, and app-scoped bookmarks. An external Xcode host should use [Packaging/GrammarWorkbench.entitlements](Packaging/GrammarWorkbench.entitlements) and mirror [Packaging/Info.plist](Packaging/Info.plist).

The app is a native document-based workbench. `.grammarworkbench` documents persist editable grammar source, the selected LR algorithm, and named sample inputs with macOS autosave and undo support. Plain-text grammars can also be opened and exported. Edits regenerate diagnostics and artifacts after a short debounce while retaining the last valid automaton during syntax errors.

The native grammar editor provides syntax highlighting, line numbers, Find, symbol/directive completion, inline diagnostic underlines, source navigation from artifacts and diagnostics, semantic grammar warnings, and targeted quick fixes.

Use `%token NAME ...` to enable explicit-terminal mode and undefined-symbol validation. Grammars without `%token` remain compatible and infer unquoted terminals.

Attach a regular expression to a token with `%token NAME /pattern/` and declare ignored input with `%skip /pattern/`. Samples then accept raw source text; the deterministic lexer uses maximal munch, preserves lexemes and source locations, and feeds token identities into the LR parser. Tokens without patterns continue to match their literal spelling. Grammars without lexer rules retain the whitespace-separated token input mode.

The automaton view uses a deterministic layered layout with routed cyclic edges, state/item/transition search, decision-state filtering, adaptive compact rendering, pan and zoom, Fit controls, and a minimap. Large graphs render a bounded state window while preserving the selected state.

Conflict analysis uses parser-configuration search to find short witnesses and bounded suffix search to produce a common accepting counterexample where possible. Decisions include side-by-side branch trees, replay traces, exact precedence provenance, and `%expect N` matching for intentional unresolved conflicts.

Decision visualization distinguishes unresolved conflicts (red), precedence- or associativity-resolved decisions (blue), and expected conflicts (green) across automaton nodes, the minimap, state filters, parsing-table cells, inspectors, tooltips, and accessibility labels. Table decision cells retain the original candidate actions while displaying the effective parser action.

The Tests workspace persists named accept, reject, and conflict cases with optional exact parse-tree snapshots. Batch runs use the same lexer and LR artifact as interactive samples, report expectation or lexical failures, and can be included in standalone HTML reports. Versioned project JSON round-trips grammar source, algorithm, samples, selection, and tests with validation on import; generated artifact JSON provides an immutable machine-readable snapshot of states, tables, decisions, and replay data. Older `.grammarworkbench` documents decode with an empty test suite.

## Architecture

- `ArtifactModel.swift`: stable, typed identities and immutable artifact snapshots.
- `PublicAPI.swift`: versioned library façade and engine-independent Codable snapshots.
- `SwiftParserCodeGenerator.swift`: standalone Swift lexer/parser source generation.
- `GrammarFrontEnd.swift`: source-located grammar parsing, diagnostics, and set analysis.
- `LRConstructionEngine.swift`: deterministic LR(0)/LR(1) closure, goto, LALR merging, table generation, and precedence resolution.
- `LexerRuntime.swift`: maximal-munch raw-source lexing, skipped rules, lexeme ranges, and lexical diagnostics.
- `ParserRuntime.swift`: legacy token input, LR execution, parse trees, trace frames, conflict witnesses, and branch replay.
- `GrammarWorkbenchDocument.swift`: native document persistence and the public document-hosting view.
- `GrammarEditor.swift`: native AppKit-backed editor, source decoration, completion, line numbering, and quick fixes.
- `SampleArtifact.swift`: replaceable sample artifact provider.
- `ExplorerStore.swift`: cross-view selection and replay state.
- `ArtifactExplorerView.swift`: native master/detail explorer.
- `HTMLExporter.swift`: dependency-free standalone report export.
- `TestingAndInterchange.swift`: persistent test cases, batch execution, and versioned project/artifact JSON interchange.

The UI consumes immutable `GrammarArtifact` values rather than construction internals, keeping artifact identities and inspection views independent from the algorithms that produce them.

## License

MIT License — see [LICENSE](LICENSE) for details.  

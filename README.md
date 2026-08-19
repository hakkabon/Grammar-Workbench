# Grammar Workbench

A native macOS SwiftUI foundation for inspecting generated LR parser artifacts.

The app opens in a guided grammar-engineering workspace: it summarizes grammar health, identifies one recommended next step, and organizes validation, examples, ambiguity, tests, algorithm choice, and generation around ordinary development tasks. Parser automata, tables, replay, and generalized analysis remain available through **Expert tools**. Safe cleanup previews recompile proposed edits and protect recorded samples and tests before Apply is enabled. See [Documentation/GuidedGrammarEngineering.md](Documentation/GuidedGrammarEngineering.md).

The native source editor is a permanent, resizable sibling of the task workspace and inspector rather than an adaptive overlay. Its AppKit host guarantees a visible viewport before and after SwiftUI layout, contains long unwrapped grammar lines with horizontal scrolling, preserves selection across model updates, and exposes stable accessibility identities. See [Documentation/EditorAndVisualFoundations.md](Documentation/EditorAndVisualFoundations.md).

The **Project** workspace unifies grammar, examples or source documents, tests,
semantics, generation, problems, and background work behind one task-oriented
navigator. Dedicated Semantics and Generate views use the same stable project
experience snapshot available to other hosts. See
[Documentation/IntegratedLanguageProjectExperience.md](Documentation/IntegratedLanguageProjectExperience.md).

Filesystem source projects use a versioned `.grammar-workbench-source.json` descriptor to associate safe rooted source globs with an explicit grammar and language identifier. The native Project workspace, CLI, VS Code, Neovim, and LSP initialization share this contract, while export produces the existing self-contained project manifest for CI and SDK hosts. See [Documentation/SourceProjectsAndExternalEditors.md](Documentation/SourceProjectsAndExternalEditors.md).

The grammar analysis and transformation library publishes reachability, productivity, nullability, dependency components, left recursion, duplicate productions, terminal usage, and FIRST/FOLLOW as immutable reports. Explainable cleanup plans are protected by source fingerprints, artifact diffs, saved tests, and bounded generalized language-membership comparison. The same facilities are available through project workspaces and the `grammar-analyze` and `grammar-transform` CLI commands. See [Documentation/GrammarAnalysisAndTransformation.md](Documentation/GrammarAnalysisAndTransformation.md).

The expert **Bootstrap** laboratory performs a bounded self-hosting experiment for a documented BNF profile. It regenerates and recompiles the meta-grammar until the canonical grammar, generated source, and parser artifact reach a fixed point, then differentially compares a corpus with the existing handwritten `Grammar` reader. The trusted reader is not replaced. Run the same release-gated experiment with `grammar-workbench bootstrap [report.json]`; see [Documentation/BootstrapLaboratory.md](Documentation/BootstrapLaboratory.md).

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%2014-blue.svg)](https://developer.apple.com/swift/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Run

```sh
swift run grammar-workbench-app
```

The automation-friendly executable is available with `swift run grammar-workbench --help`. It validates grammar files, runs persisted project test suites with CI-friendly exit codes, and exports versioned artifact JSON.

Language-tooling hosts can use the typed `GrammarWorkbenchSDK` product or its
versioned JSON process protocol. See [the SDK guide](Documentation/LanguageToolingSDK.md).

Cross-platform hosts can depend on the `GrammarWorkbenchCore` product. It exposes the same stable parser, semantic, project, generator, and interchange contracts while isolating native SwiftUI, AppKit, and WebKit surfaces. Graph interchange remains portable; `GrammarGraphLayoutEngine.availability` distinguishes the Rust-backed Swift-Layout backend from interchange-only platforms. See [cross-platform core separation](Documentation/CrossPlatformCoreSeparation.md).

Linux delivery includes release archives for the CLI, LSP server, and stateful tooling service, plus a container build and machine-readable `platform-info` report. Ubuntu CI builds, packages, and smoke-tests the complete headless toolchain; the macOS-only SwiftUI application remains a separate product. See [Documentation/LinuxDelivery.md](Documentation/LinuxDelivery.md).

WASM feasibility is available through an experimental WASI stateless-tooling host and a zero-dependency browser demonstration over portable LR tables. The build gate distinguishes a real Swift WASM module from the browser interchange profile and reports when no compatible WASM SDK is installed. See [Documentation/WASMFeasibility.md](Documentation/WASMFeasibility.md).

Reproducible portability pins the validated Swift, Node, Swift WASM SDK, WASI
target, and runtime contract in `Packaging/PortabilityToolchain.json`. Dedicated
CI builds and executes the real module and compares its SDK responses with the
native host. See [Documentation/ReproduciblePortabilityAndRelease.md](Documentation/ReproduciblePortabilityAndRelease.md).

The supported browser profile is now a versioned portable LR artifact runtime
running each parse in a cancellable Web Worker. `portable-browser` generates
validated schema-2 artifacts, while `grammar-workbench browser-runtime`
publishes the support decision. Browser WASI adapters are explicitly outside
the supported profile. See [Documentation/BrowserAndPortableRuntime.md](Documentation/BrowserAndPortableRuntime.md).

Long-lived IDE and build integrations can retain incremental state through
`GrammarStatefulLanguageToolingService` or `grammar-workbench-service`, a
concurrent JSON-lines host with lifecycle events and request cancellation. See
[the stateful tooling guide](Documentation/StatefulToolingProtocol.md).

Reusable semantic language definitions can now be distributed as versioned `GrammarSemanticLanguageKitManifest` files. A kit binds its grammar, semantic rules, file extensions, conformance tests, and generator defaults; strict compilation detects stale semantic production selectors before a consumer opens a project. Kits work through the library, CLI, SDK, and stateful service host. See [Documentation/SemanticLanguageKits.md](Documentation/SemanticLanguageKits.md).

Canonical grammar exchange spans the bootstrap BNF profile, Workbench notation, and EBNF lowering. `portable-import`, `portable-render --verify`, and `bootstrap-bundle` provide fingerprinted grammar envelopes and reproducible fixed-point evidence. See [Documentation/BootstrapLaboratory.md](Documentation/BootstrapLaboratory.md).

Parser research can be expressed as versioned, falsifiable validation programmes. `research-validate` records stable evidence separately from timing distributions, while `research-compare` detects incompatible baselines and pass-to-fail regressions. See [Documentation/ResearchValidationProgramme.md](Documentation/ResearchValidationProgramme.md).

The Research workspace also offers three selected previews for ambiguity growth, precedence-hidden alternatives, and search reproducibility. Each gives a plain-language conclusion while retaining its complete validation report. See [Documentation/SelectedResearchPreview.md](Documentation/SelectedResearchPreview.md).

Graph visualization now uses a shared, portable platform backed by the published [Swift-Layout](https://github.com/hakkabon/Swift-Layout) binary package and its Rust Sugiyama engine. LR automata, syntax trees, shared parse forests, and semantic dependencies share validated graph models, configurable layout, bounded caching, SDK/CLI access, and SVG export. See [Documentation/GraphVisualizationPlatform.md](Documentation/GraphVisualizationPlatform.md).

Graph correctness is continuously checked with deterministic pathological corpora, geometry invariants, minimized regression fixtures, phase-separated timing, and stable Graphviz DOT export. These facilities are available through the library, CLI, and language-tooling SDK.

Advanced graph geometry adds two-pass native text measurement, shape-aware edge boundaries, configurable arrowheads, rotated labels, same-rank constraints, compound clusters, an STR-packed spatial index, and portable advanced SVG/DOT output.

Interactive parser visualization builds stable-layout step-through timelines with active state and transition highlighting, playback controls, pan/zoom/fit viewport state, minimaps, and collapsible syntax-tree or shared-forest projections. Timelines are available through the library, CLI, SDK, JSON, and standalone HTML.

Visual product consolidation gives the editor and graph surfaces one semantic palette, persisted appearance and motion preferences, consistent focus and reduced-motion behavior, and a native **Visuals** gallery for reviewing representative states. Portable visual audits and deterministic SVG/HTML snapshot manifests make accessibility and presentation changes visible to release automation. See [Documentation/VisualProductConsolidation.md](Documentation/VisualProductConsolidation.md).

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
let comparison = try compilation.compareAlgorithms()
```

ISO-style EBNF is also a first-class input. Select EBNF in the app or set `notation: .ebnf` in a compilation request; `.ebnf` files are detected automatically by the CLI and document importer. Grammar Workbench delegates expansion to the existing `Grammar` package and then feeds its lowered BNF into the same LR pipeline, so there is only one EBNF implementation. The lowered source and stable synthetic nonterminal names are available for inspection:

```swift
let lowered = GrammarWorkbenchAPI.lowerEBNF(ebnfSource)
let compilation = GrammarWorkbenchAPI.compile(.init(
    source: ebnfSource,
    algorithm: .lalr,
    notation: .ebnf
))
print(lowered.loweredSource)
```

Lowering also publishes `productionOrigins`, mapping every generated BNF reduction identity back to its native EBNF declaration. The editor uses the same map for diagnostic underlines and navigation from states, table cells, decisions, and productions. EBNF completion hides synthetic lowering symbols, while native diagnostics and quick fixes cover undefined references and unclosed option, repetition, and grouping constructs. See `Documentation/EBNFEditorIntelligence.md`.

## Extensible generation and external interchange

`GrammarGenerator` is the public extension boundary for code generators, documentation emitters, and build-system adapters. A generator receives only `GrammarCompilation` and public immutable snapshots. Register generators in an independent `GrammarGeneratorRegistry`; equal identifiers are rejected unless replacement is explicit, and generation runs away from the registry actor. Results support one or more named text or binary files plus non-fatal diagnostics.

```swift
let registry = GrammarGeneratorRegistry()
try await registry.register(MyLanguageGenerator())
let result = try await registry.generate(
    identifier: "my-language",
    from: compilation,
    options: .init(["namespace": "Example"])
)
```

Built-ins provide the standalone Swift parser (`swift`), a coverage-complete Swift semantic-action starter (`semantic-swift`), portable production-only BNF (`bnf`), versioned artifact JSON (`artifact-json`), a tool-neutral semantic model (`semantic-model-json`), and the worker-compatible portable LR artifact (`portable-browser`). The app exposes these outputs in the Interchange menu. Automation can discover and invoke built-ins uniformly with `grammar-workbench list-generators` and `grammar-workbench generate GENERATOR GRAMMAR OUTPUT [ALGORITHM] [KEY=VALUE ...]`; the existing `generate-swift` command remains compatible.

Artifact interchange schema 2 uses the public engine-independent `GrammarArtifactSnapshot` and adds producer metadata. `GrammarInterchangeCodec.decodeArtifact` validates the envelope kind, schema version, and public API version before returning it. It also reads legacy schema-1 artifact exports and normalizes them to the public envelope. Project interchange is schema 2 and records the source notation; schema-1 projects remain readable and default to the native workbench notation.

For multi-document language projects, `GrammarProjectManifest` provides a separate versioned envelope containing the grammar configuration, embedded sources, batch tests, and generator targets. `GrammarProjectWorkspace` incrementally analyzes all sources, publishes a project-wide semantic index, refreshes them after grammar changes, and invokes configured generators. Automation can use `grammar-workbench project-check PROJECT` and `grammar-workbench project-generate PROJECT OUTPUT_ROOT`. See [Documentation/ProjectInfrastructure.md](Documentation/ProjectInfrastructure.md).

`GrammarSemanticWorkspaceSchema` adds language meaning to that neutral index by classifying token kinds under selected productions as definitions or references. Immutable workspace snapshots provide symbol search, definition/reference navigation, unresolved and duplicate diagnostics, dependency edges, and collision-checked revision-guarded rename plans. Project automation uses `project-semantic` and `project-rename`; see [Documentation/SemanticWorkspaceServices.md](Documentation/SemanticWorkspaceServices.md).

For live editors and build services, `GrammarWorkbenchIncrementalCompiler` moves construction off the caller's executor, coalesces concurrent equal requests, and keeps a bounded least-recently-used cache of immutable compilations. Each result includes front-end, LR-construction, total-delivery, state, item, and table-entry metrics; `statistics()` exposes cache hits, misses, shared requests, and evictions.

```swift
let compiler = GrammarWorkbenchIncrementalCompiler(capacity: 8)
let compilation = await compiler.compile(.init(source: grammarSource, algorithm: .lalr))
print(compilation.performance)
print(await compiler.statistics())
```

`GrammarIncrementalLanguageSession` complements construction caching with versioned UTF-16 document edits, checkpoint-based incremental relexing and deterministic reparsing, multi-document analysis snapshots, grammar replacement, stable session-local token and subtree identities, a searchable source index, and explicit reuse and fallback metrics. `GrammarIncrementalSemanticEvaluator` incrementally applies any typed semantic reducer and invalidates its cache across grammar revisions. The infrastructure is suitable for editors, language servers, indexes, and build daemons; the bundled LSP advertises incremental synchronization and forwards ranged edits through the same analysis coordinator. See [Documentation/IncrementalLanguageInfrastructure.md](Documentation/IncrementalLanguageInfrastructure.md).

```swift
let session = try GrammarIncrementalLanguageSession(compilation: compilation)
let first = try await session.openDocument(id: "main", text: source, revision: 1)
let next = try await session.apply(
    documentID: "main",
    edits: [.init(range: changedRange, replacement: replacement)],
    revision: 2
)
print(next.reuse)
print(next.semanticIndex.entries(named: "Declaration"))
```

`GrammarWorkbenchAPI.version` and `GrammarArtifactSnapshot.apiVersion` identify the public contract (currently version 1). Artifact state and production identifiers are stable within one compiled artifact; incremental token and node identities are stable only within their owning language session. Neither identity kind should be persisted globally. Additive fields and APIs may appear within a version, while incompatible Codable schema changes require a new API version.

Generated parsers are standalone Swift files with no Grammar Workbench dependency. They include deterministic ACTION/GOTO tables, lexer rules, typed tokens, parse-tree nodes, and structured lexical or syntax errors. Every reduction node records its production identity and exposes a bottom-up `evaluate` method, allowing applications to build typed ASTs without modifying generated parser tables. Generation rejects unresolved conflicts by default; callers may explicitly select shift, reduce, or table-order preference through `SwiftParserConflictPolicy`. The app provides **Interchange → Generate Swift Parser…**, and automation can use `grammar-workbench generate-swift GRAMMAR OUTPUT [ALGORITHM] [TYPE]`.

Successful library parses now include a Codable `GrammarSyntaxNode` tree alongside the original rendered tree. Nodes preserve lexemes, source ranges, production identities, and missing tokens inserted during recovery. Implement `GrammarSemanticReducer` directly or assemble `GrammarSemanticActions` from per-production closures, then call `compilation.parse(input, using: reducer)` to produce an application-specific AST, evaluator result, symbol index, or other `Sendable` value. `GrammarSemanticModel.validate(_:)` detects missing and stale action registrations before parsing, and its production lookup helpers avoid hard-coded rule discovery. Generate an editable starter with `grammar-workbench generate semantic-swift GRAMMAR OUTPUT typeName=MySemantics`. See `Documentation/SemanticDeveloperExperience.md` for the complete workflow.

Diagnostic parsing is enabled by default through `GrammarCompilation.parse`. It reports source-located expected-token sets, performs bounded single-token insertion or deletion, falls back to panic-mode synchronization, continues after recoverable errors, and marks inserted symbols in the concrete parse tree. Pass `GrammarParseOptions(enablesRecovery: false)` for strict fail-fast parsing. Language-specific recovery can prioritize likely inserted tokens and restrict panic-mode boundaries with `preferredInsertions` and `synchronizationTerminals`. Recovery decisions also appear in the Workbench trace, standalone HTML reports, and generated parsers through `parseRecovering`.

`GrammarCompilation.diff(from:)` explains the structural effect of an edit with state, table, conflict, production, and terminal deltas plus added and removed rules. The Analysis inspector shows this impact after each successful rebuild, and `grammar-workbench diff OLD NEW [OUTPUT]` emits the same information as JSON for reviews and CI.

## Generalized parser engineering

`GrammarCompilation.parseGeneralized` provides bounded generalized LR parsing alongside the deterministic production parser. It forks ACTION candidates at conflicts, interns equal symbol/span results into a shared-packed parse forest, and merges equivalent configurations before concrete trees are enumerated. The result retains compatibility alternatives with stable identities plus `sharedForest` nodes, packed families, and bounded derivation counting. Independent configuration, step, shared-node, family, and materialized-tree limits, rejection diagnostics, depth- or breadth-first search, and cooperative cancellation make ambiguity analysis safe for applications and tooling. By default it respects precedence-resolved decisions; set `exploresResolvedConflicts` to reveal ambiguity hidden by precedence or associativity declarations.

`GrammarParsingPlatform` adds deterministic, generalized, and adaptive orchestration behind one Codable result. Adaptive mode escalates only when deterministic parsing reaches an unresolved conflict, retains both engine results, applies reproducible ambiguity-selection policies, supports bounded order-preserving concurrent batches, and evaluates selected trees with ordinary semantic reducers. Project workspaces and `grammar-workbench platform-parse` expose the same policy. See [Documentation/AdvancedParsingPlatform.md](Documentation/AdvancedParsingPlatform.md).

The app's **Research** workspace runs this engine against the current sample and shows accepted trees, reached limits, rejection details, action counts, branch points, peak pending work, duplicates, and discarded configurations. Automation can use `grammar-workbench generalized-parse GRAMMAR INPUT [OUTPUT] [OPTIONS]`; `research-parse` remains a compatibility alias. Generalized parsing reuses generated LR artifacts but remains deliberately separate from deterministic recovery and generated-parser contracts. See [Documentation/GeneralizedParsing.md](Documentation/GeneralizedParsing.md).

The **Compare** workspace constructs SLR(1), LALR(1), and canonical LR(1) lazily from the same grammar. It compares state, transition, table, conflict, and resolved-decision counts; maps states by stable LR(0) cores; identifies canonical states merged by LALR; and lists semantically different table cells with navigation into the currently selected artifact. Recommendations prioritize eliminating unresolved conflicts and then minimizing state complexity. Comparison reports are Codable through `compareAlgorithms()`, may be included in standalone HTML, and are available from `grammar-workbench compare GRAMMAR [OUTPUT]`.

`Examples/Expression.grammar`, `Examples/Expression.ebnf`, and `Examples/ExpressionTests.json` provide ready-to-run grammar and project-interchange fixtures for both the app and CLI. `grammar-workbench lower-ebnf INPUT.ebnf OUTPUT` exposes the lowered form for debugging.

For build-time generation, attach the package's `GrammarWorkbenchPlugin` to a Swift target containing `.grammar` or `.ebnf` files. The plugin invokes the same CLI generator and emits standalone `<GrammarName>Parser.swift` sources, keeping generated parser behavior aligned with the workbench:

```swift
.target(
    name: "LanguageParser",
    plugins: [.plugin(name: "GrammarWorkbenchPlugin", package: "GrammarWorkbench")]
)
```

## Language-server ecosystem

`GrammarWorkbenchLSP` is a reusable server library and `grammar-workbench-lsp` is its JSON-RPC-over-stdio executable. Open Workbench or EBNF grammar documents receive live diagnostics, shared editor completions, go-to-definition, and native quick fixes. Associated source documents receive lexical and syntax diagnostics, expected-token completion, production-aware hover, document symbols, and folding ranges. Incremental UTF-16 changes are applied atomically and debounced, while saves are analyzed immediately through the shared incremental analysis coordinator.

Dependency-free clients are included for VS Code and Neovim under `Clients/`, with a ready-to-open workspace under `Examples/lsp`. The VS Code protocol client is exercised end to end against the real server by `node Scripts/m4-client-test.js`; any standards-compliant editor can connect using the grammar-name/language-id convention described in [Clients/README.md](Clients/README.md). Vendored Swift LSP protocol sources and their Apache-2.0 provenance are documented in [LocalDependencies/README.md](LocalDependencies/README.md). See [Documentation/Ecosystem.md](Documentation/Ecosystem.md) for products and distribution policy.

## Production validation

`Examples/Corpus` contains compatibility grammars covering recursive JSON-like data, a precedence-based statement language, nested lexer modes, and an intentional dangling-else conflict. The test suite compiles the applicable SLR, LALR, and canonical LR variants and checks strict accepted and rejected inputs. It also enforces generous construction-size and latency ceilings on a generated representative grammar; these ceilings are regression tripwires rather than microbenchmarks.

`Scripts/smoke-release.sh CLI_PATH` validates every corpus grammar through the packaged CLI, exports comparison and artifact JSON, invokes the generic Swift and BNF generators, and asks `swiftc` to parse the generated Swift source. Release packaging runs this smoke test automatically and emits `SHA256SUMS` beside the application and CLI archives. Pull requests and pushes to the primary development branches run the full suite, a release CLI build, corpus smoke tests, and metadata validation.

The release-candidate gate includes external SwiftPM consumers for the stable library, LSP, build plugin, and language-tooling SDK products. Performance, artifact-size, GUI containment, API-maturity, and fixture requirements are declared in `Packaging/ReleaseCandidate.json` and enforced by tests. Run `Scripts/validate-release-candidate.sh`; add `--package` to assemble and validate host-architecture application and CLI archives. See `Documentation/ReleaseCandidate.md`, `Documentation/API-Stability.md`, and `Documentation/Migration.md` for release policy and compatibility guidance.

## Production packaging

`Scripts/package-release.sh` builds the SwiftUI application, CLI, LSP server, and stateful tooling service, assembles a macOS 14 application bundle with document declarations, privacy manifest, and sandbox entitlements, and produces separate application, CLI, LSP, service, and editor-client ZIP archives plus SHA-256 checksums. It defaults to the host architecture; set `ARCHS="arm64 x86_64"` for a universal release. The declared source version, bundle metadata, CLI version, and archive name must agree.

For a local Developer ID release, provide `SIGNING_IDENTITY="Developer ID Application: …"`. Add `NOTARY_PROFILE` for an `xcrun notarytool` keychain profile; the script submits, waits, staples, rebuilds the archive, and validates the result. A deterministic default icon is included; `APP_ICON` may point to a replacement `.icns`. Regenerate the default and its inspectable PNG iconset with `swift Scripts/generate-app-icon.swift /tmp/GrammarWorkbench.iconset Packaging/AppIcon.icns`. Signing identities and notarization credentials are intentionally not stored in the repository. Tagged GitHub builds run the full suite and publish unsigned review artifacts; signed distribution can use the same script in a credentialed release environment.

The entitlement template grants only App Sandbox, user-selected read/write files, and app-scoped bookmarks. An external Xcode host should use [Packaging/GrammarWorkbench.entitlements](Packaging/GrammarWorkbench.entitlements) and mirror [Packaging/Info.plist](Packaging/Info.plist).

The app is a native document-based workbench. `.grammarworkbench` documents persist editable grammar source, the selected LR algorithm, and named sample inputs with macOS autosave and undo support. Plain-text grammars can also be opened and exported. Edits regenerate diagnostics and artifacts after a short debounce on an incremental background compiler while retaining the last valid automaton during syntax errors. Stale edit results are discarded, identical in-flight builds share work, and recent exact source/algorithm requests are reused. The toolbar reports construction latency and exposes phase and artifact-size details in its tooltip.

The native grammar editor provides syntax highlighting, line numbers, Find, symbol/directive completion, inline diagnostic underlines, source navigation from artifacts and diagnostics, semantic grammar warnings, and targeted quick fixes.

Use `%token NAME ...` to enable explicit-terminal mode and undefined-symbol validation. Grammars without `%token` remain compatible and infer unquoted terminals.

Attach a regular expression to a token with `%token NAME /pattern/` and declare ignored input with `%skip /pattern/`. Samples then accept raw source text; the deterministic lexer uses maximal munch, preserves lexemes and source locations, and feeds token identities into the LR parser. Tokens without patterns continue to match their literal spelling. Grammars without lexer rules retain the whitespace-separated token input mode.

Lexers begin in the implicit `DEFAULT` mode. Use `%mode NAME` to assign subsequent rules to another mode, and append `%begin NAME`, `%push NAME`, or `%pop` to a `%token` or `%skip` rule to transition after it matches. `%begin` replaces the active mode; `%push` and `%pop` support nested constructs. Static lexer analysis reports undeclared, duplicate, empty, and unreachable modes, invalid pops, and exactly shadowed rules. Runtime diagnostics identify the active mode for coverage gaps and report input that ends with an unclosed mode stack. Token inspectors, public API snapshots, HTML reports, and generated Swift parsers preserve each token’s originating mode.

```text
%token QUOTE /"/ %push STRING
%mode STRING
%token TEXT /[^"]+/
%token QUOTE /"/ %pop
```

The automaton view uses a deterministic layered layout with routed cyclic edges, state/item/transition search, decision-state filtering, adaptive compact rendering, pan and zoom, Fit controls, and a minimap. Large graphs render a bounded state window while preserving the selected state.

Conflict analysis uses parser-configuration search to find short witnesses and bounded suffix search to produce a common accepting counterexample where possible. Decisions include side-by-side branch trees, replay traces, exact precedence provenance, and `%expect N` matching for intentional unresolved conflicts.

Decision visualization distinguishes unresolved conflicts (red), precedence- or associativity-resolved decisions (blue), and expected conflicts (green) across automaton nodes, the minimap, state filters, parsing-table cells, inspectors, tooltips, and accessibility labels. Table decision cells retain the original candidate actions while displaying the effective parser action.

The Tests workspace persists named accept, reject, and conflict cases with optional exact parse-tree snapshots. Batch runs use the same lexer and LR artifact as interactive samples, report expectation or lexical failures, and can be included in standalone HTML reports. Versioned project JSON round-trips grammar source, algorithm, samples, selection, and tests with validation on import; generated artifact JSON provides an immutable machine-readable snapshot of states, tables, decisions, and replay data. Older `.grammarworkbench` documents decode with an empty test suite.

## Architecture

- `ArtifactModel.swift`: stable, typed identities and immutable artifact snapshots.
- `PublicAPI.swift`: versioned library façade and engine-independent Codable snapshots.
- `IncrementalConstruction.swift`: actor-isolated request coalescing, bounded LRU reuse, and construction metrics.
- `IncrementalLanguageInfrastructure.swift`: versioned UTF-16 edits, multi-document analysis, stable session identities, and reuse metrics.
- `IncrementalSemanticInfrastructure.swift`: typed semantic caching, grammar invalidation, searchable source indexes, and indexing metrics.
- `ProjectInfrastructure.swift`: portable project manifests, multi-document workspaces, aggregate indexes, tests, and generator plans.
- `SwiftParserCodeGenerator.swift`: standalone Swift lexer/parser source generation.
- `GeneratorInfrastructure.swift`: public generator protocol, registry, multi-file results, and built-in generators.
- `AlgorithmComparison.swift`: cross-algorithm metrics, state correspondence, table differences, and recommendations.
- `GrammarFrontEnd.swift`: source-located grammar parsing, diagnostics, and set analysis.
- `EBNFGrammarAdapter.swift`: integration with the Grammar package's EBNF lowering and stable native-source conversion.
- `ArtifactDiff.swift`: public structural edit-impact summaries.
- `SemanticOutput.swift`: source-aware syntax trees, semantic reducers, and ecosystem metadata.
- `AdvancedParsing.swift`: bounded, cancellable generalized LR parsing, stable forest identities, rejection diagnostics, and engineering metrics.
- `AdvancedParsingPlatform.swift`: adaptive engine selection, ambiguity policy, common results, semantic selection, and bounded batches.
- `GuidedGrammarEngineering.swift`: plain-language grammar health, prioritized actions, and validated source-change previews.
- `GrammarAnalysisAndTransformation.swift`: structural reports, explainable cleanup plans, corpus generation, and bounded behavioral comparison.
- `LRConstructionEngine.swift`: deterministic LR(0)/LR(1) closure, goto, LALR merging, table generation, and precedence resolution.
- `LexerRuntime.swift`: maximal-munch raw-source lexing, skipped rules, lexeme ranges, and lexical diagnostics.
- `ParserRuntime.swift`: legacy token input, LR execution, parse trees, trace frames, conflict witnesses, and branch replay.
- `GrammarWorkbenchDocument.swift`: native document persistence and the public document-hosting view.
- `GrammarEditor.swift`: native AppKit-backed editor, source decoration, completion, line numbering, and quick fixes.
- `SampleArtifact.swift`: replaceable sample artifact provider.
- `ExplorerStore.swift`: cross-view selection and replay state.
- `ArtifactExplorerView.swift`: native master/detail explorer.
- `VisualProductConsolidation.swift`: portable visual preferences, design tokens, audits, and snapshot manifests.
- `VisualProductGalleryView.swift`: native reference gallery for product states and parser visualization.
- `HTMLExporter.swift`: dependency-free standalone report export.
- `TestingAndInterchange.swift`: persistent test cases, batch execution, and versioned project/artifact JSON interchange.

The UI consumes immutable `GrammarArtifact` values rather than construction internals, keeping artifact identities and inspection views independent from the algorithms that produce them.

## License

MIT License — see [LICENSE](LICENSE) for details.

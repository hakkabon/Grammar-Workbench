# Graph visualization platform

Phase 16 replaces the automaton view's private layout algorithm with a shared graph contract backed by the published [Swift-Layout](https://github.com/hakkabon/Swift-Layout) binary package. Swift-Layout wraps the Rust [Layout](https://github.com/hakkabon/Layout) engine and is updated from tagged Rust releases by its zero-touch GitHub Actions workflow. Grammar Workbench depends on a pinned Swift-Layout revision; it does not compile Rust or copy generated UniFFI bindings.

The [Sample-App](https://github.com/hakkabon/Sample-App) remains the reference gallery for the lower-level package. Grammar Workbench builds a language-engineering layer above it rather than duplicating the sample application's domain objects or presentation code.

## Portable graph contract

`GrammarGraph` contains stable string-identified nodes and edges. Nodes carry labels, optional detail, visual kind, measured size, and metadata. Edges retain their own identity, label, and metadata. The contract is `Hashable`, `Codable`, and `Sendable`, so the same graph can travel through the SDK, service host, CLI, release fixtures, or a native view.

`GrammarGraphLayoutOptions` exposes:

- median-relaxation or balanced-alignment coordinate assignment;
- straight, orthogonal, or Bézier routing;
- top-to-bottom or left-to-right flow;
- node gaps, crossing-reduction sweeps, relaxation passes, and export margin.

`GrammarGraphLayoutEngine` validates duplicate identities, dangling edges, node dimensions, and bounded options before crossing the FFI boundary. One batched Swift-Layout call performs cycle breaking, ranking, dummy-node insertion, crossing reduction, coordinate assignment, label-aware routing, and self-loop handling. Rust errors and contained panics become ordinary `GrammarGraphLayoutError` values.

The resulting `GrammarGraphLayoutSnapshot` preserves domain nodes and edges alongside positioned frames, routed points, reversed-edge and self-loop flags, portable bounds, options, and timing metrics. `GrammarGraphLayoutService` provides a bounded actor-isolated cache for repeated UI, SDK, and export requests.

## Language-engineering adapters

The platform includes adapters for:

- LR automata, now used by the existing interactive automaton view;
- concrete syntax trees;
- shared packed parse forests, with explicit packed-family nodes; and
- semantic workspace dependency graphs.

These adapters preserve stable parser and semantic identities in graph metadata. Future GSS, grammar-dependency, FIRST/FOLLOW, bootstrap-generation, and transformation graphs can use the same model without changing Swift-Layout.

## Rendering and automation

`GrammarGraphSVGRenderer` exports accessible standalone SVG with node-kind styling, edge labels, reversed-edge styling, and optional interactive controls. The existing automaton WebKit view keeps its search, decision filters, selection bridge, minimap, pan, zoom, and fit behavior while receiving coordinates and routes from Swift-Layout.

Automation can produce JSON layout snapshots or SVG:

```sh
grammar-workbench graph-layout Examples/GraphVisualization.json Graph.json
grammar-workbench graph-layout Examples/GraphVisualization.json Graph.svg
```

The language-tooling SDK exposes the same operation as `graphLayout`; stateful and JSON-lines hosts inherit it through the stateless operation boundary.

## Evolution boundary

Layout quality will continue improving independently in the Rust repository. Grammar Workbench owns language-domain flattening, stable interchange, caching, interaction, accessibility, and visual styling. Swift-Layout owns binary distribution and the Swift-facing engine interface. This separation allows Layout and the Workbench to progress in parallel without coupling parser APIs to generated FFI types.

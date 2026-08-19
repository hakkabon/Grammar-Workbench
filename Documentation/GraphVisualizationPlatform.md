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

## Correctness and measurement

Phase 23 adds a validation boundary independent of the renderer and layout implementation. `GrammarGraphValidator` reports stable machine-readable issue codes for malformed graph identity, dangling endpoints, invalid geometry, missing layout results, overlapping nodes, and edge paths crossing unrelated nodes. Structural and positioned validation are separate, so malformed interchange can be diagnosed without invoking Swift-Layout. Edge/node crossings are warnings rather than errors because routing policies may intentionally trade clearance for compactness.

`GrammarGraphMeasurementRunner` records input validation, the complete Swift/Layout boundary, the engine-reported layout interval, output validation, and total wall time independently. The boundary measurement intentionally includes Swift encoding, UniFFI transit, Rust execution, and returned-value decoding; the engine-reported interval permits regressions inside that boundary to be distinguished from validation work without claiming precision the current FFI API cannot provide.

The deterministic corpus generator exercises variable node sizes, cycles, self-loops, parallel edges, disconnected components, and labelled edges from a reproducible seed. Release validation runs a bounded corpus, while `GrammarGraphFailureMinimizer` can reduce a failing graph to a compact JSON regression fixture using a caller-supplied failure predicate.

For automation and Graphviz comparison:

```sh
grammar-workbench graph-validate Examples/GraphVisualization.json GraphValidation.json
grammar-workbench graph-measure Examples/GraphVisualization.json GraphMeasurement.json
grammar-workbench graph-dot Examples/GraphVisualization.json Graph.dot
```

The tooling SDK exposes equivalent `graphValidate`, `graphMeasure`, and `graphDOT` operations. DOT output is deterministically ordered and retains stable node and edge identities, labels, flow direction, routing preference, and approximate dimensions.

## Advanced geometry

Phase 24 adds a portable geometry specification above the stable graph contract. It supports rectangle, rounded-rectangle, ellipse, and diamond boundaries; filled, open, swept-back, or suppressed arrowheads; tangent-aligned edge labels; same-rank groups; and compound clusters. The advanced SVG renderer preserves these choices, while advanced DOT export emits compatible `rank=same`, cluster, node-shape, and arrowhead declarations for Graphviz comparison.

`GrammarGraphGeometryEngine` uses a two-pass architecture. The first pass asks a platform-provided `GrammarGraphTextMeasurer` for actual node and edge-label dimensions and sends those pixel dimensions through the existing single batched Swift-Layout call. The second pass computes shape-aware boundary intersections, terminal tangents, arrowhead geometry, rotated-label bounds, same-rank placement, and cluster bounds entirely in Swift. The default heuristic measurer keeps headless CLI and Linux interchange workflows deterministic; AppKit, SwiftUI, or browser hosts can supply their native font measurer.

`GrammarGraphSpatialIndex` bulk-loads nodes, edge labels, and clusters into an immutable STR-packed R-tree. Point and rectangle queries therefore avoid linear scans during hit testing, selection, label collision inspection, and future interactive forest exploration.

```sh
grammar-workbench graph-geometry \
  Examples/GraphVisualization.json \
  Examples/GraphGeometry.json \
  AdvancedGraph.svg
```

The output suffix may be `.json`, `.svg`, or `.dot`. The SDK exposes the same pipeline as `graphGeometry` and returns a fully portable `GrammarGraphAdvancedLayoutSnapshot`.

## Evolution boundary

Layout quality will continue improving independently in the Rust repository. Grammar Workbench owns language-domain flattening, stable interchange, caching, interaction, accessibility, and visual styling. Swift-Layout owns binary distribution and the Swift-facing engine interface. This separation allows Layout and the Workbench to progress in parallel without coupling parser APIs to generated FFI types.

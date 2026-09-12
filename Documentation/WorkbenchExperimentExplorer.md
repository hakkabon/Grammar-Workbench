# Workbench experiment explorer

Phase 12 turns the durable output of a Grammar-REPL comparison into an
interactive research surface. The macOS Workbench has a new **Experiments**
workspace and **Open Experiment** command for schema-1 and schema-2 artifacts
produced by Grammar-REPL 0.6.0.

## Exploration surfaces

The explorer provides:

- a ten-engine evidence matrix showing capability, status, concrete
  derivations, forest shape, ambiguity, and replay size;
- a selectable baseline with explicit summary differences for another engine;
- a bounded graph projection of each portable packed forest;
- click-to-collapse forest nodes and a visible hidden-node count;
- step, slider, and graph-highlight controls for portable replay events; and
- diagnostic, unsupported-capability, producer, agreement, and fingerprint
  context; and
- Compiler-owned values, failures, derivation counts, and cross-engine
  semantic agreement when schema-2 evidence is present.

`grammar-workbench experiment-inspect EXPERIMENT [OUTPUT]` exposes the same
validated summary as stable JSON for headless use.

## Trust and ownership

Import is fail-closed and bounded to 64 MiB, 250,000 forest nodes per engine,
one million replay events, and 2,000 rendered nodes. It validates schema,
producer, engine ordering, parser settings, replay ordering, forest extents,
and every root, edge, ambiguity, and replay-node reference before presentation.

Workbench deliberately does not recompute the experiment fingerprint, rerun
parser engines, or execute Compiler semantics. Those operations require
Grammar-REPL's complete grammar, engine family, and Compiler mapping and remain
owned by `grammar-repl-experiment verify`. The
Workbench labels the fingerprint as recorded evidence, never as verification.
This read-only consumer projection avoids adding Grammar-REPL and its ten parser
engines to Workbench's dependency graph.

## Real-artifact compatibility

The implementation was exercised against artifacts emitted by Grammar-REPL
0.5.0 schema-1 and 0.6.0 schema-2 contracts, including accepted generalized
forests, Compiler semantic observations, explicit LL(1) unsupported
capabilities, terminal-only generalized rejection replay, and a rejected LR(0)
contract with no portable replay. These differences remain visible evidence;
the explorer does not normalize them away.

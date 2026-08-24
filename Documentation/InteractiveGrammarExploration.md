# Interactive grammar exploration

Phase 35 adds a rule-centred exploration layer between source editing and the
specialized parser artifacts. It reuses existing compilation and structural
analysis rather than maintaining another grammar graph.

## Exploration snapshot

`GrammarInteractiveExplorer.snapshot` creates immutable, Codable exploration
data for every declared non-terminal. Each `GrammarRuleExploration` includes:

- production text, stable production IDs, and source ranges;
- incoming and outgoing rule references;
- FIRST and FOLLOW sets;
- start, reachable, productive, nullable, and left-recursive status;
- its strongly connected recursive component.

The snapshot selects the requested rule when available and otherwise falls back
to the grammar start rule. A deterministic breadth-first path explains how the
selected rule is reached from the start symbol. Unreachable and unproductive
rules remain visible and are marked rather than silently removed.

`matchingRules` searches rule names, production text, FIRST, and FOLLOW values.
The service is renderer- and UI-neutral, has no mutable state, and throws the
same explicit compilation failure used by grammar engineering services.

## Native exploration workspace

The new **Explore** tab provides:

- searchable rule navigation with status indicators;
- a clickable path from the start rule;
- an interactive Grammar-DiagramKit railroad diagram;
- production rows that select their source declarations;
- forward and reverse dependency navigation;
- recursive-component navigation;
- FIRST and FOLLOW inspection.

Diagram element activation uses the Phase 36 structural-ID mapping to highlight
the selected element and navigate to its production. Phase 35 therefore remains
useful independently as a data service while Phase 36 supplies its visual rule
representation.

## Deliberate limits

This phase explores the compiled grammar, not parser states or runtime parse
trees. Dependency paths are shortest paths in the non-terminal reference graph;
they are explanatory navigation aids, not derivation proofs. FIRST/FOLLOW and
structural facts update after compilation settles. Persistent bookmarks,
multi-rule comparison, derivation animation, and hosted exploration sessions
remain possible future layers over the snapshot.

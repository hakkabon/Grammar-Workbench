# Advanced parsing platform

`GrammarParsingPlatform` provides one bounded orchestration layer over the deterministic and generalized LR engines. Existing `parse`, `parseGeneralized`, recovery, replay, and forest APIs remain unchanged; the platform is intended for consumers that need to choose engines by policy while handling one stable result envelope.

## Parsing modes

- `deterministic` always uses the production LR runtime, including configured diagnostic recovery.
- `generalized` always explores the bounded generalized engine.
- `adaptive` starts deterministically and escalates only if the input reaches an unresolved ACTION conflict.

Adaptive results retain the deterministic conflict result alongside the generalized forest. The `decision` field explains why an engine was selected, while common metrics report deterministic attempts, generalized configurations and branch points, accepted alternatives, reached limits, and elapsed time.

## Ambiguity policy

Generalized and adaptive requests choose one of four policies:

- `requireUnique` leaves ambiguous input unselected;
- `firstStable` selects by the forest's stable cross-process alternative identity;
- `shallowest` and `deepest` select by syntax-tree depth with stable identity tie-breaking.

The complete forest is always retained. Selection does not erase ambiguity: status remains `ambiguous`, allowing applications to distinguish an explicit policy decision from a unique parse. Limited results may retain and select useful accepted work, but their reached limits remain visible.

## Cancellation, batching, and semantics

`parseCancellable` cooperatively stops generalized exploration and also honors cancellation before deterministic work begins. `parseBatch` caps concurrent requests, preserves caller order, and reports request, completion, cancellation, and concurrency metrics. Each request keeps its own exact engine limits.

`parse(_:using:)` applies any `GrammarSemanticReducer` to the selected tree. An ambiguous `requireUnique` request has no selected tree and therefore fails semantic evaluation explicitly. `GrammarCompilation.evaluate(_:using:)` is also public for applications that select forest alternatives independently.

Project workspaces expose `parse(documentID:options:)` and bounded `parseAll`, so the same policy works over portable project manifests. The CLI equivalent is:

```sh
grammar-workbench platform-parse Grammar.grammar "input" result.json \
  --mode=adaptive --ambiguity=firstStable --maximum-trees=16
```

The release gate exercises adaptive escalation and a bounded, ordered batch against declared platform budgets.

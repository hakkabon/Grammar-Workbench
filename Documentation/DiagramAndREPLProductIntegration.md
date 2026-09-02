# Diagram and parse-console product integration

Phase 36 connects Grammar-DiagramKit 0.1.0 and a transcript-oriented parse console to
the native Grammar Workbench without introducing a second grammar or parser
implementation.

## Diagram boundary

The package pins Grammar-DiagramKit at commit `bf7d373`. `GrammarDiagramAdapter`
converts a successfully compiled rule into a renderer-neutral
`GrammarRuleDiagram`. Productions become alternatives, right-hand-side symbols
become terminal or non-terminal nodes, and empty productions become a visible
epsilon skip. DiagramKit therefore remains responsible for layout and drawing,
while Grammar Workbench remains responsible for grammar semantics.

Every rendered symbol retains a `DiagramElementID` mapping to its rule,
production, symbol index, and source range. Selecting an element in the native
diagram highlights it and selects its production in the grammar editor. The
mapping is explicit rather than inferred from labels, so repeated symbol names
remain distinguishable.

The native diagram and parse-console tab provides a rule picker and a scrollable adaptive
SwiftUI railroad diagram. Invalid compilations and grammars without productions
produce an explicit unavailable state rather than stale diagrams.

## Parse-console boundary

`GrammarWorkbenchConsoleSession` is a `Sendable`, UI-neutral parse console over an immutable
`GrammarCompilation`. Ordinary input calls `GrammarCompilation.parse`, so the
console, public API, tests, lexer modes, recovery, and Sample tab share the same
runtime. Entries retain the complete public parse result for later inspection.

The first command set is intentionally small:

- `:help` lists commands;
- `:rules` lists diagrammable rules;
- `:rule <name>` changes the diagram rule;
- `:history` prints submitted inputs;
- `:clear` clears the entries.

The native pane renders input, informational output, accepted results, errors,
tokens, expected terminals, and parse trees with copyable monospace text.

## Deliberate limits

The parse console is a Workbench UI adapter, not an alternate implementation of
Grammar-REPL. Grammar-REPL remains the canonical owner of REPL commands, command
history, and transcripts. The former `GrammarREPLSession` and transcript names
remain as deprecated aliases for one migration release; new code uses
`GrammarWorkbenchConsoleSession` and `GrammarWorkbenchConsoleEntry`.

# Diagram and REPL product integration

Phase 36 connects Grammar-DiagramKit 0.1.0 and a transcript-oriented REPL to
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

The native `Diagram & REPL` tab provides a rule picker and a scrollable adaptive
SwiftUI railroad diagram. Invalid compilations and grammars without productions
produce an explicit unavailable state rather than stale diagrams.

## REPL boundary

`GrammarREPLSession` is a `Sendable`, UI-neutral session over an immutable
`GrammarCompilation`. Ordinary input calls `GrammarCompilation.parse`, so the
REPL, public API, tests, lexer modes, recovery, and Sample tab share the same
runtime. Transcript entries retain the complete public parse result for later
inspection.

The first command set is intentionally small:

- `:help` lists commands;
- `:rules` lists diagrammable rules;
- `:rule <name>` changes the diagram rule;
- `:history` prints submitted inputs;
- `:clear` clears the transcript.

The native pane renders input, informational output, accepted results, errors,
tokens, expected terminals, and parse trees with copyable monospace text.

## Deliberate limits

Phase 36 does not import a separate Grammar-REPL package, execute arbitrary
code, persist transcripts in workbench documents, or expose REPL operations over
the hosted protocol. It establishes stable model/service boundaries first.
Future increments can add persisted histories, structured tree inspection,
semantic evaluation, UIKit interaction parity, diagram export controls, and
remote REPL sessions without replacing this adapter.

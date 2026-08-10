# Grammar Workbench

Grammar Workbench builds and explains SLR(1), LALR(1), and canonical LR(1) artifacts from editable grammars.

1. Create or open a `.grammarworkbench` document and begin in **Guide**, which recommends the next useful action.
2. Declare tokens with `%token`, optional lexer patterns with `/pattern/`, and ignored text with `%skip`. For context-sensitive lexing, select rules with `%mode` and transition with `%begin`, `%push`, or `%pop`.
3. Follow task-oriented links to validate the grammar, try an input, resolve ambiguity, protect behavior with tests, compare algorithms, or generate a parser.
4. Export a standalone HTML report, project interchange JSON, versioned artifact JSON, portable BNF, or a standalone Swift parser.
5. Build integrations can register custom `GrammarGenerator` implementations or invoke built-ins through the `generate` CLI command.
6. Enter malformed sample input to inspect expected tokens, recovery decisions, the recovered tree, and replay trace.
7. Open Compare to inspect state merging, table differences, conflicts, and the recommended LR algorithm.

Enable **Expert tools** to inspect the LR automaton, parse table, replay details, and generalized parsing research. Guide never hides the underlying evidence; it provides a task-oriented path to it. When duplicate or unreachable production lines are found, a safe change preview recompiles the proposal and checks samples and tests before enabling Apply.

Open **Grammar structure** in Guide for reachability, productivity, nullability, dependency, and left-recursion insights. Cleanup previews are explainable transformation plans: they reject stale source and compare language membership over saved examples plus a bounded generated corpus. Automation can export the same report with `grammar-analyze` or create a validated cleaned grammar with `grammar-transform`.

Open a `.ebnf` file or choose EBNF in the toolbar to use ISO-style notation. The Analysis inspector shows the BNF produced by the shared Grammar module and summarizes how each successful edit changes states, table entries, conflicts, terminals, and productions. Diagnostics, completions, quick fixes, and artifact navigation remain anchored to the original EBNF declarations rather than generated BNF symbols.

For automation, the CLI detects `.ebnf` files automatically. Use `lower-ebnf` to inspect lowering, `diff` to review artifact changes, and the `GrammarWorkbenchPlugin` SwiftPM build plugin to turn target-local `.grammar` or `.ebnf` files into standalone Swift parsers.

Accepted parses expose a source-aware structured syntax tree. Library clients can implement `GrammarSemanticReducer` to build typed ASTs or evaluate a tree, while generated Swift parsers provide the equivalent bottom-up `Node.evaluate` hook. Export Semantic Model JSON for external language tooling, or use the CLI `parse` command for a machine-readable tree.

The Research workspace runs the bounded generalized parser and retains multiple accepted trees with stable identities. Enable resolved-decision exploration to study ambiguity normally hidden by precedence. Results report exact configuration, step, or tree limits, rejection expectations, and action metrics; the equivalent CLI command is `generalized-parse` (`research-parse` remains an alias).

Library, project, and CLI consumers can use the advanced parsing platform to choose deterministic, generalized, or adaptive execution with reproducible ambiguity selection. The equivalent CLI command is `platform-parse`.

The repository's `Examples/Corpus` directory contains larger examples for recursive data, statement grammars, nested lexer modes, and intentional conflicts. They are also exercised by release smoke tests.

Documents autosave through the macOS document architecture. Release builds are sandboxed and only access files explicitly selected by the user.

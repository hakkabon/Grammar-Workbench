# Grammar Workbench

Grammar Workbench builds and explains SLR(1), LALR(1), and canonical LR(1) artifacts from editable grammars.

1. Create or open a `.grammarworkbench` document.
2. Declare tokens with `%token`, optional lexer patterns with `/pattern/`, and ignored text with `%skip`. For context-sensitive lexing, select rules with `%mode` and transition with `%begin`, `%push`, or `%pop`.
3. Choose an LR algorithm and inspect analysis, automaton, table, decisions, samples, and tests.
4. Export a standalone HTML report, project interchange JSON, versioned artifact JSON, portable BNF, or a standalone Swift parser.
5. Build integrations can register custom `GrammarGenerator` implementations or invoke built-ins through the `generate` CLI command.
6. Enter malformed sample input to inspect expected tokens, recovery decisions, the recovered tree, and replay trace.
7. Open Compare to inspect state merging, table differences, conflicts, and the recommended LR algorithm.

Open a `.ebnf` file or choose EBNF in the toolbar to use ISO-style notation. The Analysis inspector shows the BNF produced by the shared Grammar module and summarizes how each successful edit changes states, table entries, conflicts, terminals, and productions.

For automation, the CLI detects `.ebnf` files automatically. Use `lower-ebnf` to inspect lowering, `diff` to review artifact changes, and the `GrammarWorkbenchPlugin` SwiftPM build plugin to turn target-local `.grammar` or `.ebnf` files into standalone Swift parsers.

The repository's `Examples/Corpus` directory contains larger examples for recursive data, statement grammars, nested lexer modes, and intentional conflicts. They are also exercised by release smoke tests.

Documents autosave through the macOS document architecture. Release builds are sandboxed and only access files explicitly selected by the user.

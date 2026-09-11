# Grammar Workbench

The grammar source remains visible in the left resizable pane. The task workspace
is independent, so resizing or showing another area does not cover the editor.
The notation badge beside the filename shows how the source is interpreted.
Known Yacc-like and `.ebnf` extensions select their corresponding notation;
for unknown plain text, import detects a notation only when exactly one front end accepts it.

Use **Open Source Project** to load a `.grammar-workbench-source.json`
descriptor. Its associated program files appear in the Project workspace with
lexical, syntax, and optional semantic status. VS Code and Neovim use the same
descriptor to attach those files to the language server.

Grammar Workbench builds and explains SLR(1), LALR(1), and canonical LR(1) artifacts from editable grammars.

1. Create or open a `.gwb` document and begin in **Guide**, which recommends the next useful action. Legacy `.grammarworkbench` documents remain supported.
2. Declare tokens with `%token`, optional lexer patterns with `/pattern/`, and ignored text with `%skip`. For context-sensitive lexing, select rules with `%mode` and transition with `%begin`, `%push`, or `%pop`.
3. Follow task-oriented links to validate the grammar, try an input, resolve ambiguity, protect behavior with tests, compare algorithms, or generate a parser.
4. Export a standalone HTML report, project interchange JSON, versioned artifact JSON, portable BNF, or a standalone Swift parser.
5. Build integrations can register custom `GrammarGenerator` implementations or invoke built-ins through the `generate` CLI command.
6. Enter malformed sample input to inspect expected tokens, recovery decisions, the recovered tree, and replay trace.
7. Open Compare to inspect state merging, table differences, conflicts, and the recommended LR algorithm.

Use the **Expert** section of the navigation sidebar to inspect the LR automaton, parse table, replay details, and generalized parsing research. Guide never hides the underlying evidence; it provides a task-oriented path to it. When duplicate or unreachable production lines are found, a safe change preview recompiles the proposal and checks samples and tests before enabling Apply.

Open **Grammar structure** in Guide for reachability, productivity, nullability, dependency, and left-recursion insights. Cleanup previews are explainable transformation plans: they reject stale source and compare language membership over saved examples plus a bounded generated corpus. Automation can export the same report with `grammar-analyze` or create a validated cleaned grammar with `grammar-transform`.

Open **Bootstrap** in the Expert section to run the bounded self-hosting laboratory. It compiles a trusted BNF seed, regenerates the parser from its meta-grammar until the canonical model stabilizes, then compares a BNF corpus with the handwritten Grammar reader. For automation, run `grammar-workbench bootstrap [report.json]`.

The expert **Research** workspace exposes the shared-packed forest used by generalized parsing. It reports compact symbol/span nodes, packed families, represented derivations, and independent resource limits before showing the bounded set of materialized trees.

Project integrations can add a declarative semantic schema to classify definitions and references. The resulting workspace service supplies cross-document navigation, diagnostics, dependencies, and safe revision-checked rename plans; `project-semantic` exports the same snapshot for editor and CI automation.

Open a `.ebnf` file to use ISO-style notation. If an extensionless or ambiguous import needs correction, use **Interpret Grammar As** from the source editor's context menu. This changes the document interpretation without converting its source. The Analysis workspace shows the BNF produced by the shared Grammar module and summarizes how each successful edit changes states, table entries, conflicts, terminals, and productions. Diagnostics, completions, quick fixes, and artifact navigation remain anchored to the original EBNF declarations rather than generated BNF symbols.

For automation, the CLI detects `.ebnf` files automatically. Use `lower-ebnf` to inspect lowering, `diff` to review artifact changes, and the `GrammarWorkbenchPlugin` SwiftPM build plugin to turn target-local `.grammar` or `.ebnf` files into standalone Swift parsers.

Accepted parses expose a source-aware structured syntax tree. Library clients can implement `GrammarSemanticReducer` to build typed ASTs or evaluate a tree, while generated Swift parsers provide the equivalent bottom-up `Node.evaluate` hook. Export Semantic Model JSON for external language tooling, or use the CLI `parse` command for a machine-readable tree.

The Research workspace runs the bounded generalized parser and retains multiple accepted trees with stable identities. Enable resolved-decision exploration to study ambiguity normally hidden by precedence. Results report exact configuration, step, or tree limits, rejection expectations, and action metrics; the equivalent CLI command is `generalized-parse` (`research-parse` remains an alias).

For repeatable research across builds, encode hypotheses and expected outcomes in a `GrammarResearchProgramme`. `research-validate` repeats generalized runs, compares depth-first and breadth-first evidence, and emits integrity-checked reports; `research-compare` checks a candidate report against an unchanged programme baseline.

Start with **Selected research preview** if you want a guided introduction. Its three curated questions explain ambiguity growth, precedence-hidden alternatives, and search reproducibility in ordinary language, with the complete evidence available underneath.

Library, project, and CLI consumers can use the advanced parsing platform to choose deterministic, generalized, or adaptive execution with reproducible ambiguity selection. The equivalent CLI command is `platform-parse`.

The repository's `Examples/Corpus` directory contains larger examples for recursive data, statement grammars, nested lexer modes, and intentional conflicts. They are also exercised by release smoke tests.

Documents autosave through the macOS document architecture. Release builds are sandboxed and only access files explicitly selected by the user.

# Grammar Workbench

Grammar Workbench builds and explains SLR(1), LALR(1), and canonical LR(1) artifacts from editable grammars.

1. Create or open a `.grammarworkbench` document.
2. Declare tokens with `%token`, optional lexer patterns with `/pattern/`, and ignored text with `%skip`.
3. Choose an LR algorithm and inspect analysis, automaton, table, decisions, samples, and tests.
4. Export a standalone HTML report, project interchange JSON, generated artifact JSON, or a standalone Swift parser.

Documents autosave through the macOS document architecture. Release builds are sandboxed and only access files explicitly selected by the user.

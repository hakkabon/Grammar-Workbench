# EBNF and editor intelligence

The editor header shows a non-editable **Yacc-like** or **EBNF** badge beside
the grammar filename. Yacc-like is the directive-and-colon syntax historically
called Workbench notation in persisted files and APIs; EBNF selects ISO-style
grouping, option, and repetition syntax.

Persisted document or project metadata takes precedence when opening a grammar.
Otherwise `.ebnf` selects EBNF and known Yacc-like extensions select Yacc-like.
Unknown plain text is tried through both front ends and is detected only when
exactly one succeeds; inconclusive input falls back to Yacc-like. Detection runs
at import, never continuously during incomplete edits. The editor context menu
provides **Interpret Grammar As** for an explicit correction. Reinterpretation
does not convert source text.

Grammar Workbench continues to delegate EBNF parsing and lowering to the `Grammar` module. The workbench adds an origin layer around that conversion so generated BNF remains an implementation detail during editing.

## Origin-aware lowering

`GrammarWorkbenchAPI.lowerEBNF(_:)` returns `GrammarLoweringSnapshot.productionOrigins`. Each entry connects a parser production ID and lowered nonterminal to the original EBNF declaration and source range. Synthetic rules created for option, repetition, and grouping point back to the production that owns the construct.

The compilation front end applies these origins to production and diagnostic ranges. Consequently, selecting a production, state, table cell, or decision navigates to EBNF source just as it does for Workbench notation. Diagnostics produced after lowering are rewritten to avoid exposing generated names such as `__ebnf_1`.

Origin data is additive. Older encoded lowering snapshots without `productionOrigins` continue to decode with an empty map.

## Native intelligence

For EBNF documents, the editor:

- completes declared grammar and lexical symbols plus EBNF vocabulary;
- excludes synthetic lowering nonterminals and Workbench-only directives;
- reports undefined nonterminal references at their native source range;
- warns when a nonterminal is split across multiple declarations;
- offers fixes for missing `]`, `}`, and `)` delimiters;
- offers to create an empty production for an undefined reference.

Quick fixes are notation-aware. Applying a Workbench fix to an EBNF document, or an EBNF fix to Workbench syntax, is intentionally prevented by the editor intelligence boundary.

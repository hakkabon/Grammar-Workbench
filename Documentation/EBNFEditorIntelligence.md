# EBNF and editor intelligence

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

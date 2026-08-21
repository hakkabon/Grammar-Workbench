# Scale and interoperability

Phase 33 adds a bounded large-grammar audit and a Yacc/Bison interoperability
profile to the canonical grammar exchange. External grammars enter the same
`GrammarPortableInterchange` model used by Workbench, EBNF, and the bootstrap
BNF profile, so fingerprints and downstream tooling do not depend on their
source notation.

## Yacc/Bison profile

`GrammarPortableNotation.yacc` imports the conventional declarations and
grammar sections separated by `%%`. It supports `%token`, `%start`, `%empty`,
`%prec`, named symbols, quoted literals, alternatives, block and line comments,
prologue blocks, and nested semantic-action blocks. Host-language declarations
and semantic actions are deliberately discarded: the interchange contract is
grammar structure, not executable foreign code.

`GrammarPortableRenderFormat.yacc` produces deterministic Yacc source. Rendering
and importing it again must retain the canonical grammar fingerprint. This is a
syntax-level profile rather than compatibility with every Bison extension;
lexer definitions, semantic value types, code-generation directives, mid-rule
actions, and host code remain outside the profile.

```sh
swift run grammar-workbench portable-import Grammar.y Grammar.json
swift run grammar-workbench portable-render Grammar.json Export.y \
  --format=yacc --verify
```

The SDK's existing `portableGrammarImport` and `portableGrammarRender`
operations accept the new enum cases without a separate wire protocol.

## Scale audit

`GrammarPortableScaleValidator` counts source bytes, productions, unique
symbols, total right-hand-side symbols, and maximum production width without
constructing LR states or parse tables. Hosts can apply their own
`GrammarPortableScaleLimits`; defaults admit 20,000 productions and 250,000 RHS
symbols while bounding input at 8 MB. The resulting Codable report carries the
canonical fingerprint for correlation with build and CI records.

```sh
swift run grammar-workbench portable-audit Grammar.json Audit.json
```

This separates cheap admission control from expensive parser construction.
Passing the audit does not promise a particular LR-state count or construction
time, because those depend on grammar topology and algorithm choice. Existing
construction and generalized-parser budgets continue to govern those stages.

## Release contract

The release gate imports a real `.y` fixture containing declarations, comments,
literals, and semantic actions; verifies its Yacc round trip; audits it under
the published resource policy; and bounds audit latency. The public interchange
schema remains version 1 because the envelope shape is unchanged. Consumers
should use capability negotiation before sending a notation introduced by a
newer producer.

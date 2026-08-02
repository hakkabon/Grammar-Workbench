# Production grammar corpus

These grammars are compatibility fixtures, not only demonstrations. The test suite compiles every fixture and parses representative accepted and rejected inputs.

- `JSONSubset.grammar`: recursive collections, nullable lists, escaped strings, and numeric lexing.
- `MiniLanguage.grammar`: statement lists, precedence, keywords, identifiers, and raw-source parsing.
- `InterpolatedString.grammar`: nested lexer modes with push/pop transitions.
- `ExpectedConflict.grammar`: an intentional dangling-else conflict documented with `%expect`.

Changes to construction, lexing, recovery, or interchange should preserve this corpus unless the format change is deliberate and documented.

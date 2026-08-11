# Bootstrap laboratory

Phase 9 provides a bounded self-hosting experiment without changing the trusted grammar-import path. `GrammarBootstrapLaboratory` starts from a small Workbench lexer and LR grammar for a documented BNF profile, parses the profile's own meta-grammar, converts the result to a canonical `GrammarBootstrapSpecification`, renders the next parser grammar, and compiles it again.

A fixed point requires three equal values in consecutive generated stages:

- the canonical grammar fingerprint;
- the generated parser-source fingerprint; and
- a canonical parser-artifact fingerprint covering productions, item sets, transitions, and table actions.

Artifact serialization is not used for the fixed-point comparison because diagnostic identities and presentation ordering are not language contracts. The laboratory report retains all three fingerprints, construction counts, and the generation at which stability was reached.

After convergence, the generated parser validates a packaged BNF corpus. Each accepted grammar is normalized independently through the bootstrap profile reader and the existing handwritten `Grammar(bnf:start:)` implementation. Their canonical models must agree. This differential gate includes literals, alternatives, references, recursion, and the meta-grammar itself.

The first profile intentionally stays small: one production per line, angle-bracket nonterminals, single- or double-quoted literals, alternatives, and no explicit epsilon spelling. These boundaries are present in the Codable report and the GUI. The experiment does not replace the handwritten reader.

Run it from the expert **Bootstrap** workspace or in automation:

```sh
grammar-workbench bootstrap [report.json] [--maximum-generations=N]
```

The CLI exits unsuccessfully unless both convergence and all differential comparisons pass. `Packaging/ReleaseCandidate.json` bounds the number of generations and minimum corpus size used by the release gate.

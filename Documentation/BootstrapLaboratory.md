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
grammar-workbench bootstrap-bundle bundle.json [--maximum-generations=N]
```

The CLI exits unsuccessfully unless both convergence and all differential comparisons pass. `Packaging/ReleaseCandidate.json` bounds the number of generations and minimum corpus size used by the release gate.

## Portable bootstrap interchange

Phase 18 adds `GrammarPortableInterchange`, a canonical grammar envelope shared by the BNF bootstrap profile, Workbench notation, and EBNF lowering. The envelope records its source notation, normalized productions, start symbol, producer, schema version, and a verified canonical fingerprint. Production order and alternative order therefore do not affect identity.

`portable-import` converts source text into the envelope. `portable-render` emits deterministic BNF-profile or Workbench source, and `--verify` imports that output again and refuses to write a silently changed grammar. Named terminals are preserved across Workbench conversion; BNF literals remain explicitly distinguished in the canonical envelope.

`bootstrap-bundle` combines the canonical meta-grammar envelope with its complete fixed-point and differential-validation report. This gives researchers and build systems reproducible evidence without promoting the generated parser over the trusted reader.

```sh
grammar-workbench portable-import grammar.bnf grammar.json --start=syntax
grammar-workbench portable-render grammar.json canonical.bnf --verify
grammar-workbench bootstrap-bundle bootstrap.json
```

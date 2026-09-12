# Engine-family completion

Phase 9 brings the ecosystem's remaining parser implementations into the
shared comparison and release contract.

## New engine members

LL-Parsing 0.1.0 is the predictive top-down member. It consumes the shared
positioned `TokenStream`, uses Parser's tree and diagnostic contracts, follows
tagged dependency ranges, and keeps unified logging optional on non-Apple
platforms.

Earley-TableParser 0.1.0 contributes two independently selectable generalized
engines: simple-lookahead (SL) and extended-lookahead (EL) table traversal.
Both modes export deterministic, production-identified portable SPPF snapshots
and are checked against exact Catalan ambiguity.

Grammar-REPL 0.4.0 exposes ten choices in a single comparison:

- Earley, Earley Table SL, Earley Table EL, CYK, and RNGLR;
- LL(1); and
- LR(0), SLR, LALR, and canonical LR(1).

## Capability truthfulness

LL(1) does not accept arbitrary context-free grammars. Corpus v4 therefore
records engine requirements and grammar capabilities separately from parse
status. A left-recursive or prediction-conflicted grammar produces an explicit
unsupported observation with a rationale. It is not counted as an input
rejection and is excluded from cross-engine agreement calculations.

The new predictive-expression fixture exercises every engine on an LL(1)
grammar. The earlier ambiguous-expression probes continue to require exact
two- and five-derivation forests from every generalized engine while requiring
LL(1) to declare the grammar unsupported.

The pinned contract now covers twelve repositories, four grammars, 37 cases,
and ten engine choices. No accepted engine differences are permitted.

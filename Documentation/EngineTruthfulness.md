# Engine truthfulness

Phase 8 turns the shared corpus's engine differences into release-blocking
correctness work. The version-3 corpus retains its schema and 33 cases, but the
two RNGLR ambiguity exceptions have been removed: Earley, CYK, and RNGLR must
all accept the three- and four-operand probes and expose exactly two and five
derivations respectively.

## Correctness repairs

RNGLR 0.2.1 computes reduction closure as an edge-driven fixed point. A newly
added graph-structured-stack edge can expose paths for an ancestor reduction,
so a descriptor cannot be treated as permanently complete after its first
visit. SPPF construction also rejects candidate child spans that begin before
the production being expanded. This prevents backwards extents, cycles,
hash-order-dependent enumeration, and invalid portable snapshots. Terminal
labels use Grammar's canonical description so shared tree traversal retains
operator leaves.

LR-Parsing 0.2.2 constructs one immutable automaton per `LRParser`. Both parse
entry points and inspection reuse it. The live table generator already routed
all actions through structured candidates and decisions; obsolete helpers that
printed and silently overwrote conflicts were removed. LALR merged-state
transitions remain core-resolved and are now covered by explicit transition,
GOTO, ACTION, candidate, decision, identity, and endpoint invariants.

## Executable evidence

Grammar-REPL 0.3.2 repeats both ambiguity probes eight times across Earley,
CYK, RNGLR, LR(0), SLR, LALR, and canonical LR(1). Every run must retain stable
contracts and tree fingerprints. Generalized engines must expose the exact
Catalan counts; precedence-resolved deterministic engines must expose one tree.

The same property suite checks:

- contiguous replay steps with a status-compatible terminal event;
- deterministic forest node and edge ordering;
- unique node identities and valid edge/root/ambiguity references;
- forward extents and in-range pivots;
- production identity on every intermediate and packed node; and
- ambiguity markers backed by more than one packed child.

The ecosystem validator additionally requires the committed corpus to contain
no accepted engine differences. A future exception must therefore be introduced
as an explicit policy change rather than silently accommodating a regression.

## Audited older claims

The LR documentation previously described table regeneration, silent shift
selection, an uncertain LALR GOTO fix-up, and an incorrect comparator. The
first has been fixed; the second referred to dead code; the third is guarded by
cross-algorithm invariants; and the comparator was already correct. LR(0)
reductions on all grammar terminals are retained because that is the algorithm's
defined behavior, while SLR and LR(1)-family algorithms use narrower lookahead.

This phase does not claim that all engines have identical capabilities. It
requires truthful portable observations for the capabilities they advertise,
while detailed charts, stacks, tables, recovery policy, and native traces remain
engine-owned.

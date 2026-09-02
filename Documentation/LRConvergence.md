# LR convergence

Grammar-Workbench and LR-Parsing still temporarily co-own LR construction and
execution. Convergence is measured behaviorally before either implementation is
declared canonical.

The shared corpus supplies engine-neutral productions, precedence levels, and
normalized token kinds. LR-Parsing's `lr-conformance` executable constructs a
LALR parser from that model and emits one normalized status for every case. The
pinned integration workflow compares those observations with the Workbench
expectations through `Validation/Ecosystem/LRConvergence.json`.

Agreement is closed by default: a missing case, duplicate observation,
unexpected status, undocumented mismatch, or obsolete exception fails the
gate. The current corpus has one reviewed boundary. Workbench's source-oriented
parser accepts the JSON trailing-comma fixture with recovery; LR-Parsing's
normalized `TokenStream` entry point is strict and rejects it. This difference
does not select a canonical LR owner. It makes the remaining recovery API gap
explicit and prevents either implementation from drifting silently.

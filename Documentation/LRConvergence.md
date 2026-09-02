# LR convergence

LR-Parsing owns LR construction and deterministic table execution.
Grammar-Workbench converts its source-oriented grammar model into the neutral
LR specification, then adapts the resulting automaton and persisted-table
runtime output into Workbench artifacts. It no longer contains an independent
LR constructor or shift/reduce runtime.

The shared corpus supplies engine-neutral productions, precedence levels, and
normalized token kinds. LR-Parsing's `lr-conformance` executable constructs a
LALR parser from that model and emits one normalized status for every case. The
pinned integration workflow compares those observations with the Workbench
expectations through `Validation/Ecosystem/LRConvergence.json`.

Agreement is closed by default: a missing case, duplicate observation,
unexpected status, undocumented mismatch, or obsolete exception fails the
gate. LR-Parsing's generic `TokenStream` entry point now supports structured
recovery, so the former JSON trailing-comma exception is removed.

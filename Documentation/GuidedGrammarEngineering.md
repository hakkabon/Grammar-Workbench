# Guided grammar engineering

The Guide workspace is the default entry point to Grammar Workbench. It organizes existing compiler evidence around user goals rather than parser subsystems. Automata, parse tables, replay, and generalized parsing remain available through **Expert tools**.

## Grammar health

`GrammarGuidanceEngine` translates compilation diagnostics, parser decisions, the current sample, and recorded test results into a stable `GrammarGuidanceReport`. Reports contain a bounded health score, explicit counts, a plain-language headline, prioritized findings, concrete next actions, and source ranges for editor navigation.

The score is an orientation aid, not a proof of grammar quality. The underlying diagnostics, decisions, parse results, and test reports remain authoritative and are always reachable from a recommendation.

## Task-oriented workspace

The native app opens on Guide and presents six common workflows: write and validate, try an input, resolve ambiguity, protect behavior with tests, compare algorithms, and generate a parser. The first recommended action is shown separately so a new user does not need to choose an LR artifact before understanding the problem.

Turning on **Expert tools** adds the Automaton, Table, and Research workspaces. Turning it off while one of those views is selected returns to Guide; it never removes or changes the underlying artifacts.

## Safe change previews

Workbench-notation grammars can preview removal of duplicate, unreachable, and non-start unproductive production lines. Phase 8 delegates these edits to the shared transformation library. A preview:

1. derives proposed source without changing the document;
2. compiles it through the normal public API;
3. computes the artifact diff;
4. compares every document sample plus a bounded generated corpus with generalized recognition;
5. reruns the saved grammar tests;
6. enables Apply only when the result compiles, no accepted sample regresses, and all recorded tests pass.

Changed but non-regressing sample outcomes remain visible. Applying a preview edits the document through the ordinary source binding, preserving the existing autosave, undo ownership, debounced construction, and artifact-diff path.

The public guidance and preview models are UI-neutral and `Sendable`, allowing hosts to build a different guided interface without importing SwiftUI.

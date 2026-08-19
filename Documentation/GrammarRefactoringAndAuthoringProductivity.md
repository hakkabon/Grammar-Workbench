# Grammar refactoring and authoring productivity

Phase 31 adds a reusable, preview-first refactoring contract alongside the
existing cleanup transformations. The first supported refactoring is a
notation-preserving rename for nonterminals and declared token names.

## Safe rename plans

`GrammarRefactoring.planRename(from:to:in:)` creates an immutable Codable plan
containing the source fingerprint, notation, every UTF-16 edit, affected lines,
and a reason for each occurrence. It rejects invalid identifiers, unknown
symbols, and collisions between token and nonterminal declarations.

The scanner recognizes grammar identifiers but deliberately skips comments,
quoted terminal literals, and lexer regular expressions. It therefore updates
declarations, production references, `%start`, precedence directives, and
token references without changing the language-bearing contents of literals or
patterns. The same mechanism operates directly on Workbench and native EBNF
source; EBNF is not lowered and re-rendered during the edit.

`GrammarRefactoring.apply` rejects a stale fingerprint, overlapping edits, and
edits whose original text no longer matches. Plans can safely cross process
boundaries or wait for explicit user approval before application.

## Validated previews

`GrammarRefactoring.execute` recompiles the proposed source and publishes:

- the proposed source and new compilation;
- the artifact diff;
- bounded before/after language-membership comparison;
- saved-test results before and after the edit.

`isSafeToApply` requires compilation, corpus agreement, and passing post-edit
tests. `GrammarProjectWorkspace.previewGrammarRename` automatically contributes
all project sources and saved tests to that validation.

Automation can run the same guarded workflow with:

```sh
grammar-workbench grammar-refactor rename Grammar.grammar OldName NewName Output.grammar
```

The command writes nothing unless the validated preview is safe. The existing
LSP rename remains available for interactive editor edits; the new library and
CLI contracts serve previews, project tooling, CI, and hosts that need explicit
evidence before changing source.

## Scope

Phase 31 intentionally establishes the safe refactoring substrate with rename
before adding structural rewrites such as extract-rule or inline-rule. Those
operations need alternative-level source ranges and comment ownership rules to
avoid converting a convenient authoring action into a lossy formatter.

# Integrated language-project experience

Phase 13 brings grammar, source, test, semantic, transformation, and generation
facilities into one project-oriented workflow. It does not change the
`.grammarworkbench` document schema: an existing document is presented as a
small language project, while a `GrammarProjectAnalysis` uses the same public
experience model for multiple source files.

## Project workspace

The native **Project** workspace provides five stable destinations:

- the grammar and its productions;
- example or project source documents;
- regression tests;
- semantic models and workspace symbols; and
- generated parsers and interchange artifacts.

Each destination reports a count and routes to the relevant workbench. The
dedicated **Semantics** view connects production identities, generated action
starters, and the incremental sample index. The **Generate** view collects output
choices and explains why output is unavailable when errors or unresolved parser
decisions remain.

## Unified problems and background work

`GrammarProjectExperienceSnapshot` combines grammar diagnostics, unresolved
parser decisions, lexical and syntax diagnostics, failed tests, and semantic
workspace diagnostics. Problems retain their document, path, source range, area,
severity, and task destination. The same immutable snapshot can drive SwiftUI,
another GUI, an IDE, or automation.

Longer operations use `GrammarProjectOperation`. The native view reports grammar
construction, algorithm comparison, ambiguity exploration, and bootstrap work
without blocking navigation.

## Compatibility boundary

`GrammarProjectExperience.snapshot` has overloads for both a native document's
compilation/samples/tests and a complete `GrammarProjectAnalysis` with optional
semantic workspace services. This keeps presentation decisions outside parser
and project actors and establishes a bridge toward stateful SDK sessions.

Graph visualization remains behind the existing artifact views. A shared layout
abstraction should be introduced with the future layout-engine integration, once
its behavior and coordinate contracts can be validated.

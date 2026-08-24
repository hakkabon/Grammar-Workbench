# Collaborative exploration

Phase 38 connects Phase 35 rule-centred exploration to the hosted workspace
model. Participants can share where they are looking and leave review
bookmarks without turning derived compiler output into collaborative source.

## Shared exploration model

`GrammarCollaborativeExplorer` is a transport-neutral actor composed with any
`GrammarCollaborationHosting` implementation. For each workspace document it
maintains participant focus, named rule bookmarks, a bounded ordered event
stream, and bounded operation replay for idempotent retries.

Every read obtains the authoritative document from the collaboration host and
rebuilds `GrammarExplorationSnapshot`. Grammar analysis, railroad diagrams, and
other derived artifacts are not copied into shared mutable state. The returned
snapshot records the exact document revision used.

Focus and bookmark mutations use optimistic document revision checks. A client
that races an edit receives `stale-exploration-document` and must refresh before
retrying. Only current workspace participants may explore or mutate shared
state, and selected rules must exist in the compiled grammar.

## Change-aware bookmarks

Bookmarks are retained when grammar text changes. Their projection reports
whether the referenced rule still exists and whether the bookmark was created
against the current revision. This preserves review context while allowing
clients to identify material that needs reconciliation. A focus whose rule was
removed falls back to the grammar start rule.

## Tooling protocol

The stateful SDK and JSON-lines service expose `collaborationExplore`,
`collaborationExploreSelect`, `collaborationBookmarkUpsert`,
`collaborationBookmarkRemove`, and `collaborationExplorationEvents`.
Requests reuse the existing workspace, document, participant, operation,
revision, and event-sequence fields. `selectedRule`, `bookmarkID`, and
`bookmarkNote` carry exploration-specific intent.

## Deliberate limits

This phase shares navigation and review intent, not cursor ranges, parser
animations, diagram viewport coordinates, chat, or arbitrary binary artifacts.
Exploration state currently follows the service-process lifetime; Phase 37
durability continues to cover authoritative documents and editing history. A
future archive revision can persist exploration intent after retention and
privacy policy are defined, without persisting derived analysis.

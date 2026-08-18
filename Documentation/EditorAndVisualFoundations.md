# Editor and visual foundations

Phase 21 establishes a reliable native editing surface before further visual or
parser features are added. The grammar source is a permanent sibling of the
task workspace and inspector in an `HSplitView`. It is no longer hosted in an
adaptive navigation sidebar, so macOS cannot present it as an overlay obscuring
the other columns—or place another column over the source.

## Editor containment

`GrammarSourceEditor` remains an AppKit `NSTextView` hosted by SwiftUI. An
explicit `GrammarEditorContainerView` positions the 42-point line-number gutter
and the editor scroll view as non-overlapping siblings; it does not rely on
`NSScrollView`'s ruler placement, which can extend outside a SwiftUI-assigned
frame. The dedicated `GrammarEditorScrollView` handles the period before SwiftUI
assigns a final size and maintains a non-zero document view at least as large as
the visible viewport. Long unwrapped grammar lines may grow the document width
and use the horizontal scroller; they never increase the enclosing pane width.

Model-driven updates preserve a valid insertion or selection range and the
visible position. Ordinary edits continue through the native text system, with
undo, find, completion, diagnostic decoration, line numbers, horizontal and
vertical scrolling, and automatic quote and dash replacement disabled for
grammar source.

Plain UTF-8 text—including `.txt` and `.grammar` files—is opened as Workbench
notation. The `.ebnf` content type selects EBNF notation. Native
`.grammarworkbench` documents continue to retain grammar source, notation,
algorithm, examples, and tests.

## Visual contract

`WorkbenchVisualFoundation` centralizes the minimum and preferred dimensions of
the three primary panes. The minimum application width accommodates all three
minimum pane widths simultaneously. Each pane has a stable accessibility
identifier, and the native text view exposes a stable accessibility label and
identifier independently of its SwiftUI host.

The release policy records minimum editor viewport and workspace dimensions.
Regression tests cover zero-size construction, viewport growth, long-line
containment, document import, minimum pane composition, selection-driven source
navigation, and debounced edit regeneration.

This phase deliberately provides the structural foundation for later visual
polish. Screenshot baselines and human usability review belong in subsequent
application-design iterations; they do not replace these deterministic layout
and interaction invariants.

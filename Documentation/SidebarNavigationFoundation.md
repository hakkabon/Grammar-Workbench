# Sidebar navigation foundation

The native macOS application now uses a sectioned, selectable sidebar instead
of a segmented workspace picker and an Expert-mode toggle. The hierarchy is:

- **Start:** Guide and Project;
- **Grammar:** Analysis, Semantics, Compare, Explore, Diagram & Console, Decisions;
- **Run & Deliver:** Sample, Tests, Generate;
- **Expert:** Automaton, Table, Bootstrap, Research, Visuals.

Expert workspaces are always discoverable. Collapsing the navigation sidebar
does not change the selected workspace. The source editor remains a permanent
resizable pane. Artifact detail is requested contextually rather than occupying
a permanent inspector pane: selecting an Automaton state opens its LR items,
decisions, and transitions in a popover; table cells, productions, decisions,
and replay links use the same contextual presentation. This leaves navigation,
source, and workspace as the three horizontal regions and fits comfortably
inside the retained 1120-point minimum.

The Sample workspace explicitly fills and top-aligns both halves of its split
view. Trace and Animated Graph therefore use the same stable geometry, and the
parse-tree region retains a minimum visible height instead of collapsing when
the trace has little intrinsic content.

`GrammarWorkbenchDestination` and `GrammarWorkbenchNavigationSection` contain
the hierarchy, titles, and symbol names without importing SwiftUI. A future
iPad application shell can therefore reuse the same navigation contract while
choosing an adaptive split-view presentation.

The implementation deliberately retains the macOS 14 deployment target and
uses `List(selection:)`. SwiftUI's `Tab`, `TabSection`, and
`.sidebarAdaptable` require macOS 15. Moving to that API can be evaluated later
without changing destination identity or product organization.

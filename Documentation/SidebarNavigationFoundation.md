# Sidebar navigation foundation

The native macOS application now uses a sectioned, selectable sidebar instead
of a segmented workspace picker and an Expert-mode toggle. The hierarchy is:

- **Start:** Guide and Project;
- **Grammar:** Analysis, Semantics, Compare, Explore, Diagram & REPL, Decisions;
- **Run & Deliver:** Sample, Tests, Generate;
- **Expert:** Automaton, Table, Bootstrap, Research, Visuals.

Expert workspaces are always discoverable. Collapsing the navigation sidebar
does not change the selected workspace. Navigation and inspector visibility are
controlled independently from the toolbar, while the source editor remains a
permanent resizable pane. The 1120-point three-pane minimum is retained; the
expanded four-region arrangement naturally requests additional width.

`GrammarWorkbenchDestination` and `GrammarWorkbenchNavigationSection` contain
the hierarchy, titles, and symbol names without importing SwiftUI. A future
iPad application shell can therefore reuse the same navigation contract while
choosing an adaptive split-view presentation.

The implementation deliberately retains the macOS 14 deployment target and
uses `List(selection:)`. SwiftUI's `Tab`, `TabSection`, and
`.sidebarAdaptable` require macOS 15. Moving to that API can be evaluated later
without changing destination identity or product organization.

# Large-iPad adaptive workbench

This experimental platform increment establishes an installable iPadOS 17 host
and a touch-first subset of Grammar Workbench. The grammar engine, document
format, DiagramKit adapter, test runner, and Workbench parse console remain shared with the
macOS product; the iPad interface does not introduce alternate implementations.

## Included pilot workflows

- Open, edit, and autosave `.gwb` Workbench documents and `.bnf`, `.ebnf`,
  `.grammar`, `.y`, `.yacc`, `.yy`, or plain-text grammar sources. Legacy
  `.grammarworkbench` documents remain accepted.
- Show the persisted or import-detected notation beside the filename.
- Switch among Guide, Analysis, Sample, Tests, and Visuals with `NavigationSplitView`.
- Keep source and workspace side by side at comfortable large-iPad widths.
- Open source in a sheet at narrow Split View widths; Command-E provides the
  same action for an external keyboard.
- Inspect diagnostics, grammar and LR summaries, productions, parse outcomes,
  recovered trees, and saved-test results.
- Render live railroad diagrams through Grammar-DiagramKit and use the shared
  parse console below the diagram.
- Resize naturally in portrait, landscape, Split View, and Stage Manager.

Generation remains a prototype because iPad export needs a product-level Files
and share-sheet workflow. Dense Automaton, Table, Bootstrap, Research, and hosted
administration interfaces remain deliberately deferred. Their engine APIs are
available, but presenting desktop density unchanged on a touch device would not
constitute a usable port.

## Running the pilot

Open
`Platforms/GrammarWorkbenchTabletApp/GrammarWorkbenchTabletApp.xcodeproj` in
Xcode. Select the **GrammarWorkbenchTabletApp** scheme and an iPad simulator.
For a physical iPad, select a Development Team for the app target, choose the
connected iPad, and run. The host is restricted to device family 2 and therefore
does not advertise an unsupported iPhone experience.

`.gwb` is the preferred stateful format because it preserves source, notation,
algorithm, samples, and tests. Source-only documents retain their grammar text
instead of being silently rewritten as Workbench JSON. WSN is not advertised
until a real WSN front end is available.

The command-line simulator build gate is:

```sh
xcodebuild \
  -project Platforms/GrammarWorkbenchTabletApp/GrammarWorkbenchTabletApp.xcodeproj \
  -scheme GrammarWorkbenchTabletApp \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

`GrammarWorkbenchTabletFoundation` is the machine-readable scope contract used
by tests and future release checks. A feature marked `deferred` must not appear
as a nonfunctional tablet control.

## Evaluation checklist

Visual verification should cover an 11-inch or 13-inch iPad in portrait and
landscape, half-width Split View, Stage Manager resizing, light and dark mode,
touch selection in diagrams, software-keyboard avoidance, external-keyboard
editing, and opening/saving documents through Files. Performance evaluation
should include a small grammar and at least one production-corpus grammar.

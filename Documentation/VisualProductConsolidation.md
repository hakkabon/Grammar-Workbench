# Visual product consolidation

Phase 26 turns the Workbench's separate editor and graph capabilities into one visual product system. It is deliberately a consolidation milestone: the parser, geometry, and interaction engines remain unchanged, while their presentation, preferences, accessibility, and validation now share a stable contract.

## Product gallery

The expert **Visuals** workspace is the reference surface for visual development. It displays the semantic palette, loading/empty/error/success states, accessibility audit results, and the current parser timeline using the same renderer as the Parser workspace. Changes to a color, control, or graph state can therefore be reviewed together instead of one screen at a time.

The gallery complements ordinary feature tests. It is intended for manual light, dark, high-contrast, reduced-motion, Dynamic Type, and keyboard review before a release.

## Preferences and design tokens

`GrammarVisualPreferences` is a portable, Codable description of appearance, motion, minimap, edge-label, and transition-duration choices. App settings persist these preferences and both automaton and parser visualizations consume them.

`GrammarVisualDesignSystem` owns semantic colors and graph CSS. Web views no longer define unrelated color schemes. System appearance follows the browser's dark-mode media query; explicit light, dark, and high-contrast choices remain deterministic. Focus rings and reduced-motion behavior are part of the generated CSS rather than optional per-view additions.

## Automated visual evidence

`GrammarVisualProductAuditor` checks machine-detectable presentation defects, including inaccessible node labels and parser steps without action descriptions. It does not claim to replace VoiceOver or visual review.

`GrammarVisualSnapshotBuilder` creates a small deterministic manifest for rendered SVG and HTML. Each entry records its surface, byte count, dimensions where applicable, and a stable fingerprint. CI and downstream applications can compare manifests without adopting a pixel-rendering dependency; intentional output changes can be reviewed explicitly.

```swift
let preferences = GrammarVisualPreferences(
    appearance: .system,
    motion: .reduced,
    showsMinimap: true
)
let html = try GrammarParserVisualizationHTMLRenderer.render(
    timeline,
    preferences: preferences
)
let audit = GrammarVisualProductAuditor.audit(
    graph: timeline.graph,
    timeline: timeline
)
let manifest = GrammarVisualSnapshotBuilder.make(parserHTML: html)
```

These models stay in the cross-platform library. SwiftUI supplies the gallery and settings, while Linux and WASM-oriented hosts can use the same tokens, preferences, audit reports, and manifests.

## Release review

For a visual release candidate:

1. Open **Visuals** and inspect every product state in system, light, dark, and high-contrast modes.
2. Enable reduced motion, hide the minimap and edge labels, and confirm every preview responds immediately.
3. Navigate the parser controls by keyboard and verify the live action announcement with VoiceOver.
4. Run the full test suite and compare visual snapshot manifests with the reviewed baseline.
5. Treat an audit error as a release blocker; review warnings in context.


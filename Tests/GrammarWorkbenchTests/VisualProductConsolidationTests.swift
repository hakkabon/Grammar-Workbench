import Foundation
@testable import GrammarWorkbench
import Testing

private let visualProductGrammar = #"""
%token ID /[a-z]+/
%start S
S : ID ;
"""#

private func visualProductTimeline() throws -> GrammarParserVisualizationTimeline {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: visualProductGrammar))
    return try GrammarParserVisualizationBuilder.make(
        artifact: #require(compilation.artifact), parse: compilation.parse("name")
    )
}

@Test func visualPreferencesAreBoundedCodableAndRespectReducedMotion() throws {
    let preferences = GrammarVisualPreferences(
        appearance: .dark, motion: .reduced, showsMinimap: false,
        showsEdgeLabels: false, animationDurationMilliseconds: 9_000
    )
    #expect(preferences.animationDurationMilliseconds == 0)
    #expect(try JSONDecoder().decode(
        GrammarVisualPreferences.self, from: JSONEncoder().encode(preferences)
    ) == preferences)

    let standard = GrammarVisualPreferences(animationDurationMilliseconds: 9_000)
    #expect(standard.animationDurationMilliseconds == 1_000)
}

@Test func sharedVisualCSSSupportsSystemDarkContrastFocusAndMotion() {
    let system = GrammarVisualDesignSystem.graphCSS()
    #expect(system.contains("prefers-color-scheme:dark"))
    #expect(system.contains("focus-visible"))
    #expect(system.contains("prefers-reduced-motion:reduce"))
    #expect(system.contains("--gw-accent"))

    let contrast = GrammarVisualDesignSystem.palette(for: .highContrast)
    #expect(contrast.canvas == "#ffffff")
    #expect(contrast.text == "#000000")
}

@Test func visualAuditFindsAccessibilityProblemsAndAcceptsProductGraph() throws {
    let invalid = GrammarGraph(
        id: "invalid", title: "Invalid",
        nodes: [.init(id: "empty", label: "  ")],
        edges: [.init(id: "loop", source: "empty", target: "empty")]
    )
    let invalidReport = GrammarVisualProductAuditor.audit(graph: invalid)
    #expect(!invalidReport.passes)
    #expect(invalidReport.errorCount == 1)
    #expect(invalidReport.warningCount == 1)

    let timeline = try visualProductTimeline()
    let report = GrammarVisualProductAuditor.audit(graph: timeline.graph, timeline: timeline)
    #expect(report.passes)
    #expect(report.warningCount == 0)
}

@Test func visualSnapshotManifestsAreStableAndDetectOutputChanges() throws {
    let first = GrammarVisualSnapshotBuilder.make(
        graphSVG: "<svg>one</svg>", parserHTML: "<html>one</html>",
        graphSize: (width: 640, height: 480)
    )
    let repeated = GrammarVisualSnapshotBuilder.make(
        graphSVG: "<svg>one</svg>", parserHTML: "<html>one</html>",
        graphSize: (width: 640, height: 480)
    )
    let changed = GrammarVisualSnapshotBuilder.make(graphSVG: "<svg>two</svg>")
    #expect(first == repeated)
    #expect(first.entries.first { $0.id == "graph-svg" }?.fingerprint != changed.entries[0].fingerprint)
    #expect(try JSONDecoder().decode(
        GrammarVisualSnapshotManifest.self, from: JSONEncoder().encode(first)
    ) == first)
}

@Test func parserVisualizationAppliesProductPreferencesAndAccessibilityLabels() throws {
    let html = try GrammarParserVisualizationHTMLRenderer.render(
        visualProductTimeline(),
        preferences: .init(
            appearance: .dark, motion: .reduced,
            showsMinimap: false, showsEdgeLabels: false
        )
    )
    #expect(html.contains("aria-label='Parser visualization controls'"))
    #expect(html.contains("aria-live='polite'"))
    #expect(html.contains("#11151c"))
    #expect(html.contains("#minimap{position:fixed"))
    #expect(html.contains("display:none;"))
    #expect(html.contains(".edge-label{display:none}"))
}

#if os(macOS)
import SwiftUI
import WebKit

public struct GrammarParserVisualizationView: NSViewRepresentable {
    public let timeline: GrammarParserVisualizationTimeline
    @AppStorage("visualAppearance") private var visualAppearance = GrammarVisualAppearance.system.rawValue
    @AppStorage("reduceGraphMotion") private var reduceGraphMotion = false
    @AppStorage("showGraphMinimap") private var showGraphMinimap = true
    @AppStorage("showGraphEdgeLabels") private var showGraphEdgeLabels = true

    public init(timeline: GrammarParserVisualizationTimeline) { self.timeline = timeline }

    public func makeCoordinator() -> Coordinator { Coordinator() }
    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }
    public func updateNSView(_ view: WKWebView, context: Context) {
        let preferences = GrammarVisualPreferences(
            appearance: GrammarVisualAppearance(rawValue: visualAppearance) ?? .system,
            motion: reduceGraphMotion ? .reduced : .standard,
            showsMinimap: showGraphMinimap, showsEdgeLabels: showGraphEdgeLabels
        )
        guard let html = try? GrammarParserVisualizationHTMLRenderer.render(
            timeline, preferences: preferences
        ),
              context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        view.loadHTMLString(html, baseURL: nil)
    }

    public final class Coordinator {
        fileprivate var lastHTML: String?
        public init() {}
    }
}
#endif

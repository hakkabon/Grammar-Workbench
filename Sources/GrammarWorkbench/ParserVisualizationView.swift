#if os(macOS)
import SwiftUI
import WebKit

public struct GrammarParserVisualizationView: NSViewRepresentable {
    public let timeline: GrammarParserVisualizationTimeline

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
        guard let html = try? GrammarParserVisualizationHTMLRenderer.render(timeline),
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

import SwiftUI
import WebKit

enum AutomatonSVG {
    static func render(_ artifact: GrammarArtifact, selected: StateID?) -> String {
        let width = 780
        let columns = 3
        let cardWidth = 220
        let cardHeight = 112
        let gapX = 35
        let gapY = 46
        let positions = Dictionary(uniqueKeysWithValues: artifact.states.enumerated().map { index, state in
            (state.id, CGPoint(x: 30 + (index % columns) * (cardWidth + gapX), y: 30 + (index / columns) * (cardHeight + gapY)))
        })
        let height = max(280, 70 + ((artifact.states.count + columns - 1) / columns) * (cardHeight + gapY))
        let edges = artifact.transitions.compactMap { edge -> String? in
            guard let start = positions[edge.from], let end = positions[edge.to] else { return nil }
            let x1 = Int(start.x) + cardWidth / 2, y1 = Int(start.y) + cardHeight / 2
            let x2 = Int(end.x) + cardWidth / 2, y2 = Int(end.y) + cardHeight / 2
            return "<path d='M \(x1) \(y1) L \(x2) \(y2)'/><text x='\((x1+x2)/2 + 4)' y='\((y1+y2)/2 - 4)'>\(escape(edge.symbol))</text>"
        }.joined()
        let nodes = artifact.states.compactMap { state -> String? in
            guard let point = positions[state.id] else { return nil }
            let x = Int(point.x), y = Int(point.y)
            let lines = state.items.prefix(4).enumerated().map { offset, item in
                "<text class='item' x='\(x + 12)' y='\(y + 43 + offset * 16)'>\(escape(item.text))</text>"
            }.joined()
            let selectedClass = state.id == selected ? " selected" : ""
            return "<g class='node\(selectedClass)' onclick='selectState(\(state.id.rawValue))'><rect x='\(x)' y='\(y)' width='\(cardWidth)' height='\(cardHeight)' rx='11'/><text class='title' x='\(x + 12)' y='\(y + 23)'>\(state.id)</text>\(lines)</g>"
        }.joined()
        return """
        <svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 \(width) \(height)' role='img' aria-label='LR automaton'>
        <defs><marker id='arrow' viewBox='0 0 10 10' refX='9' refY='5' markerWidth='6' markerHeight='6' orient='auto-start-reverse'><path d='M 0 0 L 10 5 L 0 10 z' class='arrow'/></marker></defs>
        <style>path{stroke:#8792a5;stroke-width:1.6;fill:none;marker-end:url(#arrow)}.arrow{fill:#8792a5;stroke:none}.node{cursor:pointer}.node rect{fill:#f5f7fb;stroke:#7b879b;stroke-width:1.5}.node:hover rect,.selected rect{fill:#d9eaff;stroke:#1671d9;stroke-width:3}.title{font:700 15px system-ui;fill:#172033}.item{font:11px ui-monospace,monospace;fill:#303949}text{font:12px system-ui;fill:#4b5565}</style>
        \(edges)\(nodes)</svg>
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "'", with: "&apos;")
    }
}

struct AutomatonView: NSViewRepresentable {
    let artifact: GrammarArtifact
    let selection: ArtifactIdentity?
    let onSelect: (StateID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "stateSelection")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onSelect = onSelect
        let svg = AutomatonSVG.render(artifact, selected: selectedState)
        let html = "<html><head><meta name='viewport' content='width=device-width'><style>body{margin:0}svg{width:100%;height:auto;min-height:100vh}</style></head><body>\(svg)<script>function selectState(id){window.webkit.messageHandlers.stateSelection.postMessage(id)}</script></body></html>"
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        view.loadHTMLString(html, baseURL: nil)
    }

    private var selectedState: StateID? {
        switch selection {
        case .state(let id): id
        case .cell(let id): id.state
        case .decision(let id): artifact.decision(id)?.cell.state
        default: nil
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onSelect: (StateID) -> Void
        var lastHTML: String?
        init(onSelect: @escaping (StateID) -> Void) { self.onSelect = onSelect }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let value = message.body as? Int { onSelect(StateID(rawValue: value)) }
        }
    }
}

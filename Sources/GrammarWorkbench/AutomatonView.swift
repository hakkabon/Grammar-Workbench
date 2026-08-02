import SwiftUI
import WebKit

enum AutomatonDetail: String, CaseIterable, Identifiable {
    case automatic = "Auto"
    case full = "Items"
    case compact = "Compact"
    var id: Self { self }
}

struct AutomatonLayout {
    struct Node {
        let id: StateID
        let frame: CGRect
        let layer: Int
    }

    struct Edge {
        let transition: Transition
        let path: String
        let labelPoint: CGPoint
    }

    let nodes: [Node]
    let edges: [Edge]
    let width: CGFloat
    let height: CGFloat

    func node(_ id: StateID) -> Node? { nodes.first { $0.id == id } }
}

enum AutomatonLayoutEngine {
    static func layout(
        states: [AutomatonState],
        transitions: [Transition],
        compact: Bool
    ) -> AutomatonLayout {
        guard !states.isEmpty else {
            return AutomatonLayout(nodes: [], edges: [], width: 640, height: 360)
        }
        let stateIDs = Set(states.map(\.id))
        let validTransitions = transitions.filter {
            stateIDs.contains($0.from) && stateIDs.contains($0.to)
        }
        let outgoing = Dictionary(grouping: validTransitions, by: \.from)
        let conventionalRoot = StateID(rawValue: 0)
        let root = stateIDs.contains(conventionalRoot)
            ? conventionalRoot
            : states.min(by: { $0.id.rawValue < $1.id.rawValue })!.id
        var layers: [StateID: Int] = [root: 0]
        var queue = [root]
        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            for transition in outgoing[current, default: []].sorted(by: transitionOrder) {
                if layers[transition.to] == nil {
                    layers[transition.to] = layers[current, default: 0] + 1
                    queue.append(transition.to)
                }
            }
        }
        var nextLayer = (layers.values.max() ?? -1) + 1
        for state in states.sorted(by: { $0.id.rawValue < $1.id.rawValue }) where layers[state.id] == nil {
            layers[state.id] = nextLayer
            nextLayer += 1
        }

        var grouped = Dictionary(grouping: states.map(\.id), by: { layers[$0, default: 0] })
        for key in grouped.keys {
            grouped[key]?.sort { $0.rawValue < $1.rawValue }
        }
        let incoming = Dictionary(grouping: validTransitions, by: \.to)
        for layer in 1...(grouped.keys.max() ?? 0) {
            let previousPositions = Dictionary(uniqueKeysWithValues:
                grouped[layer - 1, default: []].enumerated().map { ($0.element, Double($0.offset)) }
            )
            grouped[layer]?.sort { lhs, rhs in
                let left = barycenter(lhs, incoming: incoming, positions: previousPositions)
                let right = barycenter(rhs, incoming: incoming, positions: previousPositions)
                return left == right ? lhs.rawValue < rhs.rawValue : left < right
            }
        }

        let nodeWidth: CGFloat = compact ? 116 : 250
        let nodeHeight: CGFloat = compact ? 50 : 112
        let horizontalGap: CGFloat = compact ? 80 : 110
        let verticalGap: CGFloat = compact ? 34 : 46
        let margin: CGFloat = 52
        var nodes: [AutomatonLayout.Node] = []
        for layer in grouped.keys.sorted() {
            for (row, id) in grouped[layer, default: []].enumerated() {
                nodes.append(.init(
                    id: id,
                    frame: CGRect(
                        x: margin + CGFloat(layer) * (nodeWidth + horizontalGap),
                        y: margin + CGFloat(row) * (nodeHeight + verticalGap),
                        width: nodeWidth,
                        height: nodeHeight
                    ),
                    layer: layer
                ))
            }
        }
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let maxRows = grouped.values.map(\.count).max() ?? 1
        let width = max(640, margin * 2 + CGFloat((grouped.keys.max() ?? 0) + 1) * nodeWidth + CGFloat(grouped.keys.max() ?? 0) * horizontalGap)
        let height = max(360, margin * 2 + CGFloat(maxRows) * nodeHeight + CGFloat(max(0, maxRows - 1)) * verticalGap)
        let topRouteBase = max(16, margin - 20)
        let edges = validTransitions.enumerated().compactMap { index, transition -> AutomatonLayout.Edge? in
            guard let source = nodeMap[transition.from], let target = nodeMap[transition.to] else { return nil }
            let start = CGPoint(x: source.frame.maxX, y: source.frame.midY)
            let end = CGPoint(x: target.frame.minX, y: target.frame.midY)
            let path: String
            let label: CGPoint
            if transition.from == transition.to {
                let loopTop = source.frame.minY - 26
                path = "M \(number(source.frame.midX - 12)) \(number(source.frame.minY)) C \(number(source.frame.midX - 34)) \(number(loopTop)) \(number(source.frame.midX + 34)) \(number(loopTop)) \(number(source.frame.midX + 12)) \(number(source.frame.minY))"
                label = CGPoint(x: source.frame.midX, y: loopTop - 4)
            } else if target.layer > source.layer {
                let middleX = (start.x + end.x) / 2
                path = "M \(number(start.x)) \(number(start.y)) C \(number(middleX)) \(number(start.y)) \(number(middleX)) \(number(end.y)) \(number(end.x)) \(number(end.y))"
                label = CGPoint(x: middleX, y: (start.y + end.y) / 2 - 7)
            } else {
                let routeY = topRouteBase - CGFloat(index % 4) * 9
                path = "M \(number(start.x)) \(number(start.y)) L \(number(start.x + 24)) \(number(start.y)) L \(number(start.x + 24)) \(number(routeY)) L \(number(end.x - 24)) \(number(routeY)) L \(number(end.x - 24)) \(number(end.y)) L \(number(end.x)) \(number(end.y))"
                label = CGPoint(x: (start.x + end.x) / 2, y: routeY - 6)
            }
            return .init(transition: transition, path: path, labelPoint: label)
        }
        return AutomatonLayout(nodes: nodes, edges: edges, width: width, height: height)
    }

    private static func barycenter(
        _ state: StateID,
        incoming: [StateID: [Transition]],
        positions: [StateID: Double]
    ) -> Double {
        let values = incoming[state, default: []].compactMap { positions[$0.from] }
        return values.isEmpty ? Double(state.rawValue) : values.reduce(0, +) / Double(values.count)
    }

    private static func transitionOrder(_ lhs: Transition, _ rhs: Transition) -> Bool {
        lhs.symbol == rhs.symbol ? lhs.to.rawValue < rhs.to.rawValue : lhs.symbol < rhs.symbol
    }

    private static func number(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}

enum AutomatonSVG {
    static func render(
        _ artifact: GrammarArtifact,
        selected: StateID?,
        visibleStates: Set<StateID>? = nil,
        detail: AutomatonDetail = .full,
        interactive: Bool = false
    ) -> String {
        let allowed = visibleStates ?? Set(artifact.states.map(\.id))
        let states = artifact.states.filter { allowed.contains($0.id) }
        let transitions = artifact.transitions.filter {
            allowed.contains($0.from) && allowed.contains($0.to)
        }
        let compact = detail == .compact || (detail == .automatic && states.count > 70)
        let layout = AutomatonLayoutEngine.layout(states: states, transitions: transitions, compact: compact)
        let nodeMap = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0) })
        let edges = layout.edges.map { edge in
            """
            <g class='edge'><path d='\(edge.path)'/><rect class='edge-label-bg' x='\(edge.labelPoint.x - 15)' y='\(edge.labelPoint.y - 11)' width='30' height='16' rx='4'/><text class='edge-label' x='\(edge.labelPoint.x)' y='\(edge.labelPoint.y)'>\(escape(edge.transition.symbol))</text></g>
            """
        }.joined()
        let nodes = states.compactMap { state -> String? in
            guard let node = nodeMap[state.id] else { return nil }
            let frame = node.frame
            let summary = artifact.decisionSummary(for: state.id)
            let dispositionClass = summary.map { " decision-\($0.disposition.rawValue)" } ?? ""
            let decisionBadge = summary.map {
                "<g class='decision-badge \($0.disposition.rawValue)'><circle cx='\(frame.maxX - 16)' cy='\(frame.minY + 17)' r='11'/><text x='\(frame.maxX - 16)' y='\(frame.minY + 21)'>\($0.decisions.count)</text></g>"
            } ?? ""
            let accessibility = summary.map { ", \($0.disposition.label), \($0.decisions.count) decision\($0.decisions.count == 1 ? "" : "s")" } ?? ""
            let lines: String
            if compact {
                lines = "<text class='count' x='\(frame.midX)' y='\(frame.minY + 34)'>\(state.items.count) items</text>"
            } else {
                lines = state.items.prefix(4).enumerated().map { offset, item in
                    "<text class='item' x='\(frame.minX + 12)' y='\(frame.minY + 43 + CGFloat(offset) * 16)'>\(escape(item.text))</text>"
                }.joined()
            }
            return """
            <g class='node\(compact ? " compact" : "")\(dispositionClass)\(state.id == selected ? " selected" : "")' data-state='\(state.id.rawValue)' role='button' aria-label='\(state.id)\(accessibility)' onclick='selectState(\(state.id.rawValue))'>
            <title>\(state.id)\(accessibility)</title>
            <rect x='\(frame.minX)' y='\(frame.minY)' width='\(frame.width)' height='\(frame.height)' rx='11'/>
            <text class='title' x='\(compact ? frame.midX : frame.minX + 12)' y='\(frame.minY + 23)'>\(state.id)</text>\(lines)\(decisionBadge)</g>
            """
        }.joined()
        let minimapNodes = layout.nodes.map {
            let disposition = artifact.decisionSummary(for: $0.id)?.disposition.rawValue
            return "<rect x='\($0.frame.minX)' y='\($0.frame.minY)' width='\($0.frame.width)' height='\($0.frame.height)' class='mini-node\(disposition.map { " mini-\($0)" } ?? "")\($0.id == selected ? " mini-selected" : "")'/>"
        }.joined()
        let controls = interactive ? """
        <div id='graph-controls'><button onclick='zoomBy(1.25)' aria-label='Zoom in'>＋</button><button onclick='zoomBy(.8)' aria-label='Zoom out'>−</button><button onclick='fitGraph()' aria-label='Fit graph'>Fit</button></div>
        <svg id='minimap' viewBox='0 0 \(layout.width) \(layout.height)' preserveAspectRatio='xMidYMid meet' onclick='fitGraph()'>\(minimapNodes)<rect id='mini-viewport'/></svg>
        """ : ""
        let svg = """
        <svg id='automaton' xmlns='http://www.w3.org/2000/svg' width='100%' height='100%' role='img' aria-label='LR automaton'>
        <defs><marker id='arrow' viewBox='0 0 10 10' refX='9' refY='5' markerWidth='6' markerHeight='6' orient='auto-start-reverse'><path d='M 0 0 L 10 5 L 0 10 z' class='arrow'/></marker></defs>
        <g id='viewport'><g id='edges'>\(edges)</g><g id='nodes'>\(nodes)</g></g></svg>
        """
        guard interactive else {
            return """
            <svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 \(layout.width) \(layout.height)' role='img' aria-label='LR automaton'>
            <defs><marker id='arrow' viewBox='0 0 10 10' refX='9' refY='5' markerWidth='6' markerHeight='6' orient='auto-start-reverse'><path d='M 0 0 L 10 5 L 0 10 z' class='arrow'/></marker></defs>
            <style>\(svgStyles)</style><g id='edges'>\(edges)</g><g id='nodes'>\(nodes)</g></svg>
            """
        }
        return "\(controls)\(svg)"
    }

    static var svgStyles: String {
        """
        .edge path{stroke:#8792a5;stroke-width:1.5;fill:none;marker-end:url(#arrow)}.arrow{fill:#8792a5;stroke:none}
        .edge-label-bg{fill:#fff;opacity:.88}.edge-label{text-anchor:middle;font:11px system-ui;fill:#4b5565}
        .node{cursor:pointer}.node rect{fill:#f5f7fb;stroke:#7b879b;stroke-width:1.5}.node.decision-resolved>rect{fill:#e7f1ff;stroke:#3478c9;stroke-width:2.5}.node.decision-unresolved>rect{fill:#ffe5e2;stroke:#c43b32;stroke-width:3}.node.decision-expected>rect{fill:#e3f6e9;stroke:#2d8a50;stroke-width:2.5}.node:hover>rect{filter:brightness(.96)}.node.selected>rect{stroke:#1266c5;stroke-width:4}
        .title{font:700 15px system-ui;fill:#172033}.node .count{font:11px system-ui;fill:#596579}.node.compact .title,.node.compact .count{text-anchor:middle}
        .item{font:11px ui-monospace,monospace;fill:#303949}.decision-badge circle{stroke:#fff;stroke-width:1.5}.decision-badge text{text-anchor:middle;font:700 11px system-ui;fill:#fff}.decision-badge.resolved circle{fill:#3478c9}.decision-badge.unresolved circle{fill:#c43b32}.decision-badge.expected circle{fill:#2d8a50}.mini-node{fill:#8391a8}.mini-resolved{fill:#3478c9}.mini-unresolved{fill:#c43b32}.mini-expected{fill:#2d8a50}.mini-selected{stroke:#1266c5;stroke-width:8;vector-effect:non-scaling-stroke}
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

struct AutomatonFilterResult {
    let visible: Set<StateID>
    let totalMatches: Int
    let truncated: Bool
}

enum DecisionStateFilter: String, CaseIterable, Identifiable {
    case all = "All states"
    case decisions = "All decisions"
    case unresolved = "Unresolved"
    case resolved = "Resolved"
    case expected = "Expected"
    var id: Self { self }
}

enum AutomatonFilter {
    static func apply(
        artifact: GrammarArtifact,
        query: String,
        decisionStatesOnly: Bool,
        limit: Int,
        selected: StateID?
    ) -> AutomatonFilterResult {
        apply(
            artifact: artifact,
            query: query,
            decisionFilter: decisionStatesOnly ? .decisions : .all,
            limit: limit,
            selected: selected
        )
    }

    static func apply(
        artifact: GrammarArtifact,
        query: String,
        decisionFilter: DecisionStateFilter,
        limit: Int,
        selected: StateID?
    ) -> AutomatonFilterResult {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = artifact.states.filter { state in
            let disposition = artifact.decisionSummary(for: state.id)?.disposition
            switch decisionFilter {
            case .all: break
            case .decisions where disposition == nil: return false
            case .unresolved where disposition != .unresolved: return false
            case .resolved where disposition != .resolved: return false
            case .expected where disposition != .expected: return false
            default: break
            }
            guard !normalized.isEmpty else { return true }
            if state.id.description.lowercased().contains(normalized) { return true }
            if state.items.contains(where: { $0.text.lowercased().contains(normalized) }) { return true }
            return artifact.transitions.contains {
                ($0.from == state.id || $0.to == state.id)
                    && $0.symbol.lowercased().contains(normalized)
            }
        }.map(\.id)
        var visible = Array(matches.prefix(max(0, limit)))
        if let selected, !visible.contains(selected) { visible.append(selected) }
        return AutomatonFilterResult(
            visible: Set(visible),
            totalMatches: matches.count,
            truncated: matches.count > limit
        )
    }
}

struct AutomatonView: View {
    let artifact: GrammarArtifact
    let selection: ArtifactIdentity?
    let onSelect: (StateID) -> Void
    @State private var query = ""
    @State private var decisionFilter = DecisionStateFilter.all
    @State private var detail = AutomatonDetail.automatic

    private let renderingLimit = 400

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Find state, item, or transition", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                Picker("States", selection: $decisionFilter) {
                    ForEach(DecisionStateFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 145)
                Picker("Detail", selection: $detail) {
                    ForEach(AutomatonDetail.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 110)
                Spacer()
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }.padding(10)
            Divider()
            if visibleIDs.isEmpty {
                ContentUnavailableView("No matching states", systemImage: "magnifyingglass", description: Text("Adjust the search or state filter."))
            } else {
                AutomatonWebView(
                    artifact: artifact,
                    selectedState: selectedState,
                    visibleStates: visibleIDs,
                    detail: detail,
                    onSelect: onSelect
                )
            }
        }
    }

    private var filterResult: AutomatonFilterResult {
        AutomatonFilter.apply(
            artifact: artifact,
            query: query,
            decisionFilter: decisionFilter,
            limit: renderingLimit,
            selected: selectedState
        )
    }

    private var visibleIDs: Set<StateID> {
        filterResult.visible
    }

    private var statusText: String {
        filterResult.truncated
            ? "Showing \(renderingLimit) of \(filterResult.totalMatches) states"
            : "\(filterResult.totalMatches) states · \(visibleTransitionCount) transitions"
    }

    private var visibleTransitionCount: Int {
        artifact.transitions.count {
            visibleIDs.contains($0.from) && visibleIDs.contains($0.to)
        }
    }

    private var selectedState: StateID? {
        switch selection {
        case .state(let id): id
        case .cell(let id): id.state
        case .decision(let id): artifact.decision(id)?.cell.state
        default: nil
        }
    }
}

private struct AutomatonWebView: NSViewRepresentable {
    let artifact: GrammarArtifact
    let selectedState: StateID?
    let visibleStates: Set<StateID>
    let detail: AutomatonDetail
    let onSelect: (StateID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "stateSelection")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onSelect = onSelect
        let svg = AutomatonSVG.render(
            artifact,
            selected: nil,
            visibleStates: visibleStates,
            detail: detail,
            interactive: true
        )
        let html = htmlDocument(svg: svg)
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            context.coordinator.pendingSelected = selectedState
            view.loadHTMLString(html, baseURL: nil)
        } else if context.coordinator.lastSelected != selectedState {
            context.coordinator.lastSelected = selectedState
            let value = selectedState.map { String($0.rawValue) } ?? "null"
            view.evaluateJavaScript("selectVisual(\(value), true)")
        }
    }

    private func htmlDocument(svg: String) -> String {
        """
        <!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width'>
        <style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}button{font:12px system-ui;padding:5px 8px}#graph-controls{position:fixed;z-index:3;right:12px;top:12px;display:flex;gap:4px}#minimap{position:fixed;z-index:3;right:12px;bottom:12px;width:170px;height:110px;background:#fffE;border:1px solid #aeb7c5;border-radius:8px}.mini-node{fill:#8391a8}.mini-selected{fill:#1671d9}#mini-viewport{fill:#1671d922;stroke:#1671d9;stroke-width:5;vector-effect:non-scaling-stroke}#automaton{touch-action:none;cursor:grab}#automaton.dragging{cursor:grabbing}\(AutomatonSVG.svgStyles)</style></head>
        <body>\(svg)<script>
        const svg=document.getElementById('automaton'), viewport=document.getElementById('viewport'), mini=document.getElementById('mini-viewport');
        let scale=1,tx=0,ty=0,drag=null; const contentW=\(layoutWidth),contentH=\(layoutHeight);
        function apply(){viewport.setAttribute('transform',`translate(${tx} ${ty}) scale(${scale})`);updateMini()}
        function updateMini(){mini.setAttribute('x',Math.max(0,-tx/scale));mini.setAttribute('y',Math.max(0,-ty/scale));mini.setAttribute('width',svg.clientWidth/scale);mini.setAttribute('height',svg.clientHeight/scale)}
        function fitGraph(){scale=Math.min(svg.clientWidth/contentW,svg.clientHeight/contentH)*.92;tx=(svg.clientWidth-contentW*scale)/2;ty=(svg.clientHeight-contentH*scale)/2;apply()}
        function zoomBy(factor,cx=svg.clientWidth/2,cy=svg.clientHeight/2){const old=scale;scale=Math.max(.08,Math.min(4,scale*factor));tx=cx-(cx-tx)*(scale/old);ty=cy-(cy-ty)*(scale/old);apply()}
        function selectState(id){selectVisual(id,false);window.webkit.messageHandlers.stateSelection.postMessage(id)}
        function selectVisual(id,focus){document.querySelectorAll('.node.selected').forEach(n=>n.classList.remove('selected'));if(id===null)return;const node=document.querySelector(`[data-state="${id}"]`);if(node){node.classList.add('selected');if(focus){const r=node.getBBox();tx=svg.clientWidth/2-(r.x+r.width/2)*scale;ty=svg.clientHeight/2-(r.y+r.height/2)*scale;apply()}}}
        svg.addEventListener('wheel',e=>{e.preventDefault();const r=svg.getBoundingClientRect();zoomBy(e.deltaY<0?1.12:.89,e.clientX-r.left,e.clientY-r.top)},{passive:false});
        svg.addEventListener('pointerdown',e=>{drag={x:e.clientX,y:e.clientY,tx,ty};svg.setPointerCapture(e.pointerId);svg.classList.add('dragging')});
        svg.addEventListener('pointermove',e=>{if(drag){tx=drag.tx+e.clientX-drag.x;ty=drag.ty+e.clientY-drag.y;apply()}});
        svg.addEventListener('pointerup',e=>{drag=null;svg.classList.remove('dragging')});window.addEventListener('resize',fitGraph);requestAnimationFrame(fitGraph);
        </script></body></html>
        """
    }

    private var layoutWidth: Int {
        let states = artifact.states.filter { visibleStates.contains($0.id) }
        let transitions = artifact.transitions.filter { visibleStates.contains($0.from) && visibleStates.contains($0.to) }
        let compact = detail == .compact || (detail == .automatic && states.count > 70)
        return Int(AutomatonLayoutEngine.layout(states: states, transitions: transitions, compact: compact).width)
    }

    private var layoutHeight: Int {
        let states = artifact.states.filter { visibleStates.contains($0.id) }
        let transitions = artifact.transitions.filter { visibleStates.contains($0.from) && visibleStates.contains($0.to) }
        let compact = detail == .compact || (detail == .automatic && states.count > 70)
        return Int(AutomatonLayoutEngine.layout(states: states, transitions: transitions, compact: compact).height)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onSelect: (StateID) -> Void
        var lastHTML: String?
        var lastSelected: StateID?
        var pendingSelected: StateID?
        init(onSelect: @escaping (StateID) -> Void) { self.onSelect = onSelect }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let value = message.body as? Int { onSelect(StateID(rawValue: value)) }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastSelected = pendingSelected
            let value = pendingSelected.map { String($0.rawValue) } ?? "null"
            webView.evaluateJavaScript("selectVisual(\(value), false)")
            pendingSelected = nil
        }
    }
}

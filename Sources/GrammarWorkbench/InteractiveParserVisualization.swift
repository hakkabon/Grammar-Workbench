import Foundation

public struct GrammarGraphViewport: Hashable, Codable, Sendable {
    public var scale: Double
    public var translation: GrammarGraphPoint
    public var minimumScale: Double
    public var maximumScale: Double

    public init(
        scale: Double = 1, translation: GrammarGraphPoint = .init(x: 0, y: 0),
        minimumScale: Double = 0.08, maximumScale: Double = 8
    ) {
        self.minimumScale = max(0.001, minimumScale)
        self.maximumScale = max(self.minimumScale, maximumScale)
        self.scale = min(self.maximumScale, max(self.minimumScale, scale))
        self.translation = translation
    }

    public mutating func pan(x: Double, y: Double) {
        translation = .init(x: translation.x + x, y: translation.y + y)
    }

    public mutating func zoom(by factor: Double, anchor: GrammarGraphPoint) {
        guard factor.isFinite, factor > 0 else { return }
        let previous = scale
        scale = min(maximumScale, max(minimumScale, scale * factor))
        let ratio = scale / previous
        translation = .init(
            x: anchor.x - (anchor.x - translation.x) * ratio,
            y: anchor.y - (anchor.y - translation.y) * ratio
        )
    }

    public mutating func fit(
        content: GrammarGraphRect, viewportWidth: Double, viewportHeight: Double,
        padding: Double = 24
    ) {
        guard content.width > 0, content.height > 0,
              viewportWidth > padding * 2, viewportHeight > padding * 2 else { return }
        scale = min(
            maximumScale,
            max(minimumScale, min(
                (viewportWidth - padding * 2) / content.width,
                (viewportHeight - padding * 2) / content.height
            ))
        )
        translation = .init(
            x: viewportWidth / 2 - content.midX * scale,
            y: viewportHeight / 2 - content.midY * scale
        )
    }

    public func worldPoint(fromScreen point: GrammarGraphPoint) -> GrammarGraphPoint {
        .init(x: (point.x - translation.x) / scale, y: (point.y - translation.y) / scale)
    }
}

public enum GrammarParserVisualizationAction: String, Hashable, Codable, Sendable {
    case shift, reduce, accept, error, recovery, conflict, other
}

public struct GrammarParserVisualizationFrame: Hashable, Codable, Sendable, Identifiable {
    public let index: Int
    public let action: GrammarParserVisualizationAction
    public let actionDescription: String
    public let activeStateID: String?
    public let activeEdgeID: String?
    public let stack: [String]
    public let remainingInput: [String]
    public let consumedTokenCount: Int
    public let production: Int?
    public var id: Int { index }
}

public struct GrammarParserVisualizationTransition: Hashable, Codable, Sendable {
    public let fromFrame: Int
    public let toFrame: Int
    public let enteredNodeIDs: [String]
    public let exitedNodeIDs: [String]
    public let enteredEdgeIDs: [String]
    public let exitedEdgeIDs: [String]
}

public struct GrammarParserVisualizationTimeline: Hashable, Codable, Sendable {
    public let graph: GrammarGraph
    public let layout: GrammarGraphAdvancedLayoutSnapshot
    public let frames: [GrammarParserVisualizationFrame]
    public let transitions: [GrammarParserVisualizationTransition]
    public let tokenCount: Int

    public func frame(at index: Int) -> GrammarParserVisualizationFrame? {
        frames.indices.contains(index) ? frames[index] : nil
    }
}

public enum GrammarParserVisualizationBuilder {
    public static func make(
        artifact: GrammarArtifactSnapshot, parse: GrammarParseResult,
        layoutOptions: GrammarGraphLayoutOptions = .init(direction: .leftToRight)
    ) throws -> GrammarParserVisualizationTimeline {
        let graph = GrammarGraph(
            id: "parser-automaton", title: "Parser step-through",
            nodes: artifact.states.map { state in
                .init(
                    id: "state:\(state.id)", label: "I\(state.id)",
                    detail: state.items.prefix(3).joined(separator: "\n"), kind: .state,
                    width: 220, height: 88, metadata: ["state": String(state.id)]
                )
            },
            edges: artifact.transitions.enumerated().map { index, transition in
                .init(
                    id: "transition:\(index):\(transition.from):\(transition.to)",
                    source: "state:\(transition.from)", target: "state:\(transition.to)",
                    label: transition.symbol,
                    metadata: ["symbol": transition.symbol]
                )
            }
        )
        let layout = try GrammarGraphGeometryEngine.layout(graph, options: layoutOptions)
        let edges = Dictionary(grouping: graph.edges) { "\($0.source)\u{1f}\($0.target)" }
        let frames = parse.trace.map { frame in
            let stateID = frame.state.map { "state:\($0)" } ?? parsedStateID(from: frame.stack.last)
            let targetState = targetStateID(from: frame.action)
            let edge = stateID.flatMap { source in
                targetState.flatMap { target in
                    edges["\(source)\u{1f}\(target)"]?.first { candidate in
                        frame.cellSymbol == nil || candidate.label == frame.cellSymbol
                    } ?? edges["\(source)\u{1f}\(target)"]?.first
                }
            }
            return GrammarParserVisualizationFrame(
                index: frame.index, action: classify(frame.action),
                actionDescription: frame.action, activeStateID: stateID,
                activeEdgeID: edge?.id, stack: frame.stack,
                remainingInput: frame.remainingInput,
                consumedTokenCount: max(0, parse.tokens.count - frame.remainingInput.filter { $0 != "$" }.count),
                production: frame.production
            )
        }
        let transitions = zip(frames, frames.dropFirst()).map { previous, current in
            transition(from: previous, to: current)
        }
        return .init(
            graph: graph, layout: layout, frames: frames,
            transitions: transitions, tokenCount: parse.tokens.count
        )
    }

    private static func parsedStateID(from value: String?) -> String? {
        guard let value else { return nil }
        let digits = value.reversed().prefix { $0.isNumber }.reversed()
        return digits.isEmpty ? nil : "state:\(String(digits))"
    }
    private static func targetStateID(from action: String) -> String? {
        guard action.lowercased().contains("shift") else { return nil }
        let suffix = action.reversed().prefix { $0.isNumber }.reversed()
        return suffix.isEmpty ? nil : "state:\(String(suffix))"
    }
    private static func classify(_ description: String) -> GrammarParserVisualizationAction {
        let value = description.lowercased()
        if value.contains("shift") { return .shift }
        if value.contains("reduce") { return .reduce }
        if value.contains("accept") { return .accept }
        if value.contains("recover") || value.contains("insert") || value.contains("delete") { return .recovery }
        if value.contains("conflict") { return .conflict }
        if value.contains("error") || value.contains("reject") { return .error }
        return .other
    }
    private static func transition(
        from: GrammarParserVisualizationFrame, to: GrammarParserVisualizationFrame
    ) -> GrammarParserVisualizationTransition {
        let previousNodes = Set([from.activeStateID].compactMap { $0 })
        let nextNodes = Set([to.activeStateID].compactMap { $0 })
        let previousEdges = Set([from.activeEdgeID].compactMap { $0 })
        let nextEdges = Set([to.activeEdgeID].compactMap { $0 })
        return .init(
            fromFrame: from.index, toFrame: to.index,
            enteredNodeIDs: nextNodes.subtracting(previousNodes).sorted(),
            exitedNodeIDs: previousNodes.subtracting(nextNodes).sorted(),
            enteredEdgeIDs: nextEdges.subtracting(previousEdges).sorted(),
            exitedEdgeIDs: previousEdges.subtracting(nextEdges).sorted()
        )
    }
}

public struct GrammarParserVisualizationState: Hashable, Codable, Sendable {
    public var currentFrame: Int
    public var isPlaying: Bool
    public var playbackRate: Double
    public var selectedNodeID: String?
    public var collapsedNodeIDs: Set<String>
    public var viewport: GrammarGraphViewport

    public init(
        currentFrame: Int = 0, isPlaying: Bool = false, playbackRate: Double = 1,
        selectedNodeID: String? = nil, collapsedNodeIDs: Set<String> = [],
        viewport: GrammarGraphViewport = .init()
    ) {
        self.currentFrame = max(0, currentFrame); self.isPlaying = isPlaying
        self.playbackRate = min(8, max(0.1, playbackRate)); self.selectedNodeID = selectedNodeID
        self.collapsedNodeIDs = collapsedNodeIDs; self.viewport = viewport
    }

    public mutating func stepForward(frameCount: Int) { currentFrame = min(max(0, frameCount - 1), currentFrame + 1) }
    public mutating func stepBackward() { currentFrame = max(0, currentFrame - 1) }
    public mutating func seek(to frame: Int, frameCount: Int) { currentFrame = min(max(0, frameCount - 1), max(0, frame)) }
    public mutating func toggleCollapsed(_ id: String) {
        if !collapsedNodeIDs.insert(id).inserted { collapsedNodeIDs.remove(id) }
    }
}

public struct GrammarGraphProjection: Hashable, Codable, Sendable {
    public let graph: GrammarGraph
    public let visibleNodeIDs: [String]
    public let hiddenNodeCount: Int
    public let collapsedNodeIDs: [String]
}

public enum GrammarInteractiveGraphProjection {
    public static func syntaxTree(
        _ root: GrammarSyntaxNode, collapsedNodeIDs: Set<String> = []
    ) -> GrammarGraphProjection {
        var nodes: [GrammarGraphNode] = [], edges: [GrammarGraphEdge] = []
        var hidden = 0
        func count(_ node: GrammarSyntaxNode) -> Int { 1 + node.children.reduce(0) { $0 + count($1) } }
        func visit(_ node: GrammarSyntaxNode, path: String) {
            let collapsed = collapsedNodeIDs.contains(path)
            let hiddenHere = collapsed ? node.children.reduce(0) { $0 + count($1) } : 0
            nodes.append(.init(
                id: path, label: node.symbol,
                detail: collapsed ? "\(hiddenHere) hidden descendant\(hiddenHere == 1 ? "" : "s")" : node.token?.lexeme,
                kind: .syntax, metadata: ["collapsed": String(collapsed), "hiddenDescendants": String(hiddenHere)]
            ))
            if collapsed { hidden += hiddenHere; return }
            for (index, child) in node.children.enumerated() {
                let childPath = "\(path).\(index)"
                edges.append(.init(id: "\(path)->\(childPath)", source: path, target: childPath))
                visit(child, path: childPath)
            }
        }
        visit(root, path: "root")
        let graph = GrammarGraph(id: "interactive-syntax-tree", title: "Syntax tree", nodes: nodes, edges: edges)
        return .init(graph: graph, visibleNodeIDs: nodes.map(\.id), hiddenNodeCount: hidden, collapsedNodeIDs: collapsedNodeIDs.sorted())
    }

    public static func sharedForest(
        _ forest: GrammarSharedParseForest, collapsedNodeIDs: Set<String> = []
    ) -> GrammarGraphProjection {
        let full = GrammarGraph.sharedForest(forest)
        let outgoing = Dictionary(grouping: full.edges, by: \.source)
        var visible = Set<String>(), queue = forest.roots.map { "symbol:\($0)" }, hidden = Set<String>()
        while let id = queue.first {
            queue.removeFirst()
            guard visible.insert(id).inserted else { continue }
            if collapsedNodeIDs.contains(id) {
                var descendants = outgoing[id, default: []].map(\.target)
                while let child = descendants.popLast() {
                    guard hidden.insert(child).inserted else { continue }
                    descendants += outgoing[child, default: []].map(\.target)
                }
                continue
            }
            queue += outgoing[id, default: []].map(\.target)
        }
        let nodes = full.nodes.filter { visible.contains($0.id) }.map { node -> GrammarGraphNode in
            guard collapsedNodeIDs.contains(node.id) else { return node }
            var metadata = node.metadata; metadata["collapsed"] = "true"
            metadata["hiddenDescendants"] = String(hidden.count)
            return .init(id: node.id, label: node.label, detail: "Collapsed", kind: node.kind, width: node.width, height: node.height, metadata: metadata)
        }
        let nodeIDs = Set(nodes.map(\.id))
        let edges = full.edges.filter { nodeIDs.contains($0.source) && nodeIDs.contains($0.target) }
        return .init(
            graph: .init(id: full.id, title: full.title, nodes: nodes, edges: edges),
            visibleNodeIDs: nodes.map(\.id), hiddenNodeCount: full.nodes.count - nodes.count,
            collapsedNodeIDs: collapsedNodeIDs.sorted()
        )
    }
}

public enum GrammarParserVisualizationHTMLRenderer {
    public static func render(_ timeline: GrammarParserVisualizationTimeline) throws -> String {
        let svg = GrammarGraphAdvancedSVGRenderer.render(timeline.layout)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let frames = String(decoding: try encoder.encode(timeline.frames), as: UTF8.self)
            .replacingOccurrences(of: "</", with: "<\\/")
        let miniNodes = timeline.layout.nodes.map { node in
            "<rect x='\(node.frame.x)' y='\(node.frame.y)' width='\(node.frame.width)' height='\(node.frame.height)'/>"
        }.joined()
        return """
        <!doctype html><html><head><meta charset='utf-8'><style>
        html,body{margin:0;width:100%;height:100%;overflow:hidden;font:13px system-ui;background:#fff}#toolbar{position:fixed;z-index:5;top:10px;left:10px;display:flex;gap:5px;align-items:center;background:#fffffff0;padding:7px;border:1px solid #ccd3df;border-radius:9px}button{padding:4px 8px}#action{min-width:220px}svg[role=img]{width:100%;height:100%;touch-action:none;cursor:grab}.node.active>*:first-child{stroke:#e05800;stroke-width:5}.edge.active path{stroke:#e05800;stroke-width:3}#minimap{position:fixed;right:12px;bottom:12px;width:170px;height:110px;background:#fffE;border:1px solid #aeb7c5;border-radius:8px}#minimap rect{fill:#8391a8}#mini-viewport{fill:#1671d922!important;stroke:#1671d9;stroke-width:5;vector-effect:non-scaling-stroke}
        </style></head><body><div id='toolbar'><button id='back'>◀</button><button id='play'>Play</button><button id='forward'>▶</button><input id='step' type='range' min='0' max='\(max(0, timeline.frames.count - 1))' value='0'/><button id='minus'>−</button><button id='plus'>＋</button><button id='fit'>Fit</button><span id='action'></span></div>
        \(svg)<svg id='minimap' viewBox='0 0 \(timeline.layout.width) \(timeline.layout.height)'>\(miniNodes)<rect id='mini-viewport'/></svg>
        <script>const frames=\(frames),svg=document.querySelector('svg[role=img]'),groups=['clusters','edges','nodes'].map(id=>document.getElementById(id)),ns='http://www.w3.org/2000/svg',viewport=document.createElementNS(ns,'g');viewport.id='viewport';groups.forEach(g=>viewport.appendChild(g));svg.appendChild(viewport);let scale=1,tx=0,ty=0,drag=null,index=0,timer=null;const mini=document.getElementById('mini-viewport'),cw=\(timeline.layout.width),ch=\(timeline.layout.height);function apply(){viewport.setAttribute('transform',`translate(${tx} ${ty}) scale(${scale})`);mini.setAttribute('x',Math.max(0,-tx/scale));mini.setAttribute('y',Math.max(0,-ty/scale));mini.setAttribute('width',svg.clientWidth/scale);mini.setAttribute('height',svg.clientHeight/scale)}function fit(){scale=Math.min(svg.clientWidth/cw,svg.clientHeight/ch)*.9;tx=(svg.clientWidth-cw*scale)/2;ty=(svg.clientHeight-ch*scale)/2;apply()}function zoom(f){const x=svg.clientWidth/2,y=svg.clientHeight/2,old=scale;scale=Math.max(.08,Math.min(8,scale*f));tx=x-(x-tx)*scale/old;ty=y-(y-ty)*scale/old;apply()}function show(i){index=Math.max(0,Math.min(frames.length-1,i));document.querySelectorAll('.active').forEach(x=>x.classList.remove('active'));const f=frames[index];if(!f)return;if(f.activeStateID)document.querySelector(`[data-node="${f.activeStateID}"]`)?.classList.add('active');if(f.activeEdgeID)document.querySelector(`[data-edge="${f.activeEdgeID}"]`)?.classList.add('active');document.getElementById('action').textContent=`${index}: ${f.actionDescription}`;document.getElementById('step').value=index}function play(){if(timer){clearInterval(timer);timer=null;document.getElementById('play').textContent='Play'}else{timer=setInterval(()=>{if(index>=frames.length-1){play()}else show(index+1)},650);document.getElementById('play').textContent='Pause'}}document.getElementById('back').onclick=()=>show(index-1);document.getElementById('forward').onclick=()=>show(index+1);document.getElementById('play').onclick=play;document.getElementById('step').oninput=e=>show(+e.target.value);document.getElementById('minus').onclick=()=>zoom(.8);document.getElementById('plus').onclick=()=>zoom(1.25);document.getElementById('fit').onclick=fit;svg.onwheel=e=>{e.preventDefault();zoom(e.deltaY<0?1.12:.89)};svg.onpointerdown=e=>{drag={x:e.clientX,y:e.clientY,tx,ty};svg.setPointerCapture(e.pointerId)};svg.onpointermove=e=>{if(drag){tx=drag.tx+e.clientX-drag.x;ty=drag.ty+e.clientY-drag.y;apply()}};svg.onpointerup=()=>drag=null;window.onresize=fit;show(0);requestAnimationFrame(fit);</script></body></html>
        """
    }
}

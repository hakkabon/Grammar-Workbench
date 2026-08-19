import Foundation

public enum GrammarGraphNodeShape: String, Hashable, Codable, Sendable, CaseIterable {
    case rectangle, roundedRectangle, ellipse, diamond
}

public enum GrammarGraphArrowheadStyle: String, Hashable, Codable, Sendable, CaseIterable {
    case filled, open, sweptBack, none
}

public enum GrammarGraphLabelOrientation: String, Hashable, Codable, Sendable {
    case horizontal, tangentAligned
}

public struct GrammarGraphRankConstraint: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let nodeIDs: [String]
    public init(id: String, nodeIDs: [String]) { self.id = id; self.nodeIDs = nodeIDs }
}

public struct GrammarGraphCluster: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let nodeIDs: [String]
    public let parentID: String?
    public init(id: String, label: String, nodeIDs: [String], parentID: String? = nil) {
        self.id = id; self.label = label; self.nodeIDs = nodeIDs; self.parentID = parentID
    }
}

public struct GrammarGraphGeometrySpecification: Hashable, Codable, Sendable {
    public var nodeShapes: [String: GrammarGraphNodeShape]
    public var edgeArrowheads: [String: GrammarGraphArrowheadStyle]
    public var rankConstraints: [GrammarGraphRankConstraint]
    public var clusters: [GrammarGraphCluster]
    public var labelOrientation: GrammarGraphLabelOrientation
    public var clusterPadding: Double

    public init(
        nodeShapes: [String: GrammarGraphNodeShape] = [:],
        edgeArrowheads: [String: GrammarGraphArrowheadStyle] = [:],
        rankConstraints: [GrammarGraphRankConstraint] = [],
        clusters: [GrammarGraphCluster] = [],
        labelOrientation: GrammarGraphLabelOrientation = .tangentAligned,
        clusterPadding: Double = 24
    ) {
        self.nodeShapes = nodeShapes; self.edgeArrowheads = edgeArrowheads
        self.rankConstraints = rankConstraints; self.clusters = clusters
        self.labelOrientation = labelOrientation; self.clusterPadding = clusterPadding
    }
}

public struct GrammarGraphTextMetrics: Hashable, Codable, Sendable {
    public let width: Double
    public let height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public protocol GrammarGraphTextMeasurer: Sendable {
    func measure(text: String, role: GrammarGraphTextRole) -> GrammarGraphTextMetrics
}

public enum GrammarGraphTextRole: String, Hashable, Codable, Sendable {
    case nodeLabel, nodeDetail, edgeLabel, clusterLabel
}

public struct GrammarGraphHeuristicTextMeasurer: GrammarGraphTextMeasurer {
    public init() {}
    public func measure(text: String, role: GrammarGraphTextRole) -> GrammarGraphTextMetrics {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let longest = lines.map(\.count).max() ?? 0
        let characterWidth = role == .nodeDetail ? 6.2 : 7.2
        return .init(width: Double(longest) * characterWidth, height: Double(max(1, lines.count)) * 17)
    }
}

public struct GrammarGraphMeasuredInput: Hashable, Codable, Sendable {
    public let graph: GrammarGraph
    public let nodeTextMetrics: [String: GrammarGraphTextMetrics]
    public let edgeTextMetrics: [String: GrammarGraphTextMetrics]
}

public struct GrammarGraphAdvancedNode: Hashable, Codable, Sendable, Identifiable {
    public let positionedNode: GrammarGraphPositionedNode
    public let shape: GrammarGraphNodeShape
    public var id: String { positionedNode.id }
    public var frame: GrammarGraphRect { positionedNode.frame }
}

public struct GrammarGraphEdgeLabelGeometry: Hashable, Codable, Sendable {
    public let position: GrammarGraphPoint
    public let angle: Double
    public let bounds: GrammarGraphRect
}

public struct GrammarGraphAdvancedRoute: Hashable, Codable, Sendable, Identifiable {
    public let route: GrammarGraphRoute
    public let sourceBoundary: GrammarGraphPoint
    public let targetBoundary: GrammarGraphPoint
    public let arrowheadStyle: GrammarGraphArrowheadStyle
    public let arrowhead: GrammarGraphArrowhead?
    public let label: GrammarGraphEdgeLabelGeometry?
    public var id: String { route.id }
}

public struct GrammarGraphPositionedCluster: Hashable, Codable, Sendable, Identifiable {
    public let cluster: GrammarGraphCluster
    public let frame: GrammarGraphRect
    public var id: String { cluster.id }
}

public struct GrammarGraphAdvancedLayoutSnapshot: Hashable, Codable, Sendable {
    public let layout: GrammarGraphLayoutSnapshot
    public let nodes: [GrammarGraphAdvancedNode]
    public let routes: [GrammarGraphAdvancedRoute]
    public let clusters: [GrammarGraphPositionedCluster]
    public let width: Double
    public let height: Double
}

public enum GrammarGraphGeometryError: Error, LocalizedError, Sendable {
    case unknownNode(constraint: String, node: String)
    case unknownEdge(String)
    case duplicateCluster(String)
    case invalidClusterParent(cluster: String, parent: String)
    case cyclicCluster(String)
    case invalidPadding

    public var errorDescription: String? {
        switch self {
        case .unknownNode(let constraint, let node): "Geometry constraint ‘\(constraint)’ references unknown node ‘\(node)’."
        case .unknownEdge(let id): "Geometry specification references unknown edge ‘\(id)’."
        case .duplicateCluster(let id): "Graph cluster ‘\(id)’ is duplicated."
        case .invalidClusterParent(let cluster, let parent): "Graph cluster ‘\(cluster)’ references unknown parent ‘\(parent)’."
        case .cyclicCluster(let id): "Graph cluster hierarchy contains a cycle at ‘\(id)’."
        case .invalidPadding: "Cluster padding must be finite and non-negative."
        }
    }
}

/// Two-pass geometry pipeline. Pass one measures platform text before the
/// single batched layout call; pass two derives precise boundaries, arrowheads,
/// label tangents, cluster bounds and the spatial index without another FFI call.
public enum GrammarGraphGeometryEngine {
    public static func prepare<M: GrammarGraphTextMeasurer>(
        _ graph: GrammarGraph, measurer: M, horizontalPadding: Double = 24,
        verticalPadding: Double = 18
    ) -> GrammarGraphMeasuredInput {
        var nodeMetrics: [String: GrammarGraphTextMetrics] = [:]
        let nodes = graph.nodes.map { node in
            let label = measurer.measure(text: node.label, role: .nodeLabel)
            let detail = node.detail.map { measurer.measure(text: $0, role: .nodeDetail) }
            let contentWidth = max(label.width, detail?.width ?? 0)
            let contentHeight = label.height + (detail?.height ?? 0)
            nodeMetrics[node.id] = .init(width: contentWidth, height: contentHeight)
            return GrammarGraphNode(
                id: node.id, label: node.label, detail: node.detail, kind: node.kind,
                width: max(node.width, contentWidth + horizontalPadding),
                height: max(node.height, contentHeight + verticalPadding), metadata: node.metadata
            )
        }
        var edgeMetrics: [String: GrammarGraphTextMetrics] = [:]
        let edges = graph.edges.map { edge in
            guard let label = edge.label else { return edge }
            let metrics = measurer.measure(text: label, role: .edgeLabel)
            edgeMetrics[edge.id] = metrics
            var metadata = edge.metadata
            metadata["geometry.labelWidth"] = String(metrics.width)
            metadata["geometry.labelHeight"] = String(metrics.height)
            return GrammarGraphEdge(
                id: edge.id, source: edge.source, target: edge.target,
                label: edge.label, metadata: metadata
            )
        }
        return .init(
            graph: .init(id: graph.id, title: graph.title, nodes: nodes, edges: edges),
            nodeTextMetrics: nodeMetrics, edgeTextMetrics: edgeMetrics
        )
    }

    public static func layout<M: GrammarGraphTextMeasurer>(
        _ graph: GrammarGraph, specification: GrammarGraphGeometrySpecification = .init(),
        options: GrammarGraphLayoutOptions = .init(), measurer: M
    ) throws -> GrammarGraphAdvancedLayoutSnapshot {
        try validate(graph, specification: specification)
        let measured = prepare(graph, measurer: measurer)
        let snapshot = try GrammarGraphLayoutEngine.layout(measured.graph, options: options)
        return enrich(snapshot, graph: measured.graph, measurements: measured, specification: specification)
    }

    public static func layout(
        _ graph: GrammarGraph, specification: GrammarGraphGeometrySpecification = .init(),
        options: GrammarGraphLayoutOptions = .init()
    ) throws -> GrammarGraphAdvancedLayoutSnapshot {
        try layout(graph, specification: specification, options: options, measurer: GrammarGraphHeuristicTextMeasurer())
    }

    private static func enrich(
        _ snapshot: GrammarGraphLayoutSnapshot, graph: GrammarGraph,
        measurements: GrammarGraphMeasuredInput,
        specification: GrammarGraphGeometrySpecification
    ) -> GrammarGraphAdvancedLayoutSnapshot {
        let positionedNodes = constrainedNodes(
            snapshot.nodes, constraints: specification.rankConstraints, options: snapshot.options
        )
        let advancedNodes = positionedNodes.map { positioned in
            GrammarGraphAdvancedNode(
                positionedNode: positioned,
                shape: specification.nodeShapes[positioned.id] ?? defaultShape(positioned.node.kind)
            )
        }
        let nodeByID = Dictionary(uniqueKeysWithValues: advancedNodes.map { ($0.id, $0) })
        let advancedRoutes = snapshot.routes.compactMap { route -> GrammarGraphAdvancedRoute? in
            guard let source = nodeByID[route.edge.source], let target = nodeByID[route.edge.target] else { return nil }
            let direction = terminalDirection(route)
            let sourceBoundary = GrammarGraphGeometry.boundaryIntersection(
                frame: source.frame, shape: source.shape,
                toward: direction.startTarget ?? .init(x: target.frame.midX, y: target.frame.midY)
            )
            let targetBoundary = GrammarGraphGeometry.boundaryIntersection(
                frame: target.frame, shape: target.shape,
                toward: direction.endSource ?? .init(x: source.frame.midX, y: source.frame.midY)
            )
            let style = specification.edgeArrowheads[route.id] ?? .filled
            let arrow = style == .none ? nil : makeArrowhead(tip: targetBoundary, from: direction.endSource ?? sourceBoundary, style: style)
            let label = route.edge.label.flatMap { _ -> GrammarGraphEdgeLabelGeometry? in
                guard let metrics = measurements.edgeTextMetrics[route.id] else { return nil }
                let position = route.labelPosition ?? midpoint(sourceBoundary, targetBoundary)
                var angle = specification.labelOrientation == .horizontal ? 0 : direction.angle
                if angle > .pi / 2 || angle < -.pi / 2 { angle += .pi }
                return .init(
                    position: position, angle: angle,
                    bounds: .init(x: position.x - metrics.width / 2, y: position.y - metrics.height / 2, width: metrics.width, height: metrics.height)
                )
            }
            return .init(
                route: route, sourceBoundary: sourceBoundary, targetBoundary: targetBoundary,
                arrowheadStyle: style, arrowhead: arrow, label: label
            )
        }
        let clusters = positionedClusters(specification.clusters, nodes: nodeByID, padding: specification.clusterPadding)
        let frames = advancedNodes.map(\.frame) + clusters.map(\.frame)
        let width = max(snapshot.width, (frames.map(\.maxX).max() ?? 0) + snapshot.options.margin)
        let height = max(snapshot.height, (frames.map(\.maxY).max() ?? 0) + snapshot.options.margin)
        return .init(
            layout: snapshot, nodes: advancedNodes, routes: advancedRoutes,
            clusters: clusters, width: width, height: height
        )
    }

    private static func validate(_ graph: GrammarGraph, specification: GrammarGraphGeometrySpecification) throws {
        guard specification.clusterPadding.isFinite, specification.clusterPadding >= 0 else { throw GrammarGraphGeometryError.invalidPadding }
        let nodes = Set(graph.nodes.map(\.id))
        let edges = Set(graph.edges.map(\.id))
        for node in specification.nodeShapes.keys where !nodes.contains(node) {
            throw GrammarGraphGeometryError.unknownNode(constraint: "nodeShapes", node: node)
        }
        for edge in specification.edgeArrowheads.keys where !edges.contains(edge) {
            throw GrammarGraphGeometryError.unknownEdge(edge)
        }
        for constraint in specification.rankConstraints {
            for node in constraint.nodeIDs where !nodes.contains(node) { throw GrammarGraphGeometryError.unknownNode(constraint: constraint.id, node: node) }
        }
        var clusterIDs: Set<String> = []
        for cluster in specification.clusters {
            guard clusterIDs.insert(cluster.id).inserted else { throw GrammarGraphGeometryError.duplicateCluster(cluster.id) }
            for node in cluster.nodeIDs where !nodes.contains(node) { throw GrammarGraphGeometryError.unknownNode(constraint: cluster.id, node: node) }
        }
        for cluster in specification.clusters {
            if let parent = cluster.parentID, !clusterIDs.contains(parent) { throw GrammarGraphGeometryError.invalidClusterParent(cluster: cluster.id, parent: parent) }
        }
        let parentByID = Dictionary(uniqueKeysWithValues: specification.clusters.map { ($0.id, $0.parentID) })
        for cluster in specification.clusters {
            var seen: Set<String> = [], current: String? = cluster.id
            while let id = current {
                guard seen.insert(id).inserted else { throw GrammarGraphGeometryError.cyclicCluster(id) }
                current = parentByID[id] ?? nil
            }
        }
    }

    private static func defaultShape(_ kind: GrammarGraphNodeKind) -> GrammarGraphNodeShape {
        switch kind { case .forest: .ellipse; case .packed: .diamond; default: .roundedRectangle }
    }
    private static func constrainedNodes(
        _ nodes: [GrammarGraphPositionedNode], constraints: [GrammarGraphRankConstraint],
        options: GrammarGraphLayoutOptions
    ) -> [GrammarGraphPositionedNode] {
        var frames = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.frame) })
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for constraint in constraints {
            let members = constraint.nodeIDs.compactMap { id in frames[id].map { (id, $0) } }
            guard members.count > 1 else { continue }
            let rank = members.map { options.direction == .topToBottom ? $0.1.midY : $0.1.midX }
                .reduce(0, +) / Double(members.count)
            var cursor = -Double.infinity
            for (id, frame) in members.sorted(by: {
                let lhs = options.direction == .topToBottom ? $0.1.minX : $0.1.minY
                let rhs = options.direction == .topToBottom ? $1.1.minX : $1.1.minY
                return (lhs, $0.0) < (rhs, $1.0)
            }) {
                if options.direction == .topToBottom {
                    let x = max(frame.x, cursor.isFinite ? cursor : frame.x)
                    frames[id] = .init(x: x, y: rank - frame.height / 2, width: frame.width, height: frame.height)
                    cursor = x + frame.width + options.horizontalGap
                } else {
                    let y = max(frame.y, cursor.isFinite ? cursor : frame.y)
                    frames[id] = .init(x: rank - frame.width / 2, y: y, width: frame.width, height: frame.height)
                    cursor = y + frame.height + options.verticalGap
                }
            }
        }
        return nodes.compactMap { value in
            guard let original = byID[value.id], let frame = frames[value.id] else { return nil }
            return .init(node: original.node, frame: frame)
        }
    }
    private static func terminalDirection(_ route: GrammarGraphRoute) -> (startTarget: GrammarGraphPoint?, endSource: GrammarGraphPoint?, angle: Double) {
        let points = route.points
        let startTarget = points.dropFirst().first
        let endSource = points.dropLast().last
        let a = endSource ?? points.first ?? .init(x: 0, y: 0)
        let b = points.last ?? a
        return (startTarget, endSource, atan2(b.y - a.y, b.x - a.x))
    }
    private static func midpoint(_ a: GrammarGraphPoint, _ b: GrammarGraphPoint) -> GrammarGraphPoint { .init(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    private static func makeArrowhead(tip: GrammarGraphPoint, from: GrammarGraphPoint, style: GrammarGraphArrowheadStyle) -> GrammarGraphArrowhead {
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        let length = style == .sweptBack ? 15.0 : 12.0
        let spread = style == .sweptBack ? 0.72 : 0.52
        return .init(
            tip: tip, angle: angle,
            left: .init(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)),
            right: .init(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread))
        )
    }
    private static func positionedClusters(
        _ clusters: [GrammarGraphCluster], nodes: [String: GrammarGraphAdvancedNode], padding: Double
    ) -> [GrammarGraphPositionedCluster] {
        let byID = Dictionary(uniqueKeysWithValues: clusters.map { ($0.id, $0) })
        let children = Dictionary(grouping: clusters.compactMap { cluster in
            cluster.parentID.map { ($0, cluster.id) }
        }, by: \.0).mapValues { $0.map(\.1) }
        var memo: [String: GrammarGraphRect] = [:]
        func frame(for id: String) -> GrammarGraphRect? {
            if let cached = memo[id] { return cached }
            guard let cluster = byID[id] else { return nil }
            let frames = cluster.nodeIDs.compactMap { nodes[$0]?.frame }
                + (children[id] ?? []).compactMap { frame(for: $0) }
            guard let minX = frames.map(\.minX).min(), let minY = frames.map(\.minY).min(),
                  let maxX = frames.map(\.maxX).max(), let maxY = frames.map(\.maxY).max() else { return nil }
            let value = GrammarGraphRect(
                x: minX - padding, y: minY - padding,
                width: maxX - minX + padding * 2, height: maxY - minY + padding * 2
            )
            memo[id] = value
            return value
        }
        return clusters.sorted { $0.id < $1.id }.compactMap { cluster in
            frame(for: cluster.id).map { .init(cluster: cluster, frame: $0) }
        }
    }
}

public enum GrammarGraphAdvancedSVGRenderer {
    public static func render(_ snapshot: GrammarGraphAdvancedLayoutSnapshot) -> String {
        let clusterMarkup = snapshot.clusters.map { cluster in
            let f = cluster.frame
            return "<g class='cluster'><rect x='\(n(f.x))' y='\(n(f.y))' width='\(n(f.width))' height='\(n(f.height))' rx='14'/><text x='\(n(f.x + 10))' y='\(n(f.y + 17))'>\(escape(cluster.cluster.label))</text></g>"
        }.joined()
        let edgeMarkup = snapshot.routes.map { route in
            let a = route.sourceBoundary, b = route.targetBoundary
            let arrow = route.arrowhead.map { arrow in
                let points = "\(n(arrow.tip.x)),\(n(arrow.tip.y)) \(n(arrow.left.x)),\(n(arrow.left.y)) \(n(arrow.right.x)),\(n(arrow.right.y))"
                switch route.arrowheadStyle {
                case .filled: return "<polygon class='arrow filled' points='\(points)'/>"
                case .open: return "<polyline class='arrow open' points='\(n(arrow.left.x)),\(n(arrow.left.y)) \(n(arrow.tip.x)),\(n(arrow.tip.y)) \(n(arrow.right.x)),\(n(arrow.right.y))'/>"
                case .sweptBack:
                    let backX = (arrow.left.x + arrow.right.x) / 2 + (arrow.tip.x - (arrow.left.x + arrow.right.x) / 2) * 0.35
                    let backY = (arrow.left.y + arrow.right.y) / 2 + (arrow.tip.y - (arrow.left.y + arrow.right.y) / 2) * 0.35
                    return "<polygon class='arrow swept' points='\(n(arrow.tip.x)),\(n(arrow.tip.y)) \(n(arrow.left.x)),\(n(arrow.left.y)) \(n(backX)),\(n(backY)) \(n(arrow.right.x)),\(n(arrow.right.y))'/>"
                case .none: return ""
                }
            } ?? ""
            let label = route.route.edge.label.flatMap { text in
                route.label.map { geometry in
                    let degrees = geometry.angle * 180 / .pi
                    return "<text class='edge-label' x='\(n(geometry.position.x))' y='\(n(geometry.position.y - 6))' transform='rotate(\(n(degrees)) \(n(geometry.position.x)) \(n(geometry.position.y)))'>\(escape(text))</text>"
                }
            } ?? ""
            return "<g class='edge' data-edge='\(escape(route.id))'><path d='\(pathData(route, snapshot: snapshot, fallbackStart: a, fallbackEnd: b))'/>\(arrow)\(label)</g>"
        }.joined()
        let nodeMarkup = snapshot.nodes.map { node in
            let f = node.frame
            let shape: String
            switch node.shape {
            case .rectangle:
                shape = "<rect x='\(n(f.x))' y='\(n(f.y))' width='\(n(f.width))' height='\(n(f.height))'/>"
            case .roundedRectangle:
                shape = "<rect x='\(n(f.x))' y='\(n(f.y))' width='\(n(f.width))' height='\(n(f.height))' rx='10'/>"
            case .ellipse:
                shape = "<ellipse cx='\(n(f.midX))' cy='\(n(f.midY))' rx='\(n(f.width / 2))' ry='\(n(f.height / 2))'/>"
            case .diamond:
                shape = "<polygon points='\(n(f.midX)),\(n(f.minY)) \(n(f.maxX)),\(n(f.midY)) \(n(f.midX)),\(n(f.maxY)) \(n(f.minX)),\(n(f.midY))'/>"
            }
            return "<g class='node shape-\(node.shape.rawValue)' data-node='\(escape(node.id))'>\(shape)<text x='\(n(f.midX))' y='\(n(f.midY + 5))'>\(escape(node.positionedNode.node.label))</text></g>"
        }.joined()
        return """
        <svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 \(n(snapshot.width)) \(n(snapshot.height))' role='img' aria-label='\(escape(snapshot.layout.title))'>
        <style>.cluster rect{fill:#f8fafc;stroke:#9aa6b2;stroke-dasharray:5 3}.cluster text{font:600 11px system-ui;fill:#536171}.edge path,.arrow.open{fill:none;stroke:#718096;stroke-width:1.6}.arrow.filled,.arrow.swept{fill:#718096}.node rect,.node ellipse,.node polygon{fill:#f5f7fb;stroke:#52667d;stroke-width:1.5}.node text,.edge-label{text-anchor:middle;font:12px system-ui;fill:#172033}.edge-label{paint-order:stroke;stroke:white;stroke-width:5}</style>
        <g id='clusters'>\(clusterMarkup)</g><g id='edges'>\(edgeMarkup)</g><g id='nodes'>\(nodeMarkup)</g></svg>
        """
    }
    private static func n(_ value: Double) -> String { String(format: "%.1f", value) }
    private static func pathData(
        _ route: GrammarGraphAdvancedRoute, snapshot: GrammarGraphAdvancedLayoutSnapshot,
        fallbackStart: GrammarGraphPoint, fallbackEnd: GrammarGraphPoint
    ) -> String {
        let baseNodes = Dictionary(uniqueKeysWithValues: snapshot.layout.nodes.map { ($0.id, $0.frame) })
        let advancedNodes = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0.frame) })
        let endpointsMoved = baseNodes[route.route.edge.source] != advancedNodes[route.route.edge.source]
            || baseNodes[route.route.edge.target] != advancedNodes[route.route.edge.target]
        guard !endpointsMoved, !route.route.segments.isEmpty else {
            return "M \(n(fallbackStart.x)) \(n(fallbackStart.y)) L \(n(fallbackEnd.x)) \(n(fallbackEnd.y))"
        }
        var result = "M \(n(fallbackStart.x)) \(n(fallbackStart.y))"
        for (index, segment) in route.route.segments.enumerated() {
            switch segment {
            case .line(_, let end):
                let point = index == route.route.segments.count - 1 ? fallbackEnd : end
                result += " L \(n(point.x)) \(n(point.y))"
            case .cubicCurve(_, let control1, let control2, let end):
                let point = index == route.route.segments.count - 1 ? fallbackEnd : end
                result += " C \(n(control1.x)) \(n(control1.y)) \(n(control2.x)) \(n(control2.y)) \(n(point.x)) \(n(point.y))"
            }
        }
        return result
    }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

public enum GrammarGraphAdvancedDOTRenderer {
    public static func render(
        _ graph: GrammarGraph, specification: GrammarGraphGeometrySpecification,
        options: GrammarGraphLayoutOptions = .init()
    ) -> String {
        var lines = [
            "digraph \(q(graph.id)) {",
            "  graph [rankdir=\(options.direction == .leftToRight ? "LR" : "TB"), compound=true];"
        ]
        let clustered = Set(specification.clusters.flatMap(\.nodeIDs))
        for cluster in specification.clusters.sorted(by: { $0.id < $1.id }) {
            lines.append("  subgraph \(q("cluster_\(cluster.id)")) {")
            lines.append("    label=\(q(cluster.label));")
            for id in cluster.nodeIDs.sorted() { lines.append("    \(q(id));") }
            lines.append("  }")
        }
        for constraint in specification.rankConstraints.sorted(by: { $0.id < $1.id }) {
            lines.append("  { rank=same; \(constraint.nodeIDs.sorted().map(q).joined(separator: "; ")); }")
        }
        for node in graph.nodes.sorted(by: { $0.id < $1.id }) {
            let shape = specification.nodeShapes[node.id] ?? .roundedRectangle
            let dotShape = switch shape { case .ellipse: "ellipse"; case .diamond: "diamond"; default: "box" }
            let style = shape == .roundedRectangle ? ", style=rounded" : ""
            let prefix = clustered.contains(node.id) ? "  " : "  "
            lines.append("\(prefix)\(q(node.id)) [label=\(q(node.label)), shape=\(dotShape)\(style)];")
        }
        for edge in graph.edges.sorted(by: { $0.id < $1.id }) {
            let arrow = specification.edgeArrowheads[edge.id] ?? .filled
            let arrowhead = switch arrow { case .filled: "normal"; case .open: "onormal"; case .sweptBack: "vee"; case .none: "none" }
            let label = edge.label.map { ", label=\(q($0))" } ?? ""
            lines.append("  \(q(edge.source)) -> \(q(edge.target)) [id=\(q(edge.id)), arrowhead=\(arrowhead)\(label)];")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }
    private static func q(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

public enum GrammarGraphGeometry {
    public static func boundaryIntersection(
        frame: GrammarGraphRect, shape: GrammarGraphNodeShape, toward point: GrammarGraphPoint
    ) -> GrammarGraphPoint {
        let cx = frame.midX, cy = frame.midY, dx = point.x - cx, dy = point.y - cy
        guard dx != 0 || dy != 0 else { return .init(x: cx, y: cy) }
        let halfWidth = frame.width / 2, halfHeight = frame.height / 2
        switch shape {
        case .rectangle, .roundedRectangle:
            let scale = min(halfWidth / max(abs(dx), .leastNonzeroMagnitude), halfHeight / max(abs(dy), .leastNonzeroMagnitude))
            return .init(x: cx + dx * scale, y: cy + dy * scale)
        case .ellipse:
            let scale = 1 / sqrt(dx * dx / (halfWidth * halfWidth) + dy * dy / (halfHeight * halfHeight))
            return .init(x: cx + dx * scale, y: cy + dy * scale)
        case .diamond:
            let scale = 1 / (abs(dx) / halfWidth + abs(dy) / halfHeight)
            return .init(x: cx + dx * scale, y: cy + dy * scale)
        }
    }
}

public struct GrammarGraphSpatialEntry: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Codable, Sendable { case node, edgeRoute, edgeLabel, cluster }
    public let id: String
    public let kind: Kind
    public let bounds: GrammarGraphRect
}

/// Immutable STR-packed R-tree. Queries visit only branches whose bounding
/// rectangles intersect the requested area.
public struct GrammarGraphSpatialIndex: Sendable {
    private indirect enum Tree: Sendable {
        case leaf(bounds: GrammarGraphRect, entries: [GrammarGraphSpatialEntry])
        case branch(bounds: GrammarGraphRect, children: [Tree])
        var bounds: GrammarGraphRect { switch self { case .leaf(let bounds, _), .branch(let bounds, _): bounds } }
    }
    private let root: Tree?

    public init(snapshot: GrammarGraphAdvancedLayoutSnapshot, nodeCapacity: Int = 8) {
        var entries = snapshot.nodes.map { GrammarGraphSpatialEntry(id: $0.id, kind: .node, bounds: $0.frame) }
        entries += snapshot.routes.map { route in
            let points = route.route.points + [route.sourceBoundary, route.targetBoundary]
            let minX = points.map(\.x).min() ?? 0, minY = points.map(\.y).min() ?? 0
            let maxX = points.map(\.x).max() ?? 0, maxY = points.map(\.y).max() ?? 0
            return .init(
                id: route.id, kind: .edgeRoute,
                bounds: .init(x: minX - 2, y: minY - 2, width: maxX - minX + 4, height: maxY - minY + 4)
            )
        }
        entries += snapshot.routes.compactMap { route in route.label.map { .init(id: route.id, kind: .edgeLabel, bounds: $0.bounds) } }
        entries += snapshot.clusters.map { .init(id: $0.id, kind: .cluster, bounds: $0.frame) }
        root = Self.pack(entries, capacity: max(2, nodeCapacity))
    }

    public func query(_ bounds: GrammarGraphRect) -> [GrammarGraphSpatialEntry] {
        guard let root else { return [] }
        var result: [GrammarGraphSpatialEntry] = []
        Self.query(root, bounds: bounds, result: &result)
        return result.sorted { ($0.kind.rawValue, $0.id) < ($1.kind.rawValue, $1.id) }
    }
    public func query(point: GrammarGraphPoint, tolerance: Double = 0) -> [GrammarGraphSpatialEntry] {
        query(.init(x: point.x - tolerance, y: point.y - tolerance, width: tolerance * 2, height: tolerance * 2))
    }

    private static func pack(_ entries: [GrammarGraphSpatialEntry], capacity: Int) -> Tree? {
        guard !entries.isEmpty else { return nil }
        var level: [Tree] = stride(from: 0, to: entries.count, by: capacity).map { start in
            let slice = Array(entries.sorted { ($0.bounds.midX, $0.bounds.midY, $0.id) < ($1.bounds.midX, $1.bounds.midY, $1.id) }[start..<min(start + capacity, entries.count)])
            return .leaf(bounds: union(slice.map(\.bounds)), entries: slice)
        }
        while level.count > 1 {
            let sorted = level.sorted { ($0.bounds.midX, $0.bounds.midY) < ($1.bounds.midX, $1.bounds.midY) }
            level = stride(from: 0, to: sorted.count, by: capacity).map { start in
                let children = Array(sorted[start..<min(start + capacity, sorted.count)])
                return .branch(bounds: union(children.map(\.bounds)), children: children)
            }
        }
        return level[0]
    }
    private static func query(_ tree: Tree, bounds: GrammarGraphRect, result: inout [GrammarGraphSpatialEntry]) {
        guard overlaps(tree.bounds, bounds) else { return }
        switch tree {
        case .leaf(_, let entries): result += entries.filter { overlaps($0.bounds, bounds) }
        case .branch(_, let children): for child in children { query(child, bounds: bounds, result: &result) }
        }
    }
    private static func union(_ frames: [GrammarGraphRect]) -> GrammarGraphRect {
        let minX = frames.map(\.minX).min() ?? 0, minY = frames.map(\.minY).min() ?? 0
        let maxX = frames.map(\.maxX).max() ?? 0, maxY = frames.map(\.maxY).max() ?? 0
        return .init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    private static func overlaps(_ a: GrammarGraphRect, _ b: GrammarGraphRect) -> Bool {
        a.minX <= b.maxX && a.maxX >= b.minX && a.minY <= b.maxY && a.maxY >= b.minY
    }
}

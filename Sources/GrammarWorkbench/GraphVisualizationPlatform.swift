import Foundation
#if canImport(SwiftLayout)
import SwiftLayout
#endif

public enum GrammarGraphNodeKind: String, Hashable, Codable, Sendable {
    case state
    case syntax
    case forest
    case packed
    case document
    case symbol
    case generic
}

public struct GrammarGraphNode: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let label: String
    public let detail: String?
    public let kind: GrammarGraphNodeKind
    public let width: Double
    public let height: Double
    public let metadata: [String: String]

    public init(
        id: String, label: String, detail: String? = nil,
        kind: GrammarGraphNodeKind = .generic,
        width: Double = 160, height: Double = 64,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.label = label
        self.detail = detail
        self.kind = kind
        self.width = width
        self.height = height
        self.metadata = metadata
    }
}

public struct GrammarGraphEdge: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let source: String
    public let target: String
    public let label: String?
    public let metadata: [String: String]

    public init(
        id: String, source: String, target: String,
        label: String? = nil, metadata: [String: String] = [:]
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.label = label
        self.metadata = metadata
    }
}

public struct GrammarGraph: Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let nodes: [GrammarGraphNode]
    public let edges: [GrammarGraphEdge]

    public init(
        id: String, title: String,
        nodes: [GrammarGraphNode], edges: [GrammarGraphEdge]
    ) {
        self.id = id
        self.title = title
        self.nodes = nodes
        self.edges = edges
    }
}

public enum GrammarGraphCoordinateAlgorithm: String, Hashable, Codable, Sendable, CaseIterable {
    case medianRelaxation
    case balancedAlignment
}

public enum GrammarGraphRoutingStyle: String, Hashable, Codable, Sendable, CaseIterable {
    case straight
    case orthogonal
    case bezier
}

public enum GrammarGraphDirection: String, Hashable, Codable, Sendable, CaseIterable {
    case topToBottom
    case leftToRight
}

public struct GrammarGraphLayoutOptions: Hashable, Codable, Sendable {
    public var horizontalGap: Double
    public var verticalGap: Double
    public var relaxationPasses: Int
    public var crossingReductionSweeps: Int
    public var algorithm: GrammarGraphCoordinateAlgorithm
    public var routing: GrammarGraphRoutingStyle
    public var direction: GrammarGraphDirection
    public var margin: Double

    public init(
        horizontalGap: Double = 44, verticalGap: Double = 72,
        relaxationPasses: Int = 4, crossingReductionSweeps: Int = 4,
        algorithm: GrammarGraphCoordinateAlgorithm = .balancedAlignment,
        routing: GrammarGraphRoutingStyle = .bezier,
        direction: GrammarGraphDirection = .leftToRight,
        margin: Double = 36
    ) {
        self.horizontalGap = horizontalGap
        self.verticalGap = verticalGap
        self.relaxationPasses = relaxationPasses
        self.crossingReductionSweeps = crossingReductionSweeps
        self.algorithm = algorithm
        self.routing = routing
        self.direction = direction
        self.margin = margin
    }
}

public struct GrammarGraphPoint: Hashable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct GrammarGraphRect: Hashable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

public struct GrammarGraphPositionedNode: Identifiable, Hashable, Codable, Sendable {
    public let node: GrammarGraphNode
    public let frame: GrammarGraphRect
    public var id: String { node.id }
}

public enum GrammarGraphPathSegment: Hashable, Codable, Sendable {
    case line(start: GrammarGraphPoint, end: GrammarGraphPoint)
    case cubicCurve(
        start: GrammarGraphPoint, control1: GrammarGraphPoint,
        control2: GrammarGraphPoint, end: GrammarGraphPoint
    )
}

public struct GrammarGraphArrowhead: Hashable, Codable, Sendable {
    public let tip: GrammarGraphPoint
    public let angle: Double
    public let left: GrammarGraphPoint
    public let right: GrammarGraphPoint
}

public struct GrammarGraphRoute: Identifiable, Hashable, Codable, Sendable {
    public let edge: GrammarGraphEdge
    public let points: [GrammarGraphPoint]
    public let segments: [GrammarGraphPathSegment]
    public let arrowhead: GrammarGraphArrowhead?
    public let labelPosition: GrammarGraphPoint?
    public let isReversed: Bool
    public let isSelfLoop: Bool
    public var id: String { edge.id }

    public init(
        edge: GrammarGraphEdge, points: [GrammarGraphPoint],
        segments: [GrammarGraphPathSegment] = [],
        arrowhead: GrammarGraphArrowhead? = nil,
        labelPosition: GrammarGraphPoint? = nil,
        isReversed: Bool, isSelfLoop: Bool
    ) {
        self.edge = edge
        self.points = points
        self.segments = segments
        self.arrowhead = arrowhead
        self.labelPosition = labelPosition
        self.isReversed = isReversed
        self.isSelfLoop = isSelfLoop
    }
}

public struct GrammarGraphLayoutMetrics: Hashable, Codable, Sendable {
    public let engine: String
    public let nodeCount: Int
    public let edgeCount: Int
    public let reversedEdgeCount: Int
    public let selfLoopCount: Int
    public let durationMilliseconds: Double
}

public struct GrammarGraphLayoutSnapshot: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let graphID: String
    public let title: String
    public let nodes: [GrammarGraphPositionedNode]
    public let routes: [GrammarGraphRoute]
    public let width: Double
    public let height: Double
    public let options: GrammarGraphLayoutOptions
    public let metrics: GrammarGraphLayoutMetrics

    public init(
        graphID: String, title: String,
        nodes: [GrammarGraphPositionedNode], routes: [GrammarGraphRoute],
        width: Double, height: Double, options: GrammarGraphLayoutOptions,
        metrics: GrammarGraphLayoutMetrics
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.graphID = graphID
        self.title = title
        self.nodes = nodes
        self.routes = routes
        self.width = width
        self.height = height
        self.options = options
        self.metrics = metrics
    }
}

public enum GrammarGraphLayoutError: Error, LocalizedError, Sendable {
    case duplicateNode(String)
    case duplicateEdge(String)
    case danglingEdge(edge: String, node: String)
    case invalidNodeSize(String)
    case invalidOptions(String)
    case unavailable(String)
    case engine(String)
    case incompleteResult(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateNode(let id): "Graph node ‘\(id)’ is duplicated."
        case .duplicateEdge(let id): "Graph edge ‘\(id)’ is duplicated."
        case .danglingEdge(let edge, let node): "Graph edge ‘\(edge)’ references unknown node ‘\(node)’."
        case .invalidNodeSize(let id): "Graph node ‘\(id)’ has an invalid size."
        case .invalidOptions(let value): "Graph layout option ‘\(value)’ is invalid."
        case .unavailable(let platform): "Graph layout is unavailable on \(platform); portable graph interchange remains available."
        case .engine(let message): "The graph layout engine failed: \(message)"
        case .incompleteResult(let id): "The graph layout engine omitted node or edge ‘\(id)’."
        }
    }
}

public enum GrammarGraphLayoutAvailability: String, Hashable, Codable, Sendable {
    case swiftLayout
    case interchangeOnly
}

/// Rust-backed Sugiyama layout hidden behind stable, Codable Workbench types.
public enum GrammarGraphLayoutEngine {
    public static var availability: GrammarGraphLayoutAvailability {
#if canImport(SwiftLayout)
        .swiftLayout
#else
        .interchangeOnly
#endif
    }

    public static func layout(
        _ graph: GrammarGraph,
        options: GrammarGraphLayoutOptions = .init()
    ) throws -> GrammarGraphLayoutSnapshot {
        try validate(graph, options: options)
#if canImport(SwiftLayout)
        guard !graph.nodes.isEmpty else {
            return .init(
                graphID: graph.id, title: graph.title, nodes: [], routes: [],
                width: 640, height: 360, options: options,
                metrics: .init(
                    engine: "rust-sugiyama", nodeCount: 0, edgeCount: 0,
                    reversedEdgeCount: 0, selfLoopCount: 0, durationMilliseconds: 0
                )
            )
        }
        let orderedNodes = graph.nodes.sorted { $0.id < $1.id }
        let externalID = Dictionary(uniqueKeysWithValues: orderedNodes.enumerated().map {
            ($0.element.id, UInt64($0.offset))
        })
        let byExternalID = Dictionary(uniqueKeysWithValues: externalID.map { ($0.value, $0.key) })
        let started = ContinuousClock.now
        let result: FfiLayoutResult
        let routing: FfiRoutingStyle
        switch options.routing {
        case .straight: routing = .straight
        case .orthogonal: routing = .orthogonal
        case .bezier: routing = .bezier
        }
        do {
            result = try SwiftLayout.layout(
                nodes: orderedNodes.map {
                    FfiNode(
                        id: externalID[$0.id]!, width: Float($0.width), height: Float($0.height)
                    )
                },
                edges: graph.edges.map { edge in
                    let measuredWidth = edge.metadata["geometry.labelWidth"].flatMap(Float.init)
                    let measuredHeight = edge.metadata["geometry.labelHeight"].flatMap(Float.init)
                    return FfiEdge(
                        from: externalID[edge.source]!, to: externalID[edge.target]!,
                        labelWidth: edge.label.map { measuredWidth ?? Float(max(24, $0.count * 7)) },
                        labelHeight: edge.label == nil ? nil : measuredHeight ?? 18
                    )
                },
                config: FfiConfig(
                    hGap: Float(options.horizontalGap), vGap: Float(options.verticalGap),
                    relaxPasses: UInt32(options.relaxationPasses),
                    sweeps: UInt32(options.crossingReductionSweeps),
                    algorithm: options.algorithm == .medianRelaxation ? .medianRelax : .brandesKopf,
                    routing: routing,
                    direction: options.direction == .topToBottom ? .topToBottom : .leftToRight
                )
            )
        } catch {
            throw GrammarGraphLayoutError.engine(error.localizedDescription)
        }
        let duration = started.duration(to: .now)
        let milliseconds = Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
        let positionByID = Dictionary(uniqueKeysWithValues: result.positions.map { ($0.id, $0) })
        let margin = options.margin
        var positioned: [GrammarGraphPositionedNode] = []
        for node in orderedNodes {
            let id = externalID[node.id]!
            guard let position = positionByID[id] else {
                throw GrammarGraphLayoutError.incompleteResult(node.id)
            }
            positioned.append(.init(
                node: node,
                frame: .init(
                    x: Double(position.x) - node.width / 2 + margin,
                    y: Double(position.y) - node.height / 2 + margin,
                    width: node.width, height: node.height
                )
            ))
        }
        let pair = { (from: UInt64, to: UInt64) in "\(from)\u{1f}\(to)" }
        var edgesByPair = Dictionary(grouping: graph.edges) {
            pair(externalID[$0.source]!, externalID[$0.target]!)
        }
        for key in edgesByPair.keys { edgesByPair[key]?.sort { $0.id < $1.id } }
        func takeEdge(from: UInt64, to: UInt64) throws -> GrammarGraphEdge {
            let key = pair(from, to)
            guard var candidates = edgesByPair[key], !candidates.isEmpty else {
                throw GrammarGraphLayoutError.incompleteResult("\(byExternalID[from] ?? "?")->\(byExternalID[to] ?? "?")")
            }
            let edge = candidates.removeFirst()
            edgesByPair[key] = candidates
            return edge
        }
        var routes: [GrammarGraphRoute] = []
        for route in result.routes {
            let edge = try takeEdge(from: route.from, to: route.to)
            routes.append(.init(
                edge: edge,
                points: route.waypoints.map {
                    .init(x: Double($0.x) + margin, y: Double($0.y) + margin)
                },
                segments: route.segments.map { segment in
                    switch segment {
                    case .line(let start, let end):
                        return .line(
                            start: point(start, margin: margin), end: point(end, margin: margin)
                        )
                    case .cubicCurve(let start, let control1, let control2, let end):
                        return .cubicCurve(
                            start: point(start, margin: margin),
                            control1: point(control1, margin: margin),
                            control2: point(control2, margin: margin),
                            end: point(end, margin: margin)
                        )
                    }
                },
                arrowhead: route.arrowhead.map {
                    .init(
                        tip: point($0.tip, margin: margin), angle: Double($0.angle),
                        left: point($0.left, margin: margin), right: point($0.right, margin: margin)
                    )
                },
                labelPosition: route.labelPosition.map { point($0, margin: margin) },
                isReversed: route.reversed, isSelfLoop: route.isSelfLoop
            ))
        }
        let nodeByID = Dictionary(uniqueKeysWithValues: positioned.map { ($0.id, $0) })
        for loop in result.selfLoops where !(edgesByPair[pair(loop.from, loop.to)]?.isEmpty ?? true) {
            let edge = try takeEdge(from: loop.from, to: loop.to)
            guard let id = byExternalID[loop.from], let node = nodeByID[id] else {
                throw GrammarGraphLayoutError.incompleteResult(edge.id)
            }
            let f = node.frame
            routes.append(.init(
                edge: edge,
                points: [
                    .init(x: f.midX - 12, y: f.minY),
                    .init(x: f.midX - 28, y: f.minY - 28),
                    .init(x: f.midX + 28, y: f.minY - 28),
                    .init(x: f.midX + 12, y: f.minY)
                ],
                segments: [], arrowhead: nil, labelPosition: nil,
                isReversed: false, isSelfLoop: true
            ))
        }
        if let remainder = edgesByPair.values.flatMap({ $0 }).first {
            throw GrammarGraphLayoutError.incompleteResult(remainder.id)
        }
        let routePoints = routes.flatMap(\.points)
            + routes.compactMap(\.arrowhead).flatMap { [$0.tip, $0.left, $0.right] }
        let minX = min(0, min(positioned.map(\.frame.minX).min() ?? 0, routePoints.map(\.x).min() ?? 0))
        let minY = min(0, min(positioned.map(\.frame.minY).min() ?? 0, routePoints.map(\.y).min() ?? 0))
        let translationX = minX < 0 ? -minX + margin : 0
        let translationY = minY < 0 ? -minY + margin : 0
        if translationX != 0 || translationY != 0 {
            positioned = positioned.map {
                .init(node: $0.node, frame: .init(
                    x: $0.frame.x + translationX, y: $0.frame.y + translationY,
                    width: $0.frame.width, height: $0.frame.height
                ))
            }
            routes = routes.map {
                .init(
                    edge: $0.edge,
                    points: $0.points.map { .init(x: $0.x + translationX, y: $0.y + translationY) },
                    segments: $0.segments.map { translated($0, x: translationX, y: translationY) },
                    arrowhead: $0.arrowhead.map {
                        .init(
                            tip: translated($0.tip, x: translationX, y: translationY), angle: $0.angle,
                            left: translated($0.left, x: translationX, y: translationY),
                            right: translated($0.right, x: translationX, y: translationY)
                        )
                    },
                    labelPosition: $0.labelPosition.map { translated($0, x: translationX, y: translationY) },
                    isReversed: $0.isReversed, isSelfLoop: $0.isSelfLoop
                )
            }
        }
        let finalRoutePoints = routes.flatMap(\.points)
            + routes.compactMap(\.arrowhead).flatMap { [$0.tip, $0.left, $0.right] }
        let width = max(
            640, max(positioned.map(\.frame.maxX).max() ?? 0, finalRoutePoints.map(\.x).max() ?? 0)
        ) + margin
        let height = max(
            360, max(positioned.map(\.frame.maxY).max() ?? 0, finalRoutePoints.map(\.y).max() ?? 0)
        ) + margin
        return .init(
            graphID: graph.id, title: graph.title,
            nodes: positioned, routes: routes.sorted { $0.id < $1.id },
            width: width, height: height, options: options,
            metrics: .init(
                engine: "rust-sugiyama", nodeCount: graph.nodes.count,
                edgeCount: graph.edges.count,
                reversedEdgeCount: routes.count { $0.isReversed },
                selfLoopCount: routes.count { $0.isSelfLoop },
                durationMilliseconds: milliseconds
            )
        )
#else
        throw GrammarGraphLayoutError.unavailable("this platform")
#endif
    }

    private static func validate(
        _ graph: GrammarGraph, options: GrammarGraphLayoutOptions
    ) throws {
        var nodes: Set<String> = []
        for node in graph.nodes {
            guard nodes.insert(node.id).inserted else { throw GrammarGraphLayoutError.duplicateNode(node.id) }
            guard node.width.isFinite, node.height.isFinite, node.width > 0, node.height > 0 else {
                throw GrammarGraphLayoutError.invalidNodeSize(node.id)
            }
        }
        var edges: Set<String> = []
        for edge in graph.edges {
            guard edges.insert(edge.id).inserted else { throw GrammarGraphLayoutError.duplicateEdge(edge.id) }
            guard nodes.contains(edge.source) else { throw GrammarGraphLayoutError.danglingEdge(edge: edge.id, node: edge.source) }
            guard nodes.contains(edge.target) else { throw GrammarGraphLayoutError.danglingEdge(edge: edge.id, node: edge.target) }
            for key in ["geometry.labelWidth", "geometry.labelHeight"] {
                if let raw = edge.metadata[key],
                   (Double(raw).map { !$0.isFinite || $0 <= 0 } ?? true) {
                    throw GrammarGraphLayoutError.invalidOptions("\(key):\(edge.id)")
                }
            }
        }
        guard options.horizontalGap.isFinite, options.horizontalGap >= 0 else {
            throw GrammarGraphLayoutError.invalidOptions("horizontalGap")
        }
        guard options.verticalGap.isFinite, options.verticalGap >= 0 else {
            throw GrammarGraphLayoutError.invalidOptions("verticalGap")
        }
        guard options.margin.isFinite, options.margin >= 0 else {
            throw GrammarGraphLayoutError.invalidOptions("margin")
        }
        guard (0...64).contains(options.relaxationPasses) else {
            throw GrammarGraphLayoutError.invalidOptions("relaxationPasses")
        }
        guard (0...64).contains(options.crossingReductionSweeps) else {
            throw GrammarGraphLayoutError.invalidOptions("crossingReductionSweeps")
        }
    }

#if canImport(SwiftLayout)
    private static func point(_ value: FfiPoint, margin: Double) -> GrammarGraphPoint {
        .init(x: Double(value.x) + margin, y: Double(value.y) + margin)
    }
#endif

    private static func translated(
        _ point: GrammarGraphPoint, x: Double, y: Double
    ) -> GrammarGraphPoint { .init(x: point.x + x, y: point.y + y) }

    private static func translated(
        _ segment: GrammarGraphPathSegment, x: Double, y: Double
    ) -> GrammarGraphPathSegment {
        switch segment {
        case .line(let start, let end):
            .line(start: translated(start, x: x, y: y), end: translated(end, x: x, y: y))
        case .cubicCurve(let start, let control1, let control2, let end):
            .cubicCurve(
                start: translated(start, x: x, y: y),
                control1: translated(control1, x: x, y: y),
                control2: translated(control2, x: x, y: y),
                end: translated(end, x: x, y: y)
            )
        }
    }
}

/// Bounded cache for repeated UI and export requests. Layout is synchronous at
/// the FFI boundary but isolated by this actor from concurrent host callers.
public actor GrammarGraphLayoutService {
    private struct Request: Hashable { let graph: GrammarGraph; let options: GrammarGraphLayoutOptions }
    private var cache: [Request: GrammarGraphLayoutSnapshot] = [:]
    private var recency: [Request] = []
    public let capacity: Int

    public init(capacity: Int = 16) { self.capacity = max(1, capacity) }

    public func layout(
        _ graph: GrammarGraph, options: GrammarGraphLayoutOptions = .init()
    ) throws -> GrammarGraphLayoutSnapshot {
        let request = Request(graph: graph, options: options)
        if let value = cache[request] { touch(request); return value }
        let value = try GrammarGraphLayoutEngine.layout(graph, options: options)
        cache[request] = value
        touch(request)
        while recency.count > capacity {
            cache[recency.removeFirst()] = nil
        }
        return value
    }

    public func removeAll() { cache.removeAll(); recency.removeAll() }
    public var cachedLayoutCount: Int { cache.count }

    private func touch(_ request: Request) {
        recency.removeAll { $0 == request }
        recency.append(request)
    }
}

// MARK: - Grammar-domain adapters

public extension GrammarGraph {
    internal static func automaton(
        _ artifact: GrammarArtifact, compact: Bool = false,
        visibleStates: Set<StateID>? = nil
    ) -> Self {
        let allowed = visibleStates ?? Set(artifact.states.map(\.id))
        let states = artifact.states.filter { allowed.contains($0.id) }
        let nodes = states.map { state in
            let summary = artifact.decisionSummary(for: state.id)
            return GrammarGraphNode(
                id: "state:\(state.id.rawValue)", label: state.id.description,
                detail: compact ? "\(state.items.count) items" : state.items.prefix(4).map(\.text).joined(separator: "\n"),
                kind: .state, width: compact ? 116 : 250, height: compact ? 50 : 112,
                metadata: [
                    "state": String(state.id.rawValue),
                    "items": String(state.items.count),
                    "decisionDisposition": summary?.disposition.rawValue ?? "none",
                    "decisions": String(summary?.decisions.count ?? 0)
                ]
            )
        }
        let edges = artifact.transitions.enumerated().compactMap { index, transition -> GrammarGraphEdge? in
            guard allowed.contains(transition.from), allowed.contains(transition.to) else { return nil }
            return .init(
                id: "transition:\(index):\(transition.from.rawValue):\(transition.to.rawValue)",
                source: "state:\(transition.from.rawValue)",
                target: "state:\(transition.to.rawValue)", label: transition.symbol,
                metadata: ["symbol": transition.symbol]
            )
        }
        return .init(id: "lr-automaton", title: "LR automaton", nodes: nodes, edges: edges)
    }

    static func syntaxTree(_ root: GrammarSyntaxNode, id: String = "syntax-tree") -> Self {
        var nodes: [GrammarGraphNode] = []
        var edges: [GrammarGraphEdge] = []
        func visit(_ node: GrammarSyntaxNode, path: String) {
            let detail = node.token?.lexeme ?? node.production.map { "Production \($0)" }
            nodes.append(.init(
                id: path, label: node.symbol, detail: detail, kind: .syntax,
                width: max(92, Double(max(node.symbol.count, detail?.count ?? 0) * 7 + 24)),
                height: detail == nil ? 42 : 58,
                metadata: ["missing": String(node.isMissing)]
            ))
            for (index, child) in node.children.enumerated() {
                let childPath = "\(path).\(index)"
                edges.append(.init(id: "\(path)->\(childPath)", source: path, target: childPath))
                visit(child, path: childPath)
            }
        }
        visit(root, path: "root")
        return .init(id: id, title: "Syntax tree", nodes: nodes, edges: edges)
    }

    static func sharedForest(
        _ forest: GrammarSharedParseForest, id: String = "shared-parse-forest"
    ) -> Self {
        var nodes = forest.nodes.map { node in
            GrammarGraphNode(
                id: "symbol:\(node.id)", label: node.symbol,
                detail: "[\(node.span.lowerBound), \(node.span.upperBound)]",
                kind: .forest, width: 132, height: 58,
                metadata: ["forestNode": node.id, "families": String(node.families.count)]
            )
        }
        var edges: [GrammarGraphEdge] = []
        for node in forest.nodes {
            for family in node.families {
                let familyID = "packed:\(node.id):\(family.id)"
                nodes.append(.init(
                    id: familyID,
                    label: family.production.map { "Production \($0)" } ?? "Token",
                    detail: family.id, kind: .packed, width: 124, height: 52,
                    metadata: ["family": family.id]
                ))
                edges.append(.init(
                    id: "\(node.id)->\(family.id)", source: "symbol:\(node.id)", target: familyID
                ))
                for (index, child) in family.children.enumerated() {
                    edges.append(.init(
                        id: "\(family.id)->\(child):\(index)", source: familyID,
                        target: "symbol:\(child)"
                    ))
                }
            }
        }
        return .init(id: id, title: "Shared parse forest", nodes: nodes, edges: edges)
    }

    static func semanticDependencies(
        _ snapshot: GrammarSemanticWorkspaceSnapshot,
        id: String = "semantic-dependencies"
    ) -> Self {
        let documentIDs = Set(snapshot.occurrences.map { $0.location.documentID })
            .union(snapshot.dependencies.flatMap { [$0.sourceDocumentID, $0.targetDocumentID] })
        let paths = Dictionary(
            snapshot.occurrences.map { ($0.location.documentID, $0.location.path) },
            uniquingKeysWith: { first, _ in first }
        )
        let nodes = documentIDs.sorted().map {
            GrammarGraphNode(
                id: "document:\($0)", label: paths[$0] ?? $0,
                detail: $0, kind: .document, width: 180, height: 58
            )
        }
        let edges = snapshot.dependencies.map {
            GrammarGraphEdge(
                id: $0.id, source: "document:\($0.sourceDocumentID)",
                target: "document:\($0.targetDocumentID)",
                label: "\($0.symbolCount) symbol\($0.symbolCount == 1 ? "" : "s")"
            )
        }
        return .init(id: id, title: "Semantic dependencies", nodes: nodes, edges: edges)
    }
}

// MARK: - Portable SVG export

public enum GrammarGraphSVGRenderer {
    public static func render(
        _ snapshot: GrammarGraphLayoutSnapshot,
        selectedNodeID: String? = nil,
        interactive: Bool = false
    ) -> String {
        let routeMarkup = snapshot.routes.map { route in
            let path = route.segments.isEmpty
                ? pathData(route.points, bezier: snapshot.options.routing == .bezier)
                : pathData(route.segments)
            let label = route.edge.label.flatMap { value -> String? in
                guard let point = route.labelPosition ?? route.points.dropFirst(route.points.count / 2).first else { return nil }
                return "<text class='edge-label' x='\(number(point.x))' y='\(number(point.y - 7))'>\(escape(value))</text>"
            } ?? ""
            return "<g class='edge\(route.isReversed ? " reversed" : "")'><path d='\(path)'/>\(label)</g>"
        }.joined()
        let nodeMarkup = snapshot.nodes.map { value in
            let frame = value.frame
            let detail = value.node.detail.map {
                "<text class='detail' x='\(number(frame.midX))' y='\(number(frame.midY + 17))'>\(escape($0.replacingOccurrences(of: "\n", with: " · ")))</text>"
            } ?? ""
            return """
            <g class='node kind-\(value.node.kind.rawValue)\(value.id == selectedNodeID ? " selected" : "")' data-node='\(escape(value.id))' role='button' aria-label='\(escape(value.node.label))'>
            <rect x='\(number(frame.x))' y='\(number(frame.y))' width='\(number(frame.width))' height='\(number(frame.height))' rx='10'/>
            <text class='label' x='\(number(frame.midX))' y='\(number(frame.midY - (value.node.detail == nil ? -5 : 3)))'>\(escape(value.node.label))</text>\(detail)</g>
            """
        }.joined()
        let controls = interactive
            ? "<div id='graph-controls'><button onclick='zoomBy(1.2)'>＋</button><button onclick='zoomBy(.83)'>−</button><button onclick='fitGraph()'>Fit</button></div>"
            : ""
        return """
        \(controls)<svg id='grammar-graph' xmlns='http://www.w3.org/2000/svg' viewBox='0 0 \(number(snapshot.width)) \(number(snapshot.height))' role='img' aria-label='\(escape(snapshot.title))'>
        <defs><marker id='graph-arrow' viewBox='0 0 10 10' refX='9' refY='5' markerWidth='6' markerHeight='6' orient='auto'><path d='M0 0 L10 5 L0 10z'/></marker></defs>
        <style>\(styles)</style><g id='edges'>\(routeMarkup)</g><g id='nodes'>\(nodeMarkup)</g></svg>
        """
    }

    public static let styles = """
    .edge path{fill:none;stroke:#8792a5;stroke-width:1.6;marker-end:url(#graph-arrow)}.edge.reversed path{stroke-dasharray:5 3}.edge-label{text-anchor:middle;font:11px system-ui;paint-order:stroke;stroke:#fff;stroke-width:5;fill:#4b5565}.node rect{fill:#f5f7fb;stroke:#718096;stroke-width:1.5}.node.kind-packed rect{fill:#fff2df;stroke:#d17a00}.node.kind-forest rect{fill:#eaf3ff;stroke:#3478c9}.node.kind-document rect{fill:#edf8ef;stroke:#39804c}.node.selected rect{stroke:#1266c5;stroke-width:4}.label{text-anchor:middle;font:700 13px system-ui;fill:#172033}.detail{text-anchor:middle;font:10px ui-monospace,monospace;fill:#596579}#graph-arrow path{fill:#8792a5}
    """

    private static func pathData(_ points: [GrammarGraphPoint], bezier: Bool) -> String {
        guard let first = points.first else { return "" }
        var value = "M \(number(first.x)) \(number(first.y))"
        if bezier, points.count >= 4, (points.count - 1).isMultiple(of: 3) {
            var index = 1
            while index + 2 < points.count {
                value += " C \(number(points[index].x)) \(number(points[index].y)) \(number(points[index + 1].x)) \(number(points[index + 1].y)) \(number(points[index + 2].x)) \(number(points[index + 2].y))"
                index += 3
            }
        } else {
            for point in points.dropFirst() { value += " L \(number(point.x)) \(number(point.y))" }
        }
        return value
    }

    private static func pathData(_ segments: [GrammarGraphPathSegment]) -> String {
        guard let first = segments.first else { return "" }
        let start: GrammarGraphPoint
        switch first {
        case .line(let value, _), .cubicCurve(let value, _, _, _): start = value
        }
        var path = "M \(number(start.x)) \(number(start.y))"
        for segment in segments {
            switch segment {
            case .line(_, let end):
                path += " L \(number(end.x)) \(number(end.y))"
            case .cubicCurve(_, let control1, let control2, let end):
                path += " C \(number(control1.x)) \(number(control1.y)) \(number(control2.x)) \(number(control2.y)) \(number(end.x)) \(number(end.y))"
            }
        }
        return path
    }

    private static func number(_ value: Double) -> String { String(format: "%.1f", value) }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

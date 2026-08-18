import Foundation

public enum GrammarGraphValidationSeverity: String, Hashable, Codable, Sendable {
    case warning
    case error
}

public enum GrammarGraphValidationCode: String, Hashable, Codable, Sendable {
    case duplicateNode, duplicateEdge, danglingSource, danglingTarget, invalidNodeSize
    case missingPositionedNode, unexpectedPositionedNode, missingRoute, unexpectedRoute
    case invalidCanvas, invalidNodeFrame, nodeOverlap, invalidRouteGeometry, edgeNodeIntersection
}

public struct GrammarGraphValidationIssue: Hashable, Codable, Sendable {
    public let severity: GrammarGraphValidationSeverity
    public let code: GrammarGraphValidationCode
    public let message: String
    public let nodeIDs: [String]
    public let edgeID: String?

    public init(
        severity: GrammarGraphValidationSeverity, code: GrammarGraphValidationCode,
        message: String, nodeIDs: [String] = [], edgeID: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.nodeIDs = nodeIDs
        self.edgeID = edgeID
    }
}

public struct GrammarGraphCorrectnessReport: Hashable, Codable, Sendable {
    public let graphID: String
    public let nodeCount: Int
    public let edgeCount: Int
    public let issues: [GrammarGraphValidationIssue]
    public var errorCount: Int { issues.count { $0.severity == .error } }
    public var warningCount: Int { issues.count { $0.severity == .warning } }
    public var isValid: Bool { errorCount == 0 }
}

/// Deterministic structural and geometric checks used by tests, automation and
/// Graphviz comparisons. Edge/node intersections are warnings because a
/// routing style may deliberately trade clearance for compactness.
public enum GrammarGraphValidator {
    public static func validate(_ graph: GrammarGraph) -> GrammarGraphCorrectnessReport {
        var issues: [GrammarGraphValidationIssue] = []
        var nodeIDs: Set<String> = []
        for node in graph.nodes {
            if !nodeIDs.insert(node.id).inserted {
                issues.append(issue(.duplicateNode, "Duplicate node identity ‘\(node.id)’.", nodes: [node.id]))
            }
            if !node.width.isFinite || !node.height.isFinite || node.width <= 0 || node.height <= 0 {
                issues.append(issue(.invalidNodeSize, "Node ‘\(node.id)’ has a non-finite or non-positive size.", nodes: [node.id]))
            }
        }
        var edgeIDs: Set<String> = []
        for edge in graph.edges {
            if !edgeIDs.insert(edge.id).inserted {
                issues.append(issue(.duplicateEdge, "Duplicate edge identity ‘\(edge.id)’.", edge: edge.id))
            }
            if !nodeIDs.contains(edge.source) {
                issues.append(issue(.danglingSource, "Edge ‘\(edge.id)’ has unknown source ‘\(edge.source)’.", nodes: [edge.source], edge: edge.id))
            }
            if !nodeIDs.contains(edge.target) {
                issues.append(issue(.danglingTarget, "Edge ‘\(edge.id)’ has unknown target ‘\(edge.target)’.", nodes: [edge.target], edge: edge.id))
            }
        }
        return report(graph, issues)
    }

    public static func validate(
        _ snapshot: GrammarGraphLayoutSnapshot, against graph: GrammarGraph
    ) -> GrammarGraphCorrectnessReport {
        var issues = validate(graph).issues
        let expectedNodes = Set(graph.nodes.map(\.id))
        let actualNodes = Set(snapshot.nodes.map(\.id))
        for id in expectedNodes.subtracting(actualNodes).sorted() {
            issues.append(issue(.missingPositionedNode, "Layout omitted node ‘\(id)’.", nodes: [id]))
        }
        for id in actualNodes.subtracting(expectedNodes).sorted() {
            issues.append(issue(.unexpectedPositionedNode, "Layout returned unknown node ‘\(id)’.", nodes: [id]))
        }
        let expectedEdges = Set(graph.edges.map(\.id))
        let actualEdges = Set(snapshot.routes.map(\.id))
        for id in expectedEdges.subtracting(actualEdges).sorted() {
            issues.append(issue(.missingRoute, "Layout omitted edge ‘\(id)’.", edge: id))
        }
        for id in actualEdges.subtracting(expectedEdges).sorted() {
            issues.append(issue(.unexpectedRoute, "Layout returned unknown edge ‘\(id)’.", edge: id))
        }
        if !snapshot.width.isFinite || !snapshot.height.isFinite || snapshot.width <= 0 || snapshot.height <= 0 {
            issues.append(issue(.invalidCanvas, "Layout canvas is non-finite or non-positive."))
        }
        for node in snapshot.nodes where !finite(node.frame) || node.frame.width <= 0 || node.frame.height <= 0 {
            issues.append(issue(.invalidNodeFrame, "Node ‘\(node.id)’ has invalid positioned geometry.", nodes: [node.id]))
        }
        for index in snapshot.nodes.indices {
            for other in snapshot.nodes.indices where other > index {
                let lhs = snapshot.nodes[index], rhs = snapshot.nodes[other]
                if intersects(lhs.frame, rhs.frame) {
                    issues.append(issue(.nodeOverlap, "Nodes ‘\(lhs.id)’ and ‘\(rhs.id)’ overlap.", nodes: [lhs.id, rhs.id]))
                }
            }
        }
        for route in snapshot.routes {
            if !routeGeometry(route).allSatisfy(finite) {
                issues.append(issue(.invalidRouteGeometry, "Edge ‘\(route.id)’ contains non-finite geometry.", edge: route.id))
                continue
            }
            guard !route.isSelfLoop else { continue }
            for segment in lineSegments(route) {
                for node in snapshot.nodes where node.id != route.edge.source && node.id != route.edge.target {
                    if segmentIntersectsInterior(segment.0, segment.1, node.frame) {
                        issues.append(.init(
                            severity: .warning, code: .edgeNodeIntersection,
                            message: "Edge ‘\(route.id)’ crosses node ‘\(node.id)’.",
                            nodeIDs: [node.id], edgeID: route.id
                        ))
                    }
                }
            }
        }
        return report(graph, issues)
    }

    private static func report(_ graph: GrammarGraph, _ issues: [GrammarGraphValidationIssue]) -> GrammarGraphCorrectnessReport {
        .init(
            graphID: graph.id, nodeCount: graph.nodes.count, edgeCount: graph.edges.count,
            issues: issues.sorted {
                ($0.severity.rawValue, $0.code.rawValue, $0.edgeID ?? "", $0.nodeIDs.joined())
                    < ($1.severity.rawValue, $1.code.rawValue, $1.edgeID ?? "", $1.nodeIDs.joined())
            }
        )
    }

    private static func issue(
        _ code: GrammarGraphValidationCode, _ message: String,
        nodes: [String] = [], edge: String? = nil
    ) -> GrammarGraphValidationIssue {
        .init(severity: .error, code: code, message: message, nodeIDs: nodes, edgeID: edge)
    }

    private static func finite(_ point: GrammarGraphPoint) -> Bool { point.x.isFinite && point.y.isFinite }
    private static func finite(_ rect: GrammarGraphRect) -> Bool {
        rect.x.isFinite && rect.y.isFinite && rect.width.isFinite && rect.height.isFinite
    }
    private static func intersects(_ a: GrammarGraphRect, _ b: GrammarGraphRect) -> Bool {
        a.minX < b.maxX && a.maxX > b.minX && a.minY < b.maxY && a.maxY > b.minY
    }
    private static func routeGeometry(_ route: GrammarGraphRoute) -> [GrammarGraphPoint] {
        var result = route.points
        for segment in route.segments {
            switch segment {
            case .line(let a, let b): result += [a, b]
            case .cubicCurve(let a, let b, let c, let d): result += [a, b, c, d]
            }
        }
        if let arrow = route.arrowhead { result += [arrow.tip, arrow.left, arrow.right] }
        if let label = route.labelPosition { result.append(label) }
        return result
    }
    private static func lineSegments(_ route: GrammarGraphRoute) -> [(GrammarGraphPoint, GrammarGraphPoint)] {
        let explicit = route.segments.compactMap { segment -> (GrammarGraphPoint, GrammarGraphPoint)? in
            if case .line(let a, let b) = segment { return (a, b) }
            return nil
        }
        if !route.segments.isEmpty { return explicit }
        return zip(route.points, route.points.dropFirst()).map { ($0, $1) }
    }
    private static func segmentIntersectsInterior(
        _ a: GrammarGraphPoint, _ b: GrammarGraphPoint, _ rect: GrammarGraphRect
    ) -> Bool {
        let epsilon = 0.01
        let minX = rect.minX + epsilon, maxX = rect.maxX - epsilon
        let minY = rect.minY + epsilon, maxY = rect.maxY - epsilon
        var t0 = 0.0, t1 = 1.0
        let dx = b.x - a.x, dy = b.y - a.y
        for (p, q) in [(-dx, a.x - minX), (dx, maxX - a.x), (-dy, a.y - minY), (dy, maxY - a.y)] {
            if p == 0 { if q < 0 { return false } }
            else {
                let t = q / p
                if p < 0 { if t > t1 { return false }; t0 = max(t0, t) }
                else { if t < t0 { return false }; t1 = min(t1, t) }
            }
        }
        return t0 <= t1
    }
}

public struct GrammarGraphMeasurement: Hashable, Codable, Sendable {
    public let inputValidationNanoseconds: UInt64
    public let layoutBoundaryNanoseconds: UInt64
    public let engineReportedNanoseconds: UInt64
    public let outputValidationNanoseconds: UInt64
    public let totalNanoseconds: UInt64
    public var integrationOverheadNanoseconds: UInt64 {
        totalNanoseconds > inputValidationNanoseconds + layoutBoundaryNanoseconds + outputValidationNanoseconds
            ? totalNanoseconds - inputValidationNanoseconds - layoutBoundaryNanoseconds - outputValidationNanoseconds : 0
    }
}

public struct GrammarGraphMeasuredLayout: Hashable, Codable, Sendable {
    public let snapshot: GrammarGraphLayoutSnapshot
    public let correctness: GrammarGraphCorrectnessReport
    public let measurement: GrammarGraphMeasurement
}

public enum GrammarGraphMeasurementRunner {
    public static func layout(
        _ graph: GrammarGraph, options: GrammarGraphLayoutOptions = .init()
    ) throws -> GrammarGraphMeasuredLayout {
        let totalStart = ContinuousClock.now
        let inputStart = ContinuousClock.now
        _ = GrammarGraphValidator.validate(graph)
        let input = nanoseconds(inputStart.duration(to: .now))
        let layoutStart = ContinuousClock.now
        let snapshot = try GrammarGraphLayoutEngine.layout(graph, options: options)
        let boundary = nanoseconds(layoutStart.duration(to: .now))
        let outputStart = ContinuousClock.now
        let report = GrammarGraphValidator.validate(snapshot, against: graph)
        let output = nanoseconds(outputStart.duration(to: .now))
        return .init(
            snapshot: snapshot, correctness: report,
            measurement: .init(
                inputValidationNanoseconds: input, layoutBoundaryNanoseconds: boundary,
                engineReportedNanoseconds: UInt64(max(0, snapshot.metrics.durationMilliseconds) * 1_000_000),
                outputValidationNanoseconds: output,
                totalNanoseconds: nanoseconds(totalStart.duration(to: .now))
            )
        )
    }

    private static func nanoseconds(_ duration: Duration) -> UInt64 {
        let value = duration.components
        return UInt64(max(0, value.seconds)) * 1_000_000_000
            + UInt64(max(0, value.attoseconds / 1_000_000_000))
    }
}

public enum GrammarGraphDOTRenderer {
    public static func render(_ graph: GrammarGraph, options: GrammarGraphLayoutOptions = .init()) -> String {
        let rank = options.direction == .leftToRight ? "LR" : "TB"
        let splines = switch options.routing { case .straight: "line"; case .orthogonal: "ortho"; case .bezier: "spline" }
        var lines = ["digraph \(quoted(graph.id)) {", "  graph [rankdir=\(rank), splines=\(splines), label=\(quoted(graph.title)), labelloc=t];"]
        for node in graph.nodes.sorted(by: { $0.id < $1.id }) {
            let shape = switch node.kind { case .packed: "diamond"; case .forest: "ellipse"; case .document: "folder"; default: "box" }
            let label = node.detail.map { "\(node.label)\\n\($0)" } ?? node.label
            lines.append("  \(quoted(node.id)) [label=\(quoted(label)), shape=\(shape), width=\(format(node.width / 72)), height=\(format(node.height / 72))];")
        }
        for edge in graph.edges.sorted(by: { $0.id < $1.id }) {
            var attributes = ["id=\(quoted(edge.id))"]
            if let label = edge.label { attributes.append("label=\(quoted(label))") }
            lines.append("  \(quoted(edge.source)) -> \(quoted(edge.target)) [\(attributes.joined(separator: ", "))];")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
    private static func format(_ value: Double) -> String { String(format: "%.3f", value) }
}

public struct GrammarGraphCorpusConfiguration: Hashable, Codable, Sendable {
    public var seed: UInt64
    public var caseCount: Int
    public var maximumNodes: Int
    public var edgeProbabilityPercent: Int
    public init(seed: UInt64 = 0x4752415048, caseCount: Int = 32, maximumNodes: Int = 24, edgeProbabilityPercent: Int = 18) {
        self.seed = seed; self.caseCount = max(0, caseCount); self.maximumNodes = max(1, maximumNodes)
        self.edgeProbabilityPercent = min(100, max(0, edgeProbabilityPercent))
    }
}

/// Reproducible graph corpus with cycles, self-loops, parallel edges and
/// disconnected components. A failed seed can be recorded as a compact fixture.
public enum GrammarGraphCorpus {
    public static func generate(_ configuration: GrammarGraphCorpusConfiguration = .init()) -> [GrammarGraph] {
        var random = SplitMix64(state: configuration.seed)
        return (0..<configuration.caseCount).map { caseIndex in
            let count = 1 + Int(random.next() % UInt64(configuration.maximumNodes))
            let nodes = (0..<count).map { index in
                GrammarGraphNode(id: "n\(index)", label: "Node \(index)", width: Double(72 + random.next() % 121), height: Double(36 + random.next() % 61))
            }
            var edges: [GrammarGraphEdge] = []
            for source in 0..<count {
                for target in 0..<count where Int(random.next() % 100) < configuration.edgeProbabilityPercent {
                    edges.append(.init(id: "e\(edges.count)", source: "n\(source)", target: "n\(target)", label: edges.count.isMultiple(of: 3) ? "edge \(edges.count)" : nil))
                    if random.next() % 17 == 0 {
                        edges.append(.init(id: "e\(edges.count)", source: "n\(source)", target: "n\(target)"))
                    }
                }
            }
            return .init(id: "seed-\(configuration.seed)-case-\(caseIndex)", title: "Generated case \(caseIndex)", nodes: nodes, edges: edges)
        }
    }

    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }
    }
}

public enum GrammarGraphFailureMinimizer {
    /// Greedily removes edges and then unreferenced nodes while preserving a
    /// caller-defined failure. The result is deterministic, not globally minimal.
    public static func minimize(_ graph: GrammarGraph, preserving failure: (GrammarGraph) throws -> Bool) rethrows -> GrammarGraph {
        var candidate = graph
        for edge in candidate.edges.sorted(by: { $0.id < $1.id }) {
            let trial = GrammarGraph(id: candidate.id, title: candidate.title, nodes: candidate.nodes, edges: candidate.edges.filter { $0.id != edge.id })
            if try failure(trial) { candidate = trial }
        }
        for node in candidate.nodes.sorted(by: { $0.id < $1.id }) where !candidate.edges.contains(where: { $0.source == node.id || $0.target == node.id }) {
            let trial = GrammarGraph(id: candidate.id, title: candidate.title, nodes: candidate.nodes.filter { $0.id != node.id }, edges: candidate.edges)
            if try failure(trial) { candidate = trial }
        }
        return candidate
    }
}

import Foundation

public enum GrammarVisualAppearance: String, Hashable, Codable, Sendable, CaseIterable {
    case system, light, dark, highContrast
}

public enum GrammarVisualMotion: String, Hashable, Codable, Sendable {
    case standard, reduced
}

public struct GrammarVisualPreferences: Hashable, Codable, Sendable {
    public var appearance: GrammarVisualAppearance
    public var motion: GrammarVisualMotion
    public var showsMinimap: Bool
    public var showsEdgeLabels: Bool
    public var animationDurationMilliseconds: Int

    public init(
        appearance: GrammarVisualAppearance = .system,
        motion: GrammarVisualMotion = .standard,
        showsMinimap: Bool = true, showsEdgeLabels: Bool = true,
        animationDurationMilliseconds: Int = 220
    ) {
        self.appearance = appearance; self.motion = motion
        self.showsMinimap = showsMinimap; self.showsEdgeLabels = showsEdgeLabels
        self.animationDurationMilliseconds = motion == .reduced
            ? 0 : min(1_000, max(0, animationDurationMilliseconds))
    }
}

public struct GrammarVisualPalette: Hashable, Codable, Sendable {
    public let canvas: String
    public let surface: String
    public let surfaceRaised: String
    public let text: String
    public let secondaryText: String
    public let border: String
    public let accent: String
    public let success: String
    public let warning: String
    public let danger: String
    public let graphEdge: String
    public let active: String
}

public enum GrammarVisualDesignSystem {
    public static let schemaVersion = 1
    public static let minimumControlSize = 28.0
    public static let cornerRadius = 10.0
    public static let graphControlSpacing = 5.0

    public static func palette(for appearance: GrammarVisualAppearance) -> GrammarVisualPalette {
        switch appearance {
        case .dark:
            .init(
                canvas: "#11151c", surface: "#1b2230", surfaceRaised: "#242d3d",
                text: "#f2f5f9", secondaryText: "#aeb9c9", border: "#526176",
                accent: "#69aaf5", success: "#65c985", warning: "#f4b65d",
                danger: "#f27d78", graphEdge: "#9aa9bd", active: "#ffad5b"
            )
        case .highContrast:
            .init(
                canvas: "#ffffff", surface: "#ffffff", surfaceRaised: "#ffffff",
                text: "#000000", secondaryText: "#202020", border: "#000000",
                accent: "#0046b8", success: "#006b2f", warning: "#8a4b00",
                danger: "#a40000", graphEdge: "#000000", active: "#c43b00"
            )
        case .system, .light:
            .init(
                canvas: "#ffffff", surface: "#f5f7fb", surfaceRaised: "#ffffff",
                text: "#172033", secondaryText: "#596579", border: "#8792a5",
                accent: "#1266c5", success: "#2d8a50", warning: "#b86a00",
                danger: "#c43b32", graphEdge: "#718096", active: "#e05800"
            )
        }
    }

    public static func graphCSS(_ preferences: GrammarVisualPreferences = .init()) -> String {
        let p = palette(for: preferences.appearance)
        let dark = palette(for: .dark)
        let duration = preferences.motion == .reduced ? 0 : preferences.animationDurationMilliseconds
        let systemDark = preferences.appearance == .system ? """
        @media(prefers-color-scheme:dark){:root{--gw-canvas:\(dark.canvas);--gw-surface:\(dark.surface);--gw-raised:\(dark.surfaceRaised);--gw-text:\(dark.text);--gw-secondary:\(dark.secondaryText);--gw-border:\(dark.border);--gw-accent:\(dark.accent);--gw-success:\(dark.success);--gw-warning:\(dark.warning);--gw-danger:\(dark.danger);--gw-edge:\(dark.graphEdge);--gw-active:\(dark.active);color-scheme:dark}}
        """ : ""
        return """
        :root{--gw-canvas:\(p.canvas);--gw-surface:\(p.surface);--gw-raised:\(p.surfaceRaised);--gw-text:\(p.text);--gw-secondary:\(p.secondaryText);--gw-border:\(p.border);--gw-accent:\(p.accent);--gw-success:\(p.success);--gw-warning:\(p.warning);--gw-danger:\(p.danger);--gw-edge:\(p.graphEdge);--gw-active:\(p.active);--gw-motion:\(duration)ms;color-scheme:\(preferences.appearance == .dark ? "dark" : "light")}
        \(systemDark)
        html,body{background:var(--gw-canvas);color:var(--gw-text)}button,input{font:inherit}button{min-width:28px;min-height:28px;border:1px solid var(--gw-border);border-radius:7px;background:var(--gw-raised);color:var(--gw-text)}button:hover{border-color:var(--gw-accent)}button:focus-visible,input:focus-visible{outline:3px solid var(--gw-accent);outline-offset:2px}.node,.edge{transition:opacity var(--gw-motion),filter var(--gw-motion)}.edge path{stroke:var(--gw-edge)}.node text,.edge-label{fill:var(--gw-text)}
        @media(prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important;scroll-behavior:auto!important}}
        """
    }
}

public enum GrammarVisualSurface: String, Hashable, Codable, Sendable, CaseIterable {
    case sourceEditor, projectDashboard, automaton, parserTimeline, syntaxTree, sharedForest
}

public enum GrammarVisualAuditSeverity: String, Hashable, Codable, Sendable {
    case information, warning, error
}

public struct GrammarVisualAuditFinding: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let severity: GrammarVisualAuditSeverity
    public let surface: GrammarVisualSurface
    public let message: String
    public let elementID: String?
}

public struct GrammarVisualAuditReport: Hashable, Codable, Sendable {
    public let schemaVersion: Int
    public let findings: [GrammarVisualAuditFinding]
    public var errorCount: Int { findings.count { $0.severity == .error } }
    public var warningCount: Int { findings.count { $0.severity == .warning } }
    public var passes: Bool { errorCount == 0 }
}

public enum GrammarVisualProductAuditor {
    public static func audit(
        graph: GrammarGraph, timeline: GrammarParserVisualizationTimeline? = nil
    ) -> GrammarVisualAuditReport {
        var findings: [GrammarVisualAuditFinding] = []
        for node in graph.nodes where node.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            findings.append(.init(
                id: "unlabelled-node:\(node.id)", severity: .error, surface: .automaton,
                message: "Interactive graph nodes require an accessible label.", elementID: node.id
            ))
        }
        for edge in graph.edges where edge.source == edge.target && edge.label == nil {
            findings.append(.init(
                id: "unlabelled-loop:\(edge.id)", severity: .warning, surface: .automaton,
                message: "A self-loop without a label may be difficult to interpret.", elementID: edge.id
            ))
        }
        if let timeline {
            if timeline.frames.isEmpty {
                findings.append(.init(
                    id: "empty-timeline", severity: .warning, surface: .parserTimeline,
                    message: "The parser timeline has no steps to present.", elementID: nil
                ))
            }
            for frame in timeline.frames where frame.actionDescription.isEmpty {
                findings.append(.init(
                    id: "empty-action:\(frame.index)", severity: .error, surface: .parserTimeline,
                    message: "Every parser step requires an action description.", elementID: String(frame.index)
                ))
            }
        }
        return .init(
            schemaVersion: GrammarVisualDesignSystem.schemaVersion,
            findings: findings.sorted { $0.id < $1.id }
        )
    }
}

public struct GrammarVisualSnapshotEntry: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let surface: GrammarVisualSurface
    public let fingerprint: String
    public let byteCount: Int
    public let width: Double?
    public let height: Double?
}

public struct GrammarVisualSnapshotManifest: Hashable, Codable, Sendable {
    public let schemaVersion: Int
    public let designSystemVersion: Int
    public let entries: [GrammarVisualSnapshotEntry]
}

public enum GrammarVisualSnapshotBuilder {
    public static func make(
        graphSVG: String? = nil, parserHTML: String? = nil,
        graphSize: (width: Double, height: Double)? = nil
    ) -> GrammarVisualSnapshotManifest {
        var entries: [GrammarVisualSnapshotEntry] = []
        if let graphSVG {
            entries.append(.init(
                id: "graph-svg", surface: .automaton,
                fingerprint: fingerprint(graphSVG), byteCount: graphSVG.utf8.count,
                width: graphSize?.width, height: graphSize?.height
            ))
        }
        if let parserHTML {
            entries.append(.init(
                id: "parser-html", surface: .parserTimeline,
                fingerprint: fingerprint(parserHTML), byteCount: parserHTML.utf8.count,
                width: nil, height: nil
            ))
        }
        return .init(
            schemaVersion: 1, designSystemVersion: GrammarVisualDesignSystem.schemaVersion,
            entries: entries.sorted { $0.id < $1.id }
        )
    }

    private static func fingerprint(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 { hash ^= UInt64(byte); hash &*= 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
}

import Foundation

public enum GrammarWorkbenchNavigationSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case start = "Start"
    case grammar = "Grammar"
    case runAndDeliver = "Run & Deliver"
    case expert = "Expert"

    public var id: Self { self }
}

/// Platform-neutral top-level application navigation. Native shells may render
/// this as a macOS List, an adaptable tab sidebar, or an iPad split view.
public enum GrammarWorkbenchDestination: String, CaseIterable, Identifiable, Codable, Sendable {
    case guide
    case project
    case analysis
    case semantics
    case comparison
    case explore
    case diagram
    case decisions
    case sample
    case tests
    case generation
    case automaton
    case table
    case bootstrap
    case research
    case visuals

    public var id: Self { self }

    public var title: String {
        switch self {
        case .guide: "Guide"
        case .project: "Project"
        case .analysis: "Analysis"
        case .semantics: "Semantics"
        case .comparison: "Compare"
        case .explore: "Explore"
        case .diagram: "Diagram & REPL"
        case .decisions: "Decisions"
        case .sample: "Sample"
        case .tests: "Tests"
        case .generation: "Generate"
        case .automaton: "Automaton"
        case .table: "Table"
        case .bootstrap: "Bootstrap"
        case .research: "Research"
        case .visuals: "Visuals"
        }
    }

    public var systemImage: String {
        switch self {
        case .guide: "house"
        case .project: "folder"
        case .analysis: "chart.bar.xaxis"
        case .semantics: "curlybraces"
        case .comparison: "scale.3d"
        case .explore: "scope"
        case .diagram: "point.3.connected.trianglepath.dotted"
        case .decisions: "arrow.triangle.branch"
        case .sample: "play.circle"
        case .tests: "checklist"
        case .generation: "hammer"
        case .automaton: "circle.grid.cross"
        case .table: "tablecells"
        case .bootstrap: "arrow.triangle.2.circlepath"
        case .research: "flask"
        case .visuals: "paintpalette"
        }
    }

    public var section: GrammarWorkbenchNavigationSection {
        switch self {
        case .guide, .project: .start
        case .analysis, .semantics, .comparison, .explore, .diagram, .decisions: .grammar
        case .sample, .tests, .generation: .runAndDeliver
        case .automaton, .table, .bootstrap, .research, .visuals: .expert
        }
    }

    public static func destinations(
        in section: GrammarWorkbenchNavigationSection
    ) -> [GrammarWorkbenchDestination] {
        allCases.filter { $0.section == section }
    }
}

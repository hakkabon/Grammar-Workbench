import Foundation

public enum GrammarWorkbenchTabletFeature: String, CaseIterable, Codable, Sendable {
    case documentEditing
    case guide
    case analysis
    case samples
    case tests
    case diagrams
    case grammarREPL
    case generation
    case expertAutomaton
    case hostedAdministration
}

public enum GrammarWorkbenchTabletFeatureStatus: String, Codable, Sendable {
    case available
    case prototype
    case deferred
}

/// A platform-neutral contract for the first large-iPad product increment.
/// It lets release checks distinguish working tablet workflows from deliberately
/// deferred desktop-only surfaces.
public enum GrammarWorkbenchTabletFoundation {
    public static let minimumMajorOSVersion = 17

    public static func status(
        of feature: GrammarWorkbenchTabletFeature
    ) -> GrammarWorkbenchTabletFeatureStatus {
        switch feature {
        case .documentEditing, .guide, .analysis, .samples, .tests, .diagrams, .grammarREPL:
            .available
        case .generation:
            .prototype
        case .expertAutomaton, .hostedAdministration:
            .deferred
        }
    }

    public static var availableFeatures: [GrammarWorkbenchTabletFeature] {
        GrammarWorkbenchTabletFeature.allCases.filter { status(of: $0) == .available }
    }
}

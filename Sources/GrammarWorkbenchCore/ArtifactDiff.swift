import Foundation

public struct GrammarArtifactSize: Hashable, Codable, Sendable {
    public let states: Int
    public let transitions: Int
    public let tableEntries: Int
    public let decisions: Int
}

public struct GrammarArtifactDiff: Hashable, Codable, Sendable {
    public let previous: GrammarArtifactSize
    public let current: GrammarArtifactSize
    public let addedProductions: [String]
    public let removedProductions: [String]
    public let addedTerminals: [String]
    public let removedTerminals: [String]

    public var stateDelta: Int { current.states - previous.states }
    public var transitionDelta: Int { current.transitions - previous.transitions }
    public var tableEntryDelta: Int { current.tableEntries - previous.tableEntries }
    public var decisionDelta: Int { current.decisions - previous.decisions }
    public var isEmpty: Bool {
        previous == current && addedProductions.isEmpty && removedProductions.isEmpty
            && addedTerminals.isEmpty && removedTerminals.isEmpty
    }

    public init(previous: GrammarArtifactSnapshot, current: GrammarArtifactSnapshot) {
        self.previous = .init(
            states: previous.states.count, transitions: previous.transitions.count,
            tableEntries: previous.table.count, decisions: previous.decisions.count
        )
        self.current = .init(
            states: current.states.count, transitions: current.transitions.count,
            tableEntries: current.table.count, decisions: current.decisions.count
        )
        let previousProductions = Set(previous.productions.map(\.text))
        let currentProductions = Set(current.productions.map(\.text))
        addedProductions = currentProductions.subtracting(previousProductions).sorted()
        removedProductions = previousProductions.subtracting(currentProductions).sorted()
        let previousTerminals = Set(previous.terminals)
        let currentTerminals = Set(current.terminals)
        addedTerminals = currentTerminals.subtracting(previousTerminals).sorted()
        removedTerminals = previousTerminals.subtracting(currentTerminals).sorted()
    }
}

public extension GrammarCompilation {
    func diff(from previous: GrammarCompilation) throws -> GrammarArtifactDiff {
        guard let previousArtifact = previous.artifact else {
            throw GrammarWorkbenchAPIError.compilationFailed(
                previous.diagnostics.first?.message ?? "The previous grammar did not compile."
            )
        }
        guard let artifact else {
            throw GrammarWorkbenchAPIError.compilationFailed(
                diagnostics.first?.message ?? "The current grammar did not compile."
            )
        }
        return GrammarArtifactDiff(previous: previousArtifact, current: artifact)
    }
}

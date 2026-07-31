import Foundation

enum LRAlgorithm: String, CaseIterable, Codable, Identifiable, Sendable {
    case slr = "SLR(1)"
    case lalr = "LALR(1)"
    case canonical = "Canonical LR(1)"
    var id: Self { self }
}

struct StateID: Hashable, Codable, Identifiable, Sendable, CustomStringConvertible {
    let rawValue: Int
    var id: Int { rawValue }
    var description: String { "I\(rawValue)" }
}

struct ProductionID: Hashable, Codable, Identifiable, Sendable {
    let rawValue: Int
    var id: Int { rawValue }
}

struct CellID: Hashable, Codable, Identifiable, Sendable {
    let state: StateID
    let symbol: String
    var id: String { "\(state.rawValue):\(symbol)" }
}

struct DecisionID: Hashable, Codable, Identifiable, Sendable {
    let rawValue: String
    var id: String { rawValue }
}

enum ArtifactIdentity: Hashable, Sendable {
    case state(StateID)
    case production(ProductionID)
    case cell(CellID)
    case decision(DecisionID)
    case traceStep(Int)
}

struct Production: Identifiable, Codable, Sendable {
    let id: ProductionID
    let lhs: String
    let rhs: [String]
    var text: String { "\(lhs) → \(rhs.isEmpty ? "ε" : rhs.joined(separator: " "))" }
}

struct LRItem: Identifiable, Codable, Sendable {
    let id: String
    let production: ProductionID
    let text: String
}

struct AutomatonState: Identifiable, Codable, Sendable {
    let id: StateID
    let items: [LRItem]
}

struct Transition: Identifiable, Codable, Sendable {
    let from: StateID
    let symbol: String
    let to: StateID
    var id: String { "\(from.rawValue)-\(symbol)-\(to.rawValue)" }
}

enum TableAction: Hashable, Codable, Sendable {
    case shift(StateID)
    case reduce(ProductionID)
    case accept
    case goTo(StateID)

    var label: String {
        switch self {
        case .shift(let state): "s\(state.rawValue)"
        case .reduce(let production): "r\(production.rawValue)"
        case .accept: "acc"
        case .goTo(let state): "\(state.rawValue)"
        }
    }
}

struct TableCell: Identifiable, Codable, Sendable {
    let id: CellID
    let actions: [TableAction]
    var isConflict: Bool { actions.count > 1 }
}

struct ReplayFrame: Identifiable, Codable, Sendable {
    let index: Int
    let stack: [String]
    let remainingInput: [String]
    let action: String
    let state: StateID?
    let cell: CellID?
    let production: ProductionID?
    var id: Int { index }

    init(
        index: Int,
        stack: [String],
        remainingInput: [String],
        action: String,
        state: StateID?,
        cell: CellID? = nil,
        production: ProductionID? = nil
    ) {
        self.index = index
        self.stack = stack
        self.remainingInput = remainingInput
        self.action = action
        self.state = state
        self.cell = cell
        self.production = production
    }
}

struct ConflictDecision: Identifiable, Codable, Sendable {
    let id: DecisionID
    let cell: CellID
    let title: String
    let explanation: String
    let witness: [String]
    let branches: [[ReplayFrame]]
}

struct ParseSample: Codable, Sendable {
    let input: String
    let tree: String
    let trace: [ReplayFrame]
}

struct GrammarArtifact: Codable, Sendable {
    let algorithm: LRAlgorithm
    let grammarSource: String
    let terminals: [String]
    let nonterminals: [String]
    let productions: [Production]
    let states: [AutomatonState]
    let transitions: [Transition]
    let cells: [TableCell]
    let decisions: [ConflictDecision]
    let sample: ParseSample

    func state(_ id: StateID) -> AutomatonState? { states.first { $0.id == id } }
    func cell(_ id: CellID) -> TableCell? { cells.first { $0.id == id } }
    func decision(_ id: DecisionID) -> ConflictDecision? { decisions.first { $0.id == id } }
}

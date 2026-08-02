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
    let provenance: ConflictProvenance?
    let branchAnalyses: [ConflictBranchAnalysis]
    let isExpected: Bool
    let candidateActions: [TableAction]

    init(
        id: DecisionID,
        cell: CellID,
        title: String,
        explanation: String,
        witness: [String],
        branches: [[ReplayFrame]],
        provenance: ConflictProvenance? = nil,
        branchAnalyses: [ConflictBranchAnalysis] = [],
        isExpected: Bool = false,
        candidateActions: [TableAction] = []
    ) {
        self.id = id
        self.cell = cell
        self.title = title
        self.explanation = explanation
        self.witness = witness
        self.branches = branches
        self.provenance = provenance
        self.branchAnalyses = branchAnalyses
        self.isExpected = isExpected
        self.candidateActions = candidateActions
    }

    private enum CodingKeys: String, CodingKey {
        case id, cell, title, explanation, witness, branches, provenance, branchAnalyses, isExpected, candidateActions
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(DecisionID.self, forKey: .id),
            cell: try values.decode(CellID.self, forKey: .cell),
            title: try values.decode(String.self, forKey: .title),
            explanation: try values.decode(String.self, forKey: .explanation),
            witness: try values.decode([String].self, forKey: .witness),
            branches: try values.decode([[ReplayFrame]].self, forKey: .branches),
            provenance: try values.decodeIfPresent(ConflictProvenance.self, forKey: .provenance),
            branchAnalyses: try values.decodeIfPresent([ConflictBranchAnalysis].self, forKey: .branchAnalyses) ?? [],
            isExpected: try values.decodeIfPresent(Bool.self, forKey: .isExpected) ?? false,
            candidateActions: try values.decodeIfPresent([TableAction].self, forKey: .candidateActions) ?? []
        )
    }
}

enum DecisionDisposition: String, Codable, Sendable {
    case unresolved
    case expected
    case resolved

    var label: String {
        switch self {
        case .unresolved: "Unresolved conflict"
        case .expected: "Expected conflict"
        case .resolved: "Resolved decision"
        }
    }
}

extension ConflictDecision {
    var disposition: DecisionDisposition {
        if isExpected { return .expected }
        guard let provenance else { return .unresolved }
        return provenance.kind == .unresolved ? .unresolved : .resolved
    }
}

struct StateDecisionSummary: Sendable {
    let state: StateID
    let disposition: DecisionDisposition
    let decisions: [ConflictDecision]
}

enum ConflictResolutionKind: String, Codable, Sendable {
    case unresolved
    case shift
    case reduce
    case nonassociativeError
}

struct ConflictProvenance: Codable, Sendable {
    let kind: ConflictResolutionKind
    let lookahead: String
    let lookaheadLevel: Int?
    let production: ProductionID?
    let productionSymbol: String?
    let productionLevel: Int?
    let associativity: Associativity?
    let selectedAction: TableAction?
}

struct ConflictBranchAnalysis: Identifiable, Codable, Sendable {
    let id: String
    let action: TableAction
    let outcome: String
    let tree: String?
    let trace: [ReplayFrame]
}

struct ConflictExpectation: Codable, Sendable {
    let expected: Int
    let actual: Int
    let matches: Bool
    let range: SourceRange
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
    let conflictExpectation: ConflictExpectation?

    init(
        algorithm: LRAlgorithm,
        grammarSource: String,
        terminals: [String],
        nonterminals: [String],
        productions: [Production],
        states: [AutomatonState],
        transitions: [Transition],
        cells: [TableCell],
        decisions: [ConflictDecision],
        sample: ParseSample,
        conflictExpectation: ConflictExpectation? = nil
    ) {
        self.algorithm = algorithm
        self.grammarSource = grammarSource
        self.terminals = terminals
        self.nonterminals = nonterminals
        self.productions = productions
        self.states = states
        self.transitions = transitions
        self.cells = cells
        self.decisions = decisions
        self.sample = sample
        self.conflictExpectation = conflictExpectation
    }

    func state(_ id: StateID) -> AutomatonState? { states.first { $0.id == id } }
    func cell(_ id: CellID) -> TableCell? { cells.first { $0.id == id } }
    func decision(_ id: DecisionID) -> ConflictDecision? { decisions.first { $0.id == id } }
    func decision(at cell: CellID) -> ConflictDecision? { decisions.first { $0.cell == cell } }
    func candidateActions(for decision: ConflictDecision) -> [TableAction] {
        if !decision.candidateActions.isEmpty { return decision.candidateActions }
        if !decision.branchAnalyses.isEmpty { return decision.branchAnalyses.map(\.action) }
        return cell(decision.cell)?.actions ?? []
    }
    func decisionSummary(for state: StateID) -> StateDecisionSummary? {
        let matches = decisions.filter { $0.cell.state == state }
        guard !matches.isEmpty else { return nil }
        let disposition: DecisionDisposition
        if matches.contains(where: { $0.disposition == .unresolved }) {
            disposition = .unresolved
        } else if matches.contains(where: { $0.disposition == .expected }) {
            disposition = .expected
        } else {
            disposition = .resolved
        }
        return StateDecisionSummary(state: state, disposition: disposition, decisions: matches)
    }
}

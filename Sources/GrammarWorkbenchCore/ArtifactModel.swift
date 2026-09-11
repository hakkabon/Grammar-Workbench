import Foundation

package enum LRAlgorithm: String, CaseIterable, Codable, Identifiable, Sendable {
    case slr = "SLR(1)"
    case lalr = "LALR(1)"
    case canonical = "Canonical LR(1)"
    package var id: Self { self }
}

package struct StateID: Hashable, Codable, Identifiable, Sendable, CustomStringConvertible {
    package let rawValue: Int
    package var id: Int { rawValue }
    package var description: String { "I\(rawValue)" }

    package init(rawValue: Int) { self.rawValue = rawValue }
}

package struct ProductionID: Hashable, Codable, Identifiable, Sendable {
    package let rawValue: Int
    package var id: Int { rawValue }

    package init(rawValue: Int) { self.rawValue = rawValue }
}

package struct CellID: Hashable, Codable, Identifiable, Sendable {
    package let state: StateID
    package let symbol: String
    package var id: String { "\(state.rawValue):\(symbol)" }

    package init(state: StateID, symbol: String) {
        self.state = state
        self.symbol = symbol
    }
}

package struct DecisionID: Hashable, Codable, Identifiable, Sendable {
    package let rawValue: String
    package var id: String { rawValue }

    package init(rawValue: String) { self.rawValue = rawValue }
}

package enum ArtifactIdentity: Hashable, Sendable {
    case state(StateID)
    case production(ProductionID)
    case cell(CellID)
    case decision(DecisionID)
    case traceStep(Int)
}

package struct Production: Identifiable, Codable, Sendable {
    package let id: ProductionID
    package let lhs: String
    package let rhs: [String]
    package var text: String { "\(lhs) → \(rhs.isEmpty ? "ε" : rhs.joined(separator: " "))" }
}

package struct LRItem: Identifiable, Codable, Sendable {
    package let id: String
    package let production: ProductionID
    package let text: String
}

package struct AutomatonState: Identifiable, Codable, Sendable {
    package let id: StateID
    package let items: [LRItem]
}

package struct Transition: Identifiable, Codable, Sendable {
    package let from: StateID
    package let symbol: String
    package let to: StateID
    package var id: String { "\(from.rawValue)-\(symbol)-\(to.rawValue)" }
}

package enum TableAction: Hashable, Codable, Sendable {
    case shift(StateID)
    case reduce(ProductionID)
    case accept
    case goTo(StateID)

    package var label: String {
        switch self {
        case .shift(let state): "s\(state.rawValue)"
        case .reduce(let production): "r\(production.rawValue)"
        case .accept: "acc"
        case .goTo(let state): "\(state.rawValue)"
        }
    }
}

package struct TableCell: Identifiable, Codable, Sendable {
    package let id: CellID
    package let actions: [TableAction]
    package var isConflict: Bool { actions.count > 1 }
}

package struct ReplayFrame: Identifiable, Codable, Sendable {
    package let index: Int
    package let stack: [String]
    package let remainingInput: [String]
    package let action: String
    package let state: StateID?
    package let cell: CellID?
    package let production: ProductionID?
    package var id: Int { index }

    package init(
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

package struct ConflictDecision: Identifiable, Codable, Sendable {
    package let id: DecisionID
    package let cell: CellID
    package let title: String
    package let explanation: String
    package let witness: [String]
    package let branches: [[ReplayFrame]]
    package let provenance: ConflictProvenance?
    package let branchAnalyses: [ConflictBranchAnalysis]
    package let isExpected: Bool
    package let candidateActions: [TableAction]

    package init(
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

    package init(from decoder: Decoder) throws {
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

package enum DecisionDisposition: String, Codable, Sendable {
    case unresolved
    case expected
    case resolved

    package var label: String {
        switch self {
        case .unresolved: "Unresolved conflict"
        case .expected: "Expected conflict"
        case .resolved: "Resolved decision"
        }
    }
}

extension ConflictDecision {
    package var disposition: DecisionDisposition {
        if isExpected { return .expected }
        guard let provenance else { return .unresolved }
        return provenance.kind == .unresolved ? .unresolved : .resolved
    }
}

package struct StateDecisionSummary: Sendable {
    package let state: StateID
    package let disposition: DecisionDisposition
    package let decisions: [ConflictDecision]
}

package enum ConflictResolutionKind: String, Codable, Sendable {
    case unresolved
    case shift
    case reduce
    case nonassociativeError
}

package struct ConflictProvenance: Codable, Sendable {
    package let kind: ConflictResolutionKind
    package let lookahead: String
    package let lookaheadLevel: Int?
    package let production: ProductionID?
    package let productionSymbol: String?
    package let productionLevel: Int?
    package let associativity: Associativity?
    package let selectedAction: TableAction?
}

package struct ConflictBranchAnalysis: Identifiable, Codable, Sendable {
    package let id: String
    package let action: TableAction
    package let outcome: String
    package let tree: String?
    package let trace: [ReplayFrame]
}

package struct ConflictExpectation: Codable, Sendable {
    package let expected: Int
    package let actual: Int
    package let matches: Bool
    package let range: SourceRange
}

package struct ParseSample: Codable, Sendable {
    package let input: String
    package let tree: String
    package let trace: [ReplayFrame]

    package init(input: String, tree: String, trace: [ReplayFrame]) {
        self.input = input
        self.tree = tree
        self.trace = trace
    }
}

package struct GrammarArtifact: Codable, Sendable {
    package let algorithm: LRAlgorithm
    package let grammarSource: String
    package let terminals: [String]
    package let nonterminals: [String]
    package let productions: [Production]
    package let states: [AutomatonState]
    package let transitions: [Transition]
    package let cells: [TableCell]
    package let decisions: [ConflictDecision]
    package let sample: ParseSample
    package let conflictExpectation: ConflictExpectation?

    package init(
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

    package func state(_ id: StateID) -> AutomatonState? { states.first { $0.id == id } }
    package func cell(_ id: CellID) -> TableCell? { cells.first { $0.id == id } }
    package func decision(_ id: DecisionID) -> ConflictDecision? { decisions.first { $0.id == id } }
    package func decision(at cell: CellID) -> ConflictDecision? { decisions.first { $0.cell == cell } }
    package func candidateActions(for decision: ConflictDecision) -> [TableAction] {
        if !decision.candidateActions.isEmpty { return decision.candidateActions }
        if !decision.branchAnalyses.isEmpty { return decision.branchAnalyses.map(\.action) }
        return cell(decision.cell)?.actions ?? []
    }
    package func decisionSummary(for state: StateID) -> StateDecisionSummary? {
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

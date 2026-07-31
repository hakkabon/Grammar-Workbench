import Foundation

enum SampleArtifact {
    static let grammarSource = "%start E\n%left '+'\n%left '*'\n\nE : E '+' E\n  | E '*' E\n  | 'id'\n  ;"

    static func make(algorithm: LRAlgorithm) -> GrammarArtifact {
        let productions = [
            Production(id: .init(rawValue: 0), lhs: "S′", rhs: ["E"]),
            Production(id: .init(rawValue: 1), lhs: "E", rhs: ["E", "+", "E"]),
            Production(id: .init(rawValue: 2), lhs: "E", rhs: ["E", "*", "E"]),
            Production(id: .init(rawValue: 3), lhs: "E", rhs: ["id"])
        ]
        let itemTexts = [
            ["S′ → • E", "E → • E + E", "E → • E * E", "E → • id"],
            ["S′ → E •", "E → E • + E", "E → E • * E"],
            ["E → id •"],
            ["E → E + • E", "E → • E + E", "E → • E * E", "E → • id"],
            ["E → E * • E", "E → • E + E", "E → • E * E", "E → • id"],
            ["E → E + E •", "E → E • + E", "E → E • * E"],
            ["E → E * E •", "E → E • + E", "E → E • * E"]
        ]
        let states = itemTexts.enumerated().map { index, texts in
            AutomatonState(id: StateID(rawValue: index), items: texts.enumerated().map {
                LRItem(id: "\(index)-\($0.offset)", production: ProductionID(rawValue: min($0.offset, 3)), text: $0.element)
            })
        }
        let transitions: [Transition] = [
            .init(from: .init(rawValue: 0), symbol: "E", to: .init(rawValue: 1)),
            .init(from: .init(rawValue: 0), symbol: "id", to: .init(rawValue: 2)),
            .init(from: .init(rawValue: 1), symbol: "+", to: .init(rawValue: 3)),
            .init(from: .init(rawValue: 1), symbol: "*", to: .init(rawValue: 4)),
            .init(from: .init(rawValue: 3), symbol: "E", to: .init(rawValue: 5)),
            .init(from: .init(rawValue: 3), symbol: "id", to: .init(rawValue: 2)),
            .init(from: .init(rawValue: 4), symbol: "E", to: .init(rawValue: 6)),
            .init(from: .init(rawValue: 4), symbol: "id", to: .init(rawValue: 2))
        ]
        var cells: [TableCell] = [
            cell(0, "id", .shift(.init(rawValue: 2))), cell(0, "E", .goTo(.init(rawValue: 1))),
            cell(1, "+", .shift(.init(rawValue: 3))), cell(1, "*", .shift(.init(rawValue: 4))), cell(1, "$", .accept),
            cell(2, "+", .reduce(.init(rawValue: 3))), cell(2, "*", .reduce(.init(rawValue: 3))), cell(2, "$", .reduce(.init(rawValue: 3))),
            cell(3, "id", .shift(.init(rawValue: 2))), cell(3, "E", .goTo(.init(rawValue: 5))),
            cell(4, "id", .shift(.init(rawValue: 2))), cell(4, "E", .goTo(.init(rawValue: 6))),
            conflictCell(5, "+", [.shift(.init(rawValue: 3)), .reduce(.init(rawValue: 1))]),
            conflictCell(5, "*", [.shift(.init(rawValue: 4)), .reduce(.init(rawValue: 1))]),
            cell(5, "$", .reduce(.init(rawValue: 1))),
            conflictCell(6, "+", [.shift(.init(rawValue: 3)), .reduce(.init(rawValue: 2))]),
            conflictCell(6, "*", [.shift(.init(rawValue: 4)), .reduce(.init(rawValue: 2))]),
            cell(6, "$", .reduce(.init(rawValue: 2)))
        ]
        if algorithm == .canonical { cells.removeAll { $0.id.state.rawValue == 5 && $0.id.symbol == "+" } }
        let witness = ["id", "+", "id", "*", "id"]
        let branchA = replay(witness, ending: "shift * (multiplication binds tighter)", state: 5)
        let branchB = replay(witness, ending: "reduce E → E + E", state: 5)
        let decisions = cells.filter(\.isConflict).map { value in
            ConflictDecision(
                id: DecisionID(rawValue: "conflict-\(value.id.id)"), cell: value.id,
                title: "Shift/reduce conflict in \(value.id.state) on ‘\(value.id.symbol)’",
                explanation: "The completed expression can reduce now, while the same lookahead can extend it. Precedence or associativity resolves which parse is intended.",
                witness: witness, branches: [branchA, branchB]
            )
        }
        let trace = replay(["id", "+", "id", "*", "id"], ending: "accept", state: 1)
        return GrammarArtifact(
            algorithm: algorithm,
            grammarSource: grammarSource,
            terminals: ["id", "+", "*", "$"], nonterminals: ["E"], productions: productions,
            states: states, transitions: transitions, cells: cells, decisions: decisions,
            sample: ParseSample(input: "id + id * id", tree: "E\n├─ E → id\n├─ +\n└─ E\n   ├─ E → id\n   ├─ *\n   └─ E → id", trace: trace)
        )
    }

    private static func cell(_ state: Int, _ symbol: String, _ action: TableAction) -> TableCell {
        TableCell(id: CellID(state: StateID(rawValue: state), symbol: symbol), actions: [action])
    }
    private static func conflictCell(_ state: Int, _ symbol: String, _ actions: [TableAction]) -> TableCell {
        TableCell(id: CellID(state: StateID(rawValue: state), symbol: symbol), actions: actions)
    }
    private static func replay(_ tokens: [String], ending: String, state: Int) -> [ReplayFrame] {
        [
            ReplayFrame(index: 0, stack: ["0"], remainingInput: tokens + ["$"], action: "start", state: .init(rawValue: 0)),
            ReplayFrame(index: 1, stack: ["0", "id", "2"], remainingInput: Array(tokens.dropFirst()) + ["$"], action: "shift id", state: .init(rawValue: 2)),
            ReplayFrame(index: 2, stack: ["0", "E", "1"], remainingInput: Array(tokens.dropFirst()) + ["$"], action: "reduce E → id", state: .init(rawValue: 1)),
            ReplayFrame(index: 3, stack: ["…", "E", "\(state)"], remainingInput: [tokens.last ?? "id", "$"], action: ending, state: .init(rawValue: state))
        ]
    }
}

enum FrontEndArtifact {
    static func make(result: GrammarFrontEndResult, algorithm: LRAlgorithm) -> GrammarArtifact {
        guard let grammar = result.grammar else {
            let fallback = SampleArtifact.make(algorithm: algorithm)
            return GrammarArtifact(
                algorithm: algorithm, grammarSource: result.source,
                terminals: fallback.terminals, nonterminals: fallback.nonterminals,
                productions: fallback.productions, states: fallback.states,
                transitions: fallback.transitions, cells: fallback.cells,
                decisions: fallback.decisions, sample: fallback.sample
            )
        }
        guard let analysis = result.analysis else {
            return SampleArtifact.make(algorithm: algorithm)
        }
        return LRConstructionEngine.construct(
            grammar: grammar,
            analysis: analysis,
            source: result.source,
            algorithm: algorithm
        )
    }
}

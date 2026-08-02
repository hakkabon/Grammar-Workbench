import Foundation

enum LRConstructionEngine {
    private struct Item: Hashable {
        let production: Int
        let dot: Int
        let lookahead: String?

        var core: Core { Core(production: production, dot: dot) }
    }

    private struct Core: Hashable, Comparable {
        let production: Int
        let dot: Int

        static func < (lhs: Core, rhs: Core) -> Bool {
            lhs.production == rhs.production ? lhs.dot < rhs.dot : lhs.production < rhs.production
        }
    }

    private struct Rule {
        let lhs: String
        let rhs: [String]
    }

    private struct Machine {
        let states: [Set<Item>]
        let transitions: [Transition]
    }

    private struct Resolution {
        let actions: [TableAction]
        let explanation: String?
        let provenance: ConflictProvenance
    }

    static func construct(
        grammar: ParsedGrammar,
        analysis: GrammarAnalysis,
        source: String,
        algorithm: LRAlgorithm
    ) -> GrammarArtifact {
        let augmentedSymbol = uniqueAugmentedSymbol(for: grammar)
        let rules = [Rule(lhs: augmentedSymbol, rhs: [grammar.startSymbol])]
            + grammar.productions.map { Rule(lhs: $0.lhs, rhs: $0.rhs) }
        let machine: Machine
        switch algorithm {
        case .slr:
            machine = lr0Machine(grammar: grammar, rules: rules)
        case .canonical:
            machine = canonicalMachine(grammar: grammar, analysis: analysis, rules: rules)
        case .lalr:
            machine = mergeLALR(canonicalMachine(grammar: grammar, analysis: analysis, rules: rules))
        }

        let productions = rules.enumerated().map {
            Production(id: .init(rawValue: $0.offset), lhs: $0.element.lhs, rhs: $0.element.rhs)
        }
        let states = machine.states.enumerated().map { stateIndex, items in
            AutomatonState(
                id: .init(rawValue: stateIndex),
                items: items.sorted(by: itemOrder).map { item in
                    LRItem(
                        id: "\(stateIndex)-\(item.production)-\(item.dot)-\(item.lookahead ?? "_")",
                        production: .init(rawValue: item.production),
                        text: itemText(item, rule: rules[item.production])
                    )
                }
            )
        }
        let table = buildTable(
            grammar: grammar,
            analysis: analysis,
            algorithm: algorithm,
            rules: rules,
            machine: machine
        )
        let actualConflicts = table.cells.filter(\.isConflict).count
        let expectation = grammar.conflictExpectation.map {
            ConflictExpectation(expected: $0.count, actual: actualConflicts, matches: $0.count == actualConflicts, range: $0.range)
        }
        let decisions = table.decisions.map { decision in
            ConflictDecision(
                id: decision.id,
                cell: decision.cell,
                title: decision.title,
                explanation: decision.explanation,
                witness: decision.witness,
                branches: decision.branches,
                provenance: decision.provenance,
                branchAnalyses: decision.branchAnalyses,
                isExpected: expectation?.matches == true && artifactCellIsConflict(decision.cell, cells: table.cells),
                candidateActions: decision.candidateActions
            )
        }
        let artifact = GrammarArtifact(
            algorithm: algorithm,
            grammarSource: source,
            terminals: grammar.terminals + ["$"],
            nonterminals: grammar.nonterminals,
            productions: productions,
            states: states,
            transitions: machine.transitions,
            cells: table.cells,
            decisions: decisions,
            sample: ParseSample(input: "", tree: "Choose a sample input in a future parsing milestone.", trace: []),
            conflictExpectation: expectation
        )
        return ConflictWitnessGenerator.enrich(artifact)
    }

    private static func lr0Machine(grammar: ParsedGrammar, rules: [Rule]) -> Machine {
        let productionsByLHS = Dictionary(grouping: rules.indices, by: { rules[$0].lhs })
        func closure(_ seed: Set<Item>) -> Set<Item> {
            var result = seed
            var changed = true
            while changed {
                changed = false
                for item in result {
                    let rule = rules[item.production]
                    guard item.dot < rule.rhs.count,
                          let indices = productionsByLHS[rule.rhs[item.dot]] else { continue }
                    for production in indices {
                        changed = result.insert(Item(production: production, dot: 0, lookahead: nil)).inserted || changed
                    }
                }
            }
            return result
        }
        return buildMachine(
            initial: closure([Item(production: 0, dot: 0, lookahead: nil)]),
            symbols: grammar.terminals + grammar.nonterminals,
            advance: { state, symbol in
                closure(Set(state.compactMap { item in
                    let rule = rules[item.production]
                    guard item.dot < rule.rhs.count, rule.rhs[item.dot] == symbol else { return nil }
                    return Item(production: item.production, dot: item.dot + 1, lookahead: nil)
                }))
            }
        )
    }

    private static func canonicalMachine(
        grammar: ParsedGrammar,
        analysis: GrammarAnalysis,
        rules: [Rule]
    ) -> Machine {
        let productionsByLHS = Dictionary(grouping: rules.indices, by: { rules[$0].lhs })
        let nonterminals = Set(grammar.nonterminals + [rules[0].lhs])
        func first(_ sequence: ArraySlice<String>) -> Set<String> {
            var result: Set<String> = []
            for symbol in sequence {
                if nonterminals.contains(symbol) {
                    result.formUnion(analysis.first[symbol, default: []])
                    if !analysis.nullable.contains(symbol) { return result }
                } else {
                    result.insert(symbol)
                    return result
                }
            }
            return result
        }
        func closure(_ seed: Set<Item>) -> Set<Item> {
            var result = seed
            var changed = true
            while changed {
                changed = false
                for item in result {
                    let rule = rules[item.production]
                    guard item.dot < rule.rhs.count,
                          let indices = productionsByLHS[rule.rhs[item.dot]],
                          let lookahead = item.lookahead else { continue }
                    let suffix = rule.rhs.dropFirst(item.dot + 1)
                    var lookaheads = first(suffix)
                    let suffixNullable = suffix.allSatisfy {
                        nonterminals.contains($0) && analysis.nullable.contains($0)
                    }
                    if suffix.isEmpty || suffixNullable { lookaheads.insert(lookahead) }
                    for production in indices {
                        for nextLookahead in lookaheads {
                            changed = result.insert(Item(production: production, dot: 0, lookahead: nextLookahead)).inserted || changed
                        }
                    }
                }
            }
            return result
        }
        return buildMachine(
            initial: closure([Item(production: 0, dot: 0, lookahead: "$")]),
            symbols: grammar.terminals + grammar.nonterminals,
            advance: { state, symbol in
                closure(Set(state.compactMap { item in
                    let rule = rules[item.production]
                    guard item.dot < rule.rhs.count, rule.rhs[item.dot] == symbol else { return nil }
                    return Item(production: item.production, dot: item.dot + 1, lookahead: item.lookahead)
                }))
            }
        )
    }

    private static func buildMachine(
        initial: Set<Item>,
        symbols: [String],
        advance: (Set<Item>, String) -> Set<Item>
    ) -> Machine {
        var states = [initial]
        var stateIndices = [initial: 0]
        var transitions: [Transition] = []
        var cursor = 0
        while cursor < states.count {
            for symbol in symbols {
                let target = advance(states[cursor], symbol)
                guard !target.isEmpty else { continue }
                let targetIndex: Int
                if let existing = stateIndices[target] {
                    targetIndex = existing
                } else {
                    targetIndex = states.count
                    stateIndices[target] = targetIndex
                    states.append(target)
                }
                transitions.append(.init(
                    from: .init(rawValue: cursor),
                    symbol: symbol,
                    to: .init(rawValue: targetIndex)
                ))
            }
            cursor += 1
        }
        return Machine(states: states, transitions: transitions)
    }

    private static func mergeLALR(_ canonical: Machine) -> Machine {
        func coreKey(_ state: Set<Item>) -> [Core] {
            Array(Set(state.map(\.core))).sorted()
        }
        var groupForCore: [[Core]: Int] = [:]
        var oldToNew: [Int: Int] = [:]
        var merged: [Set<Item>] = []
        for (index, state) in canonical.states.enumerated() {
            let key = coreKey(state)
            let group: Int
            if let existing = groupForCore[key] {
                group = existing
                merged[group].formUnion(state)
            } else {
                group = merged.count
                groupForCore[key] = group
                merged.append(state)
            }
            oldToNew[index] = group
        }
        var seen: Set<String> = []
        var transitions: [Transition] = []
        for transition in canonical.transitions {
            guard let from = oldToNew[transition.from.rawValue],
                  let to = oldToNew[transition.to.rawValue] else { continue }
            let key = "\(from):\(transition.symbol):\(to)"
            if seen.insert(key).inserted {
                transitions.append(.init(from: .init(rawValue: from), symbol: transition.symbol, to: .init(rawValue: to)))
            }
        }
        return Machine(states: merged, transitions: transitions)
    }

    private static func buildTable(
        grammar: ParsedGrammar,
        analysis: GrammarAnalysis,
        algorithm: LRAlgorithm,
        rules: [Rule],
        machine: Machine
    ) -> (cells: [TableCell], decisions: [ConflictDecision]) {
        let terminals = Set(grammar.terminals + ["$"])
        let nonterminals = Set(grammar.nonterminals)
        var candidates: [CellID: [TableAction]] = [:]
        for transition in machine.transitions {
            let cell = CellID(state: transition.from, symbol: transition.symbol)
            if terminals.contains(transition.symbol) {
                append(.shift(transition.to), to: cell, in: &candidates)
            } else if nonterminals.contains(transition.symbol) {
                append(.goTo(transition.to), to: cell, in: &candidates)
            }
        }
        for (stateIndex, state) in machine.states.enumerated() {
            for item in state {
                let rule = rules[item.production]
                guard item.dot == rule.rhs.count else { continue }
                let stateID = StateID(rawValue: stateIndex)
                if item.production == 0 {
                    append(.accept, to: .init(state: stateID, symbol: "$"), in: &candidates)
                } else {
                    let lookaheads = algorithm == .slr
                        ? analysis.follow[rule.lhs, default: []]
                        : Set([item.lookahead].compactMap { $0 })
                    for lookahead in lookaheads {
                        append(.reduce(.init(rawValue: item.production)), to: .init(state: stateID, symbol: lookahead), in: &candidates)
                    }
                }
            }
        }

        let precedence = precedenceMap(grammar.precedence)
        var cells: [TableCell] = []
        var decisions: [ConflictDecision] = []
        for id in candidates.keys.sorted(by: cellOrder) {
            let original = candidates[id, default: []].sorted(by: actionOrder)
            let resolution = resolve(original, lookahead: id.symbol, rules: rules, precedence: precedence)
            if !resolution.actions.isEmpty {
                cells.append(TableCell(id: id, actions: resolution.actions))
            }
            if original.count > 1 {
                decisions.append(decision(
                    id: id,
                    original: original,
                    resolved: resolution.actions,
                    explanation: resolution.explanation,
                    provenance: resolution.provenance
                ))
            }
        }
        return (cells, decisions)
    }

    private static func resolve(
        _ actions: [TableAction],
        lookahead: String,
        rules: [Rule],
        precedence: [String: (level: Int, associativity: Associativity)]
    ) -> Resolution {
        guard actions.count == 2,
              let shift = actions.first(where: { if case .shift = $0 { true } else { false } }),
              let reduce = actions.first(where: { if case .reduce = $0 { true } else { false } }),
              case .reduce(let productionID) = reduce,
              let shiftPrecedence = precedence[lookahead],
              let productionSymbol = rules[productionID.rawValue].rhs.reversed().first(where: { precedence[$0] != nil }),
              let reducePrecedence = precedence[productionSymbol] else {
            let production = actions.compactMap { action -> ProductionID? in
                if case .reduce(let id) = action { return id }
                return nil
            }.first
            return Resolution(
                actions: actions,
                explanation: nil,
                provenance: .init(
                    kind: .unresolved, lookahead: lookahead, lookaheadLevel: precedence[lookahead]?.level,
                    production: production, productionSymbol: nil, productionLevel: nil,
                    associativity: precedence[lookahead]?.associativity, selectedAction: nil
                )
            )
        }
        if shiftPrecedence.level > reducePrecedence.level {
            return Resolution(
                actions: [shift],
                explanation: "Resolved as shift: ‘\(lookahead)’ has higher precedence than production \(productionID.rawValue).",
                provenance: provenance(.shift, selected: shift)
            )
        }
        if shiftPrecedence.level < reducePrecedence.level {
            return Resolution(
                actions: [reduce],
                explanation: "Resolved as reduce: production \(productionID.rawValue) has higher precedence than ‘\(lookahead)’.",
                provenance: provenance(.reduce, selected: reduce)
            )
        }
        switch shiftPrecedence.associativity {
        case .left:
            return Resolution(actions: [reduce], explanation: "Resolved as reduce by left associativity.", provenance: provenance(.reduce, selected: reduce))
        case .right:
            return Resolution(actions: [shift], explanation: "Resolved as shift by right associativity.", provenance: provenance(.shift, selected: shift))
        case .nonassociative:
            return Resolution(actions: [], explanation: "Resolved as an error entry by nonassociativity.", provenance: provenance(.nonassociativeError, selected: nil))
        }

        func provenance(_ kind: ConflictResolutionKind, selected: TableAction?) -> ConflictProvenance {
            ConflictProvenance(
                kind: kind,
                lookahead: lookahead,
                lookaheadLevel: shiftPrecedence.level,
                production: productionID,
                productionSymbol: productionSymbol,
                productionLevel: reducePrecedence.level,
                associativity: shiftPrecedence.associativity,
                selectedAction: selected
            )
        }
    }

    private static func decision(
        id: CellID,
        original: [TableAction],
        resolved: [TableAction],
        explanation: String?,
        provenance: ConflictProvenance
    ) -> ConflictDecision {
        let kinds = original.map(\.label).joined(separator: " / ")
        let status = explanation ?? "No precedence rule resolves these alternatives."
        let witness = [id.symbol]
        let branches = original.enumerated().map { offset, action in
            [
                ReplayFrame(
                    index: 0,
                    stack: [id.state.description],
                    remainingInput: [id.symbol, "$"],
                    action: "choose \(action.label)",
                    state: id.state
                ),
                ReplayFrame(
                    index: 1,
                    stack: [id.state.description],
                    remainingInput: ["$"],
                    action: resolved.contains(action) ? "selected" : "alternative",
                    state: id.state
                )
            ]
        }
        return ConflictDecision(
            id: .init(rawValue: "decision-\(id.id)"),
            cell: id,
            title: "\(resolved.count <= 1 && explanation != nil ? "Resolved decision" : "Conflict") in \(id.state) on ‘\(id.symbol)’",
            explanation: "\(kinds). \(status)",
            witness: witness,
            branches: branches,
            provenance: provenance,
            candidateActions: original
        )
    }

    private static func append(_ action: TableAction, to cell: CellID, in candidates: inout [CellID: [TableAction]]) {
        if !candidates[cell, default: []].contains(action) {
            candidates[cell, default: []].append(action)
        }
    }

    private static func precedenceMap(
        _ declarations: [PrecedenceDeclaration]
    ) -> [String: (level: Int, associativity: Associativity)] {
        var result: [String: (level: Int, associativity: Associativity)] = [:]
        for declaration in declarations {
            for symbol in declaration.symbols {
                result[symbol] = (declaration.level, declaration.associativity)
            }
        }
        return result
    }

    private static func uniqueAugmentedSymbol(for grammar: ParsedGrammar) -> String {
        var value = "\(grammar.startSymbol)′"
        while grammar.nonterminals.contains(value) { value.append("′") }
        return value
    }

    private static func itemText(_ item: Item, rule: Rule) -> String {
        var parts = rule.rhs
        parts.insert("•", at: item.dot)
        let body = parts.joined(separator: " ")
        return "\(rule.lhs) → \(body)\(item.lookahead.map { ", \($0)" } ?? "")"
    }

    private static func itemOrder(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.production != rhs.production { return lhs.production < rhs.production }
        if lhs.dot != rhs.dot { return lhs.dot < rhs.dot }
        return (lhs.lookahead ?? "") < (rhs.lookahead ?? "")
    }

    private static func cellOrder(_ lhs: CellID, _ rhs: CellID) -> Bool {
        lhs.state.rawValue == rhs.state.rawValue
            ? lhs.symbol < rhs.symbol
            : lhs.state.rawValue < rhs.state.rawValue
    }

    private static func actionOrder(_ lhs: TableAction, _ rhs: TableAction) -> Bool {
        lhs.label < rhs.label
    }

    private static func artifactCellIsConflict(_ id: CellID, cells: [TableCell]) -> Bool {
        cells.first { $0.id == id }?.isConflict == true
    }
}

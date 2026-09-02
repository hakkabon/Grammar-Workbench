import LR_Parsing

enum CanonicalLRConstructionAdapter {
    static func construct(
        grammar model: ParsedGrammar,
        source: String,
        algorithm: LRAlgorithm
    ) -> GrammarArtifact {
        let specification = LRGrammarSpecification(
            start: model.startSymbol,
            terminals: model.terminals,
            rules: model.productions.map { .init(lhs: $0.lhs, rhs: $0.rhs) },
            precedence: model.precedence.map { declaration in
                .init(level: declaration.level, associativity: associativity(declaration.associativity), terminals: declaration.symbols)
            }
        )
        let parser = LR_Parsing.LRParser(specification: specification, algorithm: canonicalAlgorithm(algorithm))
        let external = parser.generate()
        let augmented = uniqueAugmentedSymbol(for: model)
        let productions = [Production(id: .init(rawValue: 0), lhs: augmented, rhs: [model.startSymbol])]
            + model.productions.enumerated().map {
                Production(id: .init(rawValue: $0.offset + 1), lhs: $0.element.lhs, rhs: $0.element.rhs)
            }

        var productionIDs: [LRArtifactID: ProductionID] = [:]
        for occurrence in external.productionOccurrences where productionIDs[occurrence.semanticIdentity] == nil {
            productionIDs[occurrence.semanticIdentity] = .init(rawValue: occurrence.ordinal + 1)
        }
        func action(_ value: LR_Parsing.LRAction) -> TableAction {
            switch value {
            case .shift(let state): .shift(.init(rawValue: state))
            case .reduce: .reduce(productionIDs[value.productionIdentity ?? .init(rawValue: "")] ?? .init(rawValue: 0))
            case .accept: .accept
            }
        }

        let states = external.states.map { state in
            AutomatonState(
                id: .init(rawValue: state.id),
                items: state.items.sorted { $0.identity < $1.identity }.map { item in
                    LRItem(
                        id: item.identity.rawValue,
                        production: productionIDs[item.productionIdentity] ?? .init(rawValue: 0),
                        text: itemText(item)
                    )
                }
            )
        }
        let transitions = external.transitions.map {
            Transition(
                from: .init(rawValue: $0.source),
                symbol: $0.symbol.lrSymbolName,
                to: .init(rawValue: $0.target)
            )
        }
        var cells: [TableCell] = []
        for (state, row) in external.actionDecisions {
            for (terminal, decision) in row {
                let actions = decision.status == .unresolved
                    ? decision.candidates.map { action($0.action) }
                    : decision.selectedAction.map { [action($0)] } ?? []
                if !actions.isEmpty {
                    cells.append(.init(
                        id: .init(state: .init(rawValue: state), symbol: terminal.lrSymbolName),
                        actions: actions.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
                    ))
                }
            }
        }
        for (state, row) in external.gotoTable {
            for (nonterminal, target) in row {
                cells.append(.init(
                    id: .init(state: .init(rawValue: state), symbol: nonterminal.name),
                    actions: [.goTo(.init(rawValue: target))]
                ))
            }
        }
        let precedenceBySymbol = Dictionary(uniqueKeysWithValues: model.precedence.flatMap { declaration in
            declaration.symbols.map { ($0, declaration) }
        })
        let decisions = external.allConflicts.map { conflict in
            let cell = CellID(
                state: .init(rawValue: conflict.state),
                symbol: conflict.lookahead.lrSymbolName
            )
            let candidates = conflict.actions.map(action)
            let selected = conflict.decision?.selectedAction.map(action)
            let kind: ConflictResolutionKind = conflict.isResolved
                ? (selected.map { if case .shift = $0 { .shift } else { .reduce } } ?? .nonassociativeError)
                : .unresolved
            let lookahead = conflict.lookahead.lrSymbolName
            let lookaheadPrecedence = precedenceBySymbol[lookahead]
            let reducedID = candidates.compactMap { candidate -> ProductionID? in
                if case .reduce(let id) = candidate { return id }
                return nil
            }.first
            let productionSymbol = reducedID.flatMap { id in
                productions.first { $0.id == id }?.rhs.reversed().first { precedenceBySymbol[$0] != nil }
            }
            let productionPrecedence = productionSymbol.flatMap { precedenceBySymbol[$0] }
            let resolvedAssociativity: Associativity? = {
                guard lookaheadPrecedence?.level == productionPrecedence?.level else { return nil }
                switch conflict.decision?.resolution {
                case .leftAssociative: return .left
                case .rightAssociative: return .right
                case .nonAssociative: return .nonassociative
                default: return nil
                }
            }()
            return ConflictDecision(
                id: .init(rawValue: conflict.identity.rawValue),
                cell: cell,
                title: "\(conflict.isResolved ? "Resolved decision" : "Conflict") in I\(conflict.state) on ‘\(cell.symbol)’",
                explanation: conflict.decision.map(decisionExplanation) ?? conflict.description,
                witness: conflict.witness.map(\.lrSymbolName),
                branches: [],
                provenance: .init(
                    kind: kind, lookahead: cell.symbol, lookaheadLevel: lookaheadPrecedence?.level,
                    production: reducedID, productionSymbol: productionSymbol,
                    productionLevel: productionPrecedence?.level, associativity: resolvedAssociativity,
                    selectedAction: selected
                ),
                candidateActions: candidates
            )
        }
        let actualConflicts = cells.count(where: \.isConflict)
        let expectation = model.conflictExpectation.map {
            ConflictExpectation(expected: $0.count, actual: actualConflicts, matches: $0.count == actualConflicts, range: $0.range)
        }
        let annotatedDecisions = decisions.map { decision in
            ConflictDecision(
                id: decision.id, cell: decision.cell, title: decision.title,
                explanation: decision.explanation, witness: decision.witness,
                branches: decision.branches, provenance: decision.provenance,
                branchAnalyses: decision.branchAnalyses,
                isExpected: expectation?.matches == true && cells.contains {
                    $0.id == decision.cell && $0.isConflict
                },
                candidateActions: decision.candidateActions
            )
        }
        return ConflictWitnessGenerator.enrich(.init(
            algorithm: algorithm, grammarSource: source,
            terminals: model.terminals + ["$"], nonterminals: model.nonterminals,
            productions: productions, states: states, transitions: transitions,
            cells: cells.sorted { $0.id.id < $1.id.id }, decisions: annotatedDecisions,
            sample: .init(input: "", tree: "Choose a sample input.", trace: []),
            conflictExpectation: expectation
        ))
    }

    private static func uniqueAugmentedSymbol(for grammar: ParsedGrammar) -> String {
        var value = "\(grammar.startSymbol)′"
        while grammar.nonterminals.contains(value) { value.append("′") }
        return value
    }

    private static func associativity(_ value: Associativity) -> LRAssociativity {
        switch value {
        case .left: .left
        case .right: .right
        case .nonassociative: .nonAssociative
        }
    }

    private static func canonicalAlgorithm(_ value: LRAlgorithm) -> LR_Parsing.LRParser.Algorithm {
        switch value {
        case .slr: .slr
        case .lalr: .lalr
        case .canonical: .lr1
        }
    }

    private static func decisionExplanation(_ decision: LRActionDecision) -> String {
        switch decision.resolution {
        case .higherPrecedence: "Resolved by higher precedence. \(decision.description)"
        case .leftAssociative: "Resolved by left associativity. \(decision.description)"
        case .rightAssociative: "Resolved by right associativity. \(decision.description)"
        case .nonAssociative: "Resolved as an error entry by nonassociativity. \(decision.description)"
        default: decision.description
        }
    }

    private static func itemText(_ item: LR_Parsing.LRItem) -> String {
        var symbols = item.production.rule.map(\.lrSymbolName)
        symbols.insert("•", at: item.dotIndex)
        let lookahead = item.lookahead.map(\.lrSymbolName).sorted()
        return "\(item.production.goal.name) → \(symbols.joined(separator: " "))"
            + (lookahead.isEmpty ? "" : ", \(lookahead.joined(separator: "/"))")
    }
}

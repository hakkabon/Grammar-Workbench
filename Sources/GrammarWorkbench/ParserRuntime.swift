import Foundation

struct ParseTreeNode: Hashable, Sendable {
    let symbol: String
    let children: [ParseTreeNode]

    func rendered() -> String {
        var lines = [symbol]
        appendChildren(to: &lines, prefix: "")
        return lines.joined(separator: "\n")
    }

    private func appendChildren(to lines: inout [String], prefix: String) {
        for (index, child) in children.enumerated() {
            let last = index == children.count - 1
            lines.append("\(prefix)\(last ? "└─ " : "├─ ")\(child.symbol)")
            child.appendChildren(to: &lines, prefix: prefix + (last ? "   " : "│  "))
        }
    }
}

enum ParseOutcome: Hashable, Sendable {
    case accepted
    case rejected(message: String, expected: [String])
    case conflict(CellID)
    case looping

    var label: String {
        switch self {
        case .accepted: "Accepted"
        case .rejected(let message, _): "Rejected: \(message)"
        case .conflict(let cell): "Conflict at \(cell.state) on ‘\(cell.symbol)’"
        case .looping: "Stopped: step limit reached"
        }
    }
}

struct ParserRuntimeResult: Sendable {
    let tokens: [String]
    let tree: ParseTreeNode?
    let frames: [ReplayFrame]
    let outcome: ParseOutcome
}

enum SampleInputTokenizer {
    struct TokenizationError: Error, Equatable {
        let message: String
    }

    static func tokenize(_ source: String) -> Result<[String], TokenizationError> {
        var tokens: [String] = []
        let characters = Array(source)
        var index = 0
        while index < characters.count {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            guard index < characters.count else { break }
            if characters[index] == "'" || characters[index] == "\"" {
                let quote = characters[index]
                index += 1
                var token = ""
                var closed = false
                while index < characters.count {
                    if characters[index] == quote {
                        index += 1
                        closed = true
                        break
                    }
                    if characters[index] == "\\", index + 1 < characters.count {
                        index += 1
                    }
                    token.append(characters[index])
                    index += 1
                }
                guard closed else { return .failure(.init(message: "Unterminated quoted token.")) }
                tokens.append(token)
            } else {
                var token = ""
                while index < characters.count, !characters[index].isWhitespace {
                    token.append(characters[index])
                    index += 1
                }
                tokens.append(token)
            }
        }
        return .success(tokens)
    }
}

enum LRParserRuntime {
    static func parse(
        _ tokens: [String],
        artifact: GrammarArtifact,
        forcing forcedChoice: (cell: CellID, action: TableAction)? = nil,
        stepLimit: Int = 1_000
    ) -> ParserRuntimeResult {
        let terminalSet = Set(artifact.terminals.filter { $0 != "$" })
        if let unknown = tokens.first(where: { !terminalSet.contains($0) }) {
            return ParserRuntimeResult(
                tokens: tokens,
                tree: nil,
                frames: [],
                outcome: .rejected(
                    message: "Unknown terminal ‘\(unknown)’.",
                    expected: terminalSet.sorted()
                )
            )
        }

        let input = tokens + ["$"]
        var cursor = 0
        var states = [StateID(rawValue: 0)]
        var symbols: [String] = []
        var nodes: [ParseTreeNode] = []
        var frames: [ReplayFrame] = []
        var forcedChoiceUsed = false

        for step in 0..<stepLimit {
            guard let state = states.last else {
                return result(.rejected(message: "Parser stack became empty.", expected: []))
            }
            let lookahead = input[min(cursor, input.count - 1)]
            let cellID = CellID(state: state, symbol: lookahead)
            guard let cell = artifact.cell(cellID), !cell.actions.isEmpty else {
                let expected = artifact.terminals.filter {
                    artifact.cell(.init(state: state, symbol: $0))?.actions.isEmpty == false
                }
                frames.append(frame(
                    index: step,
                    action: "error: no action for ‘\(lookahead)’",
                    state: state,
                    cell: cellID
                ))
                return result(.rejected(
                    message: "Unexpected ‘\(lookahead)’ in \(state).",
                    expected: expected
                ))
            }

            let action: TableAction
            if cell.actions.count > 1 {
                if let forcedChoice,
                   forcedChoice.cell == cellID,
                   cell.actions.contains(forcedChoice.action),
                   !forcedChoiceUsed {
                    action = forcedChoice.action
                    forcedChoiceUsed = true
                } else {
                    frames.append(frame(
                        index: step,
                        action: "conflict: \(cell.actions.map(\.label).joined(separator: " or "))",
                        state: state,
                        cell: cellID
                    ))
                    return result(.conflict(cellID))
                }
            } else {
                action = cell.actions[0]
            }

            switch action {
            case .shift(let target):
                frames.append(frame(
                    index: step,
                    action: "shift ‘\(lookahead)’ to \(target)",
                    state: state,
                    cell: cellID
                ))
                symbols.append(lookahead)
                states.append(target)
                nodes.append(ParseTreeNode(symbol: lookahead, children: []))
                cursor += 1
            case .reduce(let productionID):
                guard let production = artifact.productions.first(where: { $0.id == productionID }),
                      production.rhs.count <= symbols.count,
                      production.rhs.count < states.count,
                      production.rhs.count <= nodes.count else {
                    frames.append(frame(
                        index: step,
                        action: "error: invalid reduction \(productionID.rawValue)",
                        state: state,
                        cell: cellID,
                        production: productionID
                    ))
                    return result(.rejected(message: "Invalid reduction stack shape.", expected: []))
                }
                frames.append(frame(
                    index: step,
                    action: "reduce \(production.text)",
                    state: state,
                    cell: cellID,
                    production: productionID
                ))
                let count = production.rhs.count
                let children = count == 0 ? [] : Array(nodes.suffix(count))
                if count > 0 {
                    symbols.removeLast(count)
                    states.removeLast(count)
                    nodes.removeLast(count)
                }
                guard let gotoFrom = states.last,
                      let gotoCell = artifact.cell(.init(state: gotoFrom, symbol: production.lhs)),
                      case .goTo(let target) = gotoCell.actions.first else {
                    return result(.rejected(
                        message: "Missing goto for ‘\(production.lhs)’ after reduction.",
                        expected: []
                    ))
                }
                symbols.append(production.lhs)
                states.append(target)
                nodes.append(ParseTreeNode(symbol: production.lhs, children: children))
            case .accept:
                frames.append(frame(
                    index: step,
                    action: "accept",
                    state: state,
                    cell: cellID
                ))
                return result(.accepted)
            case .goTo:
                frames.append(frame(
                    index: step,
                    action: "error: goto found in ACTION table",
                    state: state,
                    cell: cellID
                ))
                return result(.rejected(message: "Invalid goto action on terminal.", expected: []))
            }
        }
        return result(.looping)

        func frame(
            index: Int,
            action: String,
            state: StateID,
            cell: CellID?,
            production: ProductionID? = nil
        ) -> ReplayFrame {
            var stack = [states[0].description]
            for offset in symbols.indices {
                stack.append(symbols[offset])
                stack.append(states[offset + 1].description)
            }
            return ReplayFrame(
                index: index,
                stack: stack,
                remainingInput: Array(input[cursor...]),
                action: action,
                state: state,
                cell: cell,
                production: production
            )
        }

        func result(_ outcome: ParseOutcome) -> ParserRuntimeResult {
            ParserRuntimeResult(
                tokens: tokens,
                tree: outcome == .accepted ? nodes.last : nil,
                frames: frames,
                outcome: outcome
            )
        }
    }
}

enum ConflictWitnessGenerator {
    private struct SearchConfiguration: Hashable {
        let stack: [StateID]
        let tokens: [String]

        static func == (lhs: SearchConfiguration, rhs: SearchConfiguration) -> Bool {
            lhs.stack == rhs.stack && lhs.tokens == rhs.tokens
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(stack)
            hasher.combine(tokens)
        }
    }

    private enum AdvanceResult {
        case shifted([StateID])
        case conflict(CellID)
        case stopped
    }

    static func enrich(_ artifact: GrammarArtifact, maxLength: Int = 12, candidateLimit: Int = 50_000) -> GrammarArtifact {
        let decisions = artifact.decisions.map { decision in
            guard artifact.cell(decision.cell)?.isConflict == true,
                  let witness = shortestWitness(
                    for: decision.cell,
                    artifact: artifact,
                    maxLength: maxLength,
                    candidateLimit: candidateLimit
                  ),
                  let actions = artifact.cell(decision.cell)?.actions else {
                return decision
            }
            let counterexample = minimalCommonCounterexample(
                witness: witness,
                cell: decision.cell,
                actions: actions,
                artifact: artifact,
                maxSuffixLength: 4,
                candidateLimit: min(candidateLimit, 3_000)
            ) ?? witness
            let branchAnalyses = actions.map { action in
                let branch = LRParserRuntime.parse(
                    counterexample,
                    artifact: artifact,
                    forcing: (decision.cell, action)
                )
                return ConflictBranchAnalysis(
                    id: "\(decision.id.rawValue)-\(action.label)",
                    action: action,
                    outcome: branchClassification(branch.outcome),
                    tree: branch.tree?.rendered(),
                    trace: branch.frames
                )
            }
            let branches = branchAnalyses.map { analysis in
                analysis.trace + [
                    ReplayFrame(
                        index: analysis.trace.count,
                        stack: analysis.trace.last?.stack ?? ["I0"],
                        remainingInput: analysis.trace.last?.remainingInput ?? [],
                        action: analysis.outcome,
                        state: analysis.trace.last?.state,
                        cell: analysis.trace.last?.cell,
                        production: analysis.trace.last?.production
                    )
                ]
            }
            return ConflictDecision(
                id: decision.id,
                cell: decision.cell,
                title: decision.title,
                explanation: decision.explanation + " The minimal counterexample was verified by parser replay after configuration search.",
                witness: counterexample,
                branches: branches,
                provenance: decision.provenance,
                branchAnalyses: branchAnalyses,
                isExpected: decision.isExpected
            )
        }
        return GrammarArtifact(
            algorithm: artifact.algorithm,
            grammarSource: artifact.grammarSource,
            terminals: artifact.terminals,
            nonterminals: artifact.nonterminals,
            productions: artifact.productions,
            states: artifact.states,
            transitions: artifact.transitions,
            cells: artifact.cells,
            decisions: decisions,
            sample: artifact.sample,
            conflictExpectation: artifact.conflictExpectation
        )
    }

    private static func branchClassification(_ outcome: ParseOutcome) -> String {
        switch outcome {
        case .accepted:
            "Accepted branch"
        case .rejected(let message, _):
            "Rejected branch: \(message)"
        case .conflict(let cell):
            "Incomplete branch: another conflict at \(cell.state) on ‘\(cell.symbol)’"
        case .looping:
            "Looping branch: step limit reached"
        }
    }

    private static func shortestWitness(
        for target: CellID,
        artifact: GrammarArtifact,
        maxLength: Int,
        candidateLimit: Int
    ) -> [String]? {
        let terminals = artifact.terminals.sorted()
        var queue = [SearchConfiguration(stack: [.init(rawValue: 0)], tokens: [])]
        var visited: Set<[StateID]> = [[.init(rawValue: 0)]]
        var cursor = 0
        while cursor < queue.count, cursor < candidateLimit {
            let configuration = queue[cursor]
            cursor += 1
            guard configuration.tokens.count < maxLength else { continue }
            for terminal in terminals {
                switch advance(configuration.stack, lookahead: terminal, artifact: artifact) {
                case .conflict(let cell) where cell == target:
                    return terminal == "$" ? configuration.tokens : configuration.tokens + [terminal]
                case .shifted(let stack) where terminal != "$":
                    if visited.insert(stack).inserted {
                        queue.append(.init(stack: stack, tokens: configuration.tokens + [terminal]))
                    }
                default:
                    break
                }
            }
        }
        return nil
    }

    private static func advance(
        _ initialStack: [StateID],
        lookahead: String,
        artifact: GrammarArtifact
    ) -> AdvanceResult {
        var stack = initialStack
        for _ in 0..<1_000 {
            guard let state = stack.last,
                  let cell = artifact.cell(.init(state: state, symbol: lookahead)),
                  !cell.actions.isEmpty else { return .stopped }
            if cell.actions.count > 1 { return .conflict(cell.id) }
            switch cell.actions[0] {
            case .shift(let target):
                stack.append(target)
                return .shifted(stack)
            case .reduce(let productionID):
                guard let production = artifact.productions.first(where: { $0.id == productionID }),
                      production.rhs.count < stack.count else { return .stopped }
                if !production.rhs.isEmpty { stack.removeLast(production.rhs.count) }
                guard let gotoState = stack.last,
                      let gotoCell = artifact.cell(.init(state: gotoState, symbol: production.lhs)),
                      case .goTo(let target) = gotoCell.actions.first else { return .stopped }
                stack.append(target)
            case .accept, .goTo:
                return .stopped
            }
        }
        return .stopped
    }

    private static func minimalCommonCounterexample(
        witness: [String],
        cell: CellID,
        actions: [TableAction],
        artifact: GrammarArtifact,
        maxSuffixLength: Int,
        candidateLimit: Int
    ) -> [String]? {
        let terminals = artifact.terminals.filter { $0 != "$" }.sorted()
        var suffixes: [[String]] = [[]]
        var cursor = 0
        while cursor < suffixes.count, cursor < candidateLimit {
            let suffix = suffixes[cursor]
            cursor += 1
            let candidate = witness + suffix
            let results = actions.map {
                LRParserRuntime.parse(candidate, artifact: artifact, forcing: (cell, $0))
            }
            if results.allSatisfy({ $0.outcome == .accepted }) {
                return candidate
            }
            if suffix.count < maxSuffixLength {
                suffixes.append(contentsOf: terminals.map { suffix + [$0] })
            }
        }
        return nil
    }
}

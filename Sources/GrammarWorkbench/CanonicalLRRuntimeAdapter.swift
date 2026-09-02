import LR_Parsing

enum CanonicalLRRuntimeAdapter {
    static func parse(
        _ tokens: [String], artifact: GrammarArtifact,
        forcing forcedChoice: (cell: CellID, action: TableAction)?,
        stepLimit: Int, recovery: ParserRecoveryConfiguration,
        resuming checkpoint: ParserCheckpoint?, prefixFrames: [ReplayFrame]
    ) -> ParserRuntimeResult {
        let table = LRRuntimeTable(
            terminals: artifact.terminals,
            productions: artifact.productions.map {
                .init(identity: String($0.id.rawValue), lhs: $0.lhs, rhs: $0.rhs)
            },
            cells: artifact.cells.map { cell in
                .init(state: cell.id.state.rawValue, symbol: cell.id.symbol,
                      actions: cell.actions.map(runtimeAction))
            }
        )
        let result = LRTableRuntime.parse(
            tokens, table: table,
            forcing: forcedChoice.map {
                (state: $0.cell.state.rawValue, symbol: $0.cell.symbol, action: runtimeAction($0.action))
            },
            stepLimit: stepLimit,
            recovery: .init(
                maximumDiagnostics: recovery.maximumDiagnostics,
                synchronizationTerminals: recovery.synchronizationTerminals,
                preferredInsertions: recovery.preferredInsertions
            ),
            resuming: checkpoint.map(runtimeCheckpoint),
            prefixFrames: prefixFrames.map(runtimeFrame)
        )
        return ParserRuntimeResult(
            tokens: tokens,
            tree: result.tree.map(workbenchNode),
            frames: result.frames.enumerated().map { index, frame in
                ReplayFrame(
                    index: index, stack: frame.stack, remainingInput: frame.remainingInput,
                    action: frame.action, state: .init(rawValue: frame.state),
                    cell: frame.symbol.map { .init(state: .init(rawValue: frame.state), symbol: $0) },
                    production: frame.productionIdentity.flatMap(Int.init).map { .init(rawValue: $0) }
                )
            },
            outcome: workbenchOutcome(result.outcome),
            diagnostics: result.diagnostics.enumerated().map { index, diagnostic in
                ParserDiagnostic(
                    index: index, tokenIndex: diagnostic.tokenIndex,
                    state: .init(rawValue: diagnostic.state), unexpected: diagnostic.unexpected,
                    expected: diagnostic.expected, message: diagnostic.message,
                    recovery: diagnostic.recovery.map {
                        switch $0 { case .deletedToken: .deletedToken; case .insertedToken: .insertedToken; case .synchronized: .synchronized }
                    },
                    recoverySymbol: diagnostic.recoverySymbol, recoveryDetail: diagnostic.recoveryDetail
                )
            },
            checkpoints: result.checkpoints.map(workbenchCheckpoint)
        )
    }

    private static func runtimeAction(_ action: TableAction) -> LRRuntimeTable.Action {
        switch action {
        case .shift(let state): .shift(state.rawValue)
        case .reduce(let production): .reduce(String(production.rawValue))
        case .accept: .accept
        case .goTo(let state): .goTo(state.rawValue)
        }
    }

    private static func runtimeNode(_ node: ParseTreeNode) -> LRRuntimeNode {
        .init(symbol: node.symbol, children: node.children.map(runtimeNode),
              productionIdentity: node.production.map { String($0.rawValue) }, isMissing: node.isMissing)
    }

    private static func workbenchNode(_ node: LRRuntimeNode) -> ParseTreeNode {
        .init(symbol: node.symbol, children: node.children.map(workbenchNode),
              production: node.productionIdentity.flatMap(Int.init).map { .init(rawValue: $0) },
              isMissing: node.isMissing)
    }

    private static func runtimeFrame(_ frame: ReplayFrame) -> LRRuntimeFrame {
        .init(stack: frame.stack, remainingInput: frame.remainingInput, action: frame.action,
              state: frame.state?.rawValue ?? 0, symbol: frame.cell?.symbol,
              productionIdentity: frame.production.map { String($0.rawValue) })
    }

    private static func runtimeCheckpoint(_ checkpoint: ParserCheckpoint) -> LRRuntimeCheckpoint {
        .init(tokenIndex: checkpoint.tokenIndex, steps: checkpoint.steps,
              states: checkpoint.states.map(\.rawValue), symbols: checkpoint.symbols,
              nodes: checkpoint.nodes.map(runtimeNode), frameCount: checkpoint.frameCount)
    }

    private static func workbenchCheckpoint(_ checkpoint: LRRuntimeCheckpoint) -> ParserCheckpoint {
        .init(tokenIndex: checkpoint.tokenIndex, steps: checkpoint.steps,
              states: checkpoint.states.map { .init(rawValue: $0) }, symbols: checkpoint.symbols,
              nodes: checkpoint.nodes.map(workbenchNode), frameCount: checkpoint.frameCount)
    }

    private static func workbenchOutcome(_ outcome: LRRuntimeOutcome) -> ParseOutcome {
        switch outcome {
        case .accepted: .accepted
        case .rejected(let message, let expected): .rejected(message: message, expected: expected)
        case .conflict(let state, let symbol):
            .conflict(.init(state: .init(rawValue: state), symbol: symbol))
        case .looping: .looping
        }
    }
}

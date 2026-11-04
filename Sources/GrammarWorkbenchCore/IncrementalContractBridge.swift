import IncrementalParsing

extension GrammarTextSnapshot {
    /// Shared source value used at package boundaries. Workbench retains its
    /// line/column edit façade, while application and validation are delegated
    /// to IncrementalParsing.
    public var incrementalSourceSnapshot: IncrementalParsing.SourceSnapshot {
        precondition(revision >= 0, "document revisions cannot be negative")
        return .init(text: text, revision: .init(UInt64(revision)))
    }
}

extension GrammarIncrementalReuseMetrics {
    public var incrementalReuseMeasurements: [IncrementalParsing.ReuseMeasurement] {
        [
            .init(dimension: .tokens, reused: reusedTokens,
                  rebuilt: createdTokens, removed: removedTokens),
            .init(dimension: .syntaxNodes, reused: reusedNodes,
                  rebuilt: createdNodes, removed: removedNodes),
        ].sorted { $0.dimension.rawValue < $1.dimension.rawValue }
    }
}

extension GrammarIncrementalLexingMetrics {
    public var incrementalExecutionEvidence: IncrementalParsing.IncrementalExecutionEvidence {
        switch strategy {
        case .full:
            return .init(strategy: .full)
        case .incremental:
            return .init(strategy: .incremental)
        case .fallback:
            return .init(
                strategy: .fallback,
                fallback: .init(
                    code: "grammarWorkbench.lexing",
                    detail: fallbackReason ?? "Incremental lexing was unavailable."))
        }
    }
}

extension GrammarIncrementalParsingMetrics {
    public var incrementalExecutionEvidence: IncrementalParsing.IncrementalExecutionEvidence {
        switch strategy {
        case .full:
            return .init(strategy: .full)
        case .incremental:
            return .init(strategy: .incremental)
        case .fallback:
            return .init(
                strategy: .fallback,
                fallback: .init(
                    code: "grammarWorkbench.parsing",
                    detail: fallbackReason ?? "Incremental parsing was unavailable."))
        }
    }
}

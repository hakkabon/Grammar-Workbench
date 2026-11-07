import IncrementalParsing

/// Explicit ownership evidence for the Workbench compatibility layer. Grammar
/// Workbench retains its public snapshot and positioned-tree types, while LR
/// construction and execution are delegated to LR-Parsing's canonical table
/// generator and `LRTableRuntime` through the canonical adapters.
public struct GrammarRuntimeConvergenceEvidence: Hashable, Codable, Sendable {
    public let constructionOwner: String
    public let executionOwner: String
    public let lexing: IncrementalExecutionEvidence
    public let parsing: IncrementalExecutionEvidence

    public init(
        constructionOwner: String,
        executionOwner: String,
        lexing: IncrementalExecutionEvidence,
        parsing: IncrementalExecutionEvidence
    ) {
        self.constructionOwner = constructionOwner
        self.executionOwner = executionOwner
        self.lexing = lexing
        self.parsing = parsing
    }
}

public extension GrammarIncrementalAnalysisSnapshot {
    var runtimeConvergenceEvidence: GrammarRuntimeConvergenceEvidence {
        .init(
            constructionOwner: "LR-Parsing.LRParser",
            executionOwner: "LR-Parsing.LRTableRuntime",
            lexing: incrementalLexing.incrementalExecutionEvidence,
            parsing: incrementalParsing.incrementalExecutionEvidence)
    }
}

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

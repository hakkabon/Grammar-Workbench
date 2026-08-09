import Foundation

public enum GrammarParsingMode: String, Hashable, Codable, Sendable {
    case deterministic
    case generalized
    /// Uses deterministic parsing first and escalates to generalized parsing
    /// only when the input reaches an unresolved ACTION conflict.
    case adaptive
}

public enum GrammarAmbiguitySelection: String, Hashable, Codable, Sendable {
    case requireUnique
    case firstStable
    case shallowest
    case deepest
}

public struct GrammarPlatformParseOptions: Hashable, Codable, Sendable {
    public var mode: GrammarParsingMode
    public var deterministic: GrammarParseOptions
    public var generalized: GrammarGeneralizedParseOptions
    public var ambiguitySelection: GrammarAmbiguitySelection

    public init(
        mode: GrammarParsingMode = .adaptive,
        deterministic: GrammarParseOptions = .init(),
        generalized: GrammarGeneralizedParseOptions = .init(),
        ambiguitySelection: GrammarAmbiguitySelection = .requireUnique
    ) {
        self.mode = mode
        self.deterministic = deterministic
        self.generalized = generalized
        self.ambiguitySelection = ambiguitySelection
    }

    private enum CodingKeys: String, CodingKey {
        case mode, deterministic, generalized, ambiguitySelection
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mode: try values.decodeIfPresent(GrammarParsingMode.self, forKey: .mode) ?? .adaptive,
            deterministic: try values.decodeIfPresent(GrammarParseOptions.self, forKey: .deterministic) ?? .init(),
            generalized: try values.decodeIfPresent(GrammarGeneralizedParseOptions.self, forKey: .generalized) ?? .init(),
            ambiguitySelection: try values.decodeIfPresent(
                GrammarAmbiguitySelection.self, forKey: .ambiguitySelection
            ) ?? .requireUnique
        )
    }
}

public struct GrammarPlatformParseRequest: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let input: String
    public let options: GrammarPlatformParseOptions

    public init(
        id: String = UUID().uuidString,
        input: String,
        options: GrammarPlatformParseOptions = .init()
    ) {
        self.id = id
        self.input = input
        self.options = options
    }
}

public enum GrammarPlatformEngine: String, Hashable, Codable, Sendable {
    case deterministic
    case generalized
}

public enum GrammarPlatformParseStatus: String, Hashable, Codable, Sendable {
    case accepted
    case recovered
    case ambiguous
    case rejected
    case conflict
    case limited
    case cancelled
    case invalid
}

public struct GrammarPlatformParseMetrics: Hashable, Codable, Sendable {
    public let elapsedNanoseconds: UInt64
    public let deterministicAttempts: Int
    public let generalizedConfigurations: Int
    public let generalizedBranchPoints: Int
    public let acceptedAlternatives: Int
    public let reachedLimits: [GrammarGeneralizedLimit]
}

/// A common envelope over deterministic and generalized parsing. The original
/// engine result remains available for detailed replay or forest inspection.
public struct GrammarPlatformParseResult: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let status: GrammarPlatformParseStatus
    public let engine: GrammarPlatformEngine
    public let deterministic: GrammarParseResult?
    public let generalized: GrammarGeneralizedParseResult?
    public let selectedTree: GrammarSyntaxNode?
    public let selectedAlternativeID: String?
    public let metrics: GrammarPlatformParseMetrics
    public let decision: String

    public var isAccepted: Bool {
        status == .accepted || status == .recovered
            || (selectedTree != nil && (status == .ambiguous || status == .limited))
    }
}

public struct GrammarPlatformBatchOptions: Hashable, Codable, Sendable {
    public var maximumConcurrentRequests: Int

    public init(maximumConcurrentRequests: Int = 4) {
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
    }
}

public struct GrammarPlatformBatchResult: Sendable {
    public let results: [GrammarPlatformParseResult]
    public let metrics: GrammarPlatformBatchMetrics
    public var accepted: Int { results.count(where: \.isAccepted) }
    public var failed: Int { results.count - accepted }
}

public struct GrammarPlatformBatchMetrics: Hashable, Codable, Sendable {
    public let requestCount: Int
    public let maximumConcurrentRequests: Int
    public let completedRequests: Int
    public let cancelledRequests: Int
}

public struct GrammarPlatformSemanticResult<Value: Sendable>: Sendable {
    public let parse: GrammarPlatformParseResult
    public let value: Value
}

/// High-level parsing orchestration for applications that need deterministic
/// speed, generalized correctness at conflicts, bounded resource use, and one
/// stable result contract.
public struct GrammarParsingPlatform: Sendable {
    public let compilation: GrammarCompilation

    public init(compilation: GrammarCompilation) throws {
        guard compilation.succeeded else {
            throw GrammarWorkbenchAPIError.compilationFailed(
                compilation.diagnostics.first?.message ?? "The grammar did not compile."
            )
        }
        self.compilation = compilation
    }

    public func parse(_ request: GrammarPlatformParseRequest) -> GrammarPlatformParseResult {
        let started = DispatchTime.now().uptimeNanoseconds
        switch request.options.mode {
        case .deterministic:
            return deterministicResult(request, started: started, decision: "Deterministic mode was requested.")
        case .generalized:
            return generalizedResult(
                request,
                result: compilation.parseGeneralized(
                    request.input, options: request.options.generalized
                ),
                started: started,
                deterministicAttempts: 0,
                decision: "Generalized mode was requested."
            )
        case .adaptive:
            let deterministic = compilation.parse(
                request.input, options: request.options.deterministic
            )
            guard deterministic.status == .conflict else {
                return deterministicResult(
                    request,
                    result: deterministic,
                    started: started,
                    decision: "Adaptive mode completed with the deterministic engine."
                )
            }
            return generalizedResult(
                request,
                result: compilation.parseGeneralized(
                    request.input, options: request.options.generalized
                ),
                started: started,
                deterministicAttempts: 1,
                deterministic: deterministic,
                decision: "Adaptive mode escalated after the deterministic engine reached an unresolved conflict."
            )
        }
    }

    public func parseCancellable(
        _ request: GrammarPlatformParseRequest
    ) async -> GrammarPlatformParseResult {
        let started = DispatchTime.now().uptimeNanoseconds
        if Task.isCancelled { return cancelledResult(request, started: started) }
        switch request.options.mode {
        case .deterministic:
            await Task.yield()
            if Task.isCancelled { return cancelledResult(request, started: started) }
            return deterministicResult(request, started: started, decision: "Deterministic mode was requested.")
        case .generalized:
            return generalizedResult(
                request,
                result: await compilation.parseGeneralizedCancellable(
                    request.input, options: request.options.generalized
                ),
                started: started,
                deterministicAttempts: 0,
                decision: "Generalized mode was requested."
            )
        case .adaptive:
            let deterministic = compilation.parse(
                request.input, options: request.options.deterministic
            )
            if Task.isCancelled { return cancelledResult(request, started: started) }
            guard deterministic.status == .conflict else {
                return deterministicResult(
                    request, result: deterministic, started: started,
                    decision: "Adaptive mode completed with the deterministic engine."
                )
            }
            return generalizedResult(
                request,
                result: await compilation.parseGeneralizedCancellable(
                    request.input, options: request.options.generalized
                ),
                started: started,
                deterministicAttempts: 1,
                deterministic: deterministic,
                decision: "Adaptive mode escalated after the deterministic engine reached an unresolved conflict."
            )
        }
    }

    public func parseBatch(
        _ requests: [GrammarPlatformParseRequest],
        options: GrammarPlatformBatchOptions = .init()
    ) async -> GrammarPlatformBatchResult {
        guard !requests.isEmpty else {
            return .init(results: [], metrics: .init(
                requestCount: 0, maximumConcurrentRequests: 0,
                completedRequests: 0, cancelledRequests: 0
            ))
        }
        let limit = min(options.maximumConcurrentRequests, requests.count)
        var results = Array<GrammarPlatformParseResult?>(repeating: nil, count: requests.count)
        await withTaskGroup(of: (Int, GrammarPlatformParseResult).self) { group in
            var next = 0
            for _ in 0..<limit {
                let index = next
                next += 1
                group.addTask { (index, await parseCancellable(requests[index])) }
            }
            while let (index, result) = await group.next() {
                results[index] = result
                if next < requests.count {
                    let pending = next
                    next += 1
                    group.addTask { (pending, await parseCancellable(requests[pending])) }
                }
            }
        }
        let completed = results.compactMap { $0 }
        return .init(
            results: completed,
            metrics: .init(
                requestCount: requests.count,
                maximumConcurrentRequests: limit,
                completedRequests: completed.count,
                cancelledRequests: completed.count { $0.status == .cancelled }
            )
        )
    }

    public func parse<R: GrammarSemanticReducer>(
        _ request: GrammarPlatformParseRequest,
        using reducer: R
    ) throws -> GrammarPlatformSemanticResult<R.Value> {
        let result = parse(request)
        guard let tree = result.selectedTree else {
            if let generalized = result.generalized {
                throw GrammarSemanticError.generalizedParseDidNotComplete(generalized.status)
            }
            throw GrammarSemanticError.parseDidNotComplete(result.deterministic?.status ?? .invalidGrammar)
        }
        return .init(
            parse: result,
            value: try compilation.evaluate(tree, using: reducer)
        )
    }

    private func deterministicResult(
        _ request: GrammarPlatformParseRequest,
        result: GrammarParseResult? = nil,
        started: UInt64,
        decision: String
    ) -> GrammarPlatformParseResult {
        let parsed = result ?? compilation.parse(
            request.input, options: request.options.deterministic
        )
        let status: GrammarPlatformParseStatus = switch parsed.status {
        case .accepted: .accepted
        case .acceptedWithRecovery: .recovered
        case .rejected, .looping: .rejected
        case .conflict: .conflict
        case .invalidGrammar: .invalid
        }
        return .init(
            id: request.id, status: status, engine: .deterministic,
            deterministic: parsed, generalized: nil,
            selectedTree: parsed.syntaxTree, selectedAlternativeID: nil,
            metrics: .init(
                elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                deterministicAttempts: 1, generalizedConfigurations: 0,
                generalizedBranchPoints: 0,
                acceptedAlternatives: parsed.syntaxTree == nil ? 0 : 1,
                reachedLimits: []
            ),
            decision: decision
        )
    }

    private func generalizedResult(
        _ request: GrammarPlatformParseRequest,
        result: GrammarGeneralizedParseResult,
        started: UInt64,
        deterministicAttempts: Int,
        deterministic: GrammarParseResult? = nil,
        decision: String
    ) -> GrammarPlatformParseResult {
        let selected = select(result.forest.alternatives, policy: request.options.ambiguitySelection)
        let status: GrammarPlatformParseStatus = switch result.status {
        case .accepted: .accepted
        case .ambiguous: .ambiguous
        case .rejected: .rejected
        case .truncated: .limited
        case .cancelled: .cancelled
        case .invalidGrammar, .lexicalError: .invalid
        }
        let selectionDecision = result.isAmbiguous
            ? " \(selectionDescription(request.options.ambiguitySelection, selected: selected))."
            : ""
        return .init(
            id: request.id, status: status, engine: .generalized,
            deterministic: deterministic, generalized: result,
            selectedTree: selected?.tree, selectedAlternativeID: selected?.id,
            metrics: .init(
                elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                deterministicAttempts: deterministicAttempts,
                generalizedConfigurations: result.metrics.exploredConfigurations,
                generalizedBranchPoints: result.metrics.branchPoints,
                acceptedAlternatives: result.alternatives.count,
                reachedLimits: result.reachedLimits
            ),
            decision: decision + selectionDecision
        )
    }

    private func cancelledResult(
        _ request: GrammarPlatformParseRequest, started: UInt64
    ) -> GrammarPlatformParseResult {
        .init(
            id: request.id, status: .cancelled, engine: .generalized,
            deterministic: nil, generalized: nil,
            selectedTree: nil, selectedAlternativeID: nil,
            metrics: .init(
                elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                deterministicAttempts: 0, generalizedConfigurations: 0,
                generalizedBranchPoints: 0, acceptedAlternatives: 0, reachedLimits: []
            ),
            decision: "Parsing was cancelled before an engine completed."
        )
    }

    private func select(
        _ alternatives: [GrammarGeneralizedAlternative],
        policy: GrammarAmbiguitySelection
    ) -> GrammarGeneralizedAlternative? {
        guard alternatives.count > 1 else { return alternatives.first }
        switch policy {
        case .requireUnique: return nil
        case .firstStable: return alternatives.min { $0.id < $1.id }
        case .shallowest:
            return alternatives.min { treeDepth($0.tree) == treeDepth($1.tree) ? $0.id < $1.id : treeDepth($0.tree) < treeDepth($1.tree) }
        case .deepest:
            return alternatives.max { treeDepth($0.tree) == treeDepth($1.tree) ? $0.id > $1.id : treeDepth($0.tree) < treeDepth($1.tree) }
        }
    }

    private func treeDepth(_ node: GrammarSyntaxNode) -> Int {
        1 + (node.children.map(treeDepth).max() ?? 0)
    }

    private func selectionDescription(
        _ policy: GrammarAmbiguitySelection,
        selected: GrammarGeneralizedAlternative?
    ) -> String {
        switch policy {
        case .requireUnique: "Ambiguity selection requires a unique tree, so no alternative was selected"
        case .firstStable: "Selected stable alternative \(selected?.id ?? "none")"
        case .shallowest: "Selected shallowest alternative \(selected?.id ?? "none")"
        case .deepest: "Selected deepest alternative \(selected?.id ?? "none")"
        }
    }
}

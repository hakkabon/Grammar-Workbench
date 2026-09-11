import Foundation

public struct GrammarDependencyEdge: Identifiable, Hashable, Codable, Sendable {
    public let from: String
    public let to: String
    public var id: String { "\(from)\u{1f}\(to)" }
}

public struct GrammarDuplicateProductionGroup: Identifiable, Hashable, Codable, Sendable {
    public let lhs: String
    public let rhs: [String]
    public let productionIDs: [Int]
    public var id: String { "\(lhs)\u{1f}\(rhs.joined(separator: "\u{1f}"))" }
    public var text: String { "\(lhs) → \(rhs.isEmpty ? "ε" : rhs.joined(separator: " "))" }
}

public struct GrammarStructuralStatistics: Hashable, Codable, Sendable {
    public let productions: Int
    public let nonterminals: Int
    public let terminals: Int
    public let dependencyEdges: Int
    public let nullableNonterminals: Int
    public let duplicateProductions: Int
}

public struct GrammarStructuralAnalysis: Hashable, Codable, Sendable {
    public let startSymbol: String
    public let statistics: GrammarStructuralStatistics
    public let reachableNonterminals: [String]
    public let unreachableNonterminals: [String]
    public let productiveNonterminals: [String]
    public let unproductiveNonterminals: [String]
    public let nullableNonterminals: [String]
    public let directlyLeftRecursiveNonterminals: [String]
    public let indirectlyLeftRecursiveComponents: [[String]]
    public let dependencyEdges: [GrammarDependencyEdge]
    public let stronglyConnectedComponents: [[String]]
    public let duplicateProductions: [GrammarDuplicateProductionGroup]
    public let unusedTerminals: [String]
    public let first: [String: [String]]
    public let follow: [String: [String]]
}

public enum GrammarTransformationKind: String, CaseIterable, Codable, Sendable {
    case removeDuplicateProductions
    case removeUnreachableProductions
    case removeUnproductiveProductions

    public var title: String {
        switch self {
        case .removeDuplicateProductions: "Remove duplicate productions"
        case .removeUnreachableProductions: "Remove unreachable productions"
        case .removeUnproductiveProductions: "Remove unproductive productions"
        }
    }
}

public enum GrammarTransformationAssurance: String, Codable, Sendable {
    /// The operation is a classical CFG-language-preserving cleanup when its
    /// preconditions hold. Runtime artifacts may still become smaller or less ambiguous.
    case languagePreserving
    /// The operation needs corpus and test validation before application.
    case requiresValidation
}

public struct GrammarTransformationOperation: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let line: Int
    public let endLine: Int
    public let symbols: [String]
    public let reason: String
    public let assurance: GrammarTransformationAssurance
    public var lines: ClosedRange<Int> { line...max(line, endLine) }
}

public struct GrammarTransformationPlan: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let kind: GrammarTransformationKind
    public let sourceFingerprint: String
    public let operations: [GrammarTransformationOperation]
    public let explanation: String

    public var affectedLines: [Int] { Array(Set(operations.flatMap { Array($0.lines) })).sorted() }
    public var hasChanges: Bool { !operations.isEmpty }
}

public enum GrammarTransformationError: Error, LocalizedError {
    case compilationFailed(String)
    case sourceChanged
    case unsupportedNotation(GrammarSourceNotation)

    public var errorDescription: String? {
        switch self {
        case .compilationFailed(let message): message
        case .sourceChanged: "The grammar changed after this transformation plan was created."
        case .unsupportedNotation(let notation): "Source-preserving \(notation.rawValue) transformations are not available."
        }
    }
}

public struct GrammarBehaviorCorpusEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let input: String
    public let origin: String

    public init(id: String = UUID().uuidString, input: String, origin: String = "user") {
        self.id = id
        self.input = input
        self.origin = origin
    }
}

public struct GrammarBehaviorComparisonOptions: Hashable, Codable, Sendable {
    public var maximumGeneratedInputs: Int
    public var maximumGeneratedCandidates: Int
    public var maximumDerivationSteps: Int
    public var maximumSententialSymbols: Int
    public var generalizedLimits: GrammarGeneralizedParseOptions

    public init(
        maximumGeneratedInputs: Int = 64,
        maximumGeneratedCandidates: Int = 4096,
        maximumDerivationSteps: Int = 12,
        maximumSententialSymbols: Int = 24,
        generalizedLimits: GrammarGeneralizedParseOptions = .init(
            maximumConfigurations: 4096, maximumSteps: 100_000, maximumTrees: 8
        )
    ) {
        self.maximumGeneratedInputs = max(0, maximumGeneratedInputs)
        self.maximumGeneratedCandidates = max(1, maximumGeneratedCandidates)
        self.maximumDerivationSteps = max(1, maximumDerivationSteps)
        self.maximumSententialSymbols = max(1, maximumSententialSymbols)
        self.generalizedLimits = generalizedLimits
    }
}

public enum GrammarBehaviorOutcome: String, Hashable, Codable, Sendable {
    case accepted
    case ambiguous
    case rejected
    case limited
    case invalid

    public var belongsToLanguage: Bool { self == .accepted || self == .ambiguous }
}

public struct GrammarBehaviorComparisonCase: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let input: String
    public let origin: String
    public let before: GrammarBehaviorOutcome
    public let after: GrammarBehaviorOutcome
    public var membershipChanged: Bool { before.belongsToLanguage != after.belongsToLanguage }
}

public struct GrammarBehaviorComparison: Hashable, Codable, Sendable {
    public let cases: [GrammarBehaviorComparisonCase]
    public let generatedInputs: Int
    public let generationReachedLimit: Bool
    public var discrepancies: [GrammarBehaviorComparisonCase] { cases.filter(\.membershipChanged) }
    public var agreesOnCorpus: Bool { discrepancies.isEmpty }
    public var conclusion: String {
        if !agreesOnCorpus { return "The grammars differ on the bounded comparison corpus." }
        return generationReachedLimit
            ? "No difference was found before the bounded generator reached its limit."
            : "No difference was found in the bounded comparison corpus."
    }
}

public struct GrammarTransformationResult: Sendable {
    public let plan: GrammarTransformationPlan
    public let proposedSource: String
    public let compilation: GrammarCompilation
    public let artifactDiff: GrammarArtifactDiff?
    public let behavior: GrammarBehaviorComparison
    public let testsBefore: WorkbenchTestReport?
    public let testsAfter: WorkbenchTestReport?

    public var isSafeToApply: Bool {
        compilation.succeeded && behavior.agreesOnCorpus && (testsAfter?.failed ?? 0) == 0
    }
}

public enum GrammarEngineering {
    public static func analyze(_ compilation: GrammarCompilation) throws -> GrammarStructuralAnalysis {
        guard let grammar = compilation.parsedGrammar, let analysis = compilation.analysis else {
            throw GrammarTransformationError.compilationFailed(
                compilation.diagnostics.first(where: { $0.severity == .error })?.message
                    ?? "The grammar did not compile."
            )
        }
        return GrammarStructuralAnalyzer.analyze(grammar, first: analysis.first, follow: analysis.follow)
    }

    public static func plan(
        _ kind: GrammarTransformationKind,
        for compilation: GrammarCompilation
    ) throws -> GrammarTransformationPlan {
        guard compilation.request.notation == .workbench else {
            throw GrammarTransformationError.unsupportedNotation(compilation.request.notation)
        }
        let structural = try analyze(compilation)
        guard let grammar = compilation.parsedGrammar else {
            throw GrammarTransformationError.compilationFailed("The grammar did not compile.")
        }
        let operations: [GrammarTransformationOperation]
        let explanation: String
        switch kind {
        case .removeDuplicateProductions:
            let byID = Dictionary(uniqueKeysWithValues: grammar.productions.map { ($0.id, $0) })
            let removableIDs = Set(structural.duplicateProductions.flatMap { group -> [Int] in
                guard let original = group.productionIDs.first.flatMap({ byID[$0] }) else { return [] }
                return group.productionIDs.dropFirst().filter {
                    byID[$0]?.range.start.line != original.range.start.line
                }
            })
            operations = grammar.productions.filter { removableIDs.contains($0.id) }.map {
                operation($0, symbols: [$0.lhs], reason: "This production has the same left- and right-hand sides as an earlier production.")
            }
            explanation = "Duplicate alternatives do not add strings to a context-free language and can introduce redundant parser actions."
        case .removeUnreachableProductions:
            let symbols = Set(structural.unreachableNonterminals)
            operations = declarationOperations(
                grammar.productions.filter { symbols.contains($0.lhs) },
                reason: "This nonterminal cannot be reached from the start symbol."
            )
            explanation = "Productions unreachable from the start symbol cannot participate in any complete derivation."
        case .removeUnproductiveProductions:
            let symbols = Set(structural.unproductiveNonterminals)
            let removable = Set(grammar.productions.filter {
                if $0.lhs == grammar.startSymbol {
                    return !symbols.contains(grammar.startSymbol)
                        && $0.rhs.contains(where: symbols.contains)
                }
                return symbols.contains($0.lhs) || $0.rhs.contains(where: symbols.contains)
            }.map(\.id))
            operations = safeDeclarationOperations(
                removableProductionIDs: removable, allProductions: grammar.productions,
                reason: "This nonterminal cannot derive a string containing only terminals."
            )
            explanation = "Non-start productions that cannot derive terminal input cannot contribute an accepted sentence."
        }
        return .init(
            id: "\(kind.rawValue)-\(fingerprint(compilation.request.source))",
            kind: kind, sourceFingerprint: fingerprint(compilation.request.source),
            operations: operations.sorted { $0.line < $1.line }, explanation: explanation
        )
    }

    public static func apply(_ plan: GrammarTransformationPlan, to source: String) throws -> String {
        guard fingerprint(source) == plan.sourceFingerprint else { throw GrammarTransformationError.sourceChanged }
        let removed = Set(plan.affectedLines)
        return source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap {
            removed.contains($0.offset + 1) ? nil : String($0.element)
        }.joined(separator: "\n")
    }

    public static func execute(
        _ plan: GrammarTransformationPlan,
        request: GrammarCompilationRequest,
        corpus: [GrammarBehaviorCorpusEntry] = [],
        tests: [WorkbenchTestCase] = [],
        options: GrammarBehaviorComparisonOptions = .init()
    ) throws -> GrammarTransformationResult {
        let before = GrammarWorkbenchAPI.compile(request)
        let source = try apply(plan, to: request.source)
        let after = GrammarWorkbenchAPI.compile(.init(
            source: source, algorithm: request.algorithm, notation: request.notation
        ))
        let comparison = compare(before, after, corpus: corpus, options: options)
        return .init(
            plan: plan, proposedSource: source, compilation: after,
            artifactDiff: try? after.diff(from: before), behavior: comparison,
            testsBefore: tests.isEmpty ? nil : before.runTests(tests),
            testsAfter: tests.isEmpty ? nil : after.runTests(tests)
        )
    }

    public static func compare(
        _ before: GrammarCompilation,
        _ after: GrammarCompilation,
        corpus: [GrammarBehaviorCorpusEntry] = [],
        options: GrammarBehaviorComparisonOptions = .init()
    ) -> GrammarBehaviorComparison {
        let generated = generatedCorpus(from: before, options: options)
        var seen: Set<String> = []
        let entries = (corpus + generated.entries).filter { seen.insert($0.input).inserted }
        let cases = entries.map { entry in
            GrammarBehaviorComparisonCase(
                id: entry.id, input: entry.input, origin: entry.origin,
                before: outcome(before, input: entry.input, options: options),
                after: outcome(after, input: entry.input, options: options)
            )
        }
        return .init(
            cases: cases, generatedInputs: generated.entries.count,
            generationReachedLimit: generated.reachedLimit
        )
    }

    private static func operation(
        _ production: GrammarProduction, symbols: [String], reason: String
    ) -> GrammarTransformationOperation {
        .init(
            id: "line-\(production.range.start.line)-\(production.id)",
            line: production.range.start.line, endLine: production.range.end.line,
            symbols: symbols, reason: reason,
            assurance: .languagePreserving
        )
    }

    private static func declarationOperations(
        _ productions: [GrammarProduction], reason: String
    ) -> [GrammarTransformationOperation] {
        Dictionary(grouping: productions, by: { $0.range.start.line }).compactMap { line, values in
            guard let first = values.first else { return nil }
            return .init(
                id: "line-\(line)-\(first.lhs)", line: line,
                endLine: values.map(\.range.end.line).max() ?? line,
                symbols: Array(Set(values.map(\.lhs))).sorted(), reason: reason,
                assurance: .languagePreserving
            )
        }
    }

    private static func safeDeclarationOperations(
        removableProductionIDs: Set<Int>,
        allProductions: [GrammarProduction],
        reason: String
    ) -> [GrammarTransformationOperation] {
        let operations: [GrammarTransformationOperation] = Dictionary(
            grouping: allProductions, by: { $0.range.start.line }
        ).compactMap { line, values in
            guard !values.isEmpty, values.allSatisfy({ removableProductionIDs.contains($0.id) }) else { return nil }
            return .init(
                id: "line-\(line)-unproductive", line: line,
                endLine: values.map(\.range.end.line).max() ?? line,
                symbols: Array(Set(values.flatMap { [$0.lhs] + $0.rhs })).sorted(),
                reason: reason, assurance: .languagePreserving
            )
        }
        let coveredLines = Set(operations.flatMap { Array($0.lines) })
        let coveredIDs = Set(allProductions.filter { coveredLines.contains($0.range.start.line) }.map(\.id))
        return removableProductionIDs.isSubset(of: coveredIDs) ? operations : []
    }

    private static func outcome(
        _ compilation: GrammarCompilation,
        input: String,
        options: GrammarBehaviorComparisonOptions
    ) -> GrammarBehaviorOutcome {
        guard let platform = try? GrammarParsingPlatform(compilation: compilation) else { return .invalid }
        var generalized = options.generalizedLimits
        generalized.exploresResolvedConflicts = true
        let result = platform.parse(.init(
            id: input, input: input,
            options: .init(mode: .generalized, generalized: generalized, ambiguitySelection: .firstStable)
        ))
        switch result.status {
        case .accepted, .recovered: return .accepted
        case .ambiguous: return .ambiguous
        case .limited: return result.isAccepted ? .ambiguous : .limited
        case .rejected, .conflict, .cancelled: return .rejected
        case .invalid: return .invalid
        }
    }

    private static func generatedCorpus(
        from compilation: GrammarCompilation,
        options: GrammarBehaviorComparisonOptions
    ) -> (entries: [GrammarBehaviorCorpusEntry], reachedLimit: Bool) {
        guard options.maximumGeneratedInputs > 0,
              let grammar = compilation.parsedGrammar,
              grammar.lexerRules.isEmpty else { return ([], false) }
        let nonterminals = Set(grammar.nonterminals)
        let byLHS = Dictionary(grouping: grammar.productions, by: \.lhs)
        struct Candidate: Hashable { let symbols: [String]; let steps: Int }
        var queue = [Candidate(symbols: [grammar.startSymbol], steps: 0)]
        var cursor = 0
        var seen: Set<[String]> = [[grammar.startSymbol]]
        var outputs: [GrammarBehaviorCorpusEntry] = []
        var outputValues: Set<String> = []
        var reachedLimit = false
        while cursor < queue.count {
            let candidate = queue[cursor]
            cursor += 1
            if let index = candidate.symbols.firstIndex(where: { nonterminals.contains($0) }) {
                guard candidate.steps < options.maximumDerivationSteps else { reachedLimit = true; continue }
                for production in byLHS[candidate.symbols[index], default: []] {
                    var next = candidate.symbols
                    next.replaceSubrange(index...index, with: production.rhs)
                    guard next.count <= options.maximumSententialSymbols else { reachedLimit = true; continue }
                    if seen.insert(next).inserted {
                        guard queue.count < options.maximumGeneratedCandidates else {
                            reachedLimit = true
                            continue
                        }
                        queue.append(.init(symbols: next, steps: candidate.steps + 1))
                    }
                }
            } else {
                let input = candidate.symbols.joined(separator: " ")
                if outputValues.insert(input).inserted {
                    outputs.append(.init(id: "generated-\(outputs.count)", input: input, origin: "generated"))
                    if outputs.count == options.maximumGeneratedInputs {
                        reachedLimit = cursor < queue.count
                        break
                    }
                }
            }
        }
        return (outputs, reachedLimit)
    }

    private static func fingerprint(_ source: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in source.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
}

public extension GrammarCompilation {
    func structuralAnalysis() throws -> GrammarStructuralAnalysis {
        try GrammarEngineering.analyze(self)
    }

    func transformationPlan(
        _ kind: GrammarTransformationKind
    ) throws -> GrammarTransformationPlan {
        try GrammarEngineering.plan(kind, for: self)
    }
}

enum GrammarStructuralAnalyzer {
    static func analyze(
        _ grammar: ParsedGrammar,
        first: [String: [String]],
        follow: [String: [String]]
    ) -> GrammarStructuralAnalysis {
        let nonterminals = Set(grammar.nonterminals)
        let byLHS = Dictionary(grouping: grammar.productions, by: \.lhs)
        var reachable: Set<String> = [grammar.startSymbol]
        var changed = true
        while changed {
            changed = false
            for lhs in reachable {
                for symbol in byLHS[lhs, default: []].flatMap(\.rhs) where nonterminals.contains(symbol) {
                    changed = reachable.insert(symbol).inserted || changed
                }
            }
        }
        var productive: Set<String> = []
        changed = true
        while changed {
            changed = false
            for production in grammar.productions
            where production.rhs.allSatisfy({ !nonterminals.contains($0) || productive.contains($0) }) {
                changed = productive.insert(production.lhs).inserted || changed
            }
        }
        var nullable: Set<String> = []
        changed = true
        while changed {
            changed = false
            for production in grammar.productions
            where production.rhs.allSatisfy({ nonterminals.contains($0) && nullable.contains($0) }) {
                changed = nullable.insert(production.lhs).inserted || changed
            }
        }
        let edges = Set(grammar.productions.flatMap { production in
            production.rhs.filter { nonterminals.contains($0) }.map {
                GrammarDependencyEdge(from: production.lhs, to: $0)
            }
        })
        let graph = Dictionary(grouping: edges, by: \.from).mapValues { Set($0.map(\.to)) }
        let components = stronglyConnected(Array(nonterminals), graph: graph)
        var leadingGraph: [String: Set<String>] = [:]
        for production in grammar.productions {
            for symbol in production.rhs {
                guard nonterminals.contains(symbol) else { break }
                leadingGraph[production.lhs, default: []].insert(symbol)
                if !nullable.contains(symbol) { break }
            }
        }
        let leadingComponents = stronglyConnected(Array(nonterminals), graph: leadingGraph)
        let direct = Set(grammar.productions.compactMap { $0.rhs.first == $0.lhs ? $0.lhs : nil })
        let indirect = leadingComponents.filter { $0.count > 1 }
        let duplicateGroups = Dictionary(grouping: grammar.productions) {
            "\($0.lhs)\u{0}\($0.rhs.joined(separator: "\u{0}"))"
        }.values.filter { $0.count > 1 }.map { values in
            GrammarDuplicateProductionGroup(
                lhs: values[0].lhs, rhs: values[0].rhs,
                productionIDs: values.map(\.id).sorted()
            )
        }.sorted { $0.id < $1.id }
        let used = Set(grammar.productions.flatMap(\.rhs))
        return .init(
            startSymbol: grammar.startSymbol,
            statistics: .init(
                productions: grammar.productions.count, nonterminals: grammar.nonterminals.count,
                terminals: grammar.terminals.count, dependencyEdges: edges.count,
                nullableNonterminals: nullable.count,
                duplicateProductions: duplicateGroups.reduce(0) { $0 + $1.productionIDs.count - 1 }
            ),
            reachableNonterminals: reachable.sorted(),
            unreachableNonterminals: nonterminals.subtracting(reachable).sorted(),
            productiveNonterminals: productive.sorted(),
            unproductiveNonterminals: nonterminals.subtracting(productive).sorted(),
            nullableNonterminals: nullable.sorted(),
            directlyLeftRecursiveNonterminals: direct.sorted(),
            indirectlyLeftRecursiveComponents: indirect,
            dependencyEdges: edges.sorted { $0.id < $1.id },
            stronglyConnectedComponents: components.filter { $0.count > 1 },
            duplicateProductions: duplicateGroups,
            unusedTerminals: Set(grammar.terminals).subtracting(used).sorted(),
            first: first, follow: follow
        )
    }

    static func stronglyConnected(_ symbols: [String], graph: [String: Set<String>]) -> [[String]] {
        var visited: Set<String> = []
        var order: [String] = []
        func visit(_ symbol: String) {
            guard visited.insert(symbol).inserted else { return }
            for next in graph[symbol, default: []].sorted() { visit(next) }
            order.append(symbol)
        }
        for symbol in symbols.sorted() { visit(symbol) }
        var reverse: [String: Set<String>] = [:]
        for (from, targets) in graph { for target in targets { reverse[target, default: []].insert(from) } }
        visited = []
        var result: [[String]] = []
        func collect(_ symbol: String, into component: inout [String]) {
            guard visited.insert(symbol).inserted else { return }
            component.append(symbol)
            for next in reverse[symbol, default: []].sorted() { collect(next, into: &component) }
        }
        for symbol in order.reversed() where !visited.contains(symbol) {
            var component: [String] = []
            collect(symbol, into: &component)
            result.append(component.sorted())
        }
        return result.sorted { ($0.first ?? "") < ($1.first ?? "") }
    }
}

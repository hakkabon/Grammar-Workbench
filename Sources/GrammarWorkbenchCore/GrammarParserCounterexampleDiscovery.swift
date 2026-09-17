import Foundation
import Grammar
import Parser

private final class CounterexampleEvaluationState {
    var count = 0
    var exhausted = false
}

public struct GrammarParserCounterexampleLimits: Hashable, Codable, Sendable {
    public var maximumCandidates: Int
    public var maximumEvaluations: Int
    public var maximumTokens: Int

    public init(
        maximumCandidates: Int = 64,
        maximumEvaluations: Int = 256,
        maximumTokens: Int = 8
    ) {
        self.maximumCandidates = maximumCandidates
        self.maximumEvaluations = maximumEvaluations
        self.maximumTokens = maximumTokens
    }
}

public struct GrammarParserCounterexampleSignature: Hashable, Codable, Sendable {
    public let law: GrammarExecutableLaw
    public let violations: [String]

    public init(_ discrepancy: ParseLawDiscrepancy) {
        law = discrepancy.witness.law
        violations = (
            discrepancy.evaluation.baseline.violations.map {
                "baseline|\($0.law.rawValue)|\($0.path)"
            }
            + discrepancy.evaluation.candidate.violations.map {
                "candidate|\($0.law.rawValue)|\($0.path)"
            }
            + discrepancy.evaluation.violations.map {
                "comparison|\($0.law.rawValue)|\($0.path)"
            }
        ).sorted()
    }
}

public struct GrammarParserCounterexample: Hashable, Codable, Sendable {
    public let signature: GrammarParserCounterexampleSignature
    public let initialTokens: [String]
    public let minimizedTokens: [String]
    public let initialDiscrepancy: ParseLawDiscrepancy
    public let minimizedDiscrepancy: ParseLawDiscrepancy
    public let oneMinimal: Bool
}

public struct GrammarParserCounterexampleSearchResult: Hashable, Codable, Sendable {
    public let candidatesConsidered: Int
    public let evaluations: Int
    public let exhaustedCandidates: Bool
    public let exhaustedEvaluationBudget: Bool
    public let counterexample: GrammarParserCounterexample?

    public var foundCounterexample: Bool { counterexample != nil }
}

public enum GrammarParserCounterexampleError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimits
    case emptyToken
    case candidateTooLong(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits:
            "Counterexample bounds must all be positive."
        case .emptyToken:
            "Counterexample candidates cannot contain empty token spellings."
        case .candidateTooLong(let count):
            "Counterexample candidate has \(count) tokens, beyond the configured bound."
        }
    }
}

/// Bounded, deterministic discovery and deletion minimization. Parser remains
/// the oracle: callers must return its fingerprinted discrepancy artifact for
/// every candidate that preserves a failure.
public enum GrammarParserCounterexampleDiscovery {
    public typealias Evaluator = ([String]) throws -> ParseLawDiscrepancy?

    public static func breadthFirstCandidates(
        alphabet: [String], maximumTokens: Int
    ) throws -> [[String]] {
        guard maximumTokens >= 0 else { throw GrammarParserCounterexampleError.invalidLimits }
        let alphabet = Array(Set(alphabet)).sorted()
        guard alphabet.allSatisfy({ !$0.isEmpty }) else {
            throw GrammarParserCounterexampleError.emptyToken
        }
        var result: [[String]] = [[]]
        var level: [[String]] = [[]]
        guard maximumTokens > 0 else { return result }
        for _ in 1...maximumTokens {
            level = level.flatMap { prefix in alphabet.map { prefix + [$0] } }
            result.append(contentsOf: level)
        }
        return result
    }

    public static func discover(
        candidates: [[String]],
        limits: GrammarParserCounterexampleLimits = .init(),
        evaluate: Evaluator
    ) throws -> GrammarParserCounterexampleSearchResult {
        guard limits.maximumCandidates > 0,
              limits.maximumEvaluations > 0,
              limits.maximumTokens > 0 else {
            throw GrammarParserCounterexampleError.invalidLimits
        }
        for candidate in candidates {
            guard candidate.allSatisfy({ !$0.isEmpty }) else {
                throw GrammarParserCounterexampleError.emptyToken
            }
            guard candidate.count <= limits.maximumTokens else {
                throw GrammarParserCounterexampleError.candidateTooLong(candidate.count)
            }
        }

        struct Sequence: Hashable { let tokens: [String] }
        enum Cached { case passing; case failing(ParseLawDiscrepancy) }

        var cache: [Sequence: Cached] = [:]
        let evaluationState = CounterexampleEvaluationState()

        func evaluateCached(_ tokens: [String]) throws -> ParseLawDiscrepancy? {
            let key = Sequence(tokens: tokens)
            if let cached = cache[key] {
                switch cached {
                case .passing: return nil
                case .failing(let discrepancy): return discrepancy
                }
            }
            guard evaluationState.count < limits.maximumEvaluations else {
                evaluationState.exhausted = true
                return nil
            }
            evaluationState.count += 1
            if let discrepancy = try evaluate(tokens) {
                cache[key] = .failing(discrepancy)
                return discrepancy
            }
            cache[key] = .passing
            return nil
        }

        var considered = 0
        for initial in candidates.prefix(limits.maximumCandidates) {
            considered += 1
            guard let initialDiscrepancy = try evaluateCached(initial) else {
                if evaluationState.exhausted { break }
                continue
            }
            let signature = GrammarParserCounterexampleSignature(initialDiscrepancy)
            var current = initial
            var currentDiscrepancy = initialDiscrepancy
            var changed = true
            while changed && !evaluationState.exhausted {
                changed = false
                let largestChunk = max(1, current.count / 2)
                chunkSearch: for chunkSize in stride(from: largestChunk, through: 1, by: -1) {
                    guard current.count >= chunkSize else { continue }
                    for start in 0...(current.count - chunkSize) {
                        var trial = current
                        trial.removeSubrange(start..<(start + chunkSize))
                        if let discrepancy = try evaluateCached(trial),
                           GrammarParserCounterexampleSignature(discrepancy) == signature {
                            current = trial
                            currentDiscrepancy = discrepancy
                            changed = true
                            break chunkSearch
                        }
                        if evaluationState.exhausted { break chunkSearch }
                    }
                }
            }

            var oneMinimal = true
            if !evaluationState.exhausted && !current.isEmpty {
                for index in current.indices {
                    var trial = current
                    trial.remove(at: index)
                    if let discrepancy = try evaluateCached(trial),
                       GrammarParserCounterexampleSignature(discrepancy) == signature {
                        oneMinimal = false
                        break
                    }
                }
            }
            if evaluationState.exhausted { oneMinimal = false }
            return .init(
                candidatesConsidered: considered,
                evaluations: evaluationState.count,
                exhaustedCandidates: false,
                exhaustedEvaluationBudget: evaluationState.exhausted,
                counterexample: .init(
                    signature: signature,
                    initialTokens: initial,
                    minimizedTokens: current,
                    initialDiscrepancy: initialDiscrepancy,
                    minimizedDiscrepancy: currentDiscrepancy,
                    oneMinimal: oneMinimal
                )
            )
        }
        return .init(
            candidatesConsidered: considered,
            evaluations: evaluationState.count,
            exhaustedCandidates: considered == candidates.count,
            exhaustedEvaluationBudget: evaluationState.exhausted,
            counterexample: nil
        )
    }
}

public struct GrammarParserCounterexampleLawSearch: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let law: GrammarExecutableLaw
    public let result: GrammarParserCounterexampleSearchResult
}

public struct GrammarParserCounterexampleProgrammeReport: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-counterexample-programme-report"

    public let schemaVersion: Int
    public let kind: String
    public let searches: [GrammarParserCounterexampleLawSearch]
    public let calibration: GrammarParserCounterexampleSearchResult

    public var passed: Bool {
        searches.allSatisfy {
            $0.result.exhaustedCandidates && !$0.result.exhaustedEvaluationBudget
                && !$0.result.foundCounterexample
        }
        && calibration.counterexample?.minimizedTokens == ["a", "b", "a"]
        && calibration.counterexample?.oneMinimal == true
        && calibration.exhaustedEvaluationBudget == false
    }
}

/// Searches the Phase-15 LALR fixtures and runs an explicitly synthetic fault
/// calibration so minimization itself cannot silently become a no-op.
public enum GrammarParserCounterexampleProgramme {
    public static func run() throws -> GrammarParserCounterexampleProgrammeReport {
        let fixtures = try GrammarParserLawProgramme.fixtures()
        let candidates = try GrammarParserCounterexampleDiscovery.breadthFirstCandidates(
            alphabet: ["a", "b"], maximumTokens: 2
        )
        let limits = GrammarParserCounterexampleLimits(
            maximumCandidates: candidates.count, maximumEvaluations: 64, maximumTokens: 8
        )
        let searches = try fixtures.map { fixture in
            let result = try GrammarParserCounterexampleDiscovery.discover(
                candidates: candidates, limits: limits
            ) { tokens in
                let input = tokens.joined(separator: " ")
                let baseline = try GrammarParserLawProgramme.observe(
                    source: fixture.baselineSource, model: fixture.witness.baseline,
                    input: input, identity: "workbench-lalr-baseline"
                )
                let candidate = try GrammarParserLawProgramme.observe(
                    source: fixture.candidateSource, model: fixture.witness.candidate,
                    input: input, identity: "workbench-lalr-candidate"
                )
                return try ParseLawDiscrepancy.makeIfFailed(
                    witness: fixture.witness, input: input,
                    tokenCount: baseline.tokenCount,
                    baseline: baseline.contract, candidate: candidate.contract
                )
            }
            return GrammarParserCounterexampleLawSearch(
                id: fixture.witness.id, law: fixture.witness.law, result: result
            )
        }

        let calibrationWitness = fixtures[0].witness
        let calibration = try GrammarParserCounterexampleDiscovery.discover(
            candidates: [["x", "a", "b", "a", "x"]],
            limits: .init(maximumCandidates: 1, maximumEvaluations: 64, maximumTokens: 8)
        ) { tokens in
            let containsTrigger = tokens.count >= 3 && (0...(tokens.count - 3)).contains {
                Array(tokens[$0...($0 + 2)]) == ["a", "b", "a"]
            }
            guard containsTrigger else {
                return nil
            }
            let rejected = ParseContractSnapshot(
                engine: .init(identity: "calibration-baseline", displayName: "Calibration", algorithm: "synthetic"),
                status: .rejected,
                replay: [
                    .init(step: 0, kind: .start, tokenIndex: 0),
                    .init(step: 1, kind: .reject, tokenIndex: tokens.count),
                ]
            )
            let accepted = ParseContractSnapshot(
                engine: .init(identity: "calibration-candidate", displayName: "Calibration", algorithm: "synthetic"),
                status: .accepted,
                replay: [
                    .init(step: 0, kind: .start, tokenIndex: 0),
                    .init(step: 1, kind: .accept, tokenIndex: tokens.count),
                ]
            )
            return try ParseLawDiscrepancy.makeIfFailed(
                witness: calibrationWitness, input: tokens.joined(separator: " "),
                tokenCount: tokens.count, baseline: rejected, candidate: accepted
            )
        }
        return .init(
            schemaVersion: GrammarParserCounterexampleProgrammeReport.currentSchemaVersion,
            kind: GrammarParserCounterexampleProgrammeReport.kindIdentifier,
            searches: searches,
            calibration: calibration
        )
    }
}

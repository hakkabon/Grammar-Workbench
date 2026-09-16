import Foundation
import Grammar
import Parser

public struct GrammarParserLawCaseResult: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let law: GrammarExecutableLaw
    public let input: String
    public let evaluation: ParseMetamorphicEvaluation
    public var passed: Bool { evaluation.passed }
}

public struct GrammarParserLawProgrammeReport: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "grammar-workbench-executable-law-report"

    public let schemaVersion: Int
    public let kind: String
    public let grammarLawSchemaVersion: Int
    public let parserContractSchemaVersion: Int
    public let discrepancySchemaVersion: Int
    public let cases: [GrammarParserLawCaseResult]
    public var passed: Bool { !cases.isEmpty && cases.allSatisfy(\.passed) }
}

public enum GrammarParserLawProgrammeError: Error, LocalizedError, Sendable {
    case compilationFailed(String)
    case parseFailed(String, GrammarParseStatus)
    case missingProduction(String)

    public var errorDescription: String? {
        switch self {
        case .compilationFailed(let detail): "Executable-law fixture did not compile: \(detail)"
        case .parseFailed(let fixture, let status):
            "Executable-law fixture ‘\(fixture)’ produced \(status.rawValue)."
        case .missingProduction(let detail):
            "Executable-law fixture could not map production identity: \(detail)"
        }
    }
}

/// Runs the first ecosystem-owned metamorphic laws through Workbench's real LR runtime.
/// Grammar owns transformations, Parser owns evaluation, and Workbench only coordinates.
public enum GrammarParserLawProgramme {
    public static func run() throws -> GrammarParserLawProgrammeReport {
        let model = try normalizedFixture()
        let permutation = try GrammarLawTransformer.permuteProductions(
            model, order: model.productions.map(\.id).reversed(), id: "production-order"
        )
        let renaming = try GrammarLawTransformer.alphaRenameNonterminals(
            model, renames: [.init(from: "S", to: "Root")], id: "alpha-renaming"
        )
        let fixtures = [
            (permutation, baselineSource, permutedSource),
            (renaming, baselineSource, renamedSource),
        ]
        let cases = try fixtures.map { witness, baselineSource, candidateSource in
            let baseline = try observe(
                source: baselineSource, model: witness.baseline, input: "a",
                identity: "workbench-lalr-baseline"
            )
            let candidate = try observe(
                source: candidateSource, model: witness.candidate, input: "a",
                identity: "workbench-lalr-candidate"
            )
            let evaluation = try ParseLawVerifier.evaluate(
                witness: witness, input: "a", tokenCount: 1,
                baseline: baseline, candidate: candidate
            )
            return GrammarParserLawCaseResult(
                id: witness.id, law: witness.law, input: "a", evaluation: evaluation
            )
        }
        return .init(
            schemaVersion: GrammarParserLawProgrammeReport.currentSchemaVersion,
            kind: GrammarParserLawProgrammeReport.kindIdentifier,
            grammarLawSchemaVersion: GrammarLawWitness.currentSchemaVersion,
            parserContractSchemaVersion: ParseContractSnapshot.currentSchemaVersion,
            discrepancySchemaVersion: ParseLawDiscrepancy.currentSchemaVersion,
            cases: cases
        )
    }

    private static func observe(
        source: String,
        model: GrammarNormalizedModel,
        input: String,
        identity: String
    ) throws -> ParseContractSnapshot {
        let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
        guard compilation.succeeded, let summary = compilation.grammar else {
            throw GrammarParserLawProgrammeError.compilationFailed(
                compilation.diagnostics.map(\.message).joined(separator: "; ")
            )
        }
        let result = compilation.parse(input, options: .init(enablesRecovery: false))
        guard result.status == .accepted, let tree = result.syntaxTree else {
            throw GrammarParserLawProgrammeError.parseFailed(identity, result.status)
        }
        let identities = try Dictionary(uniqueKeysWithValues: summary.productions.map { production in
            let match = model.productions.first {
                $0.lhs == production.lhs && $0.rhs.map(symbolName) == production.rhs
            }
            guard let match else {
                throw GrammarParserLawProgrammeError.missingProduction(production.text)
            }
            // The canonical LR artifact reserves production zero for its augmented rule.
            return (production.id + 1, match.id)
        })
        guard identities.count == model.productions.count,
              Set(identities.values) == Set(model.productions.map(\.id)) else {
            throw GrammarParserLawProgrammeError.missingProduction(
                "compiled fixture does not exactly cover its normalized witness"
            )
        }
        let portableTree = try makeTree(tree, model: model, productionIDs: identities)
        return .init(
            engine: .init(
                identity: identity, displayName: "Grammar Workbench LALR(1)", algorithm: "lalr"
            ),
            status: .accepted,
            tree: portableTree,
            replay: [
                .init(step: 0, kind: .start, tokenIndex: 0),
                .init(step: 1, kind: .accept, tokenIndex: result.tokens.count),
            ]
        )
    }

    private static func makeTree(
        _ node: GrammarSyntaxNode,
        model: GrammarNormalizedModel,
        productionIDs: [Int: GrammarProductionID]
    ) throws -> ProductionParseTree {
        if let token = node.token {
            let lower = token.range?.start.offset ?? token.index
            let upper = token.range?.end.offset ?? lower + token.lexeme.utf16.count
            return .token(
                label: token.lexeme,
                span: .init(
                    leftToken: token.index, rightToken: token.index + 1,
                    lowerUTF16Offset: lower, upperUTF16Offset: upper
                )
            )
        }
        let children = try node.children.map {
            try makeTree($0, model: model, productionIDs: productionIDs)
        }
        let span: ParseInputSpan
        if let first = children.first?.span, let last = children.last?.span {
            span = .init(
                leftToken: first.leftToken, rightToken: last.rightToken,
                lowerUTF16Offset: first.lowerUTF16Offset,
                upperUTF16Offset: last.upperUTF16Offset
            )
        } else {
            let offset = node.range?.start.offset ?? 0
            span = .init(
                leftToken: 0, rightToken: 0,
                lowerUTF16Offset: offset, upperUTF16Offset: offset
            )
        }
        let productionID = node.production.flatMap { productionIDs[$0] }
            ?? model.productions.first {
                $0.lhs == node.symbol && $0.rhs.map(symbolName) == node.children.map(\.symbol)
            }?.id
        guard let productionID else {
            throw GrammarParserLawProgrammeError.missingProduction(node.symbol)
        }
        return .production(
            nonterminal: node.symbol, productionID: productionID, span: span, children: children
        )
    }

    private static func symbolName(_ symbol: GrammarNormalizedSymbol) -> String {
        switch symbol {
        case .nonterminal(let name): name
        case .terminal(let terminal):
            switch terminal {
            case .literal(let value): value
            case .literals(let values): values.joined(separator: "|")
            case .characterRange(let lower, let upper): "\(lower)...\(upper)"
            case .regularExpression(let pattern): pattern
            case .boundary(let value): value
            }
        }
    }

    private static func normalizedFixture() throws -> GrammarNormalizedModel {
        try GrammarNormalizedModel(
            startSymbol: "S",
            productions: [
                .init(id: .init(rawValue: "s-a"), lhs: "S", rhs: [.terminal(.literal("A"))]),
                .init(id: .init(rawValue: "s-b"), lhs: "S", rhs: [.terminal(.literal("B"))]),
            ],
            lexicalDefinitions: [
                .init(name: "A", terminal: .regularExpression("a")),
                .init(name: "B", terminal: .regularExpression("b")),
            ]
        )
    }

    private static let baselineSource = #"""
    %token A /a/
    %token B /b/
    %start S
    S : A ;
    S : B ;
    """#

    private static let permutedSource = #"""
    %token A /a/
    %token B /b/
    %start S
    S : B ;
    S : A ;
    """#

    private static let renamedSource = #"""
    %token A /a/
    %token B /b/
    %start Root
    Root : A ;
    Root : B ;
    """#
}

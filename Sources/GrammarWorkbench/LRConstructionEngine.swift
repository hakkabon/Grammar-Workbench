import Foundation

enum LRConstructionEngine {
    static func construct(
        grammar: ParsedGrammar,
        analysis _: GrammarAnalysis,
        source: String,
        algorithm: LRAlgorithm
    ) -> GrammarArtifact {
        CanonicalLRConstructionAdapter.construct(
            grammar: grammar, source: source, algorithm: algorithm
        )
    }
}

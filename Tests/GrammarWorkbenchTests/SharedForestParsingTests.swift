import Foundation
import Testing
@testable import GrammarWorkbench

private let catalanGrammar = """
%start S
S : S S | 'a' ;
"""

@Test func sharedForestPacksCatalanAmbiguityBeforeEnumeration() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: catalanGrammar))
    let result = compilation.parseGeneralized(
        "a a a a a a a",
        options: .init(maximumConfigurations: 10_000, maximumSteps: 100_000, maximumTrees: 8)
    )
    #expect(result.status == .truncated)
    #expect(result.reachedLimits == [.trees])
    #expect(result.alternatives.count == 8)
    #expect(result.sharedForest.roots.count == 1)
    #expect(result.sharedForest.ambiguousNodeCount > 0)
    #expect(result.sharedForest.derivationCount(upTo: 1_000) == 132)
    #expect(result.sharedForest.nodes.count < 100)
    #expect(result.sharedForest.packedFamilyCount < 150)
}

@Test func sharedForestIdentityAndPackingAreSearchOrderIndependent() {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: catalanGrammar))
    let depth = compilation.parseGeneralized(
        "a a a a a", options: .init(maximumTrees: 64, searchStrategy: .depthFirst)
    )
    let breadth = compilation.parseGeneralized(
        "a a a a a", options: .init(maximumTrees: 64, searchStrategy: .breadthFirst)
    )
    #expect(depth.sharedForest == breadth.sharedForest)
    #expect(depth.sharedForest.derivationCount() == 14)
}

@Test func sharedForestResourceLimitsAreReportedExactly() {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: catalanGrammar))
    let nodes = compilation.parseGeneralized(
        "a a a", options: .init(maximumForestNodes: 1, maximumPackedFamilies: 100)
    )
    #expect(nodes.reachedLimits.contains(.forestNodes))

    let families = compilation.parseGeneralized(
        "a a a", options: .init(maximumForestNodes: 100, maximumPackedFamilies: 1)
    )
    #expect(families.reachedLimits.contains(.packedFamilies))
}

@Test func generalizedResultDecodesBeforeSharedForestField() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: catalanGrammar))
    let result = compilation.parseGeneralized("a a a", options: .init(maximumTrees: 8))
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
    object.removeValue(forKey: "sharedForest")
    let legacy = try JSONDecoder().decode(
        GrammarGeneralizedParseResult.self,
        from: JSONSerialization.data(withJSONObject: object)
    )
    #expect(legacy.sharedForest == .empty)
    #expect(legacy.alternatives == result.alternatives)
}

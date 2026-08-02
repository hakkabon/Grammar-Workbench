import Testing
import GrammarWorkbench

private let incrementalGrammar = """
%start S
S : 'value' ;
"""

@Test func compilationReportsConstructionPerformance() {
    let result = GrammarWorkbenchAPI.compile(.init(source: incrementalGrammar))

    #expect(result.succeeded)
    #expect(result.performance.reuse == .none)
    #expect(result.performance.totalMilliseconds >= result.performance.frontEndMilliseconds)
    #expect(result.performance.stateCount == result.artifact?.states.count)
    #expect(result.performance.itemCount > 0)
    #expect(result.performance.tableEntryCount == result.artifact?.table.count)
}

@Test func incrementalCompilerCachesExactRequests() async {
    let compiler = GrammarWorkbenchIncrementalCompiler(capacity: 2)
    let request = GrammarCompilationRequest(source: incrementalGrammar, algorithm: .lalr)

    let first = await compiler.compile(request)
    let second = await compiler.compile(request)
    let statistics = await compiler.statistics()

    #expect(first.performance.reuse == .none)
    #expect(second.performance.reuse == .cacheHit)
    #expect(first.artifact == second.artifact)
    #expect(statistics.entries == 1)
    #expect(statistics.misses == 1)
    #expect(statistics.hits == 1)
}

@Test func incrementalCompilerUsesBoundedLRUEviction() async {
    let compiler = GrammarWorkbenchIncrementalCompiler(capacity: 2)
    func request(_ terminal: String) -> GrammarCompilationRequest {
        .init(source: "%start S\nS : '\(terminal)' ;")
    }

    _ = await compiler.compile(request("one"))
    _ = await compiler.compile(request("two"))
    _ = await compiler.compile(request("one")) // one is now most recently used
    _ = await compiler.compile(request("three"))
    let rebuilt = await compiler.compile(request("two"))
    let statistics = await compiler.statistics()

    #expect(rebuilt.performance.reuse == .none)
    #expect(statistics.entries == 2)
    #expect(statistics.evictions == 2)
    #expect(statistics.misses == 4)
    #expect(statistics.hits == 1)
}

@Test func concurrentEqualRequestsShareConstruction() async {
    let compiler = GrammarWorkbenchIncrementalCompiler(capacity: 4)
    let alternatives = (0..<120).map { "N\($0)" }.joined(separator: " | ")
    let productions = (0..<120).map { "N\($0) : 't\($0)' ;" }.joined(separator: "\n")
    let request = GrammarCompilationRequest(
        source: "%start S\nS : \(alternatives) ;\n\(productions)",
        algorithm: .canonical
    )

    let results = await withTaskGroup(of: GrammarCompilation.self) { group in
        for _ in 0..<12 { group.addTask { await compiler.compile(request) } }
        var values: [GrammarCompilation] = []
        for await value in group { values.append(value) }
        return values
    }
    let statistics = await compiler.statistics()

    #expect(results.allSatisfy { $0.succeeded })
    #expect(statistics.misses == 1)
    #expect(statistics.coalescedRequests > 0)
    #expect(statistics.entries == 1)
}

@Test func invalidCompilationsAreAlsoReusable() async {
    let compiler = GrammarWorkbenchIncrementalCompiler()
    let request = GrammarCompilationRequest(source: "%start Missing")

    let first = await compiler.compile(request)
    let second = await compiler.compile(request)

    #expect(!first.succeeded)
    #expect(!second.succeeded)
    #expect(second.performance.reuse == .cacheHit)
    #expect(first.diagnostics == second.diagnostics)
}

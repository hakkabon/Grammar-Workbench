import Foundation

enum HTMLExporter {
    static func render(_ artifact: GrammarArtifact, runtime: ParserRuntimeResult? = nil) -> String {
        let automaton = AutomatonSVG.render(artifact, selected: nil)
        let rows = artifact.states.map { state in
            let values = (artifact.terminals + artifact.nonterminals).map { symbol in
                let actions = artifact.cell(.init(state: state.id, symbol: symbol))?.actions.map(\.label).joined(separator: " / ") ?? ""
                return "<td class='\(actions.contains("/") ? "conflict" : "")'>\(escape(actions))</td>"
            }.joined()
            return "<tr><th>\(state.id)</th>\(values)</tr>"
        }.joined()
        let decisions = artifact.decisions.map { decision in
            let provenance = decision.provenance.map {
                "<p><strong>Resolution:</strong> \(escape($0.kind.rawValue)); lookahead level \($0.lookaheadLevel.map(String.init) ?? "none"); production level \($0.productionLevel.map(String.init) ?? "none"); associativity \(escape($0.associativity?.rawValue ?? "none")).</p>"
            } ?? ""
            let branches = decision.branchAnalyses.map {
                "<section><h4>Action \(escape($0.action.label))</h4><p>\(escape($0.outcome))</p><pre>\(escape($0.tree ?? "No accepting tree."))</pre></section>"
            }.joined()
            return "<li><strong>\(escape(decision.title))</strong>\(decision.isExpected ? " <em>(expected)</em>" : "")<br>Minimal counterexample: <code>\(escape(decision.witness.joined(separator: " ")))</code><p>\(escape(decision.explanation))</p>\(provenance)<main>\(branches)</main></li>"
        }.joined()
        let expectation = artifact.conflictExpectation.map {
            "<p class='\($0.matches ? "expected" : "conflict")'><strong>%expect \($0.expected)</strong>: generated \($0.actual) unresolved conflicts — \($0.matches ? "matched" : "mismatch").</p>"
        } ?? ""
        let sampleInput = runtime?.tokens.joined(separator: " ") ?? artifact.sample.input
        let sampleTree = runtime?.tree?.rendered() ?? artifact.sample.tree
        let sampleOutcome = runtime?.outcome.label ?? ""
        let trace = (runtime?.frames ?? artifact.sample.trace).map {
            "<tr><td>\($0.index)</td><td><code>\(escape($0.stack.joined(separator: " ")))</code></td><td><code>\(escape($0.remainingInput.joined(separator: " ")))</code></td><td>\(escape($0.action))</td></tr>"
        }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Grammar Artifact</title>
        <style>body{font:15px system-ui;margin:auto;max-width:1100px;padding:32px;color:#172033}pre,code{font-family:ui-monospace,monospace}svg{display:block;max-width:100%;height:auto}main{display:grid;grid-template-columns:1fr 1fr;gap:20px}section{border:1px solid #ccd3df;border-radius:10px;padding:12px}table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccd3df;padding:7px}.conflict{background:#ffd9d5;color:#8d1710}.expected{background:#dcf5e5;color:#176b38;padding:8px;border-radius:8px}@media(max-width:700px){main{grid-template-columns:1fr}}</style></head>
        <body><h1>Grammar Artifact Explorer</h1><p>Algorithm: <strong>\(escape(artifact.algorithm.rawValue))</strong></p><h2>Grammar</h2><pre>\(escape(artifact.grammarSource))</pre><h2>Automaton</h2>\(automaton)<h2>Parsing table</h2><table><tr><th>State</th>\((artifact.terminals + artifact.nonterminals).map { "<th>\(escape($0))</th>" }.joined())</tr>\(rows)</table><h2>Conflicts and decisions</h2>\(expectation)<ol>\(decisions)</ol><h2>Sample parse</h2><p><code>\(escape(sampleInput))</code> — \(escape(sampleOutcome))</p><pre>\(escape(sampleTree))</pre><h3>Trace</h3><table><tr><th>Step</th><th>Stack</th><th>Input</th><th>Action</th></tr>\(trace)</table></body></html>
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

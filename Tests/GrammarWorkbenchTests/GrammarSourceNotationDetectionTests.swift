import GrammarWorkbench
import Testing

@Suite("Grammar source notation detection")
struct GrammarSourceNotationDetectionTests {
    @Test("Known file extensions take precedence")
    func extensions() {
        #expect(GrammarSourceNotationDetector.detect(
            source: "%start S\nS : 'ok' ;", pathExtension: "ebnf"
        ) == .ebnf)
        #expect(GrammarSourceNotationDetector.detect(
            source: "s = \"ok\" ;", pathExtension: "grammar"
        ) == .workbench)
        #expect(GrammarSourceNotationDetector.detect(
            source: "%start S\nS : 'ok' ;", pathExtension: "bnf"
        ) == .ebnf)
    }

    @Test("Unknown plain text uses one-parser-only detection")
    func syntaxDetection() {
        #expect(GrammarSourceNotationDetector.detect(
            source: "%start S\nS : 'ok' ;", pathExtension: "txt"
        ) == .workbench)
        #expect(GrammarSourceNotationDetector.detect(
            source: "lexical { NUMBER = /[0-9]+/ ; }\nexpression = NUMBER ;",
            pathExtension: "txt"
        ) == .ebnf)
    }

    @Test("Incomplete or ambiguous text keeps the caller fallback")
    func fallback() {
        #expect(GrammarSourceNotationDetector.detect(source: "", fallback: .workbench) == .workbench)
        #expect(GrammarSourceNotationDetector.detect(source: "not complete", fallback: .ebnf) == .ebnf)
    }
}

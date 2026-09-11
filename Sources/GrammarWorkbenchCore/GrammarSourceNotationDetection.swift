import Foundation

public enum GrammarSourceNotationDetector {
    /// Detects notation once at an import boundary. Callers should prefer
    /// persisted project/document metadata when it exists and must not run this
    /// continuously while a user is editing incomplete source.
    public static func detect(
        source: String, pathExtension: String? = nil,
        fallback: GrammarSourceNotation = .workbench
    ) -> GrammarSourceNotation {
        switch pathExtension?.lowercased() {
        case "bnf", "ebnf": return .ebnf
        case "grammar", "y", "yacc", "yy": return .workbench
        default: break
        }

        let workbench = GrammarFrontEnd.process(source, notation: .workbench)
        let ebnf = GrammarFrontEnd.process(source, notation: .ebnf)
        switch (workbench.hasErrors, ebnf.hasErrors) {
        case (false, true): return .workbench
        case (true, false): return .ebnf
        default: return fallback
        }
    }
}

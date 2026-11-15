/// Compares a draft against an accepted grammar using the project's examples
/// and the same default parser as Workbench's Parse command.
public struct GrammarDraftImpact: Sendable {
    public struct Example: Identifiable, Sendable {
        public let id: String
        public let path: String
        public let before: GrammarParseStatus
        public let after: GrammarParseStatus
        public let message: String
        public let range: SourceRange?

        public var regressed: Bool { before == .accepted && after != .accepted }
        public var beforeLabel: String { Self.label(before) }
        public var afterLabel: String { Self.label(after) }

        private static func label(_ status: GrammarParseStatus) -> String {
            // Both grammars have compiled by the time examples are evaluated.
            status == .invalidGrammar ? "lexical error" : status.rawValue
        }
    }

    public let diagnostics: [GrammarDiagnostic]
    public let compiled: Bool
    public let examples: [Example]
    public let addedRules: [String]
    public let removedRules: [String]

    public static func compare(
        draft: String, baseline: GrammarCompilation, sources: [GrammarProjectSource]
    ) -> Self {
        var request = baseline.request
        request.source = draft
        let candidate = GrammarWorkbenchAPI.compile(request)
        guard candidate.succeeded else {
            return .init(diagnostics: candidate.diagnostics, compiled: false,
                         examples: [], addedRules: [], removedRules: [])
        }
        let beforeRules = Set(baseline.grammar?.productions.map(\.text) ?? [])
        let afterRules = Set(candidate.grammar?.productions.map(\.text) ?? [])
        let examples = sources.map { source in
            let before = baseline.parse(source.text)
            let after = candidate.parse(source.text)
            let syntax = after.diagnostics.first
            // The parse result uses invalidGrammar for input lexing failures.
            let lexical = after.status == .invalidGrammar
                ? candidate.lex(source.text).diagnostics.first : nil
            return Example(id: source.id, path: source.path,
                           before: before.status, after: after.status,
                           message: syntax?.message ?? lexical?.message ?? after.message,
                           range: syntax?.range ?? lexical?.range)
        }
        return .init(diagnostics: candidate.diagnostics, compiled: true,
                     examples: examples, addedRules: afterRules.subtracting(beforeRules).sorted(),
                     removedRules: beforeRules.subtracting(afterRules).sorted())
    }
}

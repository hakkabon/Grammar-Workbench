import IncrementalParsing
import LanguageTooling

/// Shared-provider host used by Workbench integrations that load an external
/// language kit. Grammar-Workbench owns presentation and transport only; the
/// provider owns parser, semantic, compiler, and incremental state.
public struct GrammarWorkbenchToolingConsumer: Sendable {
    public let document: LanguageToolingDocument

    public static func makeProject(
        providers: [any LanguageToolingProvider],
        resolver: (any LanguageToolingProjectResolver)? = nil
    ) -> LanguageToolingProject {
        LanguageToolingProject(providers: providers, resolver: resolver)
    }

    public init(provider: any LanguageToolingProvider) {
        document = LanguageToolingDocument(provider: provider)
    }

    public var descriptor: LanguageProviderDescriptor { document.descriptor }

    @discardableResult
    public func open(_ snapshot: SourceSnapshot) async throws
        -> LanguageProviderAnalysis {
        try await document.open(snapshot)
    }

    @discardableResult
    public func apply(_ edit: SourceEdit) async throws
        -> LanguageProviderAnalysis {
        try await document.apply(edit)
    }

    public func completions(at position: ToolingPosition) async throws
        -> [ToolingCompletionItem] {
        try await document.completions(at: position)
    }

    public func definition(at position: ToolingPosition) async throws
        -> ToolingLocation? {
        try await document.definition(at: position)
    }

    public func semanticTokens() async throws -> ToolingSemanticTokensResult {
        try await document.semanticTokens()
    }
}

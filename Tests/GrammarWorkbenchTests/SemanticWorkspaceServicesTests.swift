import Foundation
import Testing
@testable import GrammarWorkbench

private let semanticWorkspaceGrammar = #"""
%token LET /let\b/
%token USE /use\b/
%token ID /[A-Za-z_][A-Za-z0-9_]*/
%token SEMI /;/
%skip /\s+/
%start Program
Program : Program Statement | Statement ;
Statement : LET ID SEMI | USE ID SEMI ;
"""#

private func semanticProject(_ sources: [GrammarProjectSource]? = nil) -> GrammarProjectManifest {
    .init(
        name: "Semantic workspace",
        grammar: .init(source: semanticWorkspaceGrammar),
        sources: sources ?? [
            .init(id: "definitions", path: "Definitions.lang", text: "let alpha;", revision: 1),
            .init(id: "uses", path: "Uses.lang", text: "use alpha;", revision: 1)
        ]
    )
}

private func semanticSchema() throws -> GrammarSemanticWorkspaceSchema {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: semanticWorkspaceGrammar))
    let model = try GrammarSemanticModel(compilation: compilation)
    let definition = try #require(model.productions(lhs: "Statement", rhs: ["LET", "ID", "SEMI"]).first)
    let reference = try #require(model.productions(lhs: "Statement", rhs: ["USE", "ID", "SEMI"]).first)
    return .init(rules: [
        .init(tokenKind: "ID", enclosingProduction: definition.id, kind: "variable", role: .definition),
        .init(tokenKind: "ID", enclosingProduction: reference.id, kind: "variable", role: .reference)
    ])
}

@Test func semanticWorkspaceResolvesSymbolsReferencesAndDependencies() async throws {
    let workspace = try GrammarProjectWorkspace(manifest: semanticProject())
    let services = try await workspace.semanticWorkspace(schema: semanticSchema())
    #expect(services.occurrences.count == 2)
    #expect(services.diagnostics.isEmpty)
    let symbols = services.workspaceSymbols(matching: "alp")
    let definition = try #require(symbols.first)
    #expect(definition.role == .definition)
    #expect(services.references(to: definition).count == 2)
    let reference = try #require(services.occurrence(documentID: "uses", atUTF16Offset: 5))
    #expect(services.definitions(of: reference) == [definition])
    #expect(services.dependencies == [
        .init(sourceDocumentID: "uses", targetDocumentID: "definitions", symbolCount: 1)
    ])
}

@Test func semanticWorkspaceReportsUnresolvedAmbiguousAndDuplicateSymbols() async throws {
    let workspace = try GrammarProjectWorkspace(manifest: semanticProject([
        .init(id: "one", path: "One.lang", text: "let alpha;", revision: 1),
        .init(id: "two", path: "Two.lang", text: "let alpha;", revision: 1),
        .init(id: "uses", path: "Uses.lang", text: "use alpha; use missing;", revision: 1)
    ]))
    let services = try await workspace.semanticWorkspace(schema: semanticSchema())
    #expect(services.diagnostics.count { $0.code == .duplicateDefinition } == 2)
    #expect(services.diagnostics.count { $0.code == .ambiguousReference } == 1)
    #expect(services.diagnostics.count { $0.code == .unresolvedReference } == 1)
}

@Test func semanticRenamePlanAppliesAtomicallyAcrossDocuments() async throws {
    let workspace = try GrammarProjectWorkspace(manifest: semanticProject())
    let services = try await workspace.semanticWorkspace(schema: semanticSchema())
    let plan = try services.renamePlan(
        documentID: "uses", atUTF16Offset: 5, replacement: "renamed"
    )
    #expect(plan.affectedOccurrences == 2)
    #expect(plan.documents.count == 2)
    let changed = try await workspace.applySemanticRename(plan)
    #expect(changed.manifest.sources.map(\.text) == ["let renamed;", "use renamed;"])
    #expect(changed.manifest.sources.map(\.revision) == [2, 2])
    let refreshed = changed.semanticWorkspace(schema: try semanticSchema())
    #expect(refreshed.workspaceSymbols().map(\.name) == ["renamed"])
    #expect(refreshed.diagnostics.isEmpty)
}

@Test func semanticRenameRejectsCollisionsAndStalePlansWithoutPartialMutation() async throws {
    let workspace = try GrammarProjectWorkspace(manifest: semanticProject([
        .init(id: "definitions", path: "Definitions.lang", text: "let alpha; let beta;", revision: 1),
        .init(id: "uses", path: "Uses.lang", text: "use alpha;", revision: 1)
    ]))
    let services = try await workspace.semanticWorkspace(schema: semanticSchema())
    #expect(throws: GrammarSemanticWorkspaceError.self) {
        try services.renamePlan(documentID: "uses", atUTF16Offset: 5, replacement: "beta")
    }
    let plan = try services.renamePlan(documentID: "uses", atUTF16Offset: 5, replacement: "gamma")
    _ = try await workspace.apply(
        documentID: "uses", edits: [.init(range: nil, replacement: "use alpha;")], revision: 2
    )
    await #expect(throws: GrammarSemanticWorkspaceError.self) {
        try await workspace.applySemanticRename(plan)
    }
    let manifest = await workspace.projectManifest()
    #expect(manifest.sources[0].text == "let alpha; let beta;")
    #expect(manifest.sources[1].text == "use alpha;")
}

@Test func semanticWorkspaceContractsRoundTripAsJSON() async throws {
    let workspace = try GrammarProjectWorkspace(manifest: semanticProject())
    let services = try await workspace.semanticWorkspace(schema: semanticSchema())
    let data = try JSONEncoder().encode(services)
    #expect(try JSONDecoder().decode(GrammarSemanticWorkspaceSnapshot.self, from: data) == services)
    let plan = try services.renamePlan(documentID: "uses", atUTF16Offset: 5, replacement: "next")
    #expect(try JSONDecoder().decode(GrammarSemanticRenamePlan.self, from: JSONEncoder().encode(plan)) == plan)
}

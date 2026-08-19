import Foundation
import Testing
@testable import GrammarWorkbench

@Test func renamePlanIsSourcePreservingAndProtectsNonCodeText() throws {
    let source = """
    # Expr stays in this comment
    %token ID /Expr[A-Za-z]*/
    %start Expr
    Expr : Expr ID | ID | 'Expr' ;
    """
    let request = GrammarCompilationRequest(source: source)
    let compilation = GrammarWorkbenchAPI.compile(request)
    let plan = try compilation.renameRefactoring(from: "Expr", to: "Expression")
    let result = try GrammarRefactoring.execute(
        plan, request: request,
        corpus: [.init(input: "value", origin: "sample")]
    )

    #expect(plan.affectedOccurrences == 3)
    #expect(plan.affectedLines == [3, 4])
    #expect(result.isSafeToApply)
    #expect(result.proposedSource.contains("%start Expression"))
    #expect(result.proposedSource.contains("Expression : Expression ID"))
    #expect(result.proposedSource.contains("# Expr stays"))
    #expect(result.proposedSource.contains("/Expr[A-Za-z]*/"))
    #expect(result.proposedSource.contains("'Expr'"))
}

@Test func renamePlanRejectsCollisionsUnknownSymbolsAndStaleSource() throws {
    let source = "%start Root\nRoot : Value ;\nValue : 'ok' ;"
    let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
    #expect(throws: GrammarRefactoringError.symbolCollision("Value")) {
        try compilation.renameRefactoring(from: "Root", to: "Value")
    }
    #expect(throws: GrammarRefactoringError.unknownSymbol("Missing")) {
        try compilation.renameRefactoring(from: "Missing", to: "Other")
    }
    #expect(throws: GrammarRefactoringError.invalidIdentifier("not-valid")) {
        try compilation.renameRefactoring(from: "Root", to: "not-valid")
    }
    let plan = try compilation.renameRefactoring(from: "Value", to: "Item")
    #expect(throws: GrammarRefactoringError.sourceChanged) {
        try GrammarRefactoring.apply(plan, to: source + "\n")
    }
}

@Test func renamePlanPreservesNativeEBNFNotation() throws {
    let source = "(* term remains in this comment *)\nexpression = term, { \"+\", term };\nterm = identifier;\nidentifier = \"name\";"
    let request = GrammarCompilationRequest(source: source, notation: .ebnf)
    let compilation = GrammarWorkbenchAPI.compile(request)
    let plan = try compilation.renameRefactoring(from: "term", to: "factor")
    let result = try GrammarRefactoring.execute(plan, request: request)

    #expect(plan.notation == .ebnf)
    #expect(plan.affectedOccurrences == 3)
    #expect(result.compilation.succeeded)
    #expect(result.isSafeToApply)
    #expect(result.proposedSource == "(* term remains in this comment *)\nexpression = factor, { \"+\", factor };\nfactor = identifier;\nidentifier = \"name\";")
}

@Test func refactoringPlansHaveStableCodableFormsAndNoOpRename() throws {
    let compilation = GrammarWorkbenchAPI.compile(.init(source: "%start S\nS : 'ok' ;"))
    let plan = try compilation.renameRefactoring(from: "S", to: "Start")
    let data = try JSONEncoder().encode(plan)
    #expect(try JSONDecoder().decode(GrammarRefactoringPlan.self, from: data) == plan)
    #expect(try compilation.renameRefactoring(from: "S", to: "S").hasChanges == false)
}

@Test func projectRenamePreviewIncludesSourcesTestsAndArtifactImpact() async throws {
    let workspace = try GrammarProjectWorkspace(manifest: .init(
        name: "Rename",
        grammar: .init(source: "%start Root\nRoot : 'ok' ;"),
        sources: [.init(id: "main", path: "Sources/main.txt", text: "ok")],
        tests: [.init(name: "accept", input: "ok", expectation: .accept)]
    ))
    let result = try await workspace.previewGrammarRename(from: "Root", to: "Document")
    #expect(result.isSafeToApply)
    #expect(result.behavior.cases.contains { $0.origin == "Sources/main.txt" })
    #expect(result.testsAfter?.allPassed == true)
    #expect(result.artifactDiff != nil)
}

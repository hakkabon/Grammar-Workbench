#if os(macOS)
import AppKit
import SwiftUI
#endif
import Testing
@testable import GrammarWorkbench

@Test func semanticValidationFindsStructuralGrammarProblems() {
    let result = GrammarFrontEnd.process("""
    %start S
    %left 'unused'
    S : 'ok' ;
    S : 'ok' ;
    Dead : Dead ;
    """)
    #expect(!result.hasErrors)
    #expect(result.diagnostics.contains { $0.message.contains("Duplicate production") })
    #expect(result.diagnostics.contains { $0.message.contains("‘Dead’ is unreachable") })
    #expect(result.diagnostics.contains { $0.message.contains("‘Dead’ cannot derive") })
    #expect(result.diagnostics.contains { $0.message.contains("‘unused’ is never used") })
    #expect(result.diagnostics.allSatisfy { $0.severity == .warning })
}

@Test func editorCompletionsIncludeDirectivesAndGrammarSymbols() {
    let result = GrammarFrontEnd.process("%start List\nList : 'item' ;")
    let completions = GrammarEditorIntelligence.completions(for: result)
    #expect(completions.contains("%start"))
    #expect(completions.contains("%nonassoc"))
    #expect(completions.contains("List"))
    #expect(completions.contains("item"))
}

@Test func missingSemicolonQuickFixProducesValidGrammar() throws {
    let source = "%start S\nS : 'id'"
    let result = GrammarFrontEnd.process(source)
    let diagnostic = try #require(result.diagnostics.first { $0.message.hasPrefix("Expected ‘;’") })
    let fix = try #require(GrammarEditorIntelligence.quickFixes(for: diagnostic, source: source).first)
    let fixedSource = fix.applying(to: source)
    #expect(fixedSource.hasSuffix(";"))
    #expect(!GrammarFrontEnd.process(fixedSource).hasErrors)
}

@Test func missingColonQuickFixProducesValidGrammar() throws {
    let source = "%start S\nS 'id' ;"
    let result = GrammarFrontEnd.process(source)
    let diagnostic = try #require(result.diagnostics.first { $0.message.hasPrefix("Expected ‘:’") })
    let fix = try #require(GrammarEditorIntelligence.quickFixes(for: diagnostic, source: source).first)
    #expect(!GrammarFrontEnd.process(fix.applying(to: source)).hasErrors)
}

#if os(macOS)
@MainActor
@Test func artifactSelectionResolvesToProductionSourceRange() {
    let source = "%start S\nS : A ;\nA : 'id' ;"
    let store = ExplorerStore(source: source)
    store.select(.production(.init(rawValue: 2)))
    #expect(store.sourceSelection?.start.line == 3)
    store.select(.state(.init(rawValue: 0)))
    #expect(store.sourceSelection != nil)
}
#endif

@Test func undefinedSymbolQuickFixAddsTokenDeclaration() throws {
    let source = "%start S\n%token ID\nS : ID Missing ;"
    let result = GrammarFrontEnd.process(source)
    let diagnostic = try #require(result.diagnostics.first { $0.code == "undefined-symbol" })
    let fix = try #require(GrammarEditorIntelligence.quickFixes(for: diagnostic, source: source).first)
    let fixed = fix.applying(to: source)
    #expect(fixed.hasPrefix("%token Missing\n"))
    #expect(!GrammarFrontEnd.process(fixed).hasErrors)
}

@Test func EBNFCompletionsHideLoweringDetailsAndIncludeNativeVocabulary() {
    let source = "root = item { item } ;\nitem = \"x\" ;"
    let result = GrammarFrontEnd.process(source, notation: .ebnf)
    let completions = GrammarEditorIntelligence.completions(for: result, notation: .ebnf)

    #expect(completions.contains("root"))
    #expect(completions.contains("item"))
    #expect(completions.contains("lexical"))
    #expect(completions.contains("ε"))
    #expect(!completions.contains { $0.hasPrefix("__ebnf_") })
    #expect(!completions.contains("%token"))
}

@Test func EBNFQuickFixesCloseConstructsAndCreateMissingProductions() throws {
    let malformed = "expression = [ \"term\" ;"
    let malformedResult = GrammarFrontEnd.process(malformed, notation: .ebnf)
    let closingDiagnostic = try #require(malformedResult.diagnostics.first)
    let closingFix = try #require(GrammarEditorIntelligence.quickFixes(
        for: closingDiagnostic, source: malformed, notation: .ebnf
    ).first)
    let closed = closingFix.applying(to: malformed)
    #expect(closed == "expression = [ \"term\" ];")
    #expect(!GrammarFrontEnd.process(closed, notation: .ebnf).hasErrors)

    let undefined = "expression = missing ;"
    let undefinedResult = GrammarFrontEnd.process(undefined, notation: .ebnf)
    let undefinedDiagnostic = try #require(undefinedResult.diagnostics.first { $0.code == "undefined-ebnf-symbol" })
    let definitionFix = try #require(GrammarEditorIntelligence.quickFixes(
        for: undefinedDiagnostic, source: undefined, notation: .ebnf
    ).first)
    #expect(!GrammarFrontEnd.process(definitionFix.applying(to: undefined), notation: .ebnf).hasErrors)
}

#if os(macOS)
@MainActor @Test func EBNFArtifactNavigationSelectsTheOriginalDeclaration() throws {
    let source = "root = item { item } ;\nitem = \"x\" ;"
    let store = ExplorerStore(source: source, notation: .ebnf)
    let repeated = try #require(store.artifact.productions.first { $0.lhs.hasPrefix("__ebnf_") })

    store.select(.production(repeated.id))

    #expect(store.sourceSelection?.start.line == 1)
    #expect(store.sourceSelection?.start.column == 1)
}

@MainActor
@Test func editorDocumentViewStartsWithVisibleDimensions() {
    let textView = GrammarSourceEditor.makeTextView(contentSize: NSSize(width: 320, height: 240))

    #expect(textView.frame.size == NSSize(width: 320, height: 240))
    #expect(textView.minSize.height == 240)
    #expect(textView.isVerticallyResizable)
    #expect(textView.textContainer?.heightTracksTextView == false)
}

@MainActor
@Test func editorUsesAVisibleFallbackBeforeSwiftUILayout() {
    let textView = GrammarSourceEditor.makeTextView(contentSize: .zero)

    #expect(textView.frame.width == GrammarEditorScrollView.fallbackViewportSize.width)
    #expect(textView.frame.height == GrammarEditorScrollView.fallbackViewportSize.height)
    #expect(textView.minSize.height > 0)
}

@MainActor
@Test func editorDocumentViewAlwaysFillsItsViewport() {
    let scrollView = GrammarEditorScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
    let textView = GrammarSourceEditor.makeTextView(contentSize: .zero)
    textView.frame.size = NSSize(width: 1, height: 1)
    scrollView.documentView = textView

    scrollView.layoutSubtreeIfNeeded()
    scrollView.ensureDocumentViewFillsViewport()

    #expect(textView.frame.width >= scrollView.contentSize.width)
    #expect(textView.frame.height >= scrollView.contentSize.height)
    #expect(textView.minSize.height == scrollView.contentSize.height)
}
#endif

#if os(macOS)
@Test func primaryVisualFoundationKeepsAllPanesSideBySide() {
    #expect(WorkbenchVisualFoundation.requiredPaneWidth <= WorkbenchVisualFoundation.windowMinimumWidth)
    #expect(WorkbenchVisualFoundation.sourceMinimumWidth >= 300)
    #expect(WorkbenchVisualFoundation.workspaceMinimumWidth > WorkbenchVisualFoundation.sourceMinimumWidth)
    #expect(WorkbenchVisualFoundation.inspectorMinimumWidth >= 240)
}
#endif

#if os(macOS)
@MainActor
@Test func lineNumberRulerNeverConsumesTheEditorViewport() {
    let scrollView = GrammarEditorScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 520))
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    let textView = GrammarSourceEditor.makeTextView(contentSize: scrollView.contentSize)
    scrollView.documentView = textView
    let container = GrammarEditorContainerView(scrollView: scrollView, textView: textView)
    container.frame = NSRect(x: 0, y: 0, width: 380, height: 520)
    container.layoutSubtreeIfNeeded()
    let ruler = container.ruler

    #expect(ruler.frame.width <= 48)
    #expect(scrollView.frame.minX >= ruler.frame.maxX)
    #expect(scrollView.contentView.frame.width >= 300)
    #expect(textView.visibleRect.width >= 300)
}

@MainActor
@Test func workbenchLayoutKeepsTheEditorBesideItsLineNumbers() throws {
    struct Host: View {
        @State var document = GrammarWorkbenchDocument()
        var body: some View { GrammarWorkbenchView(document: $document) }
    }

    let hostingView = NSHostingView(rootView: Host())
    hostingView.frame = NSRect(
        x: 0, y: 0,
        width: WorkbenchVisualFoundation.windowMinimumWidth,
        height: WorkbenchVisualFoundation.windowMinimumHeight
    )
    hostingView.layoutSubtreeIfNeeded()

    func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
    }

    let ruler = try #require(descendants(of: GrammarLineNumberRulerView.self, in: hostingView).first)
    let textView = try #require(descendants(of: NSTextView.self, in: hostingView).first {
        $0.accessibilityIdentifier() == "grammar-source-editor"
    })
    let rulerFrame = ruler.convert(ruler.bounds, to: hostingView)
    let editorScrollView = try #require(textView.enclosingScrollView as? GrammarEditorScrollView)
    editorScrollView.layoutSubtreeIfNeeded()
    let clipFrame = editorScrollView.contentView.convert(editorScrollView.contentView.bounds, to: hostingView)
    let editorFrame = textView.convert(textView.visibleRect, to: hostingView)

    #expect(rulerFrame.width <= 48)
    #expect(editorFrame.width >= WorkbenchVisualFoundation.sourceMinimumWidth - 80)
    #expect(clipFrame.minX >= rulerFrame.maxX - 1)
    #expect(editorFrame.minX >= rulerFrame.maxX - 1)
    #expect(editorFrame.intersects(rulerFrame) == false)
}
#endif

import Foundation
@testable import GrammarWorkbench
import Testing

@Suite("Workbench navigation")
struct WorkbenchNavigationTests {
    @Test("Sidebar hierarchy contains every destination exactly once")
    func hierarchy() {
        let grouped = GrammarWorkbenchNavigationSection.allCases.flatMap {
            GrammarWorkbenchDestination.destinations(in: $0)
        }
        #expect(grouped == GrammarWorkbenchDestination.allCases)
        #expect(Set(grouped).count == grouped.count)
        #expect(GrammarWorkbenchDestination.destinations(in: .start) == [.guide, .project])
        #expect(GrammarWorkbenchDestination.destinations(in: .runAndDeliver) == [
            .sample, .tests, .generation
        ])
        #expect(GrammarWorkbenchDestination.destinations(in: .expert) == [
            .automaton, .table, .bootstrap, .research, .visuals
        ])
    }

    @Test("Destination metadata is stable and usable without SwiftUI")
    func metadata() throws {
        #expect(GrammarWorkbenchDestination.diagram.title == "Diagram & REPL")
        #expect(GrammarWorkbenchDestination.explore.section == .grammar)
        #expect(GrammarWorkbenchDestination.allCases.allSatisfy {
            !$0.title.isEmpty && !$0.systemImage.isEmpty
        })
        let encoded = try JSONEncoder().encode(GrammarWorkbenchDestination.research)
        #expect(try JSONDecoder().decode(GrammarWorkbenchDestination.self, from: encoded) == .research)
    }

    #if os(macOS)
    @Test("Optional navigation fits the stable three-region minimum")
    func widthBudget() {
        #expect(WorkbenchVisualFoundation.requiredPaneWidth <= WorkbenchVisualFoundation.windowMinimumWidth)
        #expect(WorkbenchVisualFoundation.expandedPaneWidth <= WorkbenchVisualFoundation.windowMinimumWidth)
        #expect(WorkbenchVisualFoundation.navigationMinimumWidth >= 180)
    }
    #endif
}

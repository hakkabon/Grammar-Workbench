import GrammarWorkbench
import Testing

@Suite("Large-iPad adaptive workbench foundation")
struct TabletPlatformFoundationTests {
    @Test("The first tablet pilot exposes the core exploration loop")
    func coreFeatureScope() {
        let available = Set(GrammarWorkbenchTabletFoundation.availableFeatures)
        #expect(GrammarWorkbenchTabletFoundation.minimumMajorOSVersion == 17)
        #expect(available.isSuperset(of: [
            .documentEditing, .guide, .analysis, .samples, .tests, .diagrams, .grammarREPL
        ]))
    }

    @Test("Dense desktop administration remains an explicit deferral")
    func deferredScope() {
        #expect(GrammarWorkbenchTabletFoundation.status(of: .expertAutomaton) == .deferred)
        #expect(GrammarWorkbenchTabletFoundation.status(of: .hostedAdministration) == .deferred)
        #expect(GrammarWorkbenchTabletFoundation.status(of: .generation) == .prototype)
    }
}

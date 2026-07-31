import Testing
@testable import GrammarWorkbench

@Test func releaseMetadataHasAValidSemanticVersionAndBundleIdentifier() {
    let components = GrammarWorkbenchRelease.version.split(separator: ".")
    #expect(components.count == 3)
    #expect(components.allSatisfy { Int($0) != nil })
    #expect(GrammarWorkbenchRelease.bundleIdentifier == "com.grammar-workbench.app")
}

@Test func packagedGettingStartedResourceIsAvailable() {
    #expect(GrammarWorkbenchRelease.gettingStarted.contains("Grammar Workbench"))
    #expect(GrammarWorkbenchRelease.gettingStarted.contains("%token"))
}

import Foundation
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

@Test func packagedAppDeclaresTextGrammarDocuments() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let packageRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let plist = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: packageRoot.appendingPathComponent("Packaging/Info.plist")),
        format: nil
    ) as? [String: Any]
    let documentTypes = plist?["CFBundleDocumentTypes"] as? [[String: Any]]
    let grammarSource = documentTypes?.first {
        ($0["CFBundleTypeName"] as? String) == "Grammar Source"
    }
    let extensions = grammarSource?["CFBundleTypeExtensions"] as? [String]

    #expect(extensions?.contains("grammar") == true)
    #expect(extensions?.contains("txt") == true)

    let ebnfSource = documentTypes?.first {
        ($0["CFBundleTypeName"] as? String) == "Extended Backus-Naur Form Grammar"
    }
    #expect((ebnfSource?["CFBundleTypeExtensions"] as? [String])?.contains("ebnf") == true)
}

import SwiftUI

@main
struct GrammarWorkbenchApp: App {
    var body: some Scene {
        WindowGroup("Grammar Workbench") {
            ArtifactExplorerView()
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
    }
}

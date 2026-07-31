import SwiftUI
import GrammarWorkbench

@main
struct GrammarWorkbenchApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: GrammarWorkbenchDocument()) { configuration in
            GrammarWorkbenchView(
                document: configuration.$document,
                documentName: configuration.fileURL?.lastPathComponent ?? "Untitled"
            )
        }
        .windowResizability(.contentMinSize)
    }
}

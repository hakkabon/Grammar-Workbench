import GrammarWorkbench
import SwiftUI

@main
struct GrammarWorkbenchTabletApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: GrammarWorkbenchDocument()) { configuration in
            GrammarWorkbenchView(
                document: configuration.$document,
                documentName: configuration.fileURL?.lastPathComponent ?? "Untitled"
            )
        }
    }
}

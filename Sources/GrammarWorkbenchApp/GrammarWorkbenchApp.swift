import SwiftUI
import AppKit
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
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Grammar Workbench") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Grammar Workbench",
                        .applicationVersion: GrammarWorkbenchRelease.displayVersion,
                        .credits: NSAttributedString(string: "A native LR grammar construction, testing, and explanation workbench.")
                    ])
                }
            }
            CommandGroup(after: .help) {
                Button("Grammar Workbench Help") {
                    let alert = NSAlert()
                    alert.messageText = "Grammar Workbench Help"
                    alert.informativeText = GrammarWorkbenchRelease.gettingStarted
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }

        Settings {
            GrammarWorkbenchSettingsView()
        }
    }
}

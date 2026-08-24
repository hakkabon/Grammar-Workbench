import Foundation
import GrammarWorkbench
import GrammarWorkbenchSDK

private actor ToolingOutput {
    func write(_ response: GrammarToolingResponse) {
        do {
            var data = try GrammarToolingCodec.encodeLine(response)
            data.append(0x0A)
            FileHandle.standardOutput.write(data)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        }
    }
}

/// Persistent newline-delimited JSON host for `GrammarWorkbenchSDK`.
/// Requests may complete out of order and are correlated by `requestID`.
@main
enum GrammarWorkbenchServiceMain {
    static func main() async {
        let output = ToolingOutput()
        do {
            let environment = ProcessInfo.processInfo.environment
            let collaborationHost: any GrammarCollaborationHosting
            if let path = environment["GRAMMAR_WORKBENCH_COLLABORATION_STORE"],
               !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                collaborationHost = try await GrammarDurableCollaborativeWorkbenchHost.open(
                    store: GrammarCollaborationFileStore(
                        fileURL: URL(fileURLWithPath: path).standardizedFileURL
                    )
                )
            } else {
                collaborationHost = GrammarCollaborativeWorkbenchHost()
            }
            let languageKitHost: any GrammarHostedLanguageKitServing
            if let path = environment["GRAMMAR_WORKBENCH_LANGUAGE_KIT_STORE"],
               !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                languageKitHost = try await GrammarHostedLanguageKitService.open(
                    store: GrammarHostedLanguageKitFileStore(
                        fileURL: URL(fileURLWithPath: path).standardizedFileURL
                    )
                )
            } else {
                languageKitHost = GrammarHostedLanguageKitService()
            }
            let registry = GrammarToolingRequestRegistry(
                service: GrammarStatefulLanguageToolingService(
                    collaborationHost: collaborationHost, hostedLanguageKits: languageKitHost
                )
            )
            await run(registry: registry, output: output)
        } catch {
            FileHandle.standardError.write(Data(
                "error: persistent service store could not be opened: \(error.localizedDescription)\n".utf8
            ))
        }
    }

    private static func run(registry: GrammarToolingRequestRegistry, output: ToolingOutput) async {
        await withTaskGroup(of: Void.self) { group in
            while let line = readLine(strippingNewline: true) {
                guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let data = Data(line.utf8)
                do {
                    let request = try GrammarToolingCodec.decodeRequest(data)
                    group.addTask {
                        await output.write(await registry.handle(request))
                    }
                } catch {
                    await output.write(.init(
                        requestID: "invalid-request", status: .failure,
                        error: .init(code: "invalid-json", message: error.localizedDescription)
                    ))
                }
            }
        }
    }
}

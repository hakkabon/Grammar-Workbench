import Foundation
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
        let registry = GrammarToolingRequestRegistry()
        let output = ToolingOutput()
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

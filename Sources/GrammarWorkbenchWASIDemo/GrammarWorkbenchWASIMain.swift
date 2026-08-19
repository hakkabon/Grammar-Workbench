import Foundation
import GrammarWorkbenchSDK

/// Minimal WASI-friendly host for the stateless tooling contract. Each input
/// line is one `GrammarToolingRequest`; each output line is its correlated
/// `GrammarToolingResponse`. It also runs as a native executable for contract
/// testing without a WASM SDK.
@main
enum GrammarWorkbenchWASIMain {
    static func main() async {
        let service = GrammarLanguageToolingService()
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            do {
                let request = try GrammarToolingCodec.decodeRequest(Data(line.utf8))
                let response = await service.handle(request)
                print(String(decoding: try GrammarToolingCodec.encodeLine(response), as: UTF8.self))
            } catch {
                let response = GrammarToolingResponse(
                    requestID: "invalid-request", status: .failure,
                    error: .init(code: "invalid-json", message: error.localizedDescription)
                )
                if let data = try? GrammarToolingCodec.encodeLine(response) {
                    print(String(decoding: data, as: UTF8.self))
                }
            }
        }
    }
}

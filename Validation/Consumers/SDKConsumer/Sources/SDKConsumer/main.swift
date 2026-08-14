import GrammarWorkbenchSDK

@main
struct SDKConsumer {
    static func main() async throws {
        let client = GrammarToolingClient(transport: GrammarInProcessToolingTransport())
        let response = try await client.send(.init(operation: .capabilities))
        guard response.status == .success,
              response.capabilities?.operations.contains(.parse) == true else {
            fatalError("Language-tooling SDK capability negotiation failed")
        }
        print("sdk-consumer-ok")
    }
}

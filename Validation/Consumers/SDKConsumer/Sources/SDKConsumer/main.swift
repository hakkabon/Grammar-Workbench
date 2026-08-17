import GrammarWorkbenchSDK

@main
struct SDKConsumer {
    static func main() async throws {
        let client = GrammarToolingClient(transport: GrammarInProcessToolingTransport())
        let response = try await client.send(.init(operation: .capabilities))
        guard response.status == .success,
              response.capabilities?.operations.contains(.parse) == true,
              response.capabilities?.operations.contains(.graphLayout) == true,
              response.capabilities?.features["graphVisualizationPlatform"] == .stable else {
            fatalError("Language-tooling SDK capability negotiation failed")
        }
        let stateful = GrammarToolingClient(transport: GrammarStatefulInProcessToolingTransport())
        let statefulCapabilities = try await stateful.send(.init(operation: .capabilities))
        guard statefulCapabilities.capabilities?.operations.contains(.sessionOpen) == true else {
            fatalError("Stateful tooling capability negotiation failed")
        }
        let session = try await stateful.send(.init(
            operation: .sessionOpen,
            compilation: .init(source: "%start S\nS : 'ok' ;"),
            sessionID: "consumer"
        ))
        guard session.session?.id == "consumer" else {
            fatalError("Stateful tooling session did not open")
        }
        print("sdk-consumer-ok")
    }
}

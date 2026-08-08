import GrammarWorkbenchLSP

@main
enum LSPConsumer {
    static func main() async {
        let store = DocumentStore()
        guard await store.openURIs.isEmpty else {
            fatalError("A new document store must be empty")
        }
        print("lsp-consumer-ok")
    }
}

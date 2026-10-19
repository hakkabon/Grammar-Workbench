import Foundation
import GrammarWorkbenchCore
import GrammarWorkbenchReferenceExtension

let source = "%start S\nS : 'capability' ;"
let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
guard compilation.succeeded else { fatalError("Reference grammar did not compile") }

let registry = GrammarWorkbenchExtensionRegistry()
try await registry.register(CapabilityReportExtension())
let snapshot = await registry.snapshot()
guard snapshot.extensions.map(\.id) == [CapabilityReportExtension.identifier] else {
    fatalError("Reference extension discovery failed")
}

let result = try await registry.run(
    extensionIdentifier: CapabilityReportExtension.identifier,
    commandIdentifier: "capability-report",
    compilation: compilation,
    options: .init(["detail": "full"])
)
guard result.files.count == 1,
      result.files[0].suggestedFilename == "grammar-capabilities.json",
      result.properties["analysisAvailable"] == "true",
      let payload = try JSONSerialization.jsonObject(with: result.files[0].contents) as? [String: Any],
      payload["productionCount"] as? Int == 1,
      payload["startSymbol"] as? String == "S"
else { fatalError("Reference extension result failed validation") }

print("reference-extension-ok")

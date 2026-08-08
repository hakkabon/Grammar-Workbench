import Foundation
import PackagePlugin

@main
struct GrammarWorkbenchPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }
        let tool = try context.tool(named: "GrammarWorkbenchCLI")
        return sourceTarget.sourceFiles.compactMap { file in
            let source = file.url
            guard ["grammar", "ebnf"].contains(source.pathExtension.lowercased()) else { return nil }
            let base = source.deletingPathExtension().lastPathComponent
            let typeName = swiftIdentifier(base) + "Parser"
            let output = context.pluginWorkDirectoryURL.appending(path: "\(typeName).swift")
            return .buildCommand(
                displayName: "Generate \(typeName) from \(source.lastPathComponent)",
                executable: tool.url,
                arguments: ["generate", "swift", source.path, output.path, "LALR(1)", "typeName=\(typeName)"],
                inputFiles: [source],
                outputFiles: [output]
            )
        }
    }

    private func swiftIdentifier(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" ? Character(String(scalar)) : "_"
        }
        var result = String(scalars)
        if result.first?.isNumber == true { result = "_" + result }
        return result.isEmpty ? "Grammar" : result
    }
}

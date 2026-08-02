import Darwin
import Foundation
import GrammarWorkbench

@main
struct GrammarWorkbenchCLI {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            print(help)
            return
        }
        switch command {
        case "--help", "-h", "help":
            print(help)
        case "--version", "-v", "version":
            print("grammar-workbench \(GrammarWorkbenchRelease.version)")
        case "validate":
            guard arguments.count == 2 else { throw CLIError.usage("validate requires a grammar file") }
            let source = try read(arguments[1])
            let compilation = GrammarWorkbenchAPI.compile(.init(source: source))
            for diagnostic in compilation.diagnostics {
                print("\(diagnostic.severity.rawValue):\(diagnostic.range.start.line):\(diagnostic.range.start.column): \(diagnostic.message)")
            }
            guard compilation.succeeded, let grammar = compilation.grammar else { throw CLIError.validationFailed }
            print("Valid grammar: \(grammar.productions.count) productions, \(grammar.terminals.count) terminals")
        case "test":
            guard arguments.count == 2 else { throw CLIError.usage("test requires a project interchange or .grammarworkbench file") }
            let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
            let document: GrammarWorkbenchDocument
            if let interchange = try? GrammarInterchangeCodec.decode(data) {
                document = interchange
            } else {
                document = try JSONDecoder().decode(GrammarWorkbenchDocument.self, from: data)
            }
            guard let algorithm = GrammarAlgorithm(rawValue: document.algorithm) else {
                throw CLIError.usage("unknown LR algorithm ‘\(document.algorithm)’")
            }
            let compilation = GrammarWorkbenchAPI.compile(.init(source: document.source, algorithm: algorithm))
            let report = compilation.runTests(document.tests)
            for result in report.results {
                print("\(result.status.rawValue.uppercased()) \(result.name): \(result.message)")
            }
            print("\(report.passed) passed, \(report.failed) failed")
            if !report.allPassed { throw CLIError.testsFailed }
        case "export-artifact":
            guard arguments.count == 3 || arguments.count == 4 else {
                throw CLIError.usage("export-artifact requires GRAMMAR OUTPUT [ALGORITHM]")
            }
            let source = try read(arguments[1])
            let algorithm = arguments.count == 4 ? arguments[3] : "LALR(1)"
            let data = try GrammarInterchangeCodec.encodeArtifact(source: source, algorithm: algorithm)
            try data.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
            print("Wrote \(arguments[2])")
        default:
            throw CLIError.usage("unknown command ‘\(command)’")
        }
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    private static let help = """
    Grammar Workbench \(GrammarWorkbenchRelease.version)

    Usage:
      grammar-workbench validate GRAMMAR
      grammar-workbench test PROJECT
      grammar-workbench export-artifact GRAMMAR OUTPUT [ALGORITHM]
      grammar-workbench --version

    ALGORITHM is one of SLR(1), LALR(1), or Canonical LR(1).
    """
}

private enum CLIError: LocalizedError {
    case usage(String)
    case validationFailed
    case testsFailed

    var errorDescription: String? {
        switch self {
        case .usage(let detail): "\(detail). Run with --help for usage."
        case .validationFailed: "grammar validation failed"
        case .testsFailed: "one or more grammar tests failed"
        }
    }
}

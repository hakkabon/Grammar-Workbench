import Foundation
import Testing
@testable import GrammarWorkbench

@Test func portableBNFInterchangeCanonicalizesAndVerifiesRoundTrip() throws {
    let source = "<start> ::= <item> <start> | <item>\n<item> ::= 'x' | 'y'\n"
    let value = try GrammarPortableInterchangeCodec.importGrammar(
        source, notation: .bnfProfile, startSymbol: "start"
    )
    #expect(value.kind == GrammarPortableInterchange.kindIdentifier)
    #expect(value.fingerprint == value.specification.fingerprint)
    #expect(value.specification.productions.count == 4)

    let data = try GrammarPortableInterchangeCodec.encode(value)
    let decoded = try GrammarPortableInterchangeCodec.decode(data)
    #expect(decoded == value)
    #expect(try GrammarPortableInterchangeCodec.verifyRoundTrip(decoded, through: .bnfProfile).matches)
}

@Test func portableWorkbenchAndEBNFImportsShareCanonicalContracts() throws {
    let workbench = try GrammarPortableInterchangeCodec.importGrammar(
        "%start Root\n%token WORD /word/\nRoot : WORD ;", notation: .workbench
    )
    #expect(workbench.specification.startSymbol == "Root")
    #expect(try GrammarPortableInterchangeCodec.verifyRoundTrip(workbench, through: .workbench).matches)

    let ebnf = try GrammarPortableInterchangeCodec.importGrammar(
        "root = \"hello\" , { \"world\" } ;", notation: .ebnf
    )
    #expect(ebnf.specification.startSymbol == "root")
    #expect(!ebnf.specification.productions.isEmpty)
}

@Test func portableInterchangeRejectsTamperedFingerprint() throws {
    let value = GrammarPortableInterchange(
        sourceNotation: .bnfProfile,
        specification: .init(
            startSymbol: "start",
            productions: [.init(lhs: "start", rhs: [.literal("ok")])]
        )
    )
    var object = try #require(JSONSerialization.jsonObject(
        with: GrammarPortableInterchangeCodec.encode(value)
    ) as? [String: Any])
    object["fingerprint"] = "tampered"
    let data = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: GrammarPortableInterchangeError.self) {
        try GrammarPortableInterchangeCodec.decode(data)
    }
}

@Test func bootstrapBundleCarriesCanonicalGrammarAndFixedPointEvidence() throws {
    let bundle = try GrammarBootstrapInterchangeCodec.makeBundle(
        options: .init(maximumGenerations: 3)
    )
    #expect(bundle.report.succeeded)
    #expect(bundle.metaGrammar.specification.startSymbol == "syntax")
    #expect(bundle.report.generations.last?.grammarFingerprint == bundle.metaGrammar.fingerprint)
    let decoded = try GrammarBootstrapInterchangeCodec.decode(
        GrammarBootstrapInterchangeCodec.encode(bundle)
    )
    #expect(decoded == bundle)
}

@Test func portableInterchangeRejectsUndefinedStartsAndUnrepresentableProfileEpsilon() throws {
    let undefined = GrammarPortableInterchange(
        sourceNotation: .workbench,
        specification: .init(
            startSymbol: "missing",
            productions: [.init(lhs: "defined", rhs: [.literal("ok")])]
        )
    )
    #expect(throws: GrammarPortableInterchangeError.self) {
        try GrammarPortableInterchangeCodec.encode(undefined)
    }

    let epsilon = GrammarPortableInterchange(
        sourceNotation: .workbench,
        specification: .init(
            startSymbol: "start", productions: [.init(lhs: "start", rhs: [])]
        )
    )
    #expect(throws: GrammarPortableInterchangeError.self) {
        try GrammarPortableInterchangeCodec.render(epsilon, as: .bnfProfile)
    }
    #expect(try GrammarPortableInterchangeCodec.render(epsilon, as: .workbench).contains("start :  ;"))
}

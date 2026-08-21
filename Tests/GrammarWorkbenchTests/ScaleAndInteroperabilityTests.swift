import Foundation
import GrammarWorkbench
import Testing

@Test func yaccProfileImportsActionsAndRoundTripsCanonically() throws {
    let source = """
    %{ int helper; %}
    %token NUMBER
    %left '+'
    %start expression
    %%
    expression : expression '+' term { $$ = $1 + $3; } | term ;
    term : NUMBER | '(' expression ')' ;
    %%
    """
    let interchange = try GrammarPortableInterchangeCodec.importGrammar(
        source, notation: .yacc
    )
    #expect(interchange.sourceNotation == .yacc)
    #expect(interchange.specification.startSymbol == "expression")
    #expect(interchange.specification.productions.count == 4)
    #expect(try GrammarPortableInterchangeCodec.verifyRoundTrip(
        interchange, through: .yacc
    ).matches)
}

@Test func yaccProfileSupportsEmptyAndPrecedenceProductions() throws {
    let interchange = try GrammarPortableInterchangeCodec.importGrammar(
        "%token ID LOW\n%start list\n%%\nlist : %empty | list ID %prec LOW ;\n%%",
        notation: .yacc
    )
    #expect(interchange.specification.productions.contains { $0.rhs.isEmpty })
    #expect(interchange.specification.productions.contains {
        $0.rhs == [.nonterminal("list"), .terminal("ID")]
    })
}

@Test func portableScaleAuditHandlesLargeCanonicalGrammarsWithoutConstruction() throws {
    let count = 5_000
    let productions = (0..<count).map { index in
        GrammarBootstrapProduction(
            lhs: "rule\(index)",
            rhs: index + 1 < count
                ? [.nonterminal("rule\(index + 1)")]
                : [.literal("done")]
        )
    }
    let interchange = GrammarPortableInterchange(
        sourceNotation: .yacc,
        specification: .init(startSymbol: "rule0", productions: productions)
    )
    let report = try GrammarPortableScaleValidator.validate(interchange)
    #expect(report.productions == count)
    #expect(report.nonterminals == count)
    #expect(report.rightHandSideSymbols == count)
    #expect(report.fingerprint == interchange.fingerprint)
}

@Test func portableScaleAuditRejectsEachBoundBeforeParserConstruction() throws {
    let interchange = GrammarPortableInterchange(
        sourceNotation: .yacc,
        specification: .init(
            startSymbol: "root",
            productions: [.init(lhs: "root", rhs: [.literal("value")])]
        )
    )
    #expect(throws: GrammarPortableScaleError.self) {
        try GrammarPortableScaleValidator.validate(
            interchange, sourceBytes: 100,
            limits: .init(
                maximumSourceBytes: 10, maximumProductions: 10,
                maximumSymbols: 10, maximumRightHandSideSymbols: 10
            )
        )
    }
    #expect(throws: GrammarPortableScaleError.self) {
        try GrammarPortableScaleValidator.validate(
            interchange,
            limits: .init(
                maximumSourceBytes: 10, maximumProductions: 0,
                maximumSymbols: 10, maximumRightHandSideSymbols: 10
            )
        )
    }
}

@Test func yaccProfileRejectsMalformedExternalInput() throws {
    #expect(throws: GrammarPortableInterchangeError.self) {
        try GrammarPortableInterchangeCodec.importGrammar("root : ID ;", notation: .yacc)
    }
    #expect(throws: GrammarPortableInterchangeError.self) {
        try GrammarPortableInterchangeCodec.importGrammar("%%\nroot ID ;\n%%", notation: .yacc)
    }
}

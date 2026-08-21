# Release-candidate validation

The release gate requires a strictly validated semantic language-kit fixture and bounds its production, semantic-rule, and conformance-test counts. This exercises the portable kit codec and catches stale selectors or failing language behavior before packaging.

A portable graph fixture is laid out through the shipped Swift-Layout binary during release validation. Node and edge counts and elapsed layout time are bounded, and the CLI smoke workflow exports both JSON and SVG forms.

The canonical BNF fixture must survive an identity-preserving portable-interchange round trip. The bootstrap bundle must contain matching meta-grammar and fixed-point fingerprints and remain within its serialized-size budget.

The packaged research programme must pass every declared hypothesis, preserve repeated and DFS/BFS evidence identities, and remain within its case-count, repetition, report-size, and median-runtime budgets.

Every selected research preview must pass its embedded programme and remain within the catalog-count and encoded-size budgets. Preview conclusions never replace the underlying integrity-checked evidence report.

The release-candidate gate verifies the product from four perspectives:

1. The root test suite validates algorithms, documents, GUI foundations, compatibility, packaging metadata, and performance budgets.
2. Downstream fixtures compile only against published library and plugin products.
3. The release CLI and LSP server run their corpus, interchange, framed-stdio, and editor-client smoke workflows.
4. A representative ambiguous grammar must complete generalized parsing within the declared configuration, step, and forest-size budgets.
5. A representative incremental edit must retain the declared minimum percentages of unchanged token identities and semantic values, and remain below the declared maximum relex and reparse percentages.
6. Optional packaging assembles and validates the application, CLI, LSP, and editor-client archives exactly as a release build does.
7. The reference multi-document project manifest must decode, analyze, test, validate its generator plan, and generate its declared output through the packaged CLI.
8. Adaptive parsing must escalate at unresolved conflicts, and the declared bounded batch must preserve request order while staying within generalized-engine limits.
9. Guided grammar engineering must remain a stable public capability, prioritize blocking diagnostics and unresolved decisions, and validate source cleanup against samples and tests before application.
10. Grammar transformation plans must explain every edit, reject stale source, stay within declared corpus-generation bounds, and preserve membership for the release corpus and recorded tests.
11. The bootstrap laboratory must reach a canonical fixed point within the packaged generation budget and agree with the trusted handwritten BNF reader on the packaged differential corpus. It remains a laboratory and must not silently replace the trusted reader.
12. A Catalan-ambiguous grammar must retain all represented derivations in a shared-packed forest while staying within declared node and family budgets, independently of concrete-tree enumeration limits.
13. Semantic workspace services must resolve the packaged cross-document corpus without diagnostics, stay within symbol and dependency budgets, and reject stale rename plans before applying any document edit.
14. The integrated project experience must retain its five task destinations, combine project and semantic problems within the declared bound, and remain a stable Codable contract.
15. The stateful tooling service must preserve incremental document revisions, serialize each session, expose capability-negotiated JSON-lines framing, and keep session/document counts within declared release bounds.
16. The packaged research programme must pass all hypotheses with stable repeated and DFS/BFS evidence, produce an integrity-checked report, and stay within declared execution and serialization budgets.
17. The selected research catalog must stay intentionally small, run every embedded programme successfully, and retain the full report beneath each plain-language preview.
18. The native editor must start with a non-zero viewport, contain long grammar lines, and preserve simultaneous minimum widths for the source, task, and inspector panes without adaptive overlay behavior.
19. The packaged source-project descriptor must resolve only safe relative files, match its bounded source set, analyze successfully, and preserve its explicit language-to-grammar association independently of filenames.
20. The browser runtime must validate its versioned artifact, accept and reject
    the reference corpus, report located diagnostics, enforce declared input,
    token, step, and stack bounds, and retain worker-termination cancellation.
21. Grammar rename plans must preserve Workbench and EBNF notation, exclude
    comments, literals, and patterns, reject stale or colliding edits, and stay
    within the declared edit and affected-line budgets while preserving the
    release corpus and saved tests.
22. The packaged language-kit fixture must preserve package/kit identity,
    compile with passing conformance tests, stay within the direct-dependency
    budget, and resolve within the declared package-count bound.
23. The Yacc interoperability fixture must discard foreign actions, preserve
    canonical grammar identity through deterministic export and re-import, and
    complete its pre-construction scale audit within the published size and
    latency bounds.
24. The collaborative host must fill its declared workspace, participant, and
    document capacities, preserve ordered bounded events, reject stale edits,
    and replay retained operation identifiers without duplicate mutation.

Run the normal gate:

```sh
Scripts/validate-release-candidate.sh
```

Run the complete packaging gate:

```sh
Scripts/validate-release-candidate.sh --package
```

Developer ID signing and notarization remain credential-gated. Supply `SIGNING_IDENTITY` and `NOTARY_PROFILE` to the packaging gate when validating a distribution candidate.

Budgets and required consumer fixtures are declared in `Packaging/ReleaseCandidate.json`. Budget changes should be reviewed as release-policy changes, not silently adjusted to accommodate regressions.

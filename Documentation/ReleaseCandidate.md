# Release-candidate validation

The release-candidate gate verifies the product from four perspectives:

1. The root test suite validates algorithms, documents, GUI foundations, compatibility, packaging metadata, and performance budgets.
2. Downstream fixtures compile only against published library and plugin products.
3. The release CLI and LSP server run their corpus, interchange, framed-stdio, and editor-client smoke workflows.
4. A representative ambiguous grammar must complete generalized parsing within the declared configuration, step, and forest-size budgets.
5. A representative incremental edit must retain the declared minimum percentages of unchanged token identities and semantic values, and remain below the declared maximum relex and reparse percentages.
6. Optional packaging assembles and validates the application, CLI, LSP, and editor-client archives exactly as a release build does.
7. The reference multi-document project manifest must decode, analyze, test, validate its generator plan, and generate its declared output through the packaged CLI.
8. Adaptive parsing must escalate at unresolved conflicts, and the declared bounded batch must preserve request order while staying within generalized-engine limits.

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

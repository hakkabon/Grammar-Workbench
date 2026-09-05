# Dependency-boundary audit

`Validation/Ecosystem/DependencyBoundaries.json` is the reviewed allowlist for
direct dependencies of the six repositories in the compatibility manifest. It
assigns every known dependency an owner and architectural layer. A dependency
between ecosystem packages must point to a lower layer; external packages are
classified explicitly rather than being accepted implicitly.

The audit evaluates manifests through `swift package dump-package`. It rejects:

- an unclassified or newly introduced direct dependency;
- a reverse or lateral ecosystem dependency;
- a dependency duplicated under the same SwiftPM identity;
- a local package dependency or mutable branch requirement;
- an allowlist entry that is no longer present in the manifest; and
- a package whose declared SwiftPM name no longer matches its reviewed identity.

Compatible version ranges, exact versions, and exact revisions are accepted.
Local source-control mirrors remain valid because the audit uses SwiftPM package
identity and requirement data rather than comparing the resolved URL.

Run the Workbench boundary locally:

```sh
node Scripts/audit-dependency-boundaries.mjs \
  --package Grammar-Workbench="$PWD"
```

The pinned integration workflow supplies every checked-out repository to the
same command. Swift 6.0 validates Grammar, Parser, LR-Parsing, Compiler, and
Workbench; the separate Swift 6.1 job validates Grammar-REPL. Each integration
artifact includes a machine-readable dependency-boundary report next to the
existing compatibility report.

Supporting packages appear as classified dependency targets but are not claimed
as audited repositories. Promoting one into the compatibility set requires an
exact pinned revision, an `audited` policy entry with its complete direct
allowlist, and inclusion in the pinned workflow.

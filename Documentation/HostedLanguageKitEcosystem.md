# Hosted language-kit ecosystem

Phase 40 adds a transport-neutral distribution service over the deterministic
language-kit packages and resolver introduced in Phase 32. It provides hosted
publication and discovery without embedding a particular network framework,
identity provider, or cloud vendor in the core package.

## Registry contract

`GrammarHostedLanguageKitService` validates and compiles every package before
publication. A published identifier/version is immutable: different content
must use a new semantic version. Each record contains the complete package,
publisher identity, canonical package fingerprint, publication sequence, and
withdrawal state.

Withdrawal hides a version from ordinary fetches, catalogs, and dependency
resolution without deleting it or its audit history. The original publisher
may restore it. Active packages use the Phase 32 resolver, retaining its
newest-compatible selection, backtracking, dependency-first ordering, and
cycle detection.

Publishing and lifecycle mutations use operation IDs for bounded idempotent
replay. A bounded ordered stream records publication, withdrawal, and
restoration. Package count, encoded size, audit retention, identities,
publisher ownership, and event-history gaps are explicitly enforced.

## Durable hosting

`GrammarHostedLanguageKitArchive` stores records, events, replay state,
revision, and next sequence. Restoration recompiles every embedded kit and
validates fingerprints, duplicate identities, limits, event continuity, and
replay ownership. Invalid or future archives fail closed.

`GrammarHostedLanguageKitFileStore` uses atomic replacement writes;
`GrammarHostedLanguageKitMemoryStore` supports embedding and tests. Durable
mutations roll live state back if saving fails.

Set `GRAMMAR_WORKBENCH_LANGUAGE_KIT_STORE` on the JSON-lines service to enable
file-backed hosting independently of collaborative-workspace storage:

```sh
GRAMMAR_WORKBENCH_LANGUAGE_KIT_STORE=/var/lib/grammar-workbench/language-kits.json \
  grammar-workbench-service
```

## Stateful tooling operations

The persistent SDK exposes `languageKitHostPublish`, `languageKitHostWithdraw`,
`languageKitHostRestore`, `languageKitHostPackage`, `languageKitHostCatalog`,
`languageKitHostResolve`, and `languageKitHostEvents`. HTTP or WebSocket
adapters can preserve the same Codable validation and error semantics.

## Trust boundary and limits

Publisher identity is explicit audit input, not authentication. A network host
must authenticate callers and authorize the supplied identity before invoking
mutations. The core does not provide signatures, malware isolation, billing,
rate limiting, moderation, multi-region replication, or transparency-log
anchoring. Withdrawal is not deletion. The file store is single-writer and is
not a distributed database.

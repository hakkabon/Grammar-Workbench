# Language-kit ecosystem

Phase 32 turns semantic language kits into reproducible packages. A
`GrammarLanguageKitPackageManifest` embeds one validated
`GrammarSemanticLanguageKitManifest`, gives its version semantic meaning, and
declares explicit package prerequisites. Dependencies do not merge grammars or
semantic schemas: a host resolves and loads them as separate language-kit
capabilities.

Package and catalog schemas are versioned, Codable, deterministic JSON
contracts. `GrammarLanguageKitPackageCodec` validates package/kit identity and
version agreement, rejects duplicate or self dependencies, and compiles the
embedded kit with passing conformance tests. A
`GrammarLanguageKitCatalog` is a self-contained source-control or release
artifact containing one or more package versions.

`GrammarLanguageKitPackageRegistry` resolves a set of version requirements
offline. It chooses the newest compatible package, backtracks across transitive
constraints, rejects missing dependencies and cycles, and returns packages in
dependency-first order. Requirements use inclusive minimum and optional
exclusive maximum versions; `compatible(with:)` follows the next-major boundary
for 1.x and the next-minor boundary for 0.x.

## Authoring workflow

Create a conformant starter package:

```sh
swift run grammar-workbench kit-template \
  org.example.language "Example Language" 0.1.0 example ExampleLanguageKit.json
```

Validate a package and its embedded grammar, semantic selectors, and tests:

```sh
swift run grammar-workbench kit-package-validate ExampleLanguageKit.json
```

Resolve a root from an offline catalog, optionally writing a lock-style result:

```sh
swift run grammar-workbench kit-resolve Catalog.json \
  org.example.language 0.1.0 Resolution.json
```

The template is intentionally small. Authors should add semantic rules,
negative conformance cases, generator targets, and descriptive metadata before
distribution. The package format embeds content rather than filesystem paths,
so validation and resolution behave the same in an editor, CI, and a release
archive.

## Compatibility policy

Package identifiers are namespaced and immutable. The package identifier and
version must exactly match the embedded semantic kit. Additive language changes
should use a minor version; incompatible syntax or semantic changes should use
a major version. Pre-1.0 compatibility is deliberately narrower. Catalogs can
carry several versions, but cannot contain the same identifier/version twice.

The Phase 32 release gate validates a packaged example and bounds direct
dependency and resolved-package counts. Phase 40 supplies a transport-neutral
hosted registry over this foundation; see
[Hosted language-kit ecosystem](HostedLanguageKitEcosystem.md). Signatures,
publisher authentication, and network acquisition remain adapter and deployment
concerns rather than requirements for deterministic offline builds.

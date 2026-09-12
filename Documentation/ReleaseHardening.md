# Release hardening

Release packaging now fails closed around source identity and artifact
integrity. The same checks run locally and in the release workflow; GitHub
Actions is an execution host, not the owner of the contract.

## Immutable source identity

`Scripts/release-artifacts.mjs source` validates:

- the single stable `major.minor.patch` version embedded in the product;
- an optional release tag, accepting the repository's `1.0.16` convention and
  the conventional `v1.0.16` spelling;
- an optional full release revision against the checked-out `HEAD`;
- a clean checkout when `--require-clean` is selected;
- agreement between `Package.swift` and the pinned portability toolchain; and
- the version, build-number, and bundle-identifier placeholders used to build
  the application property list.

The application repository commits `Package.resolved`. Packaging disables
automatic dependency resolution and rejects a lockfile whose Grammar, Parser,
or LR-Parsing versions and revisions differ from the reviewed ecosystem
manifest. The full lockfile digest and all resolved pins are copied into release
provenance.

Both platform packagers accept `RELEASE_TAG`, `RELEASE_REVISION`, and
`RELEASE_REQUIRE_CLEAN`. Release automation supplies all three. A local
candidate can omit them; its provenance manifest still records the observed
source revision and checkout cleanliness.

## Artifact provenance

The macOS and Linux packagers create a schema-1 JSON manifest containing the
release and build versions, full Git revision, source cleanliness, Swift
toolchain, platform architectures, executable-signing and application-
notarization state, checksum-file digest, and the size and SHA-256 digest of
every published archive. `Validation/Release/ReleaseManifest.schema.json`
publishes the machine-readable interchange contract.

Each manifest has its own SHA-256 sidecar. The independent `verify` command
rejects malformed metadata, symlinks, missing or additional checksum entries,
versionless artifact names, size changes, digest changes, and a notarized state
without signing. Archive containers are also tested before the manifest is
created.

Verify an existing platform release with:

```sh
node Scripts/release-artifacts.mjs verify \
  --manifest /path/to/ReleaseManifest.json
```

Run the dependency-free corruption test with:

```sh
node Scripts/release-artifacts.mjs self-test
```

## Native validation

macOS validation now checks the app, CLI, LSP server, and stateful service. It
requires the expected app version, build number, and complete architecture set.
When signing is requested, every delivered executable must pass strict code-sign
verification. A notarized release must additionally carry a valid stapled
ticket.

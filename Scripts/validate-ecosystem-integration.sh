#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT_DIR/Packaging/EcosystemCompatibility.json"
if [ -n "${ECOSYSTEM_CHECKOUT_ROOT:-}" ]; then
    CHECKOUT_ROOT="$ECOSYSTEM_CHECKOUT_ROOT"
    OWNS_CHECKOUT_ROOT=0
else
    CHECKOUT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/grammar-ecosystem-checkouts.XXXXXX")"
    OWNS_CHECKOUT_ROOT=1
fi
KEEP_CHECKOUTS="${ECOSYSTEM_KEEP_CHECKOUTS:-0}"

cleanup() {
    if [ "$OWNS_CHECKOUT_ROOT" = "1" ] && [ "$KEEP_CHECKOUTS" != "1" ]; then
        rm -rf "$CHECKOUT_ROOT"
    fi
}
trap cleanup EXIT

node "$ROOT_DIR/Scripts/validate-ecosystem-contract.mjs"
mkdir -p "$CHECKOUT_ROOT"

node -e '
const manifest = require(process.argv[1]);
for (const repository of manifest.repositories) {
  if (repository.name !== "Grammar-Workbench") {
    process.stdout.write([repository.name, repository.repository, repository.revision].join("\t") + "\n");
  }
}
' "$MANIFEST" | while IFS=$'\t' read -r name repository revision; do
    checkout="$CHECKOUT_ROOT/$name"
    git clone --quiet --no-checkout "$repository" "$checkout"
    git -C "$checkout" checkout --quiet --detach "$revision"
    actual="$(git -C "$checkout" rev-parse HEAD)"
    if [ "$actual" != "$revision" ]; then
        echo "$name resolved $actual instead of $revision" >&2
        exit 1
    fi
    swift test --package-path "$checkout"
done

swift build --package-path "$ROOT_DIR" -c release --product grammar-workbench
BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c release --show-bin-path)"
node "$ROOT_DIR/Scripts/validate-ecosystem-contract.mjs" --cli "$BIN_DIR/grammar-workbench"

echo "Pinned ecosystem integration validation passed."

#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT_DIR/Packaging/EcosystemCompatibility.json"
KEEP_CHECKOUTS="${ECOSYSTEM_KEEP_CHECKOUTS:-0}"
MIRROR_ROOT="${ECOSYSTEM_REPOSITORY_MIRROR_ROOT:-}"
REPORT_PATH="${ECOSYSTEM_REPORT_PATH:-}"
REPOSITORY_FILTER="${ECOSYSTEM_REPOSITORIES:-}"
SKIP_WORKBENCH="${ECOSYSTEM_SKIP_WORKBENCH:-0}"
LR_ADAPTER=""
COMPILER_ADAPTER=""
GRAMMAR_REPL_ADAPTER=""

if [ -n "${ECOSYSTEM_CHECKOUT_ROOT:-}" ]; then
    CHECKOUT_ROOT="$ECOSYSTEM_CHECKOUT_ROOT"
    OWNS_CHECKOUT_ROOT=0
else
    CHECKOUT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/grammar-ecosystem-checkouts.XXXXXX")"
    OWNS_CHECKOUT_ROOT=1
fi

cleanup() {
    if [ "$OWNS_CHECKOUT_ROOT" = "1" ] && [ "$KEEP_CHECKOUTS" != "1" ]; then
        rm -rf "$CHECKOUT_ROOT"
    fi
}
trap cleanup EXIT

command -v git >/dev/null
command -v node >/dev/null
command -v swift >/dev/null
node "$ROOT_DIR/Scripts/validate-ecosystem-contract.mjs"
mkdir -p "$CHECKOUT_ROOT/checkouts" "$CHECKOUT_ROOT/build"

MANIFEST_SWIFT_VERSION="$(node -p "require(process.argv[1]).swiftIntegrationVersion" "$MANIFEST")"
ACTUAL_SWIFT_VERSION="$(swift --version | sed -n 's/.*Apple Swift version \([0-9]*\.[0-9]*\).*/\1/p' | head -1)"
if [ -z "$ACTUAL_SWIFT_VERSION" ]; then
    ACTUAL_SWIFT_VERSION="$(swift --version | sed -n 's/.*Swift version \([0-9]*\.[0-9]*\).*/\1/p' | head -1)"
fi
if [ -z "$REPOSITORY_FILTER" ] && [ "$ACTUAL_SWIFT_VERSION" != "$MANIFEST_SWIFT_VERSION" ] && [ "${ECOSYSTEM_ALLOW_TOOLCHAIN_MISMATCH:-0}" != "1" ]; then
    echo "Swift $MANIFEST_SWIFT_VERSION is required by the ecosystem manifest; found ${ACTUAL_SWIFT_VERSION:-unknown}." >&2
    exit 1
fi
if [ -z "$REPOSITORY_FILTER" ] && [ "$ACTUAL_SWIFT_VERSION" != "$MANIFEST_SWIFT_VERSION" ]; then
    echo "Warning: validating with Swift ${ACTUAL_SWIFT_VERSION:-unknown} instead of manifest baseline $MANIFEST_SWIFT_VERSION." >&2
fi

REPOSITORY_ROWS="$CHECKOUT_ROOT/repositories.tsv"
node -e '
const manifest = require(process.argv[1]);
for (const repository of manifest.repositories) {
  if (repository.name !== "Grammar-Workbench") {
    process.stdout.write([repository.name, repository.repository, repository.revision, repository.adoption, repository.swiftVersion ?? manifest.swiftIntegrationVersion].join("\t") + "\n");
  }
}
' "$MANIFEST" > "$REPOSITORY_ROWS"

while IFS=$'\t' read -r name repository revision adoption swift_version; do
    if [ -n "$REPOSITORY_FILTER" ]; then
        case " $REPOSITORY_FILTER " in
            *" $name "*) ;;
            *) continue ;;
        esac
    elif [ "$swift_version" != "$ACTUAL_SWIFT_VERSION" ]; then
        echo "==> $name requires Swift $swift_version; deferred to its compatible job"
        continue
    fi
    if [ "$swift_version" != "$ACTUAL_SWIFT_VERSION" ] && [ "${ECOSYSTEM_ALLOW_TOOLCHAIN_MISMATCH:-0}" != "1" ]; then
        echo "$name requires Swift $swift_version; found ${ACTUAL_SWIFT_VERSION:-unknown}." >&2
        exit 1
    fi
    source_repository="$repository"
    if [ -n "$MIRROR_ROOT" ] && [ -d "$MIRROR_ROOT/$name/.git" ]; then
        source_repository="$MIRROR_ROOT/$name"
    fi
    checkout="$CHECKOUT_ROOT/checkouts/$name"
    echo "==> $name @ $revision ($adoption)"
    git clone --quiet --no-checkout "$source_repository" "$checkout"
    git -C "$checkout" checkout --quiet --detach "$revision"
    actual="$(git -C "$checkout" rev-parse HEAD^{commit})"
    if [ "$actual" != "$revision" ]; then
        echo "$name resolved $actual instead of $revision" >&2
        exit 1
    fi
    if [ -n "$(git -C "$checkout" status --porcelain)" ]; then
        echo "$name checkout is not clean at $revision" >&2
        exit 1
    fi
    if [ "$name" = "LR-Parsing" ] && [ -n "$MIRROR_ROOT" ] && [ -d "$MIRROR_ROOT/Lexer/.git" ]; then
        swift package --package-path "$checkout" config set-mirror \
            --original https://github.com/hakkabon/Lexer.git \
            --mirror "file://$MIRROR_ROOT/Lexer"
    fi
    swift test --package-path "$checkout" --scratch-path "$CHECKOUT_ROOT/build/$name"
    if [ "$name" = "LR-Parsing" ] && [ "$adoption" = "conformance" ]; then
        swift build --package-path "$checkout" --scratch-path "$CHECKOUT_ROOT/build/$name" --product lr-conformance
        lr_bin_dir="$(swift build --package-path "$checkout" --scratch-path "$CHECKOUT_ROOT/build/$name" --show-bin-path)"
        LR_ADAPTER="$lr_bin_dir/lr-conformance"
    fi
    if [ "$name" = "Compiler" ] && [ "$adoption" = "conformance" ]; then
        swift build --package-path "$checkout" --scratch-path "$CHECKOUT_ROOT/build/$name" --product compiler-conformance
        compiler_bin_dir="$(swift build --package-path "$checkout" --scratch-path "$CHECKOUT_ROOT/build/$name" --show-bin-path)"
        COMPILER_ADAPTER="$compiler_bin_dir/compiler-conformance"
    fi
    if [ "$name" = "Grammar-REPL" ] && [ "$adoption" = "conformance" ]; then
        swift build --package-path "$checkout" --scratch-path "$CHECKOUT_ROOT/build/$name" --product grammar-repl-conformance
        grammar_repl_bin_dir="$(swift build --package-path "$checkout" --scratch-path "$CHECKOUT_ROOT/build/$name" --show-bin-path)"
        GRAMMAR_REPL_ADAPTER="$grammar_repl_bin_dir/grammar-repl-conformance"
    fi
done < "$REPOSITORY_ROWS"

validation_arguments=()
if [ "$SKIP_WORKBENCH" != "1" ]; then
    if [ "$ACTUAL_SWIFT_VERSION" != "$MANIFEST_SWIFT_VERSION" ] && [ "${ECOSYSTEM_ALLOW_TOOLCHAIN_MISMATCH:-0}" != "1" ]; then
        echo "Workbench conformance requires Swift $MANIFEST_SWIFT_VERSION; found ${ACTUAL_SWIFT_VERSION:-unknown}." >&2
        exit 1
    fi
    WORKBENCH_SCRATCH="$CHECKOUT_ROOT/build/Grammar-Workbench"
    swift build --package-path "$ROOT_DIR" --scratch-path "$WORKBENCH_SCRATCH" -c release --product grammar-workbench
    BIN_DIR="$(swift build --package-path "$ROOT_DIR" --scratch-path "$WORKBENCH_SCRATCH" -c release --show-bin-path)"
    validation_arguments+=(--cli "$BIN_DIR/grammar-workbench")
fi
if [ -n "$LR_ADAPTER" ]; then
    validation_arguments+=(--lr-adapter "$LR_ADAPTER")
fi
if [ -n "$COMPILER_ADAPTER" ]; then
    validation_arguments+=(--compiler-adapter "$COMPILER_ADAPTER")
fi
if [ -n "$GRAMMAR_REPL_ADAPTER" ]; then
    validation_arguments+=(--grammar-repl-adapter "$GRAMMAR_REPL_ADAPTER")
fi
if [ "${#validation_arguments[@]}" -gt 0 ]; then
    node "$ROOT_DIR/Scripts/validate-ecosystem-contract.mjs" "${validation_arguments[@]}"
fi

if [ -n "$REPORT_PATH" ]; then
    mkdir -p "$(dirname "$REPORT_PATH")"
    node -e '
const fs = require("node:fs");
const crypto = require("node:crypto");
const manifestPath = process.argv[1];
const reportPath = process.argv[2];
const swiftVersion = process.argv[3];
const manifestBytes = fs.readFileSync(manifestPath);
const manifest = JSON.parse(manifestBytes);
const report = {
  schemaVersion: 1,
  contractVersion: manifest.contractVersion,
  manifestSHA256: crypto.createHash("sha256").update(manifestBytes).digest("hex"),
  swiftIntegrationVersion: swiftVersion,
  corpusVersion: manifest.corpus.version,
  repositories: manifest.repositories.map(({name, revision, adoption, swiftVersion}) => ({name, revision, adoption, swiftVersion: swiftVersion ?? manifest.swiftIntegrationVersion})),
  result: "passed"
};
fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + "\n");
' "$MANIFEST" "$REPORT_PATH" "$ACTUAL_SWIFT_VERSION"
    echo "Integration report: $REPORT_PATH"
fi

echo "Pinned ecosystem integration validation passed."

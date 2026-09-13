#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_VERSION="$(node "$ROOT_DIR/Scripts/release-artifacts.mjs" source --print-version)"
VERSION="${VERSION:-$SOURCE_VERSION}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist-linux}"
ARCH="${ARCH:-$(uname -m)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
RELEASE_TAG="${RELEASE_TAG:-}"
RELEASE_REVISION="${RELEASE_REVISION:-}"
RELEASE_REQUIRE_CLEAN="${RELEASE_REQUIRE_CLEAN:-0}"
SWIFT_BUILD_JOBS="${SWIFT_BUILD_JOBS:-2}"

if [ "$(uname -s)" != "Linux" ]; then
    echo "package-linux.sh must run on Linux." >&2
    exit 2
fi
if [ "$VERSION" != "$SOURCE_VERSION" ]; then
    echo "VERSION ($VERSION) must match GrammarWorkbenchRelease.version ($SOURCE_VERSION)." >&2
    exit 2
fi
SOURCE_ARGUMENTS=(source --version "$VERSION")
if [ -n "$RELEASE_TAG" ]; then SOURCE_ARGUMENTS+=(--tag "$RELEASE_TAG"); fi
if [ -n "$RELEASE_REVISION" ]; then SOURCE_ARGUMENTS+=(--revision "$RELEASE_REVISION"); fi
if [ "$RELEASE_REQUIRE_CLEAN" = "1" ]; then
    SOURCE_ARGUMENTS+=(--require-clean)
elif [ "$RELEASE_REQUIRE_CLEAN" != "0" ]; then
    echo "RELEASE_REQUIRE_CLEAN must be 0 or 1." >&2
    exit 2
fi
node "$ROOT_DIR/Scripts/release-artifacts.mjs" "${SOURCE_ARGUMENTS[@]}"
case "$ARCH" in
    x86_64|amd64) ARCHIVE_ARCH="x86_64" ;;
    aarch64|arm64) ARCHIVE_ARCH="arm64" ;;
    *) echo "Unsupported Linux architecture: $ARCH" >&2; exit 2 ;;
esac
case "$SWIFT_BUILD_JOBS" in
    ''|*[!0-9]*|0) echo "SWIFT_BUILD_JOBS must be a positive integer." >&2; exit 2 ;;
esac

mkdir -p "$OUTPUT_DIR"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/grammar-workbench-linux.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
SCRATCH="$WORK_DIR/build"
PACKAGE_NAME="Grammar-Workbench-$VERSION-linux-$ARCHIVE_ARCH"
PACKAGE_DIR="$WORK_DIR/$PACKAGE_NAME"

for PRODUCT in grammar-workbench grammar-workbench-lsp grammar-workbench-service; do
    swift build --package-path "$ROOT_DIR" --scratch-path "$SCRATCH" --force-resolved-versions --jobs "$SWIFT_BUILD_JOBS" -c release --product "$PRODUCT"
done
BIN_DIR="$(swift build --package-path "$ROOT_DIR" --scratch-path "$SCRATCH" --force-resolved-versions -c release --show-bin-path)"

mkdir -p "$PACKAGE_DIR/bin"
for BINARY in grammar-workbench grammar-workbench-lsp grammar-workbench-service; do
    install -m 755 "$BIN_DIR/$BINARY" "$PACKAGE_DIR/bin/$BINARY"
done
for RESOURCE in "$BIN_DIR"/GrammarWorkbench_GrammarWorkbench.resources "$BIN_DIR"/GrammarWorkbench_GrammarWorkbench.bundle; do
    if [ -d "$RESOURCE" ]; then cp -R "$RESOURCE" "$PACKAGE_DIR/bin/"; fi
done
cp "$ROOT_DIR/LICENSE" "$PACKAGE_DIR/LICENSE.txt"
cp "$ROOT_DIR/LocalDependencies/LICENSE.txt" "$PACKAGE_DIR/THIRD-PARTY-LICENSE.txt"
cp "$ROOT_DIR/Documentation/LinuxDelivery.md" "$PACKAGE_DIR/README.md"
"$PACKAGE_DIR/bin/grammar-workbench" platform-info "$PACKAGE_DIR/platform.json"

ARCHIVE="$OUTPUT_DIR/$PACKAGE_NAME.tar.gz"
tar -C "$WORK_DIR" -czf "$ARCHIVE" "$PACKAGE_NAME"
tar -tzf "$ARCHIVE" >/dev/null
RESEARCH_NAME="Grammar-Workbench-Research-$VERSION"
RESEARCH_DIR="$WORK_DIR/$RESEARCH_NAME"
"$PACKAGE_DIR/bin/grammar-workbench" research-package \
    "$ROOT_DIR/Examples/ResearchValidationProgramme.json" \
    "$ROOT_DIR/Packaging/EcosystemCompatibility.json" \
    "$ROOT_DIR/LICENSE" "$RESEARCH_DIR"
"$PACKAGE_DIR/bin/grammar-workbench" research-package-verify "$RESEARCH_DIR"
RESEARCH_ARCHIVE="$OUTPUT_DIR/$RESEARCH_NAME.tar.gz"
tar -C "$WORK_DIR" -czf "$RESEARCH_ARCHIVE" "$RESEARCH_NAME"
tar -tzf "$RESEARCH_ARCHIVE" >/dev/null
CHECKSUMS="$(basename "$ARCHIVE").sha256"
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$ARCHIVE")" "$(basename "$RESEARCH_ARCHIVE")" > "$CHECKSUMS")
MANIFEST_NAME="$PACKAGE_NAME-manifest.json"
MANIFEST_ARGUMENTS=(
    create --directory "$OUTPUT_DIR" --output "$MANIFEST_NAME"
    --version "$VERSION" --build "$BUILD_NUMBER" --platform linux
    --architectures "$ARCHIVE_ARCH" --checksums "$CHECKSUMS"
    --artifact "$(basename "$ARCHIVE")" --artifact "$(basename "$RESEARCH_ARCHIVE")"
)
if [ -n "$RELEASE_TAG" ]; then MANIFEST_ARGUMENTS+=(--tag "$RELEASE_TAG"); fi
if [ -n "$RELEASE_REVISION" ]; then MANIFEST_ARGUMENTS+=(--revision "$RELEASE_REVISION"); fi
if [ "$RELEASE_REQUIRE_CLEAN" = "1" ]; then MANIFEST_ARGUMENTS+=(--require-clean); fi
node "$ROOT_DIR/Scripts/release-artifacts.mjs" "${MANIFEST_ARGUMENTS[@]}"
node "$ROOT_DIR/Scripts/release-artifacts.mjs" verify \
    --manifest "$OUTPUT_DIR/$MANIFEST_NAME"

echo "Created $ARCHIVE"
echo "Created $RESEARCH_ARCHIVE"
echo "Created $OUTPUT_DIR/$CHECKSUMS"
echo "Created $OUTPUT_DIR/$MANIFEST_NAME"
echo "Created $OUTPUT_DIR/$MANIFEST_NAME.sha256"

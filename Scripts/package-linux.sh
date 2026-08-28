#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_VERSION="$(sed -n 's/.*public static let version = "\([0-9.]*\)".*/\1/p' "$ROOT_DIR/Sources/GrammarWorkbench/ProductionSupport.swift")"
VERSION="${VERSION:-$SOURCE_VERSION}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist-linux}"
ARCH="${ARCH:-$(uname -m)}"

if [ "$(uname -s)" != "Linux" ]; then
    echo "package-linux.sh must run on Linux." >&2
    exit 2
fi
if [ "$VERSION" != "$SOURCE_VERSION" ]; then
    echo "VERSION ($VERSION) must match GrammarWorkbenchRelease.version ($SOURCE_VERSION)." >&2
    exit 2
fi
case "$ARCH" in
    x86_64|amd64) ARCHIVE_ARCH="x86_64" ;;
    aarch64|arm64) ARCHIVE_ARCH="arm64" ;;
    *) echo "Unsupported Linux architecture: $ARCH" >&2; exit 2 ;;
esac

mkdir -p "$OUTPUT_DIR"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/grammar-workbench-linux.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
SCRATCH="$WORK_DIR/build"
PACKAGE_NAME="Grammar-Workbench-$VERSION-linux-$ARCHIVE_ARCH"
PACKAGE_DIR="$WORK_DIR/$PACKAGE_NAME"

for PRODUCT in grammar-workbench grammar-workbench-lsp grammar-workbench-service; do
    swift build --package-path "$ROOT_DIR" --scratch-path "$SCRATCH" -c release --product "$PRODUCT"
done
BIN_DIR="$(swift build --package-path "$ROOT_DIR" --scratch-path "$SCRATCH" -c release --show-bin-path)"

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
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")

echo "Created $ARCHIVE"
echo "Created $ARCHIVE.sha256"

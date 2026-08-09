#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_VERSION="$(sed -n 's/.*public static let version = "\([0-9.]*\)".*/\1/p' "$ROOT_DIR/Sources/GrammarWorkbench/ProductionSupport.swift")"
VERSION="${VERSION:-$SOURCE_VERSION}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.grammar-workbench.app}"
ARCHS="${ARCHS:-$(uname -m)}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APP_ICON="${APP_ICON:-$ROOT_DIR/Packaging/AppIcon.icns}"
APP_NAME="Grammar Workbench.app"
APP_PATH="$OUTPUT_DIR/$APP_NAME"

case "$VERSION" in
    *[!0-9.]*|"") echo "VERSION must contain only digits and periods." >&2; exit 2 ;;
esac
if [ "$VERSION" != "$SOURCE_VERSION" ]; then
    echo "VERSION ($VERSION) must match GrammarWorkbenchRelease.version ($SOURCE_VERSION)." >&2
    exit 2
fi
case "$BUILD_NUMBER" in
    *[!0-9]*|"") echo "BUILD_NUMBER must be numeric." >&2; exit 2 ;;
esac

mkdir -p "$OUTPUT_DIR"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/grammar-workbench-release.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

APP_BINARIES=()
CLI_BINARIES=()
LSP_BINARIES=()
RESOURCE_BUNDLE=""
for ARCH in $ARCHS; do
    SCRATCH="$WORK_DIR/build-$ARCH"
    swift build --package-path "$ROOT_DIR" --scratch-path "$SCRATCH" -c release --arch "$ARCH" --product GrammarWorkbenchApp
    swift build --package-path "$ROOT_DIR" --scratch-path "$SCRATCH" -c release --arch "$ARCH" --product grammar-workbench
    swift build --package-path "$ROOT_DIR" --scratch-path "$SCRATCH" -c release --arch "$ARCH" --product grammar-workbench-lsp
    BIN_DIR="$(swift build --package-path "$ROOT_DIR" --scratch-path "$SCRATCH" -c release --arch "$ARCH" --show-bin-path)"
    APP_BINARIES+=("$BIN_DIR/GrammarWorkbenchApp")
    CLI_BINARIES+=("$BIN_DIR/grammar-workbench")
    LSP_BINARIES+=("$BIN_DIR/grammar-workbench-lsp")
    if [ -z "$RESOURCE_BUNDLE" ] && [ -d "$BIN_DIR/GrammarWorkbench_GrammarWorkbench.bundle" ]; then
        RESOURCE_BUNDLE="$BIN_DIR/GrammarWorkbench_GrammarWorkbench.bundle"
    fi
done

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
if [ "${#APP_BINARIES[@]}" -eq 1 ]; then
    cp "${APP_BINARIES[0]}" "$APP_PATH/Contents/MacOS/GrammarWorkbenchApp"
    cp "${CLI_BINARIES[0]}" "$OUTPUT_DIR/grammar-workbench"
    cp "${LSP_BINARIES[0]}" "$OUTPUT_DIR/grammar-workbench-lsp"
else
    lipo -create "${APP_BINARIES[@]}" -output "$APP_PATH/Contents/MacOS/GrammarWorkbenchApp"
    lipo -create "${CLI_BINARIES[@]}" -output "$OUTPUT_DIR/grammar-workbench"
    lipo -create "${LSP_BINARIES[@]}" -output "$OUTPUT_DIR/grammar-workbench-lsp"
fi
chmod 755 "$APP_PATH/Contents/MacOS/GrammarWorkbenchApp" "$OUTPUT_DIR/grammar-workbench" "$OUTPUT_DIR/grammar-workbench-lsp"

sed -e "s/@VERSION@/$VERSION/g" \
    -e "s/@BUILD_NUMBER@/$BUILD_NUMBER/g" \
    -e "s/@BUNDLE_IDENTIFIER@/$BUNDLE_IDENTIFIER/g" \
    "$ROOT_DIR/Packaging/Info.plist" > "$APP_PATH/Contents/Info.plist"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"
cp "$ROOT_DIR/LICENSE" "$APP_PATH/Contents/Resources/LICENSE.txt"
if [ -n "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_PATH/"
    cp "$RESOURCE_BUNDLE/PrivacyInfo.xcprivacy" "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
fi
if [ -f "$APP_ICON" ]; then
    cp "$APP_ICON" "$APP_PATH/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_PATH/Contents/Info.plist"
fi

plutil -lint "$APP_PATH/Contents/Info.plist" "$ROOT_DIR/Packaging/GrammarWorkbench.entitlements"
if [ -n "$SIGNING_IDENTITY" ]; then
    codesign --force --timestamp --options runtime --entitlements "$ROOT_DIR/Packaging/GrammarWorkbench.entitlements" --sign "$SIGNING_IDENTITY" "$APP_PATH"
    codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$OUTPUT_DIR/grammar-workbench"
    codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$OUTPUT_DIR/grammar-workbench-lsp"
else
    echo "Packaging unsigned build; set SIGNING_IDENTITY for Developer ID distribution."
fi

ZIP_PATH="$OUTPUT_DIR/Grammar-Workbench-$VERSION-macOS.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
CLI_ZIP="$OUTPUT_DIR/Grammar-Workbench-CLI-$VERSION-macOS.zip"
rm -f "$CLI_ZIP"
ditto -c -k "$OUTPUT_DIR/grammar-workbench" "$CLI_ZIP"
LSP_ZIP="$OUTPUT_DIR/Grammar-Workbench-LSP-$VERSION-macOS.zip"
rm -f "$LSP_ZIP"
ditto -c -k "$OUTPUT_DIR/grammar-workbench-lsp" "$LSP_ZIP"

VSIX_PATH="$OUTPUT_DIR/grammar-workbench-lsp-$VERSION.vsix"
if command -v npx >/dev/null 2>&1; then
    rm -f "$VSIX_PATH"
    (cd "$ROOT_DIR/Clients/vscode" && npx --yes @vscode/vsce package \
        --allow-missing-repository --out "$VSIX_PATH" >/dev/null)
    echo "Created $VSIX_PATH"
else
    echo "npx not found; skipping the VS Code extension package."
    VSIX_PATH=""
fi
LSP_PACKAGE="$WORK_DIR/Grammar-Workbench-LSP-$VERSION"
mkdir -p "$LSP_PACKAGE"
cp "$OUTPUT_DIR/grammar-workbench-lsp" "$LSP_PACKAGE/"
cp "$ROOT_DIR/LICENSE" "$LSP_PACKAGE/LICENSE.txt"
cp "$ROOT_DIR/LocalDependencies/LICENSE.txt" "$LSP_PACKAGE/THIRD-PARTY-LICENSE.txt"
cp "$ROOT_DIR/Documentation/Ecosystem.md" "$LSP_PACKAGE/README.md"
ditto -c -k --keepParent "$LSP_PACKAGE" "$LSP_ZIP"
CLIENTS_ZIP="$OUTPUT_DIR/Grammar-Workbench-Editor-Clients-$VERSION.zip"
rm -f "$CLIENTS_ZIP"
CLIENTS_PACKAGE="$WORK_DIR/Grammar-Workbench-Editor-Clients-$VERSION"
cp -R "$ROOT_DIR/Clients" "$CLIENTS_PACKAGE"
cp "$ROOT_DIR/LICENSE" "$CLIENTS_PACKAGE/GRAMMAR-WORKBENCH-LICENSE.txt"
ditto -c -k --keepParent "$CLIENTS_PACKAGE" "$CLIENTS_ZIP"

if [ -n "$NOTARY_PROFILE" ]; then
    if [ -z "$SIGNING_IDENTITY" ]; then echo "NOTARY_PROFILE requires SIGNING_IDENTITY." >&2; exit 2; fi
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_PATH"
    rm -f "$ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
fi

BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" "$ROOT_DIR/Scripts/validate-release.sh" "$APP_PATH" "$OUTPUT_DIR/grammar-workbench" "$OUTPUT_DIR/grammar-workbench-lsp"
"$ROOT_DIR/Scripts/smoke-release.sh" "$OUTPUT_DIR/grammar-workbench"
"$ROOT_DIR/Scripts/smoke-lsp.sh" "$OUTPUT_DIR/grammar-workbench-lsp"
if [ -n "$VSIX_PATH" ]; then
    (cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$CLI_ZIP")" "$(basename "$LSP_ZIP")" "$(basename "$VSIX_PATH")" > SHA256SUMS)
else
    (cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$CLI_ZIP")" "$(basename "$LSP_ZIP")" > SHA256SUMS)
fi
echo "Created $ZIP_PATH"
echo "Created $CLI_ZIP"
echo "Created $LSP_ZIP"
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$CLI_ZIP")" "$(basename "$LSP_ZIP")" "$(basename "$CLIENTS_ZIP")" > SHA256SUMS)
echo "Created $ZIP_PATH"
echo "Created $CLI_ZIP"
echo "Created $LSP_ZIP"
echo "Created $CLIENTS_ZIP"
echo "Created $OUTPUT_DIR/SHA256SUMS"

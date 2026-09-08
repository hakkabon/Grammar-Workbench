#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ] && [ "$#" -ne 4 ]; then
    echo "usage: validate-release.sh APP_PATH CLI_PATH [LSP_PATH SERVICE_PATH]" >&2
    exit 2
fi
APP_PATH="$1"
CLI_PATH="$2"
LSP_PATH="${3:-}"
SERVICE_PATH="${4:-}"
PLIST="$APP_PATH/Contents/Info.plist"
EXPECTED_BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.grammar-workbench.app}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"
EXPECTED_BUILD_NUMBER="${EXPECTED_BUILD_NUMBER:-}"
EXPECTED_ARCHS="${EXPECTED_ARCHS:-}"
REQUIRE_SIGNED_RELEASE="${REQUIRE_SIGNED_RELEASE:-0}"
REQUIRE_NOTARIZED_RELEASE="${REQUIRE_NOTARIZED_RELEASE:-0}"

case "$REQUIRE_SIGNED_RELEASE:$REQUIRE_NOTARIZED_RELEASE" in
    0:0|1:0|1:1) ;;
    *) echo "Signing and notarization requirements are inconsistent." >&2; exit 2 ;;
esac

test -x "$APP_PATH/Contents/MacOS/GrammarWorkbenchApp"
test -x "$CLI_PATH"
if [ -n "$LSP_PATH" ]; then test -x "$LSP_PATH"; test -x "$SERVICE_PATH"; fi
test -s "$APP_PATH/Contents/Resources/LICENSE.txt"
test -s "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
plutil -lint "$PLIST" "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$PLIST")" = "APPL"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")" = "14.0"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" = "$EXPECTED_BUNDLE_IDENTIFIER"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
CLI_VERSION="$($CLI_PATH --version | awk '{print $2}')"
test "$APP_VERSION" = "$CLI_VERSION"
if [ -n "$EXPECTED_VERSION" ]; then test "$APP_VERSION" = "$EXPECTED_VERSION"; fi
if [ -n "$EXPECTED_BUILD_NUMBER" ]; then test "$APP_BUILD" = "$EXPECTED_BUILD_NUMBER"; fi

BINARIES=("$APP_PATH/Contents/MacOS/GrammarWorkbenchApp" "$CLI_PATH")
if [ -n "$LSP_PATH" ]; then BINARIES+=("$LSP_PATH" "$SERVICE_PATH"); fi
for BINARY in "${BINARIES[@]}"; do
    /usr/bin/lipo -info "$BINARY" >/dev/null
    if [ -n "$EXPECTED_ARCHS" ]; then
        ACTUAL_ARCHS="$(/usr/bin/lipo -archs "$BINARY" | tr ' ' '\n' | sort | xargs)"
        NORMALIZED_EXPECTED_ARCHS="$(printf '%s\n' $EXPECTED_ARCHS | sort | xargs)"
        test "$ACTUAL_ARCHS" = "$NORMALIZED_EXPECTED_ARCHS"
    fi
done
"$CLI_PATH" --help >/dev/null

if [ "$REQUIRE_SIGNED_RELEASE" = "1" ]; then
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    for BINARY in "${BINARIES[@]:1}"; do
        codesign --verify --strict --verbose=2 "$BINARY"
    done
elif codesign -dv "$APP_PATH" >/dev/null 2>&1; then
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
fi
if [ "$REQUIRE_NOTARIZED_RELEASE" = "1" ]; then
    xcrun stapler validate "$APP_PATH"
fi
echo "Release validation passed."

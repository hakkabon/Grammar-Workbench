#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ] && [ "$#" -ne 3 ]; then
    echo "usage: validate-release.sh APP_PATH CLI_PATH [LSP_PATH]" >&2
    exit 2
fi
APP_PATH="$1"
CLI_PATH="$2"
LSP_PATH="${3:-}"
PLIST="$APP_PATH/Contents/Info.plist"

test -x "$APP_PATH/Contents/MacOS/GrammarWorkbenchApp"
test -x "$CLI_PATH"
plutil -lint "$PLIST"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$PLIST")" = "APPL"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")" = "14.0"
"$CLI_PATH" --version
"$CLI_PATH" --help >/dev/null
if [ -n "$LSP_PATH" ]; then
    test -x "$LSP_PATH"
fi

if codesign -dv "$APP_PATH" >/dev/null 2>&1; then
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
fi
echo "Release validation passed."

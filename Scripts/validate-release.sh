#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: validate-release.sh APP_PATH CLI_PATH" >&2
    exit 2
fi
APP_PATH="$1"
CLI_PATH="$2"
PLIST="$APP_PATH/Contents/Info.plist"

test -x "$APP_PATH/Contents/MacOS/GrammarWorkbenchApp"
test -x "$CLI_PATH"
plutil -lint "$PLIST"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$PLIST")" = "APPL"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")" = "14.0"
"$CLI_PATH" --version
"$CLI_PATH" --help >/dev/null

if codesign -dv "$APP_PATH" >/dev/null 2>&1; then
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
fi
echo "Release validation passed."

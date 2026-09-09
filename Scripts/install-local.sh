#!/bin/bash
# Installs the locally built Release app (make build → build/) into
# /Applications, replacing any running copy. Part of `make install`.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO_ROOT/build/Build/Products/Release/Keelhaven.app"

if [[ ! -d "$APP" ]]; then
    echo "No built app at $APP — run 'make build' first." >&2
    exit 1
fi

pkill -x Keelhaven 2>/dev/null && sleep 1 || true
rm -rf /Applications/Keelhaven.app
ditto "$APP" /Applications/Keelhaven.app
open /Applications/Keelhaven.app

PLIST=/Applications/Keelhaven.app/Contents/Info.plist
COMMIT=$(/usr/libexec/PlistBuddy -c 'Print :GitCommit' "$PLIST" 2>/dev/null || echo "?")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null || echo "?")
echo "Installed LOCAL build $BUILD ($COMMIT) — not a CI artifact."

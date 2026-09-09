#!/bin/bash
# Packages a built Keelhaven.app into a drag-to-Applications .dmg for
# distribution outside the Mac App Store (issue #63). Works on any built
# app — ad-hoc-signed builds included, which is what public releases ship
# until the optional Apple signing secrets exist (docs/RELEASING.md).
#
# Usage: make-dmg.sh [path-to-Keelhaven.app] [output.dmg]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$REPO_ROOT/build/Build/Products/Release/Keelhaven.app}"
OUT="${2:-$REPO_ROOT/Keelhaven.dmg}"

if [[ ! -d "$APP" ]]; then
    echo "No app bundle at $APP — build one first (make build)." >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

# ditto (not cp -R) preserves the code signature — a plain copy can strip
# extended attributes the signature depends on.
ditto "$APP" "$STAGING/Keelhaven.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$OUT"
hdiutil create \
    -volname "Keelhaven $VERSION" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -ov -format UDZO \
    "$OUT"

echo "Created $OUT (Keelhaven $VERSION)"

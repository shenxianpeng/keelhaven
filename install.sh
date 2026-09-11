#!/bin/bash
# Keelhaven installer — https://keelhaven.app
#
#   curl -fsSL https://keelhaven.app/install.sh | bash
#
# Downloads the latest release DMG, copies Keelhaven.app into /Applications,
# and launches it. Prefer Homebrew? The cask does the same with upgrades:
#
#   brew install --cask shenxianpeng/tap/keelhaven
#
# The script needs nothing beyond what ships with macOS, touches only
# /Applications/Keelhaven.app, and can be re-run any time to update.
set -euo pipefail

REPO="shenxianpeng/keelhaven"
MANIFEST="https://keelhaven.app/latest.json"

fail() { echo "Error: $*" >&2; exit 1; }

[[ "$(uname -s)" = "Darwin" ]] || fail "Keelhaven is a macOS app — this installer only runs on a Mac."

TMP=$(mktemp -d /tmp/keelhaven-install.XXXXXX)
MOUNT=""
cleanup() {
    [[ -n "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet 2>/dev/null
    rm -rf "$TMP"
}
trap cleanup EXIT

# The site mirrors each release's DMG next to a small manifest. Read the
# manifest for the download URL; if the site is unreachable fall back to
# the GitHub release the mirror was made from. Every fetch pins the scheme
# with --proto "=https", so a redirect can't quietly downgrade the transfer
# to plain HTTP and hand the installer a rewritten DMG.
DMG_URL=$(curl --proto "=https" -fsSL "$MANIFEST" 2>/dev/null \
    | sed -n 's/.*"dmgURL": *"\([^"]*\)".*/\1/p' || true)
if [[ -z "$DMG_URL" ]]; then
    DMG_URL=$(curl --proto "=https" -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | sed -n 's/.*"browser_download_url": *"\([^"]*\.dmg\)".*/\1/p' | head -1) \
        || true
fi
[[ -n "$DMG_URL" ]] || fail "could not find the latest release. Download it from https://keelhaven.app instead."

echo "Downloading ${DMG_URL##*/}..."
curl --proto "=https" -fL --progress-bar "$DMG_URL" -o "$TMP/Keelhaven.dmg"

MOUNT=$(hdiutil attach "$TMP/Keelhaven.dmg" -nobrowse -readonly \
    | sed -n 's/.*\(\/Volumes\/.*\)/\1/p' | tail -1)
[[ -n "$MOUNT" ]] && [[ -d "$MOUNT/Keelhaven.app" ]] || fail "the DMG did not contain Keelhaven.app."

echo "Installing to /Applications..."
# A running menu-bar app would keep files busy while we replace them.
pkill -x Keelhaven 2>/dev/null && sleep 1 || true
rm -rf /Applications/Keelhaven.app
ditto "$MOUNT/Keelhaven.app" /Applications/Keelhaven.app
hdiutil detach "$MOUNT" -quiet
MOUNT=""

# Beta builds are unnotarised; a curl download is quarantined just like a
# browser download. Clearing the flag here is the terminal equivalent of the
# one-time approval the site FAQ walks through.
xattr -dr com.apple.quarantine /Applications/Keelhaven.app 2>/dev/null || true

open /Applications/Keelhaven.app
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    /Applications/Keelhaven.app/Contents/Info.plist 2>/dev/null || echo "?")
echo "Done: Keelhaven $VERSION is running in your menu bar."

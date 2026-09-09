#!/bin/bash
# Bumps Casks/keelhaven.rb in shenxianpeng/homebrew-tap to a just-released
# version, so `brew install --cask shenxianpeng/tap/keelhaven` serves the newest
# DMG. Two callers: release.yml (authenticates with the HOMEBREW_TAP_TOKEN
# secret — a fine-grained PAT with contents: write on the tap repo) and
# release-local.sh (your normal git credentials). Idempotent: re-running for
# the version the tap already carries is a no-op, so the two release paths
# can't fight each other.
#
# Usage: update-homebrew-tap.sh <version> <dmg-path>
set -euo pipefail

VERSION="${1:-}"
DMG="${2:-}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! -f "$DMG" ]]; then
    echo "Usage: update-homebrew-tap.sh <version> <dmg-path>" >&2
    exit 1
fi

SHA256=$(shasum -a 256 "$DMG" | awk '{print $1}')

# The token rides in the remote URL; GitHub Actions masks the secret in logs.
REMOTE="https://github.com/shenxianpeng/homebrew-tap.git"
if [[ -n "${HOMEBREW_TAP_TOKEN:-}" ]]; then
    REMOTE="https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/shenxianpeng/homebrew-tap.git"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git clone -q --depth 1 "$REMOTE" "$TMP/tap"

CASK="$TMP/tap/Casks/keelhaven.rb"
sed -i '' -E \
    -e "s|^  version \".*\"|  version \"$VERSION\"|" \
    -e "s|^  sha256 \".*\"|  sha256 \"$SHA256\"|" \
    "$CASK"
# sed matched nothing? Fail here, not with a broken cask on the tap.
grep -q "version \"$VERSION\"" "$CASK"
grep -q "sha256 \"$SHA256\"" "$CASK"

if git -C "$TMP/tap" diff --quiet; then
    echo "Tap already at keelhaven $VERSION — nothing to push."
    exit 0
fi

# CI runners have no git identity; local runs keep yours.
if ! git -C "$TMP/tap" config user.email >/dev/null; then
    git -C "$TMP/tap" config user.name "github-actions[bot]"
    git -C "$TMP/tap" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
fi
git -C "$TMP/tap" commit -aqm "keelhaven $VERSION"
git -C "$TMP/tap" push -q origin HEAD:main
echo "Tap bumped to keelhaven $VERSION."

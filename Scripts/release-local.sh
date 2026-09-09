#!/bin/bash
# Manual twin of .github/workflows/release.yml — cuts a public release
# entirely from this Mac, for when Actions minutes are exhausted (the same
# situation Scripts/deploy-site.sh exists for). Produces what the workflow's
# no-secrets path would: an ad-hoc-signed universal Keelhaven-<version>.dmg
# attached to a GitHub Release with the first-launch note, then mirrored to
# https://keelhaven.app/downloads/ with latest.json — which is what flips
# the site's download button and the in-app update prompt on.
#
# Unlike the workflow, this also runs the core tests first: with no Actions
# quota the PR gate never ran, so this is the only gate left.
#
# Usage: release-local.sh <version>        e.g. release-local.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: release-local.sh <version>   e.g. release-local.sh 0.2.0" >&2
    exit 1
fi
TAG="v$VERSION"

command -v gh >/dev/null || { echo "Needs the GitHub CLI: brew install gh" >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "Needs XcodeGen: brew install xcodegen" >&2; exit 1; }

# A release must be rebuildable from its tag — refuse uncommitted work.
if ! git diff-index --quiet HEAD --; then
    echo "Working tree has uncommitted changes — commit or stash first." >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Tag $TAG already exists." >&2
    exit 1
fi
branch=$(git branch --show-current)
if [[ "$branch" != "main" ]]; then
    echo "⚠️  Releasing '$branch', not main."
fi

echo "Running core tests..."
swift test --package-path KeelhavenCore

echo "Building Keelhaven $VERSION (universal, ad-hoc signed)..."
./Scripts/fetch-restic.sh universal
xcodegen generate
# Same build settings as the workflow's no-secrets path: identity "-" is
# ad-hoc (arm64 refuses entirely unsigned binaries). The build number is the
# commit count — there is no CI run number locally, and this stays monotonic.
xcodebuild \
    -project Keelhaven.xcodeproj \
    -scheme Keelhaven \
    -configuration Release \
    -derivedDataPath build \
    -quiet \
    build \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO

DMG="Keelhaven-$VERSION.dmg"
./Scripts/make-dmg.sh build/Build/Products/Release/Keelhaven.app "$DMG"

echo "Tagging $TAG and publishing the release..."
git tag "$TAG"
# While Actions has no quota, this tag push and the release-published event
# below each leave a not-started run behind — harmless, but silence them with
#   gh workflow disable release.yml && gh workflow disable website.yml
# until quota returns (gh workflow enable ... to undo).
git push origin "$TAG"
# --notes-file is prepended to the generated notes, matching the workflow's
# body_path + generate_release_notes combination.
gh release create "$TAG" "$DMG" \
    --verify-tag \
    --title "$TAG" \
    --notes-file Scripts/first-launch-note.md \
    --generate-notes

echo "Bumping the Homebrew tap..."
./Scripts/update-homebrew-tap.sh "$VERSION" "$DMG"

echo "Mirroring the DMG into the site deploy..."
./Scripts/deploy-site.sh

echo "Released: https://github.com/shenxianpeng/keelhaven/releases/tag/$TAG"
echo "Download: https://keelhaven.app/downloads/$DMG (Pages rebuild takes ~1 min)"

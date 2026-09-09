#!/bin/bash
# Builds site/ from the current working tree and force-pushes the static
# output to this repo's gh-pages branch — which GitHub Pages serves at
# https://keelhaven.app/ (the custom domain rides along in the build
# output as site/public/CNAME; see docs/WEBSITE.md).
#
# This is the manual twin of .github/workflows/website.yml (same output,
# same branch); use it when Actions is unavailable. The workflow
# force-pushes too, so the next CI deploy simply overwrites this one.
set -euo pipefail
cd "$(dirname "$0")/.."

branch=$(git branch --show-current)
if [ "$branch" != "main" ]; then
  echo "⚠️  Deploying the working tree of '$branch', not main."
fi

# Manual twin of website.yml's mirror step. The force-push below replaces
# gh-pages wholesale, so *every* deploy must re-mirror the newest release
# DMG and latest.json, or the live download link dies with this push —
# which is also why a missing gh is a hard stop, not a skipped step.
command -v gh >/dev/null || {
  echo "Needs the GitHub CLI (brew install gh) — refusing to deploy without the DMG mirror." >&2
  exit 1
}
rm -rf site/public/downloads site/public/latest.json
mkdir -p site/public/downloads
if info=$(gh release view --repo shenxianpeng/keelhaven --json tagName,assets \
    --jq '"\(.tagName)\t\([.assets[] | select(.name | endswith(".dmg"))][0].name // "")"' 2>/dev/null); then
  tag=${info%%$'\t'*}
  asset=${info#*$'\t'}
  if [ -n "$asset" ]; then
    echo "Mirroring $asset ($tag) into the deploy."
    gh release download "$tag" --repo shenxianpeng/keelhaven --pattern '*.dmg' --dir site/public/downloads --clobber
    printf '{"version": "%s", "dmgURL": "https://keelhaven.app/downloads/%s"}\n' \
      "${tag#v}" "$asset" > site/public/latest.json
  else
    echo "Latest release $tag has no .dmg asset — deploying without a DMG mirror."
  fi
else
  echo "No published release found (or gh isn't authenticated) — deploying without a DMG mirror."
fi

npm --prefix site ci --ignore-scripts
npm --prefix site run build

dist="site/.vitepress/dist"
# Pages runs Jekyll by default, which drops VitePress's underscore-prefixed
# asset paths — .nojekyll turns that off.
touch "$dist/.nojekyll"

git -C "$dist" init -q -b gh-pages
git -C "$dist" add -A
git -C "$dist" commit -q -m "Manual deploy from $branch @ $(git rev-parse --short HEAD)"
git -C "$dist" push -q --force https://github.com/shenxianpeng/keelhaven.git gh-pages
rm -rf "$dist/.git"

echo "Deployed → https://keelhaven.app/ (Pages rebuild takes ~1 min)"

#!/bin/bash
# Prints the numbers a launch is judged by, from the one place that counts
# them without a tracker: GitHub. Stars, release downloads, and the last 14
# days of repository traffic with where it came from.
#
# Two things to know when reading it:
#
# - Release downloads are mostly `brew install` (the cask points at the release
#   asset). The website's Download button serves its own mirror of the DMG, so
#   it is not in this count — Google Analytics has that one. The deploy that
#   makes the mirror fetches the DMG from the release too, so a site deploy
#   may show up here as a download.
# - GitHub keeps traffic for 14 days and then drops it. Around a launch, run
#   this at least that often and keep what it prints:
#
#     make metrics >> ~/keelhaven-metrics.log
#
# The website's side — visits, DMG downloads, install-command copies, and the
# campaign each came from — is in docs/WEBSITE.md § "Measuring a launch".
#
# Usage: metrics.sh
set -euo pipefail

REPO="shenxianpeng/keelhaven"

command -v gh >/dev/null || { echo "Error: needs the GitHub CLI — brew install gh" >&2; exit 1; }

echo "Keelhaven — $(date +%Y-%m-%d)"
gh api "repos/$REPO" --jq '"Stars \(.stargazers_count) · Forks \(.forks_count) · Open issues and PRs \(.open_issues_count)"'

echo
echo "Release downloads"
gh api "repos/$REPO/releases" --paginate \
    --jq '.[] | "\(.tag_name)\t\([.assets[].download_count] | add // 0)"' \
    | awk -F'\t' '{ printf "  %-9s %5d\n", $1, $2; total += $2 } END { printf "  %-9s %5d\n", "total", total }'

# Traffic is only readable with push access to the repository; say so rather
# than stop, since everything above is public and already printed.
echo
if ! VIEWS=$(gh api "repos/$REPO/traffic/views" --jq '"\(.count) views from \(.uniques) visitors"' 2>/dev/null); then
    echo "Traffic: not available — it needs push access to $REPO."
    exit 0
fi
CLONES=$(gh api "repos/$REPO/traffic/clones" --jq '"\(.count) clones from \(.uniques) cloners"')
echo "Repository traffic, last 14 days"
echo "  $VIEWS"
echo "  $CLONES"

echo
echo "Where visitors came from (views / visitors)"
gh api "repos/$REPO/traffic/popular/referrers" --jq '.[] | "\(.referrer)\t\(.count)\t\(.uniques)"' \
    | awk -F'\t' '{ printf "  %-28s %5d / %d\n", $1, $2, $3 }'

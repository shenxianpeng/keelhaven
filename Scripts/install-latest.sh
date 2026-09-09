#!/bin/bash
# One-command install/update of the latest build from main:
#   ./Scripts/install-latest.sh
#
# Downloads the newest artifact for this Mac's architecture, replaces
# /Applications/Keelhaven.app, strips the quarantine flag, quits any running
# instance, and launches the new one.
#
# Builds are no longer produced on every push to main — macOS runners bill at
# 10× and two builds per push was the largest single draw on the private-repo
# minutes quota, for artifacts nobody downloaded most of the time. Instead this
# script triggers .github/workflows/build-app.yml on demand and waits for it,
# which takes roughly 3 minutes. When a matching artifact for main's current
# commit already exists it is reused and nothing is billed at all.
#
#   --no-build   install the newest existing artifact even if main has moved on
#   --build      rebuild unconditionally, ignoring any existing artifact
set -euo pipefail

REPO="shenxianpeng/keelhaven"
WORKFLOW="build-app.yml"
MODE=auto

for arg in "$@"; do
    case "$arg" in
        --no-build) MODE=reuse ;;
        --build|--force-build) MODE=force ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)" >&2; exit 1 ;;
    esac
done

if ! command -v gh >/dev/null; then
    echo "This script needs the GitHub CLI. Install it with: brew install gh" >&2
    exit 1
fi

case "$(uname -m)" in
    arm64) VARIANT="apple-silicon" ;;
    *)     VARIANT="intel" ;;
esac

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Newest unexpired artifact built from main for this architecture. The
# artifacts endpoint carries the producing run and its commit, so one call
# answers both "is there a build?" and "is it current?".
find_artifact() {
    gh api "repos/$REPO/actions/artifacts?per_page=100" --jq "
        [ .artifacts[]
          | select(.expired == false)
          | select(.name | endswith(\"-$VARIANT\"))
          | select(.workflow_run.head_branch == \"main\")
        ] | sort_by(.created_at) | reverse | .[0]
          | if . == null then empty else \"\(.workflow_run.id) \(.workflow_run.head_sha)\" end
    " 2>/dev/null || true
}

# Sets RUN rather than echoing it: `gh run watch` streams live progress, and
# capturing this in $(...) would hide it until the build was already over.
trigger_build() {
    echo "Triggering a $VARIANT build on main (about 3 minutes)..."
    # gh workflow run gives back no run id, so remember the newest run first
    # and poll until a different one shows up.
    local before after
    before=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit 1 \
        --json databaseId --jq '.[0].databaseId // 0')
    gh workflow run "$WORKFLOW" --repo "$REPO" --ref main -f variant="$VARIANT"
    for _ in $(seq 1 40); do
        sleep 3
        after=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit 1 \
            --json databaseId --jq '.[0].databaseId // 0')
        if [[ "$after" != "$before" ]]; then
            gh run watch "$after" --repo "$REPO" --exit-status
            RUN="$after"
            return 0
        fi
    done
    echo "The build workflow did not start within 2 minutes." >&2
    return 1
}

RUN=""
if [[ "$MODE" != "force" ]]; then
    # `read` returns 1 at EOF, which under `set -e` would kill the script on
    # the perfectly normal "no artifact built yet" path.
    FOUND_RUN=""; FOUND_SHA=""
    read -r FOUND_RUN FOUND_SHA <<<"$(find_artifact)" || true
    if [[ -n "${FOUND_RUN:-}" ]]; then
        if [[ "$MODE" = "reuse" ]]; then
            RUN="$FOUND_RUN"
            echo "Using existing build from run $RUN (${FOUND_SHA:0:7})."
        else
            MAIN_SHA=$(gh api "repos/$REPO/commits/main" --jq .sha)
            if [[ "$FOUND_SHA" = "$MAIN_SHA" ]]; then
                RUN="$FOUND_RUN"
                echo "Existing build matches main (${MAIN_SHA:0:7}) — no rebuild needed."
            else
                echo "Newest build is ${FOUND_SHA:0:7}, main is at ${MAIN_SHA:0:7}."
            fi
        fi
    elif [[ "$MODE" = "reuse" ]]; then
        echo "No $VARIANT artifact available to reuse (they expire after 14 days)." >&2
        echo "Run without --no-build to build one." >&2
        exit 1
    fi
fi

if [[ -z "$RUN" ]]; then
    trigger_build
fi

echo "Downloading the $VARIANT build from run $RUN..."
gh run download "$RUN" --repo "$REPO" --pattern "Keelhaven-*-$VARIANT" --dir "$TMP"

INNER=$(find "$TMP" -name 'Keelhaven.app.zip' | head -1)
if [[ -z "$INNER" ]]; then
    echo "Artifact did not contain Keelhaven.app.zip." >&2
    exit 1
fi
ditto -x -k "$INNER" "$TMP/out"

echo "Installing to /Applications..."
pkill -x Keelhaven 2>/dev/null && sleep 1 || true
rm -rf /Applications/Keelhaven.app
ditto "$TMP/out/Keelhaven.app" /Applications/Keelhaven.app
xattr -dr com.apple.quarantine /Applications/Keelhaven.app 2>/dev/null || true

open /Applications/Keelhaven.app

PLIST=/Applications/Keelhaven.app/Contents/Info.plist
COMMIT=$(/usr/libexec/PlistBuddy -c 'Print :GitCommit' "$PLIST" 2>/dev/null || echo "?")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null || echo "?")
echo "Done: Keelhaven build $BUILD ($COMMIT) is running in your menu bar."

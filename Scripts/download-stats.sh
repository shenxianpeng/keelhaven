#!/bin/bash
# Prints the website's DMG downloads as dl.keelhaven.app counted them — on the
# server, so unlike Google Analytics's file_download an ad blocker cannot hide
# them. What each field holds is listed at the top of workers/dl/src/index.js.
#
# Needs two environment variables (docs/WEBSITE.md § "Download counter"):
#
#   CLOUDFLARE_ACCOUNT_ID       the account keelhaven-dl is deployed to
#   CLOUDFLARE_ANALYTICS_TOKEN  an API token with Account Analytics: Read.
#                               Not CLOUDFLARE_API_TOKEN — wrangler reads that
#                               one, and would then try to deploy with it.
#
# Analytics Engine keeps three months and then drops it. Around a launch, keep
# what this prints next to make metrics:
#
#   make download-stats >> ~/keelhaven-metrics.log
#
# Usage: download-stats.sh [days]    (default 30, at most 90)
set -euo pipefail

DAYS=${1:-30}
if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || (( DAYS < 1 || DAYS > 90 )); then
    echo "Error: days must be a whole number from 1 to 90 — Analytics Engine keeps three months." >&2
    exit 1
fi
if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" || -z "${CLOUDFLARE_ANALYTICS_TOKEN:-}" ]]; then
    echo "Error: needs CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_ANALYTICS_TOKEN — see docs/WEBSITE.md § \"Download counter\"." >&2
    exit 1
fi

API="https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/analytics_engine/sql"
SINCE="timestamp > NOW() - INTERVAL '$DAYS' DAY"
PEOPLE="$SINCE AND blob4 != 'bot'"

# Runs one query and prints its rows, tab-separated. The token reaches curl on
# stdin rather than in its arguments, so it never shows up in `ps`.
query() {
    local sql=$1 out
    if ! out=$(curl -sS --fail-with-body "$API" -H @- --data-binary "$sql FORMAT TabSeparated" \
            <<<"Authorization: Bearer $CLOUDFLARE_ANALYTICS_TOKEN" 2>&1); then
        echo "Error: the Analytics Engine query failed — $out" >&2
        exit 1
    fi
    [[ -z "$out" ]] || printf '%s\n' "$out"
}

# One "By …" section: downloads by one field, bots left out, most first.
breakdown() {
    local title=$1 blob=$2 filter=${3:-} limit=${4:-}
    echo
    echo "$title"
    query "SELECT $blob AS value, SUM(_sample_interval) AS downloads FROM keelhaven_downloads
           WHERE $PEOPLE ${filter:+AND $filter} GROUP BY value ORDER BY downloads DESC ${limit:+LIMIT $limit}" \
        | awk -F'\t' '{ printf "  %-26s %5d\n", ($1 == "" ? "(none)" : $1), $2 }'
}

echo "Website downloads, last $DAYS days — dl.keelhaven.app"
total=$(query "SELECT SUM(_sample_interval) FROM keelhaven_downloads WHERE $PEOPLE")
bots=$(query "SELECT SUM(_sample_interval) FROM keelhaven_downloads WHERE $SINCE AND blob4 = 'bot'")
printf '  %-26s %5d\n' "downloads" "${total:-0}" "bots (left out below)" "${bots:-0}"

breakdown "By source" blob1
breakdown "By version" blob2
breakdown "By page, for the site's own buttons" blob6 "blob1 = 'site'"
breakdown "Linked from another site" blob5 "blob5 != '' AND blob1 != 'site'"
breakdown "By country, top 10" blob3 "" 10

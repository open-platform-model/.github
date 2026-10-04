#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Posts gates G2 cascade/freshness and G3 cascade/settled as commit
# statuses on release PR heads, with GITHUB_TOKEN, so both contexts come
# from GitHub Actions (workspace RELEASING.md, section "Gates"). Run by the
# receiver's gates job.
#
# Usage:
#   gates-post.sh --g2-mode <warn|enforce> --g3-mode <warn|enforce> <gates.json>
#   gates-post.sh --g2-mode <warn|enforce> --g3-mode <warn|enforce> --missing
#
# --missing (compute wrote no gates.json): a context in warn mode gets a
# warning and no status; in enforce mode it is posted as `error` on every
# open same-repo release PR head.
#
# Mapping: ok is success; a problem is success "WARN: <msg>" in warn mode
# and failure "<msg>" in enforce mode; an evaluator error is success "WARN:
# gate could not run, see the run" or error "could not evaluate, see the
# run". Descriptions are cut to 140 characters.
#
# Environment: CASCADE_REPO, CASCADE_RUN_URL (target_url), GH_TOKEN.
#
# Exit status: 0 every status posted; 1 a post failed, or (--missing) the
# release PRs cannot be listed; 2 usage.
#
# Tools: bash, jq; gh through "${CASCADE_GH:-gh}".
set -euo pipefail
CASCADE_SCRIPT=gates-post.sh
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { die "usage: gates-post.sh --g2-mode <m> --g3-mode <m> <gates.json>|--missing" 2; }
if ! { [ $# -eq 5 ] && [ "$1" = --g2-mode ] && [ "$3" = --g3-mode ]; }; then usage; fi
G2="$2" G3="$4" SRC="$5"
if ! valid_mode "$G2" || ! valid_mode "$G3"; then die "modes must be warn or enforce" 2; fi
REPO="${CASCADE_REPO:-}"
[ -n "$REPO" ] || die "CASCADE_REPO is not set" 2
URL="${CASCADE_RUN_URL:-}"
need_tools jq gh

failed=0
# post <sha> <context> <mode> <state ok|problem|error> <message>
post() {
  local line st desc
  line=$(status_for "$3" "$4" "$5") || { note "unknown gate state for $2"; failed=1; return 0; }
  st="${line%%$'\t'*}" desc="${line#*$'\t'}"
  if gh_ api -X POST "repos/$ORG/$REPO/statuses/$1" -f state="$st" -f context="$2" -f description="$desc" -f target_url="$URL" >/dev/null; then
    echo "$2 on ${1:0:12}: $st ($desc)"
  else
    note "cannot post $2 on $1"
    failed=1
  fi
}

if [ "$SRC" = --missing ]; then
  echo "::warning::no gate results from compute"
  if [ "$G2" = warn ] && [ "$G3" = warn ]; then exit 0; fi
  heads=$(gh_ pr list -R "$ORG/$REPO" --base main --state open --limit 200 --json number,headRefName,headRefOid,isCrossRepository \
    --jq '.[] | select((.headRefName | startswith("release-please--")) and .isCrossRepository == false) | .headRefOid') \
    || die "cannot list the release PRs of $REPO"
  for sha in $heads; do
    [[ $sha =~ ^[0-9a-f]{40}$ ]] || continue
    if [ "$G2" = enforce ]; then post "$sha" cascade/freshness enforce error "missing"; fi
    if [ "$G3" = enforce ]; then post "$sha" cascade/settled enforce error "missing"; fi
  done
  [ "$failed" = 0 ] || exit 1
  exit 0
fi

[ -f "$SRC" ] || die "$SRC not found"
jq -e 'type == "array"' "$SRC" >/dev/null || die "$SRC is not a JSON array"
while IFS=$'\t' read -r sha s2 m2 s3 m3; do
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || { note "skipping an entry without a commit id"; continue; }
  post "$sha" cascade/freshness "$G2" "$s2" "$m2"
  post "$sha" cascade/settled "$G3" "$s3" "$m3"
done < <(jq -r '.[] | [.sha, .freshness.state, .freshness.msg, .settled.state, .settled.msg] | map(tostring | gsub("[\t\n\r]"; " ")) | @tsv' "$SRC")
[ "$failed" = 0 ] || exit 1

#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Posts gates G2 cascade/freshness and G3 cascade/settled as commit
# statuses on release PR heads, with GITHUB_TOKEN, so both contexts come
# from GitHub Actions (workspace RELEASING.md, section "Gates"). Run by the
# receiver's Post gates job, which runs no repo code.
#
# Usage:
#   gates-post.sh --g2-mode <warn|enforce> --g3-mode <warn|enforce> <gates.json>
#   gates-post.sh --g2-mode <warn|enforce> --g3-mode <warn|enforce> --missing
#
# The heads are the open same-repo release PR heads this script lists
# itself. G3 is evaluated here (g3_eval, API reads only), once, when there is
# at least one head, and posted on every head. G2 comes from gates.json,
# which compute wrote after the release heads' code ran: only its freshness
# is read, only for a listed head, and an entry naming any other commit is
# skipped with a warning. A head without a G2 result (--missing: compute
# wrote no gates.json, or no entry for it) gets a warning and no freshness
# status in warn mode, and `error` in enforce mode.
#
# Mapping: ok is success; a problem is success "WARN: <msg>" in warn mode
# and failure "<msg>" in enforce mode; an evaluator error is success "WARN:
# gate could not run, see the run" or error "could not evaluate, see the
# run". Descriptions are cut to 140 characters.
#
# Environment: CASCADE_REPO, CASCADE_RUN_URL (target_url), GH_TOKEN.
#
# Exit status: 0 every status posted; 1 a post failed, or the release PRs
# cannot be listed; 2 usage.
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

# release_heads: the head commits of the open same-repo release PRs.
release_heads() {
  gh_ pr list -R "$ORG/$REPO" --base main --state open --limit 200 --json number,headRefName,headRefOid,isCrossRepository \
    --jq '.[] | select((.headRefName | startswith("release-please--")) and .isCrossRepository == false) | .headRefOid' \
    || die "cannot list the release PRs of $REPO"
}

if [ "$SRC" != --missing ]; then
  [ -f "$SRC" ] || die "$SRC not found"
  jq -e 'type == "array"' "$SRC" >/dev/null || die "$SRC is not a JSON array"
fi
heads=$(release_heads)
live=" $(tr '\n' ' ' <<<"$heads") "
G2RES=""
if [ "$SRC" = --missing ]; then
  echo "::warning::no gate results from compute"
else
  # "<sha>\t<state>\t<msg>" per entry; the first entry for a head counts.
  G2RES=$(jq -r '.[] | [.sha, .freshness.state, .freshness.msg] | map(tostring | gsub("[\t\n\r]"; " ")) | @tsv' "$SRC")
  while IFS=$'\t' read -r sha _; do
    [ -n "$sha" ] || continue
    [[ $live == *" $sha "* ]] || echo "::warning::skipping ${sha:0:12}: not the head of an open release PR"
  done <<<"$G2RES"
fi
if [ -n "$(tr -d '[:space:]' <<<"$heads")" ]; then g3_eval "$REPO"; fi
for sha in $heads; do
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || { note "skipping a head without a commit id"; continue; }
  line=$(awk -F '\t' -v s="$sha" '$1 == s { print; exit }' <<<"$G2RES")
  if [ -n "$line" ]; then
    IFS=$'\t' read -r _ s2 m2 <<<"$line"
    post "$sha" cascade/freshness "$G2" "$s2" "$m2"
  elif [ "$G2" = enforce ]; then
    post "$sha" cascade/freshness enforce error "missing"
  else
    echo "::warning::no cascade/freshness result for ${sha:0:12}"
  fi
  post "$sha" cascade/settled "$G3" "$G3_STATE" "$G3_MSG"
done
[ "$failed" = 0 ] || exit 1

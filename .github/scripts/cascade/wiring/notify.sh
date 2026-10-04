#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Notify downstream: tells each receiver of the calling repo that it
# released, through repository_dispatch `upstream-released` (workspace
# RELEASING.md, sections "Notify after publish" and "repository_dispatch").
# Run by the cascade-notify composite action (.github/actions/cascade-notify).
#
# Usage:
#   notify.sh validate --tag <tag>    prints the targets, comma-separated
#   notify.sh wait-proxy --tag <tag>  library only: waits for the Go proxy
#   notify.sh dispatch --tag <tag>    sends the dispatch to every target
#
# Environment: CASCADE_REPO (the calling repo's name, from the Guard step);
# dispatch: GH_TOKEN (the App token), GITHUB_STEP_SUMMARY (optional);
# wait-proxy: CASCADE_PROXY (default https://proxy.golang.org), CASCADE_CURL
# (default curl), CASCADE_SLEEP (default sleep).
#
# Exit status: 0 success (wait-proxy always, also on timeout); 1 not a
# cascade source, a bad tag, or a target still failing after 3 attempts;
# 2 usage.
#
# Tools: bash, jq, curl (wait-proxy), gh (dispatch).
set -euo pipefail
export LC_ALL=C
CASCADE_SCRIPT=notify.sh
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { die "usage: notify.sh validate|wait-proxy|dispatch --tag <tag>" 2; }

cmd="${1:-}"
[ $# -eq 3 ] && [ "$2" = --tag ] || usage
tag="$3"
src="${CASCADE_REPO:-}"
[ -n "$src" ] || die "CASCADE_REPO is not set" 2
need_tools jq

# targets: validates the source and the tag, sets TARGETS (space-separated).
targets() {
  TARGETS=$(notify_targets "$src") || die "not a cascade source: \`$(safe_text "$src")\`"
  valid_tag "$src" "$tag" || die "\`$(safe_text "$tag")\` is not a release tag of $src"
}

summary() {
  printf '%s\n' "$1"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n' "$1" >>"$GITHUB_STEP_SUMMARY"; fi
}

case "$cmd" in
  validate)
    targets
    printf '%s\n' "${TARGETS// /,}"
    ;;
  wait-proxy)
    targets
    # Only library is consumed through the Go proxy. Best effort: a timeout
    # warns and the dispatch goes out anyway; the receiver's --expect wait
    # and the daily sweep cover the rest.
    [ "$src" = library ] || exit 0
    url="${CASCADE_PROXY:-https://proxy.golang.org}/github.com/open-platform-model/library/@v/$tag.info"
    for i in $(seq 0 20); do
      code=$("${CASCADE_CURL:-curl}" -q -sS -o /dev/null -w '%{http_code}' --max-time 20 "$url" 2>/dev/null) || code=000
      if [ "$code" = 200 ]; then
        echo "the Go proxy serves library $tag"
        exit 0
      fi
      [ "$i" -lt 20 ] || break
      sleep_ 30
    done
    echo "::warning::the Go proxy did not serve library $tag within 10 minutes (last answer $code); dispatching anyway"
    ;;
  dispatch)
    targets
    need_tools gh
    body=$(jq -nc --arg s "$src" --arg t "$tag" '{event_type: "upstream-released", client_payload: {source: $s, tags: [$t]}}')
    failed=0
    for t in $TARGETS; do
      result=""
      for attempt in 1 2 3; do
        if err=$(printf '%s' "$body" | gh_ api -X POST "repos/$ORG/$t/dispatches" --input - 2>&1 >/dev/null); then
          result="HTTP 204"
          break
        fi
        result=$(grep -oE 'HTTP [0-9]{3}' <<<"$err" | head -n 1) || true
        [ -n "$result" ] || result="error"
        if [ "$attempt" -lt 3 ]; then
          case "$attempt" in 1) sleep_ 5 ;; 2) sleep_ 15 ;; esac
        fi
      done
      if [ "$result" = "HTTP 204" ]; then
        summary "- \`$t\`: dispatched (HTTP 204)"
      else
        summary "- \`$t\`: failed after 3 attempts ($result)"
        failed=1
      fi
    done
    [ "$failed" = 0 ] || die "a dispatch failed; the daily sweep covers it"
    ;;
  *) usage ;;
esac

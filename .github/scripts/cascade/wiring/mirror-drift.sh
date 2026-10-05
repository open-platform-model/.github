#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# The daily drift check of the publish mirrors (cascade-mirror-drift.yml):
# reads, from each product receiver's main, every file the .github mirrors
# copy or were read from (mirror_sources in lib.sh) and compares its sha256 with the recorded
# one, so a receiver change that leaves the mirror stale shows up red within a
# day instead of at its next live publish, which refuses it too
# (receive-publish.sh, check_mirror).
#
# Usage: mirror-drift.sh [<receiver>...] (default: MIRROR_RECEIVERS in lib.sh)
# Environment: GH_TOKEN (the run's GITHUB_TOKEN; the receivers are public).
# Requests: GET repos/open-platform-model/<receiver>/contents/<path>?ref=main
# with Accept: application/vnd.github.raw, through gh. A failed request is an
# error for that file; the check goes on with the others.
# Prints one line per file (ok, DRIFT or ERROR) and an ::error:: annotation
# per drifted or unreadable file.
# Exit status: 0 every file matches; 1 a file drifted or could not be read;
# 2 usage (an unknown receiver).
#
# Tools: bash, coreutils; gh through "${CASCADE_GH:-gh}".
set -euo pipefail
export LC_ALL=C
CASCADE_SCRIPT=mirror-drift.sh
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

need_tools gh sha256sum
recv=()
if [ $# -gt 0 ]; then recv=("$@"); else read -r -a recv <<<"$MIRROR_RECEIVERS"; fi

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
bad=0
for r in "${recv[@]}"; do
  srcs=$(mirror_sources "$r") || die "not a cascade receiver: $(safe_text "$r")" 2
  while read -r path want; do
    [ -n "$path" ] || continue
    if ! gh_ api -H "Accept: application/vnd.github.raw" "repos/$ORG/$r/contents/$path?ref=main" >"$T/file" 2>"$T/err"; then
      bad=1
      printf 'ERROR %s %s: %s\n' "$r" "$path" "$(head -c 200 "$T/err" | tr '\n' ' ')"
      printf '::error::cannot read %s from the main of %s\n' "$path" "$r"
      continue
    fi
    have=$(sha256sum <"$T/file")
    have="${have%% *}"
    if [ "$have" = "$want" ]; then
      printf 'ok %s %s\n' "$r" "$path"
    else
      bad=1
      printf 'DRIFT %s %s: %s\n' "$r" "$path" "$(mirror_stale_text "$r" "$path" "$have" "$want")"
      printf '::error::%s\n' "$(mirror_stale_text "$r" "$path" "$have" "$want")"
    fi
  done <<<"$srcs"
done
exit "$bad"

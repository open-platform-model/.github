#!/usr/bin/env bash
# Offline tests for the release-cascade wiring scripts. Run from anywhere:
#   bash .github/scripts/cascade/wiring/test/run.sh [<case file name>...]
# gh is a shim answering from per-case fixtures (test/shim/gh), origins are
# bare repos reached through file:// URLs, the resolver runs only its
# offline subcommands, and sleep is faked: nothing touches the network.
# Prints PASS/FAIL per case; exits 0 when every case passes, 1 otherwise.
# Needs bash, git, jq, grep -P, go-task and mikefarah yq v4.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR

# shellcheck source=lib.sh disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

files=(lib static notify compute publish bound gates wiringcheck drift)
[ $# -eq 0 ] || files=("$@")
for f in "${files[@]}"; do
  [ -f "$W_HERE/cases/$f.sh" ] || { fail "case file $f" "test/cases/$f.sh not found"; continue; }
  # shellcheck source=/dev/null
  . "$W_HERE/cases/$f.sh"
done

printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

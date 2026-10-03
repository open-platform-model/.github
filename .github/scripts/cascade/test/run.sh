#!/usr/bin/env bash
# Offline table test for cascade-resolve.sh and its stub. Run from anywhere:
#   bash .github/scripts/cascade/test/run.sh [<case file name>...]
# curl and git are PATH shims answering from fixture files (test/shim/), the
# clock and sleep are faked, and nothing touches the network. Prints
# PASS/FAIL per case; exits 0 when every case passes, 1 otherwise.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR

# shellcheck source=lib.sh disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

files=(semver files stub lookups newest agreement prtext requests)
[ $# -eq 0 ] || files=("$@")
for f in "${files[@]}"; do
  [ -f "$T_HERE/cases/$f.sh" ] || continue
  # shellcheck source=/dev/null
  . "$T_HERE/cases/$f.sh"
done

printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

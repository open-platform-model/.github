#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# The pins script publish hands the resolver's title and body: the receiver's
# own .tasks/cascade/pins.sh as mirrored in lib.sh (receiver_pins), so the PR
# text never depends on code from the receiver's tree. It reads only
# `git show <ref>:<path>`, never the disk; WORKTREE means HEAD (publish runs
# it in a clean worktree of the new tip).
#
# Usage: pins.sh WORKTREE|<git ref>, from inside the receiver's checkout.
# Environment: CASCADE_PINS_REPO, the receiver (the Guard step's repo name).
# Prints one TSV row per pin: <pin-key> <display> <class> <version> <labels>.
# Exit status: 0 success; 1 an unknown ref or receiver, or a malformed pin;
# 2 usage.
#
# Tools: bash, coreutils, git, grep -P, awk, sed.
set -euo pipefail
export LC_ALL=C
CASCADE_SCRIPT=pins.sh
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[ $# -eq 1 ] && [ -n "$1" ] || die "usage: pins.sh WORKTREE|<git ref>" 2
ref="$1"
[ "$ref" != WORKTREE ] || ref=HEAD
[[ $ref != -* ]] || die "the ref \`$(safe_text "$ref")\` must not start with -" 2
git rev-parse -q --verify "$ref^{commit}" >/dev/null || die "unknown ref: $(safe_text "$ref")"
receiver_classes "${CASCADE_PINS_REPO:-}" >/dev/null || die "not a cascade receiver: $(safe_text "${CASCADE_PINS_REPO:-}")"
receiver_pins "$CASCADE_PINS_REPO" "$ref"

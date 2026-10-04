#!/usr/bin/env bash
# Reports the sandbox's one upstream pin at a ref (Phase 2 cascade contract
# section 4.1). Usage: pins.sh WORKTREE|<git ref>. Exit 0, or 1 on error.
set -euo pipefail
die() { printf 'pins.sh: %s\n' "$1" >&2; exit 1; }
[ $# -eq 1 ] || die "usage: pins.sh WORKTREE|<git ref>"
ref="$1"
cd "$(git rev-parse --show-toplevel)"
if [ "$ref" = WORKTREE ]; then
  [ -f UPSTREAM_VERSION ] || exit 0
  v=$(cat UPSTREAM_VERSION)
else
  git rev-parse -q --verify "$ref^{commit}" >/dev/null || die "unknown ref: $ref"
  [ -n "$(git ls-tree --name-only "$ref" -- UPSTREAM_VERSION)" ] || exit 0
  v=$(git show "$ref:UPSTREAM_VERSION")
fi
[[ $v =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "UPSTREAM_VERSION at $ref is not vX.Y.Z: $v"
printf '%s\t%s\t%s\t%s\t%s\n' github.com/open-platform-model/cascade-sandbox-up up shipped "$v" ""

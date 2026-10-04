#!/usr/bin/env bash
# deps:cascade for the sandbox (Phase 3 wiring contract section 11.3): moves
# UPSTREAM_VERSION to the newest published cascade-sandbox-up release with
# up.tar.gz. Exit 0 when it wrote, 3 when it stays, the resolver's code on
# error.
set -euo pipefail
[ -z "$(git status --porcelain --untracked-files=all)" ] || { echo "cascade.sh: the tree is dirty" >&2; exit 1; }
state="$(git rev-parse --git-dir)/cascade"
mkdir -p "$state"
: >"$state/warnings"
export CASCADE_WARNINGS="$state/warnings"
"$CASCADE_RESOLVER" check-files --repo-root .
key=github.com/open-platform-model/cascade-sandbox-up
cur=$(cat UPSTREAM_VERSION)
args=(newest release cascade-sandbox-up --asset up.tar.gz --current "$cur" --repo-root .)
for pair in ${CASCADE_EXPECT:-}; do
  if [ "${pair%%=*}" = "$key" ]; then args+=(--expect "${pair#*=}"); fi
done
rc=0
next=$("$CASCADE_RESOLVER" "${args[@]}") || rc=$?
case "$rc" in
  0) printf '%s\n' "$next" >UPSTREAM_VERSION ;;
  3) exit 3 ;;
  *) exit "$rc" ;;
esac

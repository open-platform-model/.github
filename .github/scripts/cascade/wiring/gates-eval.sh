#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Evaluates gates G2 cascade/freshness and G3 cascade/settled on the
# receiving repo's open release PRs (workspace RELEASING.md, section
# "Gates"). Runs inside the receiver's compute job, before any pin work;
# gates-post.sh posts the result.
#
# Usage: gates-eval.sh
#
# Scope: open PRs on base main whose head ref starts with release-please--
# and whose head repo is this repo. Fork PRs are never evaluated.
# G2: the release head's own `task -x deps:cascade` in a detached worktree
#   under CASCADE_T, with CASCADE_BASE at the head and no payload variable:
#   exit 3 is ok, exit 0 with a shipped path is a problem, else an error.
# G3: an upstream's open cascade PR titled fix(deps) or feat(deps), or its
#   `autorelease: pending` PR listing a **deps:** bullet, is a problem.
#
# Environment: CASCADE_REPO, CASCADE_T (default $RUNNER_TEMP/cascade),
# CASCADE_REPO_DIR (default $PWD/repo), CASCADE_RESOLVER, GH_TOKEN and
# CASCADE_READ_TOKEN (GITHUB_TOKEN).
# Writes $CASCADE_T/gates.json:
#   [{"sha", "pr", "freshness": {"state": "ok|problem|error", "msg"}, "settled": {...}}]
#
# Exit status: 0 written (per-gate errors are in the file); 1 the release-PR
# list cannot be read (no file); 2 usage.
#
# Tools: bash, coreutils, git, jq, go-task; gh through "${CASCADE_GH:-gh}".
set -euo pipefail
export LC_ALL=C
CASCADE_SCRIPT=gates-eval.sh
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[ $# -eq 0 ] || die "usage: gates-eval.sh" 2
REPO="${CASCADE_REPO:-}"
[ -n "$REPO" ] || die "CASCADE_REPO is not set" 2
T="${CASCADE_T:-${RUNNER_TEMP:-}/cascade}"
check_scratch "$T"
RD=$(realpath -m -- "${CASCADE_REPO_DIR:-$PWD/repo}")
RESOLVER="${CASCADE_RESOLVER:-$(cd "$WIRING_DIR/.." && pwd)/cascade-resolve.sh}"
mkdir -p "$T"
rm -f "$T/gates.json"
need_tools git jq gh

prs=$(gh_ pr list -R "$ORG/$REPO" --base main --state open --limit 200 --json number,headRefName,headRefOid,isCrossRepository) \
  || die "cannot list the open PRs of $REPO"
prs=$(jq -c '[.[] | select((.headRefName | startswith("release-please--")) and .isCrossRepository == false)]' <<<"$prs") \
  || die "cannot parse the PR list of $REPO"

# g3: sets G3_STATE and G3_MSG for this receiver's upstreams.
g3() {
  local up pr n title pending problems=() p
  G3_STATE=ok G3_MSG="ok: upstreams settled"
  for up in $(g3_upstreams "$REPO"); do
    if ! pr=$(cascade_pr "$up"); then G3_STATE=error G3_MSG="cannot read the cascade PR of $up"; return 0; fi
    if [ -n "$pr" ]; then
      n=$(jq -r .number <<<"$pr")
      title=$(jq -r .title <<<"$pr")
      case "$title" in "fix(deps)"* | "feat(deps)"*) problems+=("$up has open cascade #$n") ;; esac
    fi
    if ! pending=$(gh_ pr list -R "$ORG/$up" --base main --state open --label "autorelease: pending" --json number,body); then
      G3_STATE=error G3_MSG="cannot list the release PRs of $up"
      return 0
    fi
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      problems+=("$up release #$p pending with deps")
    done < <(jq -r '.[] | select((.body // "") | contains("**deps:**")) | .number' <<<"$pending")
  done
  if [ "${#problems[@]}" -gt 0 ]; then
    G3_STATE=problem
    G3_MSG=$(printf '%s; ' "${problems[@]}")
    G3_MSG="${G3_MSG%; }"
  fi
}

# g2 <number> <sha>: sets G2_STATE and G2_MSG for one release head.
g2() {
  local n="$1" sha="$2" tmp rc=0 shipped=0 moved=""
  G2_STATE=error G2_MSG="the release head could not be checked"
  tmp="$T/g2-$n"
  rm -rf "$tmp"
  if ! git_read -C "$RD" fetch -q origin "$sha" || ! git -C "$RD" worktree add -q --detach "$tmp" "$sha"; then
    G2_MSG="cannot check out the release head"
    return 0
  fi
  (cd "$tmp" && run_repo_code env -u CASCADE_EXPECT -u CASCADE_SOURCE -u CASCADE_TAGS -u CASCADE_NOTES_FILE \
    CASCADE_BASE="$sha" task -x deps:cascade) >"$T/g2-$n.log" 2>&1 || rc=$?
  case "$rc" in
    3) G2_STATE=ok G2_MSG="ok: shipped pins current" ;;
    0)
      local cls
      if cls=$({ git -C "$tmp" diff --name-only HEAD; git -C "$tmp" ls-files --others --exclude-standard; } | sort -u \
        | "$RESOLVER" classify --classes "$tmp/.tasks/cascade/classes"); then
        if grep -q '^shipped'$'\t' <<<"$cls"; then shipped=1; fi
        if [ "$shipped" = 1 ]; then
          local pm pw k d c v
          local -A FROM=()
          if pm=$(cd "$tmp" && run_repo_code .tasks/cascade/pins.sh "$sha") && pw=$(cd "$tmp" && run_repo_code .tasks/cascade/pins.sh WORKTREE); then
            while IFS=$'\t' read -r k _ _ v _; do [ -z "$k" ] || FROM[$k]="$v"; done <<<"$pm"
            while IFS=$'\t' read -r k d c v _; do
              [ -n "$k" ] && [ "$c" = shipped ] && [ -n "${FROM[$k]:-}" ] && [ "${FROM[$k]}" != "$v" ] || continue
              moved="${moved:+$moved, }$d ${FROM[$k]}→$v"
            done <<<"$pw"
            G2_STATE=problem G2_MSG="behind: ${moved:-shipped files would change}"
          else
            G2_STATE=error G2_MSG="pins.sh failed on the release head"
          fi
        else
          G2_STATE=ok G2_MSG="ok: only test/release-tool pins behind"
        fi
      else
        G2_MSG="cannot classify the changed paths"
      fi
      ;;
    *) G2_MSG="the release head's task exited $rc" ;;
  esac
  git -C "$RD" worktree remove --force "$tmp" >/dev/null 2>&1 || rm -rf "$tmp"
  git -C "$RD" worktree prune
}

out="[]"
if [ "$(jq length <<<"$prs")" -gt 0 ]; then
  g3
  while IFS=$'\t' read -r n sha; do
    [[ $sha =~ ^[0-9a-f]{40}$ ]] || continue
    g2 "$n" "$sha"
    echo "release PR #$n: freshness $G2_STATE ($G2_MSG); settled $G3_STATE ($G3_MSG)"
    out=$(jq -c --arg sha "$sha" --argjson n "$n" --arg s2 "$G2_STATE" --arg m2 "$G2_MSG" --arg s3 "$G3_STATE" --arg m3 "$G3_MSG" \
      '. + [{sha: $sha, pr: $n, freshness: {state: $s2, msg: $m2}, settled: {state: $s3, msg: $m3}}]' <<<"$out")
  done < <(jq -r '.[] | [.number, .headRefOid] | @tsv' <<<"$prs")
fi
printf '%s\n' "$out" >"$T/gates.json"

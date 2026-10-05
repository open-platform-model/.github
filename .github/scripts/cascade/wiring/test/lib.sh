# shellcheck shell=bash
# shellcheck disable=SC2034 # the variables here are read by run.sh and the case files
# Helpers for the wiring scripts' offline tests (test/run.sh): temp dirs, a
# gh shim answering from per-case fixtures, a toy receiving repo served from
# a bare file:// origin, and assertions. Sourced, never run.

W_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIRING="$(cd "$W_HERE/.." && pwd)"
ORG_ROOT="$(cd "$WIRING/../../../.." && pwd)"
WORKFLOWS="$ORG_ROOT/.github/workflows"
RESOLVER="$ORG_ROOT/.github/scripts/cascade/cascade-resolve.sh"
COMPUTE="$WIRING/receive-compute.sh"
PUBLISH="$WIRING/receive-publish.sh"
NOTIFY="$WIRING/notify.sh"
GATES_EVAL="$WIRING/gates-eval.sh"
GATES_POST="$WIRING/gates-post.sh"

T_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/cascade-wiring.XXXXXX")
trap 'chmod -R u+w "$T_ROOT" 2>/dev/null; rm -rf "$T_ROOT"' EXIT

# Git ignores the caller's config, so a case gives the same result locally
# and on a bare runner.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Cascade Test" GIT_AUTHOR_EMAIL="cascade-test@example.invalid"
export GIT_COMMITTER_NAME="Cascade Test" GIT_COMMITTER_EMAIL="cascade-test@example.invalid"
export GIT_AUTHOR_DATE="2026-10-04T12:00:00Z" GIT_COMMITTER_DATE="2026-10-04T12:00:00Z"
unset CASCADE_SOURCE CASCADE_TAGS CASCADE_EXPECT CASCADE_NOTES_FILE CASCADE_EXTRA_SOURCES \
  CASCADE_WARNINGS CASCADE_BASE CASCADE_READ_TOKEN GITHUB_TOKEN GH_TOKEN \
  GITHUB_OUTPUT GITHUB_STEP_SUMMARY GITHUB_ENV GITHUB_REPOSITORY

mkdir -p "$T_ROOT/bin"
# Fake sleep: records each requested interval, returns at once.
# shellcheck disable=SC2016 # the fake sleep script text is literal
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$1" >>"$CASCADE_FIXTURE_DIR/sleep.log"\n' >"$T_ROOT/bin/fake-sleep"
chmod +x "$T_ROOT/bin/fake-sleep"
export CASCADE_SLEEP="$T_ROOT/bin/fake-sleep"
export CASCADE_GH="$W_HERE/shim/gh"
export CASCADE_RESOLVER="$RESOLVER"
export CASCADE_TODAY=2026-10-04

PASS=0
FAIL=0
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }
# pass also fails the case when the gh shim saw a call no fixture answered.
pass() {
  if [ -n "${GHFX:-}" ] && [ -s "$GHFX/unexpected" ]; then
    fail "$1" "unexpected gh call: $(head -n 1 "$GHFX/unexpected")"
    : >"$GHFX/unexpected"
    return 0
  fi
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

# new_fx: a fresh fixture directory for the next case.
FX_N=0
new_fx() {
  FX_N=$((FX_N + 1))
  FX="$T_ROOT/fx$FX_N"
  GHFX="$FX/gh"
  mkdir -p "$FX" "$GHFX"
  : >"$FX/sleep.log"
  : >"$GHFX/log"
  export CASCADE_FIXTURE_DIR="$FX" CASCADE_GH_FIXTURES="$GHFX"
  export GITHUB_OUTPUT="$FX/output" GITHUB_STEP_SUMMARY="$FX/summary"
  : >"$GITHUB_OUTPUT"
  : >"$GITHUB_STEP_SUMMARY"
}

# gh_reset: forget every fixture answer and the call log.
gh_reset() { rm -rf "${GHFX:?}"; mkdir -p "$GHFX"; : >"$GHFX/log"; }

# gh_fx <rc> <stdout> -- <argv...>: the next answer to that exact call.
gh_fx() {
  local rc="$1" out="$2" key dir n
  shift 3
  key=$(printf '%s\n' "$@" | sha256sum | cut -c1-32)
  dir="$GHFX/$key"
  mkdir -p "$dir"
  printf '%s\n' "$@" >"$dir/argv"
  n=1
  while [ -f "$dir/$n.rc" ]; do n=$((n + 1)); done
  printf '%s\n' "$rc" >"$dir/$n.rc"
  printf '%s' "$out" >"$dir/$n.out"
}
# gh_fx_file <rc> <file> -- <argv...>: as gh_fx, with the file's exact bytes
# as stdout (a trailing newline kept).
gh_fx_file() {
  local rc="$1" src="$2" key dir n
  shift 3
  gh_fx "$rc" "" -- "$@"
  key=$(printf '%s\n' "$@" | sha256sum | cut -c1-32)
  dir="$GHFX/$key"
  n=1
  while [ -f "$dir/$((n + 1)).rc" ]; do n=$((n + 1)); done
  cp "$src" "$dir/$n.out"
}
# gh_fx_err <rc> <stderr> -- <argv...>
gh_fx_err() {
  local rc="$1" err="$2" key dir n
  shift 3
  key=$(printf '%s\n' "$@" | sha256sum | cut -c1-32)
  dir="$GHFX/$key"
  mkdir -p "$dir"
  n=1
  while [ -f "$dir/$n.rc" ]; do n=$((n + 1)); done
  printf '%s\n' "$rc" >"$dir/$n.rc"
  printf '%s' "$err" >"$dir/$n.err"
}
# gh_accept <glob>: calls matching the glob exit 0 with no output.
gh_accept() { printf '%s\n' "$1" >>"$GHFX/accept"; }
# gh_called <glob>: exit 0 when a logged call matches.
gh_called() {
  local l
  while IFS= read -r l; do
    # shellcheck disable=SC2053 # a glob pattern
    [[ $l == $1 ]] && return 0
  done <"$GHFX/log"
  return 1
}
gh_count() {
  local l n=0
  while IFS= read -r l; do
    # shellcheck disable=SC2053 # a glob pattern
    [[ $l == $1 ]] && n=$((n + 1))
  done <"$GHFX/log"
  echo "$n"
}

# run <command...>: runs it, capturing OUT, ERR and RC.
run() {
  set +e
  OUT=$("$@" 2>"$T_ROOT/err")
  RC=$?
  set -e
  ERR=$(cat "$T_ROOT/err")
}

# expect <name> <rc> <stdout> [<stderr substring>] -- <command...>
expect() {
  local name="$1" wrc="$2" wout="$3" werr=""
  shift 3
  if [ "$1" != -- ]; then werr="$1"; shift; fi
  shift
  run "$@"
  if [ "$RC" != "$wrc" ]; then fail "$name" "exit $RC, want $wrc; stdout '$OUT'; stderr: $ERR"; return 0; fi
  if [ "$OUT" != "$wout" ]; then fail "$name" "stdout '$OUT', want '$wout'; stderr: $ERR"; return 0; fi
  if [ -n "$werr" ] && [[ $ERR != *"$werr"* ]]; then fail "$name" "stderr lacks '$werr': $ERR"; return 0; fi
  pass "$name"
}

# check <name> <command...>: passes when the command succeeds.
check() {
  local name="$1"
  shift
  if "$@"; then pass "$name"; else fail "$name" "check failed: $*"; fi
}

# in_lib <command...>: runs it in a subshell with wiring/lib.sh sourced.
in_lib() {
  (
    # shellcheck source=/dev/null
    . "$WIRING/lib.sh"
    "$@"
  )
}

# rule_copy <strict|tree>: a copy of the wiring scripts whose WF_GUARD_RULE
# is the given rule, so cases can exercise the rule that is not shipped.
rule_copy() {
  # The same depth as in the repo: check_scratch treats four levels up as
  # the org .github checkout.
  local d="$T_ROOT/rule-$1/.github/scripts/cascade/wiring"
  if [ ! -d "$d" ]; then
    mkdir -p "$d"
    cp "$WIRING"/*.sh "$d/"
    # publish runs the resolver beside the wiring scripts.
    cp "$WIRING/../cascade-resolve.sh" "$d/.."
    cp -r "$WIRING/../lib" "$d/.."
    sed -i "s/^WF_GUARD_RULE=.*/WF_GUARD_RULE=$1/" "$d/lib.sh"
  fi
  printf '%s' "$d"
}

# yaml_run <workflow file> <job> <step name>: a step's run: text.
yaml_run() {
  J="$2" S="$3" yq -r '.jobs[strenv(J)].steps[] | select(.name == strenv(S)) | .run' "$1"
}

# --- the toy receiving repo ---------------------------------------------------
# A cascade-sandbox-down look-alike: UPSTREAM_VERSION is its one shipped pin,
# fixtures/ is test, and its deps:cascade writes the version in $TOY_TARGET.

BOT_EMAIL='337635439+opm-cascade[bot]@users.noreply.github.com'

toy_files() { # toy_files <dir>
  local d="$1"
  mkdir -p "$d/.tasks/cascade" "$d/fixtures" "$d/.github/workflows"
  printf 'v0.1.0\n' >"$d/UPSTREAM_VERSION"
  printf 'fixture\n' >"$d/fixtures/data.txt"
  printf 'name: touch\non: workflow_dispatch\njobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo 1\n' >"$d/.github/workflows/touch.yml"
  printf 'shipped UPSTREAM_VERSION\ntest fixtures/\n' >"$d/.tasks/cascade/classes"
  cat >"$d/Taskfile.yml" <<'YAML'
version: '3'
tasks:
  deps:cascade:
    cmds:
      - bash .tasks/cascade/cascade.sh
  deps:cascade:title:
    cmds:
      - '"$CASCADE_RESOLVER" title --classes .tasks/cascade/classes --pins .tasks/cascade/pins.sh'
  deps:cascade:body:
    cmds:
      - '"$CASCADE_RESOLVER" body --classes .tasks/cascade/classes --pins .tasks/cascade/pins.sh'
YAML
  # The archived sandbox's own pins.sh, byte for byte: publish refuses unless
  # its sha256 is the one mirror_sources records for cascade-sandbox-down.
  cat >"$d/.tasks/cascade/pins.sh" <<'SH'
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
SH
  cat >"$d/.tasks/cascade/cascade.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for v in GH_TOKEN GITHUB_TOKEN CASCADE_READ_TOKEN GIT_CONFIG_COUNT GIT_CONFIG_VALUE_0; do
  if [ -n "${!v:-}" ]; then echo "toy: $v is visible to repo code" >&2; exit 9; fi
done
# A hostile task writes every runner command file whose path it is given.
for v in GITHUB_OUTPUT GITHUB_ENV GITHUB_PATH GITHUB_STEP_SUMMARY GITHUB_STATE; do
  if [ -n "${!v:-}" ]; then printf 'action=push\nok=true\nforged=%s\n' "$v" >>"${!v}"; fi
done
[ "${CASCADE_ALLOW_DIRTY:-}" = 1 ] || [ -z "$(git status --porcelain --untracked-files=all)" ] || { echo "toy: dirty tree" >&2; exit 1; }
printf 'task=main allow_dirty=%s\n' "${CASCADE_ALLOW_DIRTY:-}" >>"${TOY_TASK_LOG:-/dev/null}"
state="$(git rev-parse --git-dir)/cascade"
mkdir -p "$state"
: >"$state/warnings"
printf 'expect=%s source=%s tags=%s\n' "${CASCADE_EXPECT:-}" "${CASCADE_SOURCE:-}" "${CASCADE_TAGS:-}" >>"${TOY_LOG:-/dev/null}"
[ -z "${TOY_EXIT:-}" ] || exit "$TOY_EXIT"
next=$(cat "$TOY_TARGET")
cur=$(cat UPSTREAM_VERSION)
[ "$next" != "$cur" ] || exit 3
printf '%s\n' "$next" >UPSTREAM_VERSION
exit 0
SH
  chmod +x "$d/.tasks/cascade/pins.sh" "$d/.tasks/cascade/cascade.sh"
}

# TOY_LABEL_PINS: a toy pins.sh whose row carries $TOY_LABELS, for the
# compute cases that need a pin label; a case commits it to main itself.
# shellcheck disable=SC2016 # the script text is literal
TOY_LABEL_PINS='#!/usr/bin/env bash
set -euo pipefail
ref="$1"
cd "$(git rev-parse --show-toplevel)"
if [ "$ref" = WORKTREE ]; then
  [ -f UPSTREAM_VERSION ] || exit 0
  v=$(cat UPSTREAM_VERSION)
else
  v=$(git show "$ref:UPSTREAM_VERSION" 2>/dev/null) || exit 0
fi
printf "%s\t%s\t%s\t%s\t%s\n" github.com/open-platform-model/cascade-sandbox-up up shipped "$v" "${TOY_LABELS:-}"'

# mk_toy: a bare origin with the toy on main, a seed clone for "human" and
# "bot" pushes ($SEED), and the job's checkout at $WS/repo. Sets ORIGIN,
# SEED, WS, CASCADE_T, CASCADE_REPO_DIR and TOY_TARGET (v0.1.0: nothing to do).
mk_toy() {
  ORIGIN="$FX/origin.git"
  SEED="$FX/seed"
  WS="$FX/ws"
  git init -q --bare -b main "$ORIGIN"
  git init -q -b main "$SEED"
  toy_files "$SEED"
  git -C "$SEED" add -A
  git -C "$SEED" commit -q -m "toy repo"
  git -C "$SEED" remote add origin "file://$ORIGIN"
  git -C "$SEED" push -q origin main
  export TOY_TARGET="$FX/target" TOY_LOG="$FX/toy.log" TOY_TASK_LOG="$FX/task.log"
  printf 'v0.1.0\n' >"$TOY_TARGET"
  : >"$TOY_LOG"
  export CASCADE_T="$FX/t" CASCADE_REPO_DIR="$WS/repo"
  mkdir -p "$WS"
  # compute's state step reads the upstream's releases on every run that is
  # not skipped; a case that cares answers them with a fixture.
  gh_accept "api --paginate repos/open-platform-model/cascade-sandbox-up/releases --jq *"
}

# fresh_checkout: the job's own clone of origin (as actions/checkout with
# fetch-depth 0 leaves it), replacing any earlier one.
fresh_checkout() {
  rm -rf "$WS/repo" "$CASCADE_T"
  git clone -q "file://$ORIGIN" "$WS/repo"
}

# seed_commit <branch> <who bot|human|amend> <file> <content> [<message>]:
# commits on <branch> of the seed clone (created from origin/main when
# missing) and pushes it. amend: the last commit, bot author, human committer.
seed_commit() {
  local br="$1" who="$2" f="$3" c="$4" msg="${5:-edit $3}"
  git -C "$SEED" fetch -q origin
  if git -C "$SEED" rev-parse -q --verify "refs/remotes/origin/$br" >/dev/null; then
    git -C "$SEED" checkout -q -B "$br" "origin/$br"
  else
    git -C "$SEED" checkout -q -B "$br" origin/main
  fi
  mkdir -p "$(dirname "$SEED/$f")"
  printf '%s\n' "$c" >"$SEED/$f"
  git -C "$SEED" add -A
  case "$who" in
    bot) GIT_AUTHOR_NAME='opm-cascade[bot]' GIT_AUTHOR_EMAIL="$BOT_EMAIL" GIT_COMMITTER_NAME='opm-cascade[bot]' GIT_COMMITTER_EMAIL="$BOT_EMAIL" git -C "$SEED" commit -q -m "$msg" ;;
    human) git -C "$SEED" commit -q -m "$msg" ;;
    amend) GIT_AUTHOR_NAME='opm-cascade[bot]' GIT_AUTHOR_EMAIL="$BOT_EMAIL" git -C "$SEED" commit -q --amend --no-edit --reset-author ;;
  esac
  git -C "$SEED" push -q -f origin "$br"
}

origin_tip() { git --git-dir="$ORIGIN" rev-parse -q --verify "refs/heads/$1" || true; }

# pr_json <number> <title> <body file> [<labels comma list>] [<author>] [<cross 0|1>] [<owner>]
pr_json() {
  local labels="${4:-}" author="${5:-app/opm-cascade}" cross="${6:-0}" owner="${7:-open-platform-model}"
  jq -nc --argjson n "$1" --arg t "$2" --rawfile b "$3" --arg l "$labels" --arg a "$author" \
    --argjson x "$([ "$cross" = 1 ] && echo true || echo false)" --arg o "$owner" --arg oid "$(origin_tip deps/cascade)" \
    '{number: $n, title: $t, body: $b, labels: ($l | split(",") | map(select(. != "") | {name: .})),
      headRefOid: $oid, isCrossRepository: $x, headRepositoryOwner: {login: $o}, author: {login: $a}}'
}

# shellcheck disable=SC2054 # the --json value is one comma-separated argument
PR_LIST_ARGS=(pr list -R open-platform-model/cascade-sandbox-down --head deps/cascade --base main --state open --json number,title,body,labels,headRefOid,isCrossRepository,headRepositoryOwner,author)
# gh_prs <json array>: the next answer to the cascade PR list.
gh_prs() { gh_fx 0 "$1" -- "${PR_LIST_ARGS[@]}"; }

# compute <step...>: runs receive-compute.sh steps in order from $WS, as the
# receive workflow does; stops at the first failing step (RC, OUT, ERR).
compute() {
  local s
  for s in "$@"; do
    run env -C "$WS" CASCADE_REPO="${CASCADE_REPO:-cascade-sandbox-down}" \
      CASCADE_DRY_RUN="${CASCADE_DRY_RUN:-false}" CASCADE_GATES_ONLY="${CASCADE_GATES_ONLY:-false}" \
      CASCADE_REF="${CASCADE_REF:-refs/heads/main}" CASCADE_EVENT="${CASCADE_EVENT:-workflow_dispatch}" \
      CASCADE_PAYLOAD="${CASCADE_PAYLOAD:-}" CASCADE_G2_MODE="${CASCADE_G2_MODE:-warn}" CASCADE_G3_MODE="${CASCADE_G3_MODE:-warn}" \
      bash "$COMPUTE" "$s"
    [ "$RC" = 0 ] || return 0
  done
}
COMPUTE_STEPS=(init payload state prepare notes run text action plan summary)

st() { cat "$CASCADE_T/state/$1" 2>/dev/null || true; }
plan() { jq -r "$1" "$CASCADE_T/plan.json"; }

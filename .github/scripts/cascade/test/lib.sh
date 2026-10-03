# shellcheck shell=bash
# shellcheck disable=SC2034 # the variables here are read by run.sh and the case files
# Helpers for the resolver's offline table test (test/run.sh): sandbox,
# fixtures, PATH shims and assertions. Sourced, never run.

T_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASCADE_DIR="$(cd "$T_HERE/.." && pwd)"
R="$CASCADE_DIR/cascade-resolve.sh"
STUB="$CASCADE_DIR/stub-resolve.sh"
FIXTURES="$T_HERE/fixtures"

T_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/cascade-test.XXXXXX")
trap 'chmod -R u+w "$T_ROOT" 2>/dev/null; rm -rf "$T_ROOT"' EXIT

# Git ignores the caller's config (signing, hooks, templates, identity), so a
# case gives the same result locally and on a bare runner.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Cascade Test" GIT_AUTHOR_EMAIL="cascade-test@example.invalid"
export GIT_COMMITTER_NAME="Cascade Test" GIT_COMMITTER_EMAIL="cascade-test@example.invalid"
export GIT_AUTHOR_DATE="2026-10-03T12:00:00Z" GIT_COMMITTER_DATE="2026-10-03T12:00:00Z"

# PATH: the curl and git shims first, then a directory whose `cue` refuses to
# run, so the resolver's cue-free parse is what runs everywhere.
mkdir -p "$T_ROOT/bin"
printf '#!/usr/bin/env bash\necho "cue is hidden from the resolver tests" >&2\nexit 127\n' >"$T_ROOT/bin/cue"
# Fake sleep: records each requested interval, returns at once.
# shellcheck disable=SC2016 # the fake sleep script text is literal
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$1" >>"$CASCADE_FIXTURE_DIR/sleep.log"\n' >"$T_ROOT/bin/fake-sleep"
chmod +x "$T_ROOT/bin/cue" "$T_ROOT/bin/fake-sleep"
export PATH="$T_HERE/shim:$T_ROOT/bin:$PATH"
export CASCADE_SLEEP="$T_ROOT/bin/fake-sleep"
export CASCADE_TODAY=2026-10-03
unset CASCADE_WARNINGS CASCADE_BASE CASCADE_SOURCE CASCADE_TAGS CASCADE_NOTES_FILE \
  CASCADE_MAX_WAIT CASCADE_GOPROXY CASCADE_EXPECT
# Values the no-token case looks for in every request.
export GITHUB_TOKEN=ghp_cascadeTestSecretValue GH_TOKEN=gho_cascadeTestSecretValue

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

# new_fx: a fresh, empty fixture directory for the next case.
FX_N=0
new_fx() {
  FX_N=$((FX_N + 1))
  FX="$T_ROOT/fx$FX_N"
  mkdir -p "$FX/http" "$FX/git" "$FX/root"
  : >"$FX/curl.log"
  : >"$FX/sleep.log"
  export CASCADE_FIXTURE_DIR="$FX"
}

fx_path() { local rel="${1#*://}"; printf '%s/http/%s' "$FX" "${rel//\?/%3F}"; }

# fx_body <url> <file>: answer GET <url> with the file (status 200).
fx_body() { local p; p=$(fx_path "$1"); mkdir -p "$(dirname "$p")"; cp "$2" "$p"; }
# fx_text <url> <text>: answer GET <url> with the text.
fx_text() { local p; p=$(fx_path "$1"); mkdir -p "$(dirname "$p")"; printf '%s' "$2" >"$p"; }
# fx_status <url> <code>...: one status per request, the last repeating.
fx_status() { local p u="$1"; shift; p=$(fx_path "$u"); mkdir -p "$(dirname "$p")"; printf '%s\n' "$@" >"$p.status"; }
# fx_headers <url> <line>...: response headers.
fx_headers() { local p u="$1"; shift; p=$(fx_path "$u"); mkdir -p "$(dirname "$p")"; printf '%s\n' "$@" >"$p.headers"; }
# fx_refs <repo> <tag>...: git ls-remote answer for the repo.
fx_refs() {
  local repo="$1" t
  shift
  : >"$FX/git/$repo.refs"
  for t in "$@"; do printf '%040d\trefs/tags/%s\n' 0 "$t" >>"$FX/git/$repo.refs"; done
}
fx_refs_file() { cp "$2" "$FX/git/$1.refs"; }

GHCR=https://ghcr.io
ghcr_token_url() { printf '%s/token?scope=repository:%s:pull&service=ghcr.io' "$GHCR" "$1"; }
ghcr_tags_url() { printf '%s/v2/%s/tags/list?n=1000' "$GHCR" "$1"; }
ghcr_manifest_url() { printf '%s/v2/%s/manifests/%s' "$GHCR" "$1" "$2"; }

# fx_ghcr <repo> <tag>...: token plus a one-page tag list.
fx_ghcr() {
  local repo="$1" t json="" sep=""
  shift
  fx_text "$(ghcr_token_url "$repo")" '{"token":"dummy-ghcr-token"}'
  for t in "$@"; do json="$json$sep\"$t\""; sep=","; done
  fx_text "$(ghcr_tags_url "$repo")" "{\"name\":\"$repo\",\"tags\":[$json]}"
}
# fx_published_cue <repo> <tag>... : manifest HEAD answers 200.
fx_published_cue() {
  local repo="$1" t
  shift
  for t in "$@"; do fx_status "$(ghcr_manifest_url "$repo" "$t")" 200; done
}

PROXY=https://proxy.golang.org
fx_golist() { local path="$1"; shift; fx_text "$PROXY/$path/@v/list" "$(printf '%s\n' "$@")"; }
fx_goinfo() { local path="$1" t; shift; for t in "$@"; do fx_text "$PROXY/$path/@v/$t.info" "{\"Version\":\"$t\"}"; done; }

# rel_ok <repo> <tag> <asset>...: release download HEADs answer 200.
rel_url() { printf 'https://github.com/open-platform-model/%s/releases/download/%s/%s' "$1" "$2" "$3"; }
rel_ok() { local repo="$1" tag="$2" a; shift 2; for a in "$@"; do fx_status "$(rel_url "$repo" "$tag" "$a")" 200; done; }

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

# git repo helpers for title and body cases.
new_repo() {
  REPO="$T_ROOT/repo$FX_N"
  rm -rf "$REPO"
  mkdir -p "$REPO"
  git -c init.defaultBranch=main init -q "$REPO"
}
commit_all() { git -C "$REPO" add -A && git -C "$REPO" commit -q -m "${1:-commit}"; }

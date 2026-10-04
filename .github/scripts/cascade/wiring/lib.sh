# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the scripts that source this file
# Shared code for the release-cascade workflows (cascade-notify.yml,
# cascade-receive.yml, cascade-gates.yml): the fixed maps, payload
# validation, the cascade-PR filter, Notes and title-marker parsing, the
# title rank, the mention lint, the comment texts, the workflows guard, the
# action table and the gate status mapping. Design: workspace RELEASING.md,
# section "The cascade". Sourced, never run.
#
# The repo-name derivation and the org-github-ref guard are NOT here: they
# are the inline first step of every job, run before this file is checked
# out from the ref they guard.
#
# Tools: bash, coreutils, git, jq, grep with -P; gh through "${CASCADE_GH:-gh}".

ORG=open-platform-model
BOT_NAME='opm-cascade[bot]'
BOT_EMAIL='337635439+opm-cascade[bot]@users.noreply.github.com'
BOT_LOGIN='app/opm-cascade'
BRANCH=deps/cascade
NOTES_MARKER='<!-- cascade-notes: the bot keeps everything below this line -->'
# mention-guard's own pattern prefix (mention-guard.yml, the resolver's
# lib/prtext.sh): an @ that no word character or @ precedes, followed by a
# letter or digit, is a GitHub mention.
MENTION_RE='(?<![\w@])@[A-Za-z0-9]'
REPO_RE='^[A-Za-z0-9][A-Za-z0-9._-]*$'
# The resolver's tag pattern; every accepted tag also matches it.
RESOLVER_TAG_RE='^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$'
BODY_MAX=65000

# Which pushes the bot makes when main changed workflow files: strict pushes
# only updates that are no workflow change against main's tip nor against
# the old branch tip; tree only checks main's tip. A constant, never read
# from the environment. The sandbox cycle (E4c, 2026-10-04) decided tree:
# GitHub accepted an App push without the Workflows permission both for an
# in-place lease update across a workflow change on main and for a merge
# commit bringing main's workflow change in.
WF_GUARD_RULE=tree

# The five labels the bot may set or create, with RELEASING.md's colours and
# descriptions ("Labels").
BOT_LABELS="deps-cascade deps-cascade:conflict deps-cascade:hold deps-cascade:breaking need-human-review"

die() { printf '%s: %s\n' "${CASCADE_SCRIPT:-cascade}" "$1" >&2; exit "${2:-1}"; }
note() { printf '%s: %s\n' "${CASCADE_SCRIPT:-cascade}" "$1" >&2; }
gh_() { "${CASCADE_GH:-gh}" "$@"; }
sleep_() { "${CASCADE_SLEEP:-sleep}" "$@"; }

need_tools() {
  local t
  for t in "$@"; do
    if [ "$t" = gh ] && [ -n "${CASCADE_GH:-}" ]; then continue; fi
    command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"
  done
}

need_yq() {
  local v
  v=$(yq --version 2>&1) || die "missing tool: mikefarah yq v4 (yq --version failed)"
  case "$v" in
    *mikefarah*" v4."* | *mikefarah*" 4."*) ;;
    *) die "missing tool: mikefarah yq v4 (found: $v)" ;;
  esac
}

# safe_text <value>: every character outside [A-Za-z0-9._/-] replaced by ?,
# cut to 64 characters. Names untrusted input without a mention or Markdown.
safe_text() {
  local v="${1:0:64}"
  printf '%s' "${v//[^A-Za-z0-9._\/-]/?}"
}

# --- fixed maps ---------------------------------------------------------------

# notify_targets <source>: the repos a release of <source> dispatches to.
notify_targets() {
  case "$1" in
    core) echo "catalog_opm library" ;;
    catalog_opm) echo "library opm-operator cli" ;;
    library) echo "opm-operator cli" ;;
    opm-operator) echo "cli" ;;
    cli) echo "catalog_opm opm-operator" ;;
    cascade-sandbox-up) echo "cascade-sandbox-down" ;;
    *) return 1 ;;
  esac
}

# receiver_sources <receiver>: the payload sources the receiver accepts.
receiver_sources() {
  case "$1" in
    catalog_opm) echo "core cli" ;;
    library) echo "core catalog_opm" ;;
    opm-operator) echo "catalog_opm library cli" ;;
    cli) echo "catalog_opm library opm-operator" ;;
    cascade-sandbox-down) echo "cascade-sandbox-up" ;;
    *) return 1 ;;
  esac
}

# g3_upstreams <receiver>: the repos whose cascade state G3 checks. The
# release-tool edges from cli never count.
g3_upstreams() {
  case "$1" in
    catalog_opm) echo "core" ;;
    library) echo "core catalog_opm" ;;
    opm-operator) echo "catalog_opm library" ;;
    cli) echo "catalog_opm library opm-operator" ;;
    cascade-sandbox-down) echo "cascade-sandbox-up" ;;
    *) return 1 ;;
  esac
}

# tag_re <source>: the tag shape a release of <source> has.
tag_re() {
  if [ "$1" = catalog_opm ]; then
    printf '%s' '^opm-v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'
  else
    printf '%s' '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'
  fi
}

# valid_tag <source> <tag>
valid_tag() {
  local re
  re=$(tag_re "$1")
  [[ $2 =~ $re ]] && [[ $2 =~ $RESOLVER_TAG_RE ]]
}

# expect_pair <source> <tag>: the CASCADE_EXPECT pair for that release.
expect_pair() {
  case "$1" in
    core) printf 'opmodel.dev/core@v2=%s' "$2" ;;
    catalog_opm) printf 'opmodel.dev/catalogs/opm@v4=%s' "${2#opm-}" ;;
    library | opm-operator | cli | cascade-sandbox-up) printf 'github.com/open-platform-model/%s=%s' "$1" "$2" ;;
    *) return 1 ;;
  esac
}

# changelog_source <pin key>: "<repo> <tag prefix>" for the breaking check;
# exit 1 for a pin that is not a cascade repo's.
changelog_source() {
  case "$1" in
    opmodel.dev/core@v2) echo "core " ;;
    opmodel.dev/catalogs/opm@v4) echo "catalog_opm opm-" ;;
    github.com/open-platform-model/library) echo "library " ;;
    github.com/open-platform-model/opm-operator) echo "opm-operator " ;;
    github.com/open-platform-model/cli) echo "cli " ;;
    github.com/open-platform-model/cascade-sandbox-up) echo "cascade-sandbox-up " ;;
    *) return 1 ;;
  esac
}

# extra_sources <receiver>: CASCADE_EXTRA_SOURCES for the resolver's body.
# Only the sandbox receiver widens it, with a literal; never from input.
extra_sources() {
  if [ "$1" = cascade-sandbox-down ]; then echo cascade-sandbox-up; fi
}

label_color() {
  case "$1" in
    deps-cascade) echo 0366d6 ;;
    deps-cascade:conflict) echo b60205 ;;
    deps-cascade:hold) echo fbca04 ;;
    deps-cascade:breaking) echo d93f0b ;;
    need-human-review) echo e99695 ;;
    *) return 1 ;;
  esac
}

label_description() {
  case "$1" in
    deps-cascade) echo "Rolling upstream-pin PR opened by the release cascade" ;;
    deps-cascade:conflict) echo "The bot could not merge main into this cascade PR; a human resolves it" ;;
    deps-cascade:hold) echo "A human is working on this cascade PR; the bot does not push" ;;
    deps-cascade:breaking) echo "An upstream changelog in this PR announces a breaking change" ;;
    need-human-review) echo "Glue edits a human must review before merging" ;;
    *) return 1 ;;
  esac
}

is_bot_label() { [[ " $BOT_LABELS " == *" $1 "* ]]; }

# is_derived_path <path>: a merge conflict here takes main's side and the
# task regenerates the file.
is_derived_path() {
  case "${1##*/}" in go.mod | go.sum | manifest.go) return 0 ;; esac
  case "$1" in cue.mod/module.cue | */cue.mod/module.cue | internal/operator/dist/install.yaml) return 0 ;; esac
  return 1
}

# --- tokens and repo code -----------------------------------------------------

# run_repo_code <command...>: runs code from the calling repo (its tasks, its
# pins.sh) with every token and git auth header removed from its environment.
run_repo_code() {
  env -u GH_TOKEN -u GITHUB_TOKEN -u CASCADE_READ_TOKEN -u CASCADE_APP_TOKEN \
    -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0 -u GIT_CONFIG_PARAMETERS \
    "$@"
}

# auth_b64 <token>: the base64 of the basic-auth pair git sends.
auth_b64() { printf 'x-access-token:%s' "$1" | base64 | tr -d '\n'; }

# mask_read_token: masks the read header in the job log. Called once per
# step, with stdout going to the log.
mask_read_token() {
  if [ -n "${CASCADE_READ_TOKEN:-}" ]; then printf '::add-mask::%s\n' "$(auth_b64 "$CASCADE_READ_TOKEN")"; fi
}

# git_read <git args...>: a git call that may need to read a private repo.
# The GITHUB_TOKEN header reaches only this one git process, through the
# environment, never .git/config.
git_read() {
  if [ -n "${CASCADE_READ_TOKEN:-}" ]; then
    (
      GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.https://github.com/.extraheader \
        GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $(auth_b64 "$CASCADE_READ_TOKEN")" \
        GIT_TERMINAL_PROMPT=0 exec git "$@"
    )
  else
    GIT_TERMINAL_PROMPT=0 git "$@"
  fi
}

# --- payload ------------------------------------------------------------------

# validate_payload <receiver> <json>: exit 0 with P_SOURCE, P_TAGS (space
# joined) and P_EXPECT set, or exit 1 with P_REASON. Unknown keys are
# ignored. Exit 2 when the receiver is not a cascade receiver.
validate_payload() {
  local recv="$1" json="$2" allowed src re n last
  P_SOURCE="" P_TAGS="" P_EXPECT="" P_REASON=""
  allowed=$(receiver_sources "$recv") || return 2
  if ! jq -e 'type == "object"' <<<"$json" >/dev/null 2>&1; then
    P_REASON="the payload is not a JSON object"
    return 1
  fi
  if ! jq -e '(.source | type) == "string"' <<<"$json" >/dev/null; then
    P_REASON="source is not a string"
    return 1
  fi
  src=$(jq -r '.source' <<<"$json")
  if [[ " $allowed " != *" $src "* ]]; then
    P_REASON="source \`$(safe_text "$src")\` is not accepted by $recv"
    return 1
  fi
  if ! jq -e '(.tags | type) == "array" and (.tags | length) >= 1 and (.tags | length) <= 8 and all(.tags[]; type == "string")' <<<"$json" >/dev/null; then
    P_REASON="tags is not an array of 1 to 8 strings"
    return 1
  fi
  re=$(tag_re "$src")
  n=$(jq --arg re "$re" --arg rre "$RESOLVER_TAG_RE" '[.tags[] | select((test($re) and test($rre)) | not)] | length' <<<"$json") \
    || { P_REASON="tags cannot be checked"; return 1; }
  if [ "$n" != 0 ]; then
    P_REASON="$n tag(s) do not match the $(safe_text "$src") tag shape"
    return 1
  fi
  P_SOURCE="$src"
  P_TAGS=$(jq -r '.tags | join(" ")' <<<"$json")
  last=$(jq -r '.tags[-1]' <<<"$json")
  P_EXPECT=$(expect_pair "$src" "$last")
}

# --- the cascade PR -----------------------------------------------------------

PR_FIELDS=number,title,body,labels,headRefOid,isCrossRepository,headRepositoryOwner,author

# cascade_pr <repo>: prints the open cascade PR as one JSON object, or
# nothing. Only the bot's own same-repo PR on deps/cascade counts: a fork PR
# or a human PR from a branch of that name is never read further. Exit 1 on
# an API error or more than one match.
cascade_pr() {
  local out n
  out=$(gh_ pr list -R "$ORG/$1" --head "$BRANCH" --base main --state open --json "$PR_FIELDS") \
    || { note "cannot list the open $BRANCH PRs of $1"; return 1; }
  out=$(jq -c --arg org "$ORG" --arg bot "$BOT_LOGIN" \
    '[.[] | select(.isCrossRepository == false and .headRepositoryOwner.login == $org and .author.login == $bot)]' <<<"$out") \
    || { note "cannot parse the PR list of $1"; return 1; }
  n=$(jq length <<<"$out")
  case "$n" in
    0) ;;
    1) jq -c '.[0]' <<<"$out" ;;
    *) note "more than one cascade PR in $1"; return 1 ;;
  esac
}

# --- Notes and the title marker -----------------------------------------------

# extract_notes <body file> <notes file>: every byte after the first line
# equal to the Notes marker (one trailing CR ignored), or the whole body
# when no such line exists.
extract_notes() {
  local n
  n=$(grep -n -m 1 -x -F -e "$NOTES_MARKER" -e "$NOTES_MARKER"$'\r' -- "$1" | cut -d: -f1) || true
  if [ -n "$n" ]; then
    tail -n "+$((n + 1))" -- "$1" >"$2"
  else
    cat -- "$1" >"$2"
  fi
}

# body_above_notes <body file>: the body up to, not including, the Notes
# marker line (the whole body without one).
body_above_notes() {
  local n
  n=$(grep -n -m 1 -x -F -e "$NOTES_MARKER" -e "$NOTES_MARKER"$'\r' -- "$1" | cut -d: -f1) || true
  if [ -n "$n" ]; then head -n "$((n - 1))" -- "$1"; else cat -- "$1"; fi
}

# title_marker <body file>: the <T> of the first `<!-- cascade-title: <T> -->`
# line above the Notes marker, one trailing CR ignored; empty without one.
title_marker() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ "$line" != "$NOTES_MARKER" ] || return 0
    if [[ $line =~ ^'<!-- cascade-title: '(.*)' -->'$ ]]; then
      printf '%s' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$1"
}

# --- titles -------------------------------------------------------------------

# type_rank <title>: ci 1, test 2, fix 3, feat 4, anything else 0.
type_rank() {
  if [[ $1 =~ ^([a-z]+)(\([^\)]*\))?(!)?:\  ]]; then
    case "${BASH_REMATCH[1]}" in
      ci) echo 1 ;;
      test) echo 2 ;;
      fix) echo 3 ;;
      feat) echo 4 ;;
      *) echo 0 ;;
    esac
  else
    echo 0
  fi
}

# type_scope <title>: the type and scope, `fix(deps)` for `fix(deps): x`.
type_scope() { printf '%s' "${1%%: *}"; }

# final_title <has pr 0|1> <T_old> <T_marker> <T_computed>: sets FINAL_TITLE
# and TITLE_RISE (1 when a kept human title ranks below the computed class
# that rose since the last run). Once a human retitled the PR, its title is
# kept for good.
final_title() {
  local pr="$1" old="$2" marker="$3" computed="$4"
  TITLE_RISE=0
  if [ "$pr" = 1 ] && [ -n "$marker" ] && [ "$old" != "$marker" ]; then
    FINAL_TITLE="$old"
    if [ "$(type_rank "$computed")" -gt "$(type_rank "$old")" ] && [ "$(type_rank "$computed")" -gt "$(type_rank "$marker")" ]; then
      TITLE_RISE=1
    fi
  else
    FINAL_TITLE="$computed"
  fi
}

# Computed titles are one of the resolver's three types.
COMPUTED_TITLE_RE='^(fix\(deps\)|test\(fixtures\)|ci\(deps\)): '

# --- the mention lint ---------------------------------------------------------

# lint_text <surface> <text>: exit 1 naming the surface when the text holds
# a bare mention, or when grep cannot run the pattern.
lint_text() {
  local rc=0
  printf '%s\n' "$2" | grep -qP -- "$MENTION_RE" || rc=$?
  case "$rc" in
    0) note "mention lint: the $1 holds a bare mention"; return 1 ;;
    1) return 0 ;;
    *) note "mention lint: grep -P failed on the $1 (exit $rc)"; return 1 ;;
  esac
}

# --- comments -----------------------------------------------------------------

# path_list <path>...: each path, made safe, in backticks, comma-separated.
path_list() {
  local p out="" sep=""
  for p in "$@"; do
    out="$out$sep\`$(safe_text "$p")\`"
    sep=", "
  done
  printf '%s' "$out"
}

# comment_text <kind> [<value>]: the fixed comment texts. <value> is a path
# list (conflict-merge, conflict-workflows), a type (title-rise) or a PR
# number (continued).
comment_text() {
  case "$1" in
    conflict-merge) printf '%s' "The cascade could not merge \`main\` into this branch. Conflicting paths: $2. Run \`git merge origin/main\` locally, resolve, push, then remove \`deps-cascade:conflict\`." ;;
    conflict-workflows) printf '%s' "\`main\` changed workflow files since this branch's last update ($2), or this branch changes workflow files. The cascade App has no Workflows permission, so it cannot update this branch. Run \`git merge origin/main\` locally, push, then remove \`deps-cascade:conflict\`." ;;
    recreate) printf '%s' "\`main\` changed workflow files since this branch was built. The cascade App has no Workflows permission, so it rebuilt the branch under a new PR. The Notes were carried over." ;;
    close) printf '%s' "No diff against \`main\` any more. Closed by the release cascade." ;;
    too-long) printf '%s' "The PR body is over GitHub's 65000-byte limit because of the Notes. The bot never truncates Notes, so it cannot update this PR. Trim the text below the Notes marker; the next run continues." ;;
    title-rise) printf '%s' "The bot now titles this change \`$2\`, which ranks above the current title. A human set the current title, so the bot keeps it. Retitle the PR if this change should release." ;;
    continued) printf '%s' "Continued in #$2." ;;
    *) return 1 ;;
  esac
}

# --- the workflows guard and the action table ---------------------------------

# wf_guard <rule> <mode> <D1> <D2>: the action a planned push becomes, given
# the workflow files that differ from main's tip (D1) and from the old tip in
# place (D2, newline lists). Prints push, recreate, conflict or error.
wf_guard() {
  local rule="$1" mode="$2" d1="$3" d2="$4"
  case "$mode" in
    fresh)
      if [ -z "$d1" ]; then echo push; else echo error; fi ;;
    rebuild)
      if [ -n "$d1" ]; then echo error
      elif [ -z "$d2" ] || [ "$rule" = tree ]; then echo push
      else echo recreate
      fi ;;
    recreate)
      if [ -z "$d1" ]; then echo recreate; else echo error; fi ;;
    merge)
      if [ -n "$d1" ]; then echo conflict
      elif [ -z "$d2" ] || [ "$rule" = tree ]; then echo push
      else echo conflict
      fi ;;
    *) echo error ;;
  esac
}

# action_for <mode> <too long 0|1> <tree equals main 0|1> <pr open 0|1> <OLD set 0|1>
action_for() {
  case "$1" in
    skip) echo skip; return ;;
    conflict) echo conflict; return ;;
  esac
  if [ "$2" = 1 ]; then echo too_long
  elif [ "$3" = 1 ] && { [ "$4" = 1 ] || [ "$5" = 1 ]; }; then echo close
  elif [ "$3" = 1 ]; then echo noop
  else echo push
  fi
}

# --- gate statuses ------------------------------------------------------------

# truncate_desc <text>: at most 140 characters, cut with an ellipsis.
truncate_desc() {
  local LC_ALL=C.UTF-8 d="$1"
  if [ "${#d}" -gt 140 ]; then d="${d:0:139}…"; fi
  printf '%s' "$d"
}

# status_for <mode warn|enforce> <state ok|problem|error> <message>: prints
# "<state>\t<description>".
status_for() {
  local st desc
  case "$2:$1" in
    ok:*) st=success desc="$3" ;;
    problem:warn) st=success desc="WARN: $3" ;;
    problem:enforce) st=failure desc="$3" ;;
    error:warn) st=success desc="WARN: gate could not run, see the run" ;;
    error:enforce) st=error desc="could not evaluate, see the run" ;;
    *) return 1 ;;
  esac
  printf '%s\t%s\n' "$st" "$(truncate_desc "$desc")"
}

valid_mode() { [ "$1" = warn ] || [ "$1" = enforce ]; }

# --- scratch files ------------------------------------------------------------

# check_scratch <dir>: refuses a scratch directory inside the repo checkout
# or the org .github checkout.
check_scratch() {
  local t r o
  [ -n "$1" ] || die "CASCADE_T is not set"
  t=$(realpath -m -- "$1")
  r=$(realpath -m -- "${CASCADE_REPO_DIR:-repo}")
  o=$(realpath -m -- "$WIRING_DIR/../../../..")
  case "$t/" in "$r"/* | "$o"/*) die "CASCADE_T \`$1\` is inside a checkout" ;; esac
}

WIRING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

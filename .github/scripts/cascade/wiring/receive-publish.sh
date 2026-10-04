#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# The receiver's publish job (cascade-receive.yml): verifies the plan the
# compute job uploaded, then pushes deps/cascade under a lease and creates,
# edits, recreates, closes or labels the cascade PR (workspace RELEASING.md,
# sections "Two-job split", "One rolling PR per repo", "Labels"). It runs
# only git, gh, jq and these scripts, never repo code. The plan is
# untrusted: compute ran repo code, so everything that can be re-derived is.
#
# Usage:
#   receive-publish.sh verify   before the App token exists (GITHUB_TOKEN)
#   receive-publish.sh act      with the App token
#
# Environment: CASCADE_PUBLISH_GATES_ONLY (the action's required gates-only
# input, the caller's own dispatch input: only exactly false goes on; true
# and anything else are refused before the dry-run input, the plan or any
# API call, because a gates-only run never publishes and compute's outputs,
# which ran repo code, cannot be trusted to say so),
# CASCADE_PUBLISH_DRY_RUN (the action's required dry-run input:
# only exactly false publishes; true skips with publish=false; anything else
# is refused), CASCADE_REPO (the Guard step's repo name), CASCADE_T (default
# $RUNNER_TEMP/cascade; the plan artifact is in $CASCADE_T/plan),
# CASCADE_REPO_DIR (default $PWD/repo), GH_TOKEN (GITHUB_TOKEN for verify,
# the App token for act), CASCADE_READ_TOKEN (verify only),
# CASCADE_LABELS_MANAGED (act; true: labels must already exist).
#
# verify writes publish=true to GITHUB_OUTPUT, or publish=false (exit 0) when
# the dry-run input is true or the cascade PR got deps-cascade:hold since
# compute.
#
# Exit status: 0 success; 1 a refused plan (verify, before any token is
# minted), a failed push or API call, or the too_long action (act); 2 usage.
#
# Tools: bash, coreutils, git, jq, grep -P, base64; gh through
# "${CASCADE_GH:-gh}".
set -euo pipefail
export LC_ALL=C
CASCADE_SCRIPT=receive-publish.sh
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[ $# -eq 1 ] || die "usage: receive-publish.sh verify|act" 2
REPO="${CASCADE_REPO:-}"
[ -n "$REPO" ] || die "CASCADE_REPO is not set" 2
T="${CASCADE_T:-${RUNNER_TEMP:-}/cascade}"
check_scratch "$T"
RD=$(realpath -m -- "${CASCADE_REPO_DIR:-$PWD/repo}")
P="$T/plan"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"
V="$T/verified"
g() { git -C "$RD" "$@"; }
refuse() { die "refusing the plan: $1"; }
pj() { jq -r "$1" "$P/plan.json"; }

ACTIONS=" push recreate close conflict too_long "

# dry_run_switch: the caller's dry-run input, the receiver's stop switch
# (CASCADE_DRY_RUN live only at exactly false). Read here, in .github code,
# so a caller's if: that is wrong cannot make a dry run publish. Prints
# false (publish) or true (a dry run); refuses any other value.
dry_run_switch() {
  case "${CASCADE_PUBLISH_DRY_RUN-}" in
    false | true) printf '%s' "$CASCADE_PUBLISH_DRY_RUN" ;;
    *) refuse "the dry-run input must be true or false, not \`$(safe_text "${CASCADE_PUBLISH_DRY_RUN-}")\`" ;;
  esac
}

# gates_only_switch: the caller's gates-only input. Returns 0 only when it is
# exactly false; refuses otherwise.
gates_only_switch() {
  case "${CASCADE_PUBLISH_GATES_ONLY-}" in
    false) return 0 ;;
    true) refuse "a gates-only run never publishes" ;;
    *) refuse "the gates-only input must be true or false, not \`$(safe_text "${CASCADE_PUBLISH_GATES_ONLY-}")\`" ;;
  esac
}

verify() {
  local switch
  gates_only_switch
  switch=$(dry_run_switch) || exit 1
  if [ "$switch" != false ]; then
    echo "::notice::dry run (the dry-run input is true); nothing is published"
    printf 'publish=false\n' >>"$GITHUB_OUTPUT"
    exit 0
  fi
  need_tools git jq gh
  mask_read_token
  [ -f "$P/plan.json" ] || refuse "no plan.json in the cascade-plan artifact"
  jq -e 'type == "object"' "$P/plan.json" >/dev/null 2>&1 || refuse "plan.json is not a JSON object"
  rm -rf "$V"
  mkdir -p "$V"

  local action old new title computed reason l n live live_n
  [ "$(pj '.effective_dry_run')" = false ] || refuse "the plan is a dry run"
  action=$(pj '.action')
  [[ $ACTIONS == *" $action "* ]] || refuse "unknown action \`$(safe_text "$action")\`"
  jq -e '(.labels | type) == "array" and all(.labels[]; type == "string") and (.carry_labels | type) == "array" and (.conflict_files | type) == "array"' \
    "$P/plan.json" >/dev/null || refuse "labels, carry_labels and conflict_files must be arrays"
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    is_bot_label "$l" || refuse "label \`$(safe_text "$l")\` is not one of the bot's labels"
  done < <(jq -r '.labels[]' "$P/plan.json")

  # The cascade PR, re-derived with the same fork-proof filter.
  live=$(cascade_pr "$REPO") || refuse "cannot read the cascade PR"
  printf '%s' "$live" >"$V/pr.json"
  live_n=""
  [ -z "$live" ] || live_n=$(jq -r .number <<<"$live")
  n=$(pj '.pr_number // ""')
  [ "$n" = "$live_n" ] || refuse "the plan names PR \`$(safe_text "$n")\`, the cascade PR is \`${live_n:-none}\`"
  # A hold is stop switch 1, used as documented: not a failed run. No
  # verified plan is written, the mint and act steps are skipped
  # (publish=false), and act alone would refuse.
  if [ -n "$live" ] && jq -e 'any(.labels[]; .name == "deps-cascade:hold")' <<<"$live" >/dev/null; then
    echo "::notice::the cascade PR got deps-cascade:hold since compute; nothing is published"
    printf 'publish=false\n' >>"$GITHUB_OUTPUT"
    exit 0
  fi

  # The remote tip must still be the one compute built on.
  old=$(pj '.old_tip')
  new=$(pj '.new_tip')
  [[ $old =~ ^([0-9a-f]{40})?$ ]] && [[ $new =~ ^([0-9a-f]{40})?$ ]] || refuse "old_tip and new_tip must be commit ids"
  git_read -C "$RD" fetch -q origin "+refs/heads/main:refs/remotes/origin/main" || die "cannot fetch origin main"
  local remote
  remote=$(git_read -C "$RD" ls-remote origin "refs/heads/$BRANCH" | cut -f1) || die "git ls-remote of origin failed"
  [ "$remote" = "$old" ] || die "$BRANCH moved since compute; the next run retries"
  if [ -n "$old" ]; then
    git_read -C "$RD" fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" || die "cannot fetch origin $BRANCH"
  fi

  case "$action" in
    push | recreate)
      [ -n "$new" ] || refuse "$action without a new tip"
      if [ "$new" = "$old" ]; then
        [ "$action" = push ] || refuse "recreate needs a new tip"
        g update-ref refs/cascade/new "$old"
      else
        [ -f "$P/cascade.bundle" ] || refuse "no cascade.bundle"
        g bundle verify -q "$P/cascade.bundle" >/dev/null 2>&1 || refuse "cascade.bundle does not verify against this repo"
        g fetch -q "$P/cascade.bundle" "HEAD:refs/cascade/new" || refuse "cannot fetch cascade.bundle"
        [ "$(g rev-parse refs/cascade/new)" = "$new" ] || refuse "the bundle's tip is not new_tip"
      fi
      # The workflows guard again, with plain git.
      local d1 d2=""
      d1=$(g diff --name-only origin/main refs/cascade/new -- .github/workflows/)
      [ -z "$d1" ] || refuse "the new tip differs from main in workflow files: ${d1//$'\n'/ }"
      if [ "$action" = push ] && [ -n "$old" ] && [ "$WF_GUARD_RULE" = strict ]; then
        d2=$(g diff --name-only "$old" refs/cascade/new -- .github/workflows/)
        [ -z "$d2" ] || refuse "the in-place update changes workflow files: ${d2//$'\n'/ }"
      fi
      # The title, recomputed from the live PR.
      computed=$(pj '.title_computed')
      title=$(pj '.title')
      [[ $computed =~ $COMPUTED_TITLE_RE ]] || refuse "title_computed is not a cascade title"
      lint_text "computed title" "$computed" || refuse "title_computed fails the mention lint"
      local has_pr=0 old_title="" marker=""
      if [ -n "$live" ]; then
        has_pr=1
        old_title=$(jq -j .title <<<"$live")
        jq -j '.body // ""' <<<"$live" >"$V/live-body.md"
        marker=$(title_marker "$V/live-body.md")
      fi
      final_title "$has_pr" "$old_title" "$marker" "$computed"
      [ "$FINAL_TITLE" = "$title" ] || refuse "the planned title does not recompute"
      printf '%s' "$FINAL_TITLE" >"$V/title"
      printf '%s' "$TITLE_RISE" >"$V/rise"
      # The body above the Notes marker is the bot's text.
      [ -f "$P/body.md" ] || refuse "no body.md"
      [ "$(wc -c <"$P/body.md")" -le "$BODY_MAX" ] || refuse "body.md is over $BODY_MAX bytes"
      lint_text "body" "$(body_above_notes "$P/body.md")" || refuse "the body fails the mention lint"
      cp "$P/body.md" "$V/body.md"
      if [ "$TITLE_RISE" = 1 ]; then comment_text title-rise "$(type_scope "$computed")" >"$V/c-title-rise.md"; fi
      ;;
  esac

  # Labels carried by recreate come from the live PR, not the plan.
  : >"$V/carry"
  if [ "$action" = recreate ] && [ -n "$live" ]; then
    jq -r '[.labels[].name | select(. == "deps-cascade:breaking" or . == "need-human-review")] | join(",")' <<<"$live" >"$V/carry"
  fi

  # Every comment is built here from fixed texts and linted.
  case "$action" in
    conflict)
      reason=$(pj '.conflict_reason')
      local -a files=()
      mapfile -t files < <(jq -r '.conflict_files[] | strings' "$P/plan.json")
      case "$reason" in
        merge) comment_text conflict-merge "$(path_list "${files[@]}")" >"$V/c-conflict.md" ;;
        workflows) comment_text conflict-workflows "$(path_list "${files[@]}")" >"$V/c-conflict.md" ;;
        *) refuse "unknown conflict_reason \`$(safe_text "$reason")\`" ;;
      esac
      ;;
    recreate) comment_text recreate >"$V/c-recreate.md" ;;
    close) comment_text close >"$V/c-close.md" ;;
    too_long) comment_text too-long >"$V/c-too-long.md" ;;
  esac
  local c
  for c in "$V"/c-*.md; do
    [ -f "$c" ] || continue
    lint_text "comment ${c##*/}" "$(cat "$c")" || refuse "a comment fails the mention lint"
  done
  jq -c '{action, old_tip, new_tip, labels}' "$P/plan.json" >"$V/plan.json"
  printf '%s' "$live_n" >"$V/pr"
  printf 'publish=true\n' >>"$GITHUB_OUTPUT"
  echo "plan verified: $action"
}

# --- act ----------------------------------------------------------------------

vf() { jq -r "$1" "$V/plan.json"; }

# push_lease <expected old tip, empty for absent> <refspec>
push_lease() {
  g push -q "--force-with-lease=refs/heads/$BRANCH:$1" origin "$2"
}

ensure_labels() {
  local l have
  if [ "${CASCADE_LABELS_MANAGED:-false}" = true ]; then
    have=$(gh_ label list -R "$ORG/$REPO" --limit 500 --json name --jq '.[].name') || die "cannot list the labels"
    for l in $BOT_LABELS; do
      grep -qxF -- "$l" <<<"$have" || die "label $l is missing: declare it in .github/labels.yml"
    done
  else
    for l in $BOT_LABELS; do
      gh_ label create "$l" -R "$ORG/$REPO" --color "$(label_color "$l")" --description "$(label_description "$l")" --force >/dev/null \
        || die "cannot create label $l"
    done
  fi
}

# live_labels <pr>: the PR's labels, one per line, from the verified PR.
live_labels() { jq -r '.labels[].name' "$V/pr.json" 2>/dev/null || true; }

# add_labels <pr> <label>...: adds those not already present.
add_labels() {
  local n="$1" l missing=""
  shift
  local have
  have=$(live_labels)
  for l in "$@"; do
    [ -n "$l" ] || continue
    grep -qxF -- "$l" <<<"$have" || missing="${missing:+$missing,}$l"
  done
  [ -z "$missing" ] || gh_ pr edit "$n" -R "$ORG/$REPO" --add-label "$missing" >/dev/null || die "cannot label #$n"
}

create_pr() {
  local url n
  url=$(gh_ pr create -R "$ORG/$REPO" --head "$BRANCH" --base main --title "$(cat "$V/title")" --body-file "$V/body.md") \
    || die "cannot create the cascade PR"
  n="${url##*/}"
  n="${n%%[^0-9]*}"
  [[ $n =~ ^[0-9]+$ ]] || die "cannot read the new PR number from \`$(safe_text "$url")\`"
  printf '%s' "$n"
}

comment() { gh_ pr comment "$1" -R "$ORG/$REPO" --body-file "$2" >/dev/null || die "cannot comment on #$1"; }

act() {
  gates_only_switch
  [ "$(dry_run_switch)" = false ] || die "the dry-run input is not false; act publishes nothing"
  need_tools git jq gh
  [ -f "$V/plan.json" ] || die "verify has not run"
  [ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN (the App token) is not set"
  local b64
  b64=$(auth_b64 "$GH_TOKEN")
  echo "::add-mask::$b64"
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.https://github.com/.extraheader
  export GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $b64"
  export GIT_TERMINAL_PROMPT=0

  local action old new pr labels=() newpr
  action=$(vf .action)
  old=$(vf .old_tip)
  new=$(vf .new_tip)
  pr=$(cat "$V/pr")
  mapfile -t labels < <(vf '.labels[]')
  ensure_labels

  case "$action" in
    push)
      if [ "$new" != "$old" ]; then push_lease "$old" "refs/cascade/new:refs/heads/$BRANCH" || die "the lease push was rejected; the next run retries"; fi
      if [ -z "$pr" ]; then
        pr=$(create_pr)
        echo "opened #$pr"
      else
        if [ "$(jq -j .title "$V/pr.json")" != "$(cat "$V/title")" ]; then
          gh_ pr edit "$pr" -R "$ORG/$REPO" --title "$(cat "$V/title")" >/dev/null || die "cannot retitle #$pr"
        fi
        if ! cmp -s "$V/live-body.md" "$V/body.md"; then
          gh_ pr edit "$pr" -R "$ORG/$REPO" --body-file "$V/body.md" >/dev/null || die "cannot edit the body of #$pr"
        fi
        echo "updated #$pr"
      fi
      add_labels "$pr" "${labels[@]}"
      if live_labels | grep -qxF deps-cascade:conflict; then
        gh_ pr edit "$pr" -R "$ORG/$REPO" --remove-label deps-cascade:conflict >/dev/null || die "cannot remove the conflict label"
      fi
      if [ "$(cat "$V/rise")" = 1 ]; then comment "$pr" "$V/c-title-rise.md"; fi
      ;;
    recreate)
      if [ -n "$pr" ]; then
        comment "$pr" "$V/c-recreate.md"
        gh_ pr close "$pr" -R "$ORG/$REPO" >/dev/null || die "cannot close #$pr"
      fi
      if [ -n "$old" ]; then push_lease "$old" ":refs/heads/$BRANCH" || die "the lease delete was rejected; the next run retries"; fi
      push_lease "" "refs/cascade/new:refs/heads/$BRANCH" || die "the push of the rebuilt branch was rejected; the next run retries"
      newpr=$(create_pr)
      echo "opened #$newpr"
      local carry=()
      IFS=, read -r -a carry <<<"$(cat "$V/carry")" || true
      : >"$V/pr.json"
      add_labels "$newpr" "${labels[@]}" "${carry[@]}"
      if [ -n "$pr" ]; then
        comment_text continued "$newpr" >"$V/c-continued.md"
        lint_text "comment" "$(cat "$V/c-continued.md")" || die "the comment fails the mention lint"
        comment "$pr" "$V/c-continued.md"
      fi
      if [ "$(cat "$V/rise")" = 1 ]; then comment "$newpr" "$V/c-title-rise.md"; fi
      ;;
    close)
      if [ -n "$pr" ]; then
        comment "$pr" "$V/c-close.md"
        gh_ pr close "$pr" -R "$ORG/$REPO" >/dev/null || die "cannot close #$pr"
      fi
      if [ -n "$old" ] && ! push_lease "$old" ":refs/heads/$BRANCH"; then
        echo "::warning::the lease delete of $BRANCH was rejected; the branch stays and the next run decides"
      fi
      ;;
    conflict)
      [ -n "$pr" ] || { echo "::warning::conflict without an open cascade PR; nothing to label"; return 0; }
      local had=0
      if live_labels | grep -qxF deps-cascade:conflict; then had=1; fi
      add_labels "$pr" deps-cascade:conflict deps-cascade
      if [ "$had" = 0 ]; then comment "$pr" "$V/c-conflict.md"; fi
      echo "conflict on #$pr; nothing pushed"
      ;;
    too_long)
      if [ -n "$pr" ]; then
        local last
        last=$(gh_ api --paginate "repos/$ORG/$REPO/issues/$pr/comments" --jq '.[] | select(.user.login == "opm-cascade[bot]") | .body' \
          | tail -n 1) || die "cannot read the comments of #$pr"
        if [ "$last" != "$(cat "$V/c-too-long.md")" ]; then comment "$pr" "$V/c-too-long.md"; fi
      fi
      die "the PR body is over $BODY_MAX bytes because of the Notes; a human trims them"
      ;;
    *) die "unknown action $action" ;;
  esac
}

case "$1" in
  verify) verify ;;
  act) act ;;
  *) die "usage: receive-publish.sh verify|act" 2 ;;
esac

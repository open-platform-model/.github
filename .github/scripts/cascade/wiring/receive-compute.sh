#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# The receiver's compute job (cascade-receive.yml): runs the calling repo's
# `task -x deps:cascade` on the rolling deps/cascade branch, commits the
# result as the bot, and plans what publish does: push, recreate, close,
# conflict or too_long (workspace RELEASING.md, sections "The receiver",
# "One rolling PR per repo", "Additive commits", "Title from diff class").
# This job runs repo code and holds no secret; publish verifies the plan.
#
# Usage: receive-compute.sh <step>, one workflow step each, in this order:
#   init     checks tools, modes and the receiver; the effective dry run
#   payload  validates a repository_dispatch payload (dropped when invalid)
#   gates    G2 and G3 on open release PRs (gates-eval.sh); in a gates-only
#            run also the summary and action=gates-only
#   state    the cascade PR, the remote deps/cascade tip, the mode
#   prepare  the bot identity and the branch (merge mode merges main)
#   notes    the old PR's Notes and title marker
#   run      the task, the commit, the title check
#   text     body, final title, labels (with the breaking check)
#   action   the action table and the workflows guard
#   plan     plan.json, the bundle, diff.patch, the job outputs
#   summary  the job summary
#
# Environment: CASCADE_REPO (the Guard step's repo name), CASCADE_T (default
# $RUNNER_TEMP/cascade), CASCADE_REPO_DIR (default $PWD/repo),
# CASCADE_RESOLVER (default the resolver beside this script),
# CASCADE_DRY_RUN, CASCADE_GATES_ONLY, CASCADE_REF, CASCADE_EVENT,
# CASCADE_PAYLOAD, CASCADE_G2_MODE, CASCADE_G3_MODE; GH_TOKEN and
# CASCADE_READ_TOKEN (GITHUB_TOKEN) on gates, state and text only.
# Writes GITHUB_OUTPUT, GITHUB_STEP_SUMMARY and files under CASCADE_T.
#
# Exit status: 0 success, 1 failure (the job fails), 2 usage.
#
# Tools: bash, coreutils, git, jq, grep -P, go-task, mikefarah yq v4; gh
# through "${CASCADE_GH:-gh}".
set -euo pipefail
export LC_ALL=C
CASCADE_SCRIPT=receive-compute.sh
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[ $# -eq 1 ] || die "usage: receive-compute.sh <step>" 2
STEP="$1"
REPO="${CASCADE_REPO:-}"
[ -n "$REPO" ] || die "CASCADE_REPO is not set" 2
T="${CASCADE_T:-${RUNNER_TEMP:-}/cascade}"
check_scratch "$T"
RD=$(realpath -m -- "${CASCADE_REPO_DIR:-$PWD/repo}")
export CASCADE_RESOLVER="${CASCADE_RESOLVER:-$(cd "$WIRING_DIR/.." && pwd)/cascade-resolve.sh}"
ST="$T/state"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

st_set() { mkdir -p "$ST"; printf '%s' "$2" >"$ST/$1"; }
st_get() { if [ -f "$ST/$1" ]; then cat "$ST/$1"; fi; }
output() { printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"; }
# trigger <line>: one line for the summary's trigger section.
trigger() { mkdir -p "$T"; printf '%s\n' "$1" >>"$T/trigger.md"; }
g() { git -C "$RD" "$@"; }
# bot_git: git as the bot, author and committer, whatever the environment
# says (the identity is also in the repo's config, as the contract asks).
bot_git() {
  GIT_AUTHOR_NAME="$BOT_NAME" GIT_AUTHOR_EMAIL="$BOT_EMAIL" \
    GIT_COMMITTER_NAME="$BOT_NAME" GIT_COMMITTER_EMAIL="$BOT_EMAIL" git -C "$RD" "$@"
}

# repo_task <task> [VAR=value...]: runs a cascade task in the repo with no
# token in its environment. Exit status is the task's.
repo_task() {
  local task="$1"
  shift
  (cd "$RD" && run_repo_code env CASCADE_BASE=origin/main "$@" task -x "$task")
}

# payload_env: the accepted payload as VAR=value lines (none for a sweep).
payload_env() {
  local v
  v=$(st_get expect)
  if [ -n "$v" ]; then printf 'CASCADE_EXPECT=%s\n' "$v"; fi
  v=$(st_get source)
  if [ -n "$v" ]; then printf 'CASCADE_SOURCE=%s\n' "$v"; fi
  v=$(st_get tags)
  if [ -n "$v" ]; then printf 'CASCADE_TAGS=%s\n' "$v"; fi
}

step_init() {
  need_tools git jq task
  need_yq
  [ -x "$CASCADE_RESOLVER" ] || die "resolver not found: $CASCADE_RESOLVER"
  receiver_sources "$REPO" >/dev/null || die "not a cascade receiver: $REPO"
  valid_mode "${CASCADE_G2_MODE:-}" || die "g2-mode must be warn or enforce"
  valid_mode "${CASCADE_G3_MODE:-}" || die "g3-mode must be warn or enforce"
  [ -d "$RD/.git" ] || die "no repo checkout at $RD"
  rm -rf "$T"
  mkdir -p "$T" "$ST"
  local dry=false
  # A run from any ref but main is always a dry run: the cascade
  # Environment would refuse its publish job anyway.
  if [ "${CASCADE_DRY_RUN:-true}" != false ] || [ "${CASCADE_REF:-}" != refs/heads/main ]; then dry=true; fi
  st_set dry_run "$dry"
  st_set gates_only "$([ "${CASCADE_GATES_ONLY:-false}" = true ] && echo true || echo false)"
  output dry_run "$dry"
  trigger "- Event: \`$(safe_text "${CASCADE_EVENT:-unknown}")\` on \`$(safe_text "${CASCADE_REF:-}")\`; dry run: $dry"
}

step_payload() {
  st_set extra "$(extra_sources "$REPO")"
  if [ "${CASCADE_EVENT:-}" != repository_dispatch ]; then
    trigger "- Payload: none (sweep or manual run)"
    return 0
  fi
  local rc=0
  validate_payload "$REPO" "${CASCADE_PAYLOAD:-}" || rc=$?
  case "$rc" in
    0)
      st_set source "$P_SOURCE"
      st_set tags "$P_TAGS"
      st_set expect "$P_EXPECT"
      trigger "- Payload accepted: \`$P_SOURCE\` \`${P_TAGS// /\` \`}\`"
      ;;
    1)
      echo "::warning::payload dropped: $P_REASON; continuing as a sweep"
      trigger "- Payload dropped: $P_REASON; the run continues as a sweep"
      ;;
    *) die "not a cascade receiver: $REPO" ;;
  esac
}

step_gates() {
  mask_read_token
  local rc=0
  bash "$WIRING_DIR/gates-eval.sh" || rc=$?
  if [ "$(st_get gates_only)" = true ]; then
    output action gates-only
    {
      echo "## Deps cascade: gates only"
      echo
      cat "$T/trigger.md" 2>/dev/null || true
      echo
      gates_table
    } >>"$GITHUB_STEP_SUMMARY"
  fi
  if [ "$rc" != 0 ]; then
    # No gates.json: the gates job posts error in enforce mode. A real run
    # still moves pins; a gates-only run has nothing else to do.
    [ "$(st_get gates_only)" != true ] || die "gate evaluation failed"
    echo "::warning::gate evaluation failed; the gates job reports it"
  fi
}

# gates_table: the gate results as Markdown lines (for the summary).
gates_table() {
  if [ ! -f "$T/gates.json" ]; then
    echo "- Gates: not evaluated"
    return 0
  fi
  if [ "$(jq length "$T/gates.json")" = 0 ]; then
    echo "- Gates: no open release PR"
    return 0
  fi
  jq -r '.[] | "- Release PR #\(.pr) (`\(.sha[0:12])`): freshness \(.freshness.state) (\(.freshness.msg)); settled \(.settled.state) (\(.settled.msg))"' "$T/gates.json"
}

step_state() {
  mask_read_token
  local pr old mode n labels
  pr=$(cascade_pr "$REPO") || die "cannot read the cascade PR"
  printf '%s' "$pr" >"$T/pr.json"
  old=$(git_read -C "$RD" ls-remote origin refs/heads/$BRANCH | cut -f1) || die "git ls-remote of origin failed"
  git_read -C "$RD" fetch -q origin "+refs/heads/main:refs/remotes/origin/main" || die "cannot fetch origin main"
  if [ -n "$old" ]; then
    git_read -C "$RD" fetch -q origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" || die "cannot fetch origin $BRANCH"
    [ "$(g rev-parse "refs/remotes/origin/$BRANCH")" = "$old" ] || die "$BRANCH moved while it was fetched; the next run retries"
  fi
  st_set old "$old"
  if [ -n "$pr" ]; then
    n=$(jq -r .number <<<"$pr")
    st_set pr "$n"
    jq -j '.title' <<<"$pr" >"$T/old-title"
    jq -j '.body // ""' <<<"$pr" >"$T/old-body.md"
    labels=$(jq -r '[.labels[].name] | join(",")' <<<"$pr")
    st_set old_labels "$labels"
  else
    st_set pr ""
  fi
  if [ -n "$pr" ] && [[ ",$(st_get old_labels)," == *",deps-cascade:hold,"* ]]; then
    mode=skip
  elif [ -z "$old" ]; then
    mode=fresh
  elif [ -z "$pr" ]; then
    mode=recreate
  else
    # A human who amends or rebases a bot commit becomes its committer, so
    # the branch is merged, never rebuilt: no human work is reset away.
    mode=rebuild
    while IFS=$'\t' read -r ae ce; do
      if [ "$ae" != "$BOT_EMAIL" ] || [ "$ce" != "$BOT_EMAIL" ]; then mode=merge; break; fi
    done < <(g log --format='%ae%x09%ce' "origin/main..$old")
  fi
  st_set mode "$mode"
  echo "mode $mode, cascade PR ${n:-none}, remote $BRANCH ${old:-absent}"
}

step_prepare() {
  local mode f files=() other=() conflicted
  mode=$(st_get mode)
  [ "$mode" != skip ] || return 0
  g config user.name "$BOT_NAME"
  g config user.email "$BOT_EMAIL"
  case "$mode" in
    fresh | rebuild | recreate)
      g checkout -q -B "$BRANCH" origin/main
      ;;
    merge)
      g checkout -q -B "$BRANCH" "origin/$BRANCH"
      if ! bot_git merge -q --no-edit -m "Merge origin/main into $BRANCH" origin/main >/dev/null 2>&1; then
        conflicted=$(g diff --name-only --diff-filter=U)
        [ -n "$conflicted" ] || die "git merge of origin/main failed without a conflict"
        while IFS= read -r f; do
          if is_derived_path "$f"; then files+=("$f"); else other+=("$f"); fi
        done <<<"$conflicted"
        if [ "${#other[@]}" -gt 0 ]; then
          g merge --abort
          st_set mode conflict
          st_set conflict_reason merge
          printf '%s\n' "${other[@]}" >"$ST/conflict_files"
          echo "merge conflict outside derived files: ${other[*]}"
          return 0
        fi
        # Only derived files conflict: take main's side; the task
        # regenerates them.
        for f in "${files[@]}"; do
          if g cat-file -e "origin/main:$f" 2>/dev/null; then
            g checkout -q --theirs -- "$f"
            g add -- "$f"
          else
            g rm -q -- "$f"
          fi
        done
        bot_git commit -q --no-edit -m "Merge origin/main into $BRANCH"
      fi
      ;;
    *) die "unknown mode $mode" ;;
  esac
}

step_notes() {
  [ -n "$(st_get pr)" ] || return 0
  extract_notes "$T/old-body.md" "$T/notes.md"
  st_set marker "$(title_marker "$T/old-body.md")"
}

# title_of: the computed title of the current tree (empty for no diff).
title_of() {
  local out rc=0
  out=$(repo_task deps:cascade:title) || rc=$?
  case "$rc" in
    0) printf '%s' "$out" ;;
    3) ;;
    *) die "task -x deps:cascade:title exited $rc" ;;
  esac
}

step_run() {
  local mode rc=0 dirty computed
  mode=$(st_get mode)
  case "$mode" in skip | conflict) return 0 ;; esac
  [ -z "$(g status --porcelain --untracked-files=all)" ] || die "the repo tree is dirty before the task runs"
  local -a penv=()
  mapfile -t penv < <(payload_env)
  repo_task deps:cascade "${penv[@]}" || rc=$?
  case "$rc" in
    0)
      dirty=$(title_of)
      [ -n "$dirty" ] || die "the task changed the tree but the title sees no diff"
      lint_text "commit subject" "$dirty" || die "the commit subject fails the mention lint"
      g add -A
      bot_git commit -q -m "$dirty"
      computed=$(title_of)
      [ "$computed" = "$dirty" ] || die "the title after the commit (\`$computed\`) differs from the title before it (\`$dirty\`)"
      ;;
    3)
      computed=$(title_of)
      ;;
    *) die "task -x deps:cascade exited $rc" ;;
  esac
  # A rebuilt bot-only branch whose tree and base did not change keeps its
  # old commit, so a sweep with nothing new pushes nothing.
  local old
  old=$(st_get old)
  if [ "$mode" = rebuild ] && [ -n "$old" ] && [ "$(g rev-parse "HEAD^{tree}")" = "$(g rev-parse "$old^{tree}")" ] \
    && [ "$(g rev-parse "$old^")" = "$(g rev-parse origin/main)" ] 2>/dev/null; then
    g reset -q --hard "$old"
  fi
  st_set task_rc "$rc"
  st_set computed "$computed"
}

# breaking_check: exit 0 and print yes or no; exit 1 on an API or tool
# error; exit 2 when the repo's pins.sh fails.
breaking_check() {
  local m k from to repo prefix rels tag v brk c1 c2
  local pm pw
  m=$(g merge-base origin/main HEAD)
  pm=$(cd "$RD" && run_repo_code .tasks/cascade/pins.sh "$m") || { note ".tasks/cascade/pins.sh $m failed"; return 2; }
  pw=$(cd "$RD" && run_repo_code .tasks/cascade/pins.sh WORKTREE) || { note ".tasks/cascade/pins.sh WORKTREE failed"; return 2; }
  local -A FROM=() TO=()
  while IFS=$'\t' read -r k _ _ v _; do [ -z "$k" ] || FROM[$k]="$v"; done <<<"$pm"
  while IFS=$'\t' read -r k _ _ v _; do [ -z "$k" ] || TO[$k]="$v"; done <<<"$pw"
  for k in "${!TO[@]}"; do
    from="${FROM[$k]:-}" to="${TO[$k]}"
    [ -n "$from" ] && [ "$from" != "$to" ] || continue
    read -r repo prefix <<<"$(changelog_source "$k")" || continue
    [ -n "$repo" ] || continue
    rels=$(gh_ api --paginate "repos/$ORG/$repo/releases" --jq '.[] | select(.draft | not) | [.tag_name, ((.body // "") | test("BREAKING CHANGES"))] | @tsv') || return 1
    while IFS=$'\t' read -r tag brk; do
      [ -n "$tag" ] || continue
      [[ $tag == "$prefix"* ]] || continue
      v="${tag#"$prefix"}"
      c1=$("$CASCADE_RESOLVER" semver-cmp "$from" "$v" 2>/dev/null) || continue
      c2=$("$CASCADE_RESOLVER" semver-cmp "$v" "$to" 2>/dev/null) || continue
      if [ "$c1" = -1 ] && [ "$c2" != 1 ] && [ "$brk" = true ]; then
        echo yes
        return 0
      fi
    done <<<"$rels"
  done
  echo no
}

step_text() {
  local mode computed labels marker_labels l rise breaking
  mode=$(st_get mode)
  case "$mode" in skip | conflict) return 0 ;; esac
  mask_read_token
  computed=$(st_get computed)
  local -a benv=()
  mapfile -t benv < <(payload_env)
  [ -z "$(st_get extra)" ] || benv+=("CASCADE_EXTRA_SOURCES=$(st_get extra)")
  [ ! -f "$T/notes.md" ] || benv+=("CASCADE_NOTES_FILE=$T/notes.md")
  repo_task deps:cascade:body "${benv[@]}" >"$T/body.md" || die "task -x deps:cascade:body failed"
  if [ "$(wc -c <"$T/body.md")" -gt "$BODY_MAX" ]; then st_set too_long 1; else st_set too_long 0; fi

  local has_pr=0 old_title=""
  if [ -n "$(st_get pr)" ]; then has_pr=1; old_title=$(cat "$T/old-title"); fi
  final_title "$has_pr" "$old_title" "$(st_get marker)" "$computed"
  rise="$TITLE_RISE"
  st_set title "$FINAL_TITLE"
  st_set rise "$rise"

  labels="deps-cascade"
  marker_labels=$(sed -n '2s/^<!-- cascade-labels: \(.*\) -->$/\1/p' "$T/body.md")
  local -a parts=()
  IFS=, read -r -a parts <<<"$marker_labels" || true
  for l in "${parts[@]}"; do
    [ -n "$l" ] || continue
    [[ ",$labels," == *",$l,"* ]] || labels="$labels,$l"
  done
  if [ -n "$computed" ]; then
    local brc=0
    breaking=$(breaking_check) || brc=$?
    case "$brc" in
      0) if [ "$breaking" = yes ]; then labels="$labels,deps-cascade:breaking"; fi ;;
      2)
        echo "::warning::the breaking check failed: .tasks/cascade/pins.sh failed; no label added, the next run retries"
        trigger "- Warning: the breaking check failed: .tasks/cascade/pins.sh failed"
        ;;
      *)
        echo "::warning::the breaking check could not read the upstream releases; no label added, the next run retries"
        trigger "- Warning: the breaking check could not read the upstream releases"
        ;;
    esac
  fi
  st_set labels "$labels"
}

step_action() {
  local mode action tree_eq=0 has_pr=0 old_set=0 old d1="" d2="" guard reason="" carry=""
  mode=$(st_get mode)
  old=$(st_get old)
  [ -z "$(st_get pr)" ] || has_pr=1
  [ -z "$old" ] || old_set=1
  if [ "$mode" != skip ] && [ "$mode" != conflict ]; then
    if g diff --quiet origin/main HEAD; then tree_eq=1; fi
  fi
  action=$(action_for "$mode" "$(st_get too_long)" "$tree_eq" "$has_pr" "$old_set")
  if [ "$mode" = conflict ]; then reason=$(st_get conflict_reason); fi
  if [ "$action" = push ]; then
    d1=$(g diff --name-only origin/main HEAD -- .github/workflows/)
    if [ -n "$old" ] && { [ "$mode" = rebuild ] || [ "$mode" = merge ]; }; then
      d2=$(g diff --name-only "$old" HEAD -- .github/workflows/)
    fi
    guard=$(wf_guard "$WF_GUARD_RULE" "$mode" "$d1" "$d2")
    case "$guard" in
      push | recreate) action="$guard" ;;
      conflict)
        action=conflict
        reason=workflows
        printf '%s\n%s\n' "$d1" "$d2" | sed '/^$/d' | sort -u >"$ST/conflict_files"
        ;;
      *) die "the planned push changes workflow files in mode $mode, which the task never does: ${d1//$'\n'/ }" ;;
    esac
  fi
  if [ "$action" = recreate ] && [ "$has_pr" = 1 ]; then
    local l
    for l in deps-cascade:breaking need-human-review; do
      if [[ ",$(st_get old_labels)," == *",$l,"* ]]; then carry="${carry:+$carry,}$l"; fi
    done
  fi
  st_set action "$action"
  st_set conflict_reason "$reason"
  st_set carry "$carry"
  echo "action $action"
}

step_plan() {
  local action new old mode
  action=$(st_get action)
  mode=$(st_get mode)
  old=$(st_get old)
  new=""
  if [ "$mode" != skip ] && [ "$mode" != conflict ]; then new=$(g rev-parse HEAD); fi
  local cfiles="[]"
  if [ -f "$ST/conflict_files" ]; then cfiles=$(jq -R . "$ST/conflict_files" | jq -sc .); fi
  jq -n \
    --arg mode "$mode" --arg action "$action" --arg old "$old" --arg new "$new" \
    --arg title "$(st_get title)" --arg computed "$(st_get computed)" --arg marker "$(st_get marker)" \
    --arg labels "$(st_get labels)" --arg pr "$(st_get pr)" --arg reason "$(st_get conflict_reason)" \
    --argjson files "$cfiles" --arg carry "$(st_get carry)" --arg dry "$(st_get dry_run)" \
    '{mode: $mode, action: $action, old_tip: $old, new_tip: $new, title: $title, title_computed: $computed,
      title_marker_old: $marker, labels: ($labels | split(",") | map(select(. != ""))),
      pr_number: (if $pr == "" then null else ($pr | tonumber) end), conflict_reason: $reason,
      conflict_files: $files, carry_labels: ($carry | split(",") | map(select(. != ""))),
      effective_dry_run: ($dry == "true")}' >"$T/plan.json"
  if { [ "$action" = push ] || [ "$action" = recreate ]; } && [ "$new" != "$old" ]; then
    if [ "$mode" = merge ] && [ -n "$old" ]; then
      g bundle create -q "$T/cascade.bundle" HEAD ^origin/main "^$old"
    else
      g bundle create -q "$T/cascade.bundle" HEAD ^origin/main
    fi
  fi
  if [ "$(st_get dry_run)" = true ] && [ -n "$new" ]; then
    g diff --binary origin/main HEAD >"$T/diff.patch"
  fi
  [ -f "$T/body.md" ] || : >"$T/body.md"
  output action "$action"
  output mode "$mode"
}

# fence <file>: a backtick fence longer than any backtick run in the file.
fence() {
  local longest
  longest=$(grep -o '`\+' "$1" 2>/dev/null | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
  [ "$longest" -ge 3 ] || longest=2
  printf '%*s' "$((longest + 1))" '' | tr ' ' '`'
}

step_summary() {
  local f status
  status=$(
    echo "- Mode: \`$(st_get mode)\`; action: \`$(st_get action)\`"
    echo "- Old tip: \`$(st_get old)\`; new tip: \`$([ ! -f "$T/plan.json" ] || jq -r .new_tip "$T/plan.json")\`"
    echo "- Labels: \`$(st_get labels)\`"
  )
  lint_text "summary" "$status" || die "the summary fails the mention lint"
  {
    echo "## Deps cascade"
    echo
    if [ "$(st_get dry_run)" = true ]; then echo "**DRY RUN: nothing was pushed**"; echo; fi
    cat "$T/trigger.md" 2>/dev/null || true
    echo "$status"
    echo "- Title: $(st_get title)"
    gates_table
    if [ -s "$T/body.md" ]; then
      f=$(fence "$T/body.md")
      echo
      echo "<details><summary>PR body</summary>"
      echo
      echo "${f}markdown"
      cat "$T/body.md"
      echo "$f"
      echo
      echo "</details>"
    fi
    if [ -n "$(st_get mode)" ] && [ "$(st_get mode)" != skip ] && [ "$(st_get mode)" != conflict ]; then
      echo
      echo "### Diff against main"
      echo
      g diff --stat origin/main HEAD >"$T/diff.stat"
      g diff origin/main HEAD >"$T/diff.full"
      f=$(fence "$T/diff.full")
      echo "${f}text"
      cat "$T/diff.stat"
      echo "$f"
      echo
      echo "${f}diff"
      head -c 204800 "$T/diff.full"
      echo
      echo "$f"
      if [ "$(wc -c <"$T/diff.full")" -gt 204800 ]; then echo "truncated, full diff in the cascade-plan artifact"; fi
    fi
  } >>"$GITHUB_STEP_SUMMARY"
}

case "$STEP" in
  init) step_init ;;
  payload) step_payload ;;
  gates) step_gates ;;
  state) step_state ;;
  prepare) step_prepare ;;
  notes) step_notes ;;
  run) step_run ;;
  text) step_text ;;
  action) step_action ;;
  plan) step_plan ;;
  summary) step_summary ;;
  *) die "unknown step $STEP" 2 ;;
esac

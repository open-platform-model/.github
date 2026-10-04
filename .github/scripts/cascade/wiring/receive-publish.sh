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
# CASCADE_EVENT and CASCADE_PAYLOAD (verify: the run's event name and its
# client_payload as JSON, read from the event, never from compute),
# CASCADE_LABELS_MANAGED (act; true: labels must already exist).
#
# verify bounds what a push may carry: the bot's own commits (at most a merge
# of main and one task commit, authored and committed by the bot) may change
# only the receiver's allow-listed paths (publish_paths in lib.sh), and a push
# never drops a commit the bot did not make. It renders the PR title, body
# and labels itself, with the resolver and the .github mirror of the
# receiver's pins.sh and classes (pins.sh here, lib.sh), in a scratch
# worktree of the new tip under CASCADE_T: compute's body.md and titles are
# hints only.
#
# verify writes publish=true to GITHUB_OUTPUT, or publish=false (exit 0) when
# the dry-run input is true or the cascade PR got deps-cascade:hold since
# compute.
#
# Exit status: 0 success; 1 a refused plan (verify, before any token is
# minted), a failed push or API call, or the too_long action (act); 2 usage.
#
# Tools: bash, coreutils, git (2.38 or later, for merge-tree --write-tree),
# jq, grep -P, base64; gh through "${CASCADE_GH:-gh}".
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
RESOLVER="$(cd "$WIRING_DIR/.." && pwd)/cascade-resolve.sh"
TREE="$T/tree"

# bot_only <range>: exit 0 when every commit in the range has the bot as
# author and committer.
bot_only() {
  local out
  out=$(g log --format='%ae%x09%ce' "$1") || die "git log $1 failed"
  ! grep -vxF -- "$BOT_EMAIL"$'\t'"$BOT_EMAIL" <<<"$out" | grep -q .
}

# check_paths <commit> <parent>: a bot commit changes only allow-listed
# files, in place: status M, the same mode before and after, a regular file
# (no symlink 120000, no gitlink 160000).
check_paths() {
  local c="$1" p="$2" meta path om nm st
  while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
    read -r om nm _ _ st <<<"${meta#:}"
    [ "$st" = M ] || refuse "commit ${c:0:12} adds, deletes or retypes \`$(safe_text "$path")\` (status $(safe_text "$st")); the cascade task only edits files"
    [ "$om" = "$nm" ] || refuse "commit ${c:0:12} changes the mode of \`$(safe_text "$path")\`"
    case "$nm" in
      100644 | 100755) ;;
      *) refuse "commit ${c:0:12} writes \`$(safe_text "$path")\` as mode $(safe_text "$nm") (a symlink or gitlink)" ;;
    esac
    publish_path_ok "$REPO" "$path" || refuse "commit ${c:0:12} changes \`$(safe_text "$path")\`, which the cascade task of $REPO never writes"
  done < <(g diff-tree -r -z --raw --no-renames "$p" "$c")
}

# check_merge <commit> <first parent> <second parent>: a bot merge brings
# main in and nothing else: its tree is git's own merge of its parents, but
# for derived files, which carry main's content.
check_merge() {
  local c="$1" p1="$2" p2="$3" out rc=0 mt path a b
  g merge-base --is-ancestor "$p2" origin/main || refuse "merge commit ${c:0:12} does not merge main"
  out=$(g merge-tree --write-tree --no-messages "$p1" "$p2") || rc=$?
  case "$rc" in 0 | 1) ;; *) refuse "cannot recompute merge commit ${c:0:12} (git merge-tree exited $rc)" ;; esac
  mt="${out%%$'\n'*}"
  [[ $mt =~ ^[0-9a-f]{40}$ ]] || refuse "cannot recompute merge commit ${c:0:12}"
  while IFS= read -r -d '' path; do
    is_derived_path "$path" || refuse "merge commit ${c:0:12} differs from the merge of its parents in \`$(safe_text "$path")\`"
    a=$(g rev-parse -q --verify "$c:$path" || true)
    b=$(g rev-parse -q --verify "$p2:$path" || true)
    [ "$a" = "$b" ] || refuse "merge commit ${c:0:12} does not take main's \`$(safe_text "$path")\`"
  done < <(g diff-tree -r -z --name-only --no-renames "$mt" "$c")
}

# check_increment <action> <old tip>: the bot's own commits in the push (the
# new tip's commits that neither main nor, for a fast-forward, the old tip
# has) are at most two, and each passes check_paths or check_merge. A push
# that replaces the old tip may drop only bot commits. recreate rebuilds the
# branch on main, so it is refused outright when the old tip holds a commit
# the bot did not make (close keeps such a branch, and the next run, finding
# it without a PR, plans recreate).
check_increment() {
  local action="$1" old="$2" n c p1 p2 extra ae ce
  local -a range=(refs/cascade/new ^origin/main)
  if [ "$action" = recreate ] && [ -n "$old" ]; then
    bot_only "origin/main..$old" \
      || refuse "recreate would drop commits on $BRANCH the bot did not make; delete the branch or open a PR from it"
  elif [ -n "$old" ]; then
    if g merge-base --is-ancestor "$old" refs/cascade/new; then
      range+=("^$old")
    else
      bot_only "origin/main..$old" || refuse "the push would drop commits on $BRANCH the bot did not make"
    fi
  fi
  n=$(g rev-list --count "${range[@]}")
  [ "$n" -le 2 ] || refuse "the push adds $n commits; the bot makes at most a merge of main and one task commit"
  while read -r c p1 p2 extra; do
    [ -n "$p1" ] || refuse "commit ${c:0:12} is a root commit"
    [ -z "$extra" ] || refuse "commit ${c:0:12} has more than two parents"
    IFS=$'\t' read -r ae ce < <(g log -1 --format='%ae%x09%ce' "$c")
    if [ "$ae" != "$BOT_EMAIL" ] || [ "$ce" != "$BOT_EMAIL" ]; then
      refuse "commit ${c:0:12} is not the bot's (author $(safe_text "$ae"), committer $(safe_text "$ce"))"
    fi
    if [ -n "$p2" ]; then check_merge "$c" "$p1" "$p2"; else check_paths "$c" "$p1"; fi
  done < <(g rev-list --parents "${range[@]}")
}

# filter_warnings <in> <out>: the task's warning lines publish lets into the
# body above the Notes marker: at most 100, each at most 500 printable ASCII
# bytes or tabs, with no HTML, no Markdown link or image, no URL, no issue
# reference and no bare mention. A line without a tab gets the key -. One
# added line counts the dropped ones.
filter_warnings() {
  local line n=0 dropped=0 markup='[][<>]'
  : >"$2"
  if [ -f "$1" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      [ -n "$line" ] || continue
      if [ "$n" -ge 100 ] || [ "${#line}" -gt 500 ] || [[ $line =~ [^[:print:]$'\t'] ]] || [[ $line =~ $markup ]] \
        || [[ $line == *://* ]] || [[ $line =~ \#[0-9] ]] || ! lint_text "warning" "$line" 2>/dev/null; then
        dropped=$((dropped + 1))
        continue
      fi
      [[ $line == *$'\t'* ]] || line="-"$'\t'"$line"
      printf '%s\n' "$line" >>"$2"
      n=$((n + 1))
    done <"$1"
  fi
  if [ "$dropped" -gt 0 ]; then
    printf -- '-\t%s warning line(s) from the task were dropped by the publish filter\n' "$dropped" >>"$2"
  fi
}

# resolver_text <title|body> [<flag>...]: the resolver's title or body of the
# new tip's worktree, with the .github mirrors; stdout is the text.
resolver_text() {
  local what="$1"
  shift
  env -u CASCADE_WARNINGS -u CASCADE_SOURCE -u CASCADE_TAGS -u CASCADE_NOTES_FILE -u CASCADE_EXTRA_SOURCES \
    CASCADE_PINS_REPO="$REPO" "${TEXT_ENV[@]}" \
    "$RESOLVER" "$what" --classes "$V/classes" --pins "$WIRING_DIR/pins.sh" --base origin/main --repo-root "$TREE" "$@"
}

# derive_breaking: sets BRK to yes or no from the mirrored pins at the merge
# base and the new tip and the upstream releases (read here, with the job's
# token), or to unknown when a release list could not be read.
derive_breaking() {
  local m pm pw k from to repo prefix tag brk v c1 c2 unknown=0
  local -A FROM=() TO=()
  BRK=no
  m=$(g merge-base origin/main refs/cascade/new) || refuse "no merge base between main and the new tip"
  pm=$(cd "$TREE" && CASCADE_PINS_REPO="$REPO" "$WIRING_DIR/pins.sh" "$m") || refuse "the pin mirror failed at the merge base"
  pw=$(cd "$TREE" && CASCADE_PINS_REPO="$REPO" "$WIRING_DIR/pins.sh" HEAD) || refuse "the pin mirror failed at the new tip"
  while IFS=$'\t' read -r k _ _ v _; do [ -z "$k" ] || FROM[$k]="$v"; done <<<"$pm"
  while IFS=$'\t' read -r k _ _ v _; do [ -z "$k" ] || TO[$k]="$v"; done <<<"$pw"
  mkdir -p "$V/releases"
  for k in "${!TO[@]}"; do
    from="${FROM[$k]:-}" to="${TO[$k]}"
    [ -n "$from" ] && [ "$from" != "$to" ] || continue
    read -r repo prefix <<<"$(changelog_source "$k")" || continue
    [ -n "$repo" ] || continue
    if [ ! -f "$V/releases/$repo.tsv" ] && [ ! -f "$V/releases/$repo.failed" ]; then
      if ! gh_ api --paginate "repos/$ORG/$repo/releases" --jq '.[] | select(.draft | not) | [.tag_name, ((.body // "") | test("BREAKING CHANGES"))] | @tsv' \
        >"$V/releases/$repo.tsv"; then
        rm -f "$V/releases/$repo.tsv"
        : >"$V/releases/$repo.failed"
      fi
    fi
    if [ -f "$V/releases/$repo.failed" ]; then unknown=1; continue; fi
    while IFS=$'\t' read -r tag brk; do
      [ -n "$tag" ] && [[ $tag == "$prefix"* ]] || continue
      v="${tag#"$prefix"}"
      c1=$("$RESOLVER" semver-cmp "$from" "$v" 2>/dev/null) || continue
      c2=$("$RESOLVER" semver-cmp "$v" "$to" 2>/dev/null) || continue
      if [ "$c1" = -1 ] && [ "$c2" != 1 ] && [ "$brk" = true ]; then BRK=yes; return 0; fi
    done <"$V/releases/$repo.tsv"
  done
  [ "$unknown" = 0 ] || BRK=unknown
}

# drop_tree: removes the scratch worktree of the new tip.
drop_tree() {
  rm -rf "$TREE"
  g worktree prune
}

# derive_text <live PR JSON>: renders the title, body and labels of a push or
# recreate from .github code into $V; sets COMPUTED_TITLE and LABELS.
derive_text() {
  local live="$1" computed planned rc=0 marker_labels l
  drop_tree
  g -c core.hooksPath=/dev/null worktree add -q --detach "$TREE" refs/cascade/new >/dev/null 2>&1 \
    || refuse "cannot check the new tip out"
  receiver_classes "$REPO" >"$V/classes" || refuse "no classes mirror for $REPO"
  filter_warnings "$P/warnings.tsv" "$V/warnings.tsv"
  TEXT_ENV=()
  if [ "${CASCADE_EVENT:-}" = repository_dispatch ] && validate_payload "$REPO" "${CASCADE_PAYLOAD:-}"; then
    TEXT_ENV+=("CASCADE_SOURCE=$P_SOURCE" "CASCADE_TAGS=$P_TAGS")
  fi
  [ -z "$(extra_sources "$REPO")" ] || TEXT_ENV+=("CASCADE_EXTRA_SOURCES=$(extra_sources "$REPO")")
  if [ -n "$live" ]; then
    extract_notes "$V/live-body.md" "$V/notes.md"
    TEXT_ENV+=("CASCADE_NOTES_FILE=$V/notes.md")
  fi
  computed=$(resolver_text title) || rc=$?
  case "$rc" in
    0) ;;
    3) refuse "the new tip has no diff against main" ;;
    *) refuse "the title of the new tip cannot be computed (resolver exit $rc)" ;;
  esac
  resolver_text body --warnings "$V/warnings.tsv" >"$V/body.md" 2>"$V/body.err" \
    || refuse "the body of the new tip cannot be computed: $(head -c 300 "$V/body.err")"
  [ "$(wc -c <"$V/body.md")" -le "$BODY_MAX" ] || refuse "the body is over $BODY_MAX bytes; compute should have planned too_long"
  lint_text "body" "$(body_above_notes "$V/body.md")" || refuse "the body fails the mention lint"
  planned=$(pj '.title_computed')
  [ "$planned" = "$computed" ] || echo "::notice::the plan's computed title differs from the one publish derived; publish uses its own"
  COMPUTED_TITLE="$computed"

  # Labels: deps-cascade, the body's labels marker, and the breaking check.
  LABELS="deps-cascade"
  marker_labels=$(sed -n '2s/^<!-- cascade-labels: \(.*\) -->$/\1/p' "$V/body.md")
  local -a parts=()
  IFS=, read -r -a parts <<<"$marker_labels" || true
  for l in "${parts[@]}"; do
    [ -n "$l" ] || continue
    is_bot_label "$l" || refuse "the labels marker names \`$(safe_text "$l")\`"
    [[ ",$LABELS," == *",$l,"* ]] || LABELS="$LABELS,$l"
  done
  derive_breaking
  case "$BRK" in
    yes) LABELS="$LABELS,deps-cascade:breaking" ;;
    unknown)
      if jq -e '.labels | index("deps-cascade:breaking")' "$P/plan.json" >/dev/null; then
        LABELS="$LABELS,deps-cascade:breaking"
      fi
      echo "::notice::the breaking check could not read an upstream's releases; the plan's own claim is kept"
      ;;
  esac
  drop_tree
}

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
      # What the bot's own commits change, and who made them.
      check_increment "$action" "$old"
      # Title, body and labels from .github code; the plan's are hints.
      local has_pr=0 old_title="" marker=""
      : >"$V/live-body.md"
      if [ -n "$live" ]; then
        has_pr=1
        old_title=$(jq -j .title <<<"$live")
        jq -j '.body // ""' <<<"$live" >"$V/live-body.md"
        marker=$(title_marker "$V/live-body.md")
      fi
      derive_text "$live"
      computed="$COMPUTED_TITLE"
      final_title "$has_pr" "$old_title" "$marker" "$computed"
      title=$(pj '.title')
      [ "$FINAL_TITLE" = "$title" ] || echo "::notice::the plan's title differs from the one publish derived; publish uses its own"
      printf '%s' "$FINAL_TITLE" >"$V/title"
      printf '%s' "$TITLE_RISE" >"$V/rise"
      if [ "$TITLE_RISE" = 1 ]; then comment_text title-rise "$(type_scope "$computed")" >"$V/c-title-rise.md"; fi
      ;;
  esac

  # A branch holding a commit the bot did not make is never deleted.
  : >"$V/keep-branch"
  if [ "$action" = close ] && [ -n "$old" ] && ! bot_only "origin/main..$old"; then
    printf 'keep' >"$V/keep-branch"
  fi

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
  # Labels: derived for a push or recreate; the plan's are only checked above.
  if [ "$action" = push ] || [ "$action" = recreate ]; then
    jq -c --arg l "$LABELS" '{action, old_tip, new_tip, labels: ($l | split(","))}' "$P/plan.json" >"$V/plan.json"
  else
    jq -c '{action, old_tip, new_tip, labels}' "$P/plan.json" >"$V/plan.json"
  fi
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
      if [ -n "$old" ] && [ -s "$V/keep-branch" ]; then
        echo "::notice::$BRANCH holds a commit the bot did not make; the branch stays"
      elif [ -n "$old" ] && ! push_lease "$old" ":refs/heads/$BRANCH"; then
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

# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# receive-publish.sh: the refusals before the mint, and push, recreate,
# close, conflict and too_long against the bare origin.

REL_ARGS=(api --paginate repos/open-platform-model/cascade-sandbox-up/releases --jq '.[] | select(.draft | not) | [.tag_name, ((.body // "") | test("BREAKING CHANGES"))] | @tsv')
NO_BREAK=$'v0.3.0\tfalse\nv0.2.0\tfalse\nv0.1.0\tfalse'
M='<!-- cascade-notes: the bot keeps everything below this line -->'
SBX=open-platform-model/cascade-sandbox-down

bot_branch() { seed_commit deps/cascade bot UPSTREAM_VERSION "$1" "fix(deps): bump up to $1"; }
body_with() { printf '<!-- cascade-title: %s -->\n## Notes\n\n%s\n%s' "$1" "$M" "$2" >"$FX/body.in"; }

# publish_job: a fresh checkout and scratch dir for the publish job, with the
# compute job's artifact downloaded into it.
publish_job() {
  PWS="$FX/pws"
  rm -rf "$PWS"
  mkdir -p "$PWS/t/plan"
  git clone -q "file://$ORIGIN" "$PWS/repo"
  local f
  for f in plan.json body.md warnings.tsv cascade.bundle; do
    if [ -f "$CASCADE_T/$f" ]; then cp "$CASCADE_T/$f" "$PWS/t/plan/"; fi
  done
  PV="$PWS/t/verified"
}
# PUBLISH_DRY_RUN is the action's dry-run input (default false); the value
# "<unset>" leaves it out of the environment.
# PUBLISH_GATES_ONLY is the action's gates-only input (default false), with
# "<unset>" the same way. git is the wiring shim (test/shim/git), so the
# tag-on-main check answers from $FX/git.
publish() {
  # env takes its -u options before any assignment.
  local -a un=() set=()
  if [ "${PUBLISH_DRY_RUN-}" = "<unset>" ]; then un+=(-u CASCADE_PUBLISH_DRY_RUN); else set+=(CASCADE_PUBLISH_DRY_RUN="${PUBLISH_DRY_RUN-false}"); fi
  if [ "${PUBLISH_GATES_ONLY-}" = "<unset>" ]; then un+=(-u CASCADE_PUBLISH_GATES_ONLY); else set+=(CASCADE_PUBLISH_GATES_ONLY="${PUBLISH_GATES_ONLY-false}"); fi
  run env -C "$PWS" "${un[@]}" "${set[@]}" PATH="$W_HERE/shim:$PATH" CASCADE_REPO=cascade-sandbox-down CASCADE_T="$PWS/t" CASCADE_REPO_DIR="$PWS/repo" \
    GH_TOKEN=ghs_appTokenForTests CASCADE_LABELS_MANAGED="${LABELS_MANAGED:-false}" bash "$PUBLISH" "$1"
}
# edit_plan <jq filter>: tampers with the downloaded plan.
edit_plan() { jq "$1" "$PWS/t/plan/plan.json" >"$FX/p.json" && mv "$FX/p.json" "$PWS/t/plan/plan.json"; }
mutations() { grep -vE '^(pr list|api --paginate repos/[^ ]+/releases)' "$GHFX/log" || true; }
# gh_reset_p: gh_reset, still answering the upstream's release list, which
# verify reads for the breaking check.
gh_reset_p() { gh_reset; gh_accept "api --paginate repos/open-platform-model/cascade-sandbox-up/releases --jq *"; }

# --- fresh: push and open the PR ----------------------------------------------
new_fx; mk_toy; fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
compute "${COMPUTE_STEPS[@]}"
publish_job
gh_prs '[]'
publish verify
check "push: verify accepts the plan" bash -c '[ "$1" = 0 ] && [[ $2 == "plan verified: push" ]] && grep -qx publish=true "$3"' _ "$RC" "$OUT" "$GITHUB_OUTPUT"
gh_accept "label create * -R $SBX --color * --description * --force"
gh_fx 0 "https://github.com/$SBX/pull/12" -- pr create -R "$SBX" --head deps/cascade --base main --title "fix(deps): bump up to v0.2.0" --body-file "$PV/body.md"
gh_accept "pr edit 12 -R $SBX --add-label deps-cascade"
publish act
check "push: act succeeds" bash -c '[ "$1" = 0 ] && [[ $2 == *"opened #12"* ]]' _ "$RC" "$OUT"
check "push: the branch is pushed under the empty lease" test "$(origin_tip deps/cascade)" = "$(plan .new_tip)"
check "push: the five labels are created with their colours" bash -c '
  grep -qx "label create deps-cascade:conflict -R $2 --color b60205 --description The bot could not merge main into this cascade PR; a human resolves it --force" "$1" &&
  [ "$(grep -c "^label create " "$1")" = 5 ]' _ "$GHFX/log" "$SBX"
check "push: the planned labels are added" gh_called "pr edit 12 -R $SBX --add-label deps-cascade"
check "push: the token never reaches a command line" bash -c '! grep -q ghs_appTokenForTests "$1" && ! grep -q "$(printf "x-access-token:ghs_appTokenForTests" | base64)" "$1"' _ "$GHFX/log"
check "push: the push header is masked" bash -c '[[ $1 == *"::add-mask::$(printf "x-access-token:ghs_appTokenForTests" | base64 | tr -d "\n")"* ]]' _ "$OUT"
check "push: no auto-merge" bash -c '! grep -qE -- "^pr merge|--auto" "$1"' _ "$GHFX/log"

# --- refusals before the mint -------------------------------------------------
new_fx; mk_toy; fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
compute "${COMPUTE_STEPS[@]}"
refusal() { # refusal <name> <stderr substring> [<jq edit>]
  publish_job
  [ -z "${3:-}" ] || edit_plan "$3"
  gh_reset_p
  gh_prs "${LIVE:-[]}"
  publish verify
  check "refuse: $1" bash -c '[ "$1" = 1 ] && [[ $2 == *"$3"* ]] && [ ! -e "$4/plan.json" ]' _ "$RC" "$ERR" "$2" "$PV"
}
refusal "an effective dry run" "the plan is a dry run" '.effective_dry_run = true'

# The dry-run input (the receiver's stop switch, enforced here and not only
# in the caller's if:): only exactly false publishes.
publish_job
gh_reset_p
: >"$GITHUB_OUTPUT"
PUBLISH_DRY_RUN=true publish verify
check "dry-run input true: verify publishes nothing and succeeds" bash -c '[ "$1" = 0 ] && [[ $2 == *"::notice::dry run"* ]] && [ "$(cat "$3")" = publish=false ] && [ ! -e "$4/plan.json" ] && [ ! -s "$5" ]' \
  _ "$RC" "$OUT" "$GITHUB_OUTPUT" "$PV" "$GHFX/log"
for v in "<unset>" "" False TRUE " false" "false "; do
  publish_job
  gh_reset_p
  : >"$GITHUB_OUTPUT"
  PUBLISH_DRY_RUN="$v" publish verify
  check "dry-run input \`$v\`: verify refuses before reading the plan" bash -c '[ "$1" = 1 ] && [[ $2 == *"the dry-run input must be true or false"* ]] && [ ! -s "$3" ] && [ ! -s "$4" ]' \
    _ "$RC" "$ERR" "$GITHUB_OUTPUT" "$GHFX/log"
done
publish_job
gh_reset_p
gh_prs '[]'
publish verify
PUBLISH_DRY_RUN=true publish act
check "dry-run input true: act refuses even after a verified plan" bash -c '[ "$1" = 1 ] && [[ $2 == *"act publishes nothing"* ]] && ! grep -qE "^(pr (create|edit|close|comment)|label )" "$3"' _ "$RC" "$ERR" "$GHFX/log"
check "dry-run input true: act pushed nothing" test -z "$(origin_tip deps/cascade)"
# A gates-only run never publishes. The plan below is a real, complete push
# plan, as forged release-head code in a gates-only compute run could upload
# it next to forged action=push and compute-ok=true outputs; the action's
# gates-only input, the caller's own dispatch input, still stops it.
publish_job
gh_reset_p
: >"$GITHUB_OUTPUT"
PUBLISH_GATES_ONLY=true publish verify
check "gates-only input true: verify refuses a complete plan before reading it" bash -c '
  [ "$1" = 1 ] && [[ $2 == *"refusing the plan: a gates-only run never publishes"* ]] && [ ! -s "$3" ] && [ ! -e "$4/plan.json" ] && [ ! -s "$5" ]' \
  _ "$RC" "$ERR" "$GITHUB_OUTPUT" "$PV" "$GHFX/log"
publish_job
gh_reset_p
: >"$GITHUB_OUTPUT"
PUBLISH_GATES_ONLY=true PUBLISH_DRY_RUN=true publish verify
check "gates-only input true: refused even with the dry-run input true (checked first)" bash -c '
  [ "$1" = 1 ] && [[ $2 == *"a gates-only run never publishes"* ]] && [ ! -s "$3" ]' _ "$RC" "$ERR" "$GITHUB_OUTPUT"
for v in "<unset>" "" False TRUE " false" "false " yes; do
  publish_job
  gh_reset_p
  : >"$GITHUB_OUTPUT"
  PUBLISH_GATES_ONLY="$v" publish verify
  check "gates-only input \`$v\`: verify refuses before reading the plan" bash -c '
    [ "$1" = 1 ] && [[ $2 == *"the gates-only input must be true or false"* ]] && [ ! -s "$3" ] && [ ! -s "$4" ]' \
    _ "$RC" "$ERR" "$GITHUB_OUTPUT" "$GHFX/log"
done
publish_job
gh_reset_p
gh_prs '[]'
publish verify
check "gates-only: the same plan verifies when the input is false" bash -c '[ "$1" = 0 ] && grep -qx publish=true "$2"' _ "$RC" "$GITHUB_OUTPUT"
gh_reset_p
PUBLISH_GATES_ONLY=true publish act
check "gates-only input true: act refuses even after a verified plan" bash -c '[ "$1" = 1 ] && [[ $2 == *"a gates-only run never publishes"* ]] && [ ! -s "$3" ]' _ "$RC" "$ERR" "$GHFX/log"
check "gates-only input true: act pushed nothing" test -z "$(origin_tip deps/cascade)"
refusal "an unknown action" "unknown action \`merge-now\`" '.action = "merge-now"'
refusal "an unknown label" "label \`admin\` is not one of the bot's labels" '.labels += ["admin"]'
# The title is derived in publish: a forged one is a notice, never used.
publish_job
edit_plan '.title = "feat(deps)!: x" | .title_computed = "feat: x"'
gh_reset_p
gh_prs '[]'
publish verify
check "derived: a forged plan title is ignored for the derived one" bash -c '
  [ "$1" = 0 ] && [ "$(cat "$3/title")" = "fix(deps): bump up to v0.2.0" ] && [[ $2 == *"::notice::the plan'"'"'s title differs"* ]]' _ "$RC" "$OUT" "$PV"
refusal "a bad tip" "old_tip and new_tip must be commit ids" '.old_tip = "--upload-pack=x"'
printf 'b\n' >"$FX/b"
LIVE="[$(pr_json 9 "fix(deps): other" "$FX/b")]" refusal "a PR-number mismatch" "the plan names PR \`\`, the cascade PR is \`9\`"
HOLD="[$(pr_json 9 "fix(deps): other" "$FX/b" "deps-cascade:hold")]"
publish_job
edit_plan '.pr_number = 9'
gh_reset_p
gh_prs "$HOLD"
: >"$GITHUB_OUTPUT"
publish verify
check "hold: a hold added since compute stops publish without a red run" bash -c '
  [ "$1" = 0 ] && [[ $2 == *"::notice::the cascade PR got deps-cascade:hold since compute; nothing is published"* ]] &&
  [ "$(cat "$3")" = publish=false ] && [ ! -e "$4/plan.json" ]' _ "$RC" "$OUT" "$GITHUB_OUTPUT" "$PV"
refusal "a forged PR number" "the plan names PR \`3\`, the cascade PR is \`none\`" '.pr_number = 3'
publish_job
seed_commit deps/cascade human fixtures/x.txt "racing human" "test: racing"
gh_reset_p
gh_prs '[]'
publish verify
check "refuse: a moved remote tip" bash -c '[ "$1" = 1 ] && [[ $2 == *"deps/cascade moved since compute; the next run retries"* ]]' _ "$RC" "$ERR"
check "refuse: nothing mutating was called" test -z "$(mutations)"
check "refuse: act will not run without a verified plan" bash -c '
  cd "$1" && env CASCADE_PUBLISH_GATES_ONLY=false CASCADE_PUBLISH_DRY_RUN=false CASCADE_REPO=cascade-sandbox-down CASCADE_T="$1/t" CASCADE_REPO_DIR="$1/repo" GH_TOKEN=x bash "$2" act 2>&1 | grep -q "verify has not run"' _ "$PWS" "$PUBLISH"

# A planted workflow change is refused by publish's own guard.
new_fx; mk_toy; fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
compute init payload state prepare notes run
printf 'name: evil\n' >"$WS/repo/.github/workflows/touch.yml"
git -C "$WS/repo" commit -q -am "ci: evil"
compute text
compute plan
edit_plan_c() { jq "$1" "$CASCADE_T/plan.json" >"$FX/p.json" && mv "$FX/p.json" "$CASCADE_T/plan.json"; }
edit_plan_c '.action = "push" | .title = .title_computed'
rm -f "$CASCADE_T/cascade.bundle"
git -C "$WS/repo" bundle create -q "$CASCADE_T/cascade.bundle" HEAD ^origin/main
edit_plan_c ".new_tip = \"$(git -C "$WS/repo" rev-parse HEAD)\""
publish_job
gh_prs '[]'
publish verify
check "refuse: a new tip that changes workflow files" bash -c '[ "$1" = 1 ] && [[ $2 == *"differs from main in workflow files: .github/workflows/touch.yml"* ]]' _ "$RC" "$ERR"

# Recreate and the workflows conflict happen only under strict, which is not
# shipped (E4c chose tree): these run a copy of the scripts with strict.
SHIPPED_COMPUTE="$COMPUTE" SHIPPED_PUBLISH="$PUBLISH"
COMPUTE="$(rule_copy strict)/receive-compute.sh" PUBLISH="$(rule_copy strict)/receive-publish.sh"

# --- recreate end to end ------------------------------------------------------
new_fx; mk_toy
bot_branch v0.2.0
OLD=$(origin_tip deps/cascade)
body_with "fix(deps): bump up to v0.2.0" "carried notes"
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" "deps-cascade,deps-cascade:breaking,need-human-review,deps-cascade:conflict")
seed_commit main human .github/workflows/touch.yml "name: touched" "ci: touch"
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
compute "${COMPUTE_STEPS[@]}"
publish_job
gh_prs "[$PR]"
publish verify
check "recreate: verify accepts the plan" test "$RC/$OUT" = "0/plan verified: recreate"
gh_accept "label create * --force"
gh_fx 0 "" -- pr comment 5 -R "$SBX" --body-file "$PV/c-recreate.md"
gh_fx 0 "" -- pr close 5 -R "$SBX"
gh_fx 0 "https://github.com/$SBX/pull/6" -- pr create -R "$SBX" --head deps/cascade --base main --title "fix(deps): bump up to v0.3.0" --body-file "$PV/body.md"
gh_fx 0 "" -- pr edit 6 -R "$SBX" --add-label deps-cascade,deps-cascade:breaking,need-human-review
gh_fx 0 "" -- pr comment 5 -R "$SBX" --body-file "$PV/c-continued.md"
publish act
NEW=$(origin_tip deps/cascade)
check "recreate: act succeeds and opens a new PR" bash -c '[ "$1" = 0 ] && [[ $2 == *"opened #6"* ]]' _ "$RC" "$OUT"
check "recreate: the branch is rebuilt on main, not on the old tip" bash -c '
  [ "$2" = "$(jq -r .new_tip "$4")" ] && ! git --git-dir="$1" merge-base --is-ancestor "$3" "$2" && git --git-dir="$1" merge-base --is-ancestor main "$2"' \
  _ "$ORIGIN" "$NEW" "$OLD" "$PWS/t/plan/plan.json"
check "recreate: the old PR gets C-recreate, is closed, then names the new one" bash -c '
  grep -n "" "$1" | grep -E "pr (comment|close) 5" | cut -d: -f2- | tr "\n" "|" | grep -qx "pr comment 5 -R $2 --body-file $3/c-recreate.md|pr close 5 -R $2|pr comment 5 -R $2 --body-file $3/c-continued.md|"' \
  _ "$GHFX/log" "$SBX" "$PV"
check "recreate: the continued comment" test "$(cat "$PV/c-continued.md")" = "Continued in #6."
check "recreate: the new body carries the Notes" bash -c '[ "$(sed -n "/^<!-- cascade-notes:/,\$p" "$1" | tail -n +2)" = "carried notes" ]' _ "$PV/body.md"
check "recreate: the conflict label is not carried" bash -c '! grep -q "add-label.*deps-cascade:conflict" "$1"' _ "$GHFX/log"

# --- conflict without comment spam --------------------------------------------
new_fx; mk_toy
bot_branch v0.2.0
seed_commit deps/cascade human fixtures/human.txt "human" "test: human"
body_with "fix(deps): bump up to v0.2.0" ""
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" deps-cascade)
seed_commit main human .github/workflows/touch.yml "name: touched" "ci: touch"
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
compute "${COMPUTE_STEPS[@]}"
TIP=$(origin_tip deps/cascade)
publish_job
gh_prs "[$PR]"
publish verify
gh_accept "label create * --force"
gh_fx 0 "" -- pr edit 5 -R "$SBX" --add-label deps-cascade:conflict
gh_fx 0 "" -- pr comment 5 -R "$SBX" --body-file "$PV/c-conflict.md"
publish act
check "conflict: labelled and commented, nothing pushed" bash -c '[ "$1" = 0 ] && [ "$2" = "$3" ] && [ "$(grep -c "^pr comment" "$4")" = 1 ]' _ "$RC" "$(origin_tip deps/cascade)" "$TIP" "$GHFX/log"
check "conflict: the workflows comment names the path" grep -qF '(`.github/workflows/touch.yml`)' "$PV/c-conflict.md"
PR2=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" "deps-cascade,deps-cascade:conflict")
: >"$GHFX/log"
gh_prs "[$PR2]"
publish verify
publish act
check "conflict: a second run posts no second comment" bash -c '[ "$1" = 0 ] && ! grep -q "^pr comment" "$2" && ! grep -q "^pr edit" "$2"' _ "$RC" "$GHFX/log"

COMPUTE="$SHIPPED_COMPUTE" PUBLISH="$SHIPPED_PUBLISH"

# --- tree: an in-place update across a workflow change on main ---------------
new_fx; mk_toy
bot_branch v0.2.0
OLD=$(origin_tip deps/cascade)
body_with "fix(deps): bump up to v0.2.0" "kept notes"
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" deps-cascade)
seed_commit main human .github/workflows/touch.yml "name: touched" "ci: touch"
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
compute "${COMPUTE_STEPS[@]}"
publish_job
gh_prs "[$PR]"
publish verify
check "tree: verify accepts an in-place push whose old tip predates main's workflow change" test "$RC/$OUT" = "0/plan verified: push"
gh_accept "label create * --force"
gh_accept "pr edit 5 -R $SBX *"
publish act
check "tree: the same PR is updated in place under the lease" bash -c '
  [ "$1" = 0 ] && [ "$2" = "$(jq -r .new_tip "$3")" ] && ! grep -qE "^pr (create|close)" "$4"' _ "$RC" "$(origin_tip deps/cascade)" "$PWS/t/plan/plan.json" "$GHFX/log"
check "tree: the old tip is replaced, not merged" bash -c '! git --git-dir="$1" merge-base --is-ancestor "$2" "$3"' _ "$ORIGIN" "$OLD" "$(origin_tip deps/cascade)"

# --- too long -----------------------------------------------------------------
new_fx; mk_toy
bot_branch v0.2.0
head -c 70000 /dev/zero | tr '\0' 'n' >"$FX/big"
body_with "fix(deps): bump up to v0.2.0" "$(cat "$FX/big")"
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in")
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
compute "${COMPUTE_STEPS[@]}"
publish_job
gh_prs "[$PR]"
publish verify
COMMENTS_ARGS=(api --paginate repos/open-platform-model/cascade-sandbox-down/issues/5/comments --jq '.[] | select(.user.login == "opm-cascade[bot]") | .body')
gh_accept "label create * --force"
gh_fx 0 "an older comment" -- "${COMMENTS_ARGS[@]}"
gh_fx 0 "" -- pr comment 5 -R "$SBX" --body-file "$PV/c-too-long.md"
publish act
check "too long: comments once and fails the run" bash -c '[ "$1" = 1 ] && [ "$(grep -c "^pr comment 5" "$2")" = 1 ] && ! grep -q "^pr edit" "$2"' _ "$RC" "$GHFX/log"
gh_fx 0 "$(cat "$PV/c-too-long.md")" -- "${COMMENTS_ARGS[@]}"
: >"$GHFX/log"
publish act
check "too long: no second comment" bash -c '[ "$1" = 1 ] && ! grep -q "^pr comment" "$2"' _ "$RC" "$GHFX/log"

# --- close --------------------------------------------------------------------
new_fx; mk_toy
bot_branch v0.2.0
body_with "fix(deps): bump up to v0.2.0" ""
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in")
seed_commit main human UPSTREAM_VERSION v0.2.0 "fix(deps): bumped by hand"
fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
compute "${COMPUTE_STEPS[@]}"
publish_job
gh_prs "[$PR]"
publish verify
gh_accept "label create * --force"
gh_fx 0 "" -- pr comment 5 -R "$SBX" --body-file "$PV/c-close.md"
gh_fx 0 "" -- pr close 5 -R "$SBX"
publish act
check "close: comments, closes and deletes the branch under the lease" bash -c '[ "$1" = 0 ] && [ -z "$2" ]' _ "$RC" "$(origin_tip deps/cascade)"

# --- labels-managed -----------------------------------------------------------
new_fx; mk_toy; fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
compute "${COMPUTE_STEPS[@]}"
publish_job
gh_prs '[]'
publish verify
gh_fx 0 $'deps-cascade\ndeps-cascade:hold\nneed-human-review\ndeps-cascade:breaking' -- label list -R "$SBX" --limit 500 --json name --jq '.[].name'
LABELS_MANAGED=true publish act
check "labels-managed: a missing label fails before any push" bash -c '
  [ "$1" = 1 ] && [[ $2 == *"label deps-cascade:conflict is missing: declare it in .github/labels.yml"* ]] && [ -z "$3" ]' _ "$RC" "$ERR" "$(origin_tip deps/cascade)"

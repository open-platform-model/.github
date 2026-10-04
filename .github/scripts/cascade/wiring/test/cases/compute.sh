# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# receive-compute.sh against the toy repo and a bare file:// origin: modes,
# merges, the task run, titles, labels, the breaking check, the action
# table, the workflows guard and the plan.

REL_ARGS=(api --paginate repos/open-platform-model/cascade-sandbox-up/releases --jq '.[] | select(.draft | not) | [.tag_name, ((.body // "") | test("BREAKING CHANGES"))] | @tsv')
# gh_rels <tsv>: the next answer to the sandbox-up release list.
gh_rels() { gh_fx 0 "$1" -- "${REL_ARGS[@]}"; }
NO_BREAK=$'v0.4.0\tfalse\nv0.3.0\tfalse\nv0.2.0\tfalse\nv0.1.0\tfalse'
M='<!-- cascade-notes: the bot keeps everything below this line -->'

# bot_branch <version>: deps/cascade as the bot builds it, one bot commit on main.
bot_branch() { seed_commit deps/cascade bot UPSTREAM_VERSION "$1" "fix(deps): bump up to $1"; }
# body_with <title marker> <notes>: a PR body file as the bot wrote it.
body_with() { printf '<!-- cascade-title: %s -->\n## Notes\n\n%s\n%s' "$1" "$M" "$2" >"$FX/body.in"; }

# --- fresh --------------------------------------------------------------------
new_fx; mk_toy; fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_rels "$NO_BREAK"
compute "${COMPUTE_STEPS[@]}"
check "fresh: all steps succeed" test "$RC" = 0
check "fresh: mode fresh, action push" test "$(plan .mode)/$(plan .action)" = fresh/push
check "fresh: computed title" test "$(plan .title)" = "fix(deps): bump up to v0.2.0"
check "fresh: one bot commit on main" bash -c '
  [ "$(git -C "$1" rev-list --count origin/main..HEAD)" = 1 ] &&
  [ "$(git -C "$1" log -1 --format="%an|%ae|%cn|%ce|%s")" = "opm-cascade[bot]|$2|opm-cascade[bot]|$2|fix(deps): bump up to v0.2.0" ]' _ "$WS/repo" "$BOT_EMAIL"
check "fresh: the commit has no body" test -z "$(git -C "$WS/repo" log -1 --format=%b)"
check "fresh: labels" test "$(plan '.labels | join(",")')" = deps-cascade
check "fresh: no PR, no old tip" test "$(plan '.pr_number')/$(plan .old_tip)" = null/
check "fresh: the bundle holds the new tip" bash -c 'git -C "$1" bundle list-heads "$2" | grep -q "^$3 HEAD$"' _ "$WS/repo" "$CASCADE_T/cascade.bundle" "$(plan .new_tip)"
check "fresh: job outputs" test "$(cat "$GITHUB_OUTPUT")" = $'dry_run=false\naction=push\nmode=fresh'
check "fresh: the body ends at the Notes marker" test "$(tail -n 1 "$CASCADE_T/body.md")" = "$M"
check "fresh: the summary holds mode, action and the diff" bash -c 'grep -q "Mode: \`fresh\`; action: \`push\`" "$1" && grep -q "^+v0.2.0" "$1" && ! grep -q "DRY RUN" "$1"' _ "$GITHUB_STEP_SUMMARY"
check "fresh: scratch files stay out of the repo" test -z "$(git -C "$WS/repo" status --porcelain --untracked-files=all)"
check "fresh: no diff.patch outside a dry run" test ! -e "$CASCADE_T/diff.patch"

# --- dry run and the ref ------------------------------------------------------
new_fx; mk_toy; fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_rels "$NO_BREAK"
CASCADE_REF=refs/heads/feat/x compute "${COMPUTE_STEPS[@]}"
check "dry run: a branch run is a dry run" bash -c '[ "$1" = 0 ] && grep -qx "dry_run=true" "$2" && [ "$(jq -r .effective_dry_run "$3")" = true ]' _ "$RC" "$GITHUB_OUTPUT" "$CASCADE_T/plan.json"
check "dry run: the summary says so and shows the diff" bash -c 'grep -q "DRY RUN: nothing was pushed" "$1" && grep -q "^+v0.2.0" "$1"' _ "$GITHUB_STEP_SUMMARY"
check "dry run: diff.patch is written" grep -q '^+v0.2.0' "$CASCADE_T/diff.patch"
new_fx; mk_toy; fresh_checkout
gh_prs '[]'
CASCADE_DRY_RUN=yes compute init
check "dry run: anything but false is a dry run" grep -qx "dry_run=true" "$GITHUB_OUTPUT"

# --- init refusals ------------------------------------------------------------
new_fx; mk_toy; fresh_checkout
CASCADE_G2_MODE=strict compute init
check "init: a bad gate mode fails" bash -c '[ "$1" = 1 ] && [[ $2 == *"g2-mode must be warn or enforce"* ]]' _ "$RC" "$ERR"
CASCADE_REPO=core compute init
check "init: core is not a receiver" bash -c '[ "$1" = 1 ] && [[ $2 == *"not a cascade receiver: core"* ]]' _ "$RC" "$ERR"
run env -C "$WS" CASCADE_REPO=cascade-sandbox-down CASCADE_T="$WS/repo/t" bash "$COMPUTE" init
check "init: a scratch dir inside the repo is refused" bash -c '[ "$1" = 1 ] && [[ $2 == *"is inside a checkout"* ]]' _ "$RC" "$ERR"

# --- payload ------------------------------------------------------------------
new_fx; mk_toy; fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_rels "$NO_BREAK"
CASCADE_EVENT=repository_dispatch CASCADE_PAYLOAD='{"source":"cascade-sandbox-up","tags":["v0.2.0"],"extra":1}' compute "${COMPUTE_STEPS[@]}"
check "payload: valid payload reaches the task as CASCADE_EXPECT" \
  test "$(cat "$TOY_LOG")" = "expect=github.com/open-platform-model/cascade-sandbox-up=v0.2.0 source=cascade-sandbox-up tags=v0.2.0"
check "payload: the triggering release is in the body (sandbox source)" grep -qxF -- '- `cascade-sandbox-up` `v0.2.0`' "$CASCADE_T/body.md"
check "payload: the summary names the accepted payload" grep -qF 'Payload accepted: `cascade-sandbox-up` `v0.2.0`' "$GITHUB_STEP_SUMMARY"
new_fx; mk_toy; fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_rels "$NO_BREAK"
CASCADE_EVENT=repository_dispatch CASCADE_PAYLOAD='{"source":"evil","tags":["@x"]}' compute "${COMPUTE_STEPS[@]}"
check "payload: a hostile payload is dropped and the run is a sweep" bash -c '
  [ "$1" = 0 ] && [ "$(cat "$2")" = "expect= source= tags=" ]' _ "$RC" "$TOY_LOG"
run env -C "$WS" CASCADE_REPO=cascade-sandbox-down CASCADE_EVENT=repository_dispatch CASCADE_PAYLOAD='{"source":"cascade-sandbox-up"}' bash "$COMPUTE" payload
check "payload: the drop is a workflow warning" bash -c '[ "$1" = 0 ] && [[ $2 == "::warning::payload dropped: tags is not an array of 1 to 8 strings; continuing as a sweep" ]]' _ "$RC" "$OUT"
check "payload: no mention anywhere the bot writes" bash -c '! grep -rqP "(?<![\w@])@[A-Za-z0-9]" "$1/body.md" "$2" "$1/plan.json"' _ "$CASCADE_T" "$GITHUB_STEP_SUMMARY"
check "payload: the drop is in the summary" grep -qF 'Payload dropped: source `evil` is not accepted by cascade-sandbox-down' "$GITHUB_STEP_SUMMARY"
check "payload: the body records no triggering release" grep -qxF -- '- None recorded (daily sweep or manual run).' "$CASCADE_T/body.md"

# --- tokens -------------------------------------------------------------------
new_fx; mk_toy; fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_rels "$NO_BREAK"
GH_TOKEN=gho_leak GITHUB_TOKEN=ghs_leak CASCADE_READ_TOKEN=ghs_read compute "${COMPUTE_STEPS[@]}"
check "tokens: the task never sees a token" test "$RC" = 0
run env -C "$WS/repo" GH_TOKEN=x bash .tasks/cascade/cascade.sh
check "tokens: the toy task refuses a visible token (control)" test "$RC" = 9

# The task cannot write the step's command files: the toy appends forged
# lines to every one whose path it is given (control below).
new_fx; mk_toy; fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_rels "$NO_BREAK"
for f in env path state; do : >"$FX/$f"; done
GITHUB_ENV="$FX/env" GITHUB_PATH="$FX/path" GITHUB_STATE="$FX/state" compute "${COMPUTE_STEPS[@]}"
check "command files: the task's forged lines reach no command file" bash -c '
  [ "$1" = 0 ] && ! grep -q forged "$2" "$3" "$4/env" "$4/path" "$4/state" && [ "$(grep -c "^action=" "$2")" = 1 ] && grep -qx action=push "$2"' \
  _ "$RC" "$GITHUB_OUTPUT" "$GITHUB_STEP_SUMMARY" "$FX"
run env -C "$WS/repo" GITHUB_OUTPUT="$FX/control" bash .tasks/cascade/cascade.sh
check "command files: the toy task writes a command file it is given (control)" grep -qx forged=GITHUB_OUTPUT "$FX/control"

# The text step runs repo code with no token and makes no API call: the
# breaking check reads the releases state fetched.
new_fx; mk_toy; fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_rels $'v0.2.0\ttrue\nv0.1.0\tfalse'
compute init payload state prepare notes run
check "no token after repo code: state fetched the releases before the task ran" \
  test "$(cat "$CASCADE_T/releases/cascade-sandbox-up.tsv")" = $'v0.2.0\ttrue\nv0.1.0\tfalse'
: >"$GHFX/log"
compute text action plan
check "no token after repo code: text needs no token and calls no gh" bash -c '[ "$1" = 0 ] && [ ! -s "$2" ]' _ "$RC" "$GHFX/log"
check "no token after repo code: the breaking label still comes from the fetched releases" \
  test "$(plan '.labels | join(",")')" = "deps-cascade,deps-cascade:breaking"
new_fx; mk_toy; fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_rels "$NO_BREAK"
compute init payload state
rm -f "$CASCADE_T/releases/cascade-sandbox-up.tsv"
compute prepare notes run text action plan summary
check "no token after repo code: releases state did not fetch warn, never call the API" bash -c '
  [ "$1" = 0 ] && grep -q "breaking check could not read" "$2" && [ "$(grep -c "releases" "$3")" = 1 ]' _ "$RC" "$GITHUB_STEP_SUMMARY" "$GHFX/log"
new_fx; mk_toy
bot_branch v0.2.0
printf 'b\n' >"$FX/b"
gh_prs "[$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/b" "deps-cascade,deps-cascade:hold")]"
fresh_checkout
compute init payload state
check "no token after repo code: a held PR fetches no releases" bash -c '[ "$1" = 0 ] && [ "$3" = skip ] && ! grep -q releases "$2"' _ "$RC" "$GHFX/log" "$(st mode)"

# --- rebuild ------------------------------------------------------------------
new_fx; mk_toy
bot_branch v0.2.0
body_with "fix(deps): bump up to v0.2.0" "my notes"
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" "deps-cascade,need-human-review")
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_rels "$NO_BREAK"
compute "${COMPUTE_STEPS[@]}"
check "rebuild: mode rebuild, action push, same PR" test "$(plan .mode)/$(plan .action)/$(plan .pr_number)" = rebuild/push/5
check "rebuild: one bot commit on main" bash -c '[ "$(git -C "$1" rev-list --count origin/main..HEAD)" = 1 ] && [ "$(cat "$1/UPSTREAM_VERSION")" = v0.3.0 ]' _ "$WS/repo"
check "rebuild: title updated" test "$(plan .title)" = "fix(deps): bump up to v0.3.0"
check "rebuild: the old Notes are carried byte for byte" bash -c '[ "$(sed -n "/^<!-- cascade-notes:/,\$p" "$1" | tail -n +2)" = "my notes" ]' _ "$CASCADE_T/body.md"
check "rebuild: the bundle needs only main" bash -c 'git -C "$1" bundle verify -q "$2" >/dev/null 2>&1' _ "$WS/repo" "$CASCADE_T/cascade.bundle"

# Nothing new: the rebuilt tree equals the old one, the old commit is kept.
new_fx; mk_toy
bot_branch v0.2.0
body_with "fix(deps): bump up to v0.2.0" ""
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in")
fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_rels "$NO_BREAK"
compute "${COMPUTE_STEPS[@]}"
check "rebuild: no change keeps the old commit" bash -c '[ "$(jq -r .new_tip "$1")" = "$(jq -r .old_tip "$1")" ] && [ "$(jq -r .action "$1")" = push ] && [ ! -e "$2" ]' _ "$CASCADE_T/plan.json" "$CASCADE_T/cascade.bundle"

# --- merge --------------------------------------------------------------------
new_fx; mk_toy
bot_branch v0.2.0
seed_commit deps/cascade human fixtures/human.txt "human work" "test: human fixture"
HUMAN=$(origin_tip deps/cascade)
body_with "fix(deps): bump up to v0.2.0" "notes"
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in")
seed_commit main human README.md "main moved" "docs: main moved"
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_rels "$NO_BREAK"
compute "${COMPUTE_STEPS[@]}"
check "merge: a human commit gives mode merge" test "$(plan .mode)/$(plan .action)" = merge/push
check "merge: the human commit is an ancestor of the new tip" git -C "$WS/repo" merge-base --is-ancestor "$HUMAN" HEAD
check "merge: main is merged in and the bot commit is on top" bash -c '
  git -C "$1" merge-base --is-ancestor origin/main HEAD &&
  [ "$(git -C "$1" log -1 --format=%s)" = "fix(deps): bump up to v0.3.0" ] &&
  [ "$(git -C "$1" log -1 --format=%s HEAD^)" = "Merge origin/main into deps/cascade" ] &&
  [ "$(git -C "$1" log -1 --format=%ae HEAD^)" = "$2" ]' _ "$WS/repo" "$BOT_EMAIL"
check "merge: the bundle needs main and the old tip" bash -c 'git -C "$1" bundle verify "$2" 2>&1 | grep -q "$3"' _ "$WS/repo" "$CASCADE_T/cascade.bundle" "$HUMAN"

new_fx; mk_toy
bot_branch v0.2.0
seed_commit deps/cascade amend UPSTREAM_VERSION v0.2.0
body_with "fix(deps): bump up to v0.2.0" ""
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in")
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_rels "$NO_BREAK"
compute init payload state
check "merge: a bot commit a human amended is a human commit" test "$(st mode)" = merge

# A human commit on the branch that changes the task: compute runs main's.
new_fx; mk_toy
seed_commit deps/cascade bot UPSTREAM_VERSION v0.2.0 "fix(deps): bump up to v0.2.0"
git -C "$SEED" checkout -q deps/cascade
cat >"$SEED/.tasks/cascade/cascade.sh" <<'SH'
#!/usr/bin/env bash
echo "the branch's task ran" >>"${TOY_TASK_LOG:-/dev/null}"
exit 9
SH
printf 'branch-only\n' >"$SEED/.tasks/cascade/extra.txt"
git -C "$SEED" add -A
git -C "$SEED" commit -q -m "chore: a human edit of the task"
git -C "$SEED" push -q origin deps/cascade
seed_commit main human fixtures/main.txt "main moved" "test: main"
BR_TASK=$(git -C "$SEED" rev-parse "origin/deps/cascade:.tasks/cascade/cascade.sh")
body_with_c() { printf '<!-- cascade-title: %s -->\n<!-- cascade-notes: the bot keeps everything below this line -->\n' "$1" >"$FX/body.in"; }
body_with_c "fix(deps): bump up to v0.2.0"
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" deps-cascade)
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
compute "${COMPUTE_STEPS[@]}"
check "overlay: the merged branch still pushes" test "$RC/$(plan .mode)/$(plan .action)" = "0/merge/push"
check "overlay: main's task ran, with CASCADE_ALLOW_DIRTY=1, never the branch's" bash -c '
  grep -qx "task=main allow_dirty=1" "$1" && ! grep -q "the branch.s task ran" "$1"' _ "$TOY_TASK_LOG"
check "overlay: the bot's commit leaves the task tree as the branch has it" bash -c '
  [ "$(git -C "$1" rev-parse "HEAD:.tasks/cascade/cascade.sh")" = "$2" ] && git -C "$1" cat-file -e "HEAD:.tasks/cascade/extra.txt" &&
  [ -z "$(git -C "$1" diff --name-only HEAD^ HEAD -- .tasks Taskfile.yml)" ] && [ "$(git -C "$1" show HEAD:UPSTREAM_VERSION)" = v0.3.0 ]' _ "$WS/repo" "$BR_TASK"

# Derived-file conflict: main's side wins, the merge commits.
new_fx; mk_toy
seed_commit main human go.mod "module x // main 1" "build: go.mod"
seed_commit deps/cascade human go.mod "module x // branch" "build: branch go.mod"
body_with "fix(deps): x" ""
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in")
seed_commit main human go.mod "module x // main 2" "build: go.mod again"
fresh_checkout
gh_prs "[$PR]"
compute init payload state prepare
check "merge: a derived-file conflict takes main's side" bash -c '
  [ "$2" = 0 ] && [ "$(cat "$1/go.mod")" = "module x // main 2" ] &&
  [ "$(git -C "$1" log -1 --format=%s)" = "Merge origin/main into deps/cascade" ] && [ -z "$(git -C "$1" status --porcelain)" ]' _ "$WS/repo" "$RC"

# A hard conflict: mode conflict, nothing committed.
new_fx; mk_toy
seed_commit main human README.md "main" "docs: main"
seed_commit deps/cascade human README.md "branch" "docs: branch"
body_with "fix(deps): x" ""
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" deps-cascade)
seed_commit main human README.md "main 2" "docs: main 2"
fresh_checkout
gh_prs "[$PR]"
compute "${COMPUTE_STEPS[@]}"
check "merge: a hard conflict gives conflict with the paths" bash -c '
  [ "$2" = 0 ] && [ "$(jq -r "[.mode, .action, .conflict_reason, (.conflict_files | join(\",\"))] | join(\"/\")" "$1")" = conflict/conflict/merge/README.md ]' \
  _ "$CASCADE_T/plan.json" "$RC"
check "merge: the aborted merge leaves a clean tree" test -z "$(git -C "$WS/repo" status --porcelain)"
check "merge: no bundle for a conflict" test ! -e "$CASCADE_T/cascade.bundle"

# --- skip, close, noop --------------------------------------------------------
new_fx; mk_toy
bot_branch v0.2.0
body_with "fix(deps): bump up to v0.2.0" ""
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" "deps-cascade,deps-cascade:hold")
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
compute "${COMPUTE_STEPS[@]}"
check "hold: deps-cascade:hold skips" bash -c '[ "$2" = 0 ] && [ "$(jq -r "[.mode,.action]|join(\"/\")" "$1")" = skip/skip ] && [ ! -s "$3" ]' _ "$CASCADE_T/plan.json" "$RC" "$TOY_LOG"

new_fx; mk_toy
bot_branch v0.2.0
body_with "fix(deps): bump up to v0.2.0" ""
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in")
seed_commit main human UPSTREAM_VERSION v0.2.0 "fix(deps): bumped by hand"
fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
compute "${COMPUTE_STEPS[@]}"
check "close: exit 3 with an open PR closes" bash -c '[ "$2" = 0 ] && [ "$(jq -r "[.mode,.action]|join(\"/\")" "$1")" = rebuild/close ]' _ "$CASCADE_T/plan.json" "$RC"

new_fx; mk_toy
seed_commit deps/cascade bot fixtures/left.txt "left" "left behind"
fresh_checkout
gh_prs '[]'
compute "${COMPUTE_STEPS[@]}"
check "close: a left-behind branch with nothing to do closes (deletes it)" bash -c '[ "$2" = 0 ] && [ "$(jq -r "[.mode,.action]|join(\"/\")" "$1")" = recreate/close ]' _ "$CASCADE_T/plan.json" "$RC"

new_fx; mk_toy; fresh_checkout
gh_prs '[]'
compute "${COMPUTE_STEPS[@]}"
check "noop: exit 3 with no PR and no branch" bash -c '[ "$2" = 0 ] && [ "$(jq -r "[.mode,.action]|join(\"/\")" "$1")" = fresh/noop ] && grep -qx action=noop "$3"' _ "$CASCADE_T/plan.json" "$RC" "$GITHUB_OUTPUT"

# go-task's GitHub Actions annotation: dropped for exit 3 (nothing to do),
# kept for a real failure.
new_fx; mk_toy; fresh_checkout
gh_prs '[]'
compute init payload state prepare notes
GITHUB_ACTIONS=true compute run
check "run: exit 3 under GITHUB_ACTIONS leaves no error annotation" bash -c '[ "$1" = 0 ] && [[ $2 != *"::error"* ]] && [ "$(cat "$3")" = 3 ]' _ "$RC" "$OUT" "$CASCADE_T/state/task_rc"
new_fx; mk_toy; fresh_checkout
gh_prs '[]'
compute init payload state prepare notes
TOY_EXIT=5 GITHUB_ACTIONS=true compute run
check "run: a failing task under GITHUB_ACTIONS keeps its annotation" bash -c '[ "$1" = 1 ] && [[ $2 == *"::error title=Task '"'"'deps:cascade'"'"' failed::exit status 5"* ]] && [[ $3 == *"exited 5"* ]]' _ "$RC" "$OUT" "$ERR"

# --- errors -------------------------------------------------------------------
new_fx; mk_toy; fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
compute init payload state prepare notes
printf 'x\n' >"$WS/repo/stray"
compute run
check "run: a dirty tree is refused" bash -c '[ "$1" = 1 ] && [[ $2 == *"dirty before the task runs"* ]]' _ "$RC" "$ERR"
new_fx; mk_toy; fresh_checkout
gh_prs '[]'
TOY_EXIT=5 compute init payload state prepare notes run
check "run: a task error fails the job" bash -c '[ "$1" = 1 ] && [[ $2 == *"task -x deps:cascade exited 5"* ]]' _ "$RC" "$ERR"

# --- titles -------------------------------------------------------------------
new_fx; mk_toy
bot_branch v0.2.0
body_with "fix(deps): bump up to v0.2.0" "keep"
PR=$(pr_json 5 "feat(deps): sandbox" "$FX/body.in")
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_rels "$NO_BREAK"
compute "${COMPUTE_STEPS[@]}"
check "title: a human retitle is kept, the marker carries the computed title" bash -c '
  [ "$(jq -r .title "$1")" = "feat(deps): sandbox" ] && [ "$(head -n 1 "$2")" = "<!-- cascade-title: fix(deps): bump up to v0.3.0 -->" ] && [ "$(cat "$3/rise")" = 0 ]' \
  _ "$CASCADE_T/plan.json" "$CASCADE_T/body.md" "$CASCADE_T/state"

# --- labels and the breaking check --------------------------------------------
new_fx; mk_toy; fresh_checkout
printf 'v0.4.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_rels $'v0.5.0\ttrue\nv0.4.0\tfalse\nv0.3.0\ttrue\nv0.2.0\tfalse\nv0.1.0\ttrue\nlatest\ttrue'
TOY_LABELS=need-human-review compute "${COMPUTE_STEPS[@]}"
check "labels: a breaking release in the middle of the range" test "$(plan '.labels | join(",")')" = "deps-cascade,need-human-review,deps-cascade:breaking"
new_fx; mk_toy; fresh_checkout
printf 'v0.4.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_rels $'v0.5.0\ttrue\nv0.4.0\tfalse\nv0.1.0\ttrue'
compute "${COMPUTE_STEPS[@]}"
check "labels: breaking releases outside the range do not count" test "$(plan '.labels | join(",")')" = deps-cascade
new_fx; mk_toy; fresh_checkout
printf 'v0.4.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_fx_err 1 "HTTP 502" -- "${REL_ARGS[@]}"
compute "${COMPUTE_STEPS[@]}"
check "labels: an API error adds no label and warns" bash -c '
  [ "$2" = 0 ] && [ "$(jq -r ".labels|join(\",\")" "$1")" = deps-cascade ] && grep -q "breaking check could not read" "$3"' _ "$CASCADE_T/plan.json" "$RC" "$GITHUB_STEP_SUMMARY"

# --- too long -----------------------------------------------------------------
new_fx; mk_toy
bot_branch v0.2.0
head -c 70000 /dev/zero | tr '\0' 'n' >"$FX/big"
body_with "fix(deps): bump up to v0.2.0" "$(cat "$FX/big")"
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in")
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_rels "$NO_BREAK"
compute "${COMPUTE_STEPS[@]}"
check "too long: a body over 65000 bytes" bash -c '[ "$2" = 0 ] && [ "$(jq -r .action "$1")" = too_long ]' _ "$CASCADE_T/plan.json" "$RC"
check "too long: the Notes are never truncated" bash -c '[ "$(wc -c <"$1")" -gt 70000 ]' _ "$CASCADE_T/body.md"

# --- the workflows guard ------------------------------------------------------
# Under strict (not shipped; a copy of the scripts with the rule swapped).
SHIPPED_COMPUTE="$COMPUTE"
COMPUTE="$(rule_copy strict)/receive-compute.sh"
new_fx; mk_toy
bot_branch v0.2.0
body_with "fix(deps): bump up to v0.2.0" "carried"
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" "deps-cascade,deps-cascade:breaking,need-human-review,deps-cascade:conflict")
seed_commit main human .github/workflows/touch.yml "name: touched" "ci: touch"
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_rels "$NO_BREAK"
compute "${COMPUTE_STEPS[@]}"
check "guard strict: main changed a workflow under a bot-only PR gives recreate" \
  test "$(plan '[.mode, .action, (.carry_labels | join(","))] | join("/")')" = "rebuild/recreate/deps-cascade:breaking,need-human-review"
check "guard strict: recreate keeps the Notes" bash -c '[ "$(sed -n "/^<!-- cascade-notes:/,\$p" "$1" | tail -n +2)" = carried ]' _ "$CASCADE_T/body.md"

new_fx; mk_toy
bot_branch v0.2.0
seed_commit deps/cascade human fixtures/human.txt "human" "test: human"
body_with "fix(deps): bump up to v0.2.0" ""
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in")
seed_commit main human .github/workflows/touch.yml "name: touched" "ci: touch"
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_rels "$NO_BREAK"
compute "${COMPUTE_STEPS[@]}"
check "guard strict: main changed a workflow under a human commit gives a workflows conflict" \
  test "$(plan '[.mode, .action, .conflict_reason, (.conflict_files | join(","))] | join("/")')" = "merge/conflict/workflows/.github/workflows/touch.yml"

COMPUTE="$SHIPPED_COMPUTE"
# Under the shipped rule, tree: both updates push (E4c).
new_fx; mk_toy
bot_branch v0.2.0
body_with "fix(deps): bump up to v0.2.0" "carried"
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" "deps-cascade,deps-cascade:breaking,need-human-review,deps-cascade:conflict")
seed_commit main human .github/workflows/touch.yml "name: touched" "ci: touch"
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_rels "$NO_BREAK"
compute "${COMPUTE_STEPS[@]}"
check "guard tree: main changed a workflow under a bot-only PR rebuilds in place" \
  test "$(plan '[.mode, .action, .pr_number] | join("/")')" = "rebuild/push/5"
check "guard tree: the in-place rebuild keeps the Notes" bash -c '[ "$(sed -n "/^<!-- cascade-notes:/,\$p" "$1" | tail -n +2)" = carried ]' _ "$CASCADE_T/body.md"

new_fx; mk_toy
bot_branch v0.2.0
seed_commit deps/cascade human fixtures/human.txt "human" "test: human"
body_with "fix(deps): bump up to v0.2.0" ""
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in")
seed_commit main human .github/workflows/touch.yml "name: touched" "ci: touch"
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_rels "$NO_BREAK"
compute "${COMPUTE_STEPS[@]}"
check "guard tree: main changed a workflow under a human commit merges and pushes" \
  test "$(plan '[.mode, .action] | join("/")')" = "merge/push"
check "guard tree: the merge keeps the human commit" bash -c 'git -C "$1" merge-base --is-ancestor "$(git -C "$1" rev-parse origin/deps/cascade)" HEAD' _ "$WS/repo"

new_fx; mk_toy
seed_commit deps/cascade bot fixtures/left.txt "left" "left behind"
seed_commit main human .github/workflows/touch.yml "name: touched" "ci: touch"
fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_rels "$NO_BREAK"
compute "${COMPUTE_STEPS[@]}"
check "guard: a left-behind branch is recreated with nothing carried" \
  test "$(plan '[.mode, .action, (.carry_labels | length)] | join("/")')" = "recreate/recreate/0"

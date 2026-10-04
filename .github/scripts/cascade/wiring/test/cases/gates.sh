# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# gates-eval.sh (G2, G3), gates-post.sh (the status mapping, a missing
# artifact), the compute gates step and cascade-gates.yml's inline script.

SBX=open-platform-model/cascade-sandbox-down
UP=open-platform-model/cascade-sandbox-up
# shellcheck disable=SC2054 # the --json values are one comma-separated argument
REL_LIST=(pr list -R "$SBX" --base main --state open --limit 200 --json number,headRefName,headRefOid,isCrossRepository)
# shellcheck disable=SC2054 # the --json value is one comma-separated argument
UP_CASCADE=(pr list -R "$UP" --head deps/cascade --base main --state open --json number,title,body,labels,headRefOid,isCrossRepository,headRepositoryOwner,author)
# shellcheck disable=SC2054 # the --json value is one comma-separated argument
UP_PENDING=(pr list -R "$UP" --base main --state open --label "autorelease: pending" --json number,body)

# release_pr <number> <head>: the release-PR list entry.
release_pr() { jq -nc --argjson n "$1" --arg oid "$2" '{number: $n, headRefName: "release-please--branches--main", headRefOid: $oid, isCrossRepository: false}'; }
gates_eval() { run env -C "$WS" CASCADE_REPO=cascade-sandbox-down bash "$GATES_EVAL"; }
g() { jq -r "$1" "$CASCADE_T/gates.json"; }

# --- G2 -----------------------------------------------------------------------
new_fx; mk_toy
seed_commit release-please--branches--main human CHANGELOG.md "## 0.1.1" "chore(main): release 0.1.1"
HEAD1=$(origin_tip release-please--branches--main)
fresh_checkout
mkdir -p "$CASCADE_T"
printf 'v0.2.0\n' >"$TOY_TARGET"
FORK=$(jq -nc --arg oid "$HEAD1" '{number: 8, headRefName: "release-please--branches--main", headRefOid: $oid, isCrossRepository: true}')
OTHER=$(jq -nc --arg oid "$HEAD1" '{number: 9, headRefName: "feat/x", headRefOid: $oid, isCrossRepository: false}')
gh_fx 0 "[$(release_pr 7 "$HEAD1"),$FORK,$OTHER]" -- "${REL_LIST[@]}"
gh_fx 0 '[]' -- "${UP_CASCADE[@]}"
gh_fx 0 '[]' -- "${UP_PENDING[@]}"
gates_eval
check "G2: a shipped pin behind is a problem naming the move" bash -c '
  [ "$1" = 0 ] && [ "$(jq -c "[.[] | [.pr, .freshness.state, .freshness.msg]]" "$2")" = "[[7,\"problem\",\"behind: up v0.1.0→v0.2.0\"]]" ]' _ "$RC" "$CASCADE_T/gates.json"
check "G2: fork and non-release PRs are not evaluated" test "$(g length)" = 1
check "G2: the worktree is removed" bash -c '[ ! -e "$1/g2-7" ] && [ "$(git -C "$2" worktree list | wc -l)" = 1 ]' _ "$CASCADE_T" "$WS/repo"
check "G2: the job's checkout is untouched" test -z "$(git -C "$WS/repo" status --porcelain)"
check "G3: settled when the upstream has no open cascade or pending release" test "$(g '.[0].settled | .state + "|" + .msg')" = "ok|ok: upstreams settled"
check "G2: no payload value reaches the release head's task" test "$(cat "$TOY_LOG")" = "expect= source= tags="

new_fx; mk_toy
seed_commit release-please--branches--main human CHANGELOG.md "## 0.1.1" "chore(main): release 0.1.1"
HEAD1=$(origin_tip release-please--branches--main)
fresh_checkout
mkdir -p "$CASCADE_T"
gh_fx 0 "[$(release_pr 7 "$HEAD1")]" -- "${REL_LIST[@]}"
gh_fx 0 '[]' -- "${UP_CASCADE[@]}"
gh_fx 0 '[]' -- "${UP_PENDING[@]}"
CASCADE_EXPECT=x=v9.9.9 CASCADE_SOURCE=evil gates_eval
check "G2: exit 3 is ok" test "$(g '.[0].freshness | .state + "|" + .msg')" = "ok|ok: shipped pins current"
check "G2: the payload variables are unset for the release head" test "$(cat "$TOY_LOG")" = "expect= source= tags="

new_fx; mk_toy
seed_commit release-please--branches--main human .tasks/cascade/classes "test UPSTREAM_VERSION" "chore(main): release 0.1.1"
HEAD1=$(origin_tip release-please--branches--main)
fresh_checkout
mkdir -p "$CASCADE_T"
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_fx 0 "[$(release_pr 7 "$HEAD1")]" -- "${REL_LIST[@]}"
gh_fx 0 '[]' -- "${UP_CASCADE[@]}"
gh_fx 0 '[]' -- "${UP_PENDING[@]}"
gates_eval
check "G2: exit 0 with only test paths is ok (the head's own classes)" test "$(g '.[0].freshness | .state + "|" + .msg')" = "ok|ok: only test/release-tool pins behind"

new_fx; mk_toy
seed_commit release-please--branches--main human CHANGELOG.md "## 0.1.1" "chore(main): release 0.1.1"
HEAD1=$(origin_tip release-please--branches--main)
fresh_checkout
mkdir -p "$CASCADE_T"
gh_fx 0 "[$(release_pr 7 "$HEAD1")]" -- "${REL_LIST[@]}"
gh_fx 0 '[]' -- "${UP_CASCADE[@]}"
gh_fx 0 '[]' -- "${UP_PENDING[@]}"
TOY_EXIT=5 gates_eval
check "G2: another exit is an evaluator error, the worktree still removed" bash -c '
  [ "$(jq -r ".[0].freshness | .state + \"|\" + .msg" "$1")" = "error|the release head'"'"'s task exited 5" ] && [ ! -e "$2/g2-7" ]' _ "$CASCADE_T/gates.json" "$CASCADE_T"

# --- G3 -----------------------------------------------------------------------
new_fx; mk_toy
seed_commit release-please--branches--main human CHANGELOG.md "## 0.1.1" "chore(main): release 0.1.1"
HEAD1=$(origin_tip release-please--branches--main)
fresh_checkout
mkdir -p "$CASCADE_T"
printf 'b\n' >"$FX/b"
UPPR=$(jq -c '.headRepositoryOwner.login = "open-platform-model"' <<<"$(pr_json 3 "fix(deps): bump core to v2.0.0-beta.3" "$FX/b")")
UPFORK=$(pr_json 4 "fix(deps): from a fork" "$FX/b" "" "app/opm-cascade" 1 someone)
gh_fx 0 "[$(release_pr 7 "$HEAD1")]" -- "${REL_LIST[@]}"
gh_fx 0 "[$UPPR,$UPFORK]" -- "${UP_CASCADE[@]}"
gh_fx 0 '[{"number":11,"body":"## 0.2.0\n\n### Bug Fixes\n\n* **deps:** bump core"},{"number":12,"body":"no deps"}]' -- "${UP_PENDING[@]}"
gates_eval
check "G3: open upstream cascade and a pending release with deps are problems" \
  test "$(g '.[0].settled | .state + "|" + .msg')" = "problem|cascade-sandbox-up has open cascade #3; cascade-sandbox-up release #11 pending with deps"

new_fx; mk_toy
seed_commit release-please--branches--main human CHANGELOG.md "## 0.1.1" "chore(main): release 0.1.1"
HEAD1=$(origin_tip release-please--branches--main)
fresh_checkout
mkdir -p "$CASCADE_T"
gh_fx 0 "[$(release_pr 7 "$HEAD1")]" -- "${REL_LIST[@]}"
printf 'b\n' >"$FX/b"
gh_fx 0 "[$(pr_json 4 "fix(deps): from a fork" "$FX/b" "" "app/opm-cascade" 1 someone)]" -- "${UP_CASCADE[@]}"
gh_fx 0 '[]' -- "${UP_PENDING[@]}"
gates_eval
check "G3: a fork deps/cascade PR never counts" test "$(g '.[0].settled.state')" = ok
new_fx; mk_toy
seed_commit release-please--branches--main human CHANGELOG.md "## 0.1.1" "chore(main): release 0.1.1"
HEAD1=$(origin_tip release-please--branches--main)
fresh_checkout
mkdir -p "$CASCADE_T"
gh_fx 0 "[$(release_pr 7 "$HEAD1")]" -- "${REL_LIST[@]}"
gh_fx 0 '[]' -- "${UP_CASCADE[@]}"
gh_fx_err 1 "HTTP 502" -- "${UP_PENDING[@]}"
gates_eval
check "G3: an API error is an evaluator error" test "$(g '.[0].settled.state')" = error

new_fx; mk_toy; fresh_checkout
mkdir -p "$CASCADE_T"
gh_fx_err 1 "HTTP 502" -- "${REL_LIST[@]}"
gates_eval
check "gates: an unreadable release-PR list exits 1 and writes no file" bash -c '[ "$1" = 1 ] && [ ! -e "$2/gates.json" ]' _ "$RC" "$CASCADE_T"
new_fx; mk_toy; fresh_checkout
mkdir -p "$CASCADE_T"
gh_fx 0 '[]' -- "${REL_LIST[@]}"
gates_eval
check "gates: no release PR writes an empty list and asks nothing upstream" bash -c '[ "$1" = 0 ] && [ "$(cat "$2/gates.json")" = "[]" ] && [ "$(wc -l <"$3")" = 1 ]' _ "$RC" "$CASCADE_T" "$GHFX/log"

# --- the compute gates step ---------------------------------------------------
new_fx; mk_toy; fresh_checkout
gh_fx 0 '[]' -- "${REL_LIST[@]}"
CASCADE_GATES_ONLY=true compute init payload gates
check "gates-only: the step stops the run with action gates-only" bash -c '[ "$1" = 0 ] && grep -qx "action=gates-only" "$2" && grep -q "gates only" "$3"' _ "$RC" "$GITHUB_OUTPUT" "$GITHUB_STEP_SUMMARY"
new_fx; mk_toy; fresh_checkout
gh_fx_err 1 "HTTP 502" -- "${REL_LIST[@]}"
compute init payload gates
check "gates: a failed evaluation does not stop a real run" bash -c '[ "$1" = 0 ] && [[ $2 == *"::warning::gate evaluation failed"* ]]' _ "$RC" "$OUT"
gh_fx_err 1 "HTTP 502" -- "${REL_LIST[@]}"
CASCADE_GATES_ONLY=true compute init payload gates
check "gates: a failed evaluation fails a gates-only run" test "$RC" = 1

# --- gates-post: the status mapping -------------------------------------------
new_fx
SHA=0123456789abcdef0123456789abcdef01234567
P() { run env CASCADE_REPO=cascade-sandbox-down CASCADE_RUN_URL=https://run/1 bash "$GATES_POST" "$@"; }
HEADS_LIST=(pr list -R "$SBX" --base main --state open --limit 200 --json "number,headRefName,headRefOid,isCrossRepository"
  --jq '.[] | select((.headRefName | startswith("release-please--")) and .isCrossRepository == false) | .headRefOid')
heads() { gh_fx 0 "$1" -- "${HEADS_LIST[@]}"; }
heads "$SHA"
jq -n --arg s "$SHA" --arg long "$(printf 'y%.0s' $(seq 1 300))" '[
  {sha: $s, pr: 7, freshness: {state: "problem", msg: "behind: up v0.1.0→v0.2.0"}, settled: {state: "ok", msg: "ok: upstreams settled"}},
  {sha: $s, pr: 8, freshness: {state: "error", msg: "x"}, settled: {state: "problem", msg: $long}}]' >"$FX/gates.json"
gh_accept "api -X POST repos/$SBX/statuses/$SHA -f state=* -f context=* -f description=* -f target_url=https://run/1"
P --g2-mode warn --g3-mode enforce "$FX/gates.json"
LONG140="$(printf 'y%.0s' $(seq 1 139))…"
check "post: warn problem, ok, warn error, enforce problem cut to 140" bash -c '[ "$1" = 0 ] && [ "$(grep statuses "$2" | cut -d" " -f6,8,10-)" = "$3" ]' _ "$RC" "$GHFX/log" \
  "state=success context=cascade/freshness description=WARN: behind: up v0.1.0→v0.2.0 -f target_url=https://run/1
state=success context=cascade/settled description=ok: upstreams settled -f target_url=https://run/1
state=success context=cascade/freshness description=WARN: gate could not run, see the run -f target_url=https://run/1
state=failure context=cascade/settled description=$LONG140 -f target_url=https://run/1"
gh_reset
heads "$SHA"
gh_accept "api -X POST repos/$SBX/statuses/$SHA -f state=* -f context=* -f description=* -f target_url=https://run/1"
P --g2-mode enforce --g3-mode warn "$FX/gates.json"
check "post: enforce problem, warn ok, enforce error, warn problem" bash -c '[ "$(grep statuses "$1" | cut -d" " -f6,8,10- | sed "s/ -f target_url=.*//")" = "$2" ]' _ "$GHFX/log" \
  "state=failure context=cascade/freshness description=behind: up v0.1.0→v0.2.0
state=success context=cascade/settled description=ok: upstreams settled
state=error context=cascade/freshness description=could not evaluate, see the run
state=success context=cascade/settled description=WARN: ${LONG140:6}"
gh_reset
heads "$SHA"
gh_fx_err 1 "HTTP 403" -- api -X POST "repos/$SBX/statuses/$SHA" -f state=success -f context=cascade/settled -f description="ok: upstreams settled" -f target_url=https://run/1
gh_accept "api -X POST repos/$SBX/statuses/$SHA *"
P --g2-mode warn --g3-mode warn "$FX/gates.json"
check "post: a failed post fails the job after posting the rest" bash -c '[ "$1" = 1 ] && [ "$(grep -c statuses "$2")" = 4 ]' _ "$RC" "$GHFX/log"
# gates.json comes from compute, which ran repo code: only live release heads.
OTHER=fedcba9876543210fedcba9876543210fedcba98
jq -n --arg s "$SHA" --arg o "$OTHER" '[
  {sha: $o, pr: 1, freshness: {state: "ok", msg: "ok: forged"}, settled: {state: "ok", msg: "ok: forged"}},
  {sha: $s, pr: 7, freshness: {state: "ok", msg: "ok: shipped pins current"}, settled: {state: "ok", msg: "ok: upstreams settled"}}]' >"$FX/forged.json"
gh_reset
heads "$SHA"
gh_accept "api -X POST repos/$SBX/statuses/$SHA *"
P --g2-mode warn --g3-mode warn "$FX/forged.json"
check "post: an entry that is not an open release head is skipped" bash -c '
  [ "$1" = 0 ] && [ "$(grep -c statuses "$2")" = 2 ] && ! grep -q "$3" "$2" && [[ $4 == *"skipping ${3:0:12}: not the head of an open release PR"* ]]' _ "$RC" "$GHFX/log" "$OTHER" "$OUT"
gh_reset
gh_fx_err 1 "HTTP 502" -- "${HEADS_LIST[@]}"
P --g2-mode warn --g3-mode warn "$FX/gates.json"
check "post: no status when the release PRs cannot be listed" bash -c '[ "$1" = 1 ] && ! grep -q statuses "$2"' _ "$RC" "$GHFX/log"
expect "post: a bad mode" 2 "" "modes must be warn or enforce" -- env CASCADE_REPO=cascade-sandbox-down bash "$GATES_POST" --g2-mode strict --g3-mode warn "$FX/gates.json"

# A missing artifact.
gh_reset
P --g2-mode warn --g3-mode warn --missing
check "missing: warn posts nothing" bash -c '[ "$1" = 0 ] && [ ! -s "$2" ] && [[ $3 == *"::warning::no gate results"* ]]' _ "$RC" "$GHFX/log" "$OUT"
gh_reset
gh_fx 0 "$SHA" -- pr list -R "$SBX" --base main --state open --limit 200 --json number,headRefName,headRefOid,isCrossRepository \
  --jq '.[] | select((.headRefName | startswith("release-please--")) and .isCrossRepository == false) | .headRefOid'
gh_accept "api -X POST repos/$SBX/statuses/$SHA *"
P --g2-mode enforce --g3-mode warn --missing
check "missing: enforce posts error on each release head" bash -c '
  [ "$1" = 0 ] && [ "$(grep -c statuses "$2")" = 1 ] && grep -q "state=error -f context=cascade/freshness -f description=could not evaluate, see the run" "$2"' _ "$RC" "$GHFX/log"
gh_reset
gh_fx_err 1 "HTTP 502" -- pr list -R "$SBX" --base main --state open --limit 200 --json number,headRefName,headRefOid,isCrossRepository \
  --jq '.[] | select((.headRefName | startswith("release-please--")) and .isCrossRepository == false) | .headRefOid'
P --g2-mode enforce --g3-mode enforce --missing
check "missing: enforce fails when even the list fails" test "$RC" = 1

# --- cascade-gates.yml's inline script ----------------------------------------
new_fx
GATES_TEXT=$(yaml_run "$WORKFLOWS/cascade-gates.yml" gates "Post or dispatch")
# per_pr <head ref> <head repo> <g2> <g3>: runs the inline step with gh on PATH as the shim.
per_pr() {
  run env PATH="$W_HERE/shim:$PATH" GH_REPO="$SBX" GITHUB_REPOSITORY="$SBX" HEAD_REF="$1" HEAD_SHA="$SHA" HEAD_REPO="$2" \
    G2_MODE="$3" G3_MODE="$4" RUN_URL=https://run/2 bash -e -o pipefail -c "$GATES_TEXT"
}
statuses() { grep statuses "$GHFX/log" | cut -d" " -f6,8,10- | sed 's/ -f target_url=.*//' | tr '\n' '|'; }
WF_RUN=(workflow run deps-cascade.yml --ref main -f gates_only=true)
gh_accept "api -X POST repos/$SBX/statuses/$SHA *"
per_pr feat/x "$SBX" warn warn
check "per-PR: an ordinary PR gets n/a on both contexts" bash -c '[ "$1" = 0 ] && [ "$2" = "$3" ] && ! grep -q "^workflow run" "$4"' _ "$RC" "$(statuses)" \
  "state=success context=cascade/freshness description=n/a: not a release PR|state=success context=cascade/settled description=n/a: not a release PR|" "$GHFX/log"
gh_reset; gh_accept "api -X POST repos/$SBX/statuses/$SHA *"
per_pr release-please--branches--main someone/cascade-sandbox-down enforce enforce
check "per-PR: a fork release-named PR is not a release PR" bash -c '[ "$1" = 0 ] && [[ $2 == *"n/a: not a release PR|"* ]] && ! grep -q "^workflow run" "$3"' _ "$RC" "$(statuses)" "$GHFX/log"
gh_reset; gh_accept "api -X POST repos/$SBX/statuses/$SHA *"; gh_fx 0 "" -- "${WF_RUN[@]}"
per_pr release-please--branches--main "$SBX" warn warn
check "per-PR: a release PR in warn posts nothing and dispatches gates-only" bash -c '[ "$1" = 0 ] && [ -z "$2" ] && grep -qx "workflow run deps-cascade.yml --ref main -f gates_only=true" "$3"' _ "$RC" "$(statuses)" "$GHFX/log"
gh_reset; gh_accept "api -X POST repos/$SBX/statuses/$SHA *"; gh_fx 0 "" -- "${WF_RUN[@]}"
per_pr release-please--branches--main "$SBX" enforce warn
check "per-PR: a release PR in enforce posts pending first" bash -c '[ "$1" = 0 ] && [ "$2" = "state=pending context=cascade/freshness description=evaluating in Deps cascade|" ]' _ "$RC" "$(statuses)"
gh_reset; gh_accept "api -X POST repos/$SBX/statuses/$SHA *"; gh_fx_err 1 "HTTP 403: workflow disabled" -- "${WF_RUN[@]}"
per_pr release-please--branches--main "$SBX" enforce warn
check "per-PR: a failed dispatch replaces pending and fails" bash -c '[ "$1" = 1 ] && [ "$2" = "$3" ]' _ "$RC" "$(statuses)" \
  "state=pending context=cascade/freshness description=evaluating in Deps cascade|state=error context=cascade/freshness description=could not dispatch Deps cascade, see the run|state=success context=cascade/settled description=WARN: gate could not run, see the run|"
gh_reset
per_pr feat/x "$SBX" strict warn
check "per-PR: a bad mode fails before any call" bash -c '[ "$1" = 1 ] && [ ! -s "$2" ]' _ "$RC" "$GHFX/log"

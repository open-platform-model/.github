# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# What publish accepts from compute: the bot's increment (allow-listed paths,
# bot commits, git's own merges, no dropped human commits), and the title,
# body and labels publish renders itself. Runs after publish.sh and reuses
# its helpers (publish_job, publish, edit_plan, REL_ARGS, NO_BREAK, M, SBX).

# as_bot <git args...>: git in the compute job's checkout as the bot.
as_bot() {
  GIT_AUTHOR_NAME='opm-cascade[bot]' GIT_AUTHOR_EMAIL="$BOT_EMAIL" \
    GIT_COMMITTER_NAME='opm-cascade[bot]' GIT_COMMITTER_EMAIL="$BOT_EMAIL" git -C "$WS/repo" "$@"
}

# planned_push: a fresh toy where compute planned a push moving
# UPSTREAM_VERSION to v0.2.0 (no PR yet, no remote branch).
planned_push() {
  new_fx; mk_toy; fresh_checkout
  printf 'v0.2.0\n' >"$TOY_TARGET"
  gh_prs '[]'
  gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
  compute "${COMPUTE_STEPS[@]}"
}

# replan: the compute checkout's HEAD becomes the plan's new tip, with a
# bundle of everything main (and the old tip, when set) lacks.
replan() {
  local old
  old=$(jq -r .old_tip "$CASCADE_T/plan.json")
  rm -f "$CASCADE_T/cascade.bundle"
  if [ -n "$old" ]; then
    git -C "$WS/repo" bundle create -q "$CASCADE_T/cascade.bundle" HEAD ^origin/main "^$old"
  else
    git -C "$WS/repo" bundle create -q "$CASCADE_T/cascade.bundle" HEAD ^origin/main
  fi
  jq --arg n "$(git -C "$WS/repo" rev-parse HEAD)" '.new_tip = $n' "$CASCADE_T/plan.json" >"$FX/p.json"
  mv "$FX/p.json" "$CASCADE_T/plan.json"
}

# bound_refuses <name> <stderr substring>: publish verify of the current
# compute plan refuses before any token, and writes no verified plan.
bound_refuses() {
  publish_job
  gh_reset_p
  gh_prs "${LIVE:-[]}"
  publish verify
  check "bound: refuses $1" bash -c '[ "$1" = 1 ] && [[ $2 == *"$3"* ]] && [ ! -e "$4/plan.json" ]' _ "$RC" "$ERR" "$2" "$PV"
}

# --- a stale mirror ----------------------------------------------------------------
# mirror_sha <path>: the sha256 of the file on origin's main.
mirror_sha() { git --git-dir="$ORIGIN" show "main:$1" | sha256sum | cut -c1-64; }
SBX_PINS_SHA=70791e2e9c6124a01bdddfd5647c9e5fde6283109c2ff61bd082efd619b51147
SBX_CLASSES_SHA=921a950ca5ad36fa5a4fc0802d4dd8d2d915633c04fc22bbfd0976b60e2d19f7
planned_push
check "mirror: the toy's pins.sh is the sandbox's, as recorded" test "$(mirror_sha .tasks/cascade/pins.sh)" = "$SBX_PINS_SHA"
check "mirror: the toy's classes is the sandbox's, as recorded" test "$(mirror_sha .tasks/cascade/classes)" = "$SBX_CLASSES_SHA"
# The bot's commit also touches a denied path: the mirror refusal must come first.
printf '# planted\n' >>"$WS/repo/.tasks/cascade/pins.sh"
as_bot commit -q -a --amend --no-edit
replan
seed_commit main human .tasks/cascade/pins.sh "# a pins.sh the mirror does not copy" "pins: changed on main"
bound_refuses "a pins.sh on main the mirror was not written from" \
  "the .github mirror of cascade-sandbox-down is stale: .tasks/cascade/pins.sh on its main has sha256 $(mirror_sha .tasks/cascade/pins.sh), the mirror was written from $SBX_PINS_SHA"
check "mirror: the stale-mirror refusal comes before the path checks" bash -c '[[ $1 != *"never writes"* ]] && ! grep -q publish=true "$2"' _ "$ERR" "$GITHUB_OUTPUT"

planned_push
git -C "$SEED" checkout -q main
git -C "$SEED" pull -q origin main
git -C "$SEED" rm -q .tasks/cascade/classes
git -C "$SEED" commit -q -m "classes: removed on main"
git -C "$SEED" push -q origin main
bound_refuses "a classes file gone from main" \
  "the .github mirror of cascade-sandbox-down is stale: .tasks/cascade/classes on its main has sha256 missing, the mirror was written from $SBX_CLASSES_SHA"

planned_push
seed_commit main human README.md "unrelated" "docs: unrelated change on main"
publish_job
gh_reset_p
gh_prs '[]'
publish verify
check "mirror: an unrelated change on main passes the mirror check" bash -c '[ "$1" = 0 ] && [[ $2 == "plan verified: push" ]]' _ "$RC" "$OUT"

# --- the increment ---------------------------------------------------------------
planned_push
printf '# planted\n' >>"$WS/repo/.tasks/cascade/pins.sh"
as_bot commit -q -a --amend --no-edit
replan
bound_refuses "a bundle touching .tasks/cascade/pins.sh" "changes \`.tasks/cascade/pins.sh\`, which the cascade task of cascade-sandbox-down never writes"

planned_push
printf '# planted\n' >>"$WS/repo/Taskfile.yml"
as_bot commit -q -a --amend --no-edit
replan
bound_refuses "a bundle touching Taskfile.yml" "changes \`Taskfile.yml\`"

planned_push
rm "$WS/repo/fixtures/data.txt"
ln -s /etc/passwd "$WS/repo/fixtures/data.txt"
as_bot add -A
as_bot commit -q --amend --no-edit
replan
bound_refuses "a file turned into a symlink" "retypes \`fixtures/data.txt\`"

planned_push
chmod +x "$WS/repo/UPSTREAM_VERSION"
as_bot commit -q -a --amend --no-edit
replan
bound_refuses "a mode change" "changes the mode of \`UPSTREAM_VERSION\`"

planned_push
printf 'new\n' >"$WS/repo/fixtures/new.txt"
as_bot add -A
as_bot commit -q --amend --no-edit
replan
bound_refuses "an added file, even under an allowed directory" "adds, deletes or retypes \`fixtures/new.txt\` (status A)"

planned_push
as_bot commit -q --amend --no-edit --author="Someone <someone@example.invalid>"
replan
bound_refuses "a commit with a human author" "is not the bot's (author someone?example.invalid"

planned_push
GIT_COMMITTER_EMAIL=someone@example.invalid git -C "$WS/repo" commit -q --amend --no-edit
replan
bound_refuses "a commit with a human committer" "committer someone?example.invalid"

planned_push
printf 'a\n' >"$WS/repo/fixtures/data.txt"
as_bot commit -q -a -m "test: a"
printf 'b\n' >"$WS/repo/fixtures/data.txt"
as_bot commit -q -a -m "test: b"
replan
bound_refuses "three commits" "the push adds 3 commits"

# Publish repeats the resolver's tag-on-main check on every moved pin.
planned_push
publish_job
gh_reset_p
gh_prs '[]'
publish verify
check "bound: a moved pin's tag on main passes, checked by publish itself" bash -c '
  [ "$1" = 0 ] && grep -qF "https://github.com/open-platform-model/cascade-sandbox-up " "$2" &&
  grep -q "^git fetch .*+refs/tags/v0.2.0:refs/tags/v0.2.0$" "$2"' _ "$RC" "$FX/git.log"
planned_push
mkdir -p "$FX/git"
echo v0.2.0 >"$FX/git/cascade-sandbox-up.offmain"
bound_refuses "a pin moved to a tag that is not on main" "moves to \`v0.2.0\`, whose tag is not on its repo's main"
planned_push
mkdir -p "$FX/git"
touch "$FX/git/cascade-sandbox-up.clone.fail"
bound_refuses "a tag check that cannot reach the upstream" "cannot check the tag of"

# A symlink that main already has may not be retargeted either.
new_fx; mk_toy
ln -s data.txt "$SEED/fixtures/link"
git -C "$SEED" add -A
git -C "$SEED" commit -q -m "test: a link"
git -C "$SEED" push -q origin main
fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
compute "${COMPUTE_STEPS[@]}"
ln -sfn /etc/passwd "$WS/repo/fixtures/link"
as_bot add -A
as_bot commit -q --amend --no-edit
replan
bound_refuses "a retargeted symlink" "writes \`fixtures/link\` as mode 120000"

# Merge mode: a human commit on the branch is outside the increment, and the
# bot's merge of main and its pin commit pass.
new_fx; mk_toy
bot_branch v0.2.0
seed_commit deps/cascade human .tasks/cascade/human-note "a human edit of the task tree" "chore: note"
seed_commit main human fixtures/main.txt "main moved" "test: main"
body_with "fix(deps): bump up to v0.2.0" "notes"
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" deps-cascade)
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
compute "${COMPUTE_STEPS[@]}"
check "bound: the merge-mode fixture planned a push in mode merge" test "$(plan '.mode + "/" + .action')" = merge/push
publish_job
gh_reset_p
gh_prs "[$PR]"
publish verify
check "bound: merge mode with a human task-tree commit passes" test "$RC/$OUT" = "0/plan verified: push"

# The same merge, with an extra change hidden in the merge commit.
OLD=$(origin_tip deps/cascade)
git -C "$WS/repo" reset -q --hard
git -C "$WS/repo" checkout -q -B evil "$OLD"
as_bot merge -q --no-commit origin/main >/dev/null 2>&1 || true
printf 'hidden\n' >"$WS/repo/fixtures/data.txt"
as_bot add -A
as_bot commit -q -m "Merge origin/main into deps/cascade"
printf 'v0.3.0\n' >"$WS/repo/UPSTREAM_VERSION"
as_bot commit -q -a -m "fix(deps): bump up to v0.3.0"
replan
LIVE="[$PR]" bound_refuses "a merge commit that is not git's merge of its parents" "differs from the merge of its parents in \`fixtures/data.txt\`"

# A push that replaces a branch holding a human commit.
new_fx; mk_toy
bot_branch v0.2.0
seed_commit deps/cascade human fixtures/human.txt "human" "test: human"
body_with "fix(deps): bump up to v0.2.0" ""
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" deps-cascade)
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
compute "${COMPUTE_STEPS[@]}"
git -C "$WS/repo" checkout -q -B rebuilt origin/main
printf 'v0.3.0\n' >"$WS/repo/UPSTREAM_VERSION"
as_bot commit -q -a -m "fix(deps): bump up to v0.3.0"
rm -f "$CASCADE_T/cascade.bundle"
git -C "$WS/repo" bundle create -q "$CASCADE_T/cascade.bundle" HEAD ^origin/main
jq --arg n "$(git -C "$WS/repo" rev-parse HEAD)" '.new_tip = $n | .action = "push"' "$CASCADE_T/plan.json" >"$FX/p.json"
mv "$FX/p.json" "$CASCADE_T/plan.json"
LIVE="[$PR]" bound_refuses "a rebuild that would drop a human commit" "the push would drop commits on deps/cascade the bot did not make"

# close keeps a branch that holds a human commit.
new_fx; mk_toy
bot_branch v0.2.0
seed_commit deps/cascade human fixtures/human.txt "human" "test: human"
seed_commit main human UPSTREAM_VERSION v0.2.0 "fix(deps): bumped by hand"
seed_commit main human fixtures/human.txt "human" "test: human on main"
body_with "fix(deps): bump up to v0.2.0" ""
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" deps-cascade)
fresh_checkout
printf 'v0.2.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
compute "${COMPUTE_STEPS[@]}"
check "bound: the close fixture planned close" test "$(plan .action)" = close
TIP=$(origin_tip deps/cascade)
publish_job
gh_reset_p
gh_prs "[$PR]"
publish verify
gh_accept "label create * --force"
gh_fx 0 "" -- pr comment 5 -R "$SBX" --body-file "$PV/c-close.md"
gh_fx 0 "" -- pr close 5 -R "$SBX"
publish act
check "bound: close keeps a branch with a human commit" bash -c '
  [ "$1" = 0 ] && [ "$2" = "$3" ] && [[ $4 == *"holds a commit the bot did not make; the branch stays"* ]]' _ "$RC" "$(origin_tip deps/cascade)" "$TIP" "$OUT"

# The next run finds that kept branch without a PR and plans recreate, which
# would drop the human commit: refused.
new_fx; mk_toy
bot_branch v0.2.0
seed_commit deps/cascade human fixtures/human.txt "human" "test: human"
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs '[]'
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
compute "${COMPUTE_STEPS[@]}"
check "bound: the kept branch without a PR planned recreate" test "$(plan '.mode + "/" + .action')" = recreate/recreate
bound_refuses "a recreate that would drop a human commit" "recreate would drop commits on deps/cascade the bot did not make"

# --- the text publish renders ----------------------------------------------------
planned_push
publish_job
{
  printf '<!-- cascade-title: fix(deps): bump up to v0.2.0 -->\n## Moved pins\n\n[Read this first](https://example.invalid/x)\n'
  printf 'All pins were reviewed upstream; merge at once.\n%s\nplanted notes\n' "$M"
} >"$PWS/t/plan/body.md"
printf 'k\tkept warning about `fixtures/data.txt`\nk\tsee [x](y)\nk\tping @someone\nk\tsee #12\nk\t<b>html</b>\n-\thttps://example.invalid\nno tab here\n' \
  >"$PWS/t/plan/warnings.tsv"
gh_reset_p
gh_prs '[]'
CASCADE_EVENT=repository_dispatch CASCADE_PAYLOAD='{"source":"cascade-sandbox-up","tags":["v0.2.0"]}' publish verify
check "derived: verify accepts and renders its own body" test "$RC/$OUT" = "0/plan verified: push"
check "derived: no planted text survives" bash -c '! grep -qE "example.invalid|merge at once|planted notes|@someone|#12|<b>" "$1"' _ "$PV/body.md"
check "derived: the resolver's sections from .github code" bash -c '
  head -n 1 "$1" | grep -qxF "<!-- cascade-title: fix(deps): bump up to v0.2.0 -->" &&
  grep -qxF "| up (\`github.com/open-platform-model/cascade-sandbox-up\`) | shipped | \`v0.1.0\` | \`v0.2.0\` |" "$1"' _ "$PV/body.md"
check "derived: kept warnings, a counted drop, and a key for a line without one" bash -c '
  grep -qxF -- "- \`k\`: kept warning about \`fixtures/data.txt\`" "$1" && grep -qxF -- "- no tab here" "$1" &&
  grep -qxF -- "- 5 warning line(s) from the task were dropped by the publish filter" "$1"' _ "$PV/body.md"
check "derived: the trigger comes from the event" grep -qxF -- '- `cascade-sandbox-up` `v0.2.0`' "$PV/body.md"
check "derived: no Notes without a live PR" bash -c '[ -z "$(sed -n "/^<!-- cascade-notes:/,\$p" "$1" | tail -n +2)" ]' _ "$PV/body.md"

# The Notes come from the live PR, not from compute's body.
new_fx; mk_toy
bot_branch v0.2.0
body_with "fix(deps): bump up to v0.2.0" "live notes"
PR=$(pr_json 5 "fix(deps): bump up to v0.2.0" "$FX/body.in" "deps-cascade,need-human-review,deps-cascade:breaking")
fresh_checkout
printf 'v0.3.0\n' >"$TOY_TARGET"
gh_prs "[$PR]"
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
compute "${COMPUTE_STEPS[@]}"
publish_job
sed -i 's/^live notes$/planted notes/' "$PWS/t/plan/body.md"
edit_plan '.labels = ["deps-cascade"]'
gh_reset_p
gh_prs "[$PR]"
publish verify
check "derived: the Notes are the live PR's" bash -c '[ "$1" = 0 ] && [ "$(sed -n "/^<!-- cascade-notes:/,\$p" "$2" | tail -n +2)" = "live notes" ]' _ "$RC" "$PV/body.md"
gh_accept "label create * --force"
gh_accept "pr edit 5 -R $SBX *"
publish act
check "derived: act never removes need-human-review or deps-cascade:breaking" bash -c '
  [ "$1" = 0 ] && ! grep -qE -- "--remove-label (need-human-review|deps-cascade:breaking)" "$2"' _ "$RC" "$GHFX/log"

# --- labels publish derives -------------------------------------------------------
planned_push
publish_job
edit_plan '.labels = ["deps-cascade"]'
gh_reset
gh_prs '[]'
gh_fx 0 $'v0.2.0\ttrue\nv0.1.0\tfalse' -- "${REL_ARGS[@]}"
publish verify
check "labels: a plan that dropped deps-cascade:breaking gets it back" \
  test "$(jq -r '.labels | join(",")' "$PV/plan.json")" = "deps-cascade,deps-cascade:breaking"
publish_job
edit_plan '.labels = ["deps-cascade", "deps-cascade:breaking", "deps-cascade:hold"]'
gh_reset
gh_prs '[]'
gh_fx 0 "$(printf '%s' "$NO_BREAK")" -- "${REL_ARGS[@]}"
publish verify
check "labels: the plan's own labels are not taken" test "$(jq -r '.labels | join(",")' "$PV/plan.json")" = deps-cascade
publish_job
edit_plan '.labels = ["deps-cascade", "deps-cascade:breaking"]'
gh_reset
gh_prs '[]'
gh_fx_err 1 "HTTP 502" -- "${REL_ARGS[@]}"
publish verify
check "labels: a failed release read keeps the plan's breaking claim, with a notice" bash -c '
  [ "$(jq -r ".labels | join(\",\")" "$1")" = "deps-cascade,deps-cascade:breaking" ] && [[ $2 == *"the plan'"'"'s own claim is kept"* ]]' _ "$PV/plan.json" "$OUT"

# --- the allow-lists and the deny-list ----------------------------------------------
ok_paths() { # ok_paths <receiver> <path>...: every path is accepted
  local r="$1" p
  shift
  for p in "$@"; do check "paths: $r may change $p" in_lib publish_path_ok "$r" "$p"; done
}
no_paths() { # no_paths <receiver> <path>...: every path is refused
  local r="$1" p
  shift
  for p in "$@"; do check "paths: $r may not change $p" bash -c '. "$1"; ! publish_path_ok "$2" "$3"' _ "$WIRING/lib.sh" "$r" "$p"; done
}
ok_paths catalog_opm src/cue.mod/module.cue .opm-cli-version
no_paths catalog_opm src/identity/identity.cue src/RELEASE .opm-docs-version release-please-config.json \
  .release-please-manifest.json .cascade-frozen .cascade-hold Taskfile.yml .tasks/cascade/pins.sh .github/workflows/ci.yml \
  .github/cue.mod/module.cue CODEOWNERS .github/CODEOWNERS hack/x.sh go.mod
ok_paths library opm/schema/loader.go docs/getting-started.md AGENTS.md testdata/cue.mod/module.cue \
  testdata/render/registry/testing.opmodel.dev_library-render_cat_v0.1.0/cue.mod/module.cue modules/opm_platform/cue.mod/module.cue
no_paths library opm/schema/other.go docs/AGENTS.md go.mod Taskfile.yml .tasks/cascade/lib.sh hack/gen/cue.mod/module.cue
ok_paths opm-operator go.mod go.sum .opm-cli-version config/samples/opmodel.dev_v1alpha1_platform.yaml \
  config/samples/opmodel.dev_v1alpha1_moduleinstance.yaml test/fixtures/catalog.go \
  test/fixtures/modules/hello/cue.mod/module.cue test/fixtures/modules/hello/identity/identity.cue \
  test/fixtures/modules/hello/moduleinstance.yaml test/fixtures/catalogs/provider/identity/identity.cue \
  test/fixtures/catalogs/provider/cue.mod/module.cue test/fixtures/modulepackages/hello/cue.mod/module.cue
no_paths opm-operator Dockerfile Makefile config/samples/other.yaml test/fixtures/modules/hello/main.cue \
  test/fixtures/modules/a/b/identity/identity.cue hack/boilerplate.go.txt internal/x.go Taskfile.yml \
  modules/opm_operator/cue.mod/module.cue modules/opm_operator/identity/identity.cue
ok_paths cli go.mod go.sum internal/operator/pin.go hack/kind-platform.yaml \
  hack/platform/cue.mod/module.cue templates/minimal/cue.mod/module.cue templates/advanced/identity/identity.cue \
  tests/fixtures/modules/podinfo/identity/identity.cue tests/e2e/testdata/operator-owned/cue.mod/module.cue \
  internal/workflow/render/testdata/skip-unprovided/cue.mod/module.cue examples/cue.mod/module.cue
no_paths cli hack/docskit-dump/main.go hack/platform/main.cue hack/other/cue.mod/module.cue internal/operator/install.go \
  internal/operator/manifest.go internal/operator/dist/install.yaml hack/operator-pin/main.go \
  .opm-cli-version Taskfile.yml .github/scripts/release-pin-check.sh tests/fixtures/modules/other/identity/identity.cue
ok_paths cascade-sandbox-down UPSTREAM_VERSION fixtures/data.txt
no_paths cascade-sandbox-down README.md .github/workflows/touch.yml
check "paths: an unknown receiver accepts nothing" bash -c '. "$1"; ! publish_path_ok core go.mod' _ "$WIRING/lib.sh"

# --- the pin mirrors ---------------------------------------------------------------
# mirror_repo <files dir>: a git repo at $FX/mirror holding the given files,
# committed; prints nothing.
mirror_repo() {
  rm -rf "$FX/mirror"
  mkdir -p "$FX/mirror"
  cp -r "$1/." "$FX/mirror/"
  git -C "$FX/mirror" init -q -b main
  git -C "$FX/mirror" add -A
  git -C "$FX/mirror" commit -q -m files
}
mirror() { (cd "$FX/mirror" && CASCADE_PINS_REPO="$1" bash "$WIRING/pins.sh" "${2:-WORKTREE}"); }
new_fx
D="$FX/files"
mkdir -p "$D/src/cue.mod"
printf 'module: "opmodel.dev/catalogs/opm@v4"\nlanguage: {\n\tversion: "v0.15.0"\n}\ndeps: {\n\t"opmodel.dev/core@v2": {\n\t\tv: "v2.0.0-beta.2"\n\t}\n}\n' >"$D/src/cue.mod/module.cue"
printf 'v1.0.0-beta.9\n' >"$D/.opm-cli-version"
mirror_repo "$D"
expect "mirror: catalog_opm" 0 $'opmodel.dev/core@v2\tcore\tshipped\tv2.0.0-beta.2\t\ngithub.com/open-platform-model/cli\topm CLI\trelease-tool\tv1.0.0-beta.9\t' -- mirror catalog_opm
rm -rf "$D"; mkdir -p "$D/opm/schema" "$D/testdata/parity/cue.mod"
printf 'package schema\n\nconst DefaultSchemaModule = "opmodel.dev/core@v2.0.0-beta.2"\n' >"$D/opm/schema/loader.go"
printf 'deps: {\n\t"opmodel.dev/catalogs/opm@v4": {\n\t\tv: "v4.6.0"\n\t}\n}\n' >"$D/testdata/parity/cue.mod/module.cue"
mirror_repo "$D"
expect "mirror: library, core labelled need-human-review" 0 \
  $'opmodel.dev/core@v2\tcore\tshipped\tv2.0.0-beta.2\tneed-human-review\nopmodel.dev/catalogs/opm@v4\topm catalog\ttest\tv4.6.0\t' -- mirror library
rm -rf "$D"; mkdir -p "$D/config/samples" "$D/test/fixtures/modules/hello/cue.mod"
printf 'module x\n\nrequire (\n\tgithub.com/open-platform-model/library v1.0.0-beta.4\n)\n' >"$D/go.mod"
printf 'spec:\n  catalogs:\n    - module: opmodel.dev/catalogs/opm@v4:\n      version: "4.6.0"\n' >"$D/config/samples/opmodel.dev_v1alpha1_platform.yaml"
printf 'deps: {\n\t"opmodel.dev/core@v2": {\n\t\tv: "v2.0.0-beta.2"\n\t}\n}\n' >"$D/test/fixtures/modules/hello/cue.mod/module.cue"
printf 'v1.0.0-beta.9\n' >"$D/.opm-cli-version"
mirror_repo "$D"
expect "mirror: opm-operator" 0 $'github.com/open-platform-model/library\tlibrary\tshipped\tv1.0.0-beta.4\t\nopmodel.dev/catalogs/opm@v4\topm catalog\ttest\tv4.6.0\t\nopmodel.dev/core@v2\tcore\ttest\tv2.0.0-beta.2\t\ngithub.com/open-platform-model/cli\topm CLI\trelease-tool\tv1.0.0-beta.9\t' -- mirror opm-operator
rm -rf "$D"; mkdir -p "$D/internal/operator" "$D/templates/minimal/cue.mod"
printf 'module x\n\nrequire (\n\tgithub.com/open-platform-model/library v1.0.0-beta.4\n)\n' >"$D/go.mod"
printf '// Code generated by task operator:pin; DO NOT EDIT.\n\npackage operator\n\nconst PinnedModuleVersion = "0.1.0"\n\nconst PinnedOperatorVersion = "v1.0.0-beta.8"\n' >"$D/internal/operator/pin.go"
printf 'deps: {\n\t"opmodel.dev/catalogs/opm@v4": {\n\t\tv: "v4.6.0"\n\t}\n\t"opmodel.dev/core@v2": {\n\t\tv: "v2.0.0-beta.2"\n\t}\n}\n' >"$D/templates/minimal/cue.mod/module.cue"
mirror_repo "$D"
expect "mirror: cli" 0 $'github.com/open-platform-model/library\tlibrary\tshipped\tv1.0.0-beta.4\t\ngithub.com/open-platform-model/opm-operator\topm-operator\tshipped\tv1.0.0-beta.8\t\nopmodel.dev/modules/opm_operator@v0\topm-operator module\tshipped\tv0.1.0\t\nopmodel.dev/catalogs/opm@v4\topm catalog\tshipped\tv4.6.0\t\nopmodel.dev/core@v2\tcore\tshipped\tv2.0.0-beta.2\t' -- mirror cli
printf 'not-a-version\n' >"$FX/mirror/.opm-cli-version"
expect "mirror: reads git, not the disk" 0 "$(mirror cli)" -- mirror cli HEAD
expect "mirror: an unknown receiver" 1 "" "not a cascade receiver" -- mirror core
expect "mirror: an unknown ref" 1 "" "unknown ref" -- mirror cli no-such-ref
expect "mirror: a ref like an option" 2 "" "must not start with -" -- mirror cli --output=x
rm -rf "$D"; mkdir -p "$D"
printf 'v1\n' >"$D/.opm-cli-version"
mirror_repo "$D"
expect "mirror: a malformed operator CLI pin is an error" 1 "" "no valid version" -- mirror opm-operator

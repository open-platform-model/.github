# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# Static checks of the reusable cascade workflows and the composite cascade
# actions: no expression inside a run: block, no secrets input and no
# Environment in a reusable workflow, explicit permissions on every job,
# every third-party action pinned to a commit SHA, one identical Guard step
# first in every job and every action, scripts only from the pinned .github
# commit (no org-github-ref), the publish dry-run input, and SHA-pinned
# cascade references in the README shapes and the sandbox callers.

new_fx

# inline_expr <workflow>: prints the jobs/steps whose run: holds ${{.
inline_expr() {
  yq -r '.jobs | to_entries[] | .key as $j | .value.steps[]? | select((.run // "") | test("\$\{\{")) | $j + "/" + (.name // "?")' "$1"
}
printf 'on: workflow_call\njobs:\n  a:\n    runs-on: x\n    steps:\n      - name: bad\n        run: echo "${{ inputs.x }}"\n' >"$FX/bad.yml"
expect "static: an inline expression in run: is found" 0 "a/bad" -- inline_expr "$FX/bad.yml"

REUSABLE=()
for wf in cascade-receive cascade-gates; do
  REUSABLE+=("$WORKFLOWS/$wf.yml")
done
check "static: no reusable notify workflow is left (E1: notify is a composite action)" test ! -e "$WORKFLOWS/cascade-notify.yml"
GUARD_TEXT=""
for f in "${REUSABLE[@]}"; do
  n="${f##*/}"
  expect "static: $n has no expression inside run:" 0 "" -- inline_expr "$f"
  expect "static: $n is only workflow_call" 0 "workflow_call" -- yq -r '.on | keys | join(",")' "$f"
  expect "static: $n declares no secrets input" 0 "null" -- yq -r '.on.workflow_call.secrets' "$f"
  expect "static: $n has no job in an Environment (E1: its secrets would be empty)" 0 "" -- \
    yq -r '.jobs | to_entries[] | select(.value.environment != null) | .key' "$f"
  check "static: $n reads no secret" bash -c '! grep -n "secrets\." "$1"' _ "$f"
  expect "static: $n gives every job explicit permissions" 0 "" -- yq -r '.jobs | to_entries[] | select(.value.permissions == null) | .key' "$f"
  check "static: $n pins every action to a SHA with a version comment" bash -c '
    ! grep -nE "^ *(- )?uses:" "$1" | grep -vE "uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40} # v[0-9]"' _ "$f"
  expect "static: $n has the Guard step first in every job" 0 "" -- \
    yq -r '.jobs | to_entries[] | select(.value.steps[0].name != "Guard" or .value.steps[0].id != "guard") | .key' "$f"
  check "static: $n reads the repo name only from the Guard step" bash -c '! grep -n "event.repository.name" "$1"' _ "$f"
  for j in $(yq -r '.jobs | keys | .[]' "$f"); do
    t=$(yaml_run "$f" "$j" Guard)
    if [ -z "$GUARD_TEXT" ]; then GUARD_TEXT="$t"; fi
    check "static: $n job $j has the same Guard text" test "$t" = "$GUARD_TEXT"
  done
  check "static: $n names no org-github-ref" bash -c '! grep -nE "org-github-ref|INPUTS_REF" "$1"' _ "$f"
  # Every checkout of this repo is at the workflow's own commit, read by
  # the Own commit step before it.
  expect "static: $n checks this repo out only at its own commit" 0 "" -- \
    yq -r '.jobs | to_entries[] | .key as $j | .value.steps[]? | select(.with.repository == "open-platform-model/.github")
      | select(.with.ref != "${{ steps.own.outputs.sha }}") | $j + "/" + .name' "$f"
  for j in $(yq -r '.jobs | keys | .[]' "$f"); do
    o=$(J="$j" yq -r '.jobs[strenv(J)].steps | to_entries | map(select(.value.id == "own")) | .[0].key // ""' "$f")
    c=$(J="$j" yq -r '.jobs[strenv(J)].steps | to_entries | map(select(.value.with.repository == "open-platform-model/.github")) | .[0].key // ""' "$f")
    [ -n "$c" ] || continue
    check "static: $n job $j has the Own commit step before its checkout of this repo" bash -c '[ -n "$1" ] && [ "$1" -lt "$2" ]' _ "$o" "$c"
  done
done
OWN_TEXT=$(yaml_run "$WORKFLOWS/cascade-receive.yml" compute "Own commit")
for j in compute gates; do
  check "static: cascade-receive.yml job $j has the same Own commit text" test "$(yaml_run "$WORKFLOWS/cascade-receive.yml" "$j" "Own commit")" = "$OWN_TEXT"
  expect "static: cascade-receive.yml job $j reads its own commit from the job context" 0 \
    $'${{ job.workflow_repository }}\n${{ job.workflow_sha }}' -- \
    env J="$j" yq -r '.jobs[strenv(J)].steps[] | select(.id == "own") | (.env.WF_REPO, .env.WF_SHA)' "$WORKFLOWS/cascade-receive.yml"
done
# own <workflow_repository> <workflow_sha>: runs the inline Own commit step.
own() {
  : >"$FX/oout"
  local rc=0
  env WF_REPO="$1" WF_SHA="$2" GITHUB_OUTPUT="$FX/oout" bash -e -o pipefail -c "$OWN_TEXT" || rc=$?
  cat "$FX/oout"
  return "$rc"
}
SHA40=0123456789abcdef0123456789abcdef01234567
expect "own commit: this repo at a full SHA" 0 $'::notice::scripts from open-platform-model/.github '"$SHA40"$'\nsha='"$SHA40" -- \
  own open-platform-model/.github "$SHA40"
own_fails() { # own_fails <name> <workflow_repository> <workflow_sha>
  run own "$2" "$3"
  check "own commit: $1" bash -c '[ "$1" = 1 ] && [[ $2 == "::error::cannot tell the open-platform-model/.github commit"* ]]' _ "$RC" "$OUT"
}
own_fails "an empty SHA fails (it would check out the default branch)" open-platform-model/.github ""
own_fails "a short SHA fails" open-platform-model/.github 0123456
own_fails "a branch name fails" open-platform-model/.github main
own_fails "another repo fails" someone-else/.github "$SHA40"
own_fails "an empty repo fails" "" "$SHA40"

# The composite actions the caller's own cascade-Environment job runs.
for a in cascade-notify cascade-publish; do
  f="$ORG_ROOT/.github/actions/$a/action.yml"
  n="actions/$a"
  check "static: $n exists" test -f "$f"
  [ -f "$f" ] || continue
  expect "static: $n is a composite action" 0 composite -- yq -r '.runs.using' "$f"
  expect "static: $n has no expression inside run:" 0 "" -- \
    yq -r '.runs.steps[] | select((.run // "") | test("\$\{\{")) | .name' "$f"
  expect "static: $n gives every run step bash" 0 "" -- yq -r '.runs.steps[] | select(.run != null and .shell != "bash") | .name' "$f"
  check "static: $n pins every action to a SHA with a version comment" bash -c '
    ! grep -nE "^ *(- )?uses:" "$1" | grep -vE "uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40} # v[0-9]"' _ "$f"
  expect "static: $n has the Guard step first" 0 "Guard/guard" -- yq -r '.runs.steps[0].name + "/" + .runs.steps[0].id' "$f"
  check "static: $n reads no secret and no event repository name" bash -c '! grep -nE "\\$\\{\\{[^}]*secrets\.|event\.repository\.name" "$1"' _ "$f"
  expect "static: $n takes the key as a required input" 0 "true" -- yq -r '.inputs["private-key"].required' "$f"
  t=$(yq -r '.runs.steps[] | select(.name == "Guard") | .run' "$f")
  check "static: $n has the same Guard text" test "$t" = "$GUARD_TEXT"
  # M2: the scripts come from the action's own directory, at the SHA the
  # caller pinned; nothing checks out another .github ref.
  check "static: $n names no org-github-ref" bash -c '! grep -nE "org-github|INPUTS_REF" "$1"' _ "$f"
  expect "static: $n checks out no other repository" 0 "" -- \
    yq -r '.runs.steps[] | select(.with.repository != null) | .name' "$f"
  expect "static: $n runs its scripts only from GITHUB_ACTION_PATH" 0 "" -- \
    yq -r '.runs.steps[] | select((.run // "") | test("\\.sh")) | select((.run // "") | test("bash \"\\$GITHUB_ACTION_PATH/\\.\\./\\.\\./scripts/cascade/wiring/[a-z-]+\\.sh\"") | not) | .name' "$f"
done
# M1: the stop switch is a required input the action passes to verify and
# act; the scripts enforce it (publish cases).
PUB="$ORG_ROOT/.github/actions/cascade-publish/action.yml"
expect "static: actions/cascade-publish takes a required dry-run input" 0 "true" -- yq -r '.inputs["dry-run"].required' "$PUB"
expect "static: actions/cascade-publish passes dry-run to verify and act" 0 $'verify ${{ inputs.dry-run }}\nact ${{ inputs.dry-run }}' -- \
  yq -r '.runs.steps[] | select(.id == "verify" or .name == "Act") | ((.id // "act") + " " + .env.CASCADE_PUBLISH_DRY_RUN)' "$PUB"
# A gates-only run never publishes: the caller's own input, required, reaches
# both script steps (the publish cases show the scripts refuse it).
expect "static: actions/cascade-publish takes a required gates-only input" 0 "true" -- yq -r '.inputs["gates-only"].required' "$PUB"
expect "static: actions/cascade-publish passes gates-only to verify and act" 0 $'verify ${{ inputs.gates-only }}\nact ${{ inputs.gates-only }}' -- \
  yq -r '.runs.steps[] | select(.id == "verify" or .name == "Act") | ((.id // "act") + " " + .env.CASCADE_PUBLISH_GATES_ONLY)' "$PUB"
# The reusable workflow's outputs for a gates-only run come from its input,
# not from a step the release heads' code ran in.
RECV="$WORKFLOWS/cascade-receive.yml"
expect "static: cascade-receive.yml takes action from the input on a gates-only run" 0 \
  "\${{ inputs.gates-only && 'gates-only' || steps.plan.outputs.action }}" -- yq -r '.jobs.compute.outputs.action' "$RECV"
expect "static: cascade-receive.yml reports compute-ok false on a gates-only run" 0 \
  "\${{ !inputs.gates-only && steps.done.outputs.ok == 'true' && 'true' || 'false' }}" -- yq -r '.jobs.compute.outputs.ok' "$RECV"
# No compute step from the first one that runs repo code (Gates: the release
# heads' task) on is given a token; the two Read steps before it are the only
# ones that are.
expect "static: cascade-receive.yml gives the token only to Read gates and Read state, both before Gates" 0 \
  $'gates-read\nstate' -- yq -r '.jobs.compute.steps | to_entries | map(select((.value.env // {} | to_entries | map(.value) | join(" ")) | test("github\\.token|secrets\\."))) | .[].value.id' "$RECV"
check "static: cascade-receive.yml runs the repo-code steps after both Read steps" bash -c '
  idx() { I="$1" yq ".jobs.compute.steps | to_entries | map(select(.value.id == strenv(I))) | .[0].key" "$2"; }
  [ "$(idx state "$1")" -lt "$(idx gates "$1")" ] && [ "$(idx gates-read "$1")" -lt "$(idx gates "$1")" ] &&
  [ "$(idx gates "$1")" -lt "$(idx run "$1")" ] && [ "$(idx run "$1")" -lt "$(idx text "$1")" ]' _ "$RECV"
check "static: cascade-receive.yml passes no token as an action input in compute" bash -c '
  ! yq -r ".jobs.compute.steps[].with // {} | to_entries[] | .value" "$1" | grep -qE "github\.token|secrets\."' _ "$RECV"
expect "static: cascade-receive.yml runs Gates even when Read state failed" 0 "\${{ !cancelled() && steps.gates-read.outcome == 'success' }}" -- \
  yq -r '.jobs.compute.steps[] | select(.id == "gates") | .if' "$RECV"
# Repo code in compute could otherwise poison the cache main's publish jobs
# restore: no step of the reusable workflows or actions saves or restores one.
expect "static: compute's setup-go saves and restores no cache" 0 false -- \
  yq -r '.jobs.compute.steps[] | select(.uses // "" | test("^actions/setup-go@")) | .with.cache' "$RECV"
check "static: no cascade workflow or action uses a cache action or type=gha" bash -c '
  ! grep -nE "uses: [^ ]*cache|type=gha" "$@"' _ "$WORKFLOWS"/cascade-*.yml "$ORG_ROOT"/.github/actions/cascade-*/action.yml
check "static: Post gates evaluates G3 and compute does not" bash -c '
  grep -q "g3_eval \"\$REPO\"" "$1" && ! grep -qE "^[^#]*(g3_eval|g3\(\))" "$2"' _ "$GATES_POST" "$GATES_EVAL"
expect "static: cascade-receive.yml takes dry-run from Init" 0 '${{ steps.init.outputs.dry_run }}' -- yq -r '.jobs.compute.outputs.dry_run' "$RECV"
expect "static: actions/cascade-notify mints for the targets only" 0 '${{ steps.validate.outputs.targets }}' -- \
  yq -r '.runs.steps[] | select(.id == "mint") | .with.repositories' "$ORG_ROOT/.github/actions/cascade-notify/action.yml"
expect "static: actions/cascade-publish mints for the calling repo only, after verify" 0 \
  $'${{ steps.guard.outputs.repo }}\nsteps.verify.outputs.publish == \'true\'' -- \
  yq -r '.runs.steps[] | select(.id == "mint") | (.with.repositories, .if)' "$ORG_ROOT/.github/actions/cascade-publish/action.yml"

# compute's tools come from wiring/install-tools.sh: fixed versions, sha256.
expect "static: compute installs no tool through a version-range action" 0 "" -- \
  yq -r '.jobs.compute.steps[] | select(.uses // "" | test("setup-task|setup-cue")) | .uses' "$RECV"
expect "static: compute's install step runs the pinned installer with the cue input" 0 \
  $'bash org-github/.github/scripts/cascade/wiring/install-tools.sh "$CUE_INPUT"\n${{ inputs.setup-cue && inputs.cue-version || \'none\' }}' -- \
  yq -r '.jobs.compute.steps[] | select(.name == "Set up Task and CUE") | (.run, .env.CUE_INPUT)' "$RECV"
check "static: compute installs its tools before Init" bash -c '
  idx() { N="$1" yq ".jobs.compute.steps | to_entries | map(select(.value.name == strenv(N))) | .[0].key" "$2"; }
  [ "$(idx "Set up Task and CUE" "$1")" -lt "$(idx Init "$1")" ]' _ "$RECV"
INSTALL="$WIRING/install-tools.sh"
mkdir -p "$FX/rel/go-task/task/releases/download/v3.53.1" "$FX/tbin"
printf 'not task\n' >"$FX/tbin/task"
tar -czf "$FX/rel/go-task/task/releases/download/v3.53.1/task_linux_amd64.tar.gz" -C "$FX/tbin" task
inst() { # inst <cue> [<arch>]: the installer against the fixture releases
  : >"$FX/gpath"
  run env CASCADE_TOOLS_BASE="file://$FX/rel" CASCADE_TOOLS_DIR="$FX/tools/$1" CASCADE_TOOLS_ARCH="${2:-Linux x86_64}" \
    GITHUB_PATH="$FX/gpath" bash "$INSTALL" "$1"
}
inst none
check "install: an archive whose sha256 differs is refused, nothing on PATH" bash -c '
  [ "$1" = 1 ] && [[ $2 == *"the sha256 of task_linux_amd64.tar.gz is not a54a408f"* ]] && [ ! -s "$3" ] && [ ! -e "$4/bin/task" ]' _ "$RC" "$ERR" "$FX/gpath" "$FX/tools/none"
inst v0.18.0
check "install: a cue-version without a checksum is exit 2 before any download" bash -c '
  [ "$1" = 2 ] && [[ $2 == *"cue-version \`v0.18.0\` has no checksum in .github"* ]] && [ ! -e "$3/dl/task_linux_amd64.tar.gz" ]' _ "$RC" "$ERR" "$FX/tools/v0.18.0"
inst v0.17.1 "Darwin arm64"
check "install: another runner is exit 2" bash -c '[ "$1" = 2 ] && [[ $2 == *"only Linux x64"* ]]' _ "$RC" "$ERR"
run env CASCADE_TOOLS_BASE=https://example.invalid CASCADE_TOOLS_DIR="$FX/tools" CASCADE_TOOLS_ARCH="Linux x86_64" bash "$INSTALL" none
check "install: another download host is exit 2" bash -c '[ "$1" = 2 ] && [[ $2 == *"CASCADE_TOOLS_BASE must be"* ]]' _ "$RC" "$ERR"
run bash "$INSTALL"
check "install: no argument is usage" test "$RC" = 2
check "install: Task is one fixed version with its sha256, never a range" bash -c '
  grep -qx "TASK_VERSION=v3.53.1" "$1" && grep -qx "TASK_SHA256=a54a408f6861ff921f6e87774180db31bacd8c1e7c944ca696db9fea49a82fc7" "$1"' _ "$INSTALL"
check "install: the CUE default has a checksum" bash -c '
  d=$(yq -r ".on.workflow_call.inputs[\"cue-version\"].default" "$1"); grep -q "^    $d) echo [0-9a-f]\{64\} ;;" "$2"' _ "$RECV" "$INSTALL"

if [ -n "$GUARD_TEXT" ]; then
  # guard <GITHUB_REPOSITORY>: runs the inline Guard step.
  guard() {
    : >"$FX/gout"
    local rc=0
    env GITHUB_REPOSITORY="$1" GITHUB_OUTPUT="$FX/gout" bash -e -o pipefail -c "$GUARD_TEXT" || rc=$?
    cat "$FX/gout"
    return "$rc"
  }
  NOT_ORG="is not a repo of open-platform-model"
  check "guard: reads no input" bash -c '! grep -q INPUTS_REF <<<"$1"' _ "$GUARD_TEXT"
  expect "guard: a production repo" 0 $'::notice::repo library\nrepo=library' -- guard open-platform-model/library
  expect "guard: a sandbox repo" 0 $'::notice::repo cascade-sandbox-down\nrepo=cascade-sandbox-down' -- \
    guard open-platform-model/cascade-sandbox-down
  expect "guard: a foreign owner fails" 1 "::error::\`someone-else/core\` $NOT_ORG" -- guard someone-else/core
  expect "guard: a look-alike owner fails" 1 "::error::\`open-platform-model-x/cascade-sandbox-down\` $NOT_ORG" -- \
    guard open-platform-model-x/cascade-sandbox-down
  expect "guard: an empty name fails" 1 "::error::\`open-platform-model/\` $NOT_ORG" -- guard open-platform-model/
  expect "guard: no repository fails" 1 "::error::\`\` $NOT_ORG" -- guard ""
  expect "guard: a name with a newline fails" 1 "::error::\`open-platform-model/a"$'\n'"repo=core\` $NOT_ORG" -- guard "open-platform-model/a"$'\n'"repo=core"
fi

# The receiver caller's concurrency group (Phase 3 wiring contract, section
# 5), byte for byte, in the README's caller shape.
CONTRACT_GROUP="\${{ github.ref != 'refs/heads/main' && format('deps-cascade-{0}', github.ref) || (inputs.gates_only && 'deps-cascade-gates' || 'deps-cascade') }}"
check "static: the README's receiver caller uses the contract's concurrency group" grep -qxF "  group: $CONTRACT_GROUP" "$ORG_ROOT/README.md"
# The sandbox caller committed with the change (before or after its archive).
for seed in "$ORG_ROOT"/openspec/changes/add-release-cascade-workflows/sandbox/down/.github/workflows/deps-cascade.yml \
  "$ORG_ROOT"/openspec/changes/archive/*-add-release-cascade-workflows/sandbox/down/.github/workflows/deps-cascade.yml; do
  [ -f "$seed" ] || continue
  expect "static: the sandbox receiver caller uses the contract's concurrency group" 0 "$CONTRACT_GROUP" -- \
    yq -r '.concurrency.group' "$seed"
done

# --- caller shapes: the README and the sandbox callers ------------------------

# readme_block <heading text>: the yaml block after the README line that
# starts with that bold heading.
readme_block() {
  H="$1" awk 'index($0, ENVIRON["H"]) == 1 { f = 1; next } f && /^```yaml$/ { p = 1; next } p && /^```$/ { exit } p' "$ORG_ROOT/README.md"
}
readme_block "**Receiver caller**" >"$FX/readme-receiver.yml"
readme_block "**Notify caller**" >"$FX/readme-notify.yml"
readme_block "**Per-PR gates caller**" >"$FX/readme-gates.yml"
DRY_EXPR="\${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}"
check "static: the README has the three caller shapes" bash -c '[ -s "$1" ] && [ -s "$2" ] && [ -s "$3" ]' _ \
  "$FX/readme-receiver.yml" "$FX/readme-notify.yml" "$FX/readme-gates.yml"
expect "static: the README receiver passes the stop switch to the reusable job" 0 "$DRY_EXPR" -- \
  yq -r '.jobs.cascade.with["dry-run"]' "$FX/readme-receiver.yml"
expect "static: the README publish job passes the stop switch to cascade-publish" 0 "$DRY_EXPR" -- \
  yq -r '.jobs.publish.steps[] | select(.uses | test("cascade-publish@")) | .with["dry-run"]' "$FX/readme-receiver.yml"
expect "static: the README publish job passes its own gates_only input to cascade-publish" 0 "\${{ inputs.gates_only == true }}" -- \
  yq -r '.jobs.publish.steps[] | select(.uses | test("cascade-publish@")) | .with["gates-only"]' "$FX/readme-receiver.yml"
check "static: the README publish if: reads the caller's own gates_only input" bash -c '[[ $(yq -r ".jobs.publish.if" "$1") == *"&& inputs.gates_only != true"* ]]' _ "$FX/readme-receiver.yml"
check "static: the README publish if: reads no gates-only output of the reusable job" bash -c '! yq -r ".jobs.publish.if" "$1" | grep -q "needs.cascade.outputs.gates"' _ "$FX/readme-receiver.yml"
check "static: the README names no cascade reference at main or a branch" bash -c '
  ! grep -nE "open-platform-model/\.github/\.github/[^@ ]+@" "$1" | grep -vE "@<sha> # \.github main$"' _ "$ORG_ROOT/README.md"
check "static: the README pins all four cascade references as <sha>" bash -c '[ "$(grep -cE "open-platform-model/\.github/\.github/[^@ ]+@<sha> # \.github main$" "$1")" = 4 ]' _ "$ORG_ROOT/README.md"
check "static: the README bump procedure greps every .github reference, the cascade-task.yml checkout included" grep -qF "grep -rn -A1 'open-platform-model/.github' .github/workflows" "$ORG_ROOT/README.md"
check "static: the README names no org-github-ref" bash -c '! grep -n "org-github-ref" "$1"' _ "$ORG_ROOT/README.md"

for sbx in "$ORG_ROOT"/openspec/changes/add-release-cascade-workflows/sandbox \
  "$ORG_ROOT"/openspec/changes/archive/*-add-release-cascade-workflows/sandbox; do
  [ -d "$sbx" ] || continue
  seed="$sbx/down/.github/workflows/deps-cascade.yml"
  expect "static: the sandbox receiver passes the stop switch to the reusable job" 0 "$DRY_EXPR" -- \
    yq -r '.jobs.cascade.with["dry-run"]' "$seed"
  expect "static: the sandbox publish job passes the stop switch to cascade-publish" 0 "$DRY_EXPR" -- \
    yq -r '.jobs.publish.steps[] | select(.uses | test("cascade-publish@")) | .with["dry-run"]' "$seed"
  # The archived sandbox seeds are frozen at the cycle's shape, which predates
  # the gates-only clause (owner decision 26 retired the sandboxes), so only
  # the switches they share with the README are compared.
  check "static: the sandbox publish if: reads the README's dry-run switches" bash -c '
    for c in "inputs.dry_run != true" "vars.CASCADE_DRY_RUN == '"'"'false'"'"'" "needs.cascade.outputs.dry-run == '"'"'false'"'"'"; do
      [[ $(yq -r ".jobs.publish.if" "$1") == *"$c"* ]] && [[ $(yq -r ".jobs.publish.if" "$2") == *"$c"* ]] || exit 1
    done' _ "$seed" "$FX/readme-receiver.yml"
  # Every cascade reference of the sandboxes at one full commit SHA.
  refs=$(grep -rhoE "open-platform-model/\.github/\.github/[^@ ]+@[^ ]+" "$sbx" | sed 's/.*@//' | sort -u)
  check "static: the sandbox callers pin every cascade reference to one full SHA" bash -c '[[ $1 =~ ^[0-9a-f]{40}$ ]]' _ "$refs"
  check "static: the sandbox callers name no org-github-ref" bash -c '! grep -rn "org-github-ref" "$1"' _ "$sbx"
done

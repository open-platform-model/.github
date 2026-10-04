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
expect "static: actions/cascade-notify mints for the targets only" 0 '${{ steps.validate.outputs.targets }}' -- \
  yq -r '.runs.steps[] | select(.id == "mint") | .with.repositories' "$ORG_ROOT/.github/actions/cascade-notify/action.yml"
expect "static: actions/cascade-publish mints for the calling repo only, after verify" 0 \
  $'${{ steps.guard.outputs.repo }}\nsteps.verify.outputs.publish == \'true\'' -- \
  yq -r '.runs.steps[] | select(.id == "mint") | (.with.repositories, .if)' "$ORG_ROOT/.github/actions/cascade-publish/action.yml"

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
check "static: the README names no cascade reference at main or a branch" bash -c '
  ! grep -nE "open-platform-model/\.github/\.github/[^@ ]+@" "$1" | grep -vE "@<sha> # \.github main$"' _ "$ORG_ROOT/README.md"
check "static: the README pins all four cascade references as <sha>" bash -c '[ "$(grep -cE "open-platform-model/\.github/\.github/[^@ ]+@<sha> # \.github main$" "$1")" = 4 ]' _ "$ORG_ROOT/README.md"
check "static: the README names no org-github-ref" bash -c '! grep -n "org-github-ref" "$1"' _ "$ORG_ROOT/README.md"


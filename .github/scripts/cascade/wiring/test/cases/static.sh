# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# Static checks of the reusable cascade workflows and the composite cascade
# actions: no expression inside a run: block, no secrets input and no
# Environment in a reusable workflow, explicit permissions on every job,
# every third-party action pinned to a commit SHA, and one identical Guard
# step first in every job and every action.

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
done

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
done
expect "static: actions/cascade-notify mints for the targets only" 0 '${{ steps.validate.outputs.targets }}' -- \
  yq -r '.runs.steps[] | select(.id == "mint") | .with.repositories' "$ORG_ROOT/.github/actions/cascade-notify/action.yml"
expect "static: actions/cascade-publish mints for the calling repo only, after verify" 0 \
  $'${{ steps.guard.outputs.repo }}\nsteps.verify.outputs.publish == \'true\'' -- \
  yq -r '.runs.steps[] | select(.id == "mint") | (.with.repositories, .if)' "$ORG_ROOT/.github/actions/cascade-publish/action.yml"

if [ -n "$GUARD_TEXT" ]; then
  # guard <GITHUB_REPOSITORY> <org-github-ref>: runs the inline Guard step.
  guard() {
    : >"$FX/gout"
    local rc=0
    env GITHUB_REPOSITORY="$1" INPUTS_REF="$2" GITHUB_OUTPUT="$FX/gout" bash -e -o pipefail -c "$GUARD_TEXT" || rc=$?
    cat "$FX/gout"
    return "$rc"
  }
  NOT_ORG="is not a repo of open-platform-model"
  expect "guard: a production repo at main" 0 $'::notice::repo library\nrepo=library' -- guard open-platform-model/library main
  expect "guard: a production repo with a branch ref fails" 1 "::error::org-github-ref may differ from main only in a sandbox repo" -- \
    guard open-platform-model/library feat/x
  expect "guard: a production repo with an empty ref fails" 1 "::error::org-github-ref may differ from main only in a sandbox repo" -- \
    guard open-platform-model/cli ""
  expect "guard: a sandbox repo with a branch ref" 0 $'::notice::repo cascade-sandbox-down\nrepo=cascade-sandbox-down' -- \
    guard open-platform-model/cascade-sandbox-down feat/x
  expect "guard: a foreign owner fails" 1 "::error::\`someone-else/core\` $NOT_ORG" -- guard someone-else/core main
  expect "guard: a look-alike owner fails" 1 "::error::\`open-platform-model-x/cascade-sandbox-down\` $NOT_ORG" -- \
    guard open-platform-model-x/cascade-sandbox-down feat/x
  expect "guard: an empty name fails" 1 "::error::\`open-platform-model/\` $NOT_ORG" -- guard open-platform-model/ main
  expect "guard: no repository fails" 1 "::error::\`\` $NOT_ORG" -- guard "" main
  expect "guard: a name with a newline fails" 1 "::error::\`open-platform-model/a"$'\n'"repo=core\` $NOT_ORG" -- guard "open-platform-model/a"$'\n'"repo=core" main
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

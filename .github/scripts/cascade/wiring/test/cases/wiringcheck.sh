# shellcheck shell=bash
# shellcheck disable=SC2016 # yq programs and ${{ }} expressions are literal
# The canonical wiring check (.github/scripts/cascade/wiring-check.sh) against
# a fixture repo built from the README's caller shapes: it passes for a
# receiver and for core, refuses one mutation per check, and exits 2 on a bad
# config.

WCHECK="$ORG_ROOT/.github/scripts/cascade/wiring-check.sh"
WC_SHA=0123456789abcdef0123456789abcdef01234567
WC_SHA2=89abcdef0123456789abcdef0123456789abcdef

# wc_readme <heading>: the yaml block after the README line starting with it.
wc_readme() {
  H="$1" awk 'index($0, ENVIRON["H"]) == 1 { f = 1; next } f && /^```yaml$/ { p = 1; next } p && /^```$/ { exit } p' "$ORG_ROOT/README.md" |
    sed "s/@<sha> # /@$WC_SHA # /"
}

# wc_fresh [core]: a fixture repo at $WCD with the README shapes, a CI
# workflow and the config; core has no receiver files.
wc_fresh() {
  WCD="$T_ROOT/wc"
  rm -rf "$WCD"
  mkdir -p "$WCD/.github/workflows" "$WCD/.tasks/cascade"
  local w="$WCD/.github/workflows"
  {
    printf 'name: Release\non:\n  push:\n    branches: [main]\npermissions: {}\nenv:\n  CUE_REGISTRY: registry.cue.works\n'
    printf 'jobs:\n  release-please:\n    runs-on: ubuntu-latest\n    permissions: {}\n    steps:\n      - run: echo release\n'
    wc_readme "**Notify caller**"
  } >"$w/release.yml"
  cat >"$w/ci.yml" <<'YAML'
name: CI
on:
  push:
    branches: [main]
  pull_request:
permissions:
  contents: read
jobs:
  ci:
    name: Validate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - name: Verify the cascade wiring
        run: task cascade:wiring:check
YAML
  cat >"$WCD/.tasks/cascade/wiring-check.yaml" <<'YAML'
pin-comment: .github main
receiver: true
env-allow: [CUE_VERSION, CUE_REGISTRY]
ci:
  workflow: ci.yml
  job: ci
notify:
  needs: [release-please, publish]
  if: needs.release-please.outputs.release_created == 'true' && vars.CASCADE_NOTIFY != 'off'
  tag: ${{ needs.release-please.outputs.tag_name }}
publish:
  labels-managed: false
YAML
  if [ "${1:-}" = core ]; then
    yq -i '.receiver = false | del(.publish)' "$WCD/.tasks/cascade/wiring-check.yaml"
    return 0
  fi
  wc_readme "**Receiver caller**" >"$w/deps-cascade.yml"
  wc_readme "**Per-PR gates caller**" >"$w/cascade-gates.yml"
  cat >"$w/cascade-task.yml" <<YAML
name: Cascade task
on:
  pull_request:
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Clone the shared cascade resolver
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          repository: open-platform-model/.github
          ref: $WC_SHA # .github main
          path: org-github
          persist-credentials: false
YAML
}

# wc_run [<config>]: runs the check from the fixture's root (RC, OUT, ERR).
wc_run() { run env -C "$WCD" bash "$WCHECK" "$@"; }

# wc_ok <name>: the check passes with the ok line.
wc_ok() {
  wc_run
  check "wiring check: $1" bash -c '[ "$1" = 0 ] && [ "$2" = "cascade wiring: ok, .github $3 (.github main)" ] && [ -z "$4" ]' _ "$RC" "$OUT" "$WC_SHA" "$ERR"
}

# wc_mut <name> <file> <yq program> <stderr substring>: a fresh receiver
# fixture, the program applied in place to .github/workflows/<file> (or to
# the config when <file> is "config"), and the check must exit 1 naming it.
wc_mut() {
  local f="$WCD/.github/workflows/$2"
  wc_fresh
  [ "$2" != config ] || f="$WCD/.tasks/cascade/wiring-check.yaml"
  yq -i "$3" "$f"
  wc_run
  check "wiring check refuses: $1" bash -c '[ "$1" = 1 ] && [[ $2 == *"$3"* ]] && [ -z "$4" ]' _ "$RC" "$ERR" "$4" "$OUT"
}

# wc_sed <name> <file> <sed script> <stderr substring>: as wc_mut, for edits
# yq would not keep (comments).
wc_sed() {
  wc_fresh
  sed -i "$3" "$WCD/.github/workflows/$2"
  wc_run
  check "wiring check refuses: $1" bash -c '[ "$1" = 1 ] && [[ $2 == *"$3"* ]]' _ "$RC" "$ERR" "$4"
}

# wc_cfg <name> <yq program on the config> <stderr substring> [core]: the
# config is refused with exit 2.
wc_cfg() {
  wc_fresh "${4:-}"
  yq -i "$2" "$WCD/.tasks/cascade/wiring-check.yaml"
  wc_run
  check "wiring config refuses: $1" bash -c '[ "$1" = 2 ] && [[ $2 == *"$3"* ]] && [ -z "$4" ]' _ "$RC" "$ERR" "$3" "$OUT"
}

new_fx

# --- the shapes pass ----------------------------------------------------------
wc_fresh
check "wiring check: the README receiver shape has the gates-only edits" bash -c '
  [[ $(yq -r ".jobs.publish.if" "$1") == *"inputs.gates_only != true"* ]] && [ "$(yq -r ".jobs.publish.steps[0].with[\"gates-only\"]" "$1")" = "\${{ inputs.gates_only == true }}" ]' \
  _ "$WCD/.github/workflows/deps-cascade.yml"
wc_ok "the README receiver shapes pass"
wc_fresh core
wc_ok "core (no receiver) passes with release.yml and the CI job only"
wc_fresh
yq -i '.jobs.notify-downstream.needs = "release-please"' "$WCD/.github/workflows/release.yml"
yq -i '.notify.needs = ["release-please"]' "$WCD/.tasks/cascade/wiring-check.yaml"
wc_ok "a needs string equals a config list of one"
wc_fresh
yq -i '.jobs.publish.steps[0].with.labels-managed = true' "$WCD/.github/workflows/deps-cascade.yml"
yq -i '.publish.labels-managed = true' "$WCD/.tasks/cascade/wiring-check.yaml"
wc_ok "labels-managed true when the config says true (cli)"
wc_fresh
yq -i 'del(.env)' "$WCD/.github/workflows/release.yml"
yq -i '.["env-allow"] = []' "$WCD/.tasks/cascade/wiring-check.yaml"
wc_ok "no release.yml env with an empty allow-list"
wc_fresh
mv "$WCD/.tasks/cascade/wiring-check.yaml" "$WCD/other.yaml"
wc_run other.yaml
check "wiring check: the config path is an argument" test "$RC" = 0

# --- the key-holding jobs -----------------------------------------------------
wc_mut "an env on the notify job" release.yml '.jobs.notify-downstream.env = {"X": "1"}' "release.yml:notify-downstream keys"
wc_mut "a container on the publish job" deps-cascade.yml '.jobs.publish.container = "node:20"' "deps-cascade.yml:publish keys"
wc_mut "another notify job name" release.yml '.jobs.notify-downstream.name = "Notify"' "notify-downstream name"
wc_mut "another notify step name" release.yml '.jobs.notify-downstream.steps[0].name = "Notify"' "notify-downstream step name"
wc_mut "a longer notify timeout" release.yml '.jobs.notify-downstream.timeout-minutes = 30' "notify-downstream timeout-minutes"
wc_mut "another publish timeout" deps-cascade.yml '.jobs.publish.timeout-minutes = 60' "publish timeout-minutes"
wc_mut "notify needs that differ from the config" release.yml '.jobs.notify-downstream.needs = ["release-please"]' "notify-downstream needs"
wc_mut "notify if: always()" release.yml '.jobs.notify-downstream.if = "always()"' "notify-downstream if"
wc_mut "notify tag from elsewhere" release.yml '.jobs.notify-downstream.steps[0].with.tag = "${{ github.event.inputs.tag }}"' "notify-downstream tag"
wc_mut "notify on a self-hosted runner" release.yml '.jobs.notify-downstream.runs-on = "self-hosted"' "notify-downstream runs-on"
wc_mut "publish on a self-hosted runner" deps-cascade.yml '.jobs.publish.runs-on = "self-hosted"' "publish runs-on"
wc_mut "publish with contents: write" deps-cascade.yml '.jobs.publish.permissions.contents = "write"' "publish permissions"
wc_mut "a second publish step" deps-cascade.yml '.jobs.publish.steps += [{"run": "echo"}]' "publish step count"
wc_mut "an env on the publish step" deps-cascade.yml '.jobs.publish.steps[0].env = {"X": "1"}' "publish step keys"
wc_mut "the action at a branch" deps-cascade.yml '.jobs.publish.steps[0].uses = "open-platform-model/.github/.github/actions/cascade-publish@main"' "publish uses"
wc_mut "an extra notify input" release.yml '.jobs.notify-downstream.steps[0].with.extra = "x"' "notify-downstream with keys"
wc_mut "the key from another secret" release.yml '.jobs.notify-downstream.steps[0].with.private-key = "${{ secrets.OTHER }}"' "notify-downstream private-key"
wc_mut "the client id from a secret" deps-cascade.yml '.jobs.publish.steps[0].with.client-id = "${{ secrets.CASCADE_APP_CLIENT_ID }}"' "publish client-id"

# --- gates-only and the stop switch -------------------------------------------
wc_mut "a publish if: without the gates-only clause" deps-cascade.yml \
  '.jobs.publish.if |= sub(" && inputs.gates_only != true"; "")' "deps-cascade.yml publish if"
wc_mut "a publish if: reading gates-only from the reusable job" deps-cascade.yml \
  '.jobs.publish.if |= sub("inputs.gates_only != true"; "needs.cascade.outputs.action != '"'"'gates-only'"'"'")' "deps-cascade.yml publish if"
wc_mut "a publish step without the gates-only input" deps-cascade.yml 'del(.jobs.publish.steps[0].with.gates-only)' "deps-cascade.yml publish gates-only"
wc_mut "a constant gates-only input" deps-cascade.yml '.jobs.publish.steps[0].with.gates-only = false' "deps-cascade.yml publish gates-only"
wc_mut "the stop switch spelled FALSE" deps-cascade.yml '.jobs.publish.if |= sub("CASCADE_DRY_RUN == '"'"'false'"'"'"; "CASCADE_DRY_RUN == '"'"'FALSE'"'"'")' "deps-cascade.yml publish if"
wc_mut "a publish dry-run without the variable" deps-cascade.yml '.jobs.publish.steps[0].with.dry-run = "${{ inputs.dry_run == true }}"' "deps-cascade.yml publish dry-run"
wc_mut "a cascade dry-run of false" deps-cascade.yml '.jobs.cascade.with.dry-run = false' "deps-cascade.yml cascade dry-run"
wc_mut "a cascade gates-only from another source" deps-cascade.yml '.jobs.cascade.with.gates-only = "${{ inputs.gates_only }}"' "deps-cascade.yml cascade gates-only"
wc_mut "labels-managed as the string false" deps-cascade.yml '.jobs.publish.steps[0].with.labels-managed = "false"' "deps-cascade.yml publish labels-managed"
wc_mut "labels-managed true against the config" deps-cascade.yml '.jobs.publish.steps[0].with.labels-managed = true' "deps-cascade.yml publish labels-managed"
wc_mut "publish needs a second job" deps-cascade.yml '.jobs.publish.needs = ["cascade", "other"]' "deps-cascade.yml publish needs"

# --- the receiver shape -------------------------------------------------------
wc_mut "write-all at the top of deps-cascade" deps-cascade.yml '.permissions = "write-all"' "deps-cascade.yml permissions"
wc_mut "deps-cascade on pull_request_target" deps-cascade.yml '.on.pull_request_target = {}' "deps-cascade.yml triggers"
wc_mut "another dispatch type" deps-cascade.yml '.on.repository_dispatch.types = ["any"]' "repository_dispatch types"
wc_mut "a string gates_only input" deps-cascade.yml '.on.workflow_dispatch.inputs.gates_only.type = "string"' "dispatch inputs"
wc_mut "another concurrency group" deps-cascade.yml '.concurrency.group = "deps"' "concurrency.group"
wc_mut "cancel-in-progress" deps-cascade.yml '.concurrency.cancel-in-progress = true' "cancel-in-progress"
wc_mut "a third job" deps-cascade.yml '.jobs.extra = {"runs-on": "ubuntu-latest", "steps": [{"run": "echo"}]}' "deps-cascade.yml jobs"
wc_mut "cascade with actions: write" deps-cascade.yml '.jobs.cascade.permissions.actions = "write"' "deps-cascade.yml cascade permissions"
wc_mut "an input cascade-receive.yml does not take" deps-cascade.yml '.jobs.cascade.with.org-github-ref = "main"' "inputs cascade-receive.yml does not take"
wc_mut "cascade-gates on pull_request" cascade-gates.yml '.on = {"pull_request": {"types": ["opened"]}}' "cascade-gates.yml triggers"
wc_mut "cascade-gates with contents: write" cascade-gates.yml '.jobs.gates.permissions.contents = "write"' "cascade-gates.yml gates permissions"
wc_mut "write-all at the top of cascade-gates" cascade-gates.yml '.permissions = "write-all"' "cascade-gates.yml permissions"
wc_fresh
rm "$WCD/.github/workflows/cascade-gates.yml"
wc_run
check "wiring check refuses: a missing cascade-gates.yml" bash -c '[ "$1" = 1 ] && [[ $2 == *"cascade-gates.yml is missing"* ]]' _ "$RC" "$ERR"

# --- release.yml env ----------------------------------------------------------
wc_mut "BASH_ENV in release.yml env" release.yml '.env.BASH_ENV = "/tmp/x"' "release.yml env keys outside env-allow"
wc_mut "a key the allow-list lacks" release.yml '.env.EXTRA = "1"' "release.yml env keys outside env-allow"
wc_mut "an expression for the whole env" release.yml '.env = "${{ fromJSON(vars.E) }}"' "release.yml env type"

# --- who reads the key --------------------------------------------------------
JOB='{"runs-on": "ubuntu-latest", "steps": [{"run": "echo"}]}'
wc_mut "the key in another job" release.yml ".jobs.leak = $JOB | .jobs.leak.steps[0].env.K = \"\${{ secrets.CASCADE_APP_PRIVATE_KEY }}\"" "secrets.CASCADE_APP_PRIVATE_KEY readers"
wc_mut "the key in lower case" release.yml ".jobs.leak = $JOB | .jobs.leak.steps[0].env.K = \"\${{ secrets.cascade_app_private_key }}\"" "secrets.CASCADE_APP_PRIVATE_KEY readers"
wc_mut "the key by bracket" release.yml ".jobs.leak = $JOB | .jobs.leak.steps[0].env.K = \"\${{ secrets['cascade_app_private_key'] }}\"" "secrets.CASCADE_APP_PRIVATE_KEY readers"
wc_mut "every secret as JSON" release.yml ".jobs.leak = $JOB | .jobs.leak.steps[0].env.K = \"\${{ toJSON( secrets ) }}\"" "secrets.CASCADE_APP_PRIVATE_KEY readers"
wc_mut "the key in the CI workflow" ci.yml '.jobs.ci.steps[1].env.K = "${{ secrets.CASCADE_APP_PRIVATE_KEY }}"' "secrets.CASCADE_APP_PRIVATE_KEY readers"
wc_mut "the Environment as Cascade" release.yml ".jobs.leak = $JOB | .jobs.leak.environment = \"Cascade\"" "cascade Environment jobs"
wc_mut "the Environment as a map" ci.yml '.jobs.ci.environment = {"name": "CASCADE"}' "cascade Environment jobs"
wc_mut "the Environment as an expression" ci.yml '.jobs.ci.environment = "${{ vars.E }}"' "cascade Environment jobs"
wc_mut "secrets: inherit into .github" cascade-gates.yml '.jobs.gates.secrets = "inherit"' "calls into .github that pass secrets"

# --- the pin ------------------------------------------------------------------
wc_sed "two .github SHAs" cascade-gates.yml "s/@$WC_SHA/@$WC_SHA2/" "one .github SHA"
wc_sed "a resolver checkout at a branch" cascade-task.yml "s/ref: $WC_SHA/ref: main/" "one .github SHA"
wc_sed "another pin comment" deps-cascade.yml "0,/# \.github main/s//# .github branch/" "pin comment on"
wc_sed "a reference without a comment" cascade-gates.yml "s/ # \.github main//" "pin comment on"
wc_mut "a fifth .github reference" ci.yml '.jobs.ci.steps += [{"uses": "open-platform-model/.github/.github/actions/cascade-notify@'"$WC_SHA"'"}]' ".github references"

# --- the CI job ---------------------------------------------------------------
wc_mut "a CI workflow only on push" ci.yml 'del(.on.pull_request)' "ci.yml runs on pull_request"
wc_mut "a CI path filter" ci.yml '.on.pull_request = {"paths": [".github/**"]}' "ci.yml pull_request path filters"
wc_mut "a CI job if:" ci.yml '.jobs.ci.if = "false"' "ci.yml:ci if and continue-on-error"
wc_mut "a CI job continue-on-error" ci.yml '.jobs.ci.continue-on-error = true' "ci.yml:ci if and continue-on-error"
wc_mut "a CI step continue-on-error" ci.yml '.jobs.ci.steps[1].continue-on-error = true' "ci.yml:ci wiring step if and continue-on-error"
wc_mut "a CI step if:" ci.yml '.jobs.ci.steps[1].if = "false"' "ci.yml:ci wiring step if and continue-on-error"
wc_mut "no wiring step" ci.yml 'del(.jobs.ci.steps[1])' "ci.yml:ci steps running task cascade:wiring:check"
wc_mut "the config naming another job" config '.ci.job = "other"' "ci.yml:other exists"

# --- the config ---------------------------------------------------------------
wc_cfg "an unknown key" '.extra = 1' "unknown key extra"
wc_cfg "BASH_ENV in env-allow" '.["env-allow"] += ["BASH_ENV"]' "env-allow may not allow BASH_ENV"
wc_cfg "NODE_OPTIONS in env-allow" '.["env-allow"] += ["NODE_OPTIONS"]' "env-allow may not allow NODE_OPTIONS"
wc_cfg "GITHUB_TOKEN in env-allow" '.["env-allow"] += ["GITHUB_TOKEN"]' "env-allow may not allow GITHUB_TOKEN"
wc_cfg "a lower-case env-allow entry" '.["env-allow"] += ["foo"]' "is not an upper-case variable name"
wc_cfg "receiver as a string" '.receiver = "true"' "receiver must be true or false"
wc_cfg "labels-managed as a string" '.publish.labels-managed = "false"' "labels-managed must be true or false"
wc_cfg "publish on core" '.publish = {"labels-managed": false}' "publish is only for a receiver" core
wc_cfg "no notify tag" 'del(.notify.tag)' "notify needs needs, if and tag"
wc_cfg "a pin comment with a #" '.["pin-comment"] = "a # b"' "pin-comment must be words"
wc_cfg "a CI workflow path" '.ci.workflow = "../x.yml"' "ci.workflow must be a workflow file name"
wc_fresh
rm "$WCD/.tasks/cascade/wiring-check.yaml"
wc_run
check "wiring config refuses: a missing config" bash -c '[ "$1" = 2 ] && [[ $2 == *"no config at"* ]]' _ "$RC" "$ERR"
wc_fresh
run env -C "$T_ROOT" bash "$WCHECK" "$WCD/.tasks/cascade/wiring-check.yaml"
check "wiring check: outside a repo root exits 2" bash -c '[ "$1" = 2 ] && [[ $2 == *"run from the repo root"* ]]' _ "$RC" "$ERR"

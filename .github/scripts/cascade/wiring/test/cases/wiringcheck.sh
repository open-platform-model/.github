# shellcheck shell=bash
# shellcheck disable=SC2016 # yq programs and ${{ }} expressions are literal
# The canonical wiring check (.github/scripts/cascade/wiring-check.sh) against
# a fixture repo built from the README's caller shapes: it passes for a
# receiver and for core, refuses one mutation per check, exits 2 on a bad
# config, and with --pin-on-main asks the compare API about the SHA.

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
        env:
          GH_TOKEN: ${{ github.token }}
        run: bash .tasks/cascade/wiring-check.sh --pin-on-main
YAML
  cat >"$WCD/.tasks/cascade/wiring-check.yaml" <<'YAML'
pin-comment: .github main
receiver: true
env-allow: [CUE_VERSION, CUE_REGISTRY]
publish-workflows: [release.yml]
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

# The offline output on success: the ok line, then the note that the copy
# was not compared.
wc_ok_out() {
  printf 'cascade wiring: ok, .github %s (.github main)\ncascade wiring: the copy was not compared with .github %s (offline; --pin-on-main compares it)' "$1" "$1"
}

# wc_ok <name>: the check passes with the ok line.
wc_ok() {
  wc_run
  check "wiring check: $1" bash -c '[ "$1" = 0 ] && [ "$2" = "$3" ] && [ -z "$4" ]' _ "$RC" "$OUT" "$(wc_ok_out "$WC_SHA")" "$ERR"
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

# --- the release key ----------------------------------------------------------
RP_KEY='.jobs.release-please.steps += [{"uses": "actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1", "with": {"client-id": "${{ vars.RELEASE_APP_CLIENT_ID }}", "private-key": "${{ secrets.RELEASE_APP_PRIVATE_KEY }}"}}]'
wc_fresh
yq -i "$RP_KEY | .jobs.release-please.environment = \"release\"" "$WCD/.github/workflows/release.yml"
wc_ok "the release-please job reads the release key under environment: release"
wc_fresh
yq -i '.jobs.release-please.environment = "release" | .jobs.release-please.steps[0].env.K = "${{ secrets . release_app_private_key }}"' "$WCD/.github/workflows/release.yml"
wc_ok "the key in lower case with spaces under environment: release"
wc_mut "the release key without environment: release" release.yml "$RP_KEY" \
  "release key readers without environment: release: expected [], got [release.yml:release-please]"
wc_mut "the release key under environment: Release" release.yml "$RP_KEY | .jobs.release-please.environment = \"Release\"" \
  "release key readers without environment: release"
wc_mut "the release key under a map Environment" release.yml "$RP_KEY | .jobs.release-please.environment = {\"name\": \"release\"}" \
  "release key readers without environment: release"
wc_mut "the release key in an if:" ci.yml '.jobs.ci.steps[0].if = "secrets.RELEASE_APP_PRIVATE_KEY != '"''"'"' \
  "release key readers without environment: release: expected [], got [ci.yml:ci]"
wc_mut "the release key in the workflow env" release.yml '.env.K = "${{ secrets.RELEASE_APP_PRIVATE_KEY }}"' \
  "got [release.yml:<outside a job: env.K>]"
wc_mut "environment: Release on a job that does not read the key" ci.yml '.jobs.ci.environment = "Release"' \
  "environment: release on jobs that do not read the release key: expected [], got [ci.yml:ci]"
wc_mut "a map Environment named release on a job that does not read the key" ci.yml '.jobs.ci.environment = {"name": "RELEASE"}' \
  "environment: release on jobs that do not read the release key"
wc_mut "secrets: inherit to another reusable workflow" ci.yml \
  '.jobs.docs = {"uses": "open-platform-model/docs-kit/.github/workflows/publish.yml@v0.7.0", "secrets": "inherit"}' \
  "release key readers without environment: release: expected [], got [ci.yml:docs]"

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
wc_mut "a CI step continue-on-error" ci.yml '.jobs.ci.steps[1].continue-on-error = true' "ci.yml:ci wiring step keys"
wc_mut "a CI step if:" ci.yml '.jobs.ci.steps[1].if = "false"' "ci.yml:ci wiring step keys"
wc_mut "no wiring step" ci.yml 'del(.jobs.ci.steps[1])' "ci.yml:ci steps running [bash .tasks/cascade/wiring-check.sh --pin-on-main]"
wc_mut "the old offline task step" ci.yml '.jobs.ci.steps[1].run = "task cascade:wiring:check"' "ci.yml:ci steps running"
wc_mut "the wiring step without the pin check" ci.yml '.jobs.ci.steps[1].run = "bash .tasks/cascade/wiring-check.sh"' "ci.yml:ci steps running"
wc_mut "a wiring step without the token" ci.yml 'del(.jobs.ci.steps[1].env)' "ci.yml:ci wiring step keys"
wc_mut "a wiring step with more env" ci.yml '.jobs.ci.steps[1].env.BASH_ENV = "x"' "ci.yml:ci wiring step env"
wc_mut "a wiring step with a shell of its own" ci.yml '.jobs.ci.steps[1].shell = "true {0}"' "ci.yml:ci wiring step keys"
wc_mut "a wiring step in another directory" ci.yml '.jobs.ci.steps[1].working-directory = "other"' "ci.yml:ci wiring step keys"
wc_mut "a workflow default shell" ci.yml '.defaults.run.shell = "true {0}"' "ci.yml defaults.run"
wc_mut "a job default working directory" ci.yml '.jobs.ci.defaults.run.working-directory = "other"' "ci.yml defaults.run"
wc_mut "the config naming another job" config '.ci.job = "other"' "ci.yml:other exists"

# Nothing reaches the wiring step from around it (the review's routes: env,
# an earlier step writing GITHUB_ENV, a container or a service).
BEFORE="ci.yml:ci steps before the wiring step that are not a pinned action"
wc_mut "BASH_ENV in the CI job env" ci.yml '.jobs.ci.env.BASH_ENV = "x"' "ci.yml:ci env keys outside"
wc_mut "CASCADE_GH in the CI workflow env" ci.yml '.env.CASCADE_GH = "./gh"' "ci.yml env keys outside"
wc_mut "PATH in the CI workflow env" ci.yml '.env.PATH = "."' "ci.yml env keys outside"
wc_mut "the CI job env as an expression" ci.yml '.jobs.ci.env = "${{ fromJSON(vars.E) }}"' "ci.yml:ci env type"
wc_mut "a container on the CI job" ci.yml '.jobs.ci.container = "node:20"' "ci.yml:ci container and services"
wc_mut "a service on the CI job" ci.yml '.jobs.ci.services.s = {"image": "busybox", "volumes": ["/home/runner/work:/w"]}' "ci.yml:ci container and services"
wc_mut "a run: step writing GITHUB_ENV before the wiring step" ci.yml \
  '.jobs.ci.steps = [.jobs.ci.steps[0], {"run": "echo BASH_ENV=x >> \"$GITHUB_ENV\""}, .jobs.ci.steps[1]]' "$BEFORE"
wc_mut "an action at a tag before the wiring step" ci.yml \
  '.jobs.ci.steps = [.jobs.ci.steps[0], {"uses": "actions/setup-go@v7"}, .jobs.ci.steps[1]]' "$BEFORE"
wc_mut "a local action before the wiring step" ci.yml \
  '.jobs.ci.steps = [.jobs.ci.steps[0], {"uses": "./.github/actions/x@3d3c42e5aac5ba805825da76410c181273ba90b1"}, .jobs.ci.steps[1]]' "$BEFORE"
wc_mut "an earlier action with an env of its own" ci.yml '.jobs.ci.steps[0].env.BASH_ENV = "x"' "$BEFORE"
wc_mut "an earlier action with an if:" ci.yml '.jobs.ci.steps[0].if = "always()"' "$BEFORE"
wc_fresh
yq -i '.env = {"CUE_REGISTRY": "a", "OPM_REGISTRY": "b"} | .jobs.ci.env = {"CUE_VERSION": "v0"}
  | .jobs.ci.steps = [.jobs.ci.steps[0] | .id = "co" | .with = {"fetch-depth": 0},
    {"name": "Go", "uses": "actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e", "with": {"cache": false}},
    .jobs.ci.steps[1], {"run": "echo after"}]' "$WCD/.github/workflows/ci.yml"
wc_ok "registry env, pinned actions before and run: steps after the wiring step pass"

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

# --- YAML anchors and aliases ---------------------------------------------------
# The review's bypass: the cascade Environment through an alias, the key
# through secrets[format()]. Both the alias and the reader are refused.
wc_fresh
sed -i 's/^    environment: cascade$/    environment: \&e cascade/' "$WCD/.github/workflows/release.yml"
cat >>"$WCD/.github/workflows/release.yml" <<'YAML'
  leak:
    runs-on: ubuntu-latest
    environment: *e
    steps:
      - run: echo "${{ secrets[format('CASCADE_APP_{0}', 'PRIVATE_KEY')] }}" | base64
YAML
wc_run
check "wiring check refuses: an aliased Environment and a format() key" bash -c '
  [ "$1" = 1 ] && [[ $2 == *"release.yml YAML anchors and aliases: expected [0], got [2]"* ]] && [[ $2 == *"secrets.CASCADE_APP_PRIVATE_KEY readers"*"release.yml:jobs.leak.steps.0.run"* ]]' _ "$RC" "$ERR"
wc_sed "a merge key" ci.yml 's/^    runs-on: ubuntu-latest$/    <<: \&d {timeout-minutes: 5}\n    runs-on: ubuntu-latest/' "ci.yml YAML anchors and aliases"

# --- every other use of the secrets context ------------------------------------
wc_mut "the key by format()" release.yml ".jobs.leak = $JOB | .jobs.leak.steps[0].env.K = \"\${{ secrets[format('{0}', vars.N)] }}\"" "secrets.CASCADE_APP_PRIVATE_KEY readers"
wc_mut "every secret by secrets.*" release.yml ".jobs.leak = $JOB | .jobs.leak.steps[0].env.K = \"\${{ join(secrets.*, ',') }}\"" "secrets.CASCADE_APP_PRIVATE_KEY readers"
wc_mut "every secret by join()" ci.yml '.jobs.ci.steps[0].with.x = "${{ join(secrets) }}"' "secrets.CASCADE_APP_PRIVATE_KEY readers"
wc_mut "a secrets index in an if:" ci.yml '.jobs.ci.steps[0].if = "secrets[vars.N] != '"''"'"' "secrets.CASCADE_APP_PRIVATE_KEY readers"
wc_mut "the key with spaces" ci.yml '.jobs.ci.steps[0].with.x = "${{ secrets . CASCADE_APP_PRIVATE_KEY }}"' "secrets.CASCADE_APP_PRIVATE_KEY readers"
wc_fresh
yq -i '.jobs.ci.steps[0].with.token = "${{ secrets.GITHUB_TOKEN }}" | .jobs.ci.steps[0].with.note = "no secrets here, ${{ inputs.secrets_dir }}"' "$WCD/.github/workflows/ci.yml"
wc_ok "another named secret, and secrets in plain text, are no key readers"

# --- .github references in any letter case -------------------------------------
wc_mut "secrets: inherit into .github in mixed case" ci.yml \
  '.jobs.x = {"uses": "Open-Platform-Model/.github/.github/workflows/cascade-receive.yml@main", "secrets": "inherit"}' "calls into .github that pass secrets"
wc_mut "a .GitHub action reference" ci.yml '.jobs.ci.steps += [{"uses": "open-platform-model/.GitHub/.github/actions/cascade-publish@main"}]' ".github references"
wc_mut "a .GITHUB resolver checkout" ci.yml '.jobs.ci.steps += [{"uses": "actions/checkout@v7", "with": {"repository": "OPEN-PLATFORM-MODEL/.GITHUB"}}]' ".github references"

# --- env-allow names ------------------------------------------------------------
for v in GIT_TEMPLATE_DIR GIT_PROXY_COMMAND GIT_EXTERNAL_DIFF XDG_CONFIG_HOME NODE_EXTRA_CA_CERTS HTTPS_PROXY \
  SSL_CERT_FILE GIT_SSL_NO_VERIFY GH_DEBUG GIT_TRACE_CURL GCONV_PATH CURL_CA_BUNDLE LD_PRELOAD BASH_ENV CASCADE_X; do
  wc_cfg "$v in env-allow" ".[\"env-allow\"] += [\"$v\"]" "env-allow may not allow $v"
done
wc_fresh
yq -i '.env = {"OPM_REGISTRY": "a", "CUE_REGISTRY": "b", "REGISTRY": "ghcr.io", "IMAGE_NAME": "x"}' "$WCD/.github/workflows/release.yml"
yq -i '.["env-allow"] = ["OPM_REGISTRY", "CUE_REGISTRY", "REGISTRY", "IMAGE_NAME"]' "$WCD/.tasks/cascade/wiring-check.yaml"
wc_ok "the registry names the five repos use are allowed"

# --- publish workflows restore no cache ----------------------------------------
GO='{"uses": "actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e", "with": {"go-version-file": "go.mod"}}'
wc_mut "setup-go with its default cache" release.yml ".jobs.release-please.steps += [$GO]" "release.yml cache use"
wc_mut "setup-go with cache: true" release.yml ".jobs.release-please.steps += [$GO] | .jobs.release-please.steps[-1].with.cache = true" "setup-go without cache: false"
wc_mut "actions/cache" release.yml '.jobs.release-please.steps += [{"uses": "actions/cache@v5", "with": {"path": "x", "key": "k"}}]' "uses actions/cache@v5"
wc_mut "actions/cache/restore" release.yml '.jobs.release-please.steps += [{"uses": "actions/cache/restore@v5"}]' "uses actions/cache/restore@v5"
wc_mut "another cache action" release.yml '.jobs.release-please.steps += [{"uses": "Swatinem/rust-cache@v2"}]' "uses Swatinem/rust-cache@v2"
wc_mut "buildx cache-from type=gha" release.yml '.jobs.release-please.steps += [{"uses": "docker/build-push-action@v7", "with": {"push": true, "cache-from": "type=gha"}}]' "with.cache-from"
wc_mut "type=gha in a run" release.yml '.jobs.release-please.steps += [{"run": "docker buildx build --cache-to type=gha,mode=max ."}]' "type=gha at jobs.release-please.steps.1.run"
wc_mut "setup-node without package-manager-cache: false" release.yml '.jobs.release-please.steps += [{"uses": "actions/setup-node@v6"}]' "setup-node without package-manager-cache"
wc_mut "setup-node with cache: npm" release.yml '.jobs.release-please.steps += [{"uses": "actions/setup-node@v6", "with": {"package-manager-cache": false, "cache": "npm"}}]' "setup-node without package-manager-cache"
wc_mut "setup-python with cache: pip" release.yml '.jobs.release-please.steps += [{"uses": "actions/setup-python@v6", "with": {"cache": "pip"}}]' "with.cache"
wc_mut "a listed publish workflow that is missing" config '.["publish-workflows"] += ["publish-fixtures.yml"]' "publish workflow publish-fixtures.yml is missing"
wc_fresh
yq -i '.jobs.release-please.steps += [{"uses": "actions/setup-go@v7", "with": {"go-version": "1.26.0", "cache": false}},
  {"uses": "actions/setup-node@v6", "with": {"package-manager-cache": false}},
  {"uses": "docker/build-push-action@v7", "with": {"no-cache": true}}]' "$WCD/.github/workflows/release.yml"
yq -i '.jobs.ci.steps += [{"uses": "actions/setup-go@v7"}, {"uses": "actions/cache@v5"}]' "$WCD/.github/workflows/ci.yml"
wc_ok "no cache in a publish workflow, and a cache in CI, pass"
wc_cfg "no publish-workflows" 'del(.["publish-workflows"])' "publish-workflows must be a list"
wc_cfg "publish-workflows without release.yml" '.["publish-workflows"] = ["docs.yml"]' "publish-workflows must list release.yml"
wc_cfg "a publish-workflows path" '.["publish-workflows"] += ["../x.yml"]' "is not a workflow file name"

# --- declared extra references (opm-operator's module-deps.yml) ---------------------
# wc_mdeps: the receiver fixture plus a module-deps.yml with a second resolver
# checkout, as opm-operator main has, declared in the config.
wc_mdeps() {
  wc_fresh
  cat >"$WCD/.github/workflows/module-deps.yml" <<YAML
name: Operator module deps
on:
  workflow_dispatch:
permissions: {}
jobs:
  compute:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Clone the cascade resolver
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          repository: open-platform-model/.github
          ref: $WC_SHA # .github main
          path: org-github
          persist-credentials: false
YAML
  yq -i '.["extra-references"] = [{"file": "module-deps.yml", "kind": "resolver"}]' "$WCD/.tasks/cascade/wiring-check.yaml"
}
MD="$T_ROOT/wc/.github/workflows/module-deps.yml"
wc_mdeps
wc_ok "a declared module-deps.yml resolver at the pin passes"
wc_mdeps
yq -i '.["extra-references"] = []' "$WCD/.tasks/cascade/wiring-check.yaml"
rm "$MD"
wc_ok "an empty extra-references list passes"
wc_mdeps
sed -i "s/ref: $WC_SHA/ref: $WC_SHA2/" "$MD"
wc_run
check "wiring check refuses: the declared resolver at another SHA" bash -c '[ "$1" = 1 ] && [[ $2 == *"one .github SHA"* ]]' _ "$RC" "$ERR"
wc_mdeps
sed -i "s/ # \.github main$//" "$MD"
wc_run
check "wiring check refuses: the declared resolver without the pin comment" bash -c '[ "$1" = 1 ] && [[ $2 == *"pin comment on [module-deps.yml resolver@"* ]]' _ "$RC" "$ERR"
wc_mdeps
yq -i 'del(.["extra-references"])' "$WCD/.tasks/cascade/wiring-check.yaml"
wc_run
check "wiring check refuses: an undeclared second resolver" bash -c '[ "$1" = 1 ] && [[ $2 == *".github references"* ]] && [[ $2 == *"module-deps.yml resolver"* ]]' _ "$RC" "$ERR"
wc_mdeps
rm "$MD"
wc_run
check "wiring check refuses: a declared resolver that is missing" bash -c '[ "$1" = 1 ] && [[ $2 == *".github references"* ]]' _ "$RC" "$ERR"
wc_mdeps
yq -i '.jobs.compute.steps += [.jobs.compute.steps[0]]' "$MD"
wc_run
check "wiring check refuses: two resolvers for one declared entry" bash -c '[ "$1" = 1 ] && [[ $2 == *".github references"* ]]' _ "$RC" "$ERR"
wc_mdeps
yq -i '.jobs.compute.steps += [.jobs.compute.steps[0]]' "$MD"
yq -i '.["extra-references"] += [{"file": "module-deps.yml", "kind": "resolver"}]' "$WCD/.tasks/cascade/wiring-check.yaml"
wc_ok "two declared entries for two resolvers in one file pass"

# Every resolver checkout passes no credentials (the fixed one and declared ones).
for m in '.jobs.compute.steps[0].with.token = "${{ secrets.GITHUB_TOKEN }}"' \
  '.jobs.compute.steps[0].with.ssh-key = "${{ secrets.DEPLOY_KEY }}"' \
  '.jobs.compute.steps[0].with.persist-credentials = true' \
  '.jobs.compute.steps[0].with.persist-credentials = "false"' \
  'del(.jobs.compute.steps[0].with.persist-credentials)' \
  '.jobs.compute.steps[0].uses = "actions/checkout@v7"' \
  '.jobs.compute.steps[0].uses = "someone/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"'; do
  wc_mdeps
  yq -i "$m" "$MD"
  wc_run
  check "wiring check refuses a resolver checkout: $m" bash -c '[ "$1" = 1 ] && [[ $2 == *".github checkouts not actions/checkout@<sha>"*"got [module-deps.yml:compute.steps.0]"* ]]' _ "$RC" "$ERR"
done
# A .github checkout by any spelling the literal name misses, and a clone in a run: step.
OWNER_CO='{"name": "x", "uses": "actions/checkout@v4", "with": {"repository": "${{ github.repository_owner }}/.github", "ref": "main", "token": "${{ secrets.GITHUB_TOKEN }}"}}'
wc_mut "an undeclared .github checkout through repository_owner" cascade-task.yml ".jobs.test.steps += [$OWNER_CO]" "steps whose repository input is an expression"
wc_mut "a repository_owner checkout is held to the checkout rule" cascade-task.yml ".jobs.test.steps += [$OWNER_CO]" "got [cascade-task.yml:test.steps.1]"
wc_mut "a repository_owner checkout is an unexpected reference" cascade-task.yml ".jobs.test.steps += [$OWNER_CO]" ".github references"
wc_mut "a pinned checkout of another owner's .github" ci.yml \
  '.jobs.ci.steps += [{"uses": "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1", "with": {"repository": "someone/.github", "ref": "main", "token": "${{ github.token }}"}}]' ".github checkouts not actions/checkout@<sha>"
wc_mut "a git clone of .github in a run: step" cascade-task.yml \
  '.jobs.test.steps += [{"run": "git clone https://github.com/open-platform-model/.github org"}]' "run: steps that fetch .github outside the pinned checkouts: expected [], got [cascade-task.yml:test.steps.1]"
wc_mut "a clone of the owner's .github in a run: step" ci.yml \
  '.jobs.ci.steps += [{"run": "git clone \"https://github.com/${{ github.repository_owner }}/.github\""}]' "run: steps that fetch .github"
wc_fresh
yq -i '.jobs.ci.steps += [{"run": "bash ${{ github.workspace }}/.github/scripts/x.sh .github/y"}]' "$WCD/.github/workflows/ci.yml"
wc_ok "a run: step using the repo's own .github/ paths passes"
wc_fresh
yq -i '.jobs.test.steps[0].with.token = "${{ github.token }}"' "$WCD/.github/workflows/cascade-task.yml"
wc_run
check "wiring check refuses: a token on the cascade-task.yml resolver" bash -c '[ "$1" = 1 ] && [[ $2 == *"got [cascade-task.yml:test.steps.0]"* ]]' _ "$RC" "$ERR"

wc_cfg "extra-references as a map" '.["extra-references"] = {"file": "module-deps.yml", "kind": "resolver"}' "extra-references must be a list"
wc_cfg "extra-references null" '.["extra-references"] = null' "extra-references must be a list"
wc_cfg "an extra reference as a string" '.["extra-references"] = ["module-deps.yml"]' "extra-references item 1 is not a map"
wc_cfg "an extra reference with a third key" '.["extra-references"] = [{"file": "module-deps.yml", "kind": "resolver", "sha": "x"}]' "must have exactly the keys file and kind"
wc_cfg "an extra reference without a kind" '.["extra-references"] = [{"file": "module-deps.yml"}]' "must have exactly the keys file and kind"
wc_cfg "an extra reference of another kind" '.["extra-references"] = [{"file": "module-deps.yml", "kind": "action"}]' "kind [action] is not resolver"
wc_cfg "an extra reference in another directory" '.["extra-references"] = [{"file": "../module-deps.yml", "kind": "resolver"}]' "file [../module-deps.yml] is not a workflow file name"
wc_cfg "an extra reference file as a list" '.["extra-references"] = [{"file": ["a.yml"], "kind": "resolver"}]' "file and kind must be strings"

# --- --pin-on-main ----------------------------------------------------------------
COMPARE=(api "repos/open-platform-model/.github/compare/$WC_SHA...main" --jq .status)
FETCH=(api -H 'Accept: application/vnd.github.raw' "repos/open-platform-model/.github/contents/.github/scripts/cascade/wiring-check.sh?ref=$WC_SHA")
for st in identical ahead; do
  wc_fresh; gh_reset
  gh_fx 0 "$st" -- "${COMPARE[@]}"
  gh_fx_file 0 "$WCHECK" -- "${FETCH[@]}"
  run env -C "$WCD" bash "$WCHECK" --pin-on-main
  check "pin on main: $st passes" bash -c '[ "$1" = 0 ] && [ "$2" = "cascade wiring: ok, .github $3 (.github main)" ] && [ -z "$4" ]' _ "$RC" "$OUT" "$WC_SHA" "$ERR"
done
for st in behind diverged; do
  wc_fresh; gh_reset
  gh_fx 0 "$st" -- "${COMPARE[@]}"
  run env -C "$WCD" bash "$WCHECK" --pin-on-main
  check "pin on main: $st (a commit main never had) is refused" bash -c '[ "$1" = 1 ] && [ -z "$2" ] && [[ $3 == *"is not on .github main (compare status [$4])"* ]]' _ "$RC" "$OUT" "$ERR" "$st"
done
wc_fresh; gh_reset
gh_fx_err 1 "HTTP 404" -- "${COMPARE[@]}"
run env -C "$WCD" bash "$WCHECK" --pin-on-main
check "pin on main: a failed compare is refused" bash -c '[ "$1" = 1 ] && [[ $2 == *"cannot compare .github"* ]]' _ "$RC" "$ERR"
check "pin on main: a failed compare fetches no copy" test "$(gh_count "api -H *")" = 0
for v in BASH_ENV ENV; do
  wc_fresh; gh_reset
  run env -C "$WCD" "$v=" bash "$WCHECK" --pin-on-main
  check "pin on main: $v set is refused before any API call" bash -c '[ "$1" = 1 ] && [[ $2 == *"BASH_ENV or ENV is set"* ]] && [ ! -s "$3" ]' _ "$RC" "$ERR" "$GHFX/log"
done

# --- the copy is the file at the pin ---------------------------------------------
# As CI runs it: the copy at .tasks/cascade/wiring-check.sh, from the repo root.
wc_copy_run() { run env -C "$WCD" bash .tasks/cascade/wiring-check.sh "$@"; }
wc_fresh; gh_reset
cp "$WCHECK" "$WCD/.tasks/cascade/wiring-check.sh"
gh_fx 0 identical -- "${COMPARE[@]}"
gh_fx_file 0 "$WCHECK" -- "${FETCH[@]}"
wc_copy_run --pin-on-main
check "copy: a byte-identical copy at the pin passes" bash -c '[ "$1" = 0 ] && [ "$2" = "cascade wiring: ok, .github $3 (.github main)" ] && [ -z "$4" ]' _ "$RC" "$OUT" "$WC_SHA" "$ERR"
check "copy: the pinned file is fetched once, raw" test "$(gh_count "api -H Accept: application/vnd.github.raw repos/open-platform-model/.github/contents/.github/scripts/cascade/wiring-check.sh?ref=$WC_SHA")" = 1
wc_fresh; gh_reset
cp "$WCHECK" "$WCD/.tasks/cascade/wiring-check.sh"
printf '# a local tweak\n' >>"$WCD/.tasks/cascade/wiring-check.sh"
gh_fx 0 identical -- "${COMPARE[@]}"
gh_fx_file 0 "$WCHECK" -- "${FETCH[@]}"
wc_copy_run --pin-on-main
check "copy: a copy that drifted is refused" bash -c '[ "$1" = 1 ] && [ -z "$2" ] && [[ $3 == *".tasks/cascade/wiring-check.sh differs from .github/scripts/cascade/wiring-check.sh at .github $4"* ]]' _ "$RC" "$OUT" "$ERR" "$WC_SHA"
wc_fresh; gh_reset
cp "$WCHECK" "$WCD/.tasks/cascade/wiring-check.sh"
printf '# the pinned file had one more line\n' | cat "$WCHECK" - >"$T_ROOT/wc-newer.sh"
gh_fx 0 ahead -- "${COMPARE[@]}"
gh_fx_file 0 "$T_ROOT/wc-newer.sh" -- "${FETCH[@]}"
wc_copy_run --pin-on-main
check "copy: a copy left behind at a pin bump is refused" bash -c '[ "$1" = 1 ] && [[ $2 == *"differs from"* ]]' _ "$RC" "$ERR"
wc_fresh; gh_reset
cp "$WCHECK" "$WCD/.tasks/cascade/wiring-check.sh"
gh_fx 0 identical -- "${COMPARE[@]}"
gh_fx_err 1 "HTTP 403: API rate limit exceeded" -- "${FETCH[@]}"
wc_copy_run --pin-on-main
check "copy: a failed fetch is refused" bash -c '[ "$1" = 1 ] && [ -z "$2" ] && [[ $3 == *"cannot fetch .github/scripts/cascade/wiring-check.sh at .github $4"* ]]' _ "$RC" "$OUT" "$ERR" "$WC_SHA"
wc_fresh; gh_reset
cp "$WCHECK" "$WCD/.tasks/cascade/wiring-check.sh"
printf '# a local tweak\n' >>"$WCD/.tasks/cascade/wiring-check.sh"
wc_copy_run
check "copy: offline, a drifted copy passes with the note and makes no request" bash -c '[ "$1" = 0 ] && [ "$2" = "$3" ] && [ ! -s "$4" ]' _ "$RC" "$OUT" "$(wc_ok_out "$WC_SHA")" "$GHFX/log"

wc_fresh; gh_reset
yq -i '.jobs.notify-downstream.timeout-minutes = 30' "$WCD/.github/workflows/release.yml"
run env -C "$WCD" bash "$WCHECK" --pin-on-main
check "pin on main: a shape mismatch fails before any API call" bash -c '[ "$1" = 1 ] && [ ! -s "$2" ]' _ "$RC" "$GHFX/log"
wc_fresh
run env -C "$WCD" bash "$WCHECK" --pin-on-main other.yaml extra
check "pin on main: two arguments after the flag are usage" test "$RC" = 2
run env -C "$WCD" bash "$WCHECK" --online
check "an unknown flag is usage" bash -c '[ "$1" = 2 ] && [[ $2 == *"usage: wiring-check.sh [--pin-on-main] [<config>]"* ]]' _ "$RC" "$ERR"

# The README's CI step is the one the check requires.
wc_fresh
check "wiring check: the README's CI step is the required one" test \
  "$(wc_readme "**The wiring check.**" | yq -o=json -I=0 '.[0] | del(.name)')" = "$(yq -o=json -I=0 '.jobs.ci.steps[1] | del(.name)' "$WCD/.github/workflows/ci.yml")"

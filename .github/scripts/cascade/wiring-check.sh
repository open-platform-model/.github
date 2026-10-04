#!/usr/bin/env bash
# The release-cascade wiring check: compares a product repo's cascade caller
# workflows with the shapes the open-platform-model/.github README documents
# for the commit this file comes from. Canonical copy:
# open-platform-model/.github .github/scripts/cascade/wiring-check.sh. Each of
# core, catalog_opm, library, opm-operator and cli keeps a byte-identical copy
# at .tasks/cascade/wiring-check.sh, taken from the .github commit its cascade
# references pin, plus its own values in .tasks/cascade/wiring-check.yaml.
#
# It guards against mistakes. The copy and the config live in the repo's own
# tree, so a PR can change them along with the workflows; review and the main
# ruleset guard against a deliberate edit.
#
# Usage, from the repo root (task cascade:wiring:check):
#   bash .tasks/cascade/wiring-check.sh [<config>]
# <config> defaults to .tasks/cascade/wiring-check.yaml:
#   pin-comment: .github main      # the comment after every .github SHA
#   receiver: true                 # false: notify only (core)
#   env-allow: [CUE_REGISTRY]      # release.yml workflow env keys allowed
#   ci: {workflow: ci.yml, job: ci}  # the required job that runs this check
#   notify:                        # this repo's notify-downstream values
#     needs: [release-please, publish-cue]
#     if: <the job's if: text>
#     tag: <the step's tag input>
#   publish:                       # receivers only
#     labels-managed: false        # a YAML boolean
#
# Exit status: 0 the shapes match (prints "cascade wiring: ok, .github <sha>
# (<pin comment>)"); 1 a mismatch (every mismatch is printed on stderr);
# 2 usage, a missing tool or a bad config.
#
# Tools: bash, coreutils, sed, grep, mikefarah yq v4.
# shellcheck disable=SC2016 # the single-quoted ${{ }} strings are GitHub expressions, compared literally
set -euo pipefail

usage_err() { echo "cascade wiring: $*" >&2; exit 2; }
[ $# -le 1 ] || usage_err "usage: wiring-check.sh [<config>]"
CONFIG=${1:-.tasks/cascade/wiring-check.yaml}
W=.github/workflows
yq --version 2>/dev/null | grep -q mikefarah || usage_err "mikefarah yq v4 is required"
[ -f "$CONFIG" ] || usage_err "no config at $CONFIG"
[ -d "$W" ] || usage_err "no $W here; run from the repo root"

fail=0
bad() { echo "cascade wiring: $*" >&2; fail=1; }
eq() { [ "$2" = "$3" ] || bad "$1: expected [$2], got [$3]"; }
re() { [[ $3 =~ $2 ]] || bad "$1: [$3] does not match $2"; }
# y <filter> <file>: one yq read, as raw text.
y() { yq -r "$1" "$2"; }
# yj <filter> <file>: one yq read, as one-line JSON.
yj() { yq -o=json -I=0 "$1" "$2"; }

# --- the config ---------------------------------------------------------------

# Variables a workflow-level env could use to make bash, node or the dynamic
# loader run code in a step that holds the App token, or to redirect the
# runner's own files. They are refused even when the config allows them.
ENV_DENY=" BASH_ENV ENV NODE_OPTIONS SHELLOPTS BASHOPTS PS4 PROMPT_COMMAND IFS PATH HOME
  LD_PRELOAD LD_LIBRARY_PATH LD_AUDIT GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_PARAMETERS
  GIT_CONFIG_COUNT GIT_EXEC_PATH GIT_SSH GIT_SSH_COMMAND GIT_ASKPASS PYTHONSTARTUP PYTHONPATH
  PERL5OPT PERL5LIB RUBYOPT JAVA_TOOL_OPTIONS "

cfg_err() { usage_err "$CONFIG: $*"; }
want_cfg=$(printf '%s' '["ci","env-allow","notify","pin-comment","publish","receiver"]')
[ "$(y 'type' "$CONFIG")" = '!!map' ] || cfg_err "not a YAML map"
for k in $(y 'keys | .[]' "$CONFIG"); do
  [[ $want_cfg == *"\"$k\""* ]] || cfg_err "unknown key $k"
done
[ "$(y '.receiver | type' "$CONFIG")" = '!!bool' ] || cfg_err "receiver must be true or false"
RECEIVER=$(y '.receiver' "$CONFIG")
PIN_COMMENT=$(y '.["pin-comment"] // ""' "$CONFIG")
[[ $PIN_COMMENT =~ ^[A-Za-z0-9._/-]+([\ ][A-Za-z0-9._/-]+)*$ ]] || cfg_err "pin-comment must be words without quotes, # or line breaks"
[ "$(y '.["env-allow"] | type' "$CONFIG")" = '!!seq' ] || cfg_err "env-allow must be a list (use [] for none)"
ENV_ALLOW=" "
while IFS= read -r k; do
  [ -n "$k" ] || continue
  [[ $k =~ ^[A-Z][A-Z0-9_]*$ ]] || cfg_err "env-allow entry [$k] is not an upper-case variable name"
  case "$k" in GITHUB_* | ACTIONS_* | RUNNER_* | CASCADE_*) cfg_err "env-allow may not allow $k" ;; esac
  [[ $ENV_DENY != *" $k "* ]] || cfg_err "env-allow may not allow $k"
  ENV_ALLOW+="$k "
done < <(y '.["env-allow"][] | tostring' "$CONFIG")
CI_WF=$(y '.ci.workflow // ""' "$CONFIG")
CI_JOB=$(y '.ci.job // ""' "$CONFIG")
[[ $CI_WF =~ ^[A-Za-z0-9._-]+\.ya?ml$ ]] || cfg_err "ci.workflow must be a workflow file name"
[[ $CI_JOB =~ ^[A-Za-z0-9_-]+$ ]] || cfg_err "ci.job must be a job id"
NOTIFY_NEEDS=$(yj '.notify.needs // [] | [.[] | tostring]' "$CONFIG")
NOTIFY_IF=$(y '.notify.if // ""' "$CONFIG")
NOTIFY_TAG=$(y '.notify.tag // ""' "$CONFIG")
[ "$NOTIFY_NEEDS" != '[]' ] && [ -n "$NOTIFY_IF" ] && [ -n "$NOTIFY_TAG" ] || cfg_err "notify needs needs, if and tag"
if [ "$RECEIVER" = true ]; then
  [ "$(y '.publish["labels-managed"] | type' "$CONFIG")" = '!!bool' ] || cfg_err "publish.labels-managed must be true or false"
  LABELS_MANAGED=$(y '.publish["labels-managed"]' "$CONFIG")
else
  [ "$(y '.publish // "none"' "$CONFIG")" = none ] || cfg_err "publish is only for a receiver"
fi

# --- the contract's fixed values ----------------------------------------------

# The stop switch. GitHub compares strings without regard to case, so the
# receiver is live when CASCADE_DRY_RUN is false in any letter case (False,
# FALSE); the expression itself is pinned in lower case.
DRY='${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != '\''false'\'' }}'
GATES_ONLY='${{ inputs.gates_only == true }}'
GROUP='${{ github.ref != '\''refs/heads/main'\'' && format('\''deps-cascade-{0}'\'', github.ref) || (inputs.gates_only && '\''deps-cascade-gates'\'' || '\''deps-cascade'\'') }}'
# A gates-only run never publishes: the caller reads its own input, never an
# output of the reusable job, which ran repo code.
PUBLISH_IF='!cancelled() && needs.cascade.outputs.compute-ok == '\''true'\'' && needs.cascade.outputs.dry-run == '\''false'\'' && inputs.dry_run != true && inputs.gates_only != true && vars.CASCADE_DRY_RUN == '\''false'\'' && github.ref == '\''refs/heads/main'\'' && contains(fromJSON('\''["push","recreate","close","conflict","too_long"]'\''), needs.cascade.outputs.action)'

# A key-holding job has exactly these keys: no env, container, services,
# defaults or strategy, so nothing from the repo can run while it holds the key.
JOB_KEYS='["environment","if","name","needs","permissions","runs-on","steps","timeout-minutes"]'

# needs_of <file> <job>: the job's needs as a one-line JSON list (a single
# string counts as a list of one).
needs_of() { J="$2" yq -o=json -I=0 '.jobs[strenv(J)].needs // [] | [] + . | [.[] | tostring]' "$1"; }

# key_job <file> <job> <action> <permissions JSON> <with keys JSON> <name> <timeout>
# A job that holds the App key: the cascade Environment, exactly one step (the
# SHA-pinned cascade action, with no env, if or shell of its own), the key and
# client id only as that step's inputs, and no input the contract does not pass.
key_job() {
  local f=$W/$1 j=$2 n=$1:$2
  if [ ! -f "$f" ]; then bad "$1 is missing"; return 0; fi
  eq "$n keys" "$JOB_KEYS" "$(J="$j" yj '.jobs[strenv(J)] // {} | keys | sort' "$f")"
  eq "$n name" "$6" "$(J="$j" y '.jobs[strenv(J)].name' "$f")"
  eq "$n timeout-minutes" "$7" "$(J="$j" y '.jobs[strenv(J)]["timeout-minutes"]' "$f")"
  eq "$n environment" cascade "$(J="$j" y '.jobs[strenv(J)].environment' "$f")"
  eq "$n runs-on" ubuntu-latest "$(J="$j" y '.jobs[strenv(J)]["runs-on"]' "$f")"
  eq "$n permissions" "$4" "$(J="$j" yj '.jobs[strenv(J)].permissions | sort_keys(.)' "$f")"
  eq "$n step count" 1 "$(J="$j" y '.jobs[strenv(J)].steps | length' "$f")"
  eq "$n step keys" '["name","uses","with"]' "$(J="$j" yj '.jobs[strenv(J)].steps[0] // {} | keys | sort' "$f")"
  eq "$n step name" "$6" "$(J="$j" y '.jobs[strenv(J)].steps[0].name' "$f")"
  eq "$n with keys" "$5" "$(J="$j" yj '.jobs[strenv(J)].steps[0].with // {} | keys | sort' "$f")"
  re "$n uses" "^open-platform-model/\.github/\.github/actions/$3@[0-9a-f]{40}\$" "$(J="$j" y '.jobs[strenv(J)].steps[0].uses' "$f")"
  eq "$n client-id" '${{ vars.CASCADE_APP_CLIENT_ID }}' "$(J="$j" y '.jobs[strenv(J)].steps[0].with["client-id"]' "$f")"
  eq "$n private-key" '${{ secrets.CASCADE_APP_PRIVATE_KEY }}' "$(J="$j" y '.jobs[strenv(J)].steps[0].with["private-key"]' "$f")"
}

# --- notify -------------------------------------------------------------------

r=$W/release.yml
key_job release.yml notify-downstream cascade-notify '{"contents":"read"}' '["client-id","private-key","tag"]' 'Notify downstream' 20
if [ -f "$r" ]; then
  eq "release.yml:notify-downstream needs" "$NOTIFY_NEEDS" "$(needs_of "$r" notify-downstream)"
  eq "release.yml:notify-downstream if" "$NOTIFY_IF" "$(y '.jobs["notify-downstream"].if' "$r")"
  eq "release.yml:notify-downstream tag" "$NOTIFY_TAG" "$(y '.jobs["notify-downstream"].steps[0].with.tag' "$r")"
  # Workflow-level env reaches the notify action's steps, so its keys come
  # from env-allow: a deny-list alone would miss a variable that makes a bash
  # step holding the token run code. The env must be a plain map, so an
  # expression cannot hide its keys.
  re "release.yml env type" '^!!(null|map)$' "$(y '.env | tag' "$r")"
  extra=""
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    [[ $ENV_ALLOW == *" $k "* ]] || extra+="$k "
  done < <(y '.env // {} | select(tag == "!!map") | keys | .[]' "$r")
  eq "release.yml env keys outside env-allow [${ENV_ALLOW# }]" "" "${extra% }"
fi

# --- the receiver -------------------------------------------------------------

if [ "$RECEIVER" = true ]; then
  d=$W/deps-cascade.yml
  key_job deps-cascade.yml publish cascade-publish '{"contents":"read","pull-requests":"read"}' \
    '["client-id","dry-run","gates-only","labels-managed","private-key"]' Publish 15
  if [ -f "$d" ]; then
    eq "deps-cascade.yml top-level keys" '["concurrency","jobs","name","on","permissions"]' "$(yj 'keys | sort' "$d")"
    eq "deps-cascade.yml permissions" '{}' "$(yj '.permissions' "$d")"
    eq "deps-cascade.yml triggers" '["repository_dispatch","schedule","workflow_dispatch"]' "$(yj '.on | keys | sort' "$d")"
    eq "deps-cascade.yml repository_dispatch types" '["upstream-released"]' "$(yj '.on.repository_dispatch.types' "$d")"
    eq "deps-cascade.yml dispatch inputs" '{"dry_run":"boolean","gates_only":"boolean"}' \
      "$(yj '.on.workflow_dispatch.inputs // {} | with_entries(.value = .value.type) | sort_keys(.)' "$d")"
    eq "deps-cascade.yml jobs" '["cascade","publish"]' "$(yj '.jobs | keys | sort' "$d")"
    eq "deps-cascade.yml concurrency.group" "$GROUP" "$(y '.concurrency.group' "$d")"
    eq "deps-cascade.yml concurrency.cancel-in-progress" false "$(y '.concurrency["cancel-in-progress"]' "$d")"
    eq "deps-cascade.yml cascade keys" '["name","permissions","uses","with"]' "$(yj '.jobs.cascade | keys | sort' "$d")"
    eq "deps-cascade.yml cascade permissions" '{"contents":"read","pull-requests":"read","statuses":"write"}' \
      "$(yj '.jobs.cascade.permissions | sort_keys(.)' "$d")"
    re "deps-cascade.yml cascade uses" '^open-platform-model/\.github/\.github/workflows/cascade-receive\.yml@[0-9a-f]{40}$' "$(y '.jobs.cascade.uses' "$d")"
    extra=$(y '.jobs.cascade.with // {} | keys | .[]' "$d" | grep -vxE 'dry-run|gates-only|g2-mode|g3-mode|setup-go|setup-cue|cue-version' || true)
    eq "deps-cascade.yml cascade inputs cascade-receive.yml does not take" "" "${extra//$'\n'/ }"
    eq "deps-cascade.yml cascade dry-run" "$DRY" "$(y '.jobs.cascade.with["dry-run"]' "$d")"
    eq "deps-cascade.yml cascade gates-only" "$GATES_ONLY" "$(y '.jobs.cascade.with["gates-only"]' "$d")"
    eq "deps-cascade.yml publish needs" '["cascade"]' "$(needs_of "$d" publish)"
    eq "deps-cascade.yml publish if" "$PUBLISH_IF" "$(y '.jobs.publish.if' "$d")"
    eq "deps-cascade.yml publish dry-run" "$DRY" "$(y '.jobs.publish.steps[0].with["dry-run"]' "$d")"
    eq "deps-cascade.yml publish gates-only" "$GATES_ONLY" "$(y '.jobs.publish.steps[0].with["gates-only"]' "$d")"
    eq "deps-cascade.yml publish labels-managed" "$LABELS_MANAGED" "$(yj '.jobs.publish.steps[0].with["labels-managed"]' "$d")"
  else
    bad "deps-cascade.yml is missing"
  fi
  c=$W/cascade-gates.yml
  if [ -f "$c" ]; then
    eq "cascade-gates.yml top-level keys" '["concurrency","jobs","name","on","permissions"]' "$(yj 'keys | sort' "$c")"
    eq "cascade-gates.yml permissions" '{}' "$(yj '.permissions' "$c")"
    eq "cascade-gates.yml triggers" '{"pull_request_target":{"types":["opened","reopened","synchronize"]}}' "$(yj '.on' "$c")"
    eq "cascade-gates.yml jobs" '["gates"]' "$(yj '.jobs | keys' "$c")"
    eq "cascade-gates.yml gates keys" '["name","permissions","uses","with"]' "$(yj '.jobs.gates | keys | sort' "$c")"
    eq "cascade-gates.yml gates permissions" '{"actions":"write","statuses":"write"}' "$(yj '.jobs.gates.permissions | sort_keys(.)' "$c")"
    re "cascade-gates.yml gates uses" '^open-platform-model/\.github/\.github/workflows/cascade-gates\.yml@[0-9a-f]{40}$' "$(y '.jobs.gates.uses' "$c")"
  else
    bad "cascade-gates.yml is missing"
  fi
fi

# --- who reads the key --------------------------------------------------------

# Only the caller-owned jobs above read the key or declare the cascade
# Environment, and no call into .github passes secrets (inherit included).
# GitHub matches secret and Environment names without regard to case, so the
# key match is case-insensitive and also catches secrets['...'] and
# toJSON(secrets); an environment (string or map) that mentions cascade in any
# case, or is an expression, counts as declaring the cascade Environment.
want_key="release.yml:jobs.notify-downstream.steps.0.with.private-key"
want_env="release.yml:notify-downstream"
if [ "$RECEIVER" = true ]; then
  want_key=$(printf '%s\n%s' "deps-cascade.yml:jobs.publish.steps.0.with.private-key" "$want_key")
  want_env=$(printf '%s\n%s' "deps-cascade.yml:publish" "$want_env")
fi
got_key="" got_env="" got_sec=""
for f in "$W"/*.yml "$W"/*.yaml; do
  [ -e "$f" ] || continue
  b=${f##*/}
  got_key+=$(yq -r '.. | select(tag == "!!str" and test("(?i)secrets(\\.|\\[\\s*.)cascade_app_private_key|tojson\\(\\s*secrets\\s*\\)")) | path | join(".")' "$f" | sed "s|^|$b:|")$'\n'
  got_env+=$(yq -r '.jobs // {} | to_entries[] | select(.value.environment // "" | tostring | test("(?i)cascade|\\$\\{\\{")) | .key' "$f" | sed "s|^|$b:|")$'\n'
  got_sec+=$(yq -r '.jobs // {} | to_entries[] | select((.value.uses // "") | test("^open-platform-model/\\.github/")) | select(.value | has("secrets")) | .key' "$f" | sed "s|^|$b:|")$'\n'
done
eq "secrets.CASCADE_APP_PRIVATE_KEY readers" "$want_key" "$(printf '%s' "$got_key" | sed '/^$/d' | sort)"
eq "cascade Environment jobs" "$want_env" "$(printf '%s' "$got_env" | sed '/^$/d' | sort)"
eq "calls into .github that pass secrets" "" "$(printf '%s' "$got_sec" | sed '/^$/d')"

# --- the pin ------------------------------------------------------------------

# Every .github reference (the uses: lines and the cascade-task.yml resolver
# ref) carries one full SHA and the pin comment.
refs=""
for f in "$W"/*.yml "$W"/*.yaml; do
  [ -e "$f" ] || continue
  b=${f##*/}
  refs+=$(yq -r '
    (.jobs // {} | to_entries[] | select((.value.uses // "") | test("^open-platform-model/\\.github/")) | .value.uses + " " + (.value.uses | line_comment)),
    (.jobs // {} | to_entries[] | (.value.steps // [])[] | select((.uses // "") | test("^open-platform-model/\\.github/")) | .uses + " " + (.uses | line_comment)),
    (.jobs // {} | to_entries[] | (.value.steps // [])[] | select(.with.repository == "open-platform-model/.github") | "resolver@" + (.with.ref // "") + " " + ((.with.ref // "") | line_comment))
  ' "$f" | sed "s|^|$b |")$'\n'
done
refs=$(printf '%s' "$refs" | sed '/^$/d' | sort)
# "<file> <target>" with the SHA and comment stripped.
want_refs="release.yml open-platform-model/.github/.github/actions/cascade-notify"
if [ "$RECEIVER" = true ]; then
  want_refs=$(printf '%s\n' \
    "cascade-gates.yml open-platform-model/.github/.github/workflows/cascade-gates.yml" \
    "cascade-task.yml resolver" \
    "deps-cascade.yml open-platform-model/.github/.github/actions/cascade-publish" \
    "deps-cascade.yml open-platform-model/.github/.github/workflows/cascade-receive.yml" \
    "release.yml open-platform-model/.github/.github/actions/cascade-notify" | sort)
fi
eq ".github references" "$want_refs" "$(printf '%s\n' "$refs" | sed -E 's/@[^ ]* .*$//' | sort)"
shas=$(printf '%s\n' "$refs" | sed -E 's/^[^ ]+ [^@]*@([^ ]*) .*$/\1/' | sort -u)
re "one .github SHA" '^[0-9a-f]{40}$' "$shas"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  eq "pin comment on [${line% *}]" "$PIN_COMMENT" "$(printf '%s' "$line" | sed -E 's/^[^ ]+ [^ ]+ //')"
done <<<"$refs"

# --- the check runs on every PR -----------------------------------------------

# The required CI job runs this check as a plain step: on every pull request
# (no path filter, which would leave the required check unreported), with no
# if: or continue-on-error that would let a failure pass.
ci=$W/$CI_WF
if [ -f "$ci" ]; then
  eq "$CI_WF runs on pull_request" true "$(y '.on | has("pull_request")' "$ci")"
  eq "$CI_WF pull_request path filters" '[]' "$(yj '[.on.pull_request // {} | keys | .[] | select(. == "paths" or . == "paths-ignore")]' "$ci")"
  eq "$CI_WF:$CI_JOB exists" true "$(J="$CI_JOB" y '.jobs | has(strenv(J))' "$ci")"
  eq "$CI_WF:$CI_JOB if and continue-on-error" '[]' "$(J="$CI_JOB" yj '[.jobs[strenv(J)] // {} | keys | .[] | select(. == "if" or . == "continue-on-error")]' "$ci")"
  eq "$CI_WF:$CI_JOB steps running task cascade:wiring:check" 1 \
    "$(J="$CI_JOB" y '[.jobs[strenv(J)].steps // [] | .[] | select(.run == "task cascade:wiring:check")] | length' "$ci")"
  eq "$CI_WF:$CI_JOB wiring step if and continue-on-error" '[]' \
    "$(J="$CI_JOB" yj '[.jobs[strenv(J)].steps // [] | .[] | select(.run == "task cascade:wiring:check") | keys | .[] | select(. == "if" or . == "continue-on-error")]' "$ci")"
else
  bad "$CI_WF is missing"
fi

[ "$fail" = 0 ] || exit 1
echo "cascade wiring: ok, .github $shas ($PIN_COMMENT)"

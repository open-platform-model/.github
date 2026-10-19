# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# The reusable cite-lint workflow: its static shape (the cascade-only rules of
# static.sh, such as the Guard step, do not apply to it) and the inputs check,
# the one step that runs before anything is checked out.

new_fx

CL="$WORKFLOWS/cite-lint.yml"
check "cite-lint: the workflow exists" test -f "$CL"

expect "cite-lint: only workflow_call" 0 "workflow_call" -- yq -r '.on | keys | join(",")' "$CL"
expect "cite-lint: declares no secrets input" 0 "null" -- yq -r '.on.workflow_call.secrets' "$CL"
expect "cite-lint: has no job in an Environment" 0 "" -- \
  yq -r '.jobs | to_entries[] | select(.value.environment != null) | .key' "$CL"
check "cite-lint: reads no secret" bash -c '! grep -n "secrets" "$1"' _ "$CL"
expect "cite-lint: no permissions at the workflow level" 0 "{}" -- yq -o=json -I=0 '.permissions' "$CL"
expect "cite-lint: every job reads contents only" 0 "" -- \
  yq -r '.jobs | to_entries[] | select((.value.permissions | keys | join(",")) != "contents" or .value.permissions.contents != "read") | .key' "$CL"
expect "cite-lint: every job has a timeout" 0 "" -- \
  yq -r '.jobs | to_entries[] | select(.value."timeout-minutes" == null) | .key' "$CL"
expect "cite-lint: has no expression inside run:" 0 "" -- \
  yq -r '.jobs | to_entries[] | .key as $j | .value.steps[]? | select((.run // "") | test("\$\{\{")) | $j + "/" + (.name // "?")' "$CL"
check "cite-lint: pins every action to a SHA with a version comment" bash -c '
  ! grep -nE "^ *(- )?uses:" "$1" | grep -vE "uses: [A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40} # v[0-9]"' _ "$CL"
expect "cite-lint: every checkout keeps no credentials" 0 "" -- \
  yq -r '.jobs | to_entries[] | .key as $j | .value.steps[]? | select((.uses // "") | test("^actions/checkout@")) | select(.with."persist-credentials" != false) | $j + "/" + .name' "$CL"
expect "cite-lint: the Go setup uses no cache" 0 "" -- \
  yq -r '.jobs | to_entries[] | .key as $j | .value.steps[]? | select((.uses // "") | test("^actions/setup-go@")) | select(.with.cache != false) | $j + "/" + .name' "$CL"
check "cite-lint: the enh-ref default is a full commit SHA" bash -c '[[ $1 =~ ^[0-9a-f]{40}$ ]]' _ \
  "$(yq -r '.on.workflow_call.inputs."enh-ref".default' "$CL")"
expect "cite-lint: the three inputs are optional strings" 0 $'enh-ref string false\nexclude string false\npaths string false' -- \
  yq -r '.on.workflow_call.inputs | to_entries | sort_by(.key)[] | .key + " " + .value.type + " " + (.value.required | tostring)' "$CL"
expect "cite-lint: only the tool checkout takes the enh-ref input" 0 "open-platform-model/enhancements" -- \
  yq -r '.jobs[].steps[] | select((.with.ref // "") | test("inputs")) | .with.repository' "$CL"

# The Check inputs step, run on its own.
CL_CHECK=$(yaml_run "$CL" cite-lint "Check inputs")
# cl_inputs <enh-ref> <paths> <exclude>: runs the step; prints its output,
# then the argument file with | in place of each NUL.
cl_inputs() {
  local rc=0
  rm -f "$FX/cite-lint.args"
  ENH_REF="$1" PATHS="$2" EXCLUDE="$3" RUNNER_TEMP="$FX" bash -e -o pipefail -c "$CL_CHECK" || rc=$?
  if [ -f "$FX/cite-lint.args" ]; then tr '\0' '|' <"$FX/cite-lint.args"; echo; fi
  return "$rc"
}
CL_SHA=0123456789abcdef0123456789abcdef01234567
CL_NOTICE="::notice::enh at open-platform-model/enhancements $CL_SHA"
expect "cite-lint inputs: no paths and no excludes lint the root" 0 "$CL_NOTICE"$'\n--|.|' -- cl_inputs "$CL_SHA" "" ""
expect "cite-lint inputs: excludes come first, then --, then the paths" 0 "$CL_NOTICE"$'\n--exclude=gen/|--exclude=x.go|--|pkg|cmd|' -- \
  cl_inputs "$CL_SHA" $'pkg\r\n  cmd  \n\n' $'gen/\n x.go \n'
expect "cite-lint inputs: an exclude that looks like a flag stays one value" 0 "$CL_NOTICE"$'\n--exclude=--root=/etc|--|.|' -- \
  cl_inputs "$CL_SHA" "" "--root=/etc"
expect "cite-lint inputs: a name with two dots is not a parent segment" 0 "$CL_NOTICE"$'\n--|a/..b|' -- cl_inputs "$CL_SHA" "a/..b" ""
cl_refuses() { # cl_refuses <name> <enh-ref> <paths> <message start>
  run cl_inputs "$2" "$3" ""
  check "cite-lint inputs: $1" bash -c '[ "$1" = 1 ] && [[ $2 == "::error::$3"* ]]' _ "$RC" "$OUT" "$4"
}
cl_refuses "a branch name is refused" main "" "enh-ref must be a full 40-hex"
cl_refuses "a short SHA is refused" "${CL_SHA:0:12}" "" "enh-ref must be a full 40-hex"
cl_refuses "an upper-case SHA is refused" "${CL_SHA^^}" "" "enh-ref must be a full 40-hex"
cl_refuses "an empty ref is refused" "" "" "enh-ref must be a full 40-hex"
cl_refuses "a parent path is refused" "$CL_SHA" "../x" "path [../x] must be relative"
cl_refuses "a nested parent path is refused" "$CL_SHA" "a/../b" "path [a/../b] must be relative"
cl_refuses "an absolute path is refused" "$CL_SHA" "/etc" "path [/etc] must be relative"
cl_refuses "a path that looks like a flag is refused" "$CL_SHA" "-n" "path [-n] must be relative"

# The Lint step reads the argument file back. A stub enh prints its arguments
# and exits 3, so the cases see the exact command line and the exit status.
CL_LINT=$(yaml_run "$CL" cite-lint "Lint")
cl_lint() { # cl_lint <paths> <exclude>
  cl_inputs "$CL_SHA" "$1" "$2" >/dev/null
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@"\nexit 3\n' >"$FX/enh"
  chmod +x "$FX/enh"
  GITHUB_WORKSPACE=/ws RUNNER_TEMP="$FX" bash -e -o pipefail -c "$CL_LINT"
}
expect "cite-lint lint: the tool gets the root, the excludes, then -- and the paths; its exit status is the job's" 3 \
  $'cite-lint\n--root\n/ws/repo\n--exclude=gen/\n--exclude=x.go\n--\npkg\ncmd' -- cl_lint $'pkg\ncmd' $'gen/\nx.go'
expect "cite-lint lint: no input lints the root" 3 $'cite-lint\n--root\n/ws/repo\n--\n.' -- cl_lint "" ""

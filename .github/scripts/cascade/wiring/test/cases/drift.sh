# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# mirror-drift.sh, the daily drift check of the publish mirrors, against gh
# shim answers; and the shape of cascade-mirror-drift.yml.

DRIFT="$WIRING/mirror-drift.sh"
DRIFT_WF="$WORKFLOWS/cascade-mirror-drift.yml"
# raw_args <repo> <path>: the gh call the check makes for one file.
raw_args() { printf '%s\n' api -H "Accept: application/vnd.github.raw" "repos/open-platform-model/$1/contents/$2?ref=main"; }
# answer <rc> <file> <repo> <path>: the next answer for that file.
answer() {
  local -a a
  mapfile -t a < <(raw_args "$3" "$4")
  gh_fx_file "$1" "$2" -- "${a[@]}"
}

new_fx
toy_files "$FX/toy"
answer 0 "$FX/toy/.tasks/cascade/pins.sh" cascade-sandbox-down .tasks/cascade/pins.sh
answer 0 "$FX/toy/.tasks/cascade/classes" cascade-sandbox-down .tasks/cascade/classes
run bash "$DRIFT" cascade-sandbox-down
check "drift: matching files pass" bash -c '[ "$1" = 0 ] && [ "$2" = "$3" ]' _ "$RC" "$OUT" \
  $'ok cascade-sandbox-down .tasks/cascade/pins.sh\nok cascade-sandbox-down .tasks/cascade/classes'

new_fx
toy_files "$FX/toy"
printf 'shipped UPSTREAM_VERSION\n' >"$FX/classes"
answer 0 "$FX/toy/.tasks/cascade/pins.sh" cascade-sandbox-down .tasks/cascade/pins.sh
answer 0 "$FX/classes" cascade-sandbox-down .tasks/cascade/classes
run bash "$DRIFT" cascade-sandbox-down
H=$(sha256sum <"$FX/classes" | cut -c1-64)
check "drift: a changed classes file fails, naming the receiver, the file and both hashes" bash -c '
  [ "$1" = 1 ] && grep -qx "ok cascade-sandbox-down .tasks/cascade/pins.sh" <<<"$2" \
    && grep -qF "::error::the .github mirror of cascade-sandbox-down is stale: .tasks/cascade/classes on its main has sha256 $3, the mirror was written from 921a950ca5ad36fa5a4fc0802d4dd8d2d915633c04fc22bbfd0976b60e2d19f7" <<<"$2" \
    && grep -q "^DRIFT cascade-sandbox-down .tasks/cascade/classes: " <<<"$2"' _ "$RC" "$OUT" "$H"

new_fx
toy_files "$FX/toy"
mapfile -t A < <(raw_args cascade-sandbox-down .tasks/cascade/pins.sh)
gh_fx_err 1 "HTTP 404: Not Found" -- "${A[@]}"
answer 0 "$FX/toy/.tasks/cascade/classes" cascade-sandbox-down .tasks/cascade/classes
run bash "$DRIFT" cascade-sandbox-down
check "drift: an unreadable file fails, and the others are still checked" bash -c '
  [ "$1" = 1 ] && grep -q "^ERROR cascade-sandbox-down .tasks/cascade/pins.sh: HTTP 404" <<<"$2" \
    && grep -qx "::error::cannot read .tasks/cascade/pins.sh from the main of cascade-sandbox-down" <<<"$2" \
    && grep -qx "ok cascade-sandbox-down .tasks/cascade/classes" <<<"$2"' _ "$RC" "$OUT"

new_fx
expect "drift: an unknown receiver is usage" 2 "" "not a cascade receiver" -- bash "$DRIFT" core

new_fx
gh_accept "api -H Accept: application/vnd.github.raw repos/open-platform-model/*/contents/.tasks/cascade/*?ref=main"
run bash "$DRIFT"
check "drift: by default every product receiver's mirrored files are read" bash -c '
  [ "$1" = 1 ] && [ "$(grep -c "^DRIFT " <<<"$2")" = 10 ] \
    && [ "$(grep -c "repos/open-platform-model/library/contents/.tasks/cascade/lib.sh?ref=main" "$3")" = 1 ] \
    && ! grep -q cascade-sandbox-down "$3"' _ "$RC" "$OUT" "$GHFX/log"
: >"$GHFX/accept"

# --- the workflow ----------------------------------------------------------------
expect "drift workflow: read-only at the top" 0 "contents=read" -- yq -r '.permissions | to_entries | map(.key + "=" + .value) | join(",")' "$DRIFT_WF"
expect "drift workflow: the job is read-only" 0 "contents=read" -- yq -r '.jobs.drift.permissions | to_entries | map(.key + "=" + .value) | join(",")' "$DRIFT_WF"
expect "drift workflow: daily and on dispatch" 0 "schedule,workflow_dispatch" -- yq -r '.on | keys | sort | join(",")' "$DRIFT_WF"
check "drift workflow: runs the cron daily" bash -c '[[ "$(yq -r ".on.schedule[0].cron" "$1")" =~ ^[0-9]+\ [0-9]+\ \*\ \*\ \*$ ]]' _ "$DRIFT_WF"
check "drift workflow: no secret, only the run token" bash -c '! grep -q "secrets\\." "$1" && [ "$(yq -r ".jobs.drift.steps[1].env.GH_TOKEN" "$1")" = "\${{ github.token }}" ]' _ "$DRIFT_WF"
expect "drift workflow: runs mirror-drift.sh" 0 "bash .github/scripts/cascade/wiring/mirror-drift.sh" -- yq -r '.jobs.drift.steps[1].run' "$DRIFT_WF"
expect "drift workflow: the checkout keeps no credentials" 0 "false" -- yq -r '.jobs.drift.steps[0].with."persist-credentials"' "$DRIFT_WF"

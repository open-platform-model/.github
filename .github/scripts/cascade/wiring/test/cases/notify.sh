# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# notify.sh: validation, the payload bytes, retries and the Go proxy wait.

new_fx
N() { env CASCADE_REPO="$1" bash "$NOTIFY" "${@:2}"; }

expect "notify: library targets" 0 "opm-operator,cli" -- N library validate --tag v1.0.0-beta.4
expect "notify: catalog_opm targets" 0 "library,opm-operator,cli" -- N catalog_opm validate --tag opm-v4.5.1
expect "notify: opm-controller, the renamed opm-operator, targets cli" 0 "cli" -- N opm-controller validate --tag v1.0.0-beta.9
expect "notify: the sandbox target" 0 "cascade-sandbox-down" -- N cascade-sandbox-up validate --tag v0.2.0
expect "notify: a catalog tag without opm- fails" 1 "" "is not a release tag of catalog_opm" -- N catalog_opm validate --tag v4.5.1
expect "notify: an opm- tag outside catalog_opm fails" 1 "" "is not a release tag of core" -- N core validate --tag opm-v2.0.0
expect "notify: an unknown source fails" 1 "" "not a cascade source: \`modules\`" -- N modules validate --tag v1.0.0
expect "notify: a hostile tag fails, named safely" 1 "" '`v1.0.0???id?` is not a release tag' -- N core validate --tag 'v1.0.0;$(id)'
expect "notify: usage" 2 "" -- N core validate v1.0.0
expect "notify: no repo" 2 "" "CASCADE_REPO is not set" -- env -u CASCADE_REPO bash "$NOTIFY" validate --tag v1.0.0

# --- dispatch -----------------------------------------------------------------
new_fx
gh_fx 0 "" -- api -X POST repos/open-platform-model/opm-operator/dispatches --input -
gh_fx 0 "" -- api -X POST repos/open-platform-model/cli/dispatches --input -
run N library dispatch --tag v1.0.0-beta.4
WANT='{"event_type":"upstream-released","client_payload":{"source":"library","tags":["v1.0.0-beta.4"]}}'
check "notify: dispatch exits 0" test "$RC" = 0
check "notify: exact payload bytes to opm-operator" test "$(cat "$GHFX/stdin.1")" = "$WANT"
check "notify: exact payload bytes to cli" test "$(cat "$GHFX/stdin.2")" = "$WANT"
check "notify: no trailing newline in the payload" bash -c '[ "$(wc -c <"$1")" = "${#2}" ]' _ "$GHFX/stdin.1" "$WANT"
check "notify: one summary line per target" test "$(cat "$GITHUB_STEP_SUMMARY")" = $'- `opm-operator`: dispatched (HTTP 204)\n- `cli`: dispatched (HTTP 204)'
check "notify: no sleep when every dispatch succeeds" test ! -s "$FX/sleep.log"

new_fx
for _ in 1 2 3; do gh_fx_err 1 "gh: Server Error (HTTP 500)" -- api -X POST repos/open-platform-model/opm-operator/dispatches --input -; done
gh_fx 0 "" -- api -X POST repos/open-platform-model/cli/dispatches --input -
run N library dispatch --tag v1.0.0-beta.4
check "notify: one target down fails the job" test "$RC" = 1
check "notify: the next target is still dispatched" test "$(gh_count '*repos/open-platform-model/cli/dispatches*')" = 1
check "notify: three attempts at the failing target" test "$(gh_count '*repos/open-platform-model/opm-operator/dispatches*')" = 3
check "notify: waits 5 and 15 seconds between attempts" test "$(cat "$FX/sleep.log")" = $'5\n15'
check "notify: both results in the summary" test "$(cat "$GITHUB_STEP_SUMMARY")" = $'- `opm-operator`: failed after 3 attempts (HTTP 500)\n- `cli`: dispatched (HTTP 204)'

new_fx
gh_fx_err 1 "HTTP 502" -- api -X POST repos/open-platform-model/cascade-sandbox-down/dispatches --input -
gh_fx 0 "" -- api -X POST repos/open-platform-model/cascade-sandbox-down/dispatches --input -
run N cascade-sandbox-up dispatch --tag v0.2.0
check "notify: a retry that succeeds passes" bash -c '[ "$1" = 0 ] && [ "$(cat "$2")" = "- \`cascade-sandbox-down\`: dispatched (HTTP 204)" ] && [ "$(cat "$3")" = 5 ]' _ "$RC" "$GITHUB_STEP_SUMMARY" "$FX/sleep.log"

new_fx
expect "notify: dispatch refuses a bad tag before any call" 1 "" "is not a release tag" -- N library dispatch --tag 'v1.0.0 x'
check "notify: no gh call for a bad tag" test ! -s "$GHFX/log"

# --- the Go proxy wait --------------------------------------------------------
new_fx
# fake curl: prints the next status from $FX/curl.codes (the last repeats).
cat >"$FX/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CASCADE_FIXTURE_DIR/curl.log"
n=$(wc -l <"$CASCADE_FIXTURE_DIR/curl.log")
code=$(sed -n "${n}p" "$CASCADE_FIXTURE_DIR/curl.codes")
[ -n "$code" ] || code=$(tail -n 1 "$CASCADE_FIXTURE_DIR/curl.codes")
printf '%s' "$code"
SH
chmod +x "$FX/curl"
export CASCADE_CURL="$FX/curl"
printf '404\n' >"$FX/curl.codes"
run N library wait-proxy --tag v1.0.0-beta.4
check "proxy: a timeout still exits 0 with a warning" bash -c '[ "$1" = 0 ] && [[ $2 == *"::warning::the Go proxy did not serve library v1.0.0-beta.4 within 10 minutes"* ]]' _ "$RC" "$OUT"
check "proxy: polls every 30 s for 10 minutes" bash -c '[ "$(wc -l <"$1")" = 21 ] && [ "$(sort -u "$2")" = 30 ] && [ "$(wc -l <"$2")" = 20 ]' _ "$FX/curl.log" "$FX/sleep.log"
check "proxy: asks for the tag's .info" bash -c '[[ $(head -n 1 "$1") == *"https://proxy.golang.org/github.com/open-platform-model/library/@v/v1.0.0-beta.4.info"* ]]' _ "$FX/curl.log"
new_fx
cp "$T_ROOT/fx$((FX_N - 1))/curl" "$FX/curl"
export CASCADE_CURL="$FX/curl"
printf '404\n410\n200\n' >"$FX/curl.codes"
expect "proxy: stops when the proxy serves the tag" 0 "the Go proxy serves library v1.0.0-beta.4" -- N library wait-proxy --tag v1.0.0-beta.4
new_fx
expect "proxy: other sources do not wait" 0 "" -- N core wait-proxy --tag v2.0.0
check "proxy: no request for other sources" test ! -e "$FX/curl.log"
unset CASCADE_CURL

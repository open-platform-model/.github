# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# What every request of every earlier case looked like. Runs last.
all_logs="$T_ROOT/all-curl.log"
cat "$T_ROOT"/fx*/curl.log "$T_ROOT"/fx*/git.log >"$all_logs" 2>/dev/null || true
check "requests were made" test -s "$all_logs"
check "curl always gets -q first" bash -c '! grep -v -e "^-q -sS --connect-timeout 10 --max-time 60 -o " -e "^git " "$1"' _ "$all_logs"
check "the curl log covers newest and pin-of requests" bash -c 'grep -q "/tags/list" "$1" && grep -q "/blobs/sha256:" "$1"' _ "$all_logs"
check "no request goes to api.github.com" bash -c '! grep -q "api\.github\.com" "$1"' _ "$all_logs"
check "no request carries GITHUB_TOKEN or GH_TOKEN" bash -c '! grep -qF -e "$2" -e "$3" "$1"' _ "$all_logs" "$GITHUB_TOKEN" "$GH_TOKEN"
new_fx
run "$T_HERE/shim/curl" -s https://ghcr.io/
check "the curl shim exits 2 on another shape" test "$RC" = 2

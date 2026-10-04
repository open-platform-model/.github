# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# newest: candidates, publication probes, holds, the new-major warning,
# pagination, --expect and --json.

CORE_REPO=open-platform-model/opmodel.dev/core
OPM_REPO=open-platform-model/opmodel.dev/catalogs/opm
LIB=github.com/open-platform-model/library
CORE_TAGS="$FIXTURES/ghcr/core.tags.json"
OPM_TAGS="$FIXTURES/ghcr/catalogs-opm.tags.json"

# fx_ghcr_file <repo> <tags json file> [extra tag]...: token plus one page.
fx_ghcr_file() {
  local repo="$1" f="$2" tmp="$FX/tags-$RANDOM.json"
  shift 2
  jq '.tags += $ARGS.positional' "$f" --args "$@" >"$tmp"
  fx_text "$(ghcr_token_url "$repo")" '{"token":"dummy-ghcr-token"}'
  fx_body "$(ghcr_tags_url "$repo")" "$tmp"
}
fx_unpublished_cue() { local repo="$1" t; shift; for t in "$@"; do fx_status "$(ghcr_manifest_url "$repo" "$t")" 404; done; }

# --- cue --------------------------------------------------------------------
new_fx
fx_ghcr_file "$CORE_REPO" "$CORE_TAGS"
fx_published_cue "$CORE_REPO" v2.0.0-beta.2
expect "cue: newest beta among interleaved dev builds" 0 v2.0.0-beta.2 -- "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1
check "dev builds are never probed" bash -c '! grep -q "0\.dev\." "$1"' _ "$FX/curl.log"
check "only one manifest probed" test "$(grep -c '/manifests/' "$FX/curl.log")" = 1
expect "cue: at the newest already" 3 "" -- "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.2
expect "cue: --repo-root is accepted" 0 v2.0.0-beta.2 -- "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1 --repo-root "$FX/root"

new_fx
fx_ghcr_file "$CORE_REPO" "$CORE_TAGS" v3.0.0-alpha.1 v3.0.0-0.dev.1791100000.gabcdef0
fx_published_cue "$CORE_REPO" v2.0.0-beta.2
expect "cue: a v3 prerelease is never the answer" 0 v2.0.0-beta.2 \
  "new major available: \`v3.0.0-alpha.1\` (prerelease)" -- "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1
expect "cue: the new-major warning keeps exit 3" 3 "" "new major available" -- "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.2
new_fx
fx_ghcr_file "$CORE_REPO" "$CORE_TAGS" v3.0.0-alpha.1 v3.0.0
fx_published_cue "$CORE_REPO" v2.0.0-beta.2
run "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1
check "cue: a released v3 is named without (prerelease)" \
  bash -c '[ "$1" = v2.0.0-beta.2 ] && [[ $2 == *"new major available: \`v3.0.0\`"* ]] && [[ $2 != *"(prerelease)"* ]]' _ "$OUT" "$ERR"

new_fx
fx_ghcr_file "$OPM_REPO" "$OPM_TAGS" v4.6.0-rc.1
fx_published_cue "$OPM_REPO" v4.5.1 v4.6.0-rc.1
expect "stable pin skips prereleases" 0 v4.5.1 -- "$R" newest cue opmodel.dev/catalogs/opm@v4 --current v4.4.4
expect "--pre admits prereleases" 0 v4.6.0-rc.1 -- "$R" newest cue opmodel.dev/catalogs/opm@v4 --current v4.4.4 --pre
expect "catalogs/opm v1 and v2 tags are other majors" 3 "" -- "$R" newest cue opmodel.dev/catalogs/opm@v4 --current v4.5.1

new_fx
fx_ghcr_file "$OPM_REPO" "$OPM_TAGS"
fx_unpublished_cue "$OPM_REPO" v4.5.1
expect "unpublished newest keeps the pin" 3 "" \
  "no published version newer than \`v4.5.0\`; newest tagged \`v4.5.1\` is not published yet" -- \
  "$R" newest cue opmodel.dev/catalogs/opm@v4 --current v4.5.0
fx_published_cue "$OPM_REPO" v4.5.0
expect "skip to an older published candidate" 0 v4.5.0 "skip \`v4.5.1\`" -- "$R" newest cue opmodel.dev/catalogs/opm@v4 --current v4.4.4
fx_unpublished_cue "$OPM_REPO" v4.5.0 v4.4.5
expect "three unpublished candidates give exit 3" 3 "" "newest tagged \`v4.5.1\` is not published yet" -- \
  "$R" newest cue opmodel.dev/catalogs/opm@v4 --current v4.4.4
expect "never backwards" 3 "" "\`v4.9.0\` is newer than the newest published \`v4.5.1\`" -- \
  "$R" newest cue opmodel.dev/catalogs/opm@v4 --current v4.9.0

new_fx
fx_ghcr "$CORE_REPO" v2.0.0-beta.1 v2.0.0-beta.2 v2.0.0-beta.3 v2.0.0-beta.4 v2.0.0-beta.5 v2.0.0-beta.6 \
  v2.0.0-beta.7 v2.0.0-beta.8 v2.0.0-beta.9 v2.0.0-beta.10 v2.0.0-beta.11 v2.0.0-beta.12
expect "ten unpublished candidates give exit 1" 1 "" "none of the 10 newest" -- "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1
check "exactly ten probes" test "$(grep -c '/manifests/' "$FX/curl.log")" = 10
check "beta.2 is the one never probed" bash -c '! grep -q "manifests/v2.0.0-beta.2$" "$1"' _ "$FX/curl.log"

new_fx
fx_status "$(ghcr_token_url "$CORE_REPO")" 403
expect "token 403: newest is exit 1" 1 "" "unknown on GHCR or private" -- "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1
new_fx
fx_text "$(ghcr_token_url "$CORE_REPO")" '{"token":"dummy-ghcr-token"}'
fx_status "$(ghcr_tags_url "$CORE_REPO")" 404
expect "tags 404: newest is exit 1" 1 "" "unknown on GHCR or private" -- "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1
fx_status "$(ghcr_manifest_url "$CORE_REPO" v2.0.0-beta.2)" 404
expect "tags 404: published reads no tag list, a manifest 404 is 3" 3 "" -- "$R" published cue opmodel.dev/core@v2 v2.0.0-beta.2

# --- pagination --------------------------------------------------------------
new_fx
fx_text "$(ghcr_token_url "$CORE_REPO")" '{"token":"dummy-ghcr-token"}'
p1=$(ghcr_tags_url "$CORE_REPO")
p2="$GHCR/v2/$CORE_REPO/tags/list?last=v2.0.0-beta.1&n=1000"
fx_text "$p1" '{"tags":["v2.0.0-alpha.13","v2.0.0-beta.1"]}'
fx_headers "$p1" "link: </v2/$CORE_REPO/tags/list?last=v2.0.0-beta.1&n=1000>; rel=\"next\""
fx_text "$p2" '{"tags":["v2.0.0-beta.2"]}'
fx_published_cue "$CORE_REPO" v2.0.0-beta.2
expect "a relative Link is followed on ghcr.io" 0 v2.0.0-beta.2 -- "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1
check "page two was requested on ghcr.io" grep -qF " $p2" "$FX/curl.log"

new_fx
fx_text "$(ghcr_token_url "$CORE_REPO")" '{"token":"dummy-ghcr-token"}'
for i in $(seq 1 21); do
  u="$GHCR/v2/$CORE_REPO/tags/list?n=1000"
  [ "$i" = 1 ] || u="$GHCR/v2/$CORE_REPO/tags/list?last=p$i&n=1000"
  fx_text "$u" "{\"tags\":[\"v2.0.0-beta.$i\"]}"
  fx_headers "$u" "Link: </v2/$CORE_REPO/tags/list?last=p$((i + 1))&n=1000>; rel=\"next\""
done
expect "21 pages give exit 1" 1 "" "more than 20 pages" -- "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1
check "it stopped after page 20" test "$(grep -c '/tags/list' "$FX/curl.log")" = 20

new_fx
fx_text "$(ghcr_token_url "$CORE_REPO")" '{"token":"dummy-ghcr-token"}'
fx_text "$p1" '{"tags":["v2.0.0-beta.1"]}'
fx_headers "$p1" 'link: <https://evil.example/v2/x/tags/list?n=1000>; rel="next"'
expect "a Link to another host is exit 1" 1 "" "another host" -- "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1

# --- go -----------------------------------------------------------------------
new_fx
fx_body "$PROXY/$LIB/@v/list" "$FIXTURES/goproxy/library.list"
fx_body "$PROXY/$LIB/@v/v1.0.0-beta.3.info" "$FIXTURES/goproxy/library-v1.0.0-beta.3.info"
expect "go: newest prerelease from the unsorted list" 0 v1.0.0-beta.3 -- "$R" newest go "$LIB" --current v1.0.0-beta.1
check "go: v2 list 404 gives no new-major warning" bash -c '[[ $1 != *"new major"* ]]' _ "$ERR"
check "go: the v2 list was asked for" grep -qF "$PROXY/$LIB/v2/@v/list" "$FX/curl.log"
check "go: never asks for @latest" bash -c '! grep -q "@latest" "$1"' _ "$FX/curl.log"
fx_text "$PROXY/$LIB/v2/@v/list" $'v2.0.0-alpha.1\n'
expect "go: a v2 list warns new major" 0 v1.0.0-beta.3 "new major available: \`v2.0.0-alpha.1\` (prerelease)" -- \
  "$R" newest go "$LIB" --current v1.0.0-beta.1
rm "$(fx_path "$PROXY/$LIB/v2/@v/list")"
fx_status "$PROXY/$LIB/v2/@v/list" 410
expect "go: a v2 list 410 is no new major" 0 v1.0.0-beta.3 -- "$R" newest go "$LIB" --current v1.0.0-beta.1
expect "go: /vN suffix must match --current" 2 "" -- "$R" newest go "$LIB/v2" --current v1.0.0-beta.1

new_fx
X=example.com/mod
fx_golist "$X" v0.1.0 v0.2.0 v0.3.0-0.20261003120000-abcdefabcdef v0.2.1-dev.1 v1.0.0
fx_goinfo "$X" v0.2.0 v1.0.0
expect "go: v0 to v1 probes the unsuffixed list" 0 v0.2.0 "new major available: \`v1.0.0\`" -- "$R" newest go "$X" --current v0.1.0
check "go: pseudo-versions and dev builds are never probed" bash -c '! grep -qE "v0\.3\.0-0\.2026|dev\.1" "$1"' _ "$FX/curl.log"
check "go: no /v1 path" bash -c '! grep -q "/v1/@v" "$1"' _ "$FX/curl.log"
expect "go: missing module is exit 1" 1 "" "has no module" -- "$R" newest go example.com/none --current v0.1.0

# --- release and opm-cli ----------------------------------------------------------
new_fx
fx_refs_file opm-operator "$FIXTURES/git/opm-operator.refs"
fx_status "$(rel_url opm-operator v1.0.0-beta.5 install.yaml)" 404
rel_ok opm-operator v1.0.0-beta.4 install.yaml
expect "release: draft skipped" 0 v1.0.0-beta.4 "skip \`v1.0.0-beta.5\`" -- \
  "$R" newest release opm-operator --asset install.yaml --current v1.0.0-beta.3
expect "release: needs --asset" 2 "" -- "$R" newest release opm-operator --current v1.0.0-beta.3

new_fx
fx_refs_file cli "$FIXTURES/git/cli.refs"
printf '%040d\trefs/tags/v2.0.0-alpha.1\n' 0 >>"$FX/git/cli.refs"
rel_ok cli v1.0.0-beta.7 opm-linux-amd64.tar.gz
fx_status "$(rel_url cli v1.0.0-beta.7 checksums.txt)" 404
rel_ok cli v1.0.0-beta.6 opm-linux-amd64.tar.gz checksums.txt
: >"$FX/warnings"
expect "opm-cli: missing second asset skipped" 0 v1.0.0-beta.6 -- \
  env CASCADE_WARNINGS="$FX/warnings" "$R" newest opm-cli --current v1.0.0-beta.4
check "opm-cli warnings are keyed github.com/open-platform-model/cli" \
  grep -qxF $'github.com/open-platform-model/cli\tnew major available: `v2.0.0-alpha.1` (prerelease)' "$FX/warnings"
check "opm-cli: git ls-remote asks for v* tags of the cli repo" \
  grep -qF "git ls-remote --tags --refs https://github.com/open-platform-model/cli refs/tags/v*" "$FX/git.log"
new_fx
fx_refs opm-operator v1.0.0-beta.3 v1.0.0-beta.4 v2.0.0
rel_ok opm-operator v1.0.0-beta.4 install.yaml
: >"$FX/warnings"
run env CASCADE_WARNINGS="$FX/warnings" "$R" newest release opm-operator --asset install.yaml --current v1.0.0-beta.3
check "release warnings are keyed github.com/open-platform-model/<repo>" \
  grep -qxF $'github.com/open-platform-model/opm-operator\tnew major available: `v2.0.0`' "$FX/warnings"
new_fx
fx_refs opm-operator v1.0.0-beta.3
touch "$FX/git/opm-operator.refs.fail"
expect "release: git ls-remote failure is exit 1" 1 "" "git ls-remote failed after 4 attempts" -- \
  "$R" newest release opm-operator --asset install.yaml --current v1.0.0-beta.3
check "release: a failing git ls-remote is tried 4 times, sleeping 2, 4 and 8" \
  bash -c '[ "$(grep -c "^git ls-remote" "$1/git.log")" = 4 ] && [ "$(cat "$1/sleep.log")" = $'"'"'2\n4\n8'"'"' ]' _ "$FX"
new_fx
fx_refs opm-operator v1.0.0-beta.3 v1.0.0-beta.4
rel_ok opm-operator v1.0.0-beta.4 install.yaml
echo 1 >"$FX/git/opm-operator.refs.fail"
expect "release: one failed git ls-remote is retried" 0 v1.0.0-beta.4 "retrying in 2s" -- \
  "$R" newest release opm-operator --asset install.yaml --current v1.0.0-beta.3
check "release: the retry slept 2s once" bash -c '[ "$(cat "$1/sleep.log")" = 2 ]' _ "$FX"

# git ls-remote is isolated from the caller: run from inside a checkout whose
# local, global and environment config carry an actions/checkout-style
# AUTHORIZATION extraheader and a credential helper, with GIT_DIR pointing
# at it and no GIT_TERMINAL_PROMPT.
new_fx
fx_refs opm-operator v1.0.0-beta.3 v1.0.0-beta.4
rel_ok opm-operator v1.0.0-beta.4 install.yaml
CK="$FX/checkout"
git -c init.defaultBranch=main init -q "$CK"
git -C "$CK" config http.https://github.com/.extraheader "AUTHORIZATION: basic bG9jYWwtc2VjcmV0"
git -C "$CK" config credential.helper store
printf '[http]\n\textraheader = AUTHORIZATION: basic Z2xvYmFsLXNlY3JldA==\n[credential]\n\thelper = cache\n' >"$FX/gitconfig"
expect "release: ls-remote from inside a credentialed checkout still answers" 0 v1.0.0-beta.4 -- \
  env -u GIT_TERMINAL_PROMPT GIT_DIR="$CK/.git" GIT_CONFIG_GLOBAL="$FX/gitconfig" \
  GIT_CONFIG_PARAMETERS="'http.extraheader'='AUTHORIZATION: basic cGFyYW0tc2VjcmV0'" \
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=osxkeychain \
  bash -c 'cd "$1" && "$2" newest release opm-operator --asset install.yaml --current v1.0.0-beta.3' _ "$CK" "$R"
check "release: ls-remote sees no extraheader and no credential helper" \
  bash -c 'test -f "$1/git.config" && ! grep -v -x "credential.helper " "$1/git.config"' _ "$FX"
check "release: ls-remote never prompts and reads no caller config" grep -qxF \
  "GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_PARAMETERS=unset GIT_CONFIG_COUNT=unset GIT_ASKPASS=unset GIT_DIR=unset" "$FX/git.env"
check "release: ls-remote runs outside the caller's checkout with no credential helper" \
  bash -c 'o=$(cat "$1/git.opts"); [[ $o == "opts=-C "* && $o != *"$2"* && $o == *" -c credential.helper= "* ]]' _ "$FX" "$CK"
check "release: ls-remote aborts a transfer stalled for 60 seconds" \
  bash -c 'o=$(cat "$1/git.opts"); [[ $o == *" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60" ]]' _ "$FX"

# --- holds --------------------------------------------------------------------------
new_fx
fx_body "$PROXY/$LIB/@v/list" "$FIXTURES/goproxy/library.list"
fx_goinfo "$LIB" v1.0.0-beta.2 v1.0.0-beta.3
cat >"$FX/root/.cascade-hold" <<'EOF'
holds:
  - pin: github.com/open-platform-model/library
    max: v1.0.0-beta.2
    reason: "beta.3 breaks the operator build"
    expires: 2026-10-10
EOF
expect "hold caps the target" 0 v1.0.0-beta.2 \
  "held at \`v1.0.0-beta.2\` until \`2026-10-10\`: beta.3 breaks the operator build" -- \
  "$R" newest go "$LIB" --current v1.0.0-beta.1 --repo-root "$FX/root"
expect "expired hold moves again" 0 v1.0.0-beta.3 "expired \`2026-10-10\`; moving again" -- \
  env CASCADE_TODAY=2026-10-11 "$R" newest go "$LIB" --current v1.0.0-beta.1 --repo-root "$FX/root"
expect "hold below current never moves down" 3 "" \
  "hold \`max\` \`v1.0.0-beta.2\` is below the current pin \`v1.0.0-beta.3\`" -- \
  "$R" newest go "$LIB" --current v1.0.0-beta.3 --repo-root "$FX/root"
expect "hold at the current pin is exit 3" 3 "" -- "$R" newest go "$LIB" --current v1.0.0-beta.2 --repo-root "$FX/root"
run "$R" newest go "$LIB" --current v1.0.0-beta.1 --repo-root "$FX/root" --json
check "--json carries the hold" bash -c '
  [ "$(jq -r ".hold.max, .hold.expires, .target, .newest, .moved" <<<"$1" | tr "\n" " ")" = "v1.0.0-beta.2 2026-10-10 v1.0.0-beta.2 v1.0.0-beta.3 true " ]' _ "$OUT"
printf 'holds:\n  - {pin: k, max: v1.0.0, reason: r, expires: 2026-12-01}\n  - {pin: k, max: v1.0.0, reason: r, expires: 2026-12-01}\n' >"$FX/root/.cascade-hold"
: >"$FX/curl.log"
expect "a malformed hold file stops newest" 1 "" "more than one hold" -- "$R" newest go "$LIB" --current v1.0.0-beta.1 --repo-root "$FX/root"
check "a malformed hold file stops newest before any request" test ! -s "$FX/curl.log"

# --- --expect -----------------------------------------------------------------------
new_fx
fx_body "$PROXY/$LIB/@v/list" "$FIXTURES/goproxy/library.list"
fx_goinfo "$LIB" v1.0.0-beta.3
u="$PROXY/$LIB/@v/v1.0.0-beta.4.info"
fx_text "$u" '{"Version":"v1.0.0-beta.4"}'
fx_status "$u" 404 404 200
expect "--expect absent from the list, published on the third poll" 0 v1.0.0-beta.4 -- \
  "$R" newest go "$LIB" --current v1.0.0-beta.1 --expect v1.0.0-beta.4
check "--expect polled three times" test "$(grep -c "@v/v1.0.0-beta.4.info" "$FX/curl.log")" = 3
check "--expect slept 30s twice" test "$(tr '\n' ' ' <"$FX/sleep.log")" = "30 30 "

new_fx
fx_body "$PROXY/$LIB/@v/list" "$FIXTURES/goproxy/library.list"
fx_goinfo "$LIB" v1.0.0-beta.3
expect "--expect that never appears: warning and the published answer" 0 v1.0.0-beta.3 \
  "expected \`v1.0.0-beta.4\` is not published after \`90\`s" -- \
  "$R" newest go "$LIB" --current v1.0.0-beta.1 --expect v1.0.0-beta.4 --max-wait 90
check "--expect waited from requested sleeps only" test "$(tr '\n' ' ' <"$FX/sleep.log")" = "30 30 30 "
: >"$FX/sleep.log"
expect "--expect: CASCADE_MAX_WAIT is the default budget" 0 v1.0.0-beta.3 "after \`45\`s" -- \
  env CASCADE_MAX_WAIT=45 "$R" newest go "$LIB" --current v1.0.0-beta.1 --expect v1.0.0-beta.4
check "--expect: a partial last step" test "$(tr '\n' ' ' <"$FX/sleep.log")" = "30 15 "
: >"$FX/sleep.log"
run "$R" newest go "$LIB" --current v1.0.0-beta.1 --expect v1.0.0-beta.4
check "--expect: the default budget is 600s" test "$(awk '{s += $1} END {print s}' "$FX/sleep.log")" = 600
: >"$FX/sleep.log"
expect "--expect already published: no wait" 0 v1.0.0-beta.3 -- "$R" newest go "$LIB" --current v1.0.0-beta.1 --expect v1.0.0-beta.3
check "--expect already published: no sleep" test ! -s "$FX/sleep.log"
expect "--expect below the newest is never the answer" 0 v1.0.0-beta.3 -- \
  bash -c 'printf "%s\n" "{}" >"$1/http/proxy.golang.org/$2/@v/v1.0.0-beta.2.info"; "$3" newest go "$2" --current v1.0.0-beta.1 --expect v1.0.0-beta.2' _ "$FX" "$LIB" "$R"
cat >"$FX/root/.cascade-hold" <<'EOF'
holds:
  - {pin: github.com/open-platform-model/library, max: v1.0.0-beta.3, reason: r, expires: 2026-12-01}
EOF
: >"$FX/sleep.log"
expect "--expect above a hold is ignored" 0 v1.0.0-beta.3 "ignoring --expect \`v1.0.0-beta.4\`: it is above the hold" -- \
  "$R" newest go "$LIB" --current v1.0.0-beta.1 --expect v1.0.0-beta.4 --repo-root "$FX/root"
check "--expect above a hold: no wait" test ! -s "$FX/sleep.log"
expect "--expect garbage is ignored, named safely" 0 v1.0.0-beta.3 "ignoring --expect \`??octocat\`" -- \
  "$R" newest go "$LIB" --current v1.0.0-beta.1 --expect ' @octocat'

new_fx
fx_ghcr_file "$OPM_REPO" "$OPM_TAGS" v4.6.0-rc.1
fx_published_cue "$OPM_REPO" v4.5.1
expect "--expect prerelease against a stable pin is ignored" 0 v4.5.1 "is a prerelease and the pin is stable" -- \
  "$R" newest cue opmodel.dev/catalogs/opm@v4 --current v4.4.4 --expect v4.6.0-rc.1
check "--expect ignored: no sleep" test ! -s "$FX/sleep.log"

# --- --json and usage ---------------------------------------------------------------
new_fx
fx_ghcr_file "$CORE_REPO" "$CORE_TAGS"
fx_published_cue "$CORE_REPO" v2.0.0-beta.2
run "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1 --json
check "--json shape" bash -c '
  [ "$(jq -c "." <<<"$1")" = "{\"pin\":\"opmodel.dev/core@v2\",\"kind\":\"cue\",\"current\":\"v2.0.0-beta.1\",\"newest\":\"v2.0.0-beta.2\",\"target\":\"v2.0.0-beta.2\",\"moved\":true,\"hold\":null,\"newer_major\":null,\"warnings\":[]}" ]' _ "$OUT"
run "$R" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.2 --json
check "--json when nothing moves: exit 3, moved false, target is current" bash -c '
  [ "$2" = 3 ] && [ "$(jq -r ".moved, .target, .newest" <<<"$1" | tr "\n" " ")" = "false v2.0.0-beta.2 null " ]' _ "$OUT" "$RC"

expect "usage: --current required" 2 "" -- "$R" newest cue opmodel.dev/core@v2
expect "usage: cue @vN must match --current" 2 "" -- "$R" newest cue opmodel.dev/core@v2 --current v1.0.0
expect "usage: malformed --current" 2 "" -- "$R" newest cue opmodel.dev/core@v2 --current 2.0.0
expect "usage: oci is published-only" 2 "" -- "$R" newest oci open-platform-model/docs/library --current v1.0.0
expect "usage: bad --max-wait" 2 "" -- "$R" newest go "$LIB" --current v1.0.0-beta.1 --max-wait soon
expect "usage: extra positional" 2 "" -- "$R" newest go "$LIB" v1.0.0 --current v1.0.0-beta.1

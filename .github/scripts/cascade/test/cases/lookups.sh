# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# published, pin-of, language-of, the HTTP retry rules and what every request
# looks like. Fixtures under test/fixtures/ were captured read-only from
# ghcr.io, proxy.golang.org and github.com on 2026-10-04.

CORE_REPO=open-platform-model/opmodel.dev/core
OPM_REPO=open-platform-model/opmodel.dev/catalogs/opm
LIB=github.com/open-platform-model/library

# fx_modulefile <repo> <v> <module.cue file>: manifest plus modulefile blob.
fx_modulefile() {
  local repo="$1" v="$2" f="$3" d
  d="sha256:$(sha256sum "$f" | cut -d' ' -f1)"
  fx_text "$(ghcr_token_url "$repo")" '{"token":"dummy-ghcr-token"}'
  fx_text "$(ghcr_manifest_url "$repo" "$v")" \
    "{\"schemaVersion\":2,\"layers\":[{\"mediaType\":\"application/zip\",\"digest\":\"sha256:$(printf '%064d' 1)\"},{\"mediaType\":\"application/vnd.cue.modulefile.v1\",\"digest\":\"$d\"}]}"
  fx_body "$GHCR/v2/$repo/blobs/$d" "$f"
}

# --- published -------------------------------------------------------------
new_fx
fx_text "$(ghcr_token_url "$CORE_REPO")" '{"token":"dummy-ghcr-token"}'
fx_status "$(ghcr_manifest_url "$CORE_REPO" v2.0.0-beta.2)" 200
expect "published cue: manifest 200" 0 "" -- "$R" published cue opmodel.dev/core@v2 v2.0.0-beta.2
expect "published cue: manifest 404" 3 "" -- "$R" published cue opmodel.dev/core@v2 v2.0.0-beta.9
check "published cue sends the OCI manifest Accept type" \
  grep -qF -- "-H Accept: application/vnd.oci.image.manifest.v1+json $(ghcr_manifest_url "$CORE_REPO" v2.0.0-beta.2)" "$FX/curl.log"
check "published cue is a HEAD" grep -qF -- "-I -H Authorization: Bearer dummy-ghcr-token" "$FX/curl.log"

new_fx
fx_status "$(ghcr_token_url open-platform-model/opmodel.dev/private)" 403
expect "published cue: token 403 is 3 with a warning" 3 "" "may be private" -- "$R" published cue opmodel.dev/private@v1 v1.0.0
new_fx
fx_status "$(ghcr_token_url open-platform-model/opmodel.dev/nothere)" 404
expect "published cue: token 404 is 3 with a warning" 3 "" "may be private" -- "$R" published cue opmodel.dev/nothere@v1 v1.0.0

new_fx
fx_text "$(ghcr_token_url open-platform-model/docs/library)" '{"token":"dummy-ghcr-token"}'
fx_status "$(ghcr_manifest_url open-platform-model/docs/library 1.0.0-beta.3)" 200
expect "published oci: tag used as given" 0 "" -- "$R" published oci open-platform-model/docs/library 1.0.0-beta.3
check "published oci asks for the bare tag" grep -qF "/manifests/1.0.0-beta.3" "$FX/curl.log"
check "published oci sends both Accept types" \
  grep -qF -- "-H Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json" "$FX/curl.log"
expect "published oci: the v-prefixed tag is another tag" 3 "" -- "$R" published oci open-platform-model/docs/library v1.0.0-beta.3
expect "published oci: malformed tag" 2 "" -- "$R" published oci open-platform-model/docs/library 'a b'

new_fx
fx_body "$PROXY/$LIB/@v/v1.0.0-beta.3.info" "$FIXTURES/goproxy/library-v1.0.0-beta.3.info"
fx_status "$PROXY/$LIB/@v/v1.0.0-beta.4.info" 410
expect "published go: info 200" 0 "" -- "$R" published go "$LIB" v1.0.0-beta.3
expect "published go: info 404" 3 "" -- "$R" published go "$LIB" v1.0.0-beta.9
expect "published go: info 410" 3 "" -- "$R" published go "$LIB" v1.0.0-beta.4
expect "published go: CASCADE_GOPROXY is the base" 0 "" -- \
  env CASCADE_GOPROXY=https://proxy.example.invalid/ bash -c 'mkdir -p "$1/http/proxy.example.invalid/$2/@v" && : >"$1/http/proxy.example.invalid/$2/@v/v1.0.0.info" && "$3" published go "$2" v1.0.0' _ "$FX" "$LIB" "$R"

new_fx
rel_ok opm-operator v1.0.0-beta.4 install.yaml
fx_status "$(rel_url opm-operator v1.0.0-beta.5 install.yaml)" 404
expect "published release: asset 200" 0 "" -- "$R" published release opm-operator v1.0.0-beta.4 --asset install.yaml
expect "published release: draft answers 404" 3 "" "not downloadable" -- "$R" published release opm-operator v1.0.0-beta.5 --asset install.yaml
check "release probes are HEAD -L" grep -qF -- "-I -L $(rel_url opm-operator v1.0.0-beta.4 install.yaml)" "$FX/curl.log"
rel_ok cli v1.0.0-beta.7 opm-linux-amd64.tar.gz checksums.txt
rel_ok cli v1.0.0-beta.6 opm-linux-amd64.tar.gz
fx_status "$(rel_url cli v1.0.0-beta.6 checksums.txt)" 404
expect "published opm-cli: both assets" 0 "" -- "$R" published opm-cli v1.0.0-beta.7
expect "published opm-cli: missing second asset" 3 "" "checksums.txt" -- "$R" published opm-cli v1.0.0-beta.6
expect "published: unknown kind" 2 "" -- "$R" published npm x v1.0.0
expect "published: --asset on a cue query" 2 "" -- "$R" published cue opmodel.dev/core@v2 v2.0.0 --asset x
expect "published: release without --asset" 2 "" -- "$R" published release cli v1.0.0
expect "published: missing version" 2 "" -- "$R" published go "$LIB"
expect "published: malformed version" 2 "" -- "$R" published go "$LIB" 1.0.0

# --- retries and status mapping -------------------------------------------
new_fx
u="$PROXY/$LIB/@v/v1.0.0-beta.3.info"
fx_text "$u" '{}'
fx_status "$u" 503 200
expect "5xx then 200 recovers" 0 "" -- "$R" published go "$LIB" v1.0.0-beta.3
check "one sleep of 2s before the retry" test "$(cat "$FX/sleep.log")" = 2
new_fx
fx_status "$u" 503
expect "four 5xx give exit 1" 1 "" "after 4 attempts" -- "$R" published go "$LIB" v1.0.0-beta.3
check "sleeps 2, 4 and 8 between four attempts" test "$(tr '\n' ' ' <"$FX/sleep.log")" = "2 4 8 "
check "exactly four attempts" test "$(grep -c "$LIB/@v/v1.0.0-beta.3.info" "$FX/curl.log")" = 4
new_fx
fx_text "$u" '{}'
fx_status "$u" 429 200
expect "429 is retried" 0 "" -- "$R" published go "$LIB" v1.0.0-beta.3
new_fx
fx_text "$u" '{}'
fx_status "$u" 000 200
expect "no answer (000) is retried" 0 "" -- "$R" published go "$LIB" v1.0.0-beta.3
new_fx
fx_status "$u" 401
expect "an unexpected status is exit 1" 1 "" "refusing to guess" -- "$R" published go "$LIB" v1.0.0-beta.3
check "an unexpected status is not retried" test "$(grep -c . "$FX/curl.log")" = 1

# --- pin-of and language-of -------------------------------------------------
new_fx
fx_modulefile "$OPM_REPO" v4.5.1 "$FIXTURES/ghcr/catalogs-opm-v4.5.1.module.cue"
expect "pin-of: core pinned by catalog v4.5.1" 0 v2.0.0-beta.1 -- "$R" pin-of opmodel.dev/catalogs/opm@v4 v4.5.1 opmodel.dev/core@v2
check "pin-of follows the blob redirect with -L" grep -qF -- "-L -H Authorization: Bearer dummy-ghcr-token $GHCR/v2/$OPM_REPO/blobs/sha256:" "$FX/curl.log"
expect "pin-of: dep absent" 3 "" -- "$R" pin-of opmodel.dev/catalogs/opm@v4 v4.5.1 opmodel.dev/schemas@v1
expect "pin-of: third-party dep" 0 v0.12.0 -- "$R" pin-of opmodel.dev/catalogs/opm@v4 v4.5.1 cue.dev/x/k8s.io@v0
expect "language-of: v4.5.1" 0 v0.17.0 -- "$R" language-of opmodel.dev/catalogs/opm@v4 v4.5.1
expect "pin-of: unpublished module version" 1 "" "is not published" -- "$R" pin-of opmodel.dev/catalogs/opm@v4 v4.9.9 opmodel.dev/core@v2
expect "pin-of: malformed dep" 2 "" -- "$R" pin-of opmodel.dev/catalogs/opm@v4 v4.5.1 opmodel.dev/core
expect "pin-of: malformed version" 2 "" -- "$R" pin-of opmodel.dev/catalogs/opm@v4 4.5.1 opmodel.dev/core@v2

cat >"$FX/followed.cue" <<'EOF'
module: "opmodel.dev/templates/minimal@v1"
language: {
	version: "v0.16.0"
}
deps: {
	"opmodel.dev/catalogs/opm@v4": {
		v:       "v4.4.4"
		default: true
	}
	"opmodel.dev/core@v2": {
		v:       "v2.0.0-beta.1"
		default: true
	}
}
EOF
fx_modulefile open-platform-model/opmodel.dev/templates/minimal v1.0.3 "$FX/followed.cue"
expect "pin-of: a dep followed by another dep" 0 v4.4.4 -- "$R" pin-of opmodel.dev/templates/minimal@v1 v1.0.3 opmodel.dev/catalogs/opm@v4
expect "pin-of: the second dep" 0 v2.0.0-beta.1 -- "$R" pin-of opmodel.dev/templates/minimal@v1 v1.0.3 opmodel.dev/core@v2
expect "language-of: v0.16.0" 0 v0.16.0 -- "$R" language-of opmodel.dev/templates/minimal@v1 v1.0.3

printf 'module: "opmodel.dev/x@v1"\ndeps: {\n\t"opmodel.dev/core@v2": {v: "v2.0.0-beta.1"}\n\t"opmodel.dev/core@v2": {v: "v2.0.0-beta.2"}\n}\n' >"$FX/twice.cue"
fx_modulefile open-platform-model/opmodel.dev/x v1.0.0 "$FX/twice.cue"
expect "pin-of: a repeated dep key is exit 1" 1 "" "more than once" -- "$R" pin-of opmodel.dev/x@v1 v1.0.0 opmodel.dev/core@v2
expect "language-of: no language block" 3 "" -- "$R" language-of opmodel.dev/x@v1 v1.0.0
printf 'module: "opmodel.dev/y@v1"\ndeps: {\n\t"opmodel.dev/core@v2": {default: true}\n\t"opmodel.dev/other@v1": {v: "v1.0.0"}\n}\n' >"$FX/nov.cue"
fx_modulefile open-platform-model/opmodel.dev/y v1.0.0 "$FX/nov.cue"
expect "pin-of: never reads the next dep's v" 1 "" "has no" -- "$R" pin-of opmodel.dev/y@v1 v1.0.0 opmodel.dev/core@v2

new_fx
fx_text "$(ghcr_token_url "$OPM_REPO")" '{"token":"dummy-ghcr-token"}'
fx_text "$(ghcr_manifest_url "$OPM_REPO" v4.5.1)" '{"schemaVersion":2,"layers":[{"mediaType":"application/zip","digest":"sha256:0"}]}'
expect "pin-of: manifest without a module file layer" 1 "" "no module file layer" -- "$R" pin-of opmodel.dev/catalogs/opm@v4 v4.5.1 opmodel.dev/core@v2

# --- what every request looks like -----------------------------------------
all_logs="$T_ROOT/all-curl.log"
cat "$T_ROOT"/fx*/curl.log >"$all_logs"
check "requests were made" test -s "$all_logs"
check "curl always gets -q first" bash -c '! grep -v "^-q -sS --connect-timeout 10 --max-time 60 -o " "$1"' _ "$all_logs"
check "no request goes to api.github.com" bash -c '! grep -q "api\.github\.com" "$1"' _ "$all_logs"
check "no request carries GITHUB_TOKEN or GH_TOKEN" bash -c '! grep -qF -e "$2" -e "$3" "$1"' _ "$all_logs" "$GITHUB_TOKEN" "$GH_TOKEN"
run "$T_HERE/shim/curl" -s https://ghcr.io/
check "the curl shim exits 2 on another shape" test "$RC" = 2

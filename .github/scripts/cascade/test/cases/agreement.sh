# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# The stub and the real resolver agree on exit code and stdout for every case
# the stub supports. The repos test against the stub, so a disagreement here
# means their tests prove something the real resolver does not do.
#
# Left out on purpose: prerelease identifiers mixing numeric and alphanumeric
# forms (the stub sorts with sort -V), duplicate holds (the stub takes the
# first), holds inside newest (the stub has none), warning text, malformed
# arguments (a --repo-root that is not a directory among them) and steering
# files, next-patch of a prerelease, and check-files
# on an invalid file.

CORE_REPO=open-platform-model/opmodel.dev/core
OPM_REPO=open-platform-model/opmodel.dev/catalogs/opm
LIB=github.com/open-platform-model/library

new_fx
# Real side: fixtures.
fx_text "$(ghcr_token_url "$CORE_REPO")" '{"token":"dummy-ghcr-token"}'
fx_body "$(ghcr_tags_url "$CORE_REPO")" "$FIXTURES/ghcr/core.tags.json"
fx_published_cue "$CORE_REPO" v2.0.0-beta.2
fx_text "$(ghcr_token_url "$OPM_REPO")" '{"token":"dummy-ghcr-token"}'
fx_body "$(ghcr_tags_url "$OPM_REPO")" "$FIXTURES/ghcr/catalogs-opm.tags.json"
fx_published_cue "$OPM_REPO" v4.5.1
d="sha256:$(sha256sum "$FIXTURES/ghcr/catalogs-opm-v4.5.1.module.cue" | cut -d' ' -f1)"
fx_text "$(ghcr_manifest_url "$OPM_REPO" v4.5.1)" \
  "{\"layers\":[{\"mediaType\":\"application/vnd.cue.modulefile.v1\",\"digest\":\"$d\"}]}"
fx_body "$GHCR/v2/$OPM_REPO/blobs/$d" "$FIXTURES/ghcr/catalogs-opm-v4.5.1.module.cue"
fx_body "$PROXY/$LIB/@v/list" "$FIXTURES/goproxy/library.list"
fx_body "$PROXY/$LIB/@v/v1.0.0-beta.3.info" "$FIXTURES/goproxy/library-v1.0.0-beta.3.info"
fx_refs_file cli "$FIXTURES/git/cli.refs"
rel_ok cli v1.0.0-beta.7 opm-linux-amd64.tar.gz checksums.txt
fx_refs_file opm-operator "$FIXTURES/git/opm-operator.refs"
rel_ok opm-operator v1.0.0-beta.5 install.yaml
fx_text "$(ghcr_token_url open-platform-model/docs/library)" '{"token":"dummy-ghcr-token"}'
fx_status "$(ghcr_manifest_url open-platform-model/docs/library 1.0.0-beta.3)" 200

# Stub side: the same facts as a table.
export CASCADE_STUB_TABLE="$FX/stub.tsv"
cat >"$CASCADE_STUB_TABLE" <<'EOF'
newest	cue	opmodel.dev/core@v2	v2.0.0-beta.2
newest	cue	opmodel.dev/catalogs/opm@v4	v4.5.1
newest	go	github.com/open-platform-model/library	v1.0.0-beta.3
newest	opm-cli	-	v1.0.0-beta.7
newest	release	opm-operator	v1.0.0-beta.5
published	cue	opmodel.dev/core@v2	v2.0.0-beta.2
published	cue	opmodel.dev/catalogs/opm@v4	v4.5.1
published	go	github.com/open-platform-model/library	v1.0.0-beta.3
published	opm-cli	-	v1.0.0-beta.7
published	release	opm-operator	v1.0.0-beta.5
published	oci	open-platform-model/docs/library	1.0.0-beta.3
pin-of	opmodel.dev/catalogs/opm@v4	v4.5.1	opmodel.dev/core@v2	v2.0.0-beta.1
pin-of	opmodel.dev/catalogs/opm@v4	v4.5.1	cue.dev/x/k8s.io@v0	v0.12.0
language-of	opmodel.dev/catalogs/opm@v4	v4.5.1	v0.17.0
EOF

D="$FX/root"
mkdir -p "$FX/empty"
cat >"$D/.cascade-frozen" <<'EOF'
frozen:
  - path: tests/e2e/
    pins: ["opmodel.dev/core@v2"]
    reason: "a directory"
  - path: a/b/cue.mod/module.cue
    pins: ["opmodel.dev/core@v2", "opmodel.dev/catalogs/opm@v4"]
    reason: "a file"
EOF
cat >"$D/.cascade-hold" <<'EOF'
holds:
  - {pin: github.com/open-platform-model/library, max: v1.0.0-beta.2, reason: r, expires: 2026-10-10}
  - {pin: opmodel.dev/core@v2, max: v2.0.0-beta.1, reason: r, expires: 2026-10-02}
EOF

agree() { # agree <name> <args...>
  local name="$1" rout rrc
  shift
  run "$R" "$@"
  rout="$OUT" rrc="$RC"
  run "$STUB" "$@"
  if [ "$rrc" = "$RC" ] && [ "$rout" = "$OUT" ]; then
    pass "agree: $name"
  else
    fail "agree: $name" "resolver exit $rrc stdout '$rout'; stub exit $RC stdout '$OUT'"
  fi
}

agree "newest cue moves" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1 --repo-root "$FX/empty"
agree "newest cue stays" newest cue opmodel.dev/core@v2 --current v2.0.0-beta.2
agree "newest stable catalog" newest cue opmodel.dev/catalogs/opm@v4 --current v4.4.4
agree "newest stable catalog stays" newest cue opmodel.dev/catalogs/opm@v4 --current v4.5.1
agree "newest go" newest go "$LIB" --current v1.0.0-beta.1
agree "newest go stays" newest go "$LIB" --current v1.0.0-beta.3
agree "newest opm-cli" newest opm-cli --current v1.0.0-beta.4
agree "newest release" newest release opm-operator --asset install.yaml --current v1.0.0-beta.3
agree "newest ahead of upstream" newest go "$LIB" --current v1.0.0-rc.1
agree "published cue yes" published cue opmodel.dev/core@v2 v2.0.0-beta.2
agree "published cue no" published cue opmodel.dev/core@v2 v2.0.0-beta.9
agree "published go yes" published go "$LIB" v1.0.0-beta.3
agree "published go no" published go "$LIB" v1.0.0-beta.9
agree "published opm-cli yes" published opm-cli v1.0.0-beta.7
agree "published opm-cli no" published opm-cli v1.0.0-beta.1
agree "published release" published release opm-operator v1.0.0-beta.5 --asset install.yaml
agree "published oci" published oci open-platform-model/docs/library 1.0.0-beta.3
agree "published oci no" published oci open-platform-model/docs/library v1.0.0-beta.3
agree "pin-of core" pin-of opmodel.dev/catalogs/opm@v4 v4.5.1 opmodel.dev/core@v2
agree "pin-of third-party" pin-of opmodel.dev/catalogs/opm@v4 v4.5.1 cue.dev/x/k8s.io@v0
agree "pin-of absent" pin-of opmodel.dev/catalogs/opm@v4 v4.5.1 opmodel.dev/none@v1
agree "language-of" language-of opmodel.dev/catalogs/opm@v4 v4.5.1
agree "check-files" check-files --repo-root "$D"
agree "frozen" frozen opmodel.dev/core@v2 --repo-root "$D"
agree "frozen other key" frozen opmodel.dev/catalogs/opm@v4 --repo-root "$D"
agree "frozen none" frozen example.com/x@v1 --repo-root "$D"
agree "is-frozen file" is-frozen a/b/cue.mod/module.cue opmodel.dev/core@v2 --repo-root "$D"
agree "is-frozen dir prefix" is-frozen tests/e2e/x/cue.mod/module.cue opmodel.dev/core@v2 --repo-root "$D"
agree "is-frozen parent of a file entry" is-frozen a/b opmodel.dev/core@v2 --repo-root "$D"
agree "is-frozen other key" is-frozen tests/e2e/x opmodel.dev/catalogs/opm@v4 --repo-root "$D"
agree "is-frozen no file" is-frozen x opmodel.dev/core@v2 --repo-root "$FX/empty"
agree "hold in date" hold github.com/open-platform-model/library --repo-root "$D"
agree "hold expired" hold opmodel.dev/core@v2 --repo-root "$D"
agree "hold none" hold opmodel.dev/catalogs/opm@v4 --repo-root "$D"
agree "hold no file" hold opmodel.dev/core@v2 --repo-root "$FX/empty"
for pair in "v2.0.0-alpha.2 v2.0.0-alpha.10" "v2.0.0-beta.10 v2.0.0-beta.2" "v2.0.0 v2.0.0-beta.10" \
  "v2.0.0-rc.1 v2.0.0-beta.9" "v1.0.0+a v1.0.0+b" "v1.10.0 v1.9.0" "v4.5.1 v4.5.1" "v1.0.0-beta v1.0.0-beta.1"; do
  # shellcheck disable=SC2086 # the pair splits into two arguments
  agree "semver-cmp $pair" semver-cmp $pair
done
agree "next-patch" next-patch v1.0.3
agree "next-patch carry" next-patch v0.1.9

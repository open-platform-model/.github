# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# .cascade-frozen and .cascade-hold readers.
new_fx
D="$FX/root"
core=opmodel.dev/core@v2
cat=opmodel.dev/catalogs/opm@v4

cat >"$D/.cascade-frozen" <<'EOF'
frozen:
  - path: tests/e2e/
    pins: ["opmodel.dev/core@v2"]
    reason: "directory with a trailing slash"
  - path: dir
    pins: ["opmodel.dev/core@v2", "opmodel.dev/catalogs/opm@v4"]
    reason: "directory without one"
  - path: a/b/cue.mod/module.cue
    pins: ["opmodel.dev/core@v2"]
    reason: "one file"
EOF
expect "check-files: valid frozen file" 0 "" -- "$R" check-files --repo-root "$D"
expect "frozen lists paths for a key" 0 $'tests/e2e/\ndir\na/b/cue.mod/module.cue' -- "$R" frozen "$core" --repo-root "$D"
expect "frozen lists only matching entries" 0 dir -- "$R" frozen "$cat" --repo-root "$D"
expect "frozen: no entry is still exit 0" 0 "" -- "$R" frozen example.com/x@v1 --repo-root "$D"
expect "is-frozen: exact file" 0 "" -- "$R" is-frozen a/b/cue.mod/module.cue "$core" --repo-root "$D"
expect "is-frozen: directory prefix" 0 "" -- "$R" is-frozen dir/x/cue.mod/module.cue "$core" --repo-root "$D"
expect "is-frozen: trailing slash stripped" 0 "" -- "$R" is-frozen tests/e2e/testdata/x/cue.mod/module.cue "$core" --repo-root "$D"
expect "is-frozen: the directory itself" 0 "" -- "$R" is-frozen tests/e2e "$core" --repo-root "$D"
expect "is-frozen: dir2 not matched by dir" 3 "" -- "$R" is-frozen dir2/cue.mod/module.cue "$core" --repo-root "$D"
expect "is-frozen: file entry does not freeze its parent" 3 "" -- "$R" is-frozen a/b "$core" --repo-root "$D"
expect "is-frozen: other key" 3 "" -- "$R" is-frozen tests/e2e/x "$cat" --repo-root "$D"
expect "is-frozen: --repo-root defaults to the current directory" 0 "" -- bash -c 'cd "$1" && "$2" is-frozen dir/f "$3"' _ "$D" "$R" "$core"

D2="$FX/root2"; mkdir -p "$D2"
expect "missing files are empty" 0 "" -- "$R" check-files --repo-root "$D2"
expect "is-frozen with no file" 3 "" -- "$R" is-frozen a "$core" --repo-root "$D2"
expect "hold with no file" 3 "" -- "$R" hold "$core" --repo-root "$D2"
: >"$D2/.cascade-frozen"
printf 'holds: []\n' >"$D2/.cascade-hold"
expect "empty frozen file and holds: [] are valid" 0 "" -- "$R" check-files --repo-root "$D2"
printf 'frozen: []\n' >"$D2/.cascade-frozen"
: >"$D2/.cascade-hold"
expect "frozen: [] and an empty hold file are valid" 0 "" -- "$R" check-files --repo-root "$D2"

for real in library cli; do
  D3="$FX/real-$real"; mkdir -p "$D3"
  cp "$FIXTURES/frozen/$real.cascade-frozen" "$D3/.cascade-frozen"
  expect "check-files: $real's committed .cascade-frozen" 0 "" -- "$R" check-files --repo-root "$D3"
done
expect "is-frozen on library's real file" 0 "" -- "$R" is-frozen opm/schema/loader_test.go "$core" --repo-root "$FX/real-library"

bad_frozen() { # bad_frozen <name> <stderr substring> <yaml>
  local d="$FX/bad$((++BADN))"
  mkdir -p "$d"
  printf '%s\n' "$3" >"$d/.cascade-frozen"
  expect "malformed frozen: $1" 1 "" "$2" -- "$R" check-files --repo-root "$d"
  expect "malformed frozen fails is-frozen too: $1" 1 "" -- "$R" is-frozen x "$core" --repo-root "$d"
}
BADN=0
bad_frozen "absolute path" "repo-relative" $'frozen:\n  - {path: /x, pins: [k], reason: r}'
bad_frozen "dot-dot path" "must not hold" $'frozen:\n  - {path: a/../b, pins: [k], reason: r}'
bad_frozen "empty pins" "non-empty list" $'frozen:\n  - {path: a, pins: [], reason: r}'
bad_frozen "missing reason" "missing key \`reason\`" $'frozen:\n  - {path: a, pins: [k]}'
bad_frozen "unknown key" "unknown key \`why\`" $'frozen:\n  - {path: a, pins: [k], reason: r, why: w}'
bad_frozen "not a list" "must be a list" $'frozen: {path: a}'
bad_frozen "unknown top-level key" "unknown top-level key" $'frozen: []\nholds: []'
bad_frozen "not YAML" "not valid YAML" $'frozen: [\n'

H="$FX/hold"; mkdir -p "$H"
cat >"$H/.cascade-hold" <<'EOF'
holds:
  - pin: github.com/open-platform-model/library
    max: v1.0.0-beta.2
    reason: "beta.3 breaks the operator build"
    expires: 2026-10-10
  - pin: opmodel.dev/core@v2
    max: v2.0.0-beta.1
    reason: "old"
    expires: 2026-10-02
EOF
expect "hold in date" 0 v1.0.0-beta.2 -- "$R" hold github.com/open-platform-model/library --repo-root "$H"
expect "hold on its expiry day is in date" 0 v1.0.0-beta.2 -- env CASCADE_TODAY=2026-10-10 "$R" hold github.com/open-platform-model/library --repo-root "$H"
expect "hold expired" 3 "" "hold on \`opmodel.dev/core@v2\` expired \`2026-10-02\`; moving again" -- "$R" hold "$core" --repo-root "$H"
expect "no hold for the key" 3 "" -- "$R" hold "$cat" --repo-root "$H"
: >"$FX/w"
run env CASCADE_WARNINGS="$FX/w" "$R" hold "$core" --repo-root "$H"
check "expired-hold warning is keyed by the pin" grep -qxF "$core"$'\t'"hold on \`$core\` expired \`2026-10-02\`; moving again" "$FX/w"
expect "malformed CASCADE_TODAY" 1 "" -- env CASCADE_TODAY=yesterday "$R" hold "$core" --repo-root "$H"

bad_hold() {
  local d="$FX/badh$((++BADN))"
  mkdir -p "$d"
  printf '%s\n' "$3" >"$d/.cascade-hold"
  expect "malformed hold: $1" 1 "" "$2" -- "$R" check-files --repo-root "$d"
  expect "malformed hold fails hold too: $1" 1 "" -- "$R" hold k --repo-root "$d"
}
bad_hold "duplicate pin" "more than one hold for \`k\`" $'holds:\n  - {pin: k, max: v1.0.0, reason: r, expires: 2026-12-01}\n  - {pin: k, max: v1.1.0, reason: r, expires: 2026-12-01}'
bad_hold "missing reason" "entry 1: missing key \`reason\`" $'holds:\n  - {pin: k, max: v1.0.0, expires: 2026-12-01}'
bad_hold "bad expires" "YYYY-MM-DD" $'holds:\n  - {pin: k, max: v1.0.0, reason: r, expires: 2026-13-01}'
bad_hold "bad max" "v-prefixed SemVer" $'holds:\n  - {pin: k, max: 1.0.0, reason: r, expires: 2026-12-01}'
bad_hold "unknown key" "unknown key \`note\`" $'holds:\n  - {pin: k, max: v1.0.0, reason: r, expires: 2026-12-01, note: n}'
bad_hold "empty reason" "non-empty string" $'holds:\n  - {pin: k, max: v1.0.0, reason: "", expires: 2026-12-01}'

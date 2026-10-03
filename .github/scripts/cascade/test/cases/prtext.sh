# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# classify, title and body against throwaway git repos built here.

# --- classify ---------------------------------------------------------------
new_fx
C="$FX/classes"
cat >"$C" <<'EOF'
# a comment line
release-tool .opm-cli-version   # a trailing comment
test testdata/
test test/
test *_test.go

test **/fixtures/
EOF
classify_case() { expect "classify: $1" 0 "$2"$'\t'"$1" -- bash -c 'printf "%s\n" "$1" | "$2" classify --classes "$3"' _ "$1" "$R" "$C"; }
classify_case opm/schema/loader.go shipped
classify_case go.mod shipped
classify_case .opm-cli-version release-tool
classify_case sub/.opm-cli-version shipped
classify_case testdata/render/a/cue.mod/module.cue test
classify_case testdata2/x shipped
classify_case opm/kernel/render_test.go test
classify_case render_test.go test
classify_case internal/instinit/fixtures/initvalues/cue.mod/module.cue test
classify_case fixtures/x test
classify_case afixtures/x shipped
expect "classify: several paths in order" 0 $'shipped\ta\ntest\ttest/b' -- \
  bash -c 'printf "a\ntest/b\n" | "$1" classify --classes "$2"' _ "$R" "$C"
printf 'test testdata/\nrelease-tool testdata/x\n' >"$FX/first"
expect "classify: first matching line wins" 0 $'test\ttestdata/x' -- \
  bash -c 'printf "testdata/x\n" | "$1" classify --classes "$2"' _ "$R" "$FX/first"
printf 'test a/b.yaml\n' >"$FX/exact"
expect "classify: a path pattern matches exactly" 0 $'test\ta/b.yaml\nshipped\ta/b.yaml.bak' -- \
  bash -c 'printf "a/b.yaml\na/b.yaml.bak\n" | "$1" classify --classes "$2"' _ "$R" "$FX/exact"
bad_classes() {
  printf '%s\n' "$2" >"$FX/bad"
  expect "classify: $1" 1 "" "classes line" -- bash -c 'echo x | "$1" classify --classes "$2"' _ "$R" "$FX/bad"
}
bad_classes "a / and * pattern is no known form" "test src/*.cue"
bad_classes "unknown class" "docs README.md"
bad_classes "a line without a pattern" "test"
bad_classes "three fields" "test a b"
bad_classes "an absolute pattern" "test /etc/"
expect "classify: --classes required" 2 "" -- bash -c 'echo x | "$1" classify' _ "$R"

# --- a throwaway repo with a fake pins.sh -------------------------------------
# pins.conf rows: <key> <display> <class> <file> <labels>; the pin's version
# is the first line of <file>, read from the work tree or with git show.
PC="$FX/pins.conf"
cat >"$PC" <<'EOF'
opmodel.dev/core@v2	core	shipped	src/core.version	need-human-review
github.com/open-platform-model/cli	opm CLI	release-tool	.opm-cli-version
opmodel.dev/catalogs/opm@v4	opm catalog	test	testdata/catalog.version
github.com/open-platform-model/library	library	test	test/library.version	a,need-human-review, b
example.com/new@v1	new pin	shipped	src/new.version
EOF
PINS_SH="$FX/pins.sh"
cat >"$PINS_SH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ref="${1:?ref}"
[ -z "${PINS_FAIL:-}" ] || { echo "pins: told to fail" >&2; exit 1; }
while IFS=$'\t' read -r key display class file labels; do
  if [ "$ref" = WORKTREE ]; then
    [ -f "$file" ] || continue
    v=$(head -n 1 "$file")
  else
    v=$(git show "$ref:$file" 2>/dev/null | head -n 1) || true
    [ -n "$v" ] || continue
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$key" "${PINS_DISPLAY:-$display}" "$class" "$v" "$labels"
done <"$PINS_CONF"
EOF
chmod +x "$PINS_SH"
export PINS_CONF="$PC"

new_repo
mkdir -p "$REPO/src" "$REPO/testdata" "$REPO/test"
echo v2.0.0-beta.1 >"$REPO/src/core.version"
echo v1.0.0-beta.4 >"$REPO/.opm-cli-version"
echo v4.4.4 >"$REPO/testdata/catalog.version"
echo v1.0.0-beta.1 >"$REPO/test/library.version"
printf '*.log\n' >"$REPO/.gitignore"
commit_all base
BASE_SHA=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" update-ref refs/remotes/origin/main "$BASE_SHA"

reset_repo() { git -C "$REPO" reset -q --hard "$BASE_SHA" && git -C "$REPO" clean -fdxq; }
T() { (cd "$REPO" && "$R" title --classes "$C" --pins "$PINS_SH" "$@"); }
B() { (cd "$REPO" && "$R" body --classes "$C" --pins "$PINS_SH" "$@"); }

expect "title: empty diff is exit 3" 3 "" -- T
run B
check "body: empty diff still exits 0 with an empty title marker" \
  bash -c '[ "$1" = 0 ] && [ "$(head -n 1 <<<"$2")" = "<!-- cascade-title:  -->" ]' _ "$RC" "$OUT"
check "body: no moved pin gives the none row" bash -c '[[ $1 == *"| none | - | - | - |"* ]]' _ "$OUT"

echo v2.0.0-beta.2 >"$REPO/src/core.version"
expect "title: one shipped pin" 0 "fix(deps): bump core to v2.0.0-beta.2" -- T
echo v1.0.0-beta.4 >"$REPO/.opm-cli-version"
touch "$REPO/.opm-cli-version"
echo v1.0.0-beta.7 >"$REPO/.opm-cli-version"
expect "title: two pins" 0 "fix(deps): bump core to v2.0.0-beta.2 and opm CLI to v1.0.0-beta.7" -- T
echo v4.5.1 >"$REPO/testdata/catalog.version"
expect "title: three pins" 0 "fix(deps): bump core to v2.0.0-beta.2, opm CLI to v1.0.0-beta.7 and opm catalog to v4.5.1" -- T
echo v1.0.0-beta.3 >"$REPO/test/library.version"
expect "title: four pins" 0 "fix(deps): bump 4 upstream pins" -- T
run B
check "body: labels are the first-seen union" \
  bash -c '[ "$(sed -n 2p <<<"$1")" = "<!-- cascade-labels: need-human-review,a,b -->" ]' _ "$OUT"
check "body: one row per moved pin, in pins.sh order" bash -c '
  [ "$(grep -c "^| .* (\`" <<<"$1")" = 4 ] &&
  [ "$(grep "^| " <<<"$1" | sed -n 3p)" = "| core (\`opmodel.dev/core@v2\`) | shipped | \`v2.0.0-beta.1\` | \`v2.0.0-beta.2\` |" ]' _ "$OUT"
check "body: changed-file counts" bash -c '[[ $1 == *"Changed files: 1 shipped, 2 test, 1 release-tool."* ]]' _ "$OUT"
check "body: Notes is the last section" bash -c '[ "$(tail -n 1 <<<"$1")" = "<!-- cascade-notes: the bot keeps everything below this line -->" ] && [ "$(grep "^## " <<<"$1" | tail -n 1)" = "## Notes" ]' _ "$OUT"

reset_repo
echo v1.0.0-beta.7 >"$REPO/.opm-cli-version"
expect "title: release tool only" 0 "ci(deps): bump opm CLI to v1.0.0-beta.7" -- T
reset_repo
echo v4.5.1 >"$REPO/testdata/catalog.version"
expect "title: test only" 0 "test(fixtures): bump opm catalog to v4.5.1" -- T
echo v1.0.0-beta.7 >"$REPO/.opm-cli-version"
expect "title: test beats release-tool" 0 "test(fixtures): bump opm CLI to v1.0.0-beta.7 and opm catalog to v4.5.1" -- \
  bash -c 'cd "$1" && "$2" title --classes "$3" --pins "$4"' _ "$REPO" "$R" "$C" "$PINS_SH"
reset_repo
echo "notes" >"$REPO/src/README"
expect "title: an untracked file counts and no pin moved" 0 "fix(deps): refresh cascade-managed files" -- T
reset_repo
echo "noise" >"$REPO/src/build.log"
expect "title: an ignored file does not count" 3 "" -- T
reset_repo
echo v1.0.0 >"$REPO/src/new.version"
expect "title: a pin missing at the base is not moved" 0 "fix(deps): refresh cascade-managed files" -- T
reset_repo
echo v2.0.0-beta.2 >"$REPO/src/core.version"
git -C "$REPO" commit -qam "a committed bump"
expect "title: committed changes after the merge-base count" 0 "fix(deps): bump core to v2.0.0-beta.2" -- T
expect "title: --base wins" 3 "" -- T --base HEAD
expect "title: CASCADE_BASE when no --base" 3 "" -- env CASCADE_BASE=HEAD bash -c 'cd "$1" && "$2" title --classes "$3" --pins "$4"' _ "$REPO" "$R" "$C" "$PINS_SH"
expect "title: a base starting with - is a usage error" 2 "" -- T --base --oops
reset_repo
git -C "$REPO" mv testdata/catalog.version src/catalog.version
expect "title: a rename counts both paths" 0 "fix(deps): refresh cascade-managed files" -- T
run B
check "body: a rename counts both paths" bash -c '[[ $1 == *"Changed files: 1 shipped, 1 test, 0 release-tool."* ]]' _ "$OUT"
reset_repo
echo v2.0.0-beta.2 >"$REPO/src/core.version"
expect "title: a failing pins script is exit 1" 1 "" -- env PINS_FAIL=1 bash -c 'cd "$1" && "$2" title --classes "$3" --pins "$4"' _ "$REPO" "$R" "$C" "$PINS_SH"
expect "title: a bare mention in a display name fails the lint" 1 "" "mention lint: title line 1" -- \
  env PINS_DISPLAY='core for @octocat' bash -c 'cd "$1" && "$2" title --classes "$3" --pins "$4"' _ "$REPO" "$R" "$C" "$PINS_SH"
expect "title: --repo-root" 0 "fix(deps): bump core to v2.0.0-beta.2" -- \
  "$R" title --classes "$C" --pins "$PINS_SH" --repo-root "$REPO"
expect "title: --pins is required" 2 "" -- bash -c 'cd "$1" && "$2" title --classes "$3"' _ "$REPO" "$R" "$C"

# --- body: the exact layout ------------------------------------------------------
reset_repo
echo v2.0.0-beta.2 >"$REPO/src/core.version"
echo v1.0.0-beta.7 >"$REPO/.opm-cli-version"
W="$FX/warnings"
printf '%s\t%s\n' opmodel.dev/core@v2 'new major available: `v3.0.0-alpha.1` (prerelease)' \
  opmodel.dev/core@v2 'new major available: `v3.0.0-alpha.1` (prerelease)' >"$W"
printf -- '-\tdocs note\nno tab here\n' >>"$W"
printf 'keep me\n' >"$FX/notes"
cat >"$FX/golden" <<'EOF'
<!-- cascade-title: fix(deps): bump core to v2.0.0-beta.2 and opm CLI to v1.0.0-beta.7 -->
<!-- cascade-labels: need-human-review -->
## Moved pins

| Pin | Class | From | To |
| --- | --- | --- | --- |
| core (`opmodel.dev/core@v2`) | shipped | `v2.0.0-beta.1` | `v2.0.0-beta.2` |
| opm CLI (`github.com/open-platform-model/cli`) | release-tool | `v1.0.0-beta.4` | `v1.0.0-beta.7` |

Changed files: 1 shipped, 0 test, 1 release-tool.

## Triggering releases

- `core` `v2.0.0-beta.2`

## Warnings

- `opmodel.dev/core@v2`: new major available: `v3.0.0-alpha.1` (prerelease)
- docs note
- no tab here

## Notes

<!-- cascade-notes: the bot keeps everything below this line -->
keep me
EOF
golden_env=(env CASCADE_SOURCE=core CASCADE_TAGS=v2.0.0-beta.2 CASCADE_NOTES_FILE="$FX/notes")
run "${golden_env[@]}" bash -c 'cd "$1" && "$2" body --classes "$3" --pins "$4" --warnings "$5"' _ "$REPO" "$R" "$C" "$PINS_SH" "$W"
printf '%s\n' "$OUT" >"$FX/got1"
check "body: byte-exact layout" cmp -s "$FX/golden" "$FX/got1"
[ "$RC" = 0 ] || fail "body: golden run" "exit $RC: $ERR"
"${golden_env[@]}" bash -c 'cd "$1" && "$2" body --classes "$3" --pins "$4" --warnings "$5"' _ "$REPO" "$R" "$C" "$PINS_SH" "$W" >"$FX/run1" 2>/dev/null
"${golden_env[@]}" bash -c 'cd "$1" && "$2" body --classes "$3" --pins "$4" --warnings "$5"' _ "$REPO" "$R" "$C" "$PINS_SH" "$W" >"$FX/run2" 2>/dev/null
check "body: two runs give the same bytes" cmp -s "$FX/run1" "$FX/run2"

mkdir -p "$REPO/.git/cascade"
printf -- '-\tfrom the default file\n' >"$REPO/.git/cascade/warnings"
run B
check "body: warnings default to <git-dir>/cascade/warnings" bash -c '[[ $1 == *"- from the default file"* ]]' _ "$OUT"
rm "$REPO/.git/cascade/warnings"
run B
check "body: no warnings renders - None." bash -c '[[ $1 == *$'"'"'## Warnings\n\n- None.\n'"'"'* ]]' _ "$OUT"
check "body: no source renders None recorded" bash -c '[[ $1 == *"- None recorded (daily sweep or manual run)."* ]]' _ "$OUT"
expect "body: a missing --warnings file is exit 1" 1 "" -- B --warnings "$FX/nope"

run env CASCADE_SOURCE=core CASCADE_TAGS='v1.0.0 $(id)' bash -c 'cd "$1" && "$2" body --classes "$3" --pins "$4"' _ "$REPO" "$R" "$C" "$PINS_SH"
check "body: hostile tag dropped, the valid one kept" bash -c '
  [ "$2" = 0 ] && [[ $1 == *$'"'"'## Triggering releases\n\n- `core` `v1.0.0`\n\n'"'"'* ]] && [[ $1 == *"- dropped triggering tag \`??id?\`"* ]]' _ "$OUT" "$RC"
run env CASCADE_SOURCE=evil CASCADE_TAGS=v1.0.0 bash -c 'cd "$1" && "$2" body --classes "$3" --pins "$4"' _ "$REPO" "$R" "$C" "$PINS_SH"
check "body: unknown source dropped with its tags" bash -c '
  [ "$2" = 0 ] && [[ $1 == *"- None recorded (daily sweep or manual run)."* ]] && [[ $1 == *"dropped triggering source \`evil\`"* ]]' _ "$OUT" "$RC"
run env CASCADE_SOURCE='@octocat' CASCADE_TAGS='@octocat' bash -c 'cd "$1" && "$2" body --classes "$3" --pins "$4"' _ "$REPO" "$R" "$C" "$PINS_SH"
check "body: a payload mention cannot fail the lint" bash -c '[ "$2" = 0 ] && [[ $1 == *"dropped triggering source \`?octocat\`"* ]]' _ "$OUT" "$RC"

printf -- '-\tthanks @octocat for the fix\n' >"$FX/w-mention"
expect "body: a planted bare mention fails the lint" 1 "" "mention lint: body line" -- B --warnings "$FX/w-mention"
printf -- 'opmodel.dev/core@v2\tpins `opmodel.dev/core@v2` at `v2.0.0-beta.2`\n' >"$FX/w-ok"
run B --warnings "$FX/w-ok"
check "body: a module path with @ passes the lint" test "$RC" = 0

printf 'ping @octocat\nsecond line without newline' >"$FX/notes-mention"
run env CASCADE_NOTES_FILE="$FX/notes-mention" bash -c 'cd "$1" && "$2" body --classes "$3" --pins "$4"' _ "$REPO" "$R" "$C" "$PINS_SH"
check "body: a mention in Notes passes through unchanged" bash -c '
  [ "$2" = 0 ] && [ "$(sed -n "/^<!-- cascade-notes:/,\$p" <<<"$1" | tail -n +2)" = "$(cat "$3")" ]' _ "$OUT" "$RC" "$FX/notes-mention"
: >"$FX/notes-empty"
run env CASCADE_NOTES_FILE="$FX/notes-empty" bash -c 'cd "$1" && "$2" body --classes "$3" --pins "$4"' _ "$REPO" "$R" "$C" "$PINS_SH"
check "body: empty notes end the body at the marker" bash -c '[ "$(tail -n 1 <<<"$1")" = "<!-- cascade-notes: the bot keeps everything below this line -->" ]' _ "$OUT"
expect "body: a missing notes file is exit 1" 1 "" -- env CASCADE_NOTES_FILE="$FX/none" bash -c 'cd "$1" && "$2" body --classes "$3" --pins "$4"' _ "$REPO" "$R" "$C" "$PINS_SH"

# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# wiring/lib.sh: the fixed maps, payload validation, the cascade-PR filter,
# Notes and title markers, titles, the workflows guard, the action table,
# the status mapping and the token hiding.

new_fx

# --- maps ---------------------------------------------------------------------
expect "map: core notifies catalog_opm and library" 0 "catalog_opm library" -- in_lib notify_targets core
expect "map: catalog_opm notifies library, opm-operator, cli" 0 "library opm-operator cli" -- in_lib notify_targets catalog_opm
expect "map: library notifies opm-operator and cli" 0 "opm-operator cli" -- in_lib notify_targets library
expect "map: opm-operator notifies cli" 0 "cli" -- in_lib notify_targets opm-operator
expect "map: cli notifies catalog_opm and opm-operator" 0 "catalog_opm opm-operator" -- in_lib notify_targets cli
expect "map: the sandbox up notifies the sandbox down" 0 "cascade-sandbox-down" -- in_lib notify_targets cascade-sandbox-up
expect "map: a repo outside the notify map" 1 "" -- in_lib notify_targets modules
expect "map: cli receives from catalog_opm, library, opm-operator" 0 "catalog_opm library opm-operator" -- in_lib receiver_sources cli
expect "map: opm-operator receives from catalog_opm, library, cli" 0 "catalog_opm library cli" -- in_lib receiver_sources opm-operator
expect "map: library receives from core and catalog_opm" 0 "core catalog_opm" -- in_lib receiver_sources library
expect "map: catalog_opm receives from core and cli" 0 "core cli" -- in_lib receiver_sources catalog_opm
expect "map: core is no receiver" 1 "" -- in_lib receiver_sources core
expect "map: receivers invert the notify edges" 0 "" -- bash -c '
  . "$1"
  for s in core catalog_opm library opm-operator cli cascade-sandbox-up; do
    for t in $(notify_targets "$s"); do
      [[ " $(receiver_sources "$t") " == *" $s "* ]] || { echo "$s -> $t missing"; exit 1; }
    done
  done
  for r in catalog_opm library opm-operator cli cascade-sandbox-down; do
    for s in $(receiver_sources "$r"); do
      [[ " $(notify_targets "$s") " == *" $r "* ]] || { echo "$r <- $s missing"; exit 1; }
    done
  done' _ "$WIRING/lib.sh"
expect "map: G3 upstreams of cli skip nothing but the release-tool edge" 0 "catalog_opm library opm-operator" -- in_lib g3_upstreams cli
expect "map: G3 upstreams of library" 0 "core catalog_opm" -- in_lib g3_upstreams library
expect "map: G3 upstreams of catalog_opm leave out cli" 0 "core" -- in_lib g3_upstreams catalog_opm
expect "map: expect pair for a catalog tag drops opm-" 0 "opmodel.dev/catalogs/opm@v4=v4.5.1" -- in_lib expect_pair catalog_opm opm-v4.5.1
expect "map: expect pair for core" 0 "opmodel.dev/core@v2=v2.0.0-beta.3" -- in_lib expect_pair core v2.0.0-beta.3
expect "map: expect pair for library" 0 "github.com/open-platform-model/library=v1.0.0-beta.4" -- in_lib expect_pair library v1.0.0-beta.4
expect "map: expect pair for the sandbox" 0 "github.com/open-platform-model/cascade-sandbox-up=v0.2.0" -- in_lib expect_pair cascade-sandbox-up v0.2.0
expect "map: changelog source of the catalog pin" 0 "catalog_opm opm-" -- in_lib changelog_source opmodel.dev/catalogs/opm@v4
expect "map: a third-party pin has no changelog source" 1 "" -- in_lib changelog_source cue.dev/x/k8s.io@v0
expect "map: changelog source of the operator module pin" 0 "opm-operator opm_operator-" -- in_lib changelog_source opmodel.dev/modules/opm_operator@v0
expect "map: only the sandbox receiver widens the sources" 0 "cascade-sandbox-up|" -- bash -c '. "$1"; printf "%s|%s" "$(extra_sources cascade-sandbox-down)" "$(extra_sources cli)"' _ "$WIRING/lib.sh"
check "map: every receiver records the sha256 of its pins.sh and classes" bash -c '
  . "$1"
  for r in catalog_opm library opm-operator cli cascade-sandbox-down; do
    receiver_classes "$r" >/dev/null || exit 1
    src=$(mirror_sources "$r") || exit 1
    grep -qx "\.tasks/cascade/pins\.sh [0-9a-f]\{64\}" <<<"$src" || exit 1
    grep -qx "\.tasks/cascade/classes [0-9a-f]\{64\}" <<<"$src" || exit 1
    ! grep -vx "\.tasks/cascade/\(pins\.sh\|lib\.sh\|classes\) [0-9a-f]\{64\}" <<<"$src" || exit 1
  done
  ! mirror_sources core' _ "$WIRING/lib.sh"
check "map: the receivers whose pins.sh sources lib.sh record it" bash -c '
  . "$1"; for r in library opm-operator; do mirror_sources "$r" | grep -q "^\.tasks/cascade/lib\.sh " || exit 1; done' _ "$WIRING/lib.sh"
expect "map: the drift check reads every product receiver" 0 "catalog_opm library opm-operator cli" -- bash -c '. "$1"; printf "%s" "$MIRROR_RECEIVERS"' _ "$WIRING/lib.sh"
check "map: the five bot labels have colours and descriptions" bash -c '
  . "$1"; for l in $BOT_LABELS; do label_color "$l" >/dev/null && label_description "$l" >/dev/null || exit 1; done
  ! label_color e2e-verified' _ "$WIRING/lib.sh"
for p in go.mod sub/go.sum cue.mod/module.cue src/x/cue.mod/module.cue internal/operator/pin.go; do
  check "derived path: $p" in_lib is_derived_path "$p"
done
for p in README.md x/install.yaml internal/operator/manifest.go internal/operator/dist/install.yaml x/internal/operator/pin.go; do
  check "derived path: $p is not derived" bash -c '. "$1"; ! is_derived_path "$2"' _ "$WIRING/lib.sh" "$p"
done

# --- payload ------------------------------------------------------------------
pv() { # pv <receiver> <json>: prints rc|source|tags|expect|reason
  in_lib bash -c '. "$1"; rc=0; validate_payload "$2" "$3" || rc=$?; printf "%s|%s|%s|%s|%s" "$rc" "$P_SOURCE" "$P_TAGS" "$P_EXPECT" "$P_REASON"' _ "$WIRING/lib.sh" "$1" "$2"
}
expect "payload: one valid tag" 0 "0|library|v1.0.0-beta.4|github.com/open-platform-model/library=v1.0.0-beta.4|" -- \
  pv cli '{"source":"library","tags":["v1.0.0-beta.4"]}'
expect "payload: eight tags, expect from the last" 0 "0|core|v2.0.1 v2.0.2 v2.0.3 v2.0.4 v2.0.5 v2.0.6 v2.0.7 v2.0.8|opmodel.dev/core@v2=v2.0.8|" -- \
  pv library '{"source":"core","tags":["v2.0.1","v2.0.2","v2.0.3","v2.0.4","v2.0.5","v2.0.6","v2.0.7","v2.0.8"]}'
expect "payload: nine tags dropped" 0 "1||||tags is not an array of 1 to 8 strings" -- \
  pv library '{"source":"core","tags":["v2.0.1","v2.0.2","v2.0.3","v2.0.4","v2.0.5","v2.0.6","v2.0.7","v2.0.8","v2.0.9"]}'
expect "payload: no tags dropped" 0 "1||||tags is not an array of 1 to 8 strings" -- pv library '{"source":"core","tags":[]}'
expect "payload: a bad tag drops the whole payload" 0 "1||||1 tag(s) do not match the core tag shape" -- \
  pv library '{"source":"core","tags":["v2.0.1","v2.0.2; rm"]}'
expect "payload: a catalog tag without opm- dropped" 0 "1||||1 tag(s) do not match the catalog_opm tag shape" -- \
  pv library '{"source":"catalog_opm","tags":["v4.5.1"]}'
expect "payload: a catalog tag" 0 "0|catalog_opm|opm-v4.5.1|opmodel.dev/catalogs/opm@v4=v4.5.1|" -- \
  pv library '{"source":"catalog_opm","tags":["opm-v4.5.1"]}'
expect "payload: unknown source" 0 '1||||source `evil` is not accepted by cascade-sandbox-down' -- \
  pv cascade-sandbox-down '{"source":"evil","tags":["@x"]}'
expect "payload: a source from another edge" 0 '1||||source `core` is not accepted by cli' -- pv cli '{"source":"core","tags":["v2.0.0"]}'
expect "payload: a mention as source is named safely" 0 '1||||source `?octocat` is not accepted by cli' -- pv cli '{"source":"@octocat","tags":["v1.0.0"]}'
expect "payload: extra keys ignored" 0 "0|library|v1.0.0|github.com/open-platform-model/library=v1.0.0|" -- \
  pv cli '{"source":"library","tags":["v1.0.0"],"breaking":true,"labels":["x"]}'
expect "payload: a tag that is a mention" 0 "1||||1 tag(s) do not match the cascade-sandbox-up tag shape" -- \
  pv cascade-sandbox-down '{"source":"cascade-sandbox-up","tags":["@x"]}'
expect "payload: a non-string tag" 0 "1||||tags is not an array of 1 to 8 strings" -- pv cli '{"source":"library","tags":[1]}'
expect "payload: source not a string" 0 "1||||source is not a string" -- pv cli '{"source":["library"],"tags":["v1.0.0"]}'
expect "payload: not an object" 0 "1||||the payload is not a JSON object" -- pv cli '["library"]'
expect "payload: empty" 0 "1||||the payload is not a JSON object" -- pv cli ''
expect "payload: a tag with a trailing newline drops the whole payload" 0 "1||||the source or a tag holds a control character" -- \
  pv cli '{"source":"library","tags":["v1.0.0\n","v1.0.1"]}'
expect "payload: a last tag with a trailing newline" 0 "1||||the source or a tag holds a control character" -- \
  pv cli '{"source":"library","tags":["v1.0.1\n"]}'
expect "payload: a source with a trailing newline" 0 "1||||the source or a tag holds a control character" -- \
  pv cli '{"source":"library\n","tags":["v1.0.1"]}'
expect "payload: a tab or NUL inside a tag" 0 "1||||the source or a tag holds a control character" -- \
  pv cli '{"source":"library","tags":["v1.0.0\u0000","v1.0.1\t"]}'
expect "payload: a trailing space is a bad tag shape" 0 "1||||1 tag(s) do not match the library tag shape" -- \
  pv cli '{"source":"library","tags":["v1.0.0 "]}'
expect "payload: a newline in a tag" 0 "1||||the source or a tag holds a control character" -- pv cli '{"source":"library","tags":["v1.0.0\nv2.0.0"]}'
expect "payload: core is not a receiver" 0 "2||||" -- pv core '{"source":"cli","tags":["v1.0.0"]}'

# --- the cascade-PR filter ----------------------------------------------------
new_fx
mk_toy
printf 'body\n' >"$FX/b"
P_BOT=$(pr_json 7 "fix(deps): bump up to v0.2.0" "$FX/b")
P_FORK=$(pr_json 8 "evil" "$FX/b" "" "app/opm-cascade" 1 someone)
P_HUMAN=$(pr_json 9 "human" "$FX/b" "" "octocat")
P_OWNER=$(pr_json 10 "foreign owner" "$FX/b" "" "app/opm-cascade" 0 someone)
gh_prs "[$P_FORK,$P_HUMAN,$P_BOT,$P_OWNER]"
run in_lib cascade_pr cascade-sandbox-down
check "cascade PR: only the bot's same-repo PR is kept" bash -c '[ "$2" = 0 ] && [ "$(jq -r .number <<<"$1")" = 7 ]' _ "$OUT" "$RC"
gh_prs "[$P_FORK,$P_HUMAN]"
expect "cascade PR: a fork PR and a human PR are not the cascade PR" 0 "" -- in_lib cascade_pr cascade-sandbox-down
gh_prs "[$P_BOT,$(pr_json 11 "second" "$FX/b")]"
expect "cascade PR: two matches fail" 1 "" "more than one cascade PR" -- in_lib cascade_pr cascade-sandbox-down
gh_fx_err 1 "HTTP 502" -- "${PR_LIST_ARGS[@]}"
expect "cascade PR: an API error fails" 1 "" "cannot list" -- in_lib cascade_pr cascade-sandbox-down

# --- Notes and the title marker -----------------------------------------------
new_fx
M='<!-- cascade-notes: the bot keeps everything below this line -->'
printf '<!-- cascade-title: fix(deps): x -->\n## Notes\n\n%s\nkeep @this\n\ntwo lines, no newline at end' "$M" >"$FX/b1"
in_lib extract_notes "$FX/b1" "$FX/n1"
check "notes: every byte after the marker" bash -c '[ "$(cat "$1"; echo .)" = "$(printf "keep @this\n\ntwo lines, no newline at end.")" ]' _ "$FX/n1"
printf 'a human rewrote this\r\nno marker\r\n' >"$FX/b2"
in_lib extract_notes "$FX/b2" "$FX/n2"
check "notes: no marker keeps the whole body" cmp -s "$FX/b2" "$FX/n2"
printf '<!-- cascade-title: fix(deps): x -->\r\n## Notes\r\n\r\n%s\r\nhuman text\r\nmore\r\n' "$M" >"$FX/b3"
in_lib extract_notes "$FX/b3" "$FX/n3"
check "notes: a CRLF marker line is found, the CRLF notes kept" bash -c '[ "$(od -An -c "$1" | tr -d " \n")" = "humantext\\r\\nmore\\r\\n" ]' _ "$FX/n3"
# Two runs: the second body is built from the first one's notes; it must not grow.
{ printf '<!-- cascade-title: fix(deps): x -->\n## Notes\n\n%s\n' "$M"; cat "$FX/n3"; } >"$FX/b4"
in_lib extract_notes "$FX/b4" "$FX/n4"
{ printf '<!-- cascade-title: fix(deps): x -->\n## Notes\n\n%s\n' "$M"; cat "$FX/n4"; } >"$FX/b5"
check "notes: a CRLF body does not grow across two runs" cmp -s "$FX/b4" "$FX/b5"
printf '%s' "$M" >"$FX/b6"
in_lib extract_notes "$FX/b6" "$FX/n6"
check "notes: a marker on the last line without newline gives empty notes" test ! -s "$FX/n6"
printf '%s\nfirst\n%s\nsecond\n' "$M" "$M" >"$FX/b7"
in_lib extract_notes "$FX/b7" "$FX/n7"
check "notes: the first marker line wins" bash -c '[ "$(cat "$1")" = "$(printf "first\n%s\nsecond" "$2")" ]' _ "$FX/n7" "$M"
expect "title marker: the marker above the Notes" 0 "fix(deps): x" -- in_lib title_marker "$FX/b3"
printf '## Notes\n\n%s\n<!-- cascade-title: feat: pasted -->\n' "$M" >"$FX/b8"
expect "title marker: a marker pasted into the Notes is not read" 0 "" -- in_lib title_marker "$FX/b8"
expect "title marker: no marker" 0 "" -- in_lib title_marker "$FX/b2"
printf '<!-- cascade-title:  -->\n' >"$FX/b9"
expect "title marker: the empty marker" 0 "" -- in_lib title_marker "$FX/b9"
expect "body above notes: stops before the marker" 0 $'<!-- cascade-title: fix(deps): x -->\r\n## Notes\r\n\r' -- in_lib body_above_notes "$FX/b3"

# --- titles -------------------------------------------------------------------
for t in "ci(deps): x|1" "test(fixtures): x|2" "fix(deps): x|3" "feat(deps): x|4" "feat!: x|4" "fix(deps)!: x|3" "chore: x|0" "Fix: x|0" "fix:x|0"; do
  expect "rank: ${t%|*}" 0 "${t#*|}" -- in_lib type_rank "${t%|*}"
done
ft() { in_lib bash -c '. "$1"; final_title "$2" "$3" "$4" "$5"; printf "%s|%s" "$FINAL_TITLE" "$TITLE_RISE"' _ "$WIRING/lib.sh" "$@"; }
expect "title: no PR takes the computed title" 0 "fix(deps): bump up to v0.3.0|0" -- ft 0 "" "" "fix(deps): bump up to v0.3.0"
expect "title: not retitled takes the computed title" 0 "fix(deps): bump up to v0.3.0|0" -- \
  ft 1 "fix(deps): bump up to v0.2.0" "fix(deps): bump up to v0.2.0" "fix(deps): bump up to v0.3.0"
expect "title: retitled with ! is kept" 0 "feat(deps)!: new api|0" -- ft 1 "feat(deps)!: new api" "fix(deps): bump up to v0.2.0" "fix(deps): bump up to v0.3.0"
expect "title: a deliberate downgrade is kept, no rise" 0 "ci(deps): later|0" -- ft 1 "ci(deps): later" "fix(deps): bump up to v0.2.0" "fix(deps): bump up to v0.3.0"
expect "title: a rise above the kept title fires" 0 "ci(deps): later|1" -- ft 1 "ci(deps): later" "test(fixtures): refresh" "fix(deps): bump up to v0.3.0"
expect "title: the rise fires once (marker now carries the computed class)" 0 "ci(deps): later|0" -- \
  ft 1 "ci(deps): later" "fix(deps): bump up to v0.3.0" "fix(deps): bump up to v0.4.0"
expect "title: a body with no marker is not retitled" 0 "fix(deps): bump up to v0.3.0|0" -- ft 1 "my own title" "" "fix(deps): bump up to v0.3.0"
expect "title: type and scope" 0 "fix(deps)" -- in_lib type_scope "fix(deps): bump up to v0.3.0"

# --- the mention lint and comments --------------------------------------------
check "lint: a bare mention fails" bash -c '. "$1"; ! lint_text title "thanks @octocat" 2>/dev/null' _ "$WIRING/lib.sh"
check "lint: a module path passes" in_lib lint_text title "pins opmodel.dev/core@v2"
for k in conflict-merge conflict-workflows recreate close too-long title-rise continued; do
  check "comment: $k passes the lint" bash -c '. "$1"; c=$(comment_text "$2" "$3") && [ -n "$c" ] && lint_text comment "$c"' _ "$WIRING/lib.sh" "$k" "x"
done
expect "comment: path lists are made safe" 0 '`go.mod`, `a/?evil`' -- in_lib path_list go.mod 'a/@evil'
expect "comment: continued" 0 "Continued in #12." -- in_lib comment_text continued 12

# --- the workflows guard ------------------------------------------------------
wg() { in_lib wf_guard "$@"; }
for r in strict tree; do
  expect "guard $r: fresh, D1 empty" 0 push -- wg "$r" fresh "" ""
  expect "guard $r: fresh, D1 set is a bug" 0 error -- wg "$r" fresh ".github/workflows/x.yml" ""
  expect "guard $r: rebuild, both empty" 0 push -- wg "$r" rebuild "" ""
  expect "guard $r: rebuild, D1 set is a bug" 0 error -- wg "$r" rebuild ".github/workflows/x.yml" ""
  expect "guard $r: recreate, D1 empty" 0 recreate -- wg "$r" recreate "" ""
  expect "guard $r: recreate, D1 set is a bug" 0 error -- wg "$r" recreate ".github/workflows/x.yml" ""
  expect "guard $r: merge, both empty" 0 push -- wg "$r" merge "" ""
  expect "guard $r: merge, D1 set" 0 conflict -- wg "$r" merge ".github/workflows/x.yml" ""
done
expect "guard strict: rebuild, D2 set becomes recreate" 0 recreate -- wg strict rebuild "" ".github/workflows/touch.yml"
expect "guard tree: rebuild, D2 set pushes in place" 0 push -- wg tree rebuild "" ".github/workflows/touch.yml"
expect "guard strict: merge, D2 set is a conflict" 0 conflict -- wg strict merge "" ".github/workflows/touch.yml"
expect "guard tree: merge, D2 set pushes" 0 push -- wg tree merge "" ".github/workflows/touch.yml"
expect "guard: the shipped rule is tree (E4c)" 0 tree -- bash -c '. "$1"; WF_GUARD_RULE=x; . "$1"; echo "$WF_GUARD_RULE"' _ "$WIRING/lib.sh"

# --- the action table ---------------------------------------------------------
act() { in_lib action_for "$@"; }
expect "action: skip" 0 skip -- act skip 1 1 1 1
expect "action: conflict" 0 conflict -- act conflict 0 0 1 1
expect "action: too long" 0 too_long -- act rebuild 1 0 1 1
expect "action: tree equals main with an open PR closes" 0 close -- act rebuild 0 1 1 1
expect "action: tree equals main with a left-behind branch closes" 0 close -- act recreate 0 1 0 1
expect "action: tree equals main with nothing open is a no-op" 0 noop -- act fresh 0 1 0 0
expect "action: otherwise push" 0 push -- act fresh 0 0 0 0

# --- status mapping -----------------------------------------------------------
sf() { in_lib status_for "$@"; }
expect "status: ok in warn" 0 $'success\tok: shipped pins current' -- sf warn ok "ok: shipped pins current"
expect "status: ok in enforce" 0 $'success\tok: upstreams settled' -- sf enforce ok "ok: upstreams settled"
expect "status: problem in warn" 0 $'success\tWARN: behind: up v0.1.0→v0.2.0' -- sf warn problem "behind: up v0.1.0→v0.2.0"
expect "status: problem in enforce" 0 $'failure\tbehind: up v0.1.0→v0.2.0' -- sf enforce problem "behind: up v0.1.0→v0.2.0"
expect "status: error in warn" 0 $'success\tWARN: gate could not run, see the run' -- sf warn error "x"
expect "status: error in enforce" 0 $'error\tcould not evaluate, see the run' -- sf enforce error "x"
long=$(printf 'x%.0s' $(seq 1 300))
run sf enforce problem "$long"
check "status: a 300-character message is cut to 140 ending in …" bash -c '
  d="${1#*$'"'"'\t'"'"'}"; [ "$(LC_ALL=C.UTF-8; printf "%s" "${#d}")" = 140 ] && [[ $d == *… ]]' _ "$OUT"
check "status: modes other than warn and enforce are refused" bash -c '. "$1"; valid_mode warn && valid_mode enforce && ! valid_mode strict && ! valid_mode ""' _ "$WIRING/lib.sh"

# --- tokens -------------------------------------------------------------------
expect "tokens: repo code sees no token or header" 0 "|||||" -- env GH_TOKEN=a GITHUB_TOKEN=b CASCADE_READ_TOKEN=c GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0=k GIT_CONFIG_VALUE_0=v bash -c '. "$1"; run_repo_code bash -c '"'"'printf "%s|%s|%s|%s|%s|%s" "${GH_TOKEN:-}" "${GITHUB_TOKEN:-}" "${CASCADE_READ_TOKEN:-}" "${GIT_CONFIG_COUNT:-}" "${GIT_CONFIG_KEY_0:-}" "${GIT_CONFIG_VALUE_0:-}"'"'"'' _ "$WIRING/lib.sh"
expect "tokens: repo code sees no runner command file or Actions service variable" 0 "||||||||" -- \
  env GITHUB_ENV=/e GITHUB_PATH=/p GITHUB_OUTPUT=/o GITHUB_STEP_SUMMARY=/s GITHUB_STATE=/st ACTIONS_RUNTIME_TOKEN=rt \
  ACTIONS_ID_TOKEN_REQUEST_TOKEN=it GIT_CONFIG_KEY_3=k3 GIT_CONFIG_VALUE_3=v3 bash -c '. "$1"; run_repo_code bash -c '"'"'printf "%s|%s|%s|%s|%s|%s|%s|%s|%s" "${GITHUB_ENV:-}" "${GITHUB_PATH:-}" "${GITHUB_OUTPUT:-}" "${GITHUB_STEP_SUMMARY:-}" "${GITHUB_STATE:-}" "${ACTIONS_RUNTIME_TOKEN:-}" "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" "${GIT_CONFIG_KEY_3:-}" "${GIT_CONFIG_VALUE_3:-}"'"'"'' _ "$WIRING/lib.sh"
expect "tokens: repo code keeps the variables a task may read" 0 "true|/w|/tmp/r" -- \
  env GITHUB_ACTIONS=true GITHUB_WORKSPACE=/w RUNNER_TEMP=/tmp/r bash -c '. "$1"; run_repo_code bash -c '"'"'printf "%s|%s|%s" "${GITHUB_ACTIONS:-}" "${GITHUB_WORKSPACE:-}" "${RUNNER_TEMP:-}"'"'"'' _ "$WIRING/lib.sh"
expect "maps: changelog_repos of a receiver is every other product repo" 0 "core catalog_opm library opm-operator" -- \
  bash -c '. "$1"; r=$(changelog_repos cli); printf "%s" "${r% }"' _ "$WIRING/lib.sh"
expect "maps: changelog_repos of the sandbox receiver" 0 "cascade-sandbox-up" -- bash -c '. "$1"; changelog_repos cascade-sandbox-down' _ "$WIRING/lib.sh"
expect "maps: core has no changelog_repos" 1 "" -- bash -c '. "$1"; changelog_repos core' _ "$WIRING/lib.sh"
expect "tokens: git_read passes the header to that git call only" 0 "AUTHORIZATION: basic eC1hY2Nlc3MtdG9rZW46c2VjcmV0" -- \
  env CASCADE_READ_TOKEN=secret bash -c '. "$1"; git_read config --get http.https://github.com/.extraheader; [ -z "${GIT_CONFIG_COUNT:-}" ]' _ "$WIRING/lib.sh"
expect "tokens: without a read token git_read adds nothing" 1 "" -- bash -c '. "$1"; git_read config --get http.https://github.com/.extraheader' _ "$WIRING/lib.sh"
check "scratch: CASCADE_T inside the repo checkout is refused" bash -c '
  . "$1"; ! (CASCADE_REPO_DIR="$2/repo" check_scratch "$2/repo/t" 2>/dev/null) && (CASCADE_REPO_DIR="$2/repo" check_scratch "$2/t") \
    && ! (check_scratch "$3/x" 2>/dev/null)' _ "$WIRING/lib.sh" "$FX" "$ORG_ROOT"

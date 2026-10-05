# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the scripts that source this file
# Shared code for the release-cascade workflows and actions (cascade-notify,
# cascade-receive.yml, cascade-publish, cascade-gates.yml): the fixed maps, payload
# validation, the cascade-PR filter, Notes and title-marker parsing, the
# title rank, the mention lint, the comment texts, the workflows guard, the
# action table and the gate status mapping. Design: workspace RELEASING.md,
# section "The cascade". Sourced, never run.
#
# The repo-name derivation is NOT here: it is the inline Guard step, first
# in every job and action. These scripts always run at the .github commit
# the caller pinned: an action runs them from its own GITHUB_ACTION_PATH,
# a reusable workflow checks them out at its own job.workflow_sha.
#
# Tools: bash, coreutils, git, jq, grep with -P; gh through "${CASCADE_GH:-gh}".

ORG=open-platform-model
BOT_NAME='opm-cascade[bot]'
BOT_EMAIL='337635439+opm-cascade[bot]@users.noreply.github.com'
BOT_LOGIN='app/opm-cascade'
BRANCH=deps/cascade
NOTES_MARKER='<!-- cascade-notes: the bot keeps everything below this line -->'
# mention-guard's own pattern prefix (mention-guard.yml, the resolver's
# lib/prtext.sh): an @ that no word character or @ precedes, followed by a
# letter or digit, is a GitHub mention.
MENTION_RE='(?<![\w@])@[A-Za-z0-9]'
REPO_RE='^[A-Za-z0-9][A-Za-z0-9._-]*$'
# The resolver's tag pattern; every accepted tag also matches it.
RESOLVER_TAG_RE='^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$'
BODY_MAX=65000

# Which pushes the bot makes when main changed workflow files: strict pushes
# only updates that are no workflow change against main's tip nor against
# the old branch tip; tree only checks main's tip. A constant, never read
# from the environment. The sandbox cycle (E4c, 2026-10-04) decided tree:
# GitHub accepted an App push without the Workflows permission both for an
# in-place lease update across a workflow change on main and for a merge
# commit bringing main's workflow change in.
WF_GUARD_RULE=tree

# The five labels the bot may set or create, with RELEASING.md's colours and
# descriptions ("Labels").
BOT_LABELS="deps-cascade deps-cascade:conflict deps-cascade:hold deps-cascade:breaking need-human-review"

die() { printf '%s: %s\n' "${CASCADE_SCRIPT:-cascade}" "$1" >&2; exit "${2:-1}"; }
note() { printf '%s: %s\n' "${CASCADE_SCRIPT:-cascade}" "$1" >&2; }
gh_() { "${CASCADE_GH:-gh}" "$@"; }
sleep_() { "${CASCADE_SLEEP:-sleep}" "$@"; }

need_tools() {
  local t
  for t in "$@"; do
    if [ "$t" = gh ] && [ -n "${CASCADE_GH:-}" ]; then continue; fi
    command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"
  done
}

need_yq() {
  local v
  v=$(yq --version 2>&1) || die "missing tool: mikefarah yq v4 (yq --version failed)"
  case "$v" in
    *mikefarah*" v4."* | *mikefarah*" 4."*) ;;
    *) die "missing tool: mikefarah yq v4 (found: $v)" ;;
  esac
}

# safe_text <value>: every character outside [A-Za-z0-9._/-] replaced by ?,
# cut to 64 characters. Names untrusted input without a mention or Markdown.
safe_text() {
  local v="${1:0:64}"
  printf '%s' "${v//[^A-Za-z0-9._\/-]/?}"
}

# --- fixed maps ---------------------------------------------------------------

# notify_targets <source>: the repos a release of <source> dispatches to.
notify_targets() {
  case "$1" in
    core) echo "catalog_opm library" ;;
    catalog_opm) echo "library opm-operator cli" ;;
    library) echo "opm-operator cli" ;;
    opm-operator) echo "cli" ;;
    cli) echo "catalog_opm opm-operator" ;;
    cascade-sandbox-up) echo "cascade-sandbox-down" ;;
    *) return 1 ;;
  esac
}

# receiver_sources <receiver>: the payload sources the receiver accepts.
receiver_sources() {
  case "$1" in
    catalog_opm) echo "core cli" ;;
    library) echo "core catalog_opm" ;;
    opm-operator) echo "catalog_opm library cli" ;;
    cli) echo "catalog_opm library opm-operator" ;;
    cascade-sandbox-down) echo "cascade-sandbox-up" ;;
    *) return 1 ;;
  esac
}

# g3_upstreams <receiver>: the repos whose cascade state G3 checks. The
# release-tool edges from cli never count.
g3_upstreams() {
  case "$1" in
    catalog_opm) echo "core" ;;
    library) echo "core catalog_opm" ;;
    opm-operator) echo "catalog_opm library" ;;
    cli) echo "catalog_opm library opm-operator" ;;
    cascade-sandbox-down) echo "cascade-sandbox-up" ;;
    *) return 1 ;;
  esac
}

# g3_eval <receiver>: sets G3_STATE and G3_MSG, gate G3 cascade/settled
# (workspace RELEASING.md, section "Gates"): an upstream's open cascade PR
# titled fix(deps) or feat(deps), or its `autorelease: pending` PR listing a
# **deps:** bullet, is a problem; an API error is an evaluator error. Only
# the API, read with GH_TOKEN: gates-post.sh evaluates it in the Post gates
# job, which runs no repo code, so no release head can choose its result.
g3_eval() {
  local up pr n title pending problems=() p
  G3_STATE=ok G3_MSG="ok: upstreams settled"
  for up in $(g3_upstreams "$1"); do
    if ! pr=$(cascade_pr "$up"); then G3_STATE=error G3_MSG="cannot read the cascade PR of $up"; return 0; fi
    if [ -n "$pr" ]; then
      n=$(jq -r .number <<<"$pr")
      title=$(jq -r .title <<<"$pr")
      case "$title" in "fix(deps)"* | "feat(deps)"*) problems+=("$up has open cascade #$n") ;; esac
    fi
    if ! pending=$(gh_ pr list -R "$ORG/$up" --base main --state open --label "autorelease: pending" --json number,body); then
      G3_STATE=error G3_MSG="cannot list the release PRs of $up"
      return 0
    fi
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      problems+=("$up release #$p pending with deps")
    done < <(jq -r '.[] | select((.body // "") | contains("**deps:**")) | .number' <<<"$pending")
  done
  if [ "${#problems[@]}" -gt 0 ]; then
    G3_STATE=problem
    G3_MSG=$(printf '%s; ' "${problems[@]}")
    G3_MSG="${G3_MSG%; }"
  fi
}

# tag_re <source>: the tag shape a release of <source> has.
tag_re() {
  if [ "$1" = catalog_opm ]; then
    printf '%s' '^opm-v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'
  else
    printf '%s' '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'
  fi
}

# valid_tag <source> <tag>
valid_tag() {
  local re
  re=$(tag_re "$1")
  [[ $2 =~ $re ]] && [[ $2 =~ $RESOLVER_TAG_RE ]]
}

# expect_pair <source> <tag>: the CASCADE_EXPECT pair for that release.
expect_pair() {
  case "$1" in
    core) printf 'opmodel.dev/core@v2=%s' "$2" ;;
    catalog_opm) printf 'opmodel.dev/catalogs/opm@v4=%s' "${2#opm-}" ;;
    library | opm-operator | cli | cascade-sandbox-up) printf 'github.com/open-platform-model/%s=%s' "$1" "$2" ;;
    *) return 1 ;;
  esac
}

# changelog_source <pin key>: "<repo> <tag prefix>" for the breaking check;
# exit 1 for a pin that is not a cascade repo's.
changelog_source() {
  case "$1" in
    opmodel.dev/core@v2) echo "core " ;;
    opmodel.dev/catalogs/opm@v4) echo "catalog_opm opm-" ;;
    github.com/open-platform-model/library) echo "library " ;;
    github.com/open-platform-model/opm-operator) echo "opm-operator " ;;
    # The operator module, released from opm-operator on its own train.
    opmodel.dev/modules/opm_operator@v0) echo "opm-operator opm_operator-" ;;
    github.com/open-platform-model/cli) echo "cli " ;;
    github.com/open-platform-model/cascade-sandbox-up) echo "cascade-sandbox-up " ;;
    *) return 1 ;;
  esac
}

# changelog_repos <receiver>: the repos whose releases the breaking check
# may read for this receiver's moved pins, fetched before any repo code runs:
# every product repo with a changelog_source entry but the receiver itself.
changelog_repos() {
  local r
  case "$1" in
    cascade-sandbox-down) echo cascade-sandbox-up ;;
    catalog_opm | library | opm-operator | cli)
      for r in core catalog_opm library opm-operator cli; do
        [ "$r" = "$1" ] || printf '%s ' "$r"
      done
      echo
      ;;
    *) return 1 ;;
  esac
}

# extra_sources <receiver>: CASCADE_EXTRA_SOURCES for the resolver's body.
# Only the sandbox receiver widens it, with a literal; never from input.
extra_sources() {
  if [ "$1" = cascade-sandbox-down ]; then echo cascade-sandbox-up; fi
}

label_color() {
  case "$1" in
    deps-cascade) echo 0366d6 ;;
    deps-cascade:conflict) echo b60205 ;;
    deps-cascade:hold) echo fbca04 ;;
    deps-cascade:breaking) echo d93f0b ;;
    need-human-review) echo e99695 ;;
    *) return 1 ;;
  esac
}

label_description() {
  case "$1" in
    deps-cascade) echo "Rolling upstream-pin PR opened by the release cascade" ;;
    deps-cascade:conflict) echo "The bot could not merge main into this cascade PR; a human resolves it" ;;
    deps-cascade:hold) echo "A human is working on this cascade PR; the bot does not push" ;;
    deps-cascade:breaking) echo "An upstream changelog in this PR announces a breaking change" ;;
    need-human-review) echo "Glue edits a human must review before merging" ;;
    *) return 1 ;;
  esac
}

is_bot_label() { [[ " $BOT_LABELS " == *" $1 "* ]]; }

# is_derived_path <path>: a merge conflict here takes main's side and the
# task regenerates the file. internal/operator/pin.go is the cli's operator
# module pin, which its task rewrites with hack/operator-pin.
is_derived_path() {
  case "${1##*/}" in go.mod | go.sum) return 0 ;; esac
  case "$1" in cue.mod/module.cue | */cue.mod/module.cue | internal/operator/pin.go) return 0 ;; esac
  return 1
}

# --- what publish accepts from compute ----------------------------------------
# The bot's own commits may change only the files the receiver's task writes.
# The lists are read from each receiver's .tasks/cascade/cascade.sh on main
# (catalog_opm 0560990, library ca7c56b, opm-operator 53ccaab, cli bd4d1a7c,
# 2026-10-05) and live here, never in the receiver's tree, because publish
# trusts only this SHA-pinned code. A receiver whose task starts writing
# another file needs this list changed, and its pin moved, first; the sha256
# of each cascade.sh read is in mirror_sources, so publish refuses a receiver
# whose cascade.sh changed since, instead of judging paths by a stale list.

# publish_paths <receiver>: the anchored EREs of the paths its task writes.
# cue.mod/module.cue at any depth: only module versions live there, which is
# what the cascade moves, and the receivers' module lists change often.
publish_paths() {
  case "$1" in
    catalog_opm) printf '%s\n' '(^|/)cue\.mod/module\.cue$' '^\.opm-cli-version$' ;;
    library)
      printf '%s\n' '(^|/)cue\.mod/module\.cue$' '^opm/schema/loader\.go$' '^docs/getting-started\.md$' '^AGENTS\.md$'
      ;;
    opm-operator)
      printf '%s\n' '(^|/)cue\.mod/module\.cue$' '^go\.(mod|sum)$' '^\.opm-cli-version$' \
        '^config/samples/opmodel\.dev_v1alpha1_(platform|moduleinstance)\.yaml$' '^test/fixtures/catalog\.go$' \
        '^test/fixtures/(modules/[^/]+|catalogs/provider)/identity/identity\.cue$' \
        '^test/fixtures/modules/[^/]+/moduleinstance\.yaml$'
      ;;
    cli)
      printf '%s\n' '(^|/)cue\.mod/module\.cue$' '^go\.(mod|sum)$' '^internal/operator/pin\.go$' \
        '^hack/kind-platform\.yaml$' '^(templates/[^/]+|tests/fixtures/modules/podinfo)/identity/identity\.cue$'
      ;;
    cascade-sandbox-down) printf '%s\n' '^UPSTREAM_VERSION$' '^fixtures/' ;;
    *) return 1 ;;
  esac
}

# publish_denied <receiver> <path>: exit 0 for a path no bot commit may ever
# change, whatever publish_paths says: workflow and action code, the task
# code, scripts, code owners, the release configs and the steering files.
# cli's two hack/ data files (the kind Platform and its catalog pins) are the
# only exception; hack/ holds Go programs and scripts otherwise. opm-operator's
# operator module (modules/) moves through its own module/deps publisher,
# never through deps:cascade, whose repo scope leaves it alone.
publish_denied() {
  case "$1:$2" in cli:hack/kind-platform.yaml | cli:hack/platform/cue.mod/module.cue) return 1 ;; esac
  case "$1:$2" in opm-operator:modules/*) return 0 ;; esac
  case "$2" in .github/* | .tasks/* | hack/* | *.sh | release-please-config.json | .release-please-manifest.json) return 0 ;; esac
  case "${2##*/}" in Taskfile* | CODEOWNERS | .cascade-frozen | .cascade-hold) return 0 ;; esac
  return 1
}

# publish_path_ok <receiver> <path>: exit 0 when a bot commit may change it.
publish_path_ok() {
  local re
  ! publish_denied "$1" "$2" || return 1
  while IFS= read -r re; do
    [[ $2 =~ $re ]] && return 0
  done < <(publish_paths "$1")
  return 1
}

# receiver_classes <receiver>: the receiver's .tasks/cascade/classes, as on
# main (same commits as above), for the title and body publish renders.
receiver_classes() {
  case "$1" in
    catalog_opm) printf '%s\n' 'release-tool .opm-cli-version' 'shipped src/' ;;
    library) printf '%s\n' 'test testdata/' 'test modules/' 'test *_test.go' ;;
    opm-operator)
      printf '%s\n' 'release-tool .opm-cli-version' 'test config/samples/' 'test test/' 'test **/testdata/' 'test *_test.go'
      ;;
    cli)
      printf '%s\n' 'test hack/platform/' 'test hack/kind-platform.yaml' 'test examples/' 'test tests/' \
        'test **/testdata/' 'test *_test.go'
      ;;
    cascade-sandbox-down) printf '%s\n' 'shipped UPSTREAM_VERSION' 'test fixtures/' ;;
    *) return 1 ;;
  esac
}

# The pin report of each receiver's .tasks/cascade/pins.sh, as on main (same
# commits as above), reading only `git show <ref>:<path>`: one TSV row per pin,
# <pin-key> <display> <class> <version> <labels>. Each parser copies the
# receiver's own, quirks included, so publish names the same pins as compute.

# pin_blob <ref> <path>: prints the file at the ref; exit 1 when it is not a
# file there.
pin_blob() {
  [ "$(git cat-file -t "$1:$2" 2>/dev/null)" = blob ] || return 1
  git show "$1:$2"
}

PIN_SEMVER_RE='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

pins_catalog_opm() {
  local ref="$1" mod v cli key=opmodel.dev/core@v2
  if mod=$(pin_blob "$ref" src/cue.mod/module.cue) && grep -qF "\"$key\"" <<<"$mod"; then
    v=$(grep -FA5 "\"$key\"" <<<"$mod" | grep -m1 -oP 'v:\s*"\K[^"]+') || die "src/cue.mod/module.cue at $ref: no v: under \"$key\""
    [[ $v =~ $PIN_SEMVER_RE ]] || die "src/cue.mod/module.cue at $ref: \"$key\" pins a malformed version: $v"
    printf '%s\t%s\t%s\t%s\t%s\n' "$key" core shipped "$v" ""
  fi
  if cli=$(pin_blob "$ref" .opm-cli-version); then
    [[ $cli =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || die ".opm-cli-version at $ref is not one line holding a CLI tag"
    printf '%s\t%s\t%s\t%s\t%s\n' github.com/open-platform-model/cli "opm CLI" release-tool "$cli" ""
  fi
}

pins_library() {
  local ref="$1" f core="" catalog=""
  if f=$(pin_blob "$ref" opm/schema/loader.go); then
    core=$({ grep -oP 'DefaultSchemaModule = "opmodel\.dev/core@\K[^"]+' <<<"$f" || [ $? -eq 1 ]; } | head -n1)
  fi
  if f=$(pin_blob "$ref" testdata/parity/cue.mod/module.cue); then
    catalog=$(awk -v key='"opmodel.dev/catalogs/opm@v4": {' '
      { t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t) }
      done { next }
      t == key { inb = 1; next }
      inb && t ~ /^v:[ \t]*"/ { v = t; sub(/^v:[ \t]*"/, "", v); sub(/".*$/, "", v); print v; done = 1; next }
      inb && t ~ /^}/ { done = 1 }' <<<"$f")
  fi
  if [ -n "$core" ]; then
    [[ $core =~ $PIN_SEMVER_RE ]] || die "opmodel.dev/core@v2 at $ref reads '$core', not a v-prefixed version"
    printf '%s\t%s\t%s\t%s\t%s\n' opmodel.dev/core@v2 core shipped "$core" need-human-review
  fi
  if [ -n "$catalog" ]; then
    [[ $catalog =~ $PIN_SEMVER_RE ]] || die "opmodel.dev/catalogs/opm@v4 at $ref reads '$catalog', not a v-prefixed version"
    printf '%s\t%s\t%s\t%s\t%s\n' opmodel.dev/catalogs/opm@v4 "opm catalog" test "$catalog" ""
  fi
}

pins_opm_operator() {
  local ref="$1" f v
  # op_row KEY DISPLAY CLASS FILE VERSION: as the operator's row(), an
  # invalid or empty version is an error.
  op_row() {
    [[ $5 =~ $PIN_SEMVER_RE ]] || die "$4: no valid version for $1 (read '$5')"
    printf '%s\t%s\t%s\t%s\t\n' "$1" "$2" "$3" "$5"
  }
  if f=$(pin_blob "$ref" go.mod); then
    v=$(awk -v m=github.com/open-platform-model/library '
      $1 == "replace" || $2 == "=>" { next }
      $1 == "require" && $2 == m { print $3; exit }
      $1 == m { print $2; exit }' <<<"$f")
    op_row github.com/open-platform-model/library library shipped go.mod "$v"
  fi
  if f=$(pin_blob "$ref" config/samples/opmodel.dev_v1alpha1_platform.yaml); then
    v=$(awk -v k=opmodel.dev/catalogs/opm@v4: '
      index($0, k) { f = 1; next }
      f && /^[[:space:]]*version:/ { v = $0; sub(/^[[:space:]]*version:[[:space:]]*/, "", v); gsub(/"/, "", v); print v; exit }' <<<"$f")
    op_row opmodel.dev/catalogs/opm@v4 "opm catalog" test config/samples/opmodel.dev_v1alpha1_platform.yaml "v$v"
  fi
  if f=$(pin_blob "$ref" test/fixtures/modules/hello/cue.mod/module.cue); then
    v=$(awk -v k='"opmodel.dev/core@v2": {' '
      index($0, k) { f = 1; next }
      f && /^[[:space:]]*v:/ { if (match($0, /"[^"]+"/)) print substr($0, RSTART + 1, RLENGTH - 2); exit }
      f && /}/ { exit }' <<<"$f")
    op_row opmodel.dev/core@v2 core test test/fixtures/modules/hello/cue.mod/module.cue "$v"
  fi
  if f=$(pin_blob "$ref" .opm-cli-version); then
    v=$(tr -d '[:space:]' <<<"$f")
    op_row github.com/open-platform-model/cli "opm CLI" release-tool .opm-cli-version "$v"
  fi
}

pins_cli() {
  local ref="$1" f mv
  # cli_row KEY DISPLAY VERSION: as the cli's row(), empty is no row.
  cli_row() {
    [ -n "$3" ] || return 0
    [[ $3 =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]] || die "$1: not a v-prefixed version: $3"
    printf '%s\t%s\tshipped\t%s\t\n' "$1" "$2" "$3"
  }
  # cli_dep KEY: the v: of KEY's block in the module.cue on stdin.
  cli_dep() {
    awk -v k="\"$1\": {" '
      index($0, k) { f = 1; next }
      f && /^[[:space:]]*v:/ { match($0, /"[^"]*"/); print substr($0, RSTART + 1, RLENGTH - 2); exit }
      f && /^[[:space:]]*}/ { exit }'
  }
  if f=$(pin_blob "$ref" go.mod); then
    cli_row github.com/open-platform-model/library library \
      "$(awk -v m=github.com/open-platform-model/library '$1 == m {print $2; exit}' <<<"$f")"
  fi
  # The operator module pin and the operator release it deploys, both from
  # internal/operator/pin.go; the module version is bare there.
  if f=$(pin_blob "$ref" internal/operator/pin.go); then
    cli_row github.com/open-platform-model/opm-operator opm-operator \
      "$(sed -n 's/^const PinnedOperatorVersion = "\(.*\)"$/\1/p' <<<"$f")"
    mv=$(sed -n 's/^const PinnedModuleVersion = "\(.*\)"$/\1/p' <<<"$f")
    cli_row opmodel.dev/modules/opm_operator@v0 "opm-operator module" "${mv:+v$mv}"
  fi
  if f=$(pin_blob "$ref" templates/minimal/cue.mod/module.cue); then
    cli_row opmodel.dev/catalogs/opm@v4 "opm catalog" "$(cli_dep opmodel.dev/catalogs/opm@v4 <<<"$f")"
    cli_row opmodel.dev/core@v2 core "$(cli_dep opmodel.dev/core@v2 <<<"$f")"
  fi
}

pins_sandbox() {
  local v
  v=$(pin_blob "$1" UPSTREAM_VERSION) || return 0
  printf '%s\t%s\t%s\t%s\t%s\n' github.com/open-platform-model/cascade-sandbox-up up shipped "$v" ""
}

# receiver_pins <receiver> <commit>: the receiver's pin report at the commit,
# run from inside its checkout.
receiver_pins() {
  case "$1" in
    catalog_opm) pins_catalog_opm "$2" ;;
    library) pins_library "$2" ;;
    opm-operator) pins_opm_operator "$2" ;;
    cli) pins_cli "$2" ;;
    cascade-sandbox-down) pins_sandbox "$2" ;;
    *) return 1 ;;
  esac
}

# --- the mirrors' sources -----------------------------------------------------
# The receiver files the mirrors above copy, with the sha256 of the version on
# main they were written from (same commits as above; the archived sandbox's
# from its last main): pins.sh, the lib.sh it sources, classes, and, for the
# four product receivers, the cascade.sh that publish_paths was read from.
# publish refuses a push or recreate when the receiver's main holds another
# version of any of them (receive-publish.sh, check_mirror), and
# cascade-mirror-drift.yml reports the drift daily. A receiver that changes one
# of these files needs this table, the mirror or allow-list and the .github pin
# moved together. Code cascade.sh only runs (cli's hack/operator-pin, a
# Taskfile task) is not hashed: a change there that writes a new path still
# ends in a path refusal. The sandbox records no cascade.sh: the suite's toy
# receiver carries its own test task in its place.

# mirror_sources <receiver>: "<path> <sha256>" per mirrored file.
mirror_sources() {
  case "$1" in
    catalog_opm)
      printf '%s\n' '.tasks/cascade/pins.sh 264c6f70bf10629c93a3dc86df0f82aeaccbceb707d3ca21281021f46c16b8aa' \
        '.tasks/cascade/classes 83e67ce0d82150b3847a13100ef36dab818a37338a6ba6b9c9e77f30cd5e24e1' \
        '.tasks/cascade/cascade.sh c5605510fd56160f520c172bb0bbd30e50faff490b72cc37e08704ae061dd766'
      ;;
    library)
      printf '%s\n' '.tasks/cascade/pins.sh 4b18bf587622e5a06276e8f92d32ab5658494367f259e0ef50f5a024cfd84382' \
        '.tasks/cascade/lib.sh 83cb4592f5e97e85e74c820e0efe1059486cf3d14def4814d6ed80de6f71bbd7' \
        '.tasks/cascade/classes e9c3926e0f2b7324e4d9770b553ecac24df39273813eb33cf60716ef43f54c10' \
        '.tasks/cascade/cascade.sh 4f0f4e44b62c9906f6780f645760729c22403bb14c6d8bf922dc02eb231e1717'
      ;;
    opm-operator)
      printf '%s\n' '.tasks/cascade/pins.sh 3ec912b5736303f1a74dc6d457e4edae7bc3868129a839ddd3fc7c82068e3825' \
        '.tasks/cascade/lib.sh d72bca993a94d836cb91959b869fdeba5a0d9043a1263af0ecef7135d0f3b7aa' \
        '.tasks/cascade/classes d761876b3bafc8078207f8aae04b5beb2da1c8a821cd529e4ebba2af16f1ba40' \
        '.tasks/cascade/cascade.sh f741dec56ae8d5f2dce214b057e7ce4cdb35fc83c359e3c2802419d62c8b94c6'
      ;;
    cli)
      printf '%s\n' '.tasks/cascade/pins.sh 3c3f50ed302da918627a89459de330b1e18c7d449d0b748db90fc36f029ae3e1' \
        '.tasks/cascade/classes 4a0a74ffea8d3415b2edcb634ab143a7d84011bc7da0eecf39f3d66536d0e528' \
        '.tasks/cascade/cascade.sh 55223391fbc6a8df74360b9e3305fe410aa2319aebb1d1246cfb305f544e0387'
      ;;
    cascade-sandbox-down)
      printf '%s\n' '.tasks/cascade/pins.sh 70791e2e9c6124a01bdddfd5647c9e5fde6283109c2ff61bd082efd619b51147' \
        '.tasks/cascade/classes 921a950ca5ad36fa5a4fc0802d4dd8d2d915633c04fc22bbfd0976b60e2d19f7'
      ;;
    *) return 1 ;;
  esac
}

# The receivers cascade-mirror-drift.yml reads: every product receiver. The
# sandbox is archived and private, so a run's token cannot read it.
MIRROR_RECEIVERS="catalog_opm library opm-operator cli"

# mirror_stale_text <receiver> <path> <have> <want>: the refusal both checks
# print. <have> is a sha256 or "missing".
mirror_stale_text() {
  printf 'the .github mirror of %s is stale: %s on its main has sha256 %s, the mirror was written from %s; update the mirror and mirror_sources in wiring/lib.sh, then move the .github pin' \
    "$1" "$2" "$3" "$4"
}

# --- tokens and repo code -----------------------------------------------------

# run_repo_code <command...>: runs code from the calling repo (its tasks, its
# pins.sh) with every token and git auth header removed from its environment,
# and with no variable naming a runner command file (GITHUB_ENV, GITHUB_PATH,
# GITHUB_OUTPUT, GITHUB_STEP_SUMMARY, GITHUB_STATE) or an Actions service
# (every ACTIONS_*), so a task cannot set the step's outputs, environment or
# PATH through them. This stops a task that honours those variables; it is no
# boundary against hostile code, which can still find the files on disk or
# leave a process running into later steps of the job. So no compute step
# after the first one that runs repo code holds a token, and every later job
# treats what compute wrote from then on as untrusted.
run_repo_code() {
  local v
  local -a un=(-u GH_TOKEN -u GITHUB_TOKEN -u CASCADE_READ_TOKEN -u CASCADE_APP_TOKEN
    -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS
    -u GITHUB_ENV -u GITHUB_PATH -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY -u GITHUB_STATE)
  while IFS= read -r v; do
    case "$v" in ACTIONS_* | GIT_CONFIG_KEY_* | GIT_CONFIG_VALUE_*) un+=(-u "$v") ;; esac
  done < <(compgen -e)
  env "${un[@]}" "$@"
}

# auth_b64 <token>: the base64 of the basic-auth pair git sends.
auth_b64() { printf 'x-access-token:%s' "$1" | base64 | tr -d '\n'; }

# mask_read_token: masks the read header in the job log. Called once per
# step, with stdout going to the log.
mask_read_token() {
  if [ -n "${CASCADE_READ_TOKEN:-}" ]; then printf '::add-mask::%s\n' "$(auth_b64 "$CASCADE_READ_TOKEN")"; fi
}

# git_read <git args...>: a git call that may need to read a private repo.
# The GITHUB_TOKEN header reaches only this one git process, through the
# environment, never .git/config.
git_read() {
  if [ -n "${CASCADE_READ_TOKEN:-}" ]; then
    (
      GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.https://github.com/.extraheader \
        GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $(auth_b64 "$CASCADE_READ_TOKEN")" \
        GIT_TERMINAL_PROMPT=0 exec git "$@"
    )
  else
    GIT_TERMINAL_PROMPT=0 git "$@"
  fi
}

# --- payload ------------------------------------------------------------------

# validate_payload <receiver> <json>: exit 0 with P_SOURCE, P_TAGS (space
# joined) and P_EXPECT set, or exit 1 with P_REASON. Unknown keys are
# ignored. Exit 2 when the receiver is not a cascade receiver.
validate_payload() {
  local recv="$1" json="$2" allowed src n last
  P_SOURCE="" P_TAGS="" P_EXPECT="" P_REASON=""
  allowed=$(receiver_sources "$recv") || return 2
  if ! jq -e 'type == "object"' <<<"$json" >/dev/null 2>&1; then
    P_REASON="the payload is not a JSON object"
    return 1
  fi
  if ! jq -e '(.source | type) == "string"' <<<"$json" >/dev/null; then
    P_REASON="source is not a string"
    return 1
  fi
  src=$(jq -r '.source' <<<"$json")
  if [[ " $allowed " != *" $src "* ]]; then
    P_REASON="source \`$(safe_text "$src")\` is not accepted by $recv"
    return 1
  fi
  if ! jq -e '(.tags | type) == "array" and (.tags | length) >= 1 and (.tags | length) <= 8 and all(.tags[]; type == "string")' <<<"$json" >/dev/null; then
    P_REASON="tags is not an array of 1 to 8 strings"
    return 1
  fi
  # A control character anywhere (a newline above all) refuses the payload:
  # jq's regex $ matches before a final newline, and command substitution
  # drops trailing ones, so "v1.0.0\n" would otherwise pass as v1.0.0.
  if ! jq -e '[.source, .tags[]] | all(explode | all(. >= 32 and . != 127))' <<<"$json" >/dev/null 2>&1; then
    P_REASON="the source or a tag holds a control character"
    return 1
  fi
  # Each tag whole, NUL-delimited, through valid_tag's anchored bash match.
  local t
  n=0
  while IFS= read -r -d '' t; do
    valid_tag "$src" "$t" || n=$((n + 1))
  done < <(jq -j '.tags[] | ., "\u0000"' <<<"$json")
  if [ "$n" != 0 ]; then
    P_REASON="$n tag(s) do not match the $(safe_text "$src") tag shape"
    return 1
  fi
  P_SOURCE="$src"
  P_TAGS=$(jq -r '.tags | join(" ")' <<<"$json")
  last=$(jq -r '.tags[-1]' <<<"$json")
  P_EXPECT=$(expect_pair "$src" "$last")
}

# --- the cascade PR -----------------------------------------------------------

PR_FIELDS=number,title,body,labels,headRefOid,isCrossRepository,headRepositoryOwner,author

# cascade_pr <repo>: prints the open cascade PR as one JSON object, or
# nothing. Only the bot's own same-repo PR on deps/cascade counts: a fork PR
# or a human PR from a branch of that name is never read further. Exit 1 on
# an API error or more than one match.
cascade_pr() {
  local out n
  out=$(gh_ pr list -R "$ORG/$1" --head "$BRANCH" --base main --state open --json "$PR_FIELDS") \
    || { note "cannot list the open $BRANCH PRs of $1"; return 1; }
  out=$(jq -c --arg org "$ORG" --arg bot "$BOT_LOGIN" \
    '[.[] | select(.isCrossRepository == false and .headRepositoryOwner.login == $org and .author.login == $bot)]' <<<"$out") \
    || { note "cannot parse the PR list of $1"; return 1; }
  n=$(jq length <<<"$out")
  case "$n" in
    0) ;;
    1) jq -c '.[0]' <<<"$out" ;;
    *) note "more than one cascade PR in $1"; return 1 ;;
  esac
}

# --- Notes and the title marker -----------------------------------------------

# extract_notes <body file> <notes file>: every byte after the first line
# equal to the Notes marker (one trailing CR ignored), or the whole body
# when no such line exists.
extract_notes() {
  local n
  n=$(grep -n -m 1 -x -F -e "$NOTES_MARKER" -e "$NOTES_MARKER"$'\r' -- "$1" | cut -d: -f1) || true
  if [ -n "$n" ]; then
    tail -n "+$((n + 1))" -- "$1" >"$2"
  else
    cat -- "$1" >"$2"
  fi
}

# body_above_notes <body file>: the body up to, not including, the Notes
# marker line (the whole body without one).
body_above_notes() {
  local n
  n=$(grep -n -m 1 -x -F -e "$NOTES_MARKER" -e "$NOTES_MARKER"$'\r' -- "$1" | cut -d: -f1) || true
  if [ -n "$n" ]; then head -n "$((n - 1))" -- "$1"; else cat -- "$1"; fi
}

# title_marker <body file>: the <T> of the first `<!-- cascade-title: <T> -->`
# line above the Notes marker, one trailing CR ignored; empty without one.
title_marker() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ "$line" != "$NOTES_MARKER" ] || return 0
    if [[ $line =~ ^'<!-- cascade-title: '(.*)' -->'$ ]]; then
      printf '%s' "${BASH_REMATCH[1]}"
      return 0
    fi
  done <"$1"
}

# --- titles -------------------------------------------------------------------

# type_rank <title>: ci 1, test 2, fix 3, feat 4, anything else 0.
type_rank() {
  if [[ $1 =~ ^([a-z]+)(\([^\)]*\))?(!)?:\  ]]; then
    case "${BASH_REMATCH[1]}" in
      ci) echo 1 ;;
      test) echo 2 ;;
      fix) echo 3 ;;
      feat) echo 4 ;;
      *) echo 0 ;;
    esac
  else
    echo 0
  fi
}

# type_scope <title>: the type and scope, `fix(deps)` for `fix(deps): x`.
type_scope() { printf '%s' "${1%%: *}"; }

# final_title <has pr 0|1> <T_old> <T_marker> <T_computed>: sets FINAL_TITLE
# and TITLE_RISE (1 when a kept human title ranks below the computed class
# that rose since the last run). Once a human retitled the PR, its title is
# kept for good.
final_title() {
  local pr="$1" old="$2" marker="$3" computed="$4"
  TITLE_RISE=0
  if [ "$pr" = 1 ] && [ -n "$marker" ] && [ "$old" != "$marker" ]; then
    FINAL_TITLE="$old"
    if [ "$(type_rank "$computed")" -gt "$(type_rank "$old")" ] && [ "$(type_rank "$computed")" -gt "$(type_rank "$marker")" ]; then
      TITLE_RISE=1
    fi
  else
    FINAL_TITLE="$computed"
  fi
}

# Computed titles are one of the resolver's three types.
COMPUTED_TITLE_RE='^(fix\(deps\)|test\(fixtures\)|ci\(deps\)): '

# --- the mention lint ---------------------------------------------------------

# lint_text <surface> <text>: exit 1 naming the surface when the text holds
# a bare mention, or when grep cannot run the pattern.
lint_text() {
  local rc=0
  printf '%s\n' "$2" | grep -qP -- "$MENTION_RE" || rc=$?
  case "$rc" in
    0) note "mention lint: the $1 holds a bare mention"; return 1 ;;
    1) return 0 ;;
    *) note "mention lint: grep -P failed on the $1 (exit $rc)"; return 1 ;;
  esac
}

# --- comments -----------------------------------------------------------------

# path_list <path>...: each path, made safe, in backticks, comma-separated.
path_list() {
  local p out="" sep=""
  for p in "$@"; do
    out="$out$sep\`$(safe_text "$p")\`"
    sep=", "
  done
  printf '%s' "$out"
}

# comment_text <kind> [<value>]: the fixed comment texts. <value> is a path
# list (conflict-merge, conflict-workflows), a type (title-rise) or a PR
# number (continued).
comment_text() {
  case "$1" in
    conflict-merge) printf '%s' "The cascade could not merge \`main\` into this branch. Conflicting paths: $2. Run \`git merge origin/main\` locally, resolve, push, then remove \`deps-cascade:conflict\`." ;;
    conflict-workflows) printf '%s' "\`main\` changed workflow files since this branch's last update ($2), or this branch changes workflow files. The cascade App has no Workflows permission, so it cannot update this branch. Run \`git merge origin/main\` locally, push, then remove \`deps-cascade:conflict\`." ;;
    recreate) printf '%s' "\`main\` changed workflow files since this branch was built. The cascade App has no Workflows permission, so it rebuilt the branch under a new PR. The Notes were carried over." ;;
    close) printf '%s' "No diff against \`main\` any more. Closed by the release cascade." ;;
    too-long) printf '%s' "The PR body is over GitHub's 65000-byte limit because of the Notes. The bot never truncates Notes, so it cannot update this PR. Trim the text below the Notes marker; the next run continues." ;;
    title-rise) printf '%s' "The bot now titles this change \`$2\`, which ranks above the current title. A human set the current title, so the bot keeps it. Retitle the PR if this change should release." ;;
    continued) printf '%s' "Continued in #$2." ;;
    *) return 1 ;;
  esac
}

# --- the workflows guard and the action table ---------------------------------

# wf_guard <rule> <mode> <D1> <D2>: the action a planned push becomes, given
# the workflow files that differ from main's tip (D1) and from the old tip in
# place (D2, newline lists). Prints push, recreate, conflict or error.
wf_guard() {
  local rule="$1" mode="$2" d1="$3" d2="$4"
  case "$mode" in
    fresh)
      if [ -z "$d1" ]; then echo push; else echo error; fi ;;
    rebuild)
      if [ -n "$d1" ]; then echo error
      elif [ -z "$d2" ] || [ "$rule" = tree ]; then echo push
      else echo recreate
      fi ;;
    recreate)
      if [ -z "$d1" ]; then echo recreate; else echo error; fi ;;
    merge)
      if [ -n "$d1" ]; then echo conflict
      elif [ -z "$d2" ] || [ "$rule" = tree ]; then echo push
      else echo conflict
      fi ;;
    *) echo error ;;
  esac
}

# action_for <mode> <too long 0|1> <tree equals main 0|1> <pr open 0|1> <OLD set 0|1>
action_for() {
  case "$1" in
    skip) echo skip; return ;;
    conflict) echo conflict; return ;;
  esac
  if [ "$2" = 1 ]; then echo too_long
  elif [ "$3" = 1 ] && { [ "$4" = 1 ] || [ "$5" = 1 ]; }; then echo close
  elif [ "$3" = 1 ]; then echo noop
  else echo push
  fi
}

# --- gate statuses ------------------------------------------------------------

# truncate_desc <text>: at most 140 characters, cut with an ellipsis.
truncate_desc() {
  local LC_ALL=C.UTF-8 d="$1"
  if [ "${#d}" -gt 140 ]; then d="${d:0:139}…"; fi
  printf '%s' "$d"
}

# status_for <mode warn|enforce> <state ok|problem|error> <message>: prints
# "<state>\t<description>".
status_for() {
  local st desc
  case "$2:$1" in
    ok:*) st=success desc="$3" ;;
    problem:warn) st=success desc="WARN: $3" ;;
    problem:enforce) st=failure desc="$3" ;;
    error:warn) st=success desc="WARN: gate could not run, see the run" ;;
    error:enforce) st=error desc="could not evaluate, see the run" ;;
    *) return 1 ;;
  esac
  printf '%s\t%s\n' "$st" "$(truncate_desc "$desc")"
}

valid_mode() { [ "$1" = warn ] || [ "$1" = enforce ]; }

# --- scratch files ------------------------------------------------------------

# check_scratch <dir>: refuses a scratch directory inside the repo checkout
# or the org .github checkout.
check_scratch() {
  local t r o
  [ -n "$1" ] || die "CASCADE_T is not set"
  t=$(realpath -m -- "$1")
  r=$(realpath -m -- "${CASCADE_REPO_DIR:-repo}")
  o=$(realpath -m -- "$WIRING_DIR/../../../..")
  case "$t/" in "$r"/* | "$o"/*) die "CASCADE_T \`$1\` is inside a checkout" ;; esac
}

WIRING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

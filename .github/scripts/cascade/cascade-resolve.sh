#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Release-cascade resolver: the one implementation every repo's
# `task deps:cascade` (and the cascade receive workflow) asks which upstream
# version a pin moves to, whether a pin is held or frozen, and what the
# cascade PR is called. Design: workspace RELEASING.md, section "The cascade".
#
# Usage:
#   cascade-resolve.sh newest <kind> [<coordinate>] --current <v> [--asset NAME]... [--pre]
#                             [--repo-root DIR] [--expect <v>] [--max-wait SECONDS] [--json]
#   cascade-resolve.sh published <kind> [<coordinate>] <v-or-tag> [--asset NAME]...
#   cascade-resolve.sh pin-of <module>@v<N> <v> <dep-module>@v<M>
#   cascade-resolve.sh language-of <module>@v<N> <v>
#   cascade-resolve.sh frozen <pin-key> [--repo-root DIR]
#   cascade-resolve.sh is-frozen <repo-relative-path> <pin-key> [--repo-root DIR]
#   cascade-resolve.sh hold <pin-key> [--repo-root DIR]
#   cascade-resolve.sh check-files [--repo-root DIR]
#   cascade-resolve.sh semver-cmp <a> <b>
#   cascade-resolve.sh semver-sort              (stdin, one version per line)
#   cascade-resolve.sh next-patch <v>
#   cascade-resolve.sh classify --classes FILE  (stdin paths; prints "<class>\t<path>")
#   cascade-resolve.sh title --classes FILE --pins SCRIPT [--base REF] [--repo-root DIR]
#   cascade-resolve.sh body  --classes FILE --pins SCRIPT [--base REF] [--repo-root DIR]
#                            [--warnings FILE]
#
# Kinds: cue <module>@v<N> (GHCR), go <module path> (Go proxy), release <repo>
# --asset NAME... (git tags plus release downloads), opm-cli (release cli with
# its two assets), oci <image repo> (published only; the tag is used as given).
#
# Exit status (every subcommand):
#   0  success; for newest a newer version was printed; for predicates: yes
#   3  nothing to do or no; for newest: stay, stdout empty; for title: empty diff
#   1  error (network after retries, unexpected HTTP status, malformed steering
#      file, missing tool, mention lint); never a guessed or older version
#   2  usage error (unknown subcommand or flag, missing or malformed argument)
#
# Tools: bash, coreutils, curl, jq, git, mikefarah yq v4. No credentials: GHCR
# is read with its anonymous pull token, GitHub through git and anonymous
# downloads, never api.github.com.
#
# Environment: CASCADE_WARNINGS (append "<pin-key>\t<message>" per warning),
# CASCADE_GOPROXY (default https://proxy.golang.org), CASCADE_TODAY
# (YYYY-MM-DD), CASCADE_SLEEP (default sleep), CASCADE_MAX_WAIT (default 600),
# CASCADE_BASE, CASCADE_SOURCE, CASCADE_TAGS, CASCADE_NOTES_FILE.
set -euo pipefail
export LC_ALL=C

CASCADE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=lib/common.sh
. "$CASCADE_LIB/common.sh"
# shellcheck source=lib/semver.sh
. "$CASCADE_LIB/semver.sh"
# shellcheck source=lib/files.sh
. "$CASCADE_LIB/files.sh"
# shellcheck source=lib/http.sh
. "$CASCADE_LIB/http.sh"
# shellcheck source=lib/ghcr.sh
. "$CASCADE_LIB/ghcr.sh"
# shellcheck source=lib/goproxy.sh
. "$CASCADE_LIB/goproxy.sh"
# shellcheck source=lib/release.sh
. "$CASCADE_LIB/release.sh"
# shellcheck source=lib/query.sh
. "$CASCADE_LIB/query.sh"
# shellcheck source=lib/newest.sh
. "$CASCADE_LIB/newest.sh"
# shellcheck source=lib/classify.sh
. "$CASCADE_LIB/classify.sh"
# shellcheck source=lib/prtext.sh
. "$CASCADE_LIB/prtext.sh"

# Parsed flags.
REPO_ROOT=.
CURRENT=""
ASSETS=()
PRE=0
EXPECT=""
MAX_WAIT=""
JSON=0
CLASSES=""
PINS=""
BASE=""
WARN_FILE=""
POS=()

parse_args() { # parse_args <allowed flags, space-separated> <args...>
  local allowed=" $1 " flag
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --*)
        flag="$1"
        case "$allowed" in *" $flag "*) ;; *) usage "unknown flag $flag for $CMD" ;; esac
        case "$flag" in
          --pre) PRE=1; shift; continue ;;
          --json) JSON=1; shift; continue ;;
        esac
        [ $# -ge 2 ] || usage "$flag needs a value"
        case "$flag" in
          --repo-root) REPO_ROOT="$2" ;;
          --current) CURRENT="$2" ;;
          --asset) ASSETS+=("$2") ;;
          --expect) EXPECT="$2" ;;
          --max-wait) MAX_WAIT="$2" ;;
          --classes) CLASSES="$2" ;;
          --pins) PINS="$2" ;;
          --base) BASE="$2" ;;
          --warnings) WARN_FILE="$2" ;;
        esac
        shift 2
        ;;
      *) POS+=("$1"); shift ;;
    esac
  done
}

npos() { # npos <count>: exactly <count> positional arguments
  [ "${#POS[@]}" -eq "$1" ] || usage "$CMD takes $1 argument(s), got ${#POS[@]}"
}

repo_root() {
  [ -d "$REPO_ROOT" ] || usage "--repo-root \`$REPO_ROOT\` is not a directory"
}

CMD="${1:-}"
[ -n "$CMD" ] || usage "usage: cascade-resolve.sh <subcommand> ... (see the header of this script)"
shift

case "$CMD" in
  newest)
    parse_args "--current --asset --pre --repo-root --expect --max-wait --json" "$@"
    repo_root
    cmd_newest
    ;;
  published)
    parse_args "--asset" "$@"
    cmd_published
    ;;
  pin-of)
    parse_args "" "$@"
    npos 3
    cmd_pin_of "${POS[@]}"
    ;;
  language-of)
    parse_args "" "$@"
    npos 2
    cmd_language_of "${POS[@]}"
    ;;
  frozen)
    parse_args "--repo-root" "$@"
    npos 1
    repo_root
    [ -n "${POS[0]}" ] || usage "frozen needs a pin key"
    frozen_paths "${POS[0]}"
    ;;
  is-frozen)
    parse_args "--repo-root" "$@"
    npos 2
    repo_root
    [ -n "${POS[0]}" ] && [ -n "${POS[1]}" ] || usage "is-frozen needs a path and a pin key"
    if is_frozen "${POS[0]}" "${POS[1]}"; then exit 0; fi
    exit 3
    ;;
  hold)
    parse_args "--repo-root" "$@"
    npos 1
    repo_root
    [ -n "${POS[0]}" ] || usage "hold needs a pin key"
    hold_lookup "${POS[0]}"
    [ -n "$HOLD_MAX" ] || exit 3
    printf '%s\n' "$HOLD_MAX"
    ;;
  check-files)
    parse_args "--repo-root" "$@"
    npos 0
    repo_root
    load_frozen
    load_holds
    ;;
  semver-cmp)
    parse_args "" "$@"
    npos 2
    need_version "${POS[0]}" "version"
    need_version "${POS[1]}" "version"
    semver_cmp "${POS[0]}" "${POS[1]}"
    printf '%s\n' "$CMP"
    ;;
  semver-sort)
    parse_args "" "$@"
    npos 0
    SORTED=()
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      need_version "$line" "version"
      SORTED+=("$line")
    done
    semver_sort
    [ "${#SORTED[@]}" -eq 0 ] || printf '%s\n' "${SORTED[@]}"
    ;;
  next-patch)
    parse_args "" "$@"
    npos 1
    next_patch "${POS[0]}"
    printf '%s\n' "$NEXT"
    ;;
  classify)
    parse_args "--classes" "$@"
    npos 0
    cmd_classify
    ;;
  title)
    parse_args "--classes --pins --base --repo-root" "$@"
    npos 0
    repo_root
    cmd_title
    ;;
  body)
    parse_args "--classes --pins --base --repo-root --warnings" "$@"
    npos 0
    repo_root
    cmd_body
    ;;
  *) usage "unknown subcommand $CMD" ;;
esac

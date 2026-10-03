# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the other lib files and the entry point
# Query kinds and the lookups that need no candidate walk: published, pin-of
# and language-of.
#
#   kind     coordinate                     pin key
#   cue      <module path>@v<N>             the coordinate
#   go       <module path> (/vN for N>=2)   the coordinate
#   release  <repo> plus --asset NAME...    github.com/open-platform-model/<repo>
#   opm-cli  none                           github.com/open-platform-model/cli
#   oci      <image repo under ghcr.io>     the coordinate (published only)

CUE_COORD_RE='^[a-z0-9][a-z0-9.-]*(/[a-z0-9][a-z0-9._-]*)*@v(0|[1-9][0-9]*)$'
GO_PATH_RE='^[a-z0-9][a-z0-9.-]*(/[A-Za-z0-9][A-Za-z0-9._~-]*)+$'
REPO_RE='^[A-Za-z0-9][A-Za-z0-9._-]*$'
ASSET_RE='^[A-Za-z0-9][A-Za-z0-9._+-]*$'
OCI_REPO_RE='^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)+$'
OCI_TAG_RE='^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$'

# parse_kind <kind> <positional...>: sets KIND, COORD, PIN_KEY, the per-kind
# globals (CUE_REPO, CUE_MAJOR, GO_PATH, REL_REPO) and REST (what is left).
parse_kind() {
  [ $# -ge 1 ] || usage "$CMD needs a kind (cue, go, release, opm-cli or oci)"
  KIND="$1"
  shift
  COORD=""
  case "$KIND" in
    cue | go | release | oci)
      [ $# -ge 1 ] || usage "$KIND needs a coordinate"
      COORD="$1"
      shift
      ;;
    opm-cli) ;;
    *) usage "unknown kind $KIND" ;;
  esac
  [ "$KIND" = release ] || [ "${#ASSETS[@]}" -eq 0 ] || usage "--asset applies only to the release kind"
  case "$KIND" in
    cue)
      [[ $COORD =~ $CUE_COORD_RE ]] || usage "cue coordinate \`$COORD\` is not <module path>@v<N>"
      CUE_REPO="open-platform-model/${COORD%@v*}"
      CUE_MAJOR="${COORD##*@v}"
      PIN_KEY="$COORD"
      ;;
    go)
      [[ $COORD =~ $GO_PATH_RE ]] || usage "go module path \`$COORD\` is malformed"
      GO_PATH="$COORD"
      PIN_KEY="$COORD"
      ;;
    release)
      [[ $COORD =~ $REPO_RE ]] || usage "release repo \`$COORD\` is malformed"
      [ "${#ASSETS[@]}" -gt 0 ] || usage "release needs at least one --asset"
      local a
      for a in "${ASSETS[@]}"; do [[ $a =~ $ASSET_RE ]] || usage "asset \`$a\` is malformed"; done
      REL_REPO="$COORD"
      PIN_KEY="github.com/open-platform-model/$COORD"
      ;;
    opm-cli)
      REL_REPO=cli
      ASSETS=(opm-linux-amd64.tar.gz checksums.txt)
      PIN_KEY="github.com/open-platform-model/cli"
      ;;
    oci)
      [[ $COORD =~ $OCI_REPO_RE ]] || usage "oci repo \`$COORD\` is malformed"
      PIN_KEY="$COORD"
      ;;
  esac
  REST=("$@")
}

# go_major_ok <current major>: the module path's /vN suffix must agree with
# the major (none for 0 and 1).
go_major_ok() {
  local m="$1" suffix=""
  [[ $GO_PATH =~ /v([0-9]+)$ ]] && suffix="${BASH_REMATCH[1]}"
  if [ "$m" -ge 2 ]; then [ "$suffix" = "$m" ]; else [ -z "$suffix" ]; fi
}

# check_published <v>: sets PUB for the current kind (cached per version).
# Returns 1 when the package is unknown or private on GHCR.
declare -A PUB_CACHE=()
check_published() {
  local v="$1"
  if [ -n "${PUB_CACHE[$v]:-}" ]; then PUB="${PUB_CACHE[$v]}"; return 0; fi
  case "$KIND" in
    cue) ghcr_head "$CUE_REPO" "$v" "$MANIFEST_TYPE" || return 1 ;;
    oci) ghcr_head "$COORD" "$v" "$MANIFEST_TYPE, $INDEX_TYPE" || return 1 ;;
    go) goproxy_info "$GO_PATH" "$v" ;;
    release | opm-cli)
      release_published "$REL_REPO" "$v" "${ASSETS[@]}"
      [ "$PUB" = 1 ] || note "skip \`$v\`: \`$MISSING\` is not downloadable (draft, or the asset was never attached)"
      ;;
  esac
  PUB_CACHE[$v]="$PUB"
}

cmd_published() {
  parse_kind "${POS[@]}"
  [ "${#REST[@]}" -eq 1 ] || usage "published takes one version or tag after the kind and coordinate"
  local v="${REST[0]}"
  if [ "$KIND" = oci ]; then
    [[ $v =~ $OCI_TAG_RE ]] || usage "oci tag \`$v\` is malformed"
  else
    need_version "$v" "version"
  fi
  case "$KIND" in
    cue | oci) need_tools curl jq ;;
    go) need_tools curl ;;
    *) need_tools curl git ;;
  esac
  if ! check_published "$v"; then
    local repo="$COORD"
    [ "$KIND" = oci ] || repo="$CUE_REPO"
    warn "$PIN_KEY" "\`$repo\` is unknown on GHCR or the package may be private"
    exit 3
  fi
  [ "$PUB" = 1 ] || exit 3
}

# modfile_dep <file> <dep>: prints the first v: inside the dep's own block.
# Exit 3 when the dep is absent, 4 when it appears more than once, 5 when its
# block has no v:.
modfile_dep() {
  awk -v key="\"$2\"" '
    { text = text $0 "\n" }
    END {
      n = 0; rest = text; pos = 0; first = 0
      while ((i = index(rest, key)) > 0) {
        after = substr(rest, i + length(key))
        if (after ~ /^[ \t]*:[ \t]*\{/) { n++; if (n == 1) first = pos + i }
        pos += i + length(key) - 1
        rest = substr(rest, i + length(key))
      }
      if (n == 0) exit 3
      if (n > 1) exit 4
      block = substr(text, first + length(key))
      block = substr(block, index(block, "{") + 1)
      close_at = index(block, "}")
      if (close_at > 0) block = substr(block, 1, close_at - 1)
      if (match(block, /(^|[^A-Za-z0-9_])v:[ \t]*"[^"]*"/) == 0) exit 5
      m = substr(block, RSTART, RLENGTH)
      sub(/^.*v:[ \t]*"/, "", m)
      sub(/"$/, "", m)
      print m
    }' "$1"
}

# modfile_language <file>: prints language.version; exit 3 when absent.
modfile_language() {
  awk '
    { text = text $0 "\n" }
    END {
      if (match(text, /(^|\n)language:[ \t]*\{[^}]*\}/) == 0) exit 3
      block = substr(text, RSTART, RLENGTH)
      if (match(block, /version:[ \t]*"[^"]*"/) == 0) exit 3
      m = substr(block, RSTART, RLENGTH)
      sub(/^version:[ \t]*"/, "", m)
      sub(/"$/, "", m)
      print m
    }' "$1"
}

cmd_pin_of() {
  local mod="$1" v="$2" dep="$3" out rc=0
  [[ $mod =~ $CUE_COORD_RE ]] || usage "module \`$mod\` is not <module path>@v<N>"
  [[ $dep =~ $CUE_COORD_RE ]] || usage "dep \`$dep\` is not <module path>@v<M>"
  need_version "$v" "version"
  need_tools curl jq
  ghcr_modulefile "$mod" "$v"
  out=$(modfile_dep "$MODFILE" "$dep") || rc=$?
  case "$rc" in
    0) ;;
    3) exit 3 ;;
    4) die "\`$mod\` \`$v\` pins \`$dep\` more than once" ;;
    *) die "the \`$dep\` entry in \`$mod\` \`$v\` has no \`v:\` version" ;;
  esac
  is_version "$out" || die "\`$mod\` \`$v\` pins \`$dep\` at \`$out\`, not a SemVer version"
  printf '%s\n' "$out"
}

cmd_language_of() {
  local mod="$1" v="$2" out rc=0
  [[ $mod =~ $CUE_COORD_RE ]] || usage "module \`$mod\` is not <module path>@v<N>"
  need_version "$v" "version"
  need_tools curl jq
  ghcr_modulefile "$mod" "$v"
  out=$(modfile_language "$MODFILE") || rc=$?
  [ "$rc" = 0 ] || exit 3
  is_version "$out" || die "\`$mod\` \`$v\` has language version \`$out\`, not a SemVer version"
  printf '%s\n' "$out"
}

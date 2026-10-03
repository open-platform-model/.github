# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the other lib files and the entry point
# Shared helpers for cascade-resolve.sh: diagnostics, warnings, version
# syntax, tool checks and the per-run scratch directory.

# Every version the resolver reads or prints: full v-prefixed SemVer.
VERSION_RE='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

# Warnings collected in this run, for --json.
WARNINGS=()

die() { # die <message> [exit code]
  printf 'cascade-resolve: %s\n' "$1" >&2
  exit "${2:-1}"
}

usage() { die "$1" 2; }

note() { printf 'cascade-resolve: %s\n' "$1" >&2; }

# warn <pin-key> <message>: stderr line, plus one "<pin-key>\t<message>" line
# in $CASCADE_WARNINGS when it is set. Messages put versions and paths in
# backticks and never hold an @ that a word character does not precede, so
# they pass the cascade PR's mention lint.
warn() {
  printf 'cascade-resolve: warning: %s\n' "$2" >&2
  WARNINGS+=("$2")
  if [ -n "${CASCADE_WARNINGS:-}" ]; then
    printf '%s\t%s\n' "$1" "$2" >>"$CASCADE_WARNINGS"
  fi
}

is_version() { [[ $1 =~ $VERSION_RE ]]; }

need_version() { # need_version <value> <what>: exit 2 unless a valid version
  is_version "$1" || usage "$2 \`$1\` is not a v-prefixed SemVer version"
}

# safe_text <value>: the value with every character outside [A-Za-z0-9._/-]
# replaced by ?, cut to 64 characters. Used to name untrusted input (the
# dispatch payload) in a warning without letting it inject a mention or
# Markdown.
safe_text() {
  local v="${1:0:64}"
  printf '%s' "${v//[^A-Za-z0-9._\/-]/?}"
}

# Tools are checked once, when a subcommand first needs them.
TOOLS_OK=" "
need_tools() {
  local t
  for t in "$@"; do
    case "$TOOLS_OK" in *" $t "*) continue ;; esac
    command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"
    if [ "$t" = yq ]; then
      local v
      v=$(yq --version 2>&1) || die "missing tool: mikefarah yq v4 (yq --version failed)"
      case "$v" in
        *mikefarah*" v4."* | *mikefarah*" 4."*) ;;
        *) die "missing tool: mikefarah yq v4 (found: $v)" ;;
      esac
    fi
    TOOLS_OK="$TOOLS_OK$t "
  done
}

# work_dir: create the per-run scratch directory once; removed on exit.
WORK=""
work_dir() {
  if [ -z "$WORK" ]; then
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/cascade-resolve.XXXXXX")
    trap 'rm -rf "$WORK"' EXIT
  fi
}

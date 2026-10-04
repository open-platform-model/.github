# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the other lib files and the entry point
# The path-class map (.tasks/cascade/classes in each repo). Each line is
# "<class> <pattern>"; # starts a comment. The first matching line wins and a
# path no line matches is shipped. Pattern forms:
#   dir/        every path under dir/
#   a/b.yaml    exactly that path (has a /, no *)
#   name        exactly that root-level path (no /, no *)
#   *_test.go   a basename glob at any depth (no /, has *)
#   **/name/    any path with a directory segment "name", at any depth

# load_classes <file>: sets CL_CLASS, CL_KIND (dir, exact, glob, segment) and
# CL_PAT. Any other line shape is exit 1 naming the line.
load_classes() {
  local f="$1" line n=0 cls pat extra kind
  [ -f "$f" ] || die "classes file \`$f\` not found"
  CL_CLASS=() CL_KIND=() CL_PAT=()
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%%#*}"
    cls="" pat="" extra=""
    read -r cls pat extra <<<"$line" || true
    [ -n "$cls" ] || continue
    if ! { [ -n "$pat" ] && [ -z "$extra" ]; }; then die "classes line $n: want \"<class> <pattern>\""; fi
    case "$cls" in
      release-tool | test | shipped) ;;
      *) die "classes line $n: unknown class \`$cls\`" ;;
    esac
    [[ $pat != /* ]] || die "classes line $n: pattern \`$pat\` must be repo-relative"
    if [[ $pat =~ ^\*\*/[^/*]+/$ ]]; then
      kind=segment
      pat="${pat#\*\*/}"
      pat="${pat%/}"
    elif [[ $pat == */ && $pat != *'*'* ]]; then kind=dir
    elif [[ $pat != *'*'* ]]; then kind=exact
    elif [[ $pat != */* ]]; then kind=glob
    else die "classes line $n: pattern \`$pat\` is none of the known forms"
    fi
    CL_CLASS+=("$cls") CL_KIND+=("$kind") CL_PAT+=("$pat")
  done <"$f"
}

# classify_path <path>: sets CLASS.
classify_path() {
  local p="$1" i
  # shellcheck disable=SC2053 # a glob pattern is matched as a glob on purpose
  for i in "${!CL_KIND[@]}"; do
    case "${CL_KIND[i]}" in
      dir) [[ $p == "${CL_PAT[i]}"* ]] || continue ;;
      exact) [ "$p" = "${CL_PAT[i]}" ] || continue ;;
      glob) [[ ${p##*/} == ${CL_PAT[i]} ]] || continue ;;
      segment) [[ /$p == */"${CL_PAT[i]}"/* ]] || continue ;;
    esac
    CLASS="${CL_CLASS[i]}"
    return 0
  done
  CLASS=shipped
}

cmd_classify() {
  [ -n "$CLASSES" ] || usage "classify needs --classes FILE"
  load_classes "$CLASSES"
  local p
  while IFS= read -r p || [ -n "$p" ]; do
    [ -n "$p" ] || continue
    classify_path "$p"
    printf '%s\t%s\n' "$CLASS" "$p"
  done
}

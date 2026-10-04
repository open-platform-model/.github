# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the other lib files and the entry point
# The cascade PR's title and body (workspace RELEASING.md, section "Title from
# diff class"), computed from the diff against the merge-base, the repo's
# path-class map and its pins.sh report. Deterministic: the same tree and
# environment give the same bytes.

# The prefix of mention-guard's own pattern: an @ that no word character or
# @ precedes, followed by a letter or digit, is a GitHub mention.
MENTION_RE='(?<![\w@])@[A-Za-z0-9]'
# The triggering sources body accepts. cmd_body adds the names in
# CASCADE_EXTRA_SOURCES, which only the sandbox receiver sets.
CASCADE_SOURCES=" core catalog_opm library opm-operator cli "
TAG_RE='^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$'

abs_path() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }

# split_tsv <line>: sets FIELDS to the tab-separated fields, empty ones kept.
split_tsv() {
  local rest="$1"
  FIELDS=()
  while [[ $rest == *$'\t'* ]]; do
    FIELDS+=("${rest%%$'\t'*}")
    rest="${rest#*$'\t'}"
  done
  FIELDS+=("$rest")
}

# read_pins <ref> <prefix>: runs the pins script and fills <prefix>_KEYS (in
# order), <prefix>_VER, <prefix>_DISPLAY, <prefix>_CLASS, <prefix>_LABELS.
read_pins() {
  local ref="$1" pfx="$2" out line n=0
  out=$("$PINS_ABS" "$ref") || die "\`$PINS\` $ref failed"
  local -n keys="${pfx}_KEYS" ver="${pfx}_VER" disp="${pfx}_DISPLAY" cls="${pfx}_CLASS" lab="${pfx}_LABELS"
  keys=()
  while IFS= read -r line; do
    n=$((n + 1))
    [ -n "$line" ] || continue
    split_tsv "$line"
    [ "${#FIELDS[@]}" -eq 5 ] || [ "${#FIELDS[@]}" -eq 4 ] \
      || die "\`$PINS\` $ref line $n: want <pin-key>, <display>, <class>, <version> and <labels> separated by tabs"
    local k="${FIELDS[0]}" d="${FIELDS[1]}" c="${FIELDS[2]}" v="${FIELDS[3]}" l="${FIELDS[4]:-}"
    if ! { [ -n "$k" ] && [ -n "$d" ]; }; then die "\`$PINS\` $ref line $n: empty pin key or display name"; fi
    case "$c" in release-tool | test | shipped) ;; *) die "\`$PINS\` $ref line $n: unknown class \`$c\`" ;; esac
    is_version "$v" || die "\`$PINS\` $ref line $n: \`$v\` is not a v-prefixed SemVer version"
    [ -z "${ver[$k]:-}" ] || die "\`$PINS\` $ref lists \`$k\` twice"
    keys+=("$k")
    # shellcheck disable=SC2004 # associative arrays reached through namerefs
    ver[$k]="$v" disp[$k]="$d" cls[$k]="$c" lab[$k]="$l"
  done <<<"$out"
}

# pr_compute: the diff, its classes and the moved pins. Sets CHANGED,
# N_SHIPPED, N_TEST, N_TOOL, MOVED (pin keys) and TITLE.
pr_compute() {
  [ -n "$CLASSES" ] || usage "$CMD needs --classes FILE"
  [ -n "$PINS" ] || usage "$CMD needs --pins SCRIPT"
  local base="${BASE:-${CASCADE_BASE:-origin/main}}"
  [[ $base != -* ]] || usage "the base ref \`$base\` must not start with -"
  need_tools git
  CLASSES_ABS=$(abs_path "$CLASSES")
  PINS_ABS=$(abs_path "$PINS")
  WARN_ABS=""
  [ -z "$WARN_FILE" ] || WARN_ABS=$(abs_path "$WARN_FILE")
  NOTES_ABS=""
  [ -z "${CASCADE_NOTES_FILE:-}" ] || NOTES_ABS=$(abs_path "$CASCADE_NOTES_FILE")
  work_dir
  cd "$REPO_ROOT" || die "cannot enter \`$REPO_ROOT\`"
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null) || die "\`$REPO_ROOT\` is not inside a git work tree"
  cd "$top" || die "cannot enter \`$top\`"
  if ! { [ -f "$PINS_ABS" ] && [ -x "$PINS_ABS" ]; }; then die "pins script \`$PINS\` is not an executable file"; fi
  load_classes "$CLASSES_ABS"

  M=$(git merge-base "$base" HEAD 2>/dev/null) || die "no merge-base between \`$base\` and HEAD"
  local p
  CHANGED=()
  git diff --name-only --no-renames -z "$M" -- >"$WORK/changed" || die "git diff against \`$M\` failed"
  git ls-files -z --others --exclude-standard >>"$WORK/changed" || die "git ls-files failed"
  while IFS= read -r -d '' p; do CHANGED+=("$p"); done < <(sort -zu "$WORK/changed")
  N_SHIPPED=0 N_TEST=0 N_TOOL=0
  for p in "${CHANGED[@]}"; do
    classify_path "$p"
    case "$CLASS" in
      shipped) N_SHIPPED=$((N_SHIPPED + 1)) ;;
      test) N_TEST=$((N_TEST + 1)) ;;
      release-tool) N_TOOL=$((N_TOOL + 1)) ;;
    esac
  done

  declare -gA B_VER=() B_DISPLAY=() B_CLASS=() B_LABELS=() W_VER=() W_DISPLAY=() W_CLASS=() W_LABELS=()
  declare -ga B_KEYS=() W_KEYS=()
  read_pins "$M" B
  read_pins WORKTREE W
  MOVED=()
  local k
  for k in "${W_KEYS[@]}"; do
    [ -n "${B_VER[$k]:-}" ] || continue
    [ "${B_VER[$k]}" = "${W_VER[$k]}" ] || MOVED+=("$k")
  done

  TITLE=""
  [ "${#CHANGED[@]}" -gt 0 ] || return 0
  local type subject n=${#MOVED[@]}
  if [ "$N_SHIPPED" -gt 0 ]; then type="fix(deps)"
  elif [ "$N_TEST" -gt 0 ]; then type="test(fixtures)"
  else type="ci(deps)"
  fi
  bump() { printf '%s to %s' "${W_DISPLAY[$1]}" "${W_VER[$1]}"; }
  case "$n" in
    0) subject="refresh cascade-managed files" ;;
    1) subject="bump $(bump "${MOVED[0]}")" ;;
    2) subject="bump $(bump "${MOVED[0]}") and $(bump "${MOVED[1]}")" ;;
    3) subject="bump $(bump "${MOVED[0]}"), $(bump "${MOVED[1]}") and $(bump "${MOVED[2]}")" ;;
    *) subject="bump $n upstream pins" ;;
  esac
  TITLE="$type: $subject"
}

# lint_file <surface> <file>: exit 1 naming the first line holding a bare
# mention. A grep that cannot run the pattern (no PCRE, a read error) is exit
# 1 too: grep's exit 2 is never read as "no match".
lint_file() {
  local hit rc=0
  hit=$(grep -nP -m 1 -- "$MENTION_RE" "$2") || rc=$?
  case "$rc" in
    0) die "mention lint: $1 line ${hit%%:*} holds a bare mention: ${hit#*:}" ;;
    1) ;;
    *) die "mention lint: grep -P failed on the $1 (exit $rc)" ;;
  esac
}

cmd_title() {
  pr_compute
  [ -n "$TITLE" ] || exit 3
  printf '%s\n' "$TITLE" >"$WORK/title"
  lint_file title "$WORK/title"
  cat "$WORK/title"
}

cmd_body() {
  pr_compute
  local out="$WORK/body" k l t

  # Warnings first, before this run adds its own to the same file.
  local wf="$WARN_ABS" line
  local -a wlines=()
  if [ -n "$wf" ]; then
    [ -f "$wf" ] || die "warnings file \`$WARN_FILE\` not found"
  else
    wf="$(git rev-parse --absolute-git-dir)/cascade/warnings"
  fi
  if [ -f "$wf" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      [ -n "$line" ] || continue
      [[ $line == *$'\t'* ]] || line="-"$'\t'"$line"
      wlines+=("$line")
    done <"$wf"
  fi

  # Triggering releases: CASCADE_SOURCE and CASCADE_TAGS come from the
  # untrusted dispatch payload, so anything off-pattern is dropped and named
  # only in its safe form.
  local src="${CASCADE_SOURCE:-}" tags="${CASCADE_TAGS:-}" sources="$CASCADE_SOURCES" x
  local -a trig=() raw=() extra=()
  read -r -a raw <<<"$tags" || true
  # CASCADE_EXTRA_SOURCES: space-separated repo names the sandbox receiver
  # adds; a name that is not a repo name is ignored.
  read -r -a extra <<<"${CASCADE_EXTRA_SOURCES:-}" || true
  for x in "${extra[@]}"; do
    if [[ $x =~ $REPO_RE ]]; then
      sources="$sources$x "
    else
      warn - "ignored extra source \`$(safe_text "$x")\`: not a repo name"
      wlines+=("-"$'\t'"ignored extra source \`$(safe_text "$x")\`: not a repo name")
    fi
  done
  if [ -n "$src" ] && [[ $sources != *" $src "* ]]; then
    warn - "dropped triggering source \`$(safe_text "$src")\`: not a cascade repo"
    wlines+=("-"$'\t'"dropped triggering source \`$(safe_text "$src")\`: not a cascade repo")
  elif [ -z "$src" ] && [ "${#raw[@]}" -gt 0 ]; then
    warn - "dropped triggering tags: \`CASCADE_SOURCE\` is not set"
    wlines+=("-"$'\t'"dropped triggering tags: \`CASCADE_SOURCE\` is not set")
  else
    for t in "${raw[@]}"; do
      if [[ $t =~ $TAG_RE ]]; then
        trig+=("- \`$src\` \`$t\`")
      else
        warn - "dropped triggering tag \`$(safe_text "$t")\`"
        wlines+=("-"$'\t'"dropped triggering tag \`$(safe_text "$t")\`")
      fi
    done
  fi

  local labels="" sep=""
  local -a parts
  for k in "${MOVED[@]}"; do
    IFS=, read -r -a parts <<<"${W_LABELS[$k]}" || true
    for l in "${parts[@]}"; do
      l="${l#"${l%%[![:space:]]*}"}"
      l="${l%"${l##*[![:space:]]}"}"
      [ -n "$l" ] || continue
      [[ ",$labels," != *",$l,"* ]] || continue
      labels="$labels$sep$l"
      sep=","
    done
  done

  {
    printf '<!-- cascade-title: %s -->\n' "$TITLE"
    printf '<!-- cascade-labels: %s -->\n' "$labels"
    printf '## Moved pins\n\n| Pin | Class | From | To |\n| --- | --- | --- | --- |\n'
    if [ "${#MOVED[@]}" -eq 0 ]; then
      printf '| none | - | - | - |\n'
    else
      for k in "${MOVED[@]}"; do
        # shellcheck disable=SC2016 # Markdown backticks, not shell
        printf '| %s (`%s`) | %s | `%s` | `%s` |\n' "${W_DISPLAY[$k]}" "$k" "${W_CLASS[$k]}" "${B_VER[$k]}" "${W_VER[$k]}"
      done
    fi
    printf '\nChanged files: %d shipped, %d test, %d release-tool.\n' "$N_SHIPPED" "$N_TEST" "$N_TOOL"
    printf '\n## Triggering releases\n\n'
    if [ "${#trig[@]}" -eq 0 ]; then
      printf -- '- None recorded (daily sweep or manual run).\n'
    else
      printf '%s\n' "${trig[@]}"
    fi
    printf '\n## Warnings\n\n'
    local seen=$'\n' wk wm shown=0
    for line in "${wlines[@]}"; do
      [[ $seen != *$'\n'"$line"$'\n'* ]] || continue
      seen="$seen$line"$'\n'
      wk="${line%%$'\t'*}" wm="${line#*$'\t'}"
      # shellcheck disable=SC2016 # Markdown backticks, not shell
      if [ "$wk" = - ]; then printf -- '- %s\n' "$wm"; else printf -- '- `%s`: %s\n' "$wk" "$wm"; fi
      shown=1
    done
    [ "$shown" = 1 ] || printf -- '- None.\n'
    printf '\n## Notes\n\n'
  } >"$out"
  lint_file body "$out"
  printf '<!-- cascade-notes: the bot keeps everything below this line -->\n' >>"$out"
  local notes="$NOTES_ABS"
  if [ -n "$notes" ]; then
    [ -f "$notes" ] || die "CASCADE_NOTES_FILE \`$CASCADE_NOTES_FILE\` not found"
    if [ -s "$notes" ]; then
      cat "$notes" >>"$out"
      [ -z "$(tail -c 1 "$notes")" ] || printf '\n' >>"$out"
    fi
  fi
  cat "$out"
}

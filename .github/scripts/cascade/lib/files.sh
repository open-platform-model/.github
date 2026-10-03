# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the other lib files and the entry point
# Readers for the two steering files a repo keeps at its root (workspace
# RELEASING.md, section "Cascade files"): .cascade-frozen and .cascade-hold.
# Each file is converted to JSON with yq and checked with jq before any
# answer is given, so a malformed file is never half-applied.

# load_steering <name> <jq checker>: validates $REPO_ROOT/<name> and sets
# STEER_JSON (the file as JSON; {} when missing or empty).
load_steering() {
  local name="$1" checker="$2" f="$REPO_ROOT/$1" json errs
  need_tools yq jq
  STEER_JSON='{}'
  [ -e "$f" ] || return 0
  [ -f "$f" ] || die "\`$name\` is not a regular file"
  json=$(yq -o=json '.' "$f" 2>&1) || die "\`$name\` is not valid YAML: $json"
  [ -n "$json" ] || json=null
  errs=$(jq -r "$checker" <<<"$json") || die "\`$name\` could not be checked"
  if [ -n "$errs" ]; then
    while IFS= read -r e; do note "\`$name\`: $e"; done <<<"$errs"
    die "\`$name\` is malformed"
  fi
  [ "$json" != null ] || json='{}'
  STEER_JSON="$json"
}

# Shared jq definitions: one error string per problem.
# shellcheck disable=SC2016 # jq programs, not shell
JQ_DEFS='
def nonempty_str: type == "string" and length > 0;
def keys_check($i; $want):
  ((keys - $want)[] | "entry \($i): unknown key `\(.)`"),
  (($want - keys)[] | "entry \($i): missing key `\(.)`");
def top($list):
  if type == "null" then empty
  elif type != "object" then "the top level must be a mapping"
  else (keys - [$list])[] | "unknown top-level key `\(.)`"
  end;
def entries($list):
  if type != "object" then empty
  elif (.[$list] | type) == "null" then empty
  elif (.[$list] | type) != "array" then "`\($list)` must be a list"
  else .[$list] | to_entries[] | {i: (.key + 1), e: .value}
  end;
'

# shellcheck disable=SC2016 # jq program, not shell
FROZEN_CHECK="$JQ_DEFS"'
top("frozen"),
(entries("frozen") | if type == "string" then . else
  .i as $i | .e as $e |
  if ($e | type) != "object" then "entry \($i): not a mapping" else
    ($e | keys_check($i; ["path", "pins", "reason"])),
    (if ($e | has("path")) then
      if ($e.path | nonempty_str | not) then "entry \($i): `path` must be a non-empty string"
      elif ($e.path | startswith("/")) then "entry \($i): `path` must be repo-relative"
      elif ($e.path | split("/") | any(. == "..")) then "entry \($i): `path` must not hold `..`"
      else empty end
    else empty end),
    (if ($e | has("pins")) then
      if ($e.pins | type) != "array" or ($e.pins | length) == 0 then "entry \($i): `pins` must be a non-empty list"
      elif ($e.pins | all(nonempty_str) | not) then "entry \($i): every pin key must be a non-empty string"
      else empty end
    else empty end),
    (if ($e | has("reason")) and ($e.reason | nonempty_str | not) then "entry \($i): `reason` must be a non-empty string" else empty end)
  end
end)
'

# shellcheck disable=SC2016 # jq program, not shell
HOLD_CHECK="$JQ_DEFS"'
def version: test("^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$");
top("holds"),
(entries("holds") | if type == "string" then . else
  .i as $i | .e as $e |
  if ($e | type) != "object" then "entry \($i): not a mapping" else
    ($e | keys_check($i; ["pin", "max", "reason", "expires"])),
    (if ($e | has("pin")) and ($e.pin | nonempty_str | not) then "entry \($i): `pin` must be a non-empty string" else empty end),
    (if ($e | has("max")) and (($e.max | type) != "string" or ($e.max | version | not)) then "entry \($i): `max` must be a v-prefixed SemVer version" else empty end),
    (if ($e | has("reason")) and ($e.reason | nonempty_str | not) then "entry \($i): `reason` must be a non-empty string"
     elif ($e | has("reason")) and ($e.reason | test("(?<![\\w@])@[A-Za-z0-9]")) then "entry \($i): `reason` holds a bare mention (it is quoted in a cascade PR warning); glue the @ to a word or drop it"
     else empty end),
    (if ($e | has("expires")) and (($e.expires | type) != "string" or ($e.expires | test("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$") | not)) then "entry \($i): `expires` must be a YYYY-MM-DD date" else empty end)
  end
end),
(if type == "object" and (.holds | type) == "array" then
  [.holds[] | objects | .pin | strings] | group_by(.)[] | select(length > 1) | "more than one hold for `\(.[0])`"
else empty end)
'

load_frozen() { load_steering .cascade-frozen "$FROZEN_CHECK"; }
load_holds() { load_steering .cascade-hold "$HOLD_CHECK"; }

# frozen_paths <pin-key>: prints every frozen path listing the key.
frozen_paths() {
  load_frozen
  jq -r --arg k "$1" '(.frozen // [])[] | select(.pins | index($k)) | .path' <<<"$STEER_JSON"
}

# is_frozen <path> <pin-key>: 0 when an entry for the key covers the path.
is_frozen() {
  local path="$1" key="$2" p
  load_frozen
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    p="${p%/}"
    case "$path" in "$p" | "$p"/*) return 0 ;; esac
  done < <(jq -r --arg k "$key" '(.frozen // [])[] | select(.pins | index($k)) | .path' <<<"$STEER_JSON")
  return 1
}

today() {
  local t="${CASCADE_TODAY:-}"
  [ -n "$t" ] || t=$(date -u +%F)
  [[ $t =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "CASCADE_TODAY \`$(safe_text "$t")\` is not YYYY-MM-DD"
  TODAY="$t"
}

# hold_lookup <pin-key>: sets HOLD_MAX, HOLD_EXPIRES and HOLD_REASON for an
# in-date hold (all empty otherwise). An expired hold warns.
hold_lookup() {
  local key="$1" row
  HOLD_MAX="" HOLD_EXPIRES="" HOLD_REASON=""
  load_holds
  row=$(jq -r --arg k "$key" '(.holds // [])[] | select(.pin == $k) | [.max, .expires, .reason] | @tsv' <<<"$STEER_JSON")
  [ -n "$row" ] || return 0
  local max exp reason
  IFS=$'\t' read -r max exp reason <<<"$row"
  today
  if [[ $exp < $TODAY ]]; then
    warn "$key" "hold on \`$key\` expired \`$exp\`; moving again"
    return 0
  fi
  HOLD_MAX="$max" HOLD_EXPIRES="$exp" HOLD_REASON="$reason"
}

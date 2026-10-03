# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the other lib files and the entry point
# newest: the newest published upstream version a pin may move to.
#
# Candidates are the valid, non-dev versions of the current major strictly
# above --current (releases only on a stable pin, unless --pre). At most the
# ten newest are probed for "published", newest first; the first published
# one wins. An in-date hold caps the answer; a newer major is only a warning.
# The answer never moves a pin backwards and is never guessed.

# upstream_list: sets RAW to every version the upstream lists for this kind.
upstream_list() {
  case "$KIND" in
    cue)
      ghcr_tags "$CUE_REPO" \
        || die "\`$CUE_REPO\` is unknown on GHCR or private; a pinned package must exist"
      RAW=("${TAGS[@]}")
      ;;
    go)
      goproxy_list "$GO_PATH" || die "the Go proxy has no module \`$GO_PATH\`"
      RAW=("${GOLIST[@]}")
      ;;
    release | opm-cli)
      release_tags "$REL_REPO"
      RAW=("${RTAGS[@]}")
      ;;
  esac
}

# newest_in_major <major> <version>...: sets BEST to the highest valid,
# non-dev version of that major (empty when none).
newest_in_major() {
  local m="$1" v
  shift
  BEST=""
  for v in "$@"; do
    is_version "$v" || continue
    ! is_dev_or_pseudo "$v" || continue
    major_of "$v"
    [ "$MAJOR" = "$m" ] || continue
    if [ -z "$BEST" ]; then BEST="$v"; continue; fi
    semver_cmp "$v" "$BEST"
    [ "$CMP" != 1 ] || BEST="$v"
  done
}

# probe_first <limit> <version>...: sets FOUND to the first published one of
# at most <limit> versions, and PROBED to how many were checked.
probe_first() {
  local limit="$1" v
  shift
  FOUND="" PROBED=0
  for v in "$@"; do
    [ "$PROBED" -lt "$limit" ] || return 0
    PROBED=$((PROBED + 1))
    check_published "$v" || die "\`$PIN_KEY\` is unknown on GHCR or private; a pinned package must exist"
    if [ "$PUB" = 1 ]; then FOUND="$v"; return 0; fi
    note "skip \`$v\`: not published yet"
  done
}

# new_major_probe <current major>: warns when a version of the next major
# exists; sets NEWER_MAJOR.
new_major_probe() {
  local m="$1" next=$(($1 + 1)) base
  NEWER_MAJOR=""
  case "$KIND" in
    cue | release | opm-cli) newest_in_major "$next" "${RAW[@]}" ;;
    go)
      if [ "$m" -eq 0 ]; then
        # Go has no /v1: major 1 lives under the same, unsuffixed path.
        newest_in_major 1 "${RAW[@]}"
      else
        base="${GO_PATH%/v"$m"}"
        if goproxy_list "$base/v$next"; then
          newest_in_major "$next" "${GOLIST[@]}"
        else
          BEST=""
        fi
      fi
      ;;
  esac
  [ -n "$BEST" ] || return 0
  NEWER_MAJOR="$BEST"
  if is_prerelease "$BEST"; then
    warn "$PIN_KEY" "new major available: \`$BEST\` (prerelease)"
  else
    warn "$PIN_KEY" "new major available: \`$BEST\`"
  fi
}

# expect_wait: applies --expect (an untrusted hint from the dispatch
# payload). Polls "published" every 30 seconds up to the wait budget; the
# elapsed time is the sum of the requested sleeps, never the wall clock. A
# version confirmed published joins CANDS; it is never answered on its own.
expect_wait() {
  local v="$EXPECT" why="" waited=0 step budget="$1" allow_pre="$2" cmaj="$3"
  if ! is_version "$v"; then why="it is not a v-prefixed SemVer version"
  else
    major_of "$v"
    semver_cmp "$v" "$CURRENT"
    if [ "$MAJOR" != "$cmaj" ]; then why="it is another major"
    elif is_dev_or_pseudo "$v"; then why="it is a dev build"
    elif [ "$CMP" != 1 ]; then why="it is not above the current pin"
    elif [ "$allow_pre" = 0 ] && is_prerelease "$v"; then why="it is a prerelease and the pin is stable"
    elif [ -n "$HOLD_MAX" ]; then
      semver_cmp "$v" "$HOLD_MAX"
      [ "$CMP" != 1 ] || why="it is above the hold \`$HOLD_MAX\`"
    fi
  fi
  if [ -n "$why" ]; then
    note "ignoring --expect \`$(safe_text "$v")\`: $why"
    return 0
  fi
  while :; do
    unset 'PUB_CACHE[$v]'
    check_published "$v" || die "\`$PIN_KEY\` is unknown on GHCR or private; a pinned package must exist"
    [ "$PUB" = 1 ] && break
    if [ "$waited" -ge "$budget" ]; then
      warn "$PIN_KEY" "expected \`$v\` is not published after \`${waited}\`s"
      return 0
    fi
    step=30
    [ $((budget - waited)) -ge "$step" ] || step=$((budget - waited))
    note "expected \`$v\` is not published yet; checking again in ${step}s"
    "${CASCADE_SLEEP:-sleep}" "$step"
    waited=$((waited + step))
  done
  local c
  for c in "${CANDS[@]}"; do [ "$c" != "$v" ] || return 0; done
  SORTED=("${CANDS[@]}" "$v")
  semver_sort
  CANDS=()
  for ((c = ${#SORTED[@]} - 1; c >= 0; c--)); do CANDS+=("${SORTED[c]}"); done
}

cmd_newest() {
  parse_kind "${POS[@]}"
  [ "${#REST[@]}" -eq 0 ] || usage "newest takes no version argument (use --current)"
  [ "$KIND" != oci ] || usage "the oci kind is for published only"
  [ -n "$CURRENT" ] || usage "newest needs --current"
  need_version "$CURRENT" "--current"
  major_of "$CURRENT"
  local cmaj="$MAJOR"
  case "$KIND" in
    cue) [ "$CUE_MAJOR" = "$cmaj" ] || usage "\`$COORD\` is major $CUE_MAJOR but --current \`$CURRENT\` is major $cmaj" ;;
    go) go_major_ok "$cmaj" || usage "\`$COORD\` does not match the major of --current \`$CURRENT\`" ;;
  esac
  local budget="${MAX_WAIT:-${CASCADE_MAX_WAIT:-600}}"
  [[ $budget =~ ^[0-9]+$ ]] || usage "--max-wait must be a number of seconds"
  local allow_pre="$PRE"
  ! is_prerelease "$CURRENT" || allow_pre=1
  case "$KIND" in
    release | opm-cli) need_tools curl jq yq git ;;
    *) need_tools curl jq yq ;;
  esac

  # Steering files first: a malformed hold stops the run before any request.
  hold_lookup "$PIN_KEY"

  upstream_list
  filter_candidates "$CURRENT" "$PRE" "${RAW[@]}"
  [ -z "$EXPECT" ] || expect_wait "$budget" "$allow_pre" "$cmaj"

  local newest="" target=""
  probe_first 10 "${CANDS[@]}"
  newest="$FOUND"
  if [ -z "$newest" ]; then
    if [ "${#CANDS[@]}" -ge 10 ]; then
      die "none of the 10 newest candidates above \`$CURRENT\` is published; something is wrong upstream"
    elif [ "${#CANDS[@]}" -gt 0 ]; then
      warn "$PIN_KEY" "no published version newer than \`$CURRENT\`; newest tagged \`${CANDS[0]}\` is not published yet"
    else
      local -a in_rule=()
      local v
      for v in "${RAW[@]}"; do
        if [ "$allow_pre" = 0 ] && is_prerelease "$v"; then continue; fi
        in_rule+=("$v")
      done
      newest_in_major "$cmaj" "${in_rule[@]}"
      if [ -n "$BEST" ]; then
        semver_cmp "$CURRENT" "$BEST"
        [ "$CMP" != 1 ] || warn "$PIN_KEY" "\`$CURRENT\` is newer than the newest published \`$BEST\`"
      fi
    fi
  fi
  target="$newest"

  if [ -n "$HOLD_MAX" ]; then
    semver_cmp "$HOLD_MAX" "$CURRENT"
    if [ "$CMP" = -1 ]; then
      warn "$PIN_KEY" "hold \`max\` \`$HOLD_MAX\` is below the current pin \`$CURRENT\`"
      target=""
    elif [ -n "$newest" ]; then
      semver_cmp "$newest" "$HOLD_MAX"
      if [ "$CMP" = 1 ]; then
        warn "$PIN_KEY" "held at \`$HOLD_MAX\` until \`$HOLD_EXPIRES\`: $HOLD_REASON"
        local -a capped=()
        local c
        for c in "${CANDS[@]}"; do
          semver_cmp "$c" "$HOLD_MAX"
          [ "$CMP" = 1 ] || capped+=("$c")
        done
        probe_first 10 "${capped[@]}"
        target="$FOUND"
      fi
    fi
  fi

  new_major_probe "$cmaj"

  local moved=false
  if [ -n "$target" ]; then
    semver_cmp "$target" "$CURRENT"
    [ "$CMP" != 1 ] || moved=true
  fi
  if [ "$JSON" = 1 ]; then
    local wjson='[]' hold=null
    [ "${#WARNINGS[@]}" -eq 0 ] || wjson=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s -c .)
    [ -z "$HOLD_MAX" ] || hold=$(jq -n -c --arg m "$HOLD_MAX" --arg e "$HOLD_EXPIRES" '{max: $m, expires: $e}')
    local shown="$CURRENT"
    [ "$moved" = false ] || shown="$target"
    jq -n -c --arg pin "$PIN_KEY" --arg kind "$KIND" --arg current "$CURRENT" \
      --arg newest "$newest" --arg target "$shown" --argjson moved "$moved" \
      --argjson hold "$hold" --arg nm "$NEWER_MAJOR" --argjson warnings "$wjson" \
      '{pin: $pin, kind: $kind, current: $current,
        newest: (if $newest == "" then null else $newest end),
        target: $target, moved: $moved, hold: $hold,
        newer_major: (if $nm == "" then null else $nm end), warnings: $warnings}'
  elif [ "$moved" = true ]; then
    printf '%s\n' "$target"
  fi
  [ "$moved" = true ] || exit 3
}

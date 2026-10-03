# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the other lib files and the entry point
# GHCR, read anonymously. The pull token from ghcr.io/token is the only
# credential ever sent, and only to ghcr.io (curl does not forward a custom
# Authorization header when -L follows a blob redirect to another host).

GHCR=https://ghcr.io
MANIFEST_TYPE=application/vnd.oci.image.manifest.v1+json
INDEX_TYPE=application/vnd.oci.image.index.v1+json
MODULEFILE_TYPE=application/vnd.cue.modulefile.v1
declare -A GHCR_TOKENS=()

# ghcr_token <repo>: sets GHCR_TOKEN; returns 1 when GHCR does not serve the
# package anonymously (unknown or private: 403 or 404).
ghcr_token() {
  local repo="$1" url
  if [ -n "${GHCR_TOKENS[$repo]:-}" ]; then
    GHCR_TOKEN="${GHCR_TOKENS[$repo]}"
    return 0
  fi
  url="$GHCR/token?scope=repository:$repo:pull&service=ghcr.io"
  http_request "$url"
  case "$HTTP_STATUS" in
    200) ;;
    403 | 404) return 1 ;;
    *) refuse "$url" ;;
  esac
  GHCR_TOKEN=$(jq -r '.token // empty' "$HTTP_BODY" 2>/dev/null) || GHCR_TOKEN=""
  [[ $GHCR_TOKEN =~ ^[A-Za-z0-9._~+/=-]+$ ]] || die "GHCR token answer for \`$repo\` holds no usable token"
  GHCR_TOKENS[$repo]="$GHCR_TOKEN"
}

# ghcr_tags <repo>: sets TAGS to every tag, following Link pagination (at most
# 20 pages). Returns 1 for an unknown or private package (token 403/404, or
# tags 404 on the first page).
ghcr_tags() {
  local repo="$1" url pages=0 link
  TAGS=()
  ghcr_token "$repo" || return 1
  url="$GHCR/v2/$repo/tags/list?n=1000"
  while [ -n "$url" ]; do
    pages=$((pages + 1))
    [ "$pages" -le 20 ] || die "the tag list of \`$repo\` has more than 20 pages"
    http_request -H "Authorization: Bearer $GHCR_TOKEN" "$url"
    case "$HTTP_STATUS" in
      200) ;;
      404) [ "$pages" -eq 1 ] || refuse "$url"; return 1 ;;
      *) refuse "$url" ;;
    esac
    jq -e '(.tags // []) | type == "array"' "$HTTP_BODY" >/dev/null 2>&1 \
      || die "the tag list of \`$repo\` is not JSON"
    mapfile -t -O "${#TAGS[@]}" TAGS < <(jq -r '(.tags // [])[] | strings' "$HTTP_BODY")
    link=$(tr -d '\r' <"$HTTP_HEADERS" | sed -nE 's/^[Ll][Ii][Nn][Kk]: *<([^>]*)>; *rel="?next"?.*$/\1/p' | head -n 1)
    case "$link" in
      "") url="" ;;
      /*) url="$GHCR$link" ;;
      "$GHCR"/*) url="$link" ;;
      *) die "the tag list of \`$repo\` links to another host" ;;
    esac
  done
}

# ghcr_head <repo> <reference> <accept>: sets PUB to 1 when the manifest HEAD
# answers 200 and 0 on 404. Returns 1 for an unknown or private package.
ghcr_head() {
  local repo="$1" ref="$2" accept="$3" url
  ghcr_token "$repo" || return 1
  url="$GHCR/v2/$repo/manifests/$ref"
  http_request -I -H "Authorization: Bearer $GHCR_TOKEN" -H "Accept: $accept" "$url"
  case "$HTTP_STATUS" in
    200) PUB=1 ;;
    404) PUB=0 ;;
    *) refuse "$url" ;;
  esac
}

# ghcr_modulefile <module>@v<N> <v>: sets MODFILE to a file holding the
# module.cue that release published (its modulefile layer).
ghcr_modulefile() {
  local coord="$1" v="$2" repo url digest
  repo="open-platform-model/${coord%@v*}"
  ghcr_token "$repo" || die "\`$repo\` is unknown or private on GHCR"
  url="$GHCR/v2/$repo/manifests/$v"
  http_request -H "Authorization: Bearer $GHCR_TOKEN" -H "Accept: $MANIFEST_TYPE" "$url"
  case "$HTTP_STATUS" in
    200) ;;
    404) die "\`$coord\` \`$v\` is not published" ;;
    *) refuse "$url" ;;
  esac
  digest=$(jq -r --arg t "$MODULEFILE_TYPE" \
    '[(.layers // [])[] | select(.mediaType == $t) | .digest] | first // empty' "$HTTP_BODY" 2>/dev/null) || digest=""
  [[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || die "the \`$coord\` \`$v\` manifest has no module file layer"
  url="$GHCR/v2/$repo/blobs/$digest"
  http_request -L -H "Authorization: Bearer $GHCR_TOKEN" "$url"
  [ "$HTTP_STATUS" = 200 ] || refuse "$url"
  MODFILE="$HTTP_BODY"
}

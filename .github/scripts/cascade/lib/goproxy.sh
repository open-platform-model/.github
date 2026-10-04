# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the other lib files and the entry point
# The Go module proxy. Candidates come from @v/list, never @latest (which
# skips prereleases); a version is published when its .info answers 200.

goproxy_base() {
  local b="${CASCADE_GOPROXY:-https://proxy.golang.org}"
  b="${b%/}"
  case "$b" in https://* | http://*) ;; *) die "CASCADE_GOPROXY must be an http(s) URL" ;; esac
  printf '%s' "$b"
}

# go_escape <path>: the proxy's case encoding (an upper-case letter becomes
# "!" plus its lower-case form).
go_escape() { printf '%s' "$1" | sed 's/[A-Z]/!\L&/g'; }

# goproxy_list <module path>: sets GOLIST; returns 1 when the proxy answers
# 404 or 410 (no such module).
goproxy_list() {
  local url
  url="$(goproxy_base)/$(go_escape "$1")/@v/list"
  GOLIST=()
  http_request "$url"
  case "$HTTP_STATUS" in
    200) ;;
    404 | 410) return 1 ;;
    *) refuse "$url" ;;
  esac
  mapfile -t GOLIST < <(tr -d '\r' <"$HTTP_BODY" | sed '/^$/d')
}

# goproxy_info <module path> <v>: sets PUB (1 published, 0 not yet).
goproxy_info() {
  local url
  url="$(goproxy_base)/$(go_escape "$1")/@v/$2.info"
  http_request "$url"
  case "$HTTP_STATUS" in
    200) PUB=1 ;;
    404 | 410) PUB=0 ;;
    *) refuse "$url" ;;
  esac
}

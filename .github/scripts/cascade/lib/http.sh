# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the other lib files and the entry point
# The one way the resolver talks HTTP. Every request is exactly
#   curl -q -sS --connect-timeout 10 --max-time 60 -o <body> -D <headers>
#        -w '%{http_code}' [-I] [-L] [-H <header>]... <url>
# -q comes first so ~/.curlrc never applies, and curl gets no --retry: the
# resolver retries itself so the test shim can count attempts.

HTTP_N=0

# http_request [-I] [-L] [-H <header>]... <url>: sets HTTP_STATUS (three
# digits), HTTP_BODY and HTTP_HEADERS (files). No answer (000), 429 and 5xx
# are retried: 4 attempts in all, sleeping 2, 4 and 8 seconds between them,
# then exit 1. Every other status is returned for the caller to map.
http_request() {
  local -a extra=()
  while [ $# -gt 1 ]; do extra+=("$1"); shift; done
  local url="$1" code attempt=1 delays=(2 4 8)
  work_dir
  HTTP_N=$((HTTP_N + 1))
  HTTP_BODY="$WORK/r$HTTP_N.body"
  HTTP_HEADERS="$WORK/r$HTTP_N.headers"
  while :; do
    code=$(curl -q -sS --connect-timeout 10 --max-time 60 -o "$HTTP_BODY" -D "$HTTP_HEADERS" \
      -w '%{http_code}' "${extra[@]}" "$url" 2>"$WORK/curl.err") || true
    [[ $code =~ ^[0-9]{3}$ ]] || code=000
    case "$code" in
      000 | 429 | 5[0-9][0-9])
        if [ "$attempt" -ge 4 ]; then
          die "\`$(url_for_log "$url")\` answered \`$code\` after 4 attempts"
        fi
        note "\`$(url_for_log "$url")\` answered \`$code\`; retrying in ${delays[attempt - 1]}s"
        "${CASCADE_SLEEP:-sleep}" "${delays[attempt - 1]}"
        attempt=$((attempt + 1))
        ;;
      *)
        HTTP_STATUS="$code"
        return 0
        ;;
    esac
  done
}

# url_for_log <url>: the URL without its query (the GHCR token URL's query is
# harmless, but nothing secret ever belongs in a log line).
url_for_log() { printf '%s' "${1%%\?*}"; }

# refuse <url>: the answer was not one this request expects.
refuse() {
  die "\`$(url_for_log "$1")\` answered \`$HTTP_STATUS\`; refusing to guess"
}

# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the other lib files and the entry point
# GitHub releases, read without the API: tags from git ls-remote, and a
# release counts as published when every asset answers 200 to an anonymous
# HEAD of its download URL. A draft and a release without the asset both
# answer 404 there.

GH=https://github.com/open-platform-model

# release_tags <repo>: sets RTAGS to the v* tag names.
release_tags() {
  local repo="$1" out
  need_tools git
  work_dir
  out=$(git ls-remote --tags --refs "$GH/$repo" 'refs/tags/v*' 2>"$WORK/git.err") \
    || die "cannot list the tags of \`$repo\` (git ls-remote failed: $(head -c 200 "$WORK/git.err"))"
  mapfile -t RTAGS < <(printf '%s\n' "$out" | awk -F'\t' '$2 ~ /^refs\/tags\// {sub(/^refs\/tags\//, "", $2); print $2}')
}

# release_published <repo> <tag> <asset>...: sets PUB, and MISSING to the
# first asset that answered 404.
release_published() {
  local repo="$1" tag="$2" a url
  shift 2
  MISSING=""
  for a in "$@"; do
    url="$GH/$repo/releases/download/$tag/$a"
    http_request -I -L "$url"
    case "$HTTP_STATUS" in
      200) ;;
      404) MISSING="$a"; PUB=0; return 0 ;;
      *) refuse "$url" ;;
    esac
  done
  PUB=1
}

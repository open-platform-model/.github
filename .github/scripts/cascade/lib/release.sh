# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the other lib files and the entry point
# GitHub releases, read without the API: tags from git ls-remote, and a
# release counts as published when every asset answers 200 to an anonymous
# HEAD of its download URL. A draft and a release without the asset both
# answer 404 there.

GH=https://github.com/open-platform-model

# ls_remote_tags <repo>: git ls-remote of the repo's v* tags, isolated from
# the caller. It runs in $WORK (outside any repo, discovery stops there) with
# no system, global or environment config and no credential helper, so an
# actions/checkout tree's persisted AUTHORIZATION extraheader or a laptop's
# helper never reaches github.com, and it never prompts for a username.
ls_remote_tags() {
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_ASKPASS SSH_ASKPASS
    export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CEILING_DIRECTORIES="${WORK%/*}"
    exec git -C "$WORK" -c credential.helper= ls-remote --tags --refs "$GH/$1" 'refs/tags/v*'
  )
}

# release_tags <repo>: sets RTAGS to the v* tag names. A failed ls-remote is
# retried like an HTTP request: 4 attempts in all, sleeping 2, 4 and 8
# seconds between them, then exit 1.
release_tags() {
  local repo="$1" out attempt=1 delays=(2 4 8)
  need_tools git
  work_dir
  until out=$(ls_remote_tags "$repo" 2>"$WORK/git.err"); do
    if [ "$attempt" -ge 4 ]; then
      die "cannot list the tags of \`$repo\` (git ls-remote failed after 4 attempts: $(head -c 200 "$WORK/git.err"))"
    fi
    note "git ls-remote of \`$repo\` failed; retrying in ${delays[attempt - 1]}s"
    "${CASCADE_SLEEP:-sleep}" "${delays[attempt - 1]}"
    attempt=$((attempt + 1))
  done
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

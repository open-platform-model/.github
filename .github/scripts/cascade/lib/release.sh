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
  git_isolated "$WORK" ls-remote --tags --refs "$GH/$1" 'refs/tags/v*'
}

# git_isolated <dir> <git args...>: git in <dir> with no system, global or
# environment config, no credential helper, no prompt, and a stalled
# transfer aborted after 60 seconds. ls-remote and the tag-on-main check run
# through it.
git_isolated() {
  local d="$1"
  shift
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_ASKPASS SSH_ASKPASS
    export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CEILING_DIRECTORIES="${WORK%/*}"
    exec git -C "$d" -c credential.helper= -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 "$@"
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

# tag_source <pin key>: prints "<repo> <tag prefix>" when the pin's versions
# are release tags of an org repo (a Go module at the repo root, with or
# without /vN, a release repo, core and the opm catalog on GHCR); exit 1 for
# any other pin (fixtures, templates, oci), which has no tag to check.
tag_source() {
  local k="$1" r rest
  case "$k" in
    opmodel.dev/core@v[0-9]*) echo "core " ;;
    opmodel.dev/catalogs/opm@v[0-9]*) echo "catalog_opm opm-" ;;
    github.com/open-platform-model/*)
      r="${k#github.com/open-platform-model/}"
      rest=""
      if [[ $r == */* ]]; then rest="${r#*/}"; r="${r%%/*}"; fi
      [[ $r =~ $REPO_RE ]] || return 1
      [ -z "$rest" ] || [[ $rest =~ ^v[0-9]+$ ]] || return 1
      echo "$r "
      ;;
    *) return 1 ;;
  esac
}

# on_main <repo> <tag>: sets ONMAIN to 1 when the tag exists and its commit
# is reachable from the repo's main, else 0. The repo is cloned once per run,
# bare and without trees (commits only), and each tag is fetched on its own;
# a failed clone or fetch is retried like ls-remote (4 attempts in all), then
# exit 1. A forged tag, made with the release App on a commit main never had,
# is still served by the Go proxy and git; this keeps it from becoming a
# cascade PR.
declare -A ONMAIN_DIR=()
on_main() {
  local repo="$1" tag="$2" dir attempt rc delays=(2 4 8)
  need_tools git
  work_dir
  dir="${ONMAIN_DIR[$repo]:-}"
  if [ -z "$dir" ]; then
    dir="$WORK/onmain-$repo.git"
    attempt=1
    until git_isolated "$WORK" clone --bare --quiet --filter=tree:0 --no-tags --single-branch --branch main \
      "$GH/$repo" "$dir" 2>"$WORK/git.err"; do
      rm -rf "$dir"
      if [ "$attempt" -ge 4 ]; then
        die "cannot clone \`$repo\` to check its tags against main (failed after 4 attempts: $(head -c 200 "$WORK/git.err"))"
      fi
      note "the clone of \`$repo\` failed; retrying in ${delays[attempt - 1]}s"
      "${CASCADE_SLEEP:-sleep}" "${delays[attempt - 1]}"
      attempt=$((attempt + 1))
    done
    ONMAIN_DIR[$repo]="$dir"
  fi
  attempt=1
  until git_isolated "$dir" fetch --quiet --no-tags origin "+refs/tags/$tag:refs/tags/$tag" 2>"$WORK/git.err"; do
    if grep -qi "couldn't find remote ref" "$WORK/git.err"; then
      ONMAIN=0
      return 0
    fi
    if [ "$attempt" -ge 4 ]; then
      die "cannot fetch the tag \`$tag\` of \`$repo\` (failed after 4 attempts: $(head -c 200 "$WORK/git.err"))"
    fi
    note "the fetch of \`$tag\` from \`$repo\` failed; retrying in ${delays[attempt - 1]}s"
    "${CASCADE_SLEEP:-sleep}" "${delays[attempt - 1]}"
    attempt=$((attempt + 1))
  done
  rc=0
  git_isolated "$dir" merge-base --is-ancestor "refs/tags/$tag^{commit}" refs/heads/main 2>"$WORK/git.err" || rc=$?
  case "$rc" in
    0) ONMAIN=1 ;;
    1) ONMAIN=0 ;;
    *) die "cannot compare the tag \`$tag\` of \`$repo\` with main: $(head -c 200 "$WORK/git.err")" ;;
  esac
}

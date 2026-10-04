#!/usr/bin/env bash
# Installs the tools the receiver's compute job runs (cascade-receive.yml):
# Task always, CUE unless the caller turned setup-cue off. Each archive comes
# from a fixed GitHub release URL over HTTPS only and must match the sha256
# below, so no version range and no unchecked download reaches the job.
# Runs before any repo code, as the first install step after the checkouts.
#
# Usage: install-tools.sh <cue-version|none>
#   <cue-version>  a CUE release in the table below (the caller's cue-version
#                  input), or none to skip CUE (setup-cue: false)
# Environment: CASCADE_TOOLS_DIR (default $RUNNER_TEMP/cascade-tools; the
# binaries land in its bin/), GITHUB_PATH (bin/ is appended when set),
# CASCADE_TOOLS_BASE (tests only: a file:// base URL replacing
# https://github.com), CASCADE_TOOLS_ARCH (tests only: the uname -sm value).
#
# Exit status: 0 installed; 1 a download, checksum or extract failure; 2
# usage, a CUE version without a checksum here, or a runner that is not Linux
# x64.
#
# The checksums were read on 2026-10-04 from three places that agree: the
# release's own checksums file where it has one (Task), the GitHub release
# asset digest, and sha256sum of the download. A new version is a .github
# change: add its row, then callers move their pin.
#
# Tools: bash, coreutils, curl, tar.
set -euo pipefail
export LC_ALL=C
CASCADE_SCRIPT=install-tools.sh
die() { printf '%s: %s\n' "$CASCADE_SCRIPT" "$1" >&2; exit "${2:-1}"; }

TASK_VERSION=v3.53.1
TASK_SHA256=a54a408f6861ff921f6e87774180db31bacd8c1e7c944ca696db9fea49a82fc7

# cue_sha256 <version>: the linux amd64 archive's sha256; exit 1 when unknown.
cue_sha256() {
  case "$1" in
    v0.17.1) echo a39b0c97695069d95d276d99be0f5dbabb081d801bfdc9ba49b76efaf94e2369 ;;
    *) return 1 ;;
  esac
}

[ $# -eq 1 ] && [ -n "$1" ] || die "usage: install-tools.sh <cue-version|none>" 2
cue="$1"
cue_sum=""
if [ "$cue" != none ]; then
  cue_sum=$(cue_sha256 "$cue") || die "cue-version \`${cue//[^A-Za-z0-9._-]/?}\` has no checksum in .github; add it to install-tools.sh first" 2
fi
arch="${CASCADE_TOOLS_ARCH:-$(uname -sm)}"
[ "$arch" = "Linux x86_64" ] || die "only Linux x64 runners are supported, not \`$arch\`" 2
for t in curl tar sha256sum; do command -v "$t" >/dev/null 2>&1 || die "missing tool: $t" 2; done

base="${CASCADE_TOOLS_BASE:-https://github.com}"
proto="=https"
case "$base" in
  https://github.com) ;;
  file://*) proto="=file" ;;
  *) die "CASCADE_TOOLS_BASE must be https://github.com or a file:// URL" 2 ;;
esac
dir="${CASCADE_TOOLS_DIR:-${RUNNER_TEMP:?RUNNER_TEMP is not set}/cascade-tools}"
mkdir -p "$dir/bin" "$dir/dl"

# fetch <url path> <sha256> <archive name> <binary>: download, check, extract.
fetch() {
  local f="$dir/dl/$3"
  curl -q -fsSL --proto "$proto" --proto-redir "$proto" --retry 3 --max-time 120 -o "$f" "$base/$1" \
    || die "cannot download $base/$1"
  printf '%s  %s\n' "$2" "$f" | sha256sum -c --quiet - >/dev/null 2>&1 \
    || die "the sha256 of $3 is not $2; refusing it"
  tar -xzf "$f" -C "$dir/bin" "$4" || die "cannot extract $4 from $3"
  chmod 0755 "$dir/bin/$4"
}

fetch "go-task/task/releases/download/$TASK_VERSION/task_linux_amd64.tar.gz" "$TASK_SHA256" task_linux_amd64.tar.gz task
echo "installed task $TASK_VERSION"
if [ -n "$cue_sum" ]; then
  fetch "cue-lang/cue/releases/download/$cue/cue_${cue}_linux_amd64.tar.gz" "$cue_sum" "cue_${cue}_linux_amd64.tar.gz" cue
  echo "installed cue $cue"
fi
if [ -n "${GITHUB_PATH:-}" ]; then printf '%s\n' "$dir/bin" >>"$GITHUB_PATH"; fi

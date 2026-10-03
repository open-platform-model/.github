# shellcheck shell=bash
# shellcheck disable=SC2034 # globals here are read by the other lib files and the entry point
# SemVer 2.0.0 precedence, written by hand. The `sed 's/-/~/' | sort -V` trick
# ranks a numeric prerelease identifier above an alphanumeric one, which the
# spec forbids, so nothing here sorts with sort -V.

# num_cmp <a> <b>: compare two digit strings of any length; sets CMP.
num_cmp() {
  local a="$1" b="$2"
  while [ "${#a}" -gt 1 ] && [ "${a:0:1}" = 0 ]; do a="${a:1}"; done
  while [ "${#b}" -gt 1 ] && [ "${b:0:1}" = 0 ]; do b="${b:1}"; done
  if [ "${#a}" -lt "${#b}" ]; then CMP=-1
  elif [ "${#a}" -gt "${#b}" ]; then CMP=1
  elif [[ $a < $b ]]; then CMP=-1
  elif [[ $a > $b ]]; then CMP=1
  else CMP=0
  fi
}

# semver_cmp <a> <b>: both valid versions; sets CMP to -1, 0 or 1.
semver_cmp() {
  local a="${1%%+*}" b="${2%%+*}"
  a="${a#v}" b="${b#v}"
  local ac="${a%%-*}" bc="${b%%-*}" ap="" bp=""
  [[ $a != *-* ]] || ap="${a#*-}"
  [[ $b != *-* ]] || bp="${b#*-}"
  local -a an bn
  IFS=. read -r -a an <<<"$ac"
  IFS=. read -r -a bn <<<"$bc"
  local i
  for i in 0 1 2; do
    num_cmp "${an[i]}" "${bn[i]}"
    [ "$CMP" = 0 ] || return 0
  done
  # A version without a prerelease ranks above the same one with it.
  if [ -z "$ap" ] && [ -z "$bp" ]; then CMP=0; return 0; fi
  if [ -z "$ap" ]; then CMP=1; return 0; fi
  if [ -z "$bp" ]; then CMP=-1; return 0; fi
  local -a ai bi
  IFS=. read -r -a ai <<<"$ap"
  IFS=. read -r -a bi <<<"$bp"
  local n=${#ai[@]} x y xn yn
  [ "${#bi[@]}" -ge "$n" ] || n=${#bi[@]}
  for ((i = 0; i < n; i++)); do
    x="${ai[i]}" y="${bi[i]}"
    xn=0 yn=0
    [[ ! $x =~ ^[0-9]+$ ]] || xn=1
    [[ ! $y =~ ^[0-9]+$ ]] || yn=1
    if [ "$xn" = 1 ] && [ "$yn" = 1 ]; then
      num_cmp "$x" "$y"
      [ "$CMP" = 0 ] || return 0
    elif [ "$xn" = 1 ]; then CMP=-1; return 0
    elif [ "$yn" = 1 ]; then CMP=1; return 0
    elif [[ $x < $y ]]; then CMP=-1; return 0
    elif [[ $x > $y ]]; then CMP=1; return 0
    fi
  done
  # Equal so far: the longer identifier list ranks higher.
  if [ "${#ai[@]}" -lt "${#bi[@]}" ]; then CMP=-1
  elif [ "${#ai[@]}" -gt "${#bi[@]}" ]; then CMP=1
  else CMP=0
  fi
}

# semver_sort: sorts the global array SORTED ascending in place (bottom-up
# merge sort over semver_cmp, no subshell per comparison).
semver_sort() {
  local -a src=("${SORTED[@]}") dst
  local n=${#src[@]} w l m r i j
  for ((w = 1; w < n; w *= 2)); do
    dst=()
    for ((l = 0; l < n; l += 2 * w)); do
      m=$((l + w < n ? l + w : n))
      r=$((l + 2 * w < n ? l + 2 * w : n))
      i=$l j=$m
      while [ "$i" -lt "$m" ] && [ "$j" -lt "$r" ]; do
        semver_cmp "${src[i]}" "${src[j]}"
        if [ "$CMP" -le 0 ]; then dst+=("${src[i]}"); i=$((i + 1))
        else dst+=("${src[j]}"); j=$((j + 1))
        fi
      done
      while [ "$i" -lt "$m" ]; do dst+=("${src[i]}"); i=$((i + 1)); done
      while [ "$j" -lt "$r" ]; do dst+=("${src[j]}"); j=$((j + 1)); done
    done
    src=("${dst[@]}")
  done
  SORTED=("${src[@]}")
}

major_of() { local v="${1#v}"; MAJOR="${v%%.*}"; }

is_prerelease() { local v="${1%%+*}"; [[ $v == *-* ]]; }

# Never a candidate: CUE dev builds and Go pseudo-versions.
is_dev_or_pseudo() {
  local v="${1%%+*}"
  [[ $v == *-0.dev.* || $v == *-dev.* ]] && return 0
  [[ $v =~ [0-9]{14}-[0-9a-f]{12}$ ]]
}

# next_patch <v>: a release only; sets NEXT.
next_patch() {
  local v="$1"
  [[ $v =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
    || usage "next-patch needs a release version (no prerelease or build metadata), got \`$v\`"
  local p="${BASH_REMATCH[3]}" q
  # Add one to a digit string of any length.
  local carry=1 out="" d k
  for ((k = ${#p} - 1; k >= 0; k--)); do
    d=$((${p:k:1} + carry))
    carry=$((d / 10))
    out="$((d % 10))$out"
  done
  [ "$carry" = 0 ] || out="1$out"
  q="$out"
  NEXT="v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$q"
}

# filter_candidates <current> <pre 0|1> <version>...: sets CANDS to the valid,
# non-dev, in-major versions strictly above <current> (releases only unless
# <current> is a prerelease or <pre> is 1), de-duplicated by build metadata
# (first seen kept), newest first.
filter_candidates() {
  local cur="$1" pre="$2" v k cmaj
  shift 2
  major_of "$cur"; cmaj="$MAJOR"
  local allow_pre="$pre"
  ! is_prerelease "$cur" || allow_pre=1
  local seen=" "
  SORTED=()
  for v in "$@"; do
    is_version "$v" || continue
    ! is_dev_or_pseudo "$v" || continue
    major_of "$v"; [ "$MAJOR" = "$cmaj" ] || continue
    if [ "$allow_pre" = 0 ] && is_prerelease "$v"; then continue; fi
    semver_cmp "$v" "$cur"; [ "$CMP" = 1 ] || continue
    k="${v%%+*}"
    case "$seen" in *" $k "*) continue ;; esac
    seen="$seen$k "
    SORTED+=("$v")
  done
  semver_sort
  CANDS=()
  for ((k = ${#SORTED[@]} - 1; k >= 0; k--)); do CANDS+=("${SORTED[k]}"); done
}

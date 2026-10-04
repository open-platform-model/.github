# shellcheck shell=bash
# shellcheck disable=SC2016 # bash -c snippets read their own positional arguments
# SemVer precedence, sort, next-patch and argument errors.
new_fx

cmp_case() { expect "semver-cmp $1 $2" 0 "$3" -- "$R" semver-cmp "$1" "$2"; }
cmp_case v2.0.0-alpha.2 v2.0.0-alpha.10 -1
cmp_case v2.0.0-beta.10 v2.0.0-beta.2 1
cmp_case v2.0.0 v2.0.0-beta.10 1
cmp_case v2.0.0-rc.1 v2.0.0-beta.9 1
cmp_case v1.0.0+a v1.0.0+b 0
cmp_case v1.0.0-beta.1+build.7 v1.0.0-beta.1 0
cmp_case v1.0.0-alpha.beta v1.0.0-alpha.1 1
cmp_case v1.0.0-alpha.1 v1.0.0-alpha.a -1
cmp_case v1.0.0-alpha v1.0.0-alpha.1 -1
cmp_case v1.10.0 v1.9.0 1
cmp_case v1.0.0-alpha.0010 v1.0.0-alpha.9 1
cmp_case v4.5.1 v4.5.1 0
cmp_case v1.0.0-0 v1.0.0-alpha -1
cmp_case v1.0.0-0 v1.0.0-1 -1

expect "semver-cmp: missing v is a usage error" 2 "" "not a v-prefixed" -- "$R" semver-cmp 2.0.0 v2.0.0
expect "semver-cmp: one argument is a usage error" 2 "" -- "$R" semver-cmp v1.0.0
expect "semver-cmp: leading zero is a usage error" 2 "" -- "$R" semver-cmp v01.0.0 v1.0.0
expect "unknown subcommand" 2 "" "unknown subcommand" -- "$R" frobnicate
expect "no subcommand" 2 "" -- "$R"
expect "unknown flag" 2 "" "unknown flag" -- "$R" semver-cmp v1.0.0 v1.0.0 --pre

sorted_in=$'v2.0.0\nv2.0.0-beta.10\nv2.0.0-beta.2\nv2.0.0-alpha.1\nv1.0.0-alpha.beta\nv1.0.0-alpha.1\nv1.0.0-alpha\nv1.0.0-alpha.a\nv1.0.0-rc.1\nv1.0.0'
sorted_out=$'v1.0.0-alpha\nv1.0.0-alpha.1\nv1.0.0-alpha.a\nv1.0.0-alpha.beta\nv1.0.0-rc.1\nv1.0.0\nv2.0.0-alpha.1\nv2.0.0-beta.2\nv2.0.0-beta.10\nv2.0.0'
expect "semver-sort ascending" 0 "$sorted_out" -- bash -c '"$1" semver-sort <<<"$2"' _ "$R" "$sorted_in"
expect "semver-sort: empty input" 0 "" -- bash -c '"$1" semver-sort </dev/null' _ "$R"
expect "semver-sort: malformed line" 2 "" -- bash -c '"$1" semver-sort <<<"v1.0.0
1.0.0"' _ "$R"

expect "next-patch of a release" 0 v1.0.4 -- "$R" next-patch v1.0.3
expect "next-patch carries" 0 v0.1.10 -- "$R" next-patch v0.1.9
expect "next-patch of a prerelease is a usage error" 2 "" -- "$R" next-patch v1.0.0-beta.3
expect "next-patch with build metadata is a usage error" 2 "" -- "$R" next-patch v1.0.0+b1

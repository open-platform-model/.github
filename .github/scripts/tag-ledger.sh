#!/usr/bin/env bash
# Tag ledger and tag-ruleset drift check (read-only against the scanned repos).
#
# Usage: tag-ledger.sh <ledger-dir>
#
# 1. Lists every tag of each repo in REPOS with `git ls-remote --tags` (public
#    repos, no token) and records <repo> <tag> <object sha> <peeled sha>.
# 2. Compares against <ledger-dir>/ledger.tsv. A ledger row whose tag is gone
#    is DELETED; a row whose object or peeled SHA differs is CHANGED. Both are
#    findings unless ACK_FILE records that exact state. Tags not in the
#    ledger yet are APPENDED (never rewritten).
# 3. Asserts the org rulesets below, active and with no excluded refs.
#    tags-immutable is required now; a missing tags-create-app-only or
#    release-branches is reported as a pending warning until the owner
#    creates it, and checked in full from then on:
#      tags-immutable        tag, ~ALL, update + deletion + non_fast_forward,
#                            no bypass actors
#      tags-create-app-only  tag, ~ALL, creation, bypass only the release App
#      release-branches      branch, refs/heads/release/*, deletion +
#                            non_fast_forward + pull_request (squash only),
#                            no bypass actors
#    A same-named ruleset from any source other than the org is a finding.
#    The bypass list is visible only to callers who can edit the ruleset; with
#    the workflow token that one assertion is reported as unverified.
#
# Environment:
#   ORG             GitHub org (default open-platform-model)
#   REPOS           space-separated repo names
#   RELEASE_APP_ID  opm-release-please App id (default 5132303)
#   GH_TOKEN        optional; used for the REST calls
#   ACK_FILE        reviewed acknowledgements, read from the default branch of
#                   the .github repo; never a file on the ledger branch
#   FINDINGS        file that receives one Markdown bullet per finding
#   WARNINGS        file that receives one Markdown bullet per warning
#
# Exit status: 0 when the scan completed (findings are reported via FINDINGS),
# non-zero when the scan itself could not run (network, malformed ledger).
set -euo pipefail

ledger_dir=${1:?usage: tag-ledger.sh <ledger-dir>}
ORG=${ORG:-open-platform-model}
REPOS=${REPOS:?REPOS must list the repos to scan}
RELEASE_APP_ID=${RELEASE_APP_ID:-5132303}
FINDINGS=${FINDINGS:-/dev/stderr}
WARNINGS=${WARNINGS:-/dev/stderr}
API=${GITHUB_API_URL:-https://api.github.com}

ledger="$ledger_dir/ledger.tsv"
header=$'# repo\ttag\tobject\tpeeled\tfirst_seen_utc'
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [[ ! -f "$ledger" ]]; then
  printf '%s\n' "$header" >"$ledger"
fi
if [[ "$(head -n1 "$ledger")" != "$header" ]]; then
  echo "::error::$ledger does not start with the expected header; refusing to touch it" >&2
  exit 2
fi

finding() { printf -- '- %s\n' "$*" >>"$FINDINGS"; echo "::error::$*"; }
warning() { printf -- '- %s\n' "$*" >>"$WARNINGS"; echo "::warning::$*"; }

# --- 1. current tags -------------------------------------------------------
current="$work/current.tsv"
: >"$current"
for repo in $REPOS; do
  raw="$work/$repo.refs"
  # A failed listing must abort: treating it as "no tags" would report every
  # ledger row as deleted.
  git ls-remote --tags "https://github.com/$ORG/$repo.git" >"$raw"
  # Lines are "<sha>\trefs/tags/<name>" and, for annotated tags, a second
  # "<commit>\trefs/tags/<name>^{}" with the peeled commit.
  awk -F'\t' -v repo="$repo" '
    {
      ref = substr($2, 11)  # strip "refs/tags/"
      if (ref ~ /\^\{\}$/) { peeled[substr(ref, 1, length(ref) - 3)] = $1 }
      else { obj[ref] = $1; order[++n] = ref }
    }
    END {
      for (i = 1; i <= n; i++) {
        t = order[i]
        p = (t in peeled) ? peeled[t] : obj[t]
        printf "%s\t%s\t%s\t%s\n", repo, t, obj[t], p
      }
    }' "$raw" >>"$current"
done

# --- 2. compare with the ledger --------------------------------------------
# Only repos scanned in this run are compared, so dropping a repo from REPOS
# does not report its history as deleted.
appended="$work/appended.tsv"
drift="$work/drift.txt"
awk -F'\t' -v OFS='\t' -v now="$now" -v repos="$REPOS" \
  -v appended="$appended" -v drift="$drift" '
  BEGIN { split(repos, r, " "); for (i in r) scanned[r[i]] = 1 }
  FNR == NR {
    if ($0 ~ /^#/ || $0 == "") next
    key = $1 SUBSEP $2
    if (key in lobj) next  # first record wins; the ledger is append-only
    lobj[key] = $3; lpeel[key] = $4; lseen[key] = $5; lorder[++ln] = key
    next
  }
  {
    key = $1 SUBSEP $2
    cobj[key] = $3; cpeel[key] = $4
    if (!(key in lobj)) print $1, $2, $3, $4, now > appended
  }
  END {
    for (i = 1; i <= ln; i++) {
      key = lorder[i]; split(key, k, SUBSEP)
      if (!(k[1] in scanned)) continue
      if (!(key in cobj)) {
        print "DELETED", k[1], k[2], lobj[key], lpeel[key], lseen[key], "-", "-" > drift
      } else if (cobj[key] != lobj[key] || cpeel[key] != lpeel[key]) {
        print "CHANGED", k[1], k[2], lobj[key], lpeel[key], lseen[key], cobj[key], cpeel[key] > drift
      }
    }
  }' "$ledger" "$current"

# A drift row the owner has reviewed is acknowledged by a PR to the default
# branch of the .github repo adding "<repo> <tag> <object> <peeled> <note>"
# (tab-separated, "-" for both SHAs of a deleted tag) to ACK_FILE. It is then
# reported as a warning, and only while the live state still equals the
# acknowledged one. The file is deliberately not on the ledger branch: that
# branch takes plain pushes, and an acknowledgement must be reviewed.
ack=${ACK_FILE:-}
if [[ -s "$drift" ]]; then
  while IFS=$'\t' read -r kind repo tag lobj lpeel lseen cobj cpeel; do
    msg="tag $kind \`$repo\` \`$tag\` (ledger: object $lobj, peeled $lpeel, first seen $lseen"
    [[ "$kind" == CHANGED ]] && msg+="; now: object $cobj, peeled $cpeel"
    msg+=")"
    if [[ -n "$ack" && -f "$ack" ]] && awk -F'\t' -v r="$repo" -v t="$tag" -v o="$cobj" -v p="$cpeel" \
      '!/^#/ && $1 == r && $2 == t && $3 == o && $4 == p { found = 1 } END { exit !found }' "$ack"; then
      warning "acknowledged: $msg"
    else
      finding "$msg"
    fi
  done <"$drift"
fi
new_count=0
if [[ -s "$appended" ]]; then
  cat "$appended" >>"$ledger"
  new_count=$(wc -l <"$appended")
fi
echo "tag-ledger: $(wc -l <"$current") tags scanned, $new_count appended"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "appended=$new_count" >>"$GITHUB_OUTPUT"
fi

# --- 3. org rulesets ---------------------------------------------------------
# GET returns the body in $work/body.json and the HTTP status in $status. A
# 401/403 with the token is retried anonymously (the repos are public and
# anonymous reads of rulesets work), so a token refused for another repo does
# not silently switch the check off.
api_get() {
  local url="$API/$1" common=(-sS -o "$work/body.json" -w '%{http_code}'
    -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28')
  if [[ -n "${GH_TOKEN:-}" ]]; then
    status=$(curl "${common[@]}" -H "Authorization: Bearer $GH_TOKEN" "$url")
    [[ "$status" == 401 || "$status" == 403 ]] || return 0
  fi
  status=$(curl "${common[@]}" "$url")
}

# check_ruleset <repo> <required|pending> <name> <target> <include> <bypass> <rule>...
#   pending: the ruleset is planned but not created yet; its absence is a
#   warning, anything wrong with it once it exists is a finding.
#   bypass: "none" (empty list) or "app:<id>" (exactly that Integration, mode
#   always). The ruleset must come from the org: a repo-level ruleset of the
#   same name can be edited by repo admins and does not count.
check_ruleset() {
  local repo=$1 need=$2 name=$3 target=$4 include=$5 bypass=$6
  shift 6
  api_get "repos/$ORG/$repo/rulesets?includes_parents=true&targets=$target&per_page=100"
  case "$status" in
    200) ;;
    404)
      finding "ruleset \`$repo\`: listing $target rulesets returned HTTP 404 for a repo that exists"
      return ;;
    *)
      echo "::error::$repo: listing $target rulesets returned HTTP $status" >&2
      exit 3 ;;
  esac
  local id others
  id=$(jq -r --arg n "$name" --arg t "$target" --arg o "$ORG" \
    '[.[] | select(.name == $n and .target == $t and .source_type == "Organization" and .source == $o)][0].id // empty' \
    "$work/body.json")
  others=$(jq -c --arg n "$name" --arg o "$ORG" \
    '[.[] | select(.name == $n and (.source_type != "Organization" or .source != $o)) | {source_type, source}]' \
    "$work/body.json")
  [[ "$others" == "[]" ]] ||
    finding "ruleset \`$repo\`: a ruleset named \`$name\` comes from a source other than the org: $others"
  if [[ -z "$id" ]]; then
    if [[ "$need" == pending ]]; then
      warning "pending: \`$repo\`: org $target ruleset \`$name\` does not exist yet"
    else
      finding "ruleset \`$repo\`: no org $target ruleset named \`$name\` applies"
    fi
    return
  fi
  api_get "repos/$ORG/$repo/rulesets/$id"
  if [[ "$status" != 200 ]]; then
    finding "ruleset \`$repo\`: reading \`$name\` ($id) returned HTTP $status"
    return
  fi
  local b="$work/body.json" enforcement excl rule
  enforcement=$(jq -r '.enforcement' "$b")
  [[ "$enforcement" == active ]] ||
    finding "ruleset \`$repo\`: \`$name\` enforcement is $enforcement, expected active"
  jq -e --arg i "$include" '.conditions.ref_name.include | index($i)' "$b" >/dev/null ||
    finding "ruleset \`$repo\`: \`$name\` does not include \`$include\` (include: $(jq -c '.conditions.ref_name.include' "$b"))"
  excl=$(jq -c '.conditions.ref_name.exclude // []' "$b")
  [[ "$excl" == "[]" ]] ||
    finding "ruleset \`$repo\`: \`$name\` excludes refs: $excl"
  for rule in "$@"; do
    jq -e --arg t "$rule" 'any(.rules[]; .type == $t)' "$b" >/dev/null ||
      finding "ruleset \`$repo\`: \`$name\` lacks the $rule rule"
  done
  if jq -e 'any(.rules[]; .type == "pull_request")' "$b" >/dev/null; then
    jq -e '[.rules[] | select(.type == "pull_request") | .parameters.allowed_merge_methods // []][0] == ["squash"]' "$b" >/dev/null ||
      finding "ruleset \`$repo\`: \`$name\` pull_request rule allows merge methods other than squash"
  fi
  # bypass_actors is only returned to callers who can edit the ruleset; an
  # absent field is unknown, not empty. CI therefore cannot prove the bypass
  # list with GITHUB_TOKEN; the owner checks it in Settings > Rules.
  if jq -e 'has("bypass_actors")' "$b" >/dev/null; then
    local want got
    case "$bypass" in
      none) want='[]' ;;
      app:*) want=$(jq -cn --argjson id "${bypass#app:}" '[{actor_id: $id, actor_type: "Integration", bypass_mode: "always"}]') ;;
    esac
    got=$(jq -c '[.bypass_actors[] | {actor_id, actor_type, bypass_mode}] | sort' "$b")
    [[ "$got" == "$want" ]] ||
      finding "ruleset \`$repo\`: \`$name\` bypass list is $got, expected $want"
  else
    warning "\`$repo\`: the workflow token cannot see the bypass list of \`$name\`; bypass assertion not verified by CI"
  fi
  local cub
  cub=$(jq -r '.current_user_can_bypass // empty' "$b")
  if [[ -n "$cub" && "$cub" != never ]]; then
    finding "ruleset \`$repo\`: the workflow token can bypass \`$name\` ($cub)"
  fi
}

for repo in $REPOS; do
  check_ruleset "$repo" required tags-immutable tag '~ALL' none update deletion non_fast_forward
  check_ruleset "$repo" pending tags-create-app-only tag '~ALL' "app:$RELEASE_APP_ID" creation
  check_ruleset "$repo" pending release-branches branch 'refs/heads/release/*' none deletion non_fast_forward pull_request
done

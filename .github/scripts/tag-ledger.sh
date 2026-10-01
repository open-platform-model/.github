#!/usr/bin/env bash
# Tag ledger and tag-ruleset drift check (read-only against the scanned repos).
#
# Usage: tag-ledger.sh <ledger-dir>
#
# 1. Lists every tag of each repo in REPOS with `git ls-remote --tags` (public
#    repos, no token) and records <repo> <tag> <object sha> <peeled sha>.
# 2. Compares against <ledger-dir>/ledger.tsv. A ledger row whose tag is gone
#    is DELETED; a row whose object or peeled SHA differs is CHANGED. Both are
#    findings unless acknowledged.tsv records that exact state. Tags not in
#    the ledger yet are APPENDED (never rewritten).
# 3. Asserts the tag ruleset RULESET_NAME applies to each repo: active, target
#    tag, include ~ALL, rules update + deletion + non_fast_forward, and an empty
#    bypass list. A field the token cannot see is skipped with a warning.
#
# Environment:
#   ORG           GitHub org (default open-platform-model)
#   REPOS         space-separated repo names
#   RULESET_NAME  default tags-immutable
#   GH_TOKEN      optional; used for the REST calls (rate limit only)
#   FINDINGS      file that receives one Markdown bullet per finding
#   WARNINGS      file that receives one Markdown bullet per skipped check
#
# Exit status: 0 when the scan completed (findings are reported via FINDINGS),
# non-zero when the scan itself could not run (network, malformed ledger).
set -euo pipefail

ledger_dir=${1:?usage: tag-ledger.sh <ledger-dir>}
ORG=${ORG:-open-platform-model}
REPOS=${REPOS:?REPOS must list the repos to scan}
RULESET_NAME=${RULESET_NAME:-tags-immutable}
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

# A drift row the owner has reviewed is acknowledged by appending
# "<repo> <tag> <object> <peeled> <note>" (tab-separated, "-" for both SHAs of
# a deleted tag) to acknowledged.tsv on the ledger branch. It is then reported
# as a warning, and only while the live state still equals the acknowledged one.
ack="$ledger_dir/acknowledged.tsv"
if [[ -s "$drift" ]]; then
  while IFS=$'\t' read -r kind repo tag lobj lpeel lseen cobj cpeel; do
    msg="tag $kind $repo $tag (ledger: object $lobj, peeled $lpeel, first seen $lseen"
    [[ "$kind" == CHANGED ]] && msg+="; now: object $cobj, peeled $cpeel"
    msg+=")"
    if [[ -f "$ack" ]] && awk -F'\t' -v r="$repo" -v t="$tag" -v o="$cobj" -v p="$cpeel" \
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

# --- 3. tag ruleset --------------------------------------------------------
# GET returns the body on stdout and the HTTP status in $status.
api_get() {
  local auth=()
  [[ -n "${GH_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GH_TOKEN")
  status=$(curl -sS -o "$work/body.json" -w '%{http_code}' \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' "${auth[@]}" "$API/$1")
}

for repo in $REPOS; do
  api_get "repos/$ORG/$repo/rulesets?includes_parents=true&targets=tag&per_page=100"
  case "$status" in
    200) ;;
    401 | 403 | 404)
      warning "$repo: listing rulesets returned HTTP $status with the workflow token; ruleset check skipped (no token escalation by design)"
      continue ;;
    *)
      echo "::error::$repo: listing rulesets returned HTTP $status" >&2
      exit 3 ;;
  esac
  id=$(jq -r --arg n "$RULESET_NAME" \
    '[.[] | select(.name == $n and .target == "tag")][0].id // empty' "$work/body.json")
  if [[ -z "$id" ]]; then
    finding "ruleset $repo: no tag ruleset named $RULESET_NAME applies"
    continue
  fi
  api_get "repos/$ORG/$repo/rulesets/$id"
  if [[ "$status" != 200 ]]; then
    warning "$repo: reading ruleset $id returned HTTP $status; ruleset details skipped"
    continue
  fi
  b="$work/body.json"
  enforcement=$(jq -r '.enforcement' "$b")
  [[ "$enforcement" == active ]] ||
    finding "ruleset $repo: $RULESET_NAME enforcement is $enforcement, expected active"
  jq -e '.conditions.ref_name.include | index("~ALL")' "$b" >/dev/null ||
    finding "ruleset $repo: $RULESET_NAME does not include ~ALL (include: $(jq -c '.conditions.ref_name.include' "$b"))"
  excl=$(jq -c '.conditions.ref_name.exclude // []' "$b")
  [[ "$excl" == "[]" ]] ||
    finding "ruleset $repo: $RULESET_NAME excludes refs: $excl"
  for rule in update deletion non_fast_forward; do
    jq -e --arg t "$rule" 'any(.rules[]; .type == $t)' "$b" >/dev/null ||
      finding "ruleset $repo: $RULESET_NAME lacks the $rule rule"
  done
  # bypass_actors is only returned to callers who can edit the ruleset; an
  # absent field is unknown, not empty. Any entry, in any bypass_mode
  # (including exempt, which skips the rules without an audit entry), fails.
  if jq -e 'has("bypass_actors")' "$b" >/dev/null; then
    n=$(jq '.bypass_actors | length' "$b")
    [[ "$n" == 0 ]] ||
      finding "ruleset $repo: $RULESET_NAME has $n bypass actor(s): $(jq -c '.bypass_actors' "$b")"
  else
    warning "$repo: the workflow token cannot see the bypass list of $RULESET_NAME; empty-bypass assertion skipped"
  fi
  cub=$(jq -r '.current_user_can_bypass // empty' "$b")
  if [[ -n "$cub" && "$cub" != never ]]; then
    finding "ruleset $repo: the workflow token can bypass $RULESET_NAME ($cub)"
  fi
done

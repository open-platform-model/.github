#!/usr/bin/env bash
# Check out the tag-ledger branch into <ledger-dir> and prove it was only ever
# appended to since the last run that trusted it.
#
# Usage: ledger-integrity.sh <ledger-dir>
#
# The anchor is the ledger commit the previous trusted run ended on. The
# workflow keeps it outside the ledger branch (as the name of a workflow
# artifact), so deleting or rewriting the branch cannot also rewrite the
# anchor. The ledger is trusted when:
#   - the branch exists,
#   - ANCHOR is set and is an ancestor of the branch head, and
#   - ledger.tsv at the anchor is a byte prefix of ledger.tsv at the head
#     (rows were appended, none edited or removed).
# Every commit after the anchor was written by something other than a trusted
# run, so each row it appended is reported as a notice (it reaches the issue).
#
# Anything else is a finding, never a silent re-baseline. The only way past
# one is BOOTSTRAP=true (workflow_dispatch input), which creates the branch
# when it is missing or accepts the current head as the new anchor, and is
# always reported as a notice in the drift issue.
#
# Environment:
#   LEDGER_BRANCH  branch name (default tag-ledger)
#   REMOTE_URL     default https://github.com/$GITHUB_REPOSITORY.git
#   GH_TOKEN       optional; sent as the git credential for fetch and push
#   ANCHOR         last trusted ledger commit, empty when none was found
#   BOOTSTRAP      "true" to create or re-anchor the ledger
#   FINDINGS       file that receives one Markdown bullet per finding
#   NOTICES        file that receives one Markdown bullet per bootstrap event
#                  or row appended outside a trusted run
#
# Outputs (GITHUB_OUTPUT): trusted=true|false.
# Exit status: non-zero only when the check itself could not run.
set -euo pipefail

dir=${1:?usage: ledger-integrity.sh <ledger-dir>}
LEDGER_BRANCH=${LEDGER_BRANCH:-tag-ledger}
REMOTE_URL=${REMOTE_URL:-https://github.com/${GITHUB_REPOSITORY:?}.git}
ANCHOR=${ANCHOR:-}
BOOTSTRAP=${BOOTSTRAP:-false}
FINDINGS=${FINDINGS:-/dev/stderr}
NOTICES=${NOTICES:-/dev/stderr}

finding() { printf -- '- %s\n' "$*" >>"$FINDINGS"; echo "::error::$*"; }
notice() { printf -- '- %s\n' "$*" >>"$NOTICES"; echo "::notice::$*"; }
output() { [[ -z "${GITHUB_OUTPUT:-}" ]] || echo "$1" >>"$GITHUB_OUTPUT"; echo "$1"; }

git init -q "$dir"
cd "$dir"
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
if [[ -n "${GH_TOKEN:-}" ]]; then
  git config "http.https://github.com/.extraheader" \
    "AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_TOKEN" | base64 -w0)"
fi
git remote add origin "$REMOTE_URL"

rc=0
git ls-remote --exit-code --heads origin "refs/heads/$LEDGER_BRANCH" >/dev/null || rc=$?
case "$rc" in
  0) ;;
  2)
    # The branch is missing. Creating it is a deliberate act, never a side
    # effect of a scheduled run.
    if [[ "$BOOTSTRAP" != true ]]; then
      finding "ledger branch \`$LEDGER_BRANCH\` does not exist${ANCHOR:+ (last trusted commit \`$ANCHOR\`)}; it was deleted or never created. Run the workflow by hand with bootstrap=true to create it."
      output trusted=false
      exit 0
    fi
    notice "bootstrap: created a new ledger branch \`$LEDGER_BRANCH\`${ANCHOR:+, replacing one last trusted at \`$ANCHOR\`}; every current tag is recorded as the new baseline."
    git checkout -q --orphan "$LEDGER_BRANCH"
    cat >README.md <<'EOF'
# tag-ledger

Append-only record of every release tag in the open-platform-model repos that
release, written by `.github/workflows/tag-ledger.yml` on `main`. Rows are
only ever appended; never edit, reorder or delete one, and never delete or
force-push this branch. Each run proves the branch head descends from the
commit the previous run ended on and that no row changed; anything else
fails the run. Acknowledgements of reviewed drift are not kept here: they go
by PR into `tag-ledger/acknowledged.tsv` on the default branch.
EOF
    git add README.md
    output trusted=true
    exit 0
    ;;
  *)
    echo "::error::git ls-remote for $LEDGER_BRANCH failed with exit code $rc" >&2
    exit 1
    ;;
esac

# Full history: the ancestry check needs every ledger commit.
git fetch -q origin "refs/heads/$LEDGER_BRANCH:refs/remotes/origin/$LEDGER_BRANCH"
git checkout -q -b "$LEDGER_BRANCH" "origin/$LEDGER_BRANCH"
head=$(git rev-parse HEAD)

problem=
if [[ -z "$ANCHOR" ]]; then
  problem="no trusted anchor commit was found (the anchor artifact is missing or expired), so the history of \`$LEDGER_BRANCH\` (head \`$head\`) cannot be verified"
elif ! git cat-file -e "$ANCHOR^{commit}" 2>/dev/null ||
  ! git merge-base --is-ancestor "$ANCHOR" HEAD; then
  problem="the last trusted ledger commit \`$ANCHOR\` is not an ancestor of \`$LEDGER_BRANCH\` head \`$head\`: the branch history was rewritten"
else
  f=ledger.tsv
  if git cat-file -e "$ANCHOR:$f" 2>/dev/null; then
    old=$(mktemp)
    git show "$ANCHOR:$f" >"$old"
    size=$(wc -c <"$old")
    if [[ ! -f "$f" ]] || ! cmp -s -n "$size" "$old" "$f" || (($(wc -c <"$f") < size)); then
      problem="\`$f\` at head \`$head\` does not start with its content at the last trusted commit \`$ANCHOR\`: a recorded row was edited or removed"
    else
      # Rows appended after the anchor were not written by a trusted run.
      while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        notice "row appended to \`$f\` outside a trusted run (after \`$ANCHOR\`): \`${row//$'\t'/ }\`"
      done < <(tail -c +"$((size + 1))" "$f")
    fi
    rm -f "$old"
  fi
fi

if [[ -z "$problem" ]]; then
  output trusted=true
elif [[ "$BOOTSTRAP" == true ]]; then
  notice "bootstrap: accepted \`$LEDGER_BRANCH\` head \`$head\` as the new anchor although $problem."
  output trusted=true
else
  finding "ledger integrity: $problem. Nothing is appended until this is reviewed; run the workflow by hand with bootstrap=true to accept the current head."
  output trusted=false
fi

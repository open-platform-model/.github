# tag-ledger: the daily tag drift check

Covers what the daily check records, how it trusts its own ledger, the ruleset assertions, how to
answer a drift finding and the token it holds. The workflow is in `.github/workflows/` and its
script in `.github/scripts/`. The tag rules themselves are in the workspace `references/releases.md`.

## Why it exists

Release tags are immutable: no tag under `refs/tags/` is moved, deleted or re-created, and a broken
release is fixed by releasing the next version. The docs site pins refs per site version, so a moved
tag silently changes published docs. The org rulesets prevent it. This check detects it if
prevention fails or is switched off. It is detection only.

Scope: the `REPOS` list in the workflow. A releasing repo that is not in the list is not scanned,
although the org tag rulesets cover it.

## What each run does

It runs daily and on manual dispatch.

1. **Verifies the ledger before it trusts it.** `ledger.tsv` on the `tag-ledger` branch of this repo
   holds one row per tag: repo, tag, object SHA, peeled SHA, first seen. Every trusted run ends by
   uploading an artifact named `tag-ledger-anchor-<commit>`, outside the branch. The next run takes
   the newest such artifact from a scheduled or dispatched run on the default branch. It requires
   the branch head to descend from that commit and `ledger.tsv` to start with its content at that
   commit. A row appended after the anchor was not written by a trusted run, and the issue lists it
   as a notice. A missing branch, a missing or expired anchor, rewritten history or an edited row is
   a finding, and nothing is appended. The ledger is never re-created or re-baselined silently: only
   a manual run with `bootstrap: true` creates the branch or accepts its head, and it reports what
   it did. The first run must be a bootstrap run.
2. **Records tags.** `git ls-remote --tags` (public repos, no token) gives each tag's object SHA
   and, for an annotated tag, the peeled commit. New tags are appended with a plain push, never
   forced. Rows are never rewritten.
3. **Fails on drift.** A ledger tag that is gone, or whose object or peeled SHA changed, fails the
   run. The ledger keeps the original row as evidence.
4. **Checks the org rulesets.** Each scanned repo must have these, from the org (a same-named
   repo-level ruleset is a finding), active and excluding nothing. `tags-immutable` is required.
   `tags-create-app-only` and `release-branches` are treated as pending: while one is missing the
   run reports a warning in the job summary. The script still treats these two as pending even
   though both exist, so a repo dropping out of either is a warning until they are made required.

| Ruleset | Target | Refs | Rules | Bypass |
| --- | --- | --- | --- | --- |
| `tags-immutable` | tag | all | update, deletion, non_fast_forward | none |
| `tags-create-app-only` | tag | all | creation | only the release-please App, always |
| `release-branches` | branch | `refs/heads/release/*` | deletion, non_fast_forward, pull_request (squash only) | none |

CI does not verify the bypass lists. The API returns them only to callers who can edit the ruleset,
so with `GITHUB_TOKEN` that assertion is listed under "Not verified" in the job summary. The owner
checks bypass lists in the repo settings. The workflow never asks for a stronger token.

Any finding, and any failed step, opens an issue titled `tag-ledger: release tag or ruleset drift`,
or comments on it while it is open, and fails the run. A bootstrap is reported on the same issue
without failing.

## Responding to drift

Never move a tag back: that is a second mutation. Release the next version. Then open a PR here that
adds a row to the acknowledgement file in `tag-ledger/` (repo, tag, live object SHA, live peeled
SHA, note; tab-separated, `-` for both SHAs of a deleted tag). Until it merges, every run stays red.
Once merged, that exact state is reported as a warning, and any further change fails again.

Acknowledgements live on the default branch, never on the ledger branch. The ledger branch takes
plain pushes (the job's own token can write it), so a row there could silence a finding with no
review. The default branch already holds this workflow's code: whoever can change it can change the
check itself, so the acknowledgement file adds no new way in. A PR there passes `mention-guard` and
review.

## Token

`GITHUB_TOKEN` with `contents: write`, `issues: write` and `actions: read`. `contents: write` covers
every branch of this repo, `main` included (the branch the org ruleset reads `mention-guard` from).
The job pushes only to `tag-ledger`. The scanned repos are only read.

## Owner setup

The owner adds a branch ruleset on `refs/heads/tag-ledger` in this repo (deletion, non_fast_forward,
no bypass) and one on the default branch that requires a pull request, so an acknowledgement cannot
land by direct push. The first run is a manual one with `bootstrap: true`.

## Pitfalls

- Moving a tag to make the check green: it is a second mutation. Acknowledge and release the next
  version.
- An acknowledgement row pushed to the ledger branch: it is evidence only and silences nothing.
- Treating `bootstrap: true` as a routine fix: it accepts the current branch head and is for the first run only.

## Check before you finish

- [ ] The ledger code appends with a plain push and never rewrites a row.
- [ ] A new finding kind opens or comments on the one drift issue and fails the run.
- [ ] An acknowledgement lands by PR on the default branch only.
- [ ] The token permissions did not widen without a comment that names why.

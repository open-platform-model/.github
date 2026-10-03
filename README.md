# open-platform-model/.github

Org-wide GitHub configuration. Currently hosts two things: the `mention-guard`
required PR workflow and the `tag-ledger` drift check.

## `mention-guard` (required PR workflow)

An organization ruleset ("Require workflows to pass before merging") runs
[`.github/workflows/mention-guard.yml`](.github/workflows/mention-guard.yml)
on every pull request in every repo of this org. It scans the **PR title, PR
body, and every branch commit message**. All three are public on the PR, and
the squash commit is built from them: release-please later copies it into
changelogs and GitHub release notes, which re-render mentions.

What the squash commit carries depends on the repo's merge settings. Repos that
squash with `squash_merge_commit_message: COMMIT_MESSAGES` put the branch commit
messages into its body. The release repos (core, catalog_opm, library,
opm-operator, cli, opm) switch to `BLANK` with a `PR_TITLE` title once the owner
applies the
[workspace `RELEASING.md` "Owner settings"](https://github.com/open-platform-model/workspace/blob/main/RELEASING.md#owner-settings),
so only the PR title reaches `main` there; until then they still squash with
`COMMIT_MESSAGES`. Every other org repo stays on `COMMIT_MESSAGES`. That page is
the source of truth for the settings; check it, or `gh api
repos/open-platform-model/<repo>`, rather than this paragraph.

It fails the PR when it finds:

| Rule | Example that fails | Why |
| --- | --- | --- |
| Bare `@mention` | `@v1`, `->@v1`, `"@v1"`, `` `@v1` `` | GitHub pings the real user `v1`; commit messages are not Markdown, so backticks do not protect. Glue the `@` to a word character (`core@v2`) or drop it. |
| Session identifiers | `Claude-Session: …`, `claude.ai/code/session_…` | Private, meaningless to readers, permanent. |
| AI generated-with footers | `🤖 Generated with [Claude Code]` | Never allowed. |
| Embellished AI co-author trailers | `Co-Authored-By: Claude Fable 5 <…>` | The only allowed AI attribution is exactly `Co-Authored-By: Claude <noreply@anthropic.com>`. Human co-author trailers are untouched. |

**What passes:** `opmodel.dev/core@v2`, `user@example.com`, `@@` diff hunk
headers, human `Co-Authored-By` trailers, and the plain
`Co-Authored-By: Claude <noreply@anthropic.com>` trailer.

## Bot exceptions

Two carve-outs keep automated PRs mergeable. Neither weakens the rule for
anything that reaches permanent history.

**1. Automation handles are allowed anywhere.** `@dependabot`, `@renovate`,
`@renovate-bot`, `@github-actions` and `@dependabot-preview` never count as
violations. Every Dependabot PR body ends with its command list
(`` `@dependabot rebase` ``, `` `@dependabot recreate` ``, …), which failed the
gate on every dependency bump in the org. The rule exists so an uninvolved
stranger is not pinged and left with a permanent backlink on their profile —
these are bots already on the thread, and the handle has to stay literal or the
documented command stops working. The match is exact: `@dependabotx` still
fails.

**2. A bot-authored PR body is advisory, not blocking.** Findings there are
reported as notices and the job passes. The body is generated boilerplate no
maintainer can reword — Dependabot rewrites it on every rebase or recreate —
and no repo in this org puts the PR body into the squash commit (repos squash
with `COMMIT_MESSAGES` or, in the release repos, `BLANK`; neither includes the
PR body), so it never reaches permanent history. Without this, the only way
to merge a release-please PR whose changelog quotes a contributor would be an
admin bypass.

The **PR title** and **commit messages** of a bot PR are still hard failures.
The title becomes the squash title and the release-notes entry (except in a
one-commit PR in a repo on GitHub's default `COMMIT_OR_PR_TITLE`, where the
commit subject does). The commit messages become the squash body in repos that
squash with `COMMIT_MESSAGES`, and stay public on the PR everywhere.

**Limits (by design):** the gate cannot un-ping a mention typed into a PR
title/body (that fires on submit — the gate keeps it out of *permanent*
history), and it cannot see a squash message retyped in the merge box. The
local `commit-msg` hook in `core` covers the laptop side.

**Break-glass:** org admins are on the ruleset's bypass list. For a false
positive, prefer rewording; bypass is for emergencies.

Changing the rules: edit the workflow here on `main` — the ruleset references
this file by path, so every repo picks the change up immediately.

## `tag-ledger` (daily drift check)

Release tags are immutable: no tag under `refs/tags/` is ever moved, deleted or
re-created, and a broken release is fixed by releasing the next version. The
docs site pins refs per site version, so a moved tag silently changes published
docs. The org rulesets prevent it;
[`.github/workflows/tag-ledger.yml`](.github/workflows/tag-ledger.yml) detects
it if prevention ever fails or is switched off.

Scope: `core`, `library`, `catalog_opm`, `cli`, `opm-operator` (the repos that
release). `modules` is out of scope. The list is `REPOS` in the workflow.

It runs daily at 04:17 UTC and on manual dispatch. Each run:

1. **Verifies the ledger before trusting it.** `ledger.tsv` on the
   `tag-ledger` branch of this repo holds one row per tag (repo, tag, object
   SHA, peeled SHA, first seen). Every trusted run ends by uploading an
   artifact named `tag-ledger-anchor-<commit>`, outside the branch. The next
   run takes the newest such artifact from a scheduled or dispatched run of
   this workflow on the default branch, and requires the branch head to
   descend from that commit and `ledger.tsv` to start with its content at it.
   Rows appended after the anchor were not written by a trusted run; each one
   is reported in the issue as a notice. A missing branch,
   a missing or expired anchor, rewritten history or an edited row is a
   finding, and nothing is appended. The ledger is never re-created or
   re-baselined silently: only a manual run with `bootstrap: true` creates the
   branch or accepts its current head, and that run reports what it did in the
   issue. The first run must be such a bootstrap run.
2. **Records tags.** `git ls-remote --tags` (public repos, no token) gives each
   tag's object SHA and, for annotated tags, the peeled commit. New tags are
   appended with a plain push (never forced); rows are never rewritten.
3. **Fails on drift.** A ledger tag that is gone, or whose object or peeled SHA
   changed, fails the run. The ledger keeps the original row as evidence.
4. **Checks the org rulesets.** Each repo must have these, from the org (a
   same-named repo-level ruleset is a finding), active and excluding nothing.
   `tags-immutable` is required now. `tags-create-app-only` and
   `release-branches` are planned: while one does not exist, the run reports
   it as a pending warning in the job summary; once it exists, every
   assertion below applies to it.

   | Ruleset | Target | Refs | Rules | Bypass |
   | --- | --- | --- | --- | --- |
   | `tags-immutable` | tag | `~ALL` | update, deletion, non_fast_forward | none |
   | `tags-create-app-only` | tag | `~ALL` | creation | only the `opm-release-please` App (5132303), always |
   | `release-branches` | branch | `refs/heads/release/*` | deletion, non_fast_forward, pull_request (squash only) | none |

   **CI does not verify the bypass lists.** The API returns them only to
   callers who can edit the ruleset, so with `GITHUB_TOKEN` that assertion is
   listed under "Not verified" in the job summary. The owner checks bypass
   lists in Settings > Rules; the workflow never asks for a stronger token.

Any finding, and any failed step, opens an issue titled
`tag-ledger: release tag or ruleset drift`, or comments on it while it is
open, and fails the run. A bootstrap is reported on the same issue without
failing.

**Responding to drift.** Never move a tag back: that is a second mutation.
Release the next version, then open a PR here adding a row to
[`tag-ledger/acknowledged.tsv`](tag-ledger/acknowledged.tsv) (repo, tag, live
object SHA, live peeled SHA, note; tab-separated, `-` for both SHAs of a
deleted tag). Until it merges, every run stays red. Once merged, that exact
state is reported as a warning; any further change fails again.

Acknowledgements live on the default branch, never on the ledger branch. The
ledger branch takes plain pushes (the job's own token can write it), so a row
there could silence a finding without anyone reviewing it. The default branch
already holds this workflow's code: whoever can change it can change the check
itself, so the acknowledgement file adds no new way in. A PR there passes
`mention-guard` and review.

**Token:** `GITHUB_TOKEN` with `contents: write`, `issues: write` and
`actions: read`. `contents: write` covers every branch of this repo, `main`
included (the branch the org ruleset reads `mention-guard.yml` from); the job
only pushes to `tag-ledger`. The scanned repos are only read.

**Before merging:** the owner confirms `tags-immutable` (the other two may
follow later and show as pending), adds a branch ruleset on
`refs/heads/tag-ledger` in this repo (deletion, non_fast_forward, no bypass)
and one on this repo's default branch requiring a pull request, so an
acknowledgement cannot land by direct push. The first run is then a manual
one with `bootstrap: true`.

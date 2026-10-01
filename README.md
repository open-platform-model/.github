# open-platform-model/.github

Org-wide GitHub configuration. Currently hosts two things: the `mention-guard`
required PR workflow and the `tag-ledger` drift check.

## `mention-guard` (required PR workflow)

An organization ruleset ("Require workflows to pass before merging") runs
[`.github/workflows/mention-guard.yml`](.github/workflows/mention-guard.yml)
on every pull request in every repo of this org. It scans the **PR title, PR
body, and every branch commit message** — the surfaces that become the squash
commit (all repos use `squash_merge_commit_message: COMMIT_MESSAGES`) and later
leak into release-please changelogs and GitHub release notes.

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
and no repo in this org puts the PR body into the squash commit (every repo
uses `squash_merge_commit_message: COMMIT_MESSAGES`), so it never reaches
permanent history. Without this, the only way to merge a release-please PR
whose changelog quotes a contributor would be an admin bypass.

The **PR title** and **commit messages** of a bot PR are still hard failures —
those are the surfaces that become the squash commit and the release notes.

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
docs. The org tag ruleset `tags-immutable` prevents it;
[`.github/workflows/tag-ledger.yml`](.github/workflows/tag-ledger.yml) detects
it if prevention ever fails or is switched off.

Scope: `core`, `library`, `catalog_opm`, `cli`, `opm-operator` (the repos that
release). `modules` is out of scope for now. The list is `REPOS` in the
workflow.

It runs daily at 04:17 UTC and on manual dispatch. For each repo it:

1. **Records tags in an append-only ledger.** `git ls-remote --tags` (public
   repos, no token) gives each tag's object SHA and, for annotated tags, the
   peeled commit. `ledger.tsv` on the `tag-ledger` branch of this repo holds
   one row per tag: repo, tag, object, peeled, first seen. New tags are
   appended with a plain push (never forced); rows are never rewritten. The
   workflow creates the branch on its first run.
2. **Fails on drift.** A ledger tag that is gone, or whose object or peeled SHA
   changed, fails the run. The ledger keeps the original row as evidence.
3. **Checks the ruleset.** `GET /repos/{owner}/{repo}/rulesets` must list a tag
   ruleset named `tags-immutable` that is active, includes `~ALL`, excludes
   nothing, carries the `update`, `deletion` and `non_fast_forward` rules and
   has an empty bypass list (in any mode, `exempt` included). The API returns
   the bypass list only to callers who can edit the ruleset, so with the
   default `GITHUB_TOKEN` that assertion is skipped with a warning. The
   workflow never asks for a stronger token.

Any finding opens an issue titled `tag-ledger: release tag or ruleset drift`,
or comments on it while it is open. Until the owner creates the
`tags-immutable` ruleset, every run fails on the ruleset check; that is the
intended signal.

**Responding to drift.** Never move a tag back: that is a second mutation.
Release the next version, then append a row to `acknowledged.tsv` on the
ledger branch (repo, tag, live object SHA, live peeled SHA, note;
tab-separated, `-` for both SHAs of a deleted tag). That exact state is then
reported as a warning; any further change fails again.

**Token:** `GITHUB_TOKEN` with `contents: write` (ledger branch of this repo
only) and `issues: write`. The scanned repos are only read. Protect the
`tag-ledger` branch against deletion and force pushes with a ruleset; plain
pushes from the workflow stay allowed.

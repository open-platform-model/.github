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
   run requires the branch head to descend from that commit and `ledger.tsv`
   and `acknowledged.tsv` to start with their content at it. A missing branch,
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
   same-named repo-level ruleset is a finding), active and excluding nothing:

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
Release the next version, then append a row to `acknowledged.tsv` on the
ledger branch (repo, tag, live object SHA, live peeled SHA, note;
tab-separated, `-` for both SHAs of a deleted tag). That exact state is then
reported as a warning; any further change fails again. An appended row keeps
the ledger's integrity check green.

**Token:** `GITHUB_TOKEN` with `contents: write`, `issues: write` and
`actions: read`. `contents: write` covers every branch of this repo, `main`
included (the branch the org ruleset reads `mention-guard.yml` from); the job
only pushes to `tag-ledger`. The scanned repos are only read.

**Before merging:** the owner creates the three rulesets above and a branch
ruleset on `refs/heads/tag-ledger` in this repo (deletion, non_fast_forward,
no bypass); then the first run is a manual one with `bootstrap: true`.

## `cut-release-branch` (reusable workflow)

[`.github/workflows/cut-release-branch.yml`](.github/workflows/cut-release-branch.yml)
cuts a maintenance branch `release/<tag_prefix><minor>` (for example
`release/v2.0`, `release/opm-v4.4`). It is the only way a release branch is
created; branches are cut lazily, at GA or when main starts work a released
minor must not get, and are never deleted.

| Input | Default | Meaning |
| --- | --- | --- |
| `tag_prefix` | `v` | Tag text before the version (`opm-v`, `k8s-v` in `catalog_opm`) |
| `minor` | required | `X.Y` |
| `package_path` | `.` | Package key in `release-please-config.json` (`opm`, `k8s`) |
| `release_workflow` | `.github/workflows/release.yml` | Caller workflow that runs release-please |
| `release_app_client_id` | empty | With secret `release_app_private_key`: mint the release App token |

Secrets: `release_app_private_key`, or `token`.

It finds the highest final `<tag_prefix><minor>.<patch>` tag (prereleases are
ignored) and refuses when none exists or the branch already exists. It creates
the branch at that tag's commit, then opens a PR into it that, on that branch
only:

- sets `versioning: always-bump-patch` and `prerelease: false` for the package,
  and removes any other package from the branch's release-please config;
- adds `release/**` to the release workflow's push trigger and sets
  `target-branch: ${{ github.ref_name }}` on its release-please step
  (release-please otherwise targets the default branch).

Files are edited as text to keep their layout and checked against a
`jq`/`yq` edit; on a mismatch the `jq`/`yq` output is used.

**Token.** Callers pass a token with `contents: write` and
`pull-requests: write` on their repo. The release App is preferred: pass its
client id and private key and the workflow mints the token itself, so CI runs
on the setup PR without manual approval (a token cannot be handed over from
another job of the caller). Caller example in the workflow header.

**Unproven until the sandbox runs it:** that the `release-branches` ruleset
lets the API create a `release/*` branch at an existing commit, and that
release-please on the branch anchors on the cut tag.

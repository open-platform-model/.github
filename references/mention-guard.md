# mention-guard: the required PR workflow

Covers what `mention-guard` scans, which rules fail a PR, the two bot exceptions, the limits of the
scan and how to change the rules. The workflow is in `.github/workflows/`. Tag drift, cite-lint and
the cascade are other topics.

## What it is

An organization ruleset ("Require workflows to pass before merging") runs the workflow on every pull
request in every repo of the org. The ruleset reads the workflow by path from `main` of this repo,
so an edit on `main` applies to every repo at once, with no pin.

It scans the PR title, the PR body and every branch commit message. All three are public on the PR.
The squash commit is built from the title and, in some repos, the commit messages, never the body.
release-please later copies it into changelogs and GitHub release notes, which render mentions again.

What the squash commit carries depends on the repo's merge settings. A repo that squashes with
`COMMIT_MESSAGES` puts the branch commit messages into the body. The releasing repos and this repo
squash with a `PR_TITLE` title and a `BLANK` body, so only the PR title reaches `main`. The workspace
`RELEASING.md` is the source of truth for the settings; read it, or run
`gh api repos/open-platform-model/<repo>`, before you rely on this paragraph.

## Rules that fail a PR

| Rule | Example that fails | Why |
| --- | --- | --- |
| Bare mention | `@v1`, `->@v1`, `"@v1"`, backticked `@v1` | GitHub pings the real user. Commit messages are not Markdown, so backticks do not protect. Glue the `@` to a word character (`core@v2`) or drop it. |
| Session identifier | `Claude-Session: ...`, a `claude.ai/code/session_...` link | Private, meaningless to readers, permanent. |
| AI generated-with footer | "Generated with Claude Code" | Never allowed. |
| Embellished AI co-author trailer | `Co-Authored-By:` with a model name | The only allowed AI attribution is exactly `Co-Authored-By: Claude <noreply@anthropic.com>`. Human co-author trailers are untouched. |

What passes: `opmodel.dev/core@v2`, `user@example.com`, `@@` diff hunk headers, human `Co-Authored-By`
trailers and the plain Claude trailer.

## Bot exceptions

Two carve-outs keep automated PRs mergeable. Neither weakens the rule for text that reaches
permanent history.

1. **Automation handles are allowed anywhere.** `@dependabot`, `@renovate`, `@renovate-bot`,
   `@github-actions` and `@dependabot-preview` never count. Every Dependabot PR body ends with its
   command list (`@dependabot rebase` and others), which failed the gate on every dependency bump.
   The rule protects strangers from a ping and a permanent backlink; these bots are already on the
   thread, and the handle must stay literal or the command stops working. The match is exact:
   `@dependabotx` still fails.
2. **A bot-authored PR body is advisory.** Findings there are notices and the job passes. The body is
   generated boilerplate that no maintainer can reword (Dependabot rewrites it on every rebase), and
   no repo in the org puts the PR body into the squash commit, so it never reaches permanent history.
   Without this, a release-please PR whose changelog quotes a contributor could merge only by admin
   bypass.

The PR title and the commit messages of a bot PR are still hard failures. The title becomes the
squash title and the release-notes entry. The commit messages become the squash body in repos that
squash with `COMMIT_MESSAGES`, and they stay public on the PR everywhere.

## Limits (by design)

- The gate cannot un-ping a mention typed into a PR title or body: GitHub fires it on submit. The
  gate keeps the text out of permanent history.
- It cannot see a squash message retyped in the merge box. The local `commit-msg` hook in `core`
  covers the laptop side.
- It does not rescan an edit in the other org repos. A run required by the org ruleset fires only on
  `opened`, `synchronize` and `reopened`: GitHub ignores the `edited` type that the workflow lists.
  In this repo the workflow also runs on its own, and `edited` does fire. "Re-run jobs" does not
  help, because it reads the title and body from the original event (commit messages are listed
  fresh). For a fresh scan of an edited title or body, push a commit, or close and reopen the PR.
- Org admins are on the ruleset's bypass list. For a false positive, reword the text. Use bypass only
  in an emergency.

## Pitfalls

- A path filter on this workflow: the ruleset requires it on every PR, and a filtered required check
  never reports on the other PRs.
- A new carve-out for a human account: the exceptions are for bots. Reword the text instead.

## Check before you finish

- [ ] The change keeps the workflow reporting on every PR, with no path filter.
- [ ] A rule you add has a row in the table above with an example that fails and a reason.
- [ ] A bot exception you add is exact-match and has a reason here.
- [ ] Your own commit text passes the rules above, or this PR cannot merge.

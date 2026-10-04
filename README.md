# open-platform-model/.github

Org-wide GitHub configuration. Currently hosts two things: the `mention-guard`
required PR workflow and the `tag-ledger` drift check.

## `mention-guard` (required PR workflow)

An organization ruleset ("Require workflows to pass before merging") runs
[`.github/workflows/mention-guard.yml`](.github/workflows/mention-guard.yml)
on every pull request in every repo of this org. It scans the **PR title, PR
body, and every branch commit message**. All three are public on the PR. The
squash commit is built from the title and, in some repos, the commit messages,
never the body; release-please later copies it into changelogs and GitHub
release notes, which re-render mentions.

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

## `cascade` (release-cascade resolver)

[`.github/scripts/cascade/cascade-resolve.sh`](.github/scripts/cascade/cascade-resolve.sh)
is the one implementation every repo's `task deps:cascade` (and the cascade
receive workflow) asks which upstream version a pin moves to, whether
a pin is held or frozen, and what the cascade PR is called. The design is the
workspace `RELEASING.md`, section "The cascade"; the interface is fixed by the
Phase 2 cascade contract, kept with the OpenSpec change `add-cascade-resolver`.

**How repos find it.** A repo task uses `CASCADE_RESOLVER` when it is set (an
absolute path), and otherwise
`<main checkout>/../.github/.github/scripts/cascade/cascade-resolve.sh`, so a
checkout of this repo beside the others is all a laptop needs. CI checks this
repo out at `main` beside the repo it works on.

**Subcommands.** `newest`, `published`, `pin-of`, `language-of`, `frozen`,
`is-frozen`, `hold`, `check-files`, `semver-cmp`, `semver-sort`,
`next-patch`, `classify`, `title` and `body`; the script header lists their
arguments. Query kinds: `cue` (GHCR), `go` (the Go proxy), `release` and
`opm-cli` (git tags plus anonymous release downloads) and `oci` (published
only). Versions are always `v`-prefixed SemVer.

| Exit | Meaning |
| --- | --- |
| 0 | success; for `newest`, a newer version was printed; for a predicate, yes |
| 3 | nothing to do, or no; for `title`, the diff is empty |
| 1 | error: network after retries, an unexpected status, a malformed `.cascade-*` file, a missing tool, the mention lint; never a guessed version |
| 2 | usage error |

It needs `bash`, `curl`, `jq`, `git` and mikefarah `yq` v4, and no
credentials: it never sends a token anywhere but GHCR's own anonymous pull
token to `ghcr.io`, and never calls `api.github.com`.

**The stub.** [`stub-resolve.sh`](.github/scripts/cascade/stub-resolve.sh) is
the canonical stub the repos copy byte for byte into
`.tasks/cascade/testdata/` (sha256
`970130f7d55c07f5b86d4f5b6f392330427ff923eb34f93553656bcd4b893d9c`). The test
suite checks the checksum and that the stub and the real resolver agree on
every case the stub supports. Changing it means a new contract version and a
new checksum in every copy.

**Tests.** Run them locally with
`bash .github/scripts/cascade/test/run.sh` (the resolver) and
`bash .github/scripts/cascade/wiring/test/run.sh` (the workflows' scripts,
below; it also needs go-task). `curl` and `git` are PATH shims
answering from `test/fixtures/` (captured from the real services), sleep and
the date are faked, and nothing touches the network.
[`cascade-resolver.yml`](.github/workflows/cascade-resolver.yml) runs
pinned `shellcheck`, `actionlint` and go-task releases and both suites on every PR and push to
`main`, with no path filter, as the job **`Resolver tests`**.
[`cascade-resolver-live.yml`](.github/workflows/cascade-resolver-live.yml)
checks read-only invariants against GHCR and GitHub weekly and on dispatch;
it is never required.

**Owner step after merge:** add `Resolver tests` to the ruleset on `main` of
this repo (workspace `RELEASING.md`, section "Rulesets on main").

### Cascade workflows

Two reusable workflows and two composite actions run the cascade in the five product repos
(workspace `RELEASING.md`, sections "The cascade" and "Gates"). Their scripts live in
[`.github/scripts/cascade/wiring/`](.github/scripts/cascade/wiring/), with every fixed map
(who notifies whom, which sources a receiver accepts, tag shapes) in `lib.sh`. The
`opm-cascade` App key is each repo's `cascade` Environment secret `CASCADE_APP_PRIVATE_KEY`,
with the variable `CASCADE_APP_CLIENT_ID`. A reusable-workflow job that declares
`environment: cascade` sees the caller's Environment variables but not its secrets (unless the
caller passes `secrets: inherit`, which no caller does), so every job that mints the App token is
the caller's own: it declares `environment: cascade` and passes the key to a composite action
as an input. No reusable workflow takes or reads a secret. Callers pin every cascade workflow
and action to a full commit SHA (owner decision 24 for the actions, extended to the workflows; see
"Pinning and bumps" below).

| File | Kind | Jobs or caller job | Does |
| --- | --- | --- | --- |
| [`cascade-notify`](.github/actions/cascade-notify/action.yml) | composite action | the caller's `Notify downstream` (`cascade` Environment) | after a release is published: checks the tag, waits up to 10 minutes for the Go proxy (library only), and sends `repository_dispatch` `upstream-released` with `{source, tags}` to each downstream repo |
| [`cascade-receive.yml`](.github/workflows/cascade-receive.yml) | reusable workflow | `Compute`, `Post gates` | runs the repo's `task -x deps:cascade` on the rolling `deps/cascade` branch with no secret in reach and plans the result; posts G2 and G3 on open release PRs; outputs `action`, `dry-run` and `compute-ok` |
| [`cascade-publish`](.github/actions/cascade-publish/action.yml) | composite action | the caller's `Publish` (`cascade` Environment) | verifies the plan, then pushes, opens, edits, recreates, closes or labels the cascade PR; never runs repo code |
| [`cascade-gates.yml`](.github/workflows/cascade-gates.yml) | reusable workflow | `Cascade gates` | per PR (`pull_request_target`, nothing checked out): `n/a` on both gate contexts for an ordinary PR; a gates-only receiver run for a release PR |

Every job's and every action's first step, `Guard`, derives the repo name from
`GITHUB_REPOSITORY` and refuses a repo outside `open-platform-model`.

**Pinning and bumps.** Owner decision 24 pins the two cascade actions by SHA in every repo,
replacing `@main` (decision 13) for them; the supervisor extended it to the two reusable
workflows, because the receive workflow runs the scripts of its own commit, so a workflow at
`main` with an action at a SHA would mix compute and publish script versions (the `plan.json`
between them). Each caller names `cascade-notify`, `cascade-publish`, `cascade-receive.yml` and
`cascade-gates.yml` by the full 40-character SHA of a commit on this repo's `main`, never by a
branch or tag (opm-operator's `sha_pinning_required` refuses an action named by branch). The
`ref:` of the `open-platform-model/.github` checkout in each repo's `cascade-task.yml` (the CI job
that tests the repo's `deps:cascade` task against the resolver) carries the same SHA, so CI tests
the resolver the receiver runs. A repo uses one SHA in all these references. The scripts come
from that same commit: the two actions run them from their own directory (`GITHUB_ACTION_PATH`),
and the receive workflow checks them out at its own `job.workflow_sha`, so a pinned reference
runs exactly that commit's code and there is no input naming another `.github` ref. A merge to
`main` here therefore changes nothing in a product repo until that repo moves its pin. A repo
whose `dependabot.yml` configures the `github-actions` ecosystem ignores
`open-platform-model/.github*`, so Dependabot never moves one reference on its own. To roll a
change out:

1. Merge the `.github` PR, then take the full SHA of the squash commit it made on `main`
   (`git rev-parse origin/main` right after fetching, or the PR's merge commit), and check it is
   on `main`: `gh api repos/open-platform-model/.github/compare/<SHA>...main --jq .status` must
   print `identical` or `ahead` (a branch commit that a squash merge left behind prints
   `diverged`).
2. Rerun the sandbox scenario that covers the change. The sandboxes are disarmed between
   rollouts (no App key in their `cascade` Environments, `cascade-sandbox-up` private), so:
   re-arm them (the supervisor restores the key in both Environments and makes
   `cascade-sandbox-up` public, under owner decision 22), move the sandbox callers
   (`cascade-sandbox-up` `release.yml`, `cascade-sandbox-down` `deps-cascade.yml` and
   `cascade-gates.yml`) to that SHA by a sandbox PR, run the scenario, then disarm them again.
3. In each of core, catalog_opm, library, opm-operator and cli, open one PR titled
   `ci(deps): pin the cascade to .github <first 7 of the SHA>` that replaces the SHA in every
   cascade reference (`grep -rn 'open-platform-model/.github' .github/workflows`: the `uses:`
   lines and the `ref:` under the `cascade-task.yml` checkout) and changes nothing else, unless
   the `.github` change altered an input, in which case the caller edit rides the same PR. All of
   a repo's cascade references carry the same SHA.
4. Merge each after its CI is green; order does not matter, because a repo runs only its own pin.
   To roll back, move the pins back the same way.

`<sha>` in the shapes below stands for that full SHA.

**Notify caller** (in each upstream's release workflow; `needs`, `if` and `tag` per repo):

```yaml
  notify-downstream:
    name: Notify downstream
    needs: [release-please, publish]
    if: needs.release-please.outputs.release_created == 'true' && vars.CASCADE_NOTIFY != 'off'
    runs-on: ubuntu-latest
    environment: cascade
    timeout-minutes: 20
    permissions:
      contents: read
    steps:
      - name: Notify downstream
        uses: open-platform-model/.github/.github/actions/cascade-notify@<sha> # .github main
        with:
          tag: ${{ needs.release-please.outputs.tag_name }}
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

**Receiver caller** (`deps-cascade.yml` in catalog_opm, library, opm-operator and cli):

```yaml
name: Deps cascade

on:
  repository_dispatch:
    types: [upstream-released]
  schedule:
    - cron: '17 5 * * *'
  workflow_dispatch:
    inputs:
      dry_run:
        description: Compute and show the diff in the job summary; push nothing
        type: boolean
        default: false
      gates_only:
        description: Evaluate and post the release-PR gates only (sent by Cascade gates)
        type: boolean
        default: false

permissions: {}

concurrency:
  group: ${{ github.ref != 'refs/heads/main' && format('deps-cascade-{0}', github.ref) || (inputs.gates_only && 'deps-cascade-gates' || 'deps-cascade') }}
  cancel-in-progress: false

jobs:
  cascade:
    name: Deps cascade
    permissions:
      contents: read
      pull-requests: read
      statuses: write
    uses: open-platform-model/.github/.github/workflows/cascade-receive.yml@<sha> # .github main
    with:
      dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
      gates-only: ${{ inputs.gates_only == true }}
      g2-mode: ${{ vars.CASCADE_G2_MODE || 'warn' }}
      g3-mode: ${{ vars.CASCADE_G3_MODE || 'warn' }}
      setup-go: false

  publish:
    name: Publish
    needs: cascade
    if: >-
      !cancelled()
      && needs.cascade.outputs.compute-ok == 'true'
      && needs.cascade.outputs.dry-run == 'false'
      && inputs.dry_run != true
      && vars.CASCADE_DRY_RUN == 'false'
      && github.ref == 'refs/heads/main'
      && contains(fromJSON('["push","recreate","close","conflict","too_long"]'), needs.cascade.outputs.action)
    runs-on: ubuntu-latest
    environment: cascade
    timeout-minutes: 15
    permissions:
      contents: read
      pull-requests: read
    steps:
      - name: Publish
        uses: open-platform-model/.github/.github/actions/cascade-publish@<sha> # .github main
        with:
          dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
          labels-managed: false
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

Real runs on `main` share the group `deps-cascade`; gates-only runs use `deps-cascade-gates`
and runs from any other ref (always dry runs) `deps-cascade-<ref>`, so neither replaces a
pending real run. The stop switch is the `cascade-publish` input `dry-run`, given the same
expression as the reusable job's `dry-run`: the action publishes only when it is exactly `false`,
does nothing on `true` and fails on any other value (an empty or missing input included), so a
mistyped `if:` cannot make a dry run publish. The `publish` job's `if:` repeats the switches only
so a dry run does not start a `cascade` Environment job; it reads them itself, not from the
reusable job that ran repo code. `cascade-publish` also refuses any ref but `main` and a plan
marked as a dry run. `setup-go: true` installs Go from `repo/go.mod` (opm-operator, cli);
`labels-managed: true` (cli, an input of `cascade-publish`) only checks that the five cascade labels exist instead of
creating them; `setup-cue` (default true) and `cue-version` (default `v0.17.1`) install CUE.

**Per-PR gates caller** (`cascade-gates.yml` in the same four repos):

```yaml
name: Cascade gates
on:
  pull_request_target:
    types: [opened, reopened, synchronize]
permissions: {}
concurrency:
  group: cascade-gates-${{ github.event.pull_request.number }}
  cancel-in-progress: true
jobs:
  gates:
    name: Cascade gates
    permissions:
      statuses: write
      actions: write
    uses: open-platform-model/.github/.github/workflows/cascade-gates.yml@<sha> # .github main
    with:
      g2-mode: ${{ vars.CASCADE_G2_MODE || 'warn' }}
      g3-mode: ${{ vars.CASCADE_G3_MODE || 'warn' }}
```

**Repo variables.**

| Variable | Repo | Meaning |
| --- | --- | --- |
| `CASCADE_DRY_RUN` | receivers | the receiver pushes only when it is exactly `false`; unset, deleted or anything else is a dry run (compute, summary and artifact; no push, PR, label or comment) |
| `CASCADE_NOTIFY` | upstreams | `off` skips notify, so that repo's releases stop dispatching |
| `CASCADE_G2_MODE`, `CASCADE_G3_MODE` | receivers | `warn` (default: a problem posts `success` with `WARN:`) or `enforce` (a problem posts `failure`) |

A run from any ref other than `main` is always a dry run, and `workflow_dispatch` with
`dry_run: true` dry-runs one run.

**Stop switches**, smallest first: the `deps-cascade:hold` label on the cascade PR (the bot
skips it); a `.cascade-hold` entry (one pin); `CASCADE_DRY_RUN` set to anything but `false`;
`CASCADE_NOTIFY=off` in an upstream; disabling `deps-cascade.yml`; suspending the
`opm-cascade` App (notify and publish then fail at minting, compute and gates keep running).

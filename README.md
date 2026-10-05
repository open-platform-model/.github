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
messages into its body. The releasing repos (core, catalog_opm, library,
opm-operator, cli, opm, docs-kit, modules, opm-portal) and this repo squash only,
with a `PR_TITLE` title and a `BLANK` body, so only the PR title reaches `main`
there (the
[workspace `RELEASING.md` "Owner settings"](https://github.com/open-platform-model/workspace/blob/main/RELEASING.md#owner-settings)).
The other org repos still squash with `COMMIT_MESSAGES`. That page is the
source of truth for the settings; check it, or `gh api
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

It also does not rescan an edit. A run required by the org ruleset fires only
on `opened`, `synchronize` and `reopened`: GitHub ignores the `edited` type
that `mention-guard.yml` lists, so in the other org repos, editing a PR title
or body after a run starts no new ruleset scan (here in `.github` the
workflow also runs on its own, where `edited` does fire). "Re-run jobs" does
not help either: it reads the title and body from the original event (commit
messages are listed fresh). For a fresh scan of an edited title or body, push
a commit, or close and reopen the PR.

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

Scope: six of the nine releasing repos, `core`, `library`, `catalog_opm`,
`cli`, `opm-operator` and `opm` (`REPOS` in the workflow). `docs-kit`, `modules`
and `opm-portal` are not scanned yet, although the org tag rulesets cover them
(owner decision 34).

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
   assertion below applies to it. All three now exist and apply to every
   scanned repo, but the script still treats the two planned ones as pending,
   so a repo dropping out of either is only a warning until they are made
   required.

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
repo out at the repo's cascade pin (see "Pinning and bumps" below) beside the
repo it works on.

**Subcommands.** `newest`, `published`, `pin-of`, `language-of`, `frozen`,
`is-frozen`, `hold`, `check-files`, `tag-on-main`, `semver-cmp`, `semver-sort`,
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

`newest` proposes only a version whose release tag is on its repo's `main`,
for every pin whose versions are tags of an org repo (`go
github.com/open-platform-model/<repo>`, `release`, `opm-cli`, and the `cue`
modules `opmodel.dev/core`, `opmodel.dev/catalogs/opm`, whose tags are `opm-v*`, and
`opmodel.dev/modules/opm_operator`, whose tags are opm-operator's `opm_operator-v*`). A tag made on a commit `main` never had (the release App can create
one) is still served by the Go proxy and listed by git, so `newest` clones the
repo once per run, bare and without trees, fetches each probed tag and skips,
with a warning, one whose commit is not an ancestor of `main`. `tag-on-main
<pin-key> <v>` answers the same for one version (exit 0 on main or no tag to
check, 3 not), and `receive-publish.sh verify` runs it on every pin the new
tip moves, since `compute` reaches `newest` only through repo code. Release branches
(`release/*`) are not accepted yet; the release-branch automation extends this
check when it lands.

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
checks read-only invariants against GHCR and GitHub weekly and on dispatch, and
[`cascade-mirror-drift.yml`](.github/workflows/cascade-mirror-drift.yml) checks the publish
mirrors against the receivers daily (below); neither is ever required.

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
| [`cascade-receive.yml`](.github/workflows/cascade-receive.yml) | reusable workflow | `Compute`, `Post gates` | runs the repo's `task -x deps:cascade` on the rolling `deps/cascade` branch with no secret in reach and plans the result; posts G2 (from `compute`) and G3 (evaluated in `Post gates`) on open release PRs; outputs `action`, `dry-run` and `compute-ok` (hints only: `compute` ran repo code) |
| [`cascade-publish`](.github/actions/cascade-publish/action.yml) | composite action | the caller's `Publish` (`cascade` Environment) | refuses a gates-only run, verifies the plan, then pushes, opens, edits, recreates, closes or labels the cascade PR; never runs repo code |
| [`cascade-gates.yml`](.github/workflows/cascade-gates.yml) | reusable workflow | `Cascade gates` | per PR (`pull_request_target`, nothing checked out): `n/a` on both gate contexts for an ordinary PR; a gates-only receiver run for a release PR |

Every job's and every action's first step, `Guard`, derives the repo name from
`GITHUB_REPOSITORY` and refuses a repo outside `open-platform-model`.

**The opm-operator rename.** The repo `opm-operator` is being renamed `opm-controller`. Since
the name comes from `GITHUB_REPOSITORY`, it flips the moment GitHub renames the repo, whatever
`.github` commit the caller pins, and every map in `lib.sh` fails closed on a name it does not
know. Until the rename is done, every map keyed by a receiver or a source therefore accepts both
names with the same values: `notify_targets`, `receiver_sources`, `g3_upstreams`, `publish_paths`,
`publish_denied`, `receiver_classes`, `receiver_pins`, `mirror_sources`, `changelog_repos`,
`expect_pair`, `changelog_source` (and the resolver's `tag_source`, both module trains
`opm_operator-v*` and `opm_controller-v*`), the resolver's accepted body sources, and cli's pin
file (`internal/operator/pin.go` or `internal/controller/pin.go`). Two lists keep the old name
only, because they name a repo GitHub must find: the target lists of `notify_targets` (they set
the App token's `repositories:`, and a name that does not exist fails the mint for every target)
and cli's `g3_upstreams` (read by API). A later `.github` change flips those, drops the old name
and records the renamed repos' new mirror hashes once the rename has merged.

**Repo code in `compute`.** `compute` runs the receiver's tasks and `pins.sh` (`main`'s, on
`main` merged with `deps/cascade`), the new dependency code those tasks build or run, and, for
G2, the task of every open `release-please--*` head; any write collaborator can push to either
branch. Its two `Read` steps make every read that needs
`GITHUB_TOKEN` (the release-PR list, the release heads' commits, the cascade PR, the branch
tips and the upstream releases for the breaking check) before the first step that runs repo
code, and no step from `Gates` on is given a token. Repo code also runs without `GITHUB_ENV`,
`GITHUB_PATH`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`, `GITHUB_STATE` and every `ACTIONS_*`
variable, so a task that honours them cannot set the step's outputs, environment or `PATH`.
None of this is a boundary inside the job. Hostile code can find the runner's command files on
disk, leave a process running into later steps, and rewrite the checked-out scripts. It can
plant a git hook or `core.fsmonitor` in `repo/.git` (the G2 worktrees share it), which the two
`actions/checkout` post steps then run with the job's read-only token in their environment. With
the runner's `sudo` it can read that token and the artifact runtime token, and the runtime token
also writes the Actions cache of `main`'s scope. So everything `compute` writes from `Gates` on
(its `action` and `compute-ok` outputs, `gates.json`, the plan, the bundle and any cache entry)
is untrusted:

- `Post gates` posts only on the open release heads it lists itself, takes only G2 from
  `gates.json`, and evaluates G3 itself from the API. A release head can still choose its own
  G2 result, which is why G2 stays `warn`; it cannot choose G3.
- `publish` takes its switches from the caller's inputs and re-derives the plan: what the push
  may change, who made its commits, and the PR's title, body and labels (below).
- No job that publishes restores an Actions cache: `compute` installs Go with `cache: false`,
  and the wiring check (below) refuses a cache in every workflow a repo lists as publishing,
  because a cache entry written from `compute` (or any job on `main` that runs repo code) would
  otherwise reach a released binary or image.
- On a branch a human merged into (merge mode), `compute` runs `main`'s task: when the branch
  changed `.tasks/` or a root `Taskfile*`, it puts `main`'s versions in the work tree, runs the
  task with `CASCADE_ALLOW_DIRTY=1` and leaves those paths out of its commit.
- `compute` installs Task v3.53.1 and CUE with `wiring/install-tools.sh`: fixed release URLs,
  HTTPS only, each archive checked against a sha256 held here. A `cue-version` without a row
  there fails before any repo code runs; a new version is a change here first.

**What `publish` accepts.** Before it mints the App token, `publish` (`receive-publish.sh
verify`) bounds the push and writes the PR text itself:

- *The increment.* The bot's own commits are the new tip's commits that neither `main` nor, for
  a fast-forward, the old remote tip has: at most two (a merge of `main` and one task commit),
  each authored and committed by the bot. A plain commit may change only paths on the
  receiver's allow-list (`publish_paths` in `wiring/lib.sh`), in place: status `M`, no mode
  change, no symlink and no gitlink. A merge commit must be git's own merge of its parents
  (`git merge-tree --write-tree`), its second parent on `main`, except derived files carrying
  `main`'s content. A deny-list always wins: `.github/**`, `.tasks/**`, any `Taskfile*`,
  `hack/**` (but cli's `hack/kind-platform.yaml` and `hack/platform/cue.mod/module.cue`), any
  `*.sh`, any `CODEOWNERS`, the release-please files, `.cascade-frozen` and `.cascade-hold`,
  and opm-operator's `modules/**` (its operator module moves only through `module-deps.yml`).
- *Human commits.* A push that does not contain the old tip is refused when the old branch holds
  a commit the bot did not make, a `recreate` over such a branch is refused, and `close` keeps
  such a branch.
- *The text.* `publish` checks the new tip out into a scratch worktree and runs the resolver's
  own `title` and `body` there with a mirror of the receiver's `pins.sh` and `classes`
  (`wiring/pins.sh` and `receiver_pins`/`receiver_classes` in `lib.sh`, which read only `git
  show`), the trigger from the event, the live PR's Notes, and `compute`'s warnings after a
  line filter (no HTML, link, URL, issue reference or mention; at most 100 lines of 500
  bytes). The labels are `deps-cascade`, the pins' labels (`need-human-review` for library's
  core) and `deps-cascade:breaking` from the mirrored pins and the releases `publish` reads
  itself. `compute`'s `body.md` and titles are hints; a planned title that differs is a notice.
  The bot never removes `need-human-review` or `deps-cascade:breaking`.

| Receiver | Paths its bot commits may change (besides any `cue.mod/module.cue`) |
| --- | --- |
| catalog_opm | `.opm-cli-version` |
| library | `opm/schema/loader.go`, `docs/getting-started.md`, `AGENTS.md` |
| opm-operator (also as opm-controller) | `go.mod`, `go.sum`, `.opm-cli-version`, the sample Platform and ModuleInstance, `test/fixtures/catalog.go`, the fixture modules' and provider's `identity/identity.cue`, the fixture modules' `moduleinstance.yaml` |
| cli | `go.mod`, `go.sum`, `internal/operator/pin.go` or `internal/controller/pin.go`, `hack/kind-platform.yaml`, the templates' and podinfo's `identity/identity.cue` |

**Keeping the mirrors in step.** The allow-lists, the pin parsers and the classes copy each
receiver's `.tasks/cascade/` on its `main` (read 2026-10-05: catalog_opm `0560990`, library
`ca7c56b`, opm-operator `53ccaab`, cli `bd4d1a7c`). `mirror_sources` in `wiring/lib.sh` records
the sha256 of every receiver file the mirrors copy or were read from: `pins.sh`, the `lib.sh` it
sources (library, opm-operator), `classes`, and the `cascade.sh` each allow-list was read from.
For a push or recreate, `publish` first reads those files on the receiver's `origin/main` and
refuses, naming the receiver, the file and both hashes, when one differs, so a stale pin mirror
or a stale allow-list stops the run before it renders a body or judges a path. Code that
`cascade.sh` only runs (cli's `hack/operator-pin`, a Taskfile task) is not hashed: when a change
there makes the task write a new path, publish still refuses that path as one the task never
writes, and the allow-list needs the same update. [`cascade-mirror-drift.yml`](.github/workflows/cascade-mirror-drift.yml)
runs the same comparison daily (`wiring/mirror-drift.sh`, read-only, with the run's own token)
and fails red on drift. A receiver change to its `cascade.sh` (or to what its task writes), its
`pins.sh`, the `lib.sh` it sources or its `classes` therefore needs the matching change here (mirror, allow-list
and hash) merged first, and the receiver's change should carry its pin bump to that `.github`
commit, so both land together; until both have, publish refuses that receiver's plans, which is
the intended fail-closed state. To check a mirror, run the receiver's `pins.sh` and
`CASCADE_PINS_REPO=<repo> .github/scripts/cascade/wiring/pins.sh` on the same commits of its
checkout and compare; to check an allow-list, run the receiver's own cascade suite with its
sandboxes kept and pass every changed path through `publish_path_ok`.

**What stays open (residual risk).**

- G2 still runs every open release head's own task inside `compute`, which is a run on
  `main`'s ref: that code can write `main`'s Actions cache scope. The sink is closed, not the
  write: no publish workflow restores a cache (the wiring check's `publish-workflows` rule).
- Merge mode runs `main`'s `.tasks/` and root `Taskfile*`, but the rest of the branch tip's
  code still runs in that `main`-ref run: `hack/` programs and scripts the task calls and the
  `go.mod` toolchain line. Anyone who can push to `deps/cascade` gets this, the same class as
  G2, and the cache sink is closed the same way.
- A receiver's own publisher outside `cascade-receive.yml` and `cascade-publish` (opm-operator's
  `module-deps.yml`, `task deps:cascade:module`, since `4b981c6`) gets only its own repo's
  bounds. Since opm-operator PR 225 its `publish` job runs in the `release` Environment and
  takes only plain files under `modules/opm_operator/` from `compute`'s artifact, but the PR
  title and body still come from `compute`, and its tools are not pinned here. Routing it through
  these workflows needs its own mirror entries.
- `main` requires a pull request but no approval while OPM is in beta (owner decision 36), so a
  write collaborator, or the `opm-cascade` bot, can merge a PR whose required checks pass
  without anyone reviewing it, a change to `.tasks/cascade/` included.
- One `opm-cascade` key sits in all five `cascade` Environments (owner decision 31): a leak
  reaches every receiver at once. The workspace `RELEASING.md`, "Rotating the cascade App key",
  is the response.
- `compute` still chooses the action (push, close, conflict, too long). A hostile `compute` can
  stall or relabel its own receiver's cascade PR as conflicted, but cannot publish anything
  outside the bounds above.
- `setup-go` installs Go from the receiver's `go.mod` version without a checksum held here.
- The mirrors drift unless kept in step (above); a stale mirror now stops publish instead of
  misleading it, which halts that receiver's cascade until `.github` and its pin move.

**Pinning and bumps.** Owner decision 24 pins the two cascade actions by SHA in every repo,
replacing `@main` (decision 13) for them; the supervisor extended it to the two reusable
workflows, because the receive workflow runs the scripts of its own commit, so a workflow at
`main` with an action at a SHA would mix compute and publish script versions (the `plan.json`
between them). Each caller names `cascade-notify`, `cascade-publish`, `cascade-receive.yml` and
`cascade-gates.yml` by the full 40-character SHA of a commit on this repo's `main`, never by a
branch or tag (every product repo has `sha_pinning_required` on, which refuses an action named
by branch). The
`ref:` of the `open-platform-model/.github` checkout in each receiver's `cascade-task.yml` (the CI
job that tests the repo's `deps:cascade` task against the resolver; core has none) carries the
same SHA, so CI tests
the resolver the receiver runs. Any other checkout of `.github` a repo needs (opm-operator's
`module-deps.yml`) is declared in its wiring config and carries the same SHA too. A repo uses one
SHA in all these references. The scripts come
from that same commit: the two actions run them from their own directory (`GITHUB_ACTION_PATH`),
and the receive workflow checks them out at its own `job.workflow_sha`, so a pinned reference
runs exactly that commit's code and there is no input naming another `.github` ref. A merge to
`main` here therefore changes nothing in a product repo's cascade (its callers, its receiver and
its `cascade-task.yml`) until that repo moves its pin. Two things do not wait for a pin:
`mention-guard` applies at once through the org ruleset, and a laptop `task deps:cascade` uses the
sibling `.github` checkout as it stands. A repo whose `dependabot.yml` configures the
`github-actions` ecosystem ignores `open-platform-model/.github*`, so Dependabot never moves one
reference on its own. To roll a change out:

1. Merge the `.github` PR once its `Resolver tests` job is green (both offline suites, the static
   checks, `shellcheck` and `actionlint`; no sandbox proves a change, owner decision 26, so a
   change of behavior comes with suite cases). Then take the full SHA of the squash commit it
   made on `main` (`git rev-parse origin/main` right after fetching, or the PR's merge commit),
   and check it is on `main`: `gh api repos/open-platform-model/.github/compare/<SHA>...main
   --jq .status` must print `identical` or `ahead`. This repo is squash-only, so a branch commit
   left behind by the merge prints `diverged`, and it deletes the PR branch on merge, so pin the
   squash SHA, never a branch commit.
2. Dry run: the dry-run checks in one receiver (catalog_opm, library, opm-operator or cli; core
   has no receiver). Set that repo's variable `CASCADE_DRY_RUN` to `true` if it is not
   already, noting the old value; open and merge its pin PR as in steps 3 and 4; run
   `gh workflow run deps-cascade.yml -R open-platform-model/<receiver>` and check the run succeeds,
   its `Compute` log shows `scripts from open-platform-model/.github <SHA>`, `Publish` is
   skipped, and the summary's mode and action match `task -x deps:cascade` run locally on that
   repo's `main`; check that that receiver's next PR shows `cascade/freshness` and
   `cascade/settled`, and that its `cascade-task.yml` (by `workflow_dispatch`) checks the
   resolver out at `<SHA>` and passes. Then set `CASCADE_DRY_RUN` back. A dry run skips
   `Publish` and notify runs only on a release, so a change to `cascade-publish` or
   `cascade-notify` first meets real GitHub on the first live publish run or the first release
   of an upstream that pins it.

   **Which repos move when** (owner decision 37). It depends on which action the diff touches.
   A diff touches an action when it changes any file that action runs: its `action.yml` and
   every script it calls or sources, directly or through another script. Under
   `.github/scripts/cascade/`, `cascade-notify` runs `wiring/notify.sh` and `wiring/lib.sh`;
   `cascade-publish` runs `wiring/receive-publish.sh`, `wiring/lib.sh`, `wiring/pins.sh`,
   `cascade-resolve.sh` and everything in `lib/`. So a change to `wiring/lib.sh` touches both,
   and a change to the resolver or its `lib/` touches `cascade-publish`. When unsure, count the
   file as touched.

   - **Neither `cascade-publish` nor `cascade-notify`:** no canary. All five repos may move
     together (steps 3 and 4), live or dry; the only requirement is the dry-run checks above in
     one receiver after its pin PR has merged.
   - **`cascade-publish` but not `cascade-notify`, every receiver dry-run** (none has
     `CASCADE_DRY_RUN` set to `false`): all five repos may move together too, with the dry-run
     checks in one receiver after its merge, because no receiver publishes. The canary is the
     Phase 4 canary, the first receiver whose `CASCADE_DRY_RUN` is set to `false` (Phase 4,
     going live, is planned in the workspace's `RELEASING.md`, "Phases"): it has the first live
     publish on the new pin, and every other receiver stays dry until that run has succeeded.
   - **`cascade-publish` but not `cascade-notify`, any receiver live:** one live receiver is the
     canary. It moves first and takes the dry-run checks above; every other receiver, live or
     dry, stays on the old pin until the canary's first live publish run on the new pin has
     succeeded.
   - **`cascade-notify` but not `cascade-publish`:** a dry run does not help, because notify has
     no dry run: it runs live on every release of an upstream, whatever `CASCADE_DRY_RUN` says.
     So one upstream (core or a receiver) moves first as the canary; every other repo stays on
     the old pin until the canary's first live notify run on the new pin, on its next release,
     has succeeded. A receiver canary takes the dry-run checks above; with core as the canary,
     the first receiver to move after it takes them. This holds whether every receiver is dry
     or not.
   - **Both actions:** the `cascade-notify` rule above holds, plus the publish rule for the
     receivers' state. While every receiver is dry-run, every receiver but the Phase 4 canary
     also stays dry until the canary's first live publish on the new pin has succeeded. Once any
     receiver is live, the canary is a live receiver, and no other repo moves until both its
     first live publish run and its first live notify run on the new pin have succeeded.

   Watch every first live run on the new pin and roll back if one fails.
3. In each of the other repos among core, catalog_opm, library, opm-operator and cli, open one
   PR titled `ci(deps): pin the cascade to .github <first 7 of the SHA>` that replaces the SHA in
   every cascade reference and the copy of the wiring check (below) and changes nothing else,
   unless the `.github` change altered an input or a caller shape, in which case the caller edit
   and the `.tasks/cascade/wiring-check.yaml` edit ride the same PR. Find them with
   `grep -rn -A1 'open-platform-model/.github' .github/workflows`: the `uses:` lines and the
   `repository:` line of the `cascade-task.yml` checkout, whose `ref:` the `-A1` prints on the
   next line (comment lines also match and need no change); opm-operator's `module-deps.yml`
   has a second such checkout, declared in its config's `extra-references`. All of a repo's
   cascade references carry the same SHA. Before the PR is opened, `bash
   .tasks/cascade/wiring-check.sh --pin-on-main` passes (the shapes, then the `compare` check of
   step 1 for that SHA, then the comparison of the new copy with the file at that SHA).
4. Merge each after its CI is green and its "Verify the cascade wiring" step printed
   `cascade wiring: ok, .github <SHA> (.github main)`: that step runs the same check with
   `--pin-on-main`, so it has also confirmed the SHA is on `.github`'s `main` and the copy is
   the file at that SHA. Otherwise the order does not matter, because a repo runs only its own
   pin; the limits are step 2's rules for which repos wait after a change that touches
   `cascade-publish` or `cascade-notify`.
   To roll back, move the pins back the same way (no canary needed for a SHA the repo
   already ran).

**The wiring check.** One script,
[`.github/scripts/cascade/wiring-check.sh`](.github/scripts/cascade/wiring-check.sh), checks
every product repo's caller shapes against the shapes below; each repo runs a byte-identical copy
at `.tasks/cascade/wiring-check.sh` with its own values in `.tasks/cascade/wiring-check.yaml`:
offline through `task cascade:wiring:check`, and online in a step of its required CI job:

```yaml
      - name: Verify the cascade wiring
        env:
          GH_TOKEN: ${{ github.token }}
        run: bash .tasks/cascade/wiring-check.sh --pin-on-main
```

Only SHA-pinned actions (checkout, setup) may come before it; every `run:` step goes after it.
catalog_opm's `main` writes `OPM_CLI_VERSION` to `GITHUB_ENV` in a step before it, so its next
pin bump moves the wiring step above that step.

It prints every mismatch and exits 1, or prints `cascade wiring: ok, .github <SHA> (<pin
comment>)`; offline (without `--pin-on-main`) a second line says `the copy was not compared`; a
bad config exits 2. It checks:

- no workflow file uses a YAML anchor or alias (GitHub resolves them, the check reads text);
- the key-holding jobs (`notify-downstream`, `publish`): exact job and step keys, names,
  timeouts (20 and 15 minutes), `environment: cascade`, `runs-on: ubuntu-latest`, permissions,
  one SHA-pinned cascade action with exact inputs, the client id and the key; notify's `needs`,
  `if:` and `tag` from the config; publish's `needs`, `if:` (with the gates-only clause),
  `dry-run`, `gates-only` and `labels-managed` (a YAML boolean, from the config);
- `release.yml`'s top-level `env`: a map whose keys are all on the config's `env-allow`;
- for a receiver: the triggers, permissions, concurrency and jobs of `deps-cascade.yml` and
  `cascade-gates.yml`, and that the `cascade` job passes only inputs `cascade-receive.yml` takes;
- in every workflow: the App key read only by the key-holding jobs, where a reader is any
  expression that names it in any case or uses the secrets context other than as
  `secrets.<name>` (`secrets[…]` with any index, `format()` included, `secrets.*`, or
  `toJSON(secrets)` and any other function given the whole context); the cascade Environment
  (any case, a map, or an expression) only on them; and no call into `.github` (in any case)
  passing `secrets:`;
- in every workflow: every job that reads the release App key `RELEASE_APP_PRIVATE_KEY` (an
  expression naming it in any case, or `secrets: inherit`) declares exactly `environment:
  release` (the main-only Environment that holds the key, owner decision 29), and no other job
  declares `release`; a read outside a job is refused;
- in every workflow the config's `publish-workflows` lists: no cache action (any action whose
  name says `cache`), `actions/setup-go` with `cache: false`, `actions/setup-node` with
  `package-manager-cache: false` and no `cache`, no other `cache*` input but `no-cache`, and no
  `type=gha` anywhere (buildx `cache-from`/`cache-to`). A reusable workflow called from there is
  not checked (docs-kit's `publish.yml` sets `cache: false`);
- one full SHA and the pin comment on every `.github` reference, matched in any case (the four
  `uses:`, the `cascade-task.yml` resolver `ref:`, and each resolver checkout the config's
  `extra-references` declares), and no other reference;
- every checkout of `.github` (a step whose `with.repository` is any owner's `.github` in any
  case) is `actions/checkout@<full SHA>` with exactly `repository`, `ref`, `path` and
  `persist-credentials: false`, so no token or SSH key reaches it; no step's `repository` input
  is an expression (`${{ github.repository_owner }}/.github` would name `.github` unseen), and
  no `run:` step names `open-platform-model/.github` or an expression or owner variable followed
  by `/.github` (a `git clone` past the pinned checkouts);
- that the config's CI job runs it as exactly the step above on every pull request: no path
  filter, no `if:` or `continue-on-error`, no `shell` or `working-directory` of its own or from
  `defaults`;
- that nothing reaches that step from around it: the CI workflow's and job's `env` are plain
  maps whose names are only `CUE_*`, `OPM_*`, `REGISTRY` or `IMAGE_NAME` (so no `BASH_ENV`,
  `CASCADE_GH` or `PATH`), the job has no `container` or `services`, and every step before the
  wiring step is an action from another repo at a full SHA with only `id`, `name`, `uses` and
  `with` (no `run:` step that could write `GITHUB_ENV` or `GITHUB_PATH` or leave a process
  behind). With `--pin-on-main` the check also exits 1 when `BASH_ENV` or `ENV` is set, a
  tripwire only, since bash reads `BASH_ENV` before the script runs;
- with `--pin-on-main`, after every shape matched:
  `gh api repos/open-platform-model/.github/compare/<SHA>...main --jq .status` prints
  `identical` or `ahead`, so a commit that exists only in a fork of `.github` (which GitHub also
  resolves under this repo's name) is refused; then
  `gh api -H 'Accept: application/vnd.github.raw'
  "repos/open-platform-model/.github/contents/.github/scripts/cascade/wiring-check.sh?ref=<SHA>"`
  must return exactly the bytes of the script that is running (`.tasks/cascade/wiring-check.sh`
  in CI), so a copy that drifted or was not replaced at a pin bump fails with `differs from`.

The config is data, read with `yq`, never run. `env-allow` may name only `CUE_*`, `OPM_*`,
`REGISTRY` and `IMAGE_NAME`: a workflow-level env reaches the notify action's steps, which hold
the App token, and too many other names make bash, git, gh, node, curl or the loader run code or
send traffic elsewhere (`BASH_ENV`, `GIT_*`, `GH_*`, `NODE_*`, `LD_*`, `XDG_*`, `SSL_*`,
`*_PROXY` and more) for a deny-list to be safe. `publish-workflows` must list `release.yml`.
`extra-references` (optional) lists more pinned `.github` references, one item per reference,
each a map of exactly `file` (a workflow file name) and `kind`; the only kind is `resolver`, a
checkout of `.github` held to the rules above. Only a receiver may set it, a file appears at
most once, and never one of `release.yml`, `deps-cascade.yml`, `cascade-gates.yml` or
`cascade-task.yml`, which hold the fixed references. A new kind (another action or
reusable-workflow call) is a change here, never a config entry. Each repo's values:

| Repo | `receiver` | `env-allow` | `publish-workflows` | `ci` (workflow, job) | `notify.needs` | `labels-managed` |
| --- | --- | --- | --- | --- | --- | --- |
| core | `false` | `CUE_VERSION`, `CUE_REGISTRY` | `release.yml`, `branch-publish.yml`, `docs.yml` | `ci.yml`, `ci` | `release-please`, `publish-cue` | (none) |
| catalog_opm | `true` | `OPM_REGISTRY`, `CUE_REGISTRY` | `release.yml`, `branch-publish.yml`, `docs.yml` | `ci.yml`, `ci` | `release-please`, `publish-cue` | `false` |
| library | `true` | (none) | `release.yml`, `docs.yml` | `test.yml`, `test` | `release-please` | `false` |
| opm-operator | `true` | `REGISTRY`, `IMAGE_NAME`, `CUE_VERSION` | `release.yml`, `publish-fixtures.yml`, `docs.yml`, `image-pr.yml`, `test-e2e.yml`, `module-image.yml`, `module-deps.yml` | `lint.yml`, `lint` | `release-please`, `publish-release` | `false` |
| cli | `true` | (none) | `release.yml`, `publish-fixtures.yml`, `docs.yml` | `pr.yml`, `lint` | `release-please`, `goreleaser` | `true` |

`pin-comment` is `.github main` everywhere; `notify.if` and `notify.tag` are each repo's own
`release.yml` values. Only opm-operator sets `extra-references`, for the resolver checkout in
`module-deps.yml` (the operator module's own dependency bot, job `compute`):
`extra-references: [{file: module-deps.yml, kind: resolver}]`. catalog_opm's file, for example:

```yaml
pin-comment: .github main
receiver: true
env-allow: [OPM_REGISTRY, CUE_REGISTRY]
publish-workflows: [release.yml, branch-publish.yml, docs.yml]
ci:
  workflow: ci.yml
  job: ci
notify:
  needs: [release-please, publish-cue]
  if: ${{ !cancelled() && needs.publish-cue.outputs.published == 'true' && vars.CASCADE_NOTIFY != 'off' }}
  tag: ${{ needs.release-please.outputs.opm_tag_name }}
publish:
  labels-managed: false
```

**Keeping the copy in sync.** A repo's copy is the file at the `.github` SHA its cascade
references pin, and it moves only with the pin: the pin-bump PR (step 3 above) replaces it with

```sh
sha=<the new .github SHA>
gh api "repos/open-platform-model/.github/contents/.github/scripts/cascade/wiring-check.sh?ref=$sha" \
  -H 'Accept: application/vnd.github.raw' >.tasks/cascade/wiring-check.sh
```

so the PR's diff of the copy is exactly `.github`'s change between the two SHAs, and a reviewer
confirms it with the same `gh api` call piped to `cmp - .tasks/cascade/wiring-check.sh`. A change
to the check is made here, never in a copy. The required CI step makes the same comparison
(`--pin-on-main`), so a copy that differs from the file at the pin fails CI on every PR. The
comparison runs from the copy under test, though, so it catches drift and a copy left behind at a
bump but does not replace review. A PR can pass an edited copy by also deleting the comparison,
or by changing what runs around the CI step. The shape rule above refuses the plain routes (env,
a container or service, a `run:` step before the wiring step), but an earlier SHA-pinned action
can still set the step's environment through `GITHUB_ENV` or `GITHUB_PATH`, so a reviewer reads
any change to the CI workflow, and to the copy, as a change to the check. The copy and the
config live in the repo's own tree, so a PR can change them along with the workflows: the check
guards against mistakes, and only review guards against a deliberate edit. CODEOWNERS on
`/.tasks/` requests that review, but while OPM is in beta the `main` ruleset requires a pull
request and no approval (owner decision 36), so nothing enforces it.
Offline (`task cascade:wiring:check`) the copy is not compared, and the check
says so.

**When the wiring step's API call fails.** The required step makes two GitHub API requests (the
`compare`, then the contents read of the pinned file), so a GitHub outage, a secondary rate limit
or the job token's hourly limit fails the required job on every PR with `cannot compare .github
<SHA> with main` or `cannot fetch .github/scripts/cascade/wiring-check.sh at .github <SHA>`.
Only those two messages can be outages, and `cannot compare` is also what a SHA GitHub does not
know prints (the compare returns 404), which is a finding:

1. Confirm the SHA exists: `gh api repos/open-platform-model/.github/commits/<SHA> --jq .sha`
   must print the SHA. A 404 or 422 is a pin to fix, never an outage; skip the steps below. If
   this call fails for the outage itself, re-run it until it answers.
2. Re-run the failed job (`gh run rerun <run id> --failed -R open-platform-model/<repo>`).
3. Check <https://www.githubstatus.com> and `gh api rate_limit`; wait for the reset or the
   recovery and re-run again.
4. If it lasts, step 1 printed the SHA and a merge cannot wait, an admin may merge with admin
   bypass (`gh pr merge --admin`) only a PR whose changed files (`gh pr diff <n> --name-only`) include nothing under
   `.github/**` or `.tasks/**`, after every other required check passed and `task
   cascade:wiring:check` passed on the PR head. A PR touching those paths waits for the API.
5. Never remove `--pin-on-main` from the step (the check refuses that shape anyway), and never
   edit the copy to skip a request.

`is not on .github main` and `differs from` are findings, not outages: fix the pin or the copy,
and never bypass them.

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
      && inputs.gates_only != true
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
          gates-only: ${{ inputs.gates_only == true }}
          labels-managed: false
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

Real runs on `main` share the group `deps-cascade`; gates-only runs use `deps-cascade-gates`
and runs from any other ref (always dry runs) `deps-cascade-<ref>`, so neither replaces a
pending real run. The stop switch is the `cascade-publish` input `dry-run`, given the same
expression as the reusable job's `dry-run`: the action publishes only when it is exactly `false`,
does nothing on `true` and fails on any other value (an empty or missing input included), so a
mistyped `if:` cannot make a dry run publish. GitHub compares strings without regard to case, so
the receiver is live when `CASCADE_DRY_RUN` is `false` in any letter case (`False`, `FALSE`);
any other value keeps it dry. A gates-only run never publishes: the `publish` job's `if:` reads
the caller's own `gates_only` input, and the required `cascade-publish` input `gates-only`
(the same input as `${{ inputs.gates_only == true }}`) makes the action fail before the mint
unless it is exactly `false`. A gates-only run runs the code of every open release head inside
`compute`, so `compute`'s outputs are hints there and everywhere: the reusable workflow also
reports `action: gates-only` and `compute-ok: false` for such a run, from its input, but nothing
relies on that. The `publish` job's `if:` repeats the switches only
so a dry run does not start a `cascade` Environment job; it reads them itself, not from the
reusable job that ran repo code. `cascade-publish` also refuses any ref but `main` and a plan
marked as a dry run. `setup-go: true` installs Go from `repo/go.mod` (opm-operator, cli);
`labels-managed: true` (cli, an input of `cascade-publish`) only checks that the five cascade labels exist instead of
creating them; `setup-cue` (default true) and `cue-version` (default `v0.17.1`, and only a version
whose sha256 `wiring/install-tools.sh` holds) install CUE.

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
| `CASCADE_DRY_RUN` | receivers | the receiver pushes only when it is `false`, in any letter case (GitHub compares without case); unset, deleted or anything else is a dry run (compute, summary and artifact; no push, PR, label or comment) |
| `CASCADE_NOTIFY` | upstreams | `off` skips notify, so that repo's releases stop dispatching |
| `CASCADE_G2_MODE`, `CASCADE_G3_MODE` | receivers | `warn` (default: a problem posts `success` with `WARN:`) or `enforce` (a problem posts `failure`) |

A run from any ref other than `main` and every gates-only run is always a dry run, and
`workflow_dispatch` with `dry_run: true` dry-runs one run.

**Stop switches**, smallest first: the `deps-cascade:hold` label on the cascade PR (the bot
skips it); a `.cascade-hold` entry (one pin); `CASCADE_DRY_RUN` set to anything but `false` (in any letter case);
`CASCADE_NOTIFY=off` in an upstream; disabling `deps-cascade.yml`; suspending the
`opm-cascade` App (notify and publish then fail at minting, compute and gates keep running).

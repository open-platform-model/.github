## Why

The cascade's version logic is merged (`add-cascade-resolver`, archived 2026-10-04) and every
receiving repo has a `task -x deps:cascade`, but nothing runs them: no upstream tells a
downstream that it released, and no workflow turns a task diff into the rolling `deps/cascade`
PR. Workspace RELEASING.md, section "Rollout and changes" ("Phases", row 3, and "Changes", row
`add-release-cascade-workflows`) makes this change the first Phase 3 step: shared notify and
receive workflows in `.github`, proven by one full two-repo sandbox cycle before any product repo
joins. The interface every Phase 3 branch builds against is the Phase 3 wiring contract, version
2, committed with this change as `contract.md` and cited as "contract §N".

Phase 0 is done (owner decision 22; state verified 2026-10-04): the `opm-cascade` App (no
Workflows or Actions permission, owner decision 5) is installed on the five product repos and
both sandboxes, each with a `main`-only `cascade` Environment holding `CASCADE_APP_PRIVATE_KEY`
and the variable `CASCADE_APP_CLIENT_ID`.

## What Changes

- **`cascade-notify.yml`** (reusable, `workflow_call`): validates the tag for the calling repo,
  waits for the Go proxy when the source is library, mints an App token scoped to the fixed
  targets and sends `repository_dispatch` `upstream-released` with `{source, tags}` to each
  (RELEASING.md, sections "Notify after publish" and "repository_dispatch"; contract §3.1, §4).
- **`cascade-receive.yml`** (reusable): three jobs. `compute` (no secret) validates the payload,
  evaluates G2 and G3, picks the branch mode, runs the repo's task, commits as the bot, builds
  title, body and labels, and uploads a git bundle and plan. `gates` posts G2 and G3 with
  `GITHUB_TOKEN`. `publish` (`cascade` Environment) verifies the plan, mints the token, and
  pushes under a lease, creates or edits, recreates, closes or labels the PR (RELEASING.md,
  sections "The receiver", "One rolling PR per repo", "Additive commits", "Title from diff
  class", "Concurrency", "Two-job split", "Labels"; contract §5 to §7, §9).
- **`cascade-gates.yml`** (reusable): the per-PR `pull_request_target` worker that posts `n/a`
  on ordinary PRs and starts a gates-only receiver run on release PRs (RELEASING.md, section
  "Gates"; contract §8).
- **Scripts** under `.github/scripts/cascade/wiring/`: `lib.sh` (the fixed maps of contract §3,
  payload validation, the cascade-PR filter, Notes and title-marker parsing, the title rank, the
  mention lint, comment texts, `WF_GUARD_RULE`), `notify.sh`, `receive-compute.sh`,
  `receive-publish.sh`, `gates-eval.sh`, `gates-post.sh`. The repo-name derivation and the
  `org-github-ref` guard are not scripts: they are the inline first step of every job, run
  before anything is checked out from the ref they guard.
- **Resolver widening for the sandbox** (contract §11.2): `lib/prtext.sh:11` accepts the names in
  `CASCADE_EXTRA_SOURCES` as triggering sources; only the sandbox receiver sets it.
- **Tests and CI**: an offline wiring suite `.github/scripts/cascade/wiring/test/run.sh` (bare
  `file://` repos, a `gh` shim, the real resolver's offline subcommands) run as a new step of
  the existing `Resolver tests` job in `cascade-resolver.yml`, which also gains a pinned,
  checksum-verified go-task install; its shim joins the `shellcheck` step. No new job and no new
  check context (contract §12).
- **README**: a "cascade workflows" part of the `cascade` section: the three workflows, the
  caller shapes, the repo variables (`CASCADE_DRY_RUN`, `CASCADE_NOTIFY`, `CASCADE_G2_MODE`,
  `CASCADE_G3_MODE`) and the stop switches.
- **The sandbox cycle** (contract §11): the seed files are committed under
  `openspec/changes/add-release-cascade-workflows/sandbox/`, then pushed to `cascade-sandbox-up`
  and `cascade-sandbox-down` to call these workflows at a full commit SHA of
  `feat/add-release-cascade-workflows`, with that SHA as `org-github-ref` (the sandbox
  Environments hold the production App key, so an unreviewed push to the branch must not reach
  them). Run E1, E1b, E2 to E7 (E6 with the supervisor toggling the setting
  during the cycle, before merge) and S3 to S11, and record every run URL, PR URL and outcome in
  `design.md` under "Sandbox cycle" and in the scratchpad file `p3-gh-workflows-sandbox.md`.
  E4c decides `WF_GUARD_RULE` (`strict` stays unless E4c proves `tree` safe; E4c accepted both pushes, so it ships as `tree`). The owner's
  pull-request-only bypass is not exercised; its manual check goes to the scratchpad file
  `p3-gh-workflows-owner-checks.md` for the PR notes.

Not in this change:

- Any product repo's `release.yml` notify job, `deps-cascade.yml` or `cascade-gates.yml` caller,
  or catalog_opm's `verify-published` split: those are each repo's `join-release-cascade`
  (contract §1 B1 to B5, §4.5, §10).
- Setting `CASCADE_DRY_RUN` in a product repo, making G2 or G3 required, or flipping a gate mode
  (supervisor before each join; Phase 5 `require-pin-freshness-gate`).
- The workspace RELEASING.md amendments of contract §14: a separate workspace PR.
- The `tag-ledger.yml` `REPOS` and `README.md:90` scope fix for `opm`: its own `.github` PR.
- The composite-action fallback of contract §13.1; it is built only if E1 fails, and then only
  after the supervisor accepts that contract change.

## Capabilities

### New Capabilities

- `cascade-workflows`: rules shared by the three reusable workflows: pinning, permissions, no
  inline expressions, no secrets input, repo-name derivation, the `org-github-ref` sandbox
  guard, and App token minting.
- `cascade-notify`: the notify interface, the fixed source-to-target map, tag shapes, the
  dispatch payload and retries, and library's Go proxy wait.
- `cascade-receive`: the receive interface and job split, dry run, payload validation, the
  cascade-PR filter, modes, merge rules, Notes, title, labels with the breaking check, the action
  table, the workflows guard, and publish's verification.
- `cascade-gates`: G2 and G3 evaluation, the status mapping and modes, and the per-PR workflow.

### Modified Capabilities

- `cascade-pr-text`: "Cascade PR body" accepts the sources in `CASCADE_EXTRA_SOURCES`.
- `cascade-resolver-checks`: "Required CI check for .github" also runs the wiring suite and
  shellchecks its shim; a new requirement describes the offline wiring suite.

## Impact

- **New files** under `.github/workflows/` (three) and `.github/scripts/cascade/wiring/`; one
  line in `.github/scripts/cascade/lib/prtext.sh` plus two cases in
  `.github/scripts/cascade/test/cases/prtext.sh`; one step and one shim path in
  `.github/workflows/cascade-resolver.yml`; the README. `mention-guard.yml`, `tag-ledger.yml` and
  `cascade-resolver-live.yml` are untouched.
- **Callers.** After this merges: core (notify only), catalog_opm, library, opm-operator and cli
  (notify, receiver, gates caller) through their `join-release-cascade`, all at `@main` (owner
  decision 13); during the change only `cascade-sandbox-up` and `cascade-sandbox-down`, at a commit SHA of
  `feat/add-release-cascade-workflows`.
- **Hosts and APIs.** `api.github.com` (dispatches, pulls, releases, labels, comments, statuses,
  workflow dispatch), `github.com` (git fetch and push with the App token), `proxy.golang.org`
  (library notify only). The resolver keeps its own host list.
- **Depends on:** `add-cascade-resolver` (merged); the Phase 0 settings (done); and, before the
  sandbox cycle (section 5 of `tasks.md`), three supervisor steps from contract §11 and §15:
  `cascade-sandbox-up` made public (it is still private on 2026-10-04), a PR-required `main`
  ruleset with an owner pull-request-only bypass on both sandboxes (none exists yet), and this
  branch pushed to `origin`. The agent sets `CASCADE_DRY_RUN=false` on `cascade-sandbox-down`
  after seeding (allowed by the Phase 3 brief). During the cycle the supervisor also toggles
  `sha_pinning_required` on `cascade-sandbox-down` for E6. After merge the supervisor moves the
  sandbox callers to `@main` and deletes the branch.
- **Gate to merge:** the full sandbox cycle green with E1, E1b and E2 to E5 recorded (contract
  §1), and the contract §14 RELEASING.md amendments merged before or together with this PR.
- **Depended on by:** `join-release-cascade` in core, catalog_opm, library, opm-operator and cli;
  each may be written in parallel but merges only after this change, because it calls `@main`.
- **Owner steps (never in `tasks.md`):** the bypass check in `p3-gh-workflows-owner-checks.md`; if E6 shows
  `sha_pinning_required` refuses an `@main` reusable call, the opm-operator decision of contract
  §15 item 2.
- **Release class:** none; `.github` does not release. PR title:
  `feat(cascade): add the release cascade workflows`.

## Context

The interface is fixed by the Phase 3 wiring contract, version 2, committed verbatim with this
change as `contract.md` and cited as "contract §N". It binds this change (contract §1 row A) and
the five `join-release-cascade` changes (rows B1 to B5). This design does not reopen it; it
records layout, script interfaces, network calls, the few points the contract leaves to this
change, and the sandbox cycle. Where the contract and workspace RELEASING.md disagree, the
contract §14 amendments to RELEASING.md land first (contract §1); a new disagreement goes to the
supervisor.

State of `.github` at `origin/main` (`6a18e7d`):

- Workflows: `mention-guard.yml` (required org-wide by path from `main`, its pattern at
  `mention-guard.yml:56`), `tag-ledger.yml`, `cascade-resolver.yml` (job `Resolver tests`,
  `timeout-minutes: 10` at `:27`, `shellcheck` over `.github/scripts` plus two shims at `:66-69`,
  `actionlint` on `.github/workflows/*.yml` at `:79`, the offline suite at `:81-82`) and
  `cascade-resolver-live.yml`. Every checkout is pinned to
  `3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1` (`tag-ledger.yml:72`,
  `cascade-resolver.yml:39`).
- The resolver `.github/scripts/cascade/cascade-resolve.sh` with `lib/`. `classify`, `title`,
  `body`, `semver-cmp` and the steering-file readers need no network. The `release` kind takes
  any repo matching `REPO_RE` (`lib/query.sh:15`, `:50`) and reads tags with an isolated,
  credential-free `git ls-remote` (`lib/release.sh:10-19`) and assets anonymously
  (`lib/release.sh:48`), so it cannot see a private upstream.
- The triggering-source allowlist is the literal at `lib/prtext.sh:11`, enforced at
  `lib/prtext.sh:166`; the "Unknown source dropped" case is `test/cases/prtext.sh:216-218`.
- The canonical stub `stub-resolve.sh` answers `newest`, `published`, `pin-of`, `language-of`,
  the steering-file readers, `semver-cmp` and `next-patch`, but not `classify`, `title` or
  `body` (`stub-resolve.sh:18-90`).

Live state of the sandboxes (2026-10-04, `gh api`): both hold only `README.md`; both have the
`cascade` Environment with a custom branch policy listing only `main`; neither has a branch
ruleset of its own (only the org `mention-guard` ruleset applies); `cascade-sandbox-up` is still
private.

## Goals / Non-Goals

**Goals:**

- Implement contract §2 to §9 and §12 in `.github`, so B1 to B5 only add callers.
- Prove the whole path in a real repo pair before any product repo calls it (contract §11),
  including the two GitHub behaviours no document settles: whether a reusable job's
  `environment:` resolves the caller's Environment secret (E1, E1b), and when GitHub refuses an
  App push for want of the Workflows permission (E2 to E5).

**Non-Goals:**

- Product repo callers (B1 to B5), RELEASING.md text (contract §14), Phase 4 and 5 switches.
- Any change to the resolver's query logic; the only resolver edit is the sandbox allowlist line.

## Decisions

### Layout

```text
.github/workflows/cascade-notify.yml
.github/workflows/cascade-receive.yml
.github/workflows/cascade-gates.yml
.github/scripts/cascade/wiring/lib.sh
.github/scripts/cascade/wiring/notify.sh
.github/scripts/cascade/wiring/receive-compute.sh
.github/scripts/cascade/wiring/receive-publish.sh
.github/scripts/cascade/wiring/gates-eval.sh
.github/scripts/cascade/wiring/gates-post.sh
.github/scripts/cascade/wiring/test/run.sh
.github/scripts/cascade/wiring/test/lib.sh
.github/scripts/cascade/wiring/test/shim/gh
.github/scripts/cascade/wiring/test/cases/*.sh
.github/scripts/cascade/wiring/test/fixtures/
```

`lib.sh` is the single source of every fixed map (contract §3.1 to §3.7), the comment texts
(contract §7.5), the mention-lint pattern (copied from `lib/prtext.sh:10`, the same as
`mention-guard.yml:56`) and the constant `WF_GUARD_RULE` (default `strict`). Every other script
sources it and nothing else duplicates a map.

### Workflows

All three follow the `cascade-workflows` spec. Third-party pins are the contract §2.2 SHAs
(checkout v7.0.1, create-github-app-token v3.2.0, setup-go v7.0.0, setup-cue v1.0.1, setup-task
v2.0.0); `actions/upload-artifact` and `actions/download-artifact` are pinned to the SHA of their
current release at implementation time, recorded in a comment.

| Workflow | Job (name) | Environment | Permissions | Timeout | Runs |
| --- | --- | --- | --- | --- | --- |
| `cascade-notify.yml` | `notify` (`Notify downstream`) | `cascade` | `contents: read` | 20 | guard, checkout `org-github`, `notify.sh validate`, Go proxy wait (library), mint, `notify.sh dispatch` |
| `cascade-receive.yml` | `compute` (`Compute`) | none | `contents: read`, `pull-requests: read` | 45 | contract §6.2 steps 1 to 15 |
| | `gates` (`Post gates`) | none | `statuses: write`, `pull-requests: read` | 10 | contract §6.3 |
| | `publish` (`Publish`) | `cascade` | `contents: read`, `pull-requests: read` | 15 | contract §6.4 |
| `cascade-gates.yml` | `gates` (`Cascade gates`) | none | `statuses: write`, `actions: write` | 5 | contract §8.3, inline script, no checkout |

No job name here is, or becomes in this change, a required check. Each job's first step derives
the repo name from `GITHUB_REPOSITORY` (contract §2.2) and runs the `org-github-ref` guard
(contract §2.4); both are `lib.sh` functions, except in `cascade-gates.yml`, which inlines the
same two checks because it checks nothing out (contract §8.3).

The `compute` job outputs `action`, `dry_run` and `mode`. `publish`'s `if:` is the contract
§6.4 expression. Artifacts: `cascade-gates` (`gates.json`) and `cascade-plan` (`plan.json`,
`body.md`, `cascade.bundle`, and `diff.patch` in a dry run), retention 1 day.

### Script interfaces

Every script: bash, `set -euo pipefail`, a `die()` to stderr, tool check at start (`git`, `jq`,
and `gh` where used; `task` and mikefarah `yq` v4 in `receive-compute.sh` and `gates-eval.sh`),
`gh` only through `"${CASCADE_GH:-gh}"`, sleeps only through `"${CASCADE_SLEEP:-sleep}"`.
Exit codes: 0 success, 1 failure, 2 usage. Scratch directory `CASCADE_T` (the workflows set it
to `$RUNNER_TEMP/cascade`; scripts refuse a `CASCADE_T` inside `repo/` or `org-github/`).

| Script | Syntax | Environment read | Writes |
| --- | --- | --- | --- |
| `notify.sh` | `notify.sh validate --tag <tag>` | `CASCADE_REPO` | stdout: targets, comma-separated; exit 1 "not a cascade source" or bad tag |
| | `notify.sh dispatch --tag <tag>` | `CASCADE_REPO`, `GH_TOKEN` (App), `GITHUB_STEP_SUMMARY` | one summary line per target; exit 1 when any target failed after 3 attempts |
| | `notify.sh wait-proxy --tag <tag>` | `CASCADE_PROXY` (default `https://proxy.golang.org`) | always exit 0; a warning on timeout |
| `receive-compute.sh` | `receive-compute.sh <step>`, step one of `guard`, `payload`, `gates`, `state`, `prepare`, `notes`, `run`, `text`, `action`, `plan`, `summary` | `CASCADE_REPO`, `CASCADE_T`, `CASCADE_RESOLVER`, `CASCADE_DRY_RUN`, `CASCADE_REF` (`github.ref`), `CASCADE_EVENT` (`github.event_name`), `CASCADE_PAYLOAD` (`toJSON(github.event.client_payload)`), `CASCADE_G2_MODE`, `CASCADE_G3_MODE`, `GH_TOKEN` (`GITHUB_TOKEN`) | `GITHUB_ENV`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`, files under `CASCADE_T` |
| `receive-publish.sh` | `receive-publish.sh verify`, then (token minted) `receive-publish.sh act` | `CASCADE_REPO`, `CASCADE_T`, `CASCADE_LABELS_MANAGED`, `GH_TOKEN` (`GITHUB_TOKEN` for `verify`, App token for `act`), `CASCADE_PUSH_B64` (masked header, `act` only) | PR, labels, comments, branch; `verify` exits 1 before the mint on any refusal; `act` exits 1 for `too_long` |
| `gates-eval.sh` | `gates-eval.sh` | `CASCADE_REPO`, `CASCADE_T`, `CASCADE_RESOLVER`, `GH_TOKEN` | `$CASCADE_T/gates.json`; exit 1 only when the release-PR list cannot be read (then no file) |
| `gates-post.sh` | `gates-post.sh --g2-mode <m> --g3-mode <m> <gates.json>` | `CASCADE_REPO`, `CASCADE_RUN_URL`, `GH_TOKEN` | statuses; exit 1 when any post failed |

Each step of `receive-compute.sh` is one workflow step, so the job log shows which part failed
and contract §6.2's order is visible in the workflow file.

### Network requests

All through `gh api` with the token named; GitHub answers are checked by status.

| Request | Who | Token | Expected | On failure |
| --- | --- | --- | --- | --- |
| `GET https://proxy.golang.org/github.com/open-platform-model/library/@v/<tag>.info` | notify (library) | none | 200 | 404/410/other: poll again every 30 s, 10 min cap, then warn and continue |
| `POST /repos/open-platform-model/<target>/dispatches` | notify | App (targets, contents write) | 204 | 3 attempts (5, 15, 45 s), then the target counts as failed |
| PR list (`gh pr list --head deps/cascade --base main --state open --json …`) | compute, publish verify, gates-eval (own repo and G3 upstreams) | `GITHUB_TOKEN` | 200 | job error (compute, publish); evaluator error (G3) |
| PR list for release PRs (`--state open --base main --json number,headRefName,headRefOid,isCrossRepository,labels,body`) | gates-eval, gates (missing artifact, enforce) | `GITHUB_TOKEN` | 200 | gates-eval exit 1; gates job fails |
| `GET /repos/open-platform-model/<repo>/releases` (paginated) | compute breaking check | `GITHUB_TOKEN` | 200 | no label, summary warning |
| `git ls-remote` / `git fetch` of `github.com/open-platform-model/<repo>` | compute, publish verify | anonymous for public repos; the checkout's `GITHUB_TOKEN` header is not persisted, so the private sandbox-down fetches with a `GITHUB_TOKEN` extraheader set the same way as the push header | success | job error |
| `git push` with lease to `deps/cascade` (update, create, delete) | publish act | App (own repo) | success | lease rejected: job fails, the next run retries (close: warning, delete skipped) |
| `gh pr create` / `gh pr edit` / `gh pr close` / `gh pr comment` | publish act | App | 2xx | job fails |
| `gh label create --force` (or `gh label list` with `labels-managed`) | publish act | App | 2xx | job fails |
| `POST /repos/open-platform-model/<repo>/statuses/<sha>` | gates, cascade-gates | `GITHUB_TOKEN` (`statuses: write`) | 201 | gates-post exit 1 |
| `POST /repos/open-platform-model/<repo>/actions/workflows/deps-cascade.yml/dispatches` (`gh workflow run --ref main -f gates_only=true`) | cascade-gates | `GITHUB_TOKEN` (`actions: write`) | 204 | contract §8.3 error/WARN statuses, then fail |

### Branch strategy, title, labels, gates

Exactly contract §7.1 to §7.6 and §8. Two implementation points the contract leaves open:

- **Merge-mode derived files.** A conflicted path counts as derived when its basename is
  `go.mod`, `go.sum` or `manifest.go`, it ends in `cue.mod/module.cue`, or it equals
  `internal/operator/dist/install.yaml` (contract §7.2, RELEASING.md "One rolling PR per repo").
- **The commit-identity test** for `rebuild` compares both `%ae` and `%ce` of every commit in
  `origin/main..origin/deps/cascade` to the bot's noreply email (contract §7.1). A merge commit
  the bot made counts as a bot commit.

### Tests and CI

The wiring suite (`cascade-resolver-checks` spec, "Offline wiring test suite") mirrors the
resolver suite: `test/run.sh` sources `test/lib.sh` (case runner, `PASS`/`FAIL`, temp dirs under
a trap, git isolated with `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`). The `gh`
shim answers each `gh` invocation from a per-case fixture directory keyed by the argument
vector, logs every call, and fails a case on an unexpected call. A static case greps the three
workflows' `run:` blocks for `${{` and fails on a match.

`cascade-resolver.yml` gains one step, `Offline wiring tests` (`bash
.github/scripts/cascade/wiring/test/run.sh`), after `Offline resolver tests`, and the `gh` shim
joins the shellcheck file list. The job and context name stay `Resolver tests`; the timeout is
raised from 10 only if a green run needs it.

## Research & Decisions

### Environment secrets in a reusable workflow (E1, E1b)

- **Context.** RELEASING.md, section "Notify after publish", puts `environment: cascade` inside
  the reusable workflow because a `uses:` caller job cannot set it. The GitHub pages read during
  research do not say whether the called job resolves the caller repo's Environment; one search
  summary suggested it does not.
- **Options.** (a) Reusable jobs declare the Environment (contract §2.2). (b) Composite actions
  called from a caller-owned job that declares it (contract §13.1).
- **Decision.** (a), proven by E1 (a real dispatch minted in the sandbox) and E1b (a branch
  run is refused by the Environment's `main`-only policy before any step). If E1 fails, stop and
  report; (b) is a contract change the supervisor must accept first.

### When GitHub refuses an App push without the Workflows permission (E2 to E5)

- **Context.** Owner decision 5 forbids the Workflows permission. GitHub's rule is undocumented;
  third-party reports (lanes#694, php-fpm-ng#710, community discussion 35410) suggest it compares
  the pushed tree to the default branch's tip, and that merges or force-updates across a
  workflow change on `main` are refused.
- **Decision.** Push only what passes under both plausible rules (contract §7.6, `strict`).
  E4c measures whether an in-place lease update across a workflow change and a pushed merge
  commit that brings `main`'s workflow change in are accepted. Only if both are accepted does
  this change set `WF_GUARD_RULE=tree` (fewer `recreate` and `conflict` outcomes), and then
  E3/E4 (a) and (b) are rerun expecting `push`. The value and the evidence are recorded under
  "Sandbox cycle" before merge; it is not a follow-up. If E2 fails, the design cannot work
  without the forbidden permission: stop and escalate (contract §13.2).

### A private upstream sandbox

- **Context.** The resolver reads `release` sources anonymously (`lib/release.sh:10-19`, `:48`);
  `cascade-sandbox-up` is private, so `newest release cascade-sandbox-up` would fail.
- **Decision.** Make `cascade-sandbox-up` public (contract §11.1, a supervisor step); never give
  the resolver credentials. `cascade-sandbox-down` stays private; the resolver never reads it.

### Sandbox sources in the PR body

- **Options.** (A) Accept the "dropped triggering source" warning in sandbox PR bodies. (B) A
  sandbox-only variable widening `lib/prtext.sh:11`. (C) A sandbox stub resolver.
- **Decision.** (B): `CASCADE_SOURCES=" core catalog_opm library opm-operator cli
  ${CASCADE_EXTRA_SOURCES:-} "`, with every extra name checked against `REPO_RE` and ignored with
  a warning otherwise. Only `receive-compute.sh` exports it, only when the repo is
  `cascade-sandbox-down`, with the literal `cascade-sandbox-up` (contract §3.6); never from an
  input or the payload. (A) would leave S2's "Triggering releases" check unprovable; (C) would
  test a stub instead of the resolver.

### Statuses posted with GITHUB_TOKEN

- **Decision.** Both gate contexts are posted by GitHub Actions (integration 15368), from the
  `gates` job and the per-PR workflow, never with the App token (contract §8.4). The App's Commit
  statuses permission becomes unused (a contract §14 note for the owner).

### `@main` calls under `sha_pinning_required` (E6)

- **Context.** opm-operator has `sha_pinning_required: true`; owner decision 13 says `@main`.
  docs-kit's tag-pinned reusable call ran green there, which suggests reusable-workflow refs are
  exempt, but the setting's date is unknown.
- **Decision.** Measure E6 in `cascade-sandbox-down` (setting toggled by the supervisor, since
  repo Actions settings are outside this branch's sandbox permissions) and record the result; a
  refusal is an owner decision for opm-operator (contract §15 item 2), not something this change
  works around.

### Departures from contract §12, reported to the supervisor

- **The wiring suite uses the real resolver, not the stub.** The toy task needs `title`,
  `body` and `classify`, which the stub does not implement (`stub-resolve.sh:18-90`) and which
  run offline in the real resolver. The toy task never calls `newest`, so no network is reached.
- **The concurrency-group expression is not tested offline.** It lives in each caller (contract
  §5), not in any `.github` file, and no offline evaluator of GitHub expressions exists here.
  actionlint checks it in the sandbox caller, and S11 proves the three cases from run logs.

## Risks / Trade-offs

- [Under `strict`, every workflow change on `main`, including Dependabot `github_actions` bumps,
  turns a bot-only cascade PR into a new PR and a human-touched one into `conflict`] → E4c may
  allow `tree`; otherwise accepted and documented in the C-recreate comment and RELEASING.md.
- [One App key in seven Environments: anyone who can run a `main` job in any `cascade`
  Environment, sandboxes included, reaches all seven repos with the App's permissions] → sandbox
  `main` rulesets before the Environments are used (contract §11.5); probe tokens always scoped
  with `repositories`; rotating the key rotates it everywhere. Recorded again under "Sandbox
  cycle".
- [`compute` runs repo code, and G2 runs it from a release-PR head] → no secret in `compute`,
  read-only permissions, `publish` re-derives and verifies everything before minting (contract
  §6.4, §8.2).
- [A newer pending run replaces an older pending one in the `deps-cascade` group] → it loses only
  its `CASCADE_EXPECT` wait and its "Triggering releases" line; the version is re-resolved and
  the breaking label comes from the pin range (contract §5).
- [The per-PR `pull_request_target` workflow on Dependabot PRs may get a read-only token (E7)] →
  recorded; it blocks only Phase 5's required contexts.
- [Public repos disable scheduled workflows after 60 days without activity] → product repos are
  active; the sandbox uses no schedule.
- [`publish` runs with `GITHUB_TOKEN` for git reads on the private sandbox] → the header is set
  through `GIT_CONFIG_*` like the push header, never persisted in `.git/config`.

## Migration Plan

1. Sections 1 to 4 of `tasks.md` land the code and tests, each green and committed.
2. The supervisor completes the sandbox preconditions (proposal "Depends on").
3. Section 5 runs the sandbox cycle against this branch and records results here.
4. The contract §14 workspace PR merges, then this PR, then the sandbox callers move to `@main`
   and S1 is rerun once (contract §11.3).
5. B1 to B5 merge after this, each receiver behind `CASCADE_DRY_RUN=true`.

Rollback: callers stop at once by stop switches (contract §9.2: `CASCADE_NOTIFY=off`,
`CASCADE_DRY_RUN` not `false`, disabling `deps-cascade.yml`, suspending the App). Reverting this
PR breaks every `@main` caller, so revert the callers first.

## Sandbox cycle

The run follows contract §11.3 and §11.4. The sandbox repos are seeded by PRs there; pushes,
releases, tags and repository variables in the two sandbox repos are allowed by the Phase 3 run
rules; Environments, secrets, Actions settings and rulesets there are supervisor-only. Every row
gets its run URL, PR URL and observed outcome. Nothing has run yet.

**Preconditions** (supervisor): `cascade-sandbox-up` public; `main` rulesets on both sandboxes;
`CASCADE_DRY_RUN=false` on `cascade-sandbox-down`; this branch pushed to `origin` so
`@feat/add-release-cascade-workflows` resolves.

**Seeds.** `cascade-sandbox-up`: `README.md`; `.github/workflows/release.yml`
(`workflow_dispatch` input `version`; job `release` with `contents: write` creating a published
release with `up.tar.gz`; job `notify-downstream` calling `cascade-notify.yml@feat/add-release-cascade-workflows`
with `org-github-ref` set the same); seed release `v0.1.0`. `cascade-sandbox-down`:
`UPSTREAM_VERSION` (`v0.1.0`), `Taskfile.yml` with the four cascade tasks, `.tasks/cascade/classes`
(`shipped UPSTREAM_VERSION`, `test fixtures/`), `.tasks/cascade/pins.sh` (one row, key
`github.com/open-platform-model/cascade-sandbox-up`, display `up`, class `shipped`),
`.tasks/cascade/cascade.sh` (contract §11.3), `.github/workflows/ci.yml` (job `ci`),
`.github/workflows/touch.yml`, `.github/workflows/deps-cascade.yml` (contract §5, no schedule,
`setup-cue: false`), `.github/workflows/cascade-gates.yml` (contract §8.3).

| Id | Step | Pass | Run / PR | Result |
| --- | --- | --- | --- | --- |
| E1 | S1: release `v0.2.0` in up | notify mints in the reusable job; down starts a `repository_dispatch` run whose actor is `opm-cascade[bot]`; a branch `workflow_dispatch` of down's caller is a forced dry run | | not run |
| E1b | `probe-env` branch in up calls notify | the Environment refuses before any step; no token | | not run |
| E2 | S2: receiver opens the PR | one PR by `app/opm-cascade`, title `fix(deps): bump up to v0.2.0`, body with moved pin, triggering release and Notes marker; bot commit; `ci` and `mention-guard` pass | | not run |
| S3 | release `v0.3.0` | same PR number, one commit, `v0.3.0`, title updated | | not run |
| S4 | human commit `fixtures/human.txt`, release `v0.4.0` | human commit kept as ancestor, bot commit on top, title `fix(deps)` | | not run |
| E3/E4 | `touch.yml` changed on `main`; (a) with the human commit, (b) bot-only after close and rerun, (c) probe pushes | (a) `conflict`, label and comment, no push; (b) `recreate` with Notes and labels carried; (c) decides `WF_GUARD_RULE` | | not run |
| E5 | probe update-branch with the App token | recorded only | | not run |
| E6 | `sha_pinning_required` on down (supervisor), caller at `@main` | recorded; refusal goes to the owner | | not run (needs A on `main`) |
| E7 | a Dependabot PR in down | `n/a` statuses posted, or the read-only token recorded as a Phase 5 blocker | | not run |
| S5 | Notes edited, release again | Notes byte for byte; a bare mention in Notes fails mention-guard (accepted) | | not run |
| S6 | squash-merge the PR | `main` message is exactly `<PR title> (#N)` | | not run |
| S7 | fake `release-please--x` PR behind | `cascade/freshness` `WARN: behind: up …`; ordinary PR `n/a` | | not run |
| S8 | dispatch `{"source":"evil","tags":["@x"]}` | dropped with a warning, sweep, no mention | | not run |
| S9 | `CASCADE_DRY_RUN=true`, release | summary diff and "DRY RUN", nothing pushed | | not run |
| S10 | retitle to `feat(deps): sandbox`, release | title kept, marker computed, no title-rise comment | | not run |
| S11 | push to the S7 PR while a dispatch run is pending | gates-only run in `deps-cascade-gates`; pending run not replaced | | not run |

**`WF_GUARD_RULE`:** `strict` (default; to be confirmed or changed by E4c).

**Shared-key reach:** the seven `cascade` Environments hold one App key (contract Facts); whoever
can run a `main` job in any of them can mint a token for all seven repos. Rotating the key
rotates it everywhere.

## Open Questions

None that change the specs or tasks. E1, E2 and E6 can each force a supervisor or owner decision
(contract §13, §15); the tasks stop and report at those points instead of choosing.

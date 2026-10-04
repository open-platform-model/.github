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
.github/actions/cascade-notify/action.yml     (composite; E1 replaced cascade-notify.yml)
.github/actions/cascade-publish/action.yml    (composite; E1 moved publish out of cascade-receive.yml)
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
`mention-guard.yml:56`) and the constant `WF_GUARD_RULE` (`tree`, decided by E4c; it was `strict` until then). Every other script
sources it and nothing else duplicates a map.

### Workflows

The two reusable workflows and the two composite actions follow the `cascade-workflows` spec
(the table below is the shape after the E1 fallback; see Research & Decisions). Third-party pins are the contract §2.2 SHAs
(checkout v7.0.1, create-github-app-token v3.2.0, setup-go v7.0.0, setup-cue v1.0.1, setup-task
v2.0.0); `actions/upload-artifact` and `actions/download-artifact` are pinned to the SHA of their
current release at implementation time, recorded in a comment.

| Workflow | Job (name) | Environment | Permissions | Timeout | Runs |
| --- | --- | --- | --- | --- | --- |
| the caller's `notify-downstream`, running `actions/cascade-notify` | `Notify downstream` | `cascade` | `contents: read` | 20 | guard, `notify.sh validate` (scripts from the action's own directory), Go proxy wait (library), mint, `notify.sh dispatch` |
| `cascade-receive.yml` | `compute` (`Compute`) | none | `contents: read`, `pull-requests: read` | 45 | contract §6.2 steps 1 to 15, then `Done` (output `ok`) |
| | `gates` (`Post gates`) | none | `contents: read`, `statuses: write`, `pull-requests: read` | 10 | contract §6.3 |
| the caller's `publish`, running `actions/cascade-publish` | `Publish` | `cascade` | `contents: read`, `pull-requests: read` | 15 | guard, main-only check, the `dry-run` input, contract §6.4 |
| `cascade-gates.yml` | `gates` (`Cascade gates`) | none | `statuses: write`, `actions: write` | 5 | contract §8.3, inline script, no checkout |

No job name here is, or becomes in this change, a required check.

**The guard step.** The first step of every reusable job and of both composite actions is the
same inline `run:` step, `Guard`, written in the YAML and run before any script. It reads
`GITHUB_REPOSITORY`, fails unless the owner is exactly `open-platform-model` and the name is
non-empty and matches the resolver's `REPO_RE`, and writes the name to the step output `repo`
(contract §2.2, §2.4). The wiring suite extracts the step text from each job and action with
`yq`, asserts the copies are identical, and runs it against the guard cases. Until the review of
the sandbox cycle it also refused an `org-github-ref` other than `main` outside the sandboxes;
that input is gone (next paragraph).

**Scripts at the pinned commit (review M2, owner decision 24).** Every caller pins the four
cascade references to a full commit SHA of `.github` `main`, and the scripts always come from
that same commit. The composite actions run them from their own directory
(`$GITHUB_ACTION_PATH/../../scripts/cascade/wiring/`; the runner downloads the whole `.github`
tree at the action's ref) and check nothing else out. `cascade-receive.yml` cannot see its own
files, so each job's `Own commit` step reads `job.workflow_repository` and `job.workflow_sha`
(the identity of the called workflow, not the caller), fails unless they are
`open-platform-model/.github` and a 40-character SHA (an empty ref would check out the default
branch), and the `org-github` checkout uses that SHA. Before this, the actions and the workflow
checked their scripts out at `org-github-ref`, default `main`, which the Guard refused to change
outside the sandboxes: a SHA-pinned reference would have run its own `action.yml` with `main`'s
scripts, and a script-interface change on `main` would have broken every pinned caller until it
moved its pin. `cascade-gates.yml` checks nothing out and only lost the input. actionlint 1.7.12
does not know `job.workflow_*` yet, so `.github/actionlint.yaml` ignores exactly that message for
`cascade-receive.yml`; the sandbox runs prove the values (Sandbox cycle, review-fix rows).

The `compute` job outputs `action`, `dry_run`, `mode` and `ok`, which `cascade-receive.yml`
exposes as `action`, `dry-run` and `compute-ok`. The caller's `publish` `if:` is the contract
§6.4 expression with `compute-ok` for `needs.compute.result` and three terms the caller reads
itself, never from `compute`: `inputs.dry_run != true`, `vars.CASCADE_DRY_RUN == 'false'` and
`github.ref == 'refs/heads/main'`. `compute` runs repo code, which
can write `GITHUB_ENV` or `BASH_ENV` for the steps after it, so its `dry_run` output alone cannot
hold the `CASCADE_DRY_RUN` stop switch; `receive-publish.sh verify` also refuses a plan whose
`effective_dry_run` is true.

**The stop switch inside the action (review M1).** After the E1 fallback the `if:` above lived
only in each repo's copy of the caller, and one typo would have made a receiver live while
`CASCADE_DRY_RUN=true`. So `cascade-publish` takes a required input `dry-run`, which the caller
gives the same expression as the reusable job's: `${{ inputs.dry_run == true ||
vars.CASCADE_DRY_RUN != 'false' }}`. `receive-publish.sh` reads it as `CASCADE_PUBLISH_DRY_RUN`
first in `verify` (exactly `false`: go on; `true`: a notice, `publish=false`, exit 0, so the mint
and `act` are skipped; anything else, empty or missing included, a refusal before the mint), and
`act` refuses unless it is `false`. GitHub does not enforce `required` on a composite input, so
the script's refusal of an empty value is what makes it required. The `if:` keeps its switch
terms only so a dry run starts no `cascade` Environment job. Static cases check the expression
byte for byte in the README shape and the sandbox caller, and that the sandbox `if:` equals the
README's; each join change asserts its own. Artifacts: `cascade-gates` (`gates.json`) and `cascade-plan`
(`plan.json`, `body.md`, `cascade.bundle`, and `diff.patch` in a dry run), retention 1 day.

### Script interfaces

Every script: bash, `set -euo pipefail`, a `die()` to stderr, tool check at start (`git`, `jq`,
and `gh` where used; `task` and mikefarah `yq` v4 in `receive-compute.sh` and `gates-eval.sh`),
`gh` only through `"${CASCADE_GH:-gh}"`, sleeps only through `"${CASCADE_SLEEP:-sleep}"`.
Exit codes: 0 success, 1 failure, 2 usage. Scratch directory `CASCADE_T` (the workflows set it
to `$RUNNER_TEMP/cascade`; scripts refuse a `CASCADE_T` inside `repo/` or the `.github` tree
they run from).

| Script | Syntax | Environment read | Writes |
| --- | --- | --- | --- |
| `notify.sh` | `notify.sh validate --tag <tag>` | `CASCADE_REPO` | stdout: targets, comma-separated; exit 1 "not a cascade source" or bad tag |
| | `notify.sh dispatch --tag <tag>` | `CASCADE_REPO`, `GH_TOKEN` (App), `GITHUB_STEP_SUMMARY` | one summary line per target; exit 1 when any target failed after 3 attempts |
| | `notify.sh wait-proxy --tag <tag>` | `CASCADE_PROXY` (default `https://proxy.golang.org`) | always exit 0; a warning on timeout |
| `receive-compute.sh` | `receive-compute.sh <step>`, step one of `init`, `payload`, `gates`, `state`, `prepare`, `notes`, `run`, `text`, `action`, `plan`, `summary` | `CASCADE_REPO` (the `Guard` output), `CASCADE_T`, `CASCADE_RESOLVER`, `CASCADE_DRY_RUN`, `CASCADE_GATES_ONLY`, `CASCADE_REF` (`github.ref`), `CASCADE_EVENT` (`github.event_name`), `CASCADE_PAYLOAD` (`toJSON(github.event.client_payload)`), `CASCADE_G2_MODE`, `CASCADE_G3_MODE`; `GH_TOKEN` and `CASCADE_READ_TOKEN` (both `GITHUB_TOKEN`) only on the steps that call the API or fetch (`gates`, `state`, `text`) | `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`, files under `CASCADE_T`; never `GITHUB_ENV` |
| `receive-publish.sh` | `receive-publish.sh verify`, then (token minted) `receive-publish.sh act` | `CASCADE_PUBLISH_DRY_RUN` (the `dry-run` input), `CASCADE_REPO`, `CASCADE_T`, `CASCADE_LABELS_MANAGED`, `GH_TOKEN` (`GITHUB_TOKEN` for `verify`, the mint output for `act`), `CASCADE_READ_TOKEN` (`verify` only) | PR, labels, comments, branch; `verify` exits 1 before the mint on any refusal; `act` exits 1 for `too_long` |
| `gates-eval.sh` | `gates-eval.sh` | `CASCADE_REPO`, `CASCADE_T`, `CASCADE_RESOLVER`, `GH_TOKEN` | `$CASCADE_T/gates.json`; exit 1 only when the release-PR list cannot be read (then no file) |
| `gates-post.sh` | `gates-post.sh --g2-mode <m> --g3-mode <m> <gates.json>` | `CASCADE_REPO`, `CASCADE_RUN_URL`, `GH_TOKEN` | statuses; exit 1 when any post failed |

Each step of `receive-compute.sh` is one workflow step, so the job log shows which part failed
and contract §6.2's order is visible in the workflow file. Steps hand values to each other
through one file per value under `$CASCADE_T/state/`, read without `eval` or `source`; the
payload values reach the task only through the `run` step's own environment.

### Token hygiene in `compute` and `publish`

- **Repo code never sees a token.** Every command that runs repo code (`task -x deps:cascade`,
  its `:title` and `:body` tasks, `.tasks/cascade/pins.sh`, and the G2 task in a release-head
  worktree) runs under
  `env -u GH_TOKEN -u GITHUB_TOKEN -u CASCADE_READ_TOKEN -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0`.
  The `run` step is not given either token at all. A wiring case has the toy task fail when it
  sees `GH_TOKEN`, `GITHUB_TOKEN` or `CASCADE_READ_TOKEN`.
- **The read header.** `actions/checkout` keeps no credential (`persist-credentials: false`), so
  the later `git ls-remote` and `git fetch` of a private repo (only `cascade-sandbox-down`) need
  one. `lib.sh`'s `git_read` sets `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_0` and
  `GIT_CONFIG_VALUE_0` to the masked `GITHUB_TOKEN` header inside a subshell around that one git
  call, and only when `CASCADE_READ_TOKEN` is set; nothing is written to `.git/config`.
- **The push header.** `act` receives only the mint output, as `GH_TOKEN` through `env:`. It
  computes the base64 of `x-access-token:<token>` itself, prints `::add-mask::` for it, and
  exports `GIT_CONFIG_*` inside its own process. No step hands the header to another step, and
  nothing writes it to `GITHUB_ENV`, an output or a file.
- **What this does not stop (review m3).** `run_repo_code` removes the tokens from repo code's
  own environment, but repo code in the `gates` or `run` step can still write the runner's
  `GITHUB_ENV`, `GITHUB_PATH` or `BASH_ENV` files, so a later `compute` step that holds the
  read-only `GH_TOKEN` and `CASCADE_READ_TOKEN` can end up running its code, and it can forge
  the `action` and `compute-ok` outputs. The reach is what `compute`'s token already allows
  (`contents: read`, `pull-requests: read`) plus a forged plan, which `publish` re-derives and
  verifies before it mints (contract §6.4); the stop switch is not read from `compute` at all.
  So "no token reaches repo code" holds for the process, not for the job. This matters again in
  Phase 5, when G2 and G3 become required checks: their statuses are posted by the `gates` job
  from `gates.json`, which `compute` wrote after running repo code, so a release head's own task
  could shape its G2 result (Risks).
- **No red annotation for "nothing to do" (review m2).** go-task under `GITHUB_ACTIONS=true`
  prints `::error title=Task '<name>' failed::exit status <n>` on stdout for any failing task,
  including the cascade's exit 3. `repo_task` pipes the task's stdout through a filter that drops
  only that exact line for exit status 3; the pipeline's status stays the task's, and every other
  failure keeps its annotation.

### Network requests

All through `gh api` with the token named; GitHub answers are checked by status.

| Request | Who | Token | Expected | On failure |
| --- | --- | --- | --- | --- |
| `GET https://proxy.golang.org/github.com/open-platform-model/library/@v/<tag>.info` | notify (library) | none | 200 | 404/410/other: poll again every 30 s, 10 min cap, then warn and continue |
| `POST /repos/open-platform-model/<target>/dispatches` | notify | App (targets, contents write) | 204 | 3 attempts (waits of 5 and 15 s between them), then the target counts as failed |
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
- **A failed gate evaluation does not stop pin work.** When `gates-eval.sh` cannot read the
  release-PR list (exit 1, no `gates.json`), the `gates` step of a real run warns and continues;
  the `gates` job then handles the missing artifact (contract §6.3). Only a gates-only run fails.
- **A rebuild with nothing new keeps the old commit.** When the rebuilt tree equals `OLD`'s
  tree and `OLD` is one commit on the current `origin/main`, `compute` resets to `OLD`, so a
  sweep with nothing new pushes nothing (`new_tip == old_tip`, only edits).
- **A hold that appears after `compute`** stops `publish` in `verify`, before the mint.
- **The commit-identity test** for `rebuild` compares both `%ae` and `%ce` of every commit in
  `origin/main..origin/deps/cascade` to the bot's noreply email (contract §7.1). A merge commit
  the bot made counts as a bot commit.

### Tests and CI

The wiring suite (`cascade-resolver-checks` spec, "Offline wiring test suite") mirrors the
resolver suite: `test/run.sh` sources `test/lib.sh` (case runner, `PASS`/`FAIL`, temp dirs under
a trap, git isolated with `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`). The `gh`
shim answers each `gh` invocation from a per-case fixture directory keyed by the argument
vector, logs every call, and fails a case on an unexpected call. A static case greps the three
workflows' `run:` blocks for `${{` and fails on a match. The toy task calls the real resolver
for `title`, `body`, `classify` and `semver-cmp`, all offline; no case calls `newest`,
`published` or `pin-of`.

`cascade-resolver.yml` gains two steps in the `Resolver tests` job: `Install task`, which
downloads go-task v3.52.0 from its GitHub release and checks a pinned sha256, as the job already
does for shellcheck and actionlint (the ubuntu-24.04 image ships no go-task, and the wiring
suite runs `task`); and `Offline wiring tests` (`bash .github/scripts/cascade/wiring/test/run.sh`)
after `Offline resolver tests`. The `gh` shim joins the shellcheck file list. The job and
context name stay `Resolver tests`; the timeout is raised from 10 only if a green run needs it.

## Research & Decisions

### Environment secrets in a reusable workflow (E1, E1b)

- **Context.** RELEASING.md, section "Notify after publish", puts `environment: cascade` inside
  the reusable workflow because a `uses:` caller job cannot set it. The GitHub pages read during
  research do not say whether the called job resolves the caller repo's Environment; one search
  summary suggested it does not.
- **Options.** (a) Reusable jobs declare the Environment (contract §2.2). (b) Composite actions
  called from a caller-owned job that declares it (contract §13.1).
- **First decision.** (a), to be proven by E1 and E1b before merge.
- **E1 result (2026-10-04): (a) fails.** In run
  [37205835905](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37205835905)
  the reusable notify job ran in the caller's `cascade` Environment and read
  `vars.CASCADE_APP_CLIENT_ID` from it, but `secrets.CASCADE_APP_PRIVATE_KEY` was empty and the
  mint failed ("The 'private-key' input must be set to a non-empty string"). A probe
  ([37205963663](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37205963663))
  called one reusable job with `environment: cascade` twice: without `secrets:` it saw the
  variable but not the secret; with `secrets: inherit` it saw both. So a called workflow sees
  the caller's Environment secrets only when the caller passes `secrets: inherit`, which contract
  §2.2 forbids.
- **Decision: (b), the contract §13.1 fallback**, implemented in this change on the
  supervisor's standing instruction. Notify and publish are composite actions
  (`.github/actions/cascade-notify`, `.github/actions/cascade-publish`) that take the key as the
  `private-key` input. The caller owns each job that mints: it declares `environment: cascade`,
  passes `secrets.CASCADE_APP_PRIVATE_KEY` and `vars.CASCADE_APP_CLIENT_ID`, and holds the
  stop-switch `if:`. `cascade-notify.yml` is deleted; `cascade-receive.yml` keeps `compute` and
  `gates`, and outputs `action`, `dry-run` and `compute-ok` for the caller's `publish` job, which
  reads the dry-run switches itself. `cascade-publish` also fails on any ref but `main`.
  `secrets: inherit` (the one-line alternative) was not chosen: it hands every repo and org
  secret of the caller to the called workflow, where the composite action receives only the key.
  E1 was re-run on the fallback (Sandbox cycle).

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

### Branch references under `sha_pinning_required` (E6)

- **Context.** opm-operator has `sha_pinning_required: true`; owner decision 13 says `@main`.
  docs-kit's tag-pinned reusable call ran green there, which suggests reusable-workflow refs are
  exempt, but the setting's date is unknown.
- **Decision.** Measure E6 in `cascade-sandbox-down` and record the result; a refusal is an
  owner decision for opm-operator (contract §15 item 2), not something this change works around.
- **E6 result (2026-10-04).** `sha_pinning_required` does **not** refuse a reusable-workflow
  reference by branch (`@main`, or a `.github` feature branch) or by SHA; all three ran. It
  **does** refuse an action reference by branch, including the `.github` composite actions
  (`cascade-notify@<branch>`: "is not allowed ... because all actions must be pinned to a
  full-length commit SHA"), and accepts them by full SHA. Because E1 moved notify and publish
  into composite actions, opm-operator's `notify-downstream` and `publish` steps cannot use
  `@main` while the setting is on: the owner chooses between turning the setting off there and
  pinning opm-operator's two action references to a `.github` commit SHA (a carve-out from
  owner decision 13). Its `cascade-receive.yml@main` and `cascade-gates.yml@main` calls are
  unaffected.
- **Owner decision 24 (2026-10-04).** "Pin by SHA in all five repos": every repo pins the
  cascade actions (and, in the README shapes, the two reusable workflows) to a `.github` commit
  SHA; this supersedes `@main` from decision 13 for the cascade references. Review M2 made the
  pin mean what it says: the scripts now come from the pinned commit too (Workflows, "Scripts at
  the pinned commit"). The cost the owner accepted: every change to the cascade workflows or
  actions needs one pin-bump PR per product repo (README "Pinning and bumps").

### Departures from the contract, reported to the supervisor

- **The wiring suite uses the real resolver, not the stub** (contract §12). The toy task needs
  `title`, `body` and `classify`, which the stub does not implement (`stub-resolve.sh:18-90`)
  and which run offline in the real resolver. No case calls `newest`, `published` or `pin-of`,
  so no network is reached.
- **The concurrency-group expression is not evaluated offline** (contract §12). It lives in each
  caller (contract §5), and no offline evaluator of GitHub expressions exists here. Instead the
  sandbox caller is committed with this change (`sandbox/down/`), the pinned actionlint checks
  it, a wiring case asserts its `concurrency.group` equals the contract §5 string byte for byte,
  and S11 proves the three cases from run logs.
- **`publish`'s `if:` gains `!inputs.dry-run && github.ref == 'refs/heads/main'`, and `verify`
  refuses `effective_dry_run: true`** (contract §6.4). Only additions: the stop switch no longer
  depends on an output of the job that runs repo code.
- **The `gates` job also has `contents: read`** (contract §6.1 table). It checks out `org-github`
  for `gates-post.sh`, and contract §2.2 gives that checkout `contents: read`.
- **The title-rise comment fires only on `push` and `recreate`** (contract §6.4 step 5 says
  "independently of the action"). "Once per rise" relies on the body marker being rewritten with
  `T_computed`; the other actions never edit the body, so firing there would repeat the comment
  on every run.
- **Notify waits 5 and 15 s between its 3 attempts** (contract §4.1 lists "5, 15 and 45 s").
  Three attempts have two gaps; a 45 s wait after the last attempt would only delay the red job.
- **E3/E4 (b) is split** (contract §11.4). As written, (b) closes the PR, reruns and expects
  "recreate with the Notes carried", but with no open PR `CASCADE_NOTES_FILE` is not set
  (contract §6.2 step 9) and "a recreate with no open PR carries nothing" (contract §6.4). (b) is
  now a bot-only branch under an open PR (`rebuild` turned into `recreate` by the guard, Notes
  and labels carried); (b2) is the closed PR (a fresh PR with no Notes). The contract text is
  inconsistent, not the design; reported to the supervisor.
- **Contract §13.1 fallback implemented (E1).** Notify and publish are composite actions in
  caller-owned `cascade` jobs; `cascade-notify.yml` is gone and `cascade-receive.yml` has two
  jobs plus the outputs `action`, `dry-run` and `compute-ok`. Every caller shape in contract §4.3,
  §4.5 and §5 changes (README "Cascade workflows" holds the new ones); the B changes depend on it.
- **`WF_GUARD_RULE` ships as `tree` (E4c).** Under `tree` a workflow change on `main` alone (D1
  empty) is merged or rebuilt in place, and `recreate` happens only for a closed PR's leftover
  branch. That is not "never `conflict`" (review m1): when the branch itself differs from `main`
  in a workflow file (D1 non-empty, for example a human workflow commit on `deps/cascade`), merge
  mode still gives `conflict` with reason `workflows` (`lib.sh` `wf_guard`), and fresh, rebuild
  and recreate modes give `error`, because the task never edits workflows.
- **S5: mention-guard no longer fails on a bare mention in a bot-authored PR body.** `.github`
  main treats such a body as advisory (a notice), so the P2 §11 C1 expectation the contract
  repeats is outdated. Nothing in this change depends on it.
- **S6: the squash commit is not "title only".** GitHub appends `Co-authored-by:` trailers for
  commit authors other than the merger even under the BLANK message setting, so a merged cascade
  PR carries `Co-authored-by: opm-cascade[bot] <…>`. The first line is exactly `<title> (#N)`;
  release-please reads the header and the footers it knows (`BREAKING CHANGE`, `Release-As`),
  not `Co-authored-by` (review n1), so releases are unaffected.
- **E3/E4 (b) reached without a human force push** (Sandbox cycle).

## Risks / Trade-offs

- [Under `strict`, every workflow change on `main`, including Dependabot `github_actions` bumps,
  turns a bot-only cascade PR into a new PR and a human-touched one into `conflict`] → E4c showed
  GitHub accepts both updates, so `tree` ships; `strict` stays in the code should GitHub tighten
  the rule, and a refused push then fails the publish job visibly.
- [One App key in seven Environments: anyone who can run a `main` job in any `cascade`
  Environment, sandboxes included, reaches all seven repos with the App's permissions] → sandbox
  `main` rulesets before the Environments are used (contract §11.5); probe tokens always scoped
  with `repositories`; rotating the key rotates it everywhere. Recorded again under "Sandbox
  cycle".
- [`compute` runs repo code, and G2 runs it from a release-PR head] → no secret in `compute`,
  read-only permissions, `publish` re-derives and verifies everything before minting (contract
  §6.4, §8.2), and the stop switch is the `cascade-publish` input, never a `compute` output.
  Repo code can still reach later `compute` steps through the runner's env files and shape
  `gates.json` (Token hygiene, review m3); before G2 and G3 become required in Phase 5, that
  reach needs its own answer (for example evaluating G2 in a job that runs no other step after
  the repo task).
- [A newer pending run replaces an older pending one in the `deps-cascade` group] → it loses only
  its `CASCADE_EXPECT` wait and its "Triggering releases" line; the version is re-resolved and
  the breaking label comes from the pin range (contract §5).
- [The per-PR `pull_request_target` workflow on Dependabot PRs may get a read-only token (E7)] →
  E7 showed `Statuses: write` and `Actions: write` on a Dependabot PR; not a Phase 5 blocker.
- [Public repos disable scheduled workflows after 60 days without activity] → product repos are
  active; the sandbox uses no schedule.
- [`compute` and `publish` read the private sandbox with `GITHUB_TOKEN`] → the header is set
  through `GIT_CONFIG_*` in a subshell around the one git call, never persisted in
  `.git/config`, and every repo-code command runs with all tokens unset (Token hygiene).
- [During the cycle the sandbox callers run code from `feat/add-release-cascade-workflows`, an
  unprotected branch, inside `cascade` Environments that hold the one App key] → a push to that
  branch needs no review, so a caller at the branch ref would let whoever can push it (anyone
  with write access to `.github`) mint a token for any of the seven repos through the next
  sandbox run. The callers therefore pin a full commit SHA of this branch (implementation review
  finding 3; since review M2 the scripts come from that same commit): a later push to the branch changes
  nothing a sandbox runs until a sandbox PR, merged by PR under the sandbox `main` ruleset, moves
  the pin. Right after this PR merges the callers move to a SHA on `.github` `main` and the
  branch is deleted (Migration Plan step 4, task 5.8).

## Migration Plan

1. Sections 1 to 4 of `tasks.md` land the code and tests, each green and committed.
2. The supervisor completes the sandbox preconditions (proposal "Depends on").
3. Section 5 runs the sandbox cycle against this branch and records results here.
4. The contract §14 workspace PR merges, then this PR. Right after the merge the sandbox
   callers move to a full commit SHA on `.github` `main` in one sandbox PR per sandbox,
   `feat/add-release-cascade-workflows` is deleted from `origin`, and S1 is rerun once (contract
   §11.3, task 5.8). The product callers pin a `.github` `main` SHA as well (owner decision 24)
   and move it by the README's bump procedure.
5. B1 to B5 merge after this, each receiver behind `CASCADE_DRY_RUN=true`.

Rollback: callers stop at once by stop switches (contract §9.2: `CASCADE_NOTIFY=off`,
`CASCADE_DRY_RUN` not `false`, disabling `deps-cascade.yml`, suspending the App). Every caller
is pinned to a SHA, so reverting this PR changes nothing a product repo runs until its pin moves;
remove or disable the callers first.

## Sandbox cycle

The run follows contract §11.3 and §11.4, with E3/E4 (b) split as "Departures" says. The
sandbox repos are seeded by PRs there. Under the Phase 3 brief the agent may, in the two
sandbox repos only, open and merge PRs, push branches, create releases and tags (never move or
delete one), send dispatches and set repository variables; Environments, secrets, Actions
settings and rulesets there stay supervisor steps. Sandbox clones use `git@github.com:` URLs:
the owner's `gh` token has no `workflow` scope, so an HTTPS push of `.github/workflows/*` would
be refused. Every row gets its run URL, PR URL, the `org-github` commit it ran, and the observed
outcome, here and in the scratchpad file `p3-gh-workflows-sandbox.md`.

**Status (2026-10-04): done.** The full cycle ran against `feat/add-release-cascade-workflows`
with every caller pinned to a commit SHA (implementation review finding 3). Three `.github`
commits were exercised: `d5d47bb` (the reusable notify and publish jobs; E1 failed there),
`038da12` (the contract §13.1 fallback: composite actions in caller-owned `cascade` jobs) and
`30a98c6` (`WF_GUARD_RULE=tree` from E4c). Each move of the pin was a sandbox PR: [up#3](https://github.com/open-platform-model/cascade-sandbox-up/pull/3) and
[down#4](https://github.com/open-platform-model/cascade-sandbox-down/pull/4) to `038da12`, [up#4](https://github.com/open-platform-model/cascade-sandbox-up/pull/4) and [down#10](https://github.com/open-platform-model/cascade-sandbox-down/pull/10) to `30a98c6`. Seeds: [down#1](https://github.com/open-platform-model/cascade-sandbox-down/pull/1) and [up#1](https://github.com/open-platform-model/cascade-sandbox-up/pull/1); release
`v0.1.0` by hand; `CASCADE_DRY_RUN=false` on down. Cleanup: [down#15](https://github.com/open-platform-model/cascade-sandbox-down/pull/15) and [up#5](https://github.com/open-platform-model/cascade-sandbox-up/pull/5) removed every
probe workflow, the probe PRs [down#3](https://github.com/open-platform-model/cascade-sandbox-down/pull/3) and [down#13](https://github.com/open-platform-model/cascade-sandbox-down/pull/13) were closed, and the `probe-env`, `probe/*`,
`probe-branch-run` and `release-please--branches--main` branches were deleted. Left open on
purpose: the live cascade PR [down#14](https://github.com/open-platform-model/cascade-sandbox-down/pull/14) and Dependabot's [down#2](https://github.com/open-platform-model/cascade-sandbox-down/pull/2). `v0.2.0` exists from the failed
first E1 run, so the reruns started at `v0.2.1`; releases are never deleted.

Two scenarios ran differently from the runbook, for reasons outside the code:

- **E3/E4 (b).** The runbook's human lease-reset of `deps/cascade` to the last bot-only commit
  was refused by this session's own permission layer (a force push), not by GitHub. The same
  state was reached without it: (b2) closed the PR so the bot recreated the branch bot-only under
  a new PR, then a second workflow change on `main` under that open PR gave `rebuild` with D2
  non-empty, which is exactly (b).
- **E6.** The agent toggled `sha_pinning_required` on `cascade-sandbox-down` itself, under the
  supervisor's grant for E6 only (owner decision 22 gives settings changes to the supervisor; the
  supervisor confirmed the grant on 2026-10-04, review M3), and restored it 81 seconds later. `.github` has no reusable workflow on `main`, so a
  true `@main` reference was tested against a harmless reusable probe on `cascade-sandbox-up`
  `main`; `.github` references were tested by branch and by SHA.

**Preconditions** (supervisor): `cascade-sandbox-up` public; `main` rulesets on both sandboxes
(contract §11.5); this branch pushed to `origin` so its commit SHAs resolve. All three were met on 2026-10-04. **Agent:** the variable `CASCADE_DRY_RUN=false` on `cascade-sandbox-down`, set after
the seed PR merges and before E1.

**Seeds** (committed under `sandbox/up/` and `sandbox/down/` in this change, linted with the
pinned actionlint and shellcheck before they are pushed). `cascade-sandbox-up`: `README.md`;
`.github/workflows/release.yml` (`workflow_dispatch` input `version`; job `release` with
`contents: write` creating a published release with `up.tar.gz`; job `notify-downstream`
in the `cascade` Environment running the `cascade-notify` action at a commit SHA of this
branch); `.github/workflows/probe-env.yml` (E1b: `workflow_dispatch`,
the same job shape, skipped on `main` so only the `--ref probe-env` run reaches the Environment); seed release
`v0.1.0`. `cascade-sandbox-down`: `UPSTREAM_VERSION` (`v0.1.0`), `Taskfile.yml` with the four
cascade tasks, `.tasks/cascade/classes` (`shipped UPSTREAM_VERSION`, `test fixtures/`),
`.tasks/cascade/pins.sh` (one row, key `github.com/open-platform-model/cascade-sandbox-up`,
display `up`, class `shipped`), `.tasks/cascade/cascade.sh` (contract §11.3),
`.github/workflows/ci.yml` (job `ci`, plus one step using a deliberately old SHA-pinned
`actions/checkout` for E7), `.github/dependabot.yml` (`github-actions`, daily),
`.github/workflows/touch.yml`, `.github/workflows/deps-cascade.yml` (contract §5, no schedule,
`setup-cue: false`, plus the caller-owned `publish` job running `cascade-publish`),
`.github/workflows/cascade-gates.yml` (contract §8.3), and
`.github/workflows/probe.yml`: `workflow_dispatch` with a choice input `e4c-inplace`,
`e4c-merge` or `e5` and a `pr` input, one job in the `cascade` Environment that mints a token
with `repositories: cascade-sandbox-down` and only `contents: write` (E4c) or `contents: write`
plus `pull-requests: write` (E5), and records whether GitHub accepts the push or the
update-branch call. `probe.yml` is in the first seed so that no workflow change on `main` is
needed mid-cycle; it is removed by a sandbox PR, and the `probe-env` branch and the `probe/*`
branches deleted, after the cycle. The committed seeds show the final shape, pinned to
`a2950ce` (review-fix cycle below; `30a98c6` with `org-github-ref` before it). Two probe sets were added during the cycle and are not seeds: `probe-secrets.yml` and
`probe-secrets-called.yml` in up (E1 follow-up, [up#2](https://github.com/open-platform-model/cascade-sandbox-up/pull/2)) and `probe-pin-{a,b,c,d,e,g}.yml` in down
(E6, [down#12](https://github.com/open-platform-model/cascade-sandbox-down/pull/12)); both were removed by the cleanup PRs.

| Id | Step | org-github | Run / PR | Result |
| --- | --- | --- | --- | --- |
| E1 (first) | release `v0.2.0` in up | `d5d47bb` | [up 37205835905](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37205835905) | **fail**: the reusable notify job ran in the caller's `cascade` Environment and read `vars.CASCADE_APP_CLIENT_ID`, but `secrets.CASCADE_APP_PRIVATE_KEY` was empty ("The 'private-key' input must be set to a non-empty string") |
| E1 probe | one reusable job with `environment: cascade`, called without `secrets:` and with `secrets: inherit` | n/a | [up 37205963663](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37205963663), [up#2](https://github.com/open-platform-model/cascade-sandbox-up/pull/2) | without: secret no, variable yes; with `secrets: inherit`: both yes. Contract §13.1 fallback implemented (Research & Decisions) |
| E1 | release `v0.2.1` in up | `038da12` | [up 37206437700](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37206437700), [down 37206458777](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37206458777), branch run [down 37206547449](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37206547449) | **pass**: the caller-owned job minted and dispatched (HTTP 204); down's run is `repository_dispatch`, actor and triggering actor `opm-cascade[bot]`; a `workflow_dispatch` from branch `probe-branch-run` with `dry_run=false` planned `effective_dry_run: true` and `Publish` was skipped |
| E1b | `probe-env.yml` dispatched with `--ref probe-env` | `038da12` | [up 37206627490](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37206627490) | **pass**: "Branch "probe-env" is not allowed to deploy to cascade due to environment protection rules"; zero steps ran, no token |
| E2 | the receiver opens the PR | `038da12` | [down#5](https://github.com/open-platform-model/cascade-sandbox-down/pull/5) | **pass**: author `app/opm-cascade`, title `fix(deps): bump up to v0.2.1`, body with the moved pin `v0.1.0`→`v0.2.1`, triggering release `cascade-sandbox-up` `v0.2.1` and the Notes marker; commit `0518a3c` author and committer the bot; `ci`, `mention-guard` and `Cascade gates` passed |
| E7 | Dependabot PR bumping the old checkout pin | `d5d47bb` | [down#2](https://github.com/open-platform-model/cascade-sandbox-down/pull/2), [gates](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37205783292) | **pass**: the `pull_request_target` token had `Statuses: write` and `Actions: write`; both contexts `success` "n/a: not a release PR" by `github-actions[bot]`. Not a Phase 5 blocker |
| S3 | release `v0.3.0` | `038da12` | [up 37206670878](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37206670878), [down 37206696519](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37206696519) | **pass**: `rebuild`/`push`, PR 5 kept, one commit, `v0.3.0`, title updated |
| S4 | human commit, release `v0.4.0` | `038da12` | [up 37206780011](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37206780011), [down 37206803140](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37206803140) | **pass**: `merge`/`push`; human `458b38d` an ancestor, bot `36c22d1` on top, title `fix(deps)` |
| E3/E4 (a), strict | `touch.yml` changed on main ([down#6](https://github.com/open-platform-model/cascade-sandbox-down/pull/6)), human commit present, release `v0.5.0` | `038da12` | [up 37206905348](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37206905348), [down 37206929569](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37206929569), sweep [down 37206991382](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37206991382) | **pass**: `merge`/`conflict`, reason `workflows`, file `touch.yml`; label and one C-conflict comment, no push; the sweep added no second comment |
| E3/E4 (c) | `probe.yml` `e4c-inplace` and `e4c-merge` | `038da12` | [down 37207063750](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37207063750), [down 37207085490](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37207085490) | **both accepted**: in-place lease update of `probe/inplace` to `f893fd0` and merge commit `df079fb` into `probe/merge`, each with D1 empty and D2 = three workflow files. Decides `tree` |
| E3/E4 (b2), strict | close PR 5, release `v0.6.0` | `038da12` | [up 37207230069](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37207230069), [down 37207250517](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37207250517) | **pass**: `recreate` with no open PR, fresh [down#7](https://github.com/open-platform-model/cascade-sandbox-down/pull/7), no Notes, nothing carried, no comment on the closed PR |
| E3/E4 (b), strict | Notes and `need-human-review` on PR 7, workflow change on main ([down#8](https://github.com/open-platform-model/cascade-sandbox-down/pull/8)), release `v0.7.0` (breaking) | `038da12` | [up 37207358154](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37207358154), [down 37207378831](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37207378831) | **pass**: `rebuild`→`recreate`; C-recreate and "Continued in #9." on PR 7; [down#9](https://github.com/open-platform-model/cascade-sandbox-down/pull/9) with the Notes byte-identical, `need-human-review` carried, `deps-cascade:breaking` from the release notes |
| E3/E4 (b), tree | pin move [down#10](https://github.com/open-platform-model/cascade-sandbox-down/pull/10) is a workflow change on main under bot-only PR 9; release `v0.8.0` | `30a98c6` | [up 37207795782](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37207795782), [down 37207816358](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37207816358) | **pass**: `rebuild`/`push`, PR 9 rebuilt in place on `329c74c` (`d924f19`), no comment |
| E3/E4 (a), tree | human commit `774ed1a`, workflow change on main ([down#11](https://github.com/open-platform-model/cascade-sandbox-down/pull/11)), release `v0.9.0` | `30a98c6` | [up 37207954306](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37207954306), [down 37207979847](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37207979847) | **pass**: `merge`/`push`; the App pushed merge commit `c086837` that brings main's workflow change in; human commit kept |
| E5 | `probe.yml` `e5` on [down#3](https://github.com/open-platform-model/cascade-sandbox-down/pull/3) | `30a98c6` | [down 37208052407](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208052407) | recorded: `PUT update-branch` with the App token was **accepted** after the workflow change ("Updating pull request branch."); unused by the design |
| E6 | `sha_pinning_required: true` on down, probes [down#12](https://github.com/open-platform-model/cascade-sandbox-down/pull/12) | `30a98c6` | A [down 37208164124](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208164124), B [down 37208166361](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208166361), C [down 37208168647](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208168647), D [down 37208170244](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208170244), E [down 37208171918](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208171918), G [down 37208173937](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208173937), receiver [down 37208176173](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208176173) | reusable workflow at `@main` (A), at a SHA (B) and at a `.github` branch (C): **not refused**, all ran. Composite action at a SHA (D): ran. Composite action at a branch (E) and the control `actions/checkout@v4` (G): **refused** at job setup, "must be pinned to a full-length commit SHA". The real receiver (reusable and action at `30a98c6`) succeeded with publish |
| S5 | Notes edited on PR 9 with a bare mention of a non-existent handle, release `v0.10.0` | `30a98c6` | [up 37208293318](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37208293318), [down 37208315156](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208315156), [mention-guard](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208368685) | **pass** for the Notes (byte-identical). The mention did **not** fail mention-guard: on `.github` main a bot-authored PR body is advisory (notice only), so the contract's expectation is outdated |
| S6 | squash-merge PR 9 | `30a98c6` | [down#9](https://github.com/open-platform-model/cascade-sandbox-down/pull/9), `5f4f893` | **partial**: first line exactly `fix(deps): bump up to v0.10.0 (#9)`, but GitHub appended `Co-authored-by:` trailers for the other commit authors (the bot, the human, and the `Claude` trailer of the sandbox human commits) despite the BLANK message setting |
| S7 | fake release PR with `UPSTREAM_VERSION` behind | `30a98c6` | [down#13](https://github.com/open-platform-model/cascade-sandbox-down/pull/13), gates-only [down 37208464972](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208464972) | **pass**: `cascade/freshness` `success` "WARN: behind: up v0.9.0→v0.10.0", `cascade/settled` "ok: upstreams settled"; the gates-only run skipped `Publish`; ordinary PRs show `n/a` |
| S8 | dispatch `{"source":"evil","tags":["@x"]}` | `30a98c6` | [down 37208516941](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208516941) | **pass**: "payload dropped: source `evil` is not accepted by cascade-sandbox-down; continuing as a sweep", `fresh`/`noop`, no `@x` in the plan or body |
| S9 | `CASCADE_DRY_RUN=true`, release `v0.11.0`, back to `false` | `30a98c6` | [up 37208574770](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37208574770), [down 37208598636](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208598636) | **pass**: `effective_dry_run: true`, `Publish` skipped, no branch or PR, `diff.patch` `v0.10.0`→`v0.11.0` (the summary's "DRY RUN" line is not readable through the API; the offline case covers it) |
| S10 | release `v0.12.0` ([down#14](https://github.com/open-platform-model/cascade-sandbox-down/pull/14)), retitle to `feat(deps): sandbox`, release `v0.13.0` | `30a98c6` | [down 37208687309](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208687309), [down 37208784609](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208784609) | **pass**: title kept, body marker `fix(deps): bump up to v0.13.0`, no comment |
| S11 | sweep active, dispatch pending, push to the S7 PR | `30a98c6` | sweep [down 37208881115](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208881115), dispatch [down 37208904285](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208904285), gates-only [down 37208922871](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37208922871) | **pass**: the dispatch run was pending from 14:20:35 to 14:21:04 (the sweep ended 14:21:02); the gates-only run was created 14:20:54 and started 14:20:58 in its own group; the pending run was not replaced and its body names `cascade-sandbox-up` `v0.14.0` |

**Proxies (review n2).** Three rows prove their point only through a stand-in, which is
acceptable but should be read as such: E7 ran in the private `cascade-sandbox-down`, while every
product repo is public; S5's Notes edit had no CRLF, so the CRLF case is proven only by the
offline suite; and E6 tested a true `@main` reusable reference against a probe workflow on
`cascade-sandbox-up`, because `.github` `main` had no cascade workflow yet.

### Review-fix cycle (`a2950ce`)

The verification of the cycle above (findings M1, M2 and m2, and owner decision 24) changed the
actions, the receive and gates workflows and `receive-compute.sh`; `a2950ce` carries all of it.
The sandbox callers moved to it by [up#6](https://github.com/open-platform-model/cascade-sandbox-up/pull/6) and [down#16](https://github.com/open-platform-model/cascade-sandbox-down/pull/16), which also drop
`org-github-ref` and pass `cascade-publish` its `dry-run` input. These runs re-prove the changed
parts: the scripts at the pinned commit, the dry-run switch inside the action, one dispatch
updating the rolling PR, notify, and the exit-3 annotation.

| Id | Step | `.github` | Run / PR | Result |
| --- | --- | --- | --- | --- |
| R1 notify, switch on | `CASCADE_DRY_RUN=true` on down, release `v0.15.0` in up | `a2950ce` | [up 37211493811](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37211493811), [down 37211515507](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37211515507) | **pass**: the notify job downloaded `open-platform-model/.github@a2950ce`, ran `notify.sh` from `GITHUB_ACTION_PATH` and dispatched (HTTP 204). Down's `Own commit` step logged `scripts from open-platform-model/.github a2950ce6d314618c108cfdf2e978133c2ab09f4a` in both jobs (so `job.workflow_sha` is the called workflow's SHA). The plan was `rebuild`/`push` with `effective_dry_run: true`, `Publish` was skipped, and `deps/cascade` stayed at `c4965a0` |
| R2 switch inside the action | probe [down#17](https://github.com/open-platform-model/cascade-sandbox-down/pull/17): the real receiver (always a dry run) plus `cascade-publish` with `dry-run` given by hand and no switch in its `if:`; removed by [down#18](https://github.com/open-platform-model/cascade-sandbox-down/pull/18) | `a2950ce` | `true`: [down 37211613251](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37211613251); empty: [down 37211616082](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37211616082); `False`: [down 37211773378](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37211773378) | **pass**: with `true` the Publish job ran and logged "dry run (the dry-run input is true); nothing is published", and the mint and `Act` steps were skipped. An empty dispatch value became the input's default `true` (GitHub's doing; the offline cases cover empty and missing). With `False` the job failed with "refusing the plan: the dry-run input must be true or false, not `False`" before the mint. `deps/cascade` stayed at `c4965a0` throughout |
| R3 switch off, one dispatch | `CASCADE_DRY_RUN=false`, release `v0.16.0` in up | `a2950ce` | [up 37211875058](https://github.com/open-platform-model/cascade-sandbox-up/actions/runs/37211875058), [down 37211895079](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37211895079), gates [down 37211939078](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37211939078) | **pass**: notify dispatched (HTTP 204); the `repository_dispatch` run verified `push` and updated [down#14](https://github.com/open-platform-model/cascade-sandbox-down/pull/14) in place to `9f3806c` (one commit, author and committer `opm-cascade[bot]`, `fix(deps): bump up to v0.16.0`; the human title `feat(deps): sandbox` kept, as in S10); `Cascade gates` at `a2950ce` passed on the new head |
| R4 sweep with nothing new | `workflow_dispatch` sweep | `a2950ce` | [down 37211972443](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37211972443) | **pass**: `rebuild` with an unchanged tree kept the old commit; PR 14's head stayed `9f3806c` |
| R5 no-change annotation (m2) | squash-merge PR 14 (down `main` `9c504e9`), then a sweep | `a2950ce` | [down 37212051452](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37212051452) | **pass**: the task exited 3 (`fresh`/`noop`, `Publish` skipped); the log has go-task's plain "exit status 3" lines but no `##[error]`, and the job annotations are notices only |

Also on `a2950ce`: `Cascade gates` on the probe PRs ([down 37211593025](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37211593025),
[down 37211841347](https://github.com/open-platform-model/cascade-sandbox-down/actions/runs/37211841347)) posted `n/a` with no `org-github-ref` input.
After the cycle `CASCADE_DRY_RUN` on down is `false`, its `main` is at `v0.16.0`, no cascade PR
is open, and Dependabot's [down#2](https://github.com/open-platform-model/cascade-sandbox-down/pull/2) is still open.

**`WF_GUARD_RULE`: `tree`**, decided by E4c (contract §7.6). With an App token scoped to
`cascade-sandbox-down` and only `contents: write`, after `main` had changed three workflow files
(`cascade-gates.yml`, `deps-cascade.yml`, `touch.yml`) since the probe branches were built,
GitHub accepted both the in-place `--force-with-lease` update of `probe/inplace` to `main` plus
one commit (D1 empty, D2 the three files) and the push of a merge commit bringing `main` into
`probe/merge` (same D2). So GitHub compares the pushed tree to the default branch, not the
update to the old tip. `strict` stays implemented and tested through a rule-swapped copy of the
scripts, should GitHub tighten the rule.

**Shared-key reach:** the seven `cascade` Environments hold one App key (contract Facts); whoever
can run a `main` job in any of them can mint a token for all seven repos. Rotating the key
rotates it everywhere. During the cycle that reach also extends to whoever can push to
`feat/add-release-cascade-workflows` in `.github` (Risks); it ends when the sandbox callers move
to a SHA on `.github` `main` and the branch is deleted (Migration Plan step 4).

## Open Questions

- **opm-operator under `sha_pinning_required` (E6): answered** by owner decision 24 (every repo
  pins by SHA), with the scripts at the pinned commit since review M2.
- **Contract v3.** The five join changes cite contract v2, which still has `org-github-ref`,
  `@main` callers, the reusable notify workflow and `publish` inside `cascade-receive.yml`; they
  need the README caller shapes, the `dry-run` input and the bump procedure (review B2, a
  supervisor step).
- **RELEASING.md** (contract §14, a workspace PR) must also describe the caller-owned
  `cascade` jobs, `tree`, and the S5/S6 findings above.

## Plan review (commit c8a038d)

1 blocker, 6 majors, 9 minors and 4 nits; every finding is applied. Finding 17 (the branch-ref
reach during the cycle) was first applied as its second option, record plus a listed step after
merge, on the grounds that the reach was the same set of people who can change `.github`'s
workflows by PR. That was wrong: a push to the feature branch needs no PR. The implementation
review (finding 3) corrected it, and the sandbox callers now pin a commit SHA of this branch
(Risks); a fix found during the cycle costs one sandbox PR to move the pin. Finding 4 also
reports the contract §11.4 (b) inconsistency to the supervisor ("Departures").

## Implementation review (head 04bc25d)

2 blockers, 1 major, 2 minors, 3 nits. The two blockers are gates, not code: the sandbox cycle
(run in section 5) and the contract §14 RELEASING.md amendments (a workspace PR the supervisor
owns). Applied in this change:

- **3 (major).** Sandbox callers pin a full commit SHA of this branch (Risks); task 5.8 moves
  them to a SHA on `main` after merge and deletes the branch.
- **4.** `gates-post.sh` posts only on the head of an open same-repo release PR, listed with
  `GITHUB_TOKEN` exactly as `--missing` lists them; any other entry in `gates.json` (which
  compute, running repo code, wrote) is skipped with a warning, and a failed listing posts
  nothing and fails the job.
- **5.** The proposal commit `c8a038d` is part of this branch; section 5's commits are listed in
  `tasks.md`.
- **6.** A `deps-cascade:hold` added between compute and publish is stop switch 1 used as
  documented: `verify` writes a notice and `publish=false` and exits 0, and the mint and `act`
  steps are skipped (`if: steps.verify.outputs.publish == 'true'`). No verified plan is written,
  so `act` alone still refuses.
- **7.** The breaking check returns 2 when `.tasks/cascade/pins.sh` fails and warns "the
  breaking check failed: .tasks/cascade/pins.sh failed" instead of naming the release API.
- **8.** The cleanup PR also removes `probe-env.yml` from `cascade-sandbox-up`.


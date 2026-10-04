## Context

`add-release-cascade-workflows` (PR 9, squash `2376ffa`) split the receiver into `compute` (runs
repo code, no secret), `gates` (posts statuses with `GITHUB_TOKEN`) and the caller's own
`publish` job (the `cascade` Environment and the App key), and made `publish` re-derive
everything it can from an untrusted plan. The five `join-release-cascade` reviews then found
that the split leaks in three places (proposal, "Why"). This change closes them in `.github`;
each product repo applies the caller edit and the script copy in its next pin bump.

Trust model this design keeps to, stated once:

- **Trusted:** the caller's own `inputs.*` and `vars.*` read in the caller's job, the inputs a
  caller passes `cascade-publish`, the `.github` scripts at the pinned SHA as checked out
  *before* any repo code ran, and anything `publish` re-derives with plain git and the API.
- **Untrusted:** everything `compute` produces after the first step that runs repo code: step
  and job outputs, the job summary, `gates.json`, `plan.json`, the bundle. Repo code is the
  receiver's tasks and `pins.sh` on `main` merged with the `deps/cascade` branch (any write
  collaborator can push there) and the code of every open `release-please--*` head (any write
  collaborator can push one; no ruleset covers it).

## Goals / Non-Goals

**Goals:**

- No gates-only run can reach a token or a push, whatever `compute` outputs.
- Repo code never inherits a variable that names a runner command file, and no `compute` step
  after the first repo-code step holds `GITHUB_TOKEN`.
- One wiring-check script for all five repos, tested once here, with per-repo values in data.

**Non-Goals:**

- A job boundary between the release heads' code and the receiver's own task (G2 in its own
  job): it would need a third job and a second artifact for little gain, since `compute` is
  untrusted either way (Research, "Separate job for G2").
- Trustworthy G2 statuses against a malicious release head: G2 runs that head's own task, so the
  head decides its own freshness by design. The statuses stay `warn`.
- Editing the five repos: their caller edits ride their pin bumps (Migration Plan).

## Decisions

### D1. A gates-only run never publishes, enforced three times

1. **Caller `if:`** (each receiver's `deps-cascade.yml`): `publish` adds
   `&& inputs.gates_only != true` right after `inputs.dry_run != true`. The caller reads its own
   dispatch input, which no step of the reusable job can change.
2. **Action input** (`cascade-publish`): a new input `gates-only`, `required: true`, which the
   caller passes as `${{ inputs.gates_only == true }}`. The `Verify the plan` and `Act` steps get
   it as `CASCADE_PUBLISH_GATES_ONLY`. `receive-publish.sh` checks it first, before the dry-run
   input, the plan or any API call: exactly `false` continues; `true` fails with "refusing the
   plan: a gates-only run never publishes"; any other value (empty, missing, `False`) fails with
   "refusing the plan: the gates-only input must be true or false, not `<value>`". Refusing
   (exit 1) rather than skipping is deliberate: a gates-only run can reach the action only when
   the caller's `if:` is wrong and `compute`'s outputs say `push`, which is either a broken
   caller or a forged run, and both should turn the run red.
3. **Reusable outputs** (`cascade-receive.yml`): `compute`'s outputs become
   `action: ${{ inputs.gates-only && 'gates-only' || steps.plan.outputs.action }}` and
   `ok: ${{ !inputs.gates-only && steps.done.outputs.ok == 'true' && 'true' || 'false' }}`, and
   `receive-compute.sh init` records `dry_run=true` for a gates-only run. These come from the
   input and the `Init` step, which runs before any repo code, so a gates-only run's outputs say
   `gates-only`, `false`, `true` whatever the release heads print. They are defence in depth
   only: with root on a hosted runner, repo code could tamper with the runner that reports job
   outputs (D2), so points 1 and 2 never rely on them.

The `gates-only` input is required rather than defaulting to `false`: a caller that bumps its pin
without passing it fails closed at verify (GitHub warns about a missing required input of a
composite action and passes an empty string), and the wiring check (D4) refuses the shape before
merge.

### D2. Repo code runs after every token read in `compute`

`compute` now runs in this order (new or moved steps in bold); the `Done`, `Summary` and upload
steps are unchanged:

| Step (id) | Script | Token | Repo code | `if:` |
| --- | --- | --- | --- | --- |
| Guard, Own commit, checkouts, setup-go/cue/task | inline, actions | checkout only | no | as before |
| Init (`init`) | `receive-compute.sh init` | none | no | — |
| Payload (`payload`) | `receive-compute.sh payload` | none | no | — |
| **Read gates (`gates-read`)** | `receive-compute.sh gates-read` → `gates-eval.sh read` | `GH_TOKEN`, `CASCADE_READ_TOKEN` | no | — |
| **Read state (`state`)** | `receive-compute.sh state` | `GH_TOKEN`, `CASCADE_READ_TOKEN` | no | `!inputs.gates-only` |
| **Gates (`gates`)** | `receive-compute.sh gates` → `gates-eval.sh run` | **none** | release heads | `!cancelled() && steps.gates-read.outcome == 'success'` |
| Upload the gate results | upload-artifact | runtime only | no | as before |
| Prepare, Notes, Run the task | as before | none | `run` | `!inputs.gates-only` |
| Body, title and labels (`text`) | `receive-compute.sh text` | **none** (was `GH_TOKEN`) | yes | `!inputs.gates-only` |
| Action, Plan, Summary, Upload the plan, Done | as before | none | no | as before |

- `gates-eval.sh read` lists the open same-repo release PRs, evaluates G3 (upstream API reads
  only), and fetches each head commit into the checkout with `git_read`. It writes
  `$CASCADE_T/gates-read.json`: `[{"pr", "sha", "fetched": bool, "settled": {"state", "msg"}}]`.
  Exit 0 written; 1 the release-PR list cannot be read (no file); 2 usage.
- `gates-eval.sh run` reads `gates-read.json`, runs G2 per head (a head with `fetched: false` is
  `error`, "cannot check out the release head"), and writes `$CASCADE_T/gates.json` exactly as
  before. Exit 0 written; 1 no `gates-read.json`; 2 usage. It needs no token and no `gh`.
- `receive-compute.sh gates-read` runs `read`; a failure in a real run is a warning and the run
  goes on (as the old `gates` step did); in a gates-only run it fails the step.
  `receive-compute.sh gates` runs `run` and keeps the gates-only summary and `action=gates-only`
  output; without `gates-read.json` it warns in a real run and fails a gates-only run.
- `receive-compute.sh state` additionally fetches, unless the mode is `skip`, the upstream
  releases the breaking check needs, before any repo code runs: for each repo of
  `changelog_repos <receiver>` (a new fixed map in `lib.sh`: every product repo with a
  changelog source except the receiver itself; `cascade-sandbox-up` for the sandbox receiver),
  `gh api --paginate repos/open-platform-model/<repo>/releases --jq '<tag, BREAKING>'`
  into `$CASCADE_T/releases/<repo>.tsv`; a failed call leaves `<repo>.failed` and is not an
  error here. `breaking_check` (in `text`) reads those files and makes no API call; a missing or
  failed file gives the same warning as an API error did ("the breaking check could not read
  the upstream releases").
- G2 still runs before any pin work, and its results are still uploaded when a later step fails
  (`Gates` runs even when `Read state` failed).

### D3. `run_repo_code` drops the runner's command-file variables

`run_repo_code` unsets, besides the tokens and `GIT_CONFIG_COUNT`/`GIT_CONFIG_PARAMETERS`:
`GITHUB_ENV`, `GITHUB_PATH`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`, `GITHUB_STATE`, every
exported `ACTIONS_*` variable (the runtime, cache, results and OIDC request variables), and every
exported `GIT_CONFIG_KEY_<n>`/`GIT_CONFIG_VALUE_<n>`. The list is computed from `compgen -e` at
call time, so a variable the runner adds under those prefixes is dropped too. Variables a task
may read (`GITHUB_ACTIONS`, `GITHUB_WORKSPACE`, `RUNNER_TEMP`, `PATH`, `HOME`) stay.

### D4. One canonical wiring check, data per repo

`.github/scripts/cascade/wiring-check.sh` (usage `wiring-check.sh [<config>]`, run from the repo
root; exit 0 ok, 1 a mismatch, 2 usage, missing yq or a bad config) checks, against the README
caller shapes of the same commit:

- **Key-holding jobs** (`release.yml:notify-downstream`, `deps-cascade.yml:publish`): exact job
  keys, `name` and step name (`Notify downstream`, `Publish`), `timeout-minutes` (20, 15),
  `environment: cascade`, `runs-on: ubuntu-latest`, exact permissions, one step with keys
  `name`, `uses`, `with`, the action at a full SHA, exact `with` keys, the client id and key
  expressions. Notify's `needs` (string or list), `if:` and `tag` come from the config.
  Publish's `needs` is `cascade`, its `if:` is the D1 expression, `dry-run` and `gates-only` the
  contract expressions, and `labels-managed` the config's YAML boolean.
- **release.yml env**: a map (or absent) whose keys are all in the config's `env-allow`.
- **Receiver shape** (when `receiver: true`): `deps-cascade.yml` top-level keys, `permissions:
  {}`, triggers `repository_dispatch` (`upstream-released`), `schedule`, `workflow_dispatch`
  with boolean `dry_run` and `gates_only`, the concurrency group and `cancel-in-progress:
  false`, the `cascade` job's keys, permissions, `uses`, `dry-run` and `gates-only` and no input
  the reusable workflow does not take; `cascade-gates.yml` top-level keys, `permissions: {}`,
  trigger `pull_request_target` with `opened`, `reopened`, `synchronize`, and the `gates` job's
  keys, permissions and `uses`.
- **Key readers** across every workflow file: case-insensitive `secrets.cascade_app_private_key`,
  `secrets[…]` and `toJSON(secrets)`; any `environment` (string or map) naming `cascade` in any
  case or written as an expression; no `.github` call passing `secrets:`.
- **The pin**: every `.github` reference (four `uses:` and the `cascade-task.yml` resolver
  `ref:`) at one full SHA with the config's `pin-comment`.
- **The CI job** named by `ci.workflow` and `ci.job`: the workflow runs on `pull_request` with no
  `paths`/`paths-ignore`; the job has no `if:` or `continue-on-error`; exactly one step runs
  `task cascade:wiring:check`, with neither key.

The config, `.tasks/cascade/wiring-check.yaml`, is data read with `yq`, never sourced:

```yaml
pin-comment: .github main
receiver: true
env-allow: [OPM_REGISTRY, CUE_REGISTRY]
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

Unknown keys, a non-boolean `receiver` or `labels-managed`, `publish` on a non-receiver, an
`env-allow` entry that is not an upper-case name, and an `env-allow` entry naming a variable
that makes a shell, node, git or the loader run code (`BASH_ENV`, `ENV`, `NODE_OPTIONS`,
`SHELLOPTS`, `PS4`, `LD_PRELOAD`, `PATH`, the `GIT_*` command hooks and others, plus every
`GITHUB_*`, `ACTIONS_*`, `RUNNER_*` and `CASCADE_*` name) are config errors (exit 2), so a
config edit cannot widen the allow-list to a code-running variable.

Checked on 2026-10-04 against each product repo's `origin/main` workflows (core `98c1877`,
catalog_opm `3288406`, library `93a892f`, opm-operator `81a640d`, cli `dc3f77a1`) with the
configs in the README table: after the D1 caller edit all five print `cascade wiring: ok`; as
they are, core passes and each receiver fails on exactly three lines (the publish `with` keys,
its `if:` and its `gates-only` input).

### D5. Keeping the copies identical

The script is pinned like the actions: a repo's copy is the file at the `.github` SHA its
cascade references name. The pin-bump PR (README "Pinning and bumps", step 3) replaces the copy
along with the SHA:

```sh
sha=<the new .github SHA>
gh api "repos/open-platform-model/.github/contents/.github/scripts/cascade/wiring-check.sh?ref=$sha" \
  -H 'Accept: application/vnd.github.raw' >.tasks/cascade/wiring-check.sh
```

and `git diff` of the copy shows only `.github`'s own changes since the old SHA. A reviewer
checks it with `gh api … | cmp - .tasks/cascade/wiring-check.sh`. The script cannot check this
itself offline (it does not know which `.github` commit it was copied from beyond the SHA it
reads, and core has no `.github` checkout in CI), so the check is the PR review's; the README
says so.

### Script interfaces (new or changed)

- `receive-compute.sh <step>`: steps `init payload gates-read state gates prepare notes run text
  action plan summary`. `gates-read` and `state` read `GH_TOKEN` and `CASCADE_READ_TOKEN`; no
  other step does. Exit codes unchanged (0, 1, 2).
- `gates-eval.sh read|run` (D2). Environment: `CASCADE_REPO`, `CASCADE_T`, `CASCADE_REPO_DIR`,
  `CASCADE_RESOLVER`; `GH_TOKEN` and `CASCADE_READ_TOKEN` for `read` only.
- `receive-publish.sh verify|act`: new environment `CASCADE_PUBLISH_GATES_ONLY` (D1). Exit codes
  unchanged (a refusal is 1).
- `wiring-check.sh [<config>]` (D4).

### Network requests

Unchanged hosts and paths; only where they run. `Read state` gains the releases list per
`changelog_repos` entry (`GET api.github.com/repos/open-platform-model/<repo>/releases`, paged,
200; any failure is recorded, not fatal), which `Body, title and labels` used to make.
`gates-eval.sh run` makes no request. `wiring-check.sh` makes none.

### Workflows

No trigger, job name, permission or timeout changes. `cascade-receive.yml`: the step order and
`env` of D2, the two output expressions of D1. `cascade-publish`: the required input
`gates-only`, passed to `Verify the plan` and `Act` as `CASCADE_PUBLISH_GATES_ONLY`.

## Research & Decisions

### Separate job for G2

- Context: review item 2 of the cli join suggested moving G2 into its own job so `compute` never
  runs release-head code before planning.
- Options: (a) a third job `gates-eval` with its own checkout, uploading `cascade-gates`; (b) keep
  G2 in `compute` but after every token read (D2).
- Decision: (b). `compute` already runs untrusted code (merge mode runs the `deps/cascade`
  branch's tasks, which any write collaborator can push), so a job boundary in front of the
  release heads would not make the plan trustworthy; `publish` re-derives it either way. (b)
  removes the only thing the boundary would add, a token in reach after repo code.

### What a step boundary does not stop

Measured against what a GitHub-hosted runner allows, not assumed:

- The runner keeps a step's command files under `$RUNNER_TEMP/_runner_file_commands/`, named
  per step; unsetting the variables hides the paths, not the directory.
- Processes a step starts in the background keep running until the job ends, so they can write
  a later step's command files or rewrite `org-github/` scripts and tools on disk.
- The `runner` user has password-less `sudo`, so repo code can read other processes' memory,
  including the runner's job token (read-only here: `contents: read`, `pull-requests: read`) and
  the artifact runtime token, and can change what the runner reports.

So D3 stops the accidental and the casual case (a task that appends to `$GITHUB_ENV`, a tool
that honours `GITHUB_OUTPUT`), and D2 removes any token a later step would carry, but neither is
a security boundary inside the job. The boundaries are the job edges: `gates` posts only on the
open release heads it re-lists itself, and `publish` takes its decisions from the caller's inputs
(D1) and re-derives the plan.

### Canonical script versus a shared action

- Options: (a) a reusable workflow or action that checks the caller's files; (b) a script copied
  into each repo.
- Decision: (b). The check must run in each repo's required CI job on the PR's own tree before
  the SHA moves, including a PR that moves the SHA; a reusable workflow at the old SHA would
  check the new shape with old rules. Byte-identical copies keep the review to one diff.

## Risks / Trade-offs

- [Release-head code still sets its own G2 status] → accepted; G2 stays `warn`; an owner
  ruleset on `release-please--*` is the fix (owner step, not in this change).
- [`compute` can still forge `action`/`compute-ok` on a real run] → `publish` already treats the
  plan as untrusted and refuses anything it cannot re-derive (`cascade-receive` "Publish
  verifies before it mints"); unchanged.
- [Four extra API calls per receiver run for the releases] → one paged list per upstream, well
  inside the hourly limit of `GITHUB_TOKEN`.
- [A copy drifts from the canonical script] → review at each pin bump (D5); a drifted copy still
  only checks shapes, it holds no secret.
- [The canonical check refuses today's callers] → intended: each repo applies the caller edit in
  the same PR that moves its pin and copies the script (Migration Plan).

## Migration Plan

1. Merge this change; take its squash SHA (README "Pinning and bumps", step 1).
2. Canary (step 2, with the `cascade-publish` rule): in one receiver, one PR that moves every
   cascade reference to the SHA, copies `wiring-check.sh`, adds `.tasks/cascade/wiring-check.yaml`,
   and makes the two caller edits in `deps-cascade.yml`:
   - `publish` `if:`: insert `&& inputs.gates_only != true` after `&& inputs.dry_run != true`;
   - the `Publish` step's `with:`: add `gates-only: ${{ inputs.gates_only == true }}` after
     `dry-run`.
3. The other repos follow after the canary's first live publish; core takes only the copy, the
   config and the SHA (it has no receiver).
4. Rollback: revert that repo's pin PR (SHA, script copy, config and caller edit together). The
   old `cascade-publish` would only warn about the extra `gates-only` input, but the old script
   copy refuses it, so the four go back as one.

## Open Questions

- None for the owner. The ruleset on `release-please--*` (owner decision 22 keeps settings with
  the owner) would turn the G2 residual into a closed gap; it is listed, not assumed.

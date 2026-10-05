# cascade-workflows Specification

## Purpose
Rules every release-cascade reusable workflow and composite action in `.github` follows: action
pinning, explicit permissions, untrusted-input handling, where the shared scripts come from, and
how the `opm-cascade` App token is minted and used.

## Requirements

### Requirement: Hardened workflow shape

`cascade-receive.yml` and `cascade-gates.yml` SHALL be callable only through `workflow_call`;
`cascade-notify` and `cascade-publish` SHALL be composite actions under `.github/actions/`. Every
job SHALL declare `permissions:` explicitly. Every third-party `uses:` SHALL be pinned to a full
commit SHA with the version in a comment. No `run:` block SHALL contain a `${{ }}` expression;
every context value SHALL reach a script through `env:`. No reusable workflow SHALL declare a
`secrets:` input, read a secret or declare an Environment, because a reusable-workflow job sees
the caller's Environment variables but not its Environment secrets unless the caller passes
`secrets: inherit` (sandbox cycle E1). The App key SHALL be read only as the `cascade`
Environment secret `CASCADE_APP_PRIVATE_KEY`, by the caller's own job that declares
`environment: cascade`, and passed to the composite action as its `private-key` input; no caller
SHALL pass `secrets:` or `secrets: inherit` to a reusable cascade workflow.

#### Scenario: Inline expression rejected

- **WHEN** a `run:` block in one of the three workflows contains `${{`
- **THEN** the offline wiring suite fails

#### Scenario: Caller passes no secrets

- **WHEN** an upstream's own `Notify downstream` job declares `environment: cascade` and runs the
  `cascade-notify` action with `private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}`
- **THEN** the action mints the App token from the caller repo's `cascade` Environment, and no
  reusable workflow receives a secret

#### Scenario: Reusable job does not see the Environment secret

- **WHEN** a reusable-workflow job declares `environment: cascade` and its caller passes no `secrets:`
- **THEN** `secrets.CASCADE_APP_PRIVATE_KEY` is empty in that job, so no reusable cascade workflow mints the token

### Requirement: Repo name from GITHUB_REPOSITORY

Every job SHALL derive the repo name once, in its first step, from `GITHUB_REPOSITORY`, and SHALL
fail when the owner part is not exactly `open-platform-model` or the name part is empty. Every
later use of the repo name SHALL read that step's output; `github.event.repository.name` SHALL
NOT be used.

#### Scenario: Foreign owner

- **WHEN** `GITHUB_REPOSITORY` is `someone-else/core`
- **THEN** the first step fails and no later step runs

### Requirement: Scripts come from the pinned .github commit

Callers SHALL reference `cascade-notify`, `cascade-publish`, `cascade-receive.yml` and
`cascade-gates.yml` by the full 40-character SHA of a commit on `open-platform-model/.github`
`main` (owner decision 24 for the actions, extended by the supervisor to the reusable workflows),
never by a branch or tag, and one repo SHALL use one SHA in all its cascade references. The scripts SHALL run at that same commit, with no input naming another
`.github` ref: the composite actions SHALL run them from their own directory
(`GITHUB_ACTION_PATH`) and SHALL NOT check out `open-platform-model/.github`; each
`cascade-receive.yml` job that needs them SHALL check out `open-platform-model/.github` to
`org-github` with `persist-credentials: false`, at the ref its `Own commit` step wrote, after
that step has checked that `job.workflow_repository` is `open-platform-model/.github` and
`job.workflow_sha` is a full 40-character SHA, and failed otherwise. The repo-name derivation
(`Guard`) SHALL be written inline in the workflow or action and run before any script.

#### Scenario: A pinned action runs its own commit's code

- **WHEN** opm-operator, with `sha_pinning_required` on, runs `cascade-publish@<sha>`
- **THEN** the action's scripts come from `<sha>`, not from `.github` `main`

#### Scenario: The receive workflow checks its scripts out at its own SHA

- **WHEN** `cascade-sandbox-down` calls `cascade-receive.yml@<sha>`
- **THEN** both jobs check out `open-platform-model/.github` at `<sha>`

#### Scenario: Unknown own commit

- **WHEN** `job.workflow_sha` is empty or not a full SHA
- **THEN** the job fails in its `Own commit` step instead of checking out the default branch

### Requirement: App token minting

The App token SHALL be minted only inside the `cascade-notify` or `cascade-publish` composite
action, run by a caller job that declares `environment: cascade`, as the step directly before its
first use and after every check that could still stop the job, from the `client-id` and
`private-key` inputs the caller fills with `vars.CASCADE_APP_CLIENT_ID` and
`secrets.CASCADE_APP_PRIVATE_KEY`, with `owner:
open-platform-model` and a non-empty `repositories` list. The step before the mint SHALL fail when
that list is empty. Notify's token SHALL be scoped to its targets with `permission-contents:
write` only; publish's token SHALL be scoped to the calling repo with `permission-contents:
write`, `permission-pull-requests: write` and `permission-issues: write`. The token SHALL NOT be
passed between jobs, written to a file, placed on a command line or kept past its job; git SHALL
receive it as a masked `http.https://github.com/.extraheader` value through `GIT_CONFIG_COUNT`,
`GIT_CONFIG_KEY_0` and `GIT_CONFIG_VALUE_0`.

#### Scenario: Empty repository list

- **WHEN** the repository list computed for the mint is empty
- **THEN** the job fails before the mint step and no token exists

#### Scenario: Branch run cannot reach the key

- **WHEN** a job that declares `environment: cascade` runs from a ref other than `main`
- **THEN** GitHub refuses the deployment before any step runs and no token is minted

### Requirement: Repo code never holds a token

Every command that runs code from the calling repo (its cascade tasks, its `pins.sh`, and the G2
task in a release-head worktree) SHALL run with `GH_TOKEN`, `GITHUB_TOKEN`, the read-token
variable and every `GIT_CONFIG_*` header variable unset. It SHALL also run with `GITHUB_ENV`,
`GITHUB_PATH`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`, `GITHUB_STATE` and every exported
`ACTIONS_*` variable unset, so repo code inherits no path to a runner command file. A git read of
the calling repo that needs credentials SHALL receive the `GITHUB_TOKEN` header through
`GIT_CONFIG_*` only for that one git call, never written to `.git/config`, a file, `GITHUB_ENV`
or a step output. In `compute`, every read that needs `GITHUB_TOKEN` (the release-PR list, the
release heads' fetch, the cascade PR, the branch tips and the upstream releases for the breaking
check) SHALL happen in steps that run before the first step that runs repo code, and no step
from that one on SHALL be given `GITHUB_TOKEN`, a secret or any other token. Steps are no
boundary inside a job (repo code can reach the runner's files, the checkout actions' post steps
and, with `sudo`, the job's read-only token and the artifact runtime token), so the outputs,
summary, artifacts and Actions cache entries `compute` writes after that point SHALL be treated
as untrusted by every later job.

#### Scenario: Task sees no token

- **WHEN** `compute` runs `task -x deps:cascade` in a run where `GITHUB_TOKEN` is available to the job
- **THEN** the task's environment holds neither `GH_TOKEN` nor `GITHUB_TOKEN` nor an authorization header

#### Scenario: Task cannot write the step's outputs or environment

- **WHEN** a repo's `deps:cascade` task, or a release head's task under G2, appends `action=push` to `$GITHUB_OUTPUT` and a variable to `$GITHUB_ENV`
- **THEN** both variables are unset in the task's environment and the step's output and environment files are unchanged

#### Scenario: No token after repo code

- **WHEN** `cascade-receive.yml` is read
- **THEN** the `Read gates` and `Read state` steps are the only `compute` steps given `GITHUB_TOKEN`, and both come before `Gates`, `Run the task` and `Body, title and labels`

#### Scenario: Breaking check without a token

- **WHEN** `Body, title and labels` runs the breaking check for a moved pin
- **THEN** it reads the upstream releases fetched by `Read state` and makes no API call

### Requirement: No Actions cache from repo code reaches a publish job

No step of `cascade-receive.yml`, `cascade-gates.yml`, `cascade-notify` or `cascade-publish` SHALL
save or restore an Actions cache: `compute` SHALL install Go with `cache: false`, and none of them
SHALL use a cache action or a `type=gha` build cache. Repo code that runs on `main` can write the
cache of `main`'s scope (through a cache step that saves after it ran, or with the artifact
runtime token it can read), so every product repo's publish workflows SHALL restore no cache
either; the wiring check enforces that in each repo.

#### Scenario: compute's Go install

- **WHEN** a receiver calls `cascade-receive.yml` with `setup-go: true`
- **THEN** the `Set up Go` step passes `cache: false`, so its post step saves no module or build cache after the repo's task ran

### Requirement: Compute installs pinned, checksummed tools

`cascade-receive.yml`'s `compute` job SHALL install Task and CUE with
`wiring/install-tools.sh` from the `.github` checkout, before any repo code runs: each archive
from a fixed GitHub release URL over HTTPS only, checked with `sha256sum` against a table in that
script (Task v3.53.1; CUE per `cue-version`, v0.17.1 today), and SHALL fail when the checksum
differs, when the requested `cue-version` has no table entry (exit 2), or when the runner is not
Linux x64. No version range (such as `3.x`) SHALL be installed. `setup-go` stays SHA-pinned with
`cache: false`.

#### Scenario: Unknown CUE version

- **WHEN** a caller passes `cue-version: v0.18.0`, which the table lacks
- **THEN** the `compute` job fails at the install step, before any repo code runs

#### Scenario: Tampered archive

- **WHEN** the downloaded Task archive's sha256 differs from the table
- **THEN** the install step fails and nothing is added to `PATH`

### Requirement: This repo's own workflows are least privilege

Every workflow file of `open-platform-model/.github` SHALL declare top-level `permissions:`, and
every `uses:` in them SHALL name a full commit SHA with a version comment. `.github/CODEOWNERS`
SHALL name the code owners of `/.github/`.

#### Scenario: Mention-guard pinned

- **WHEN** the wiring suite's static cases read `mention-guard.yml`
- **THEN** its `actions/github-script` reference is a full SHA with a `# v7` comment

### Requirement: Rollout order for a new pin

The README's "Pinning and bumps" steps SHALL state the order in which the product repos move to a
new `.github` SHA (owner decision 37). One receiver SHALL take the new pin as a dry run and pass
the dry-run checks. A change that touches neither `cascade-publish` nor `cascade-notify` has no
canary: all five repos MAY move together, live or dry, with the dry-run checks in one receiver
after its pin PR has merged. For a change that touches `cascade-publish` and not `cascade-notify`:
while every receiver is dry-run (`CASCADE_DRY_RUN` is not `false`, in any letter case, in any
receiver), all five repos MAY move together, the canary is the first receiver set live (the
Phase 4 canary), and every other receiver SHALL stay dry until the canary's first live publish
run on the new pin has succeeded; once any receiver is live, the canary SHALL be one live
receiver, and every other receiver, live or dry, SHALL stay on the old pin until that run has
succeeded. For a change that touches `cascade-notify`, which has no dry run, one repo SHALL move
first as the canary and every other repo SHALL stay on the old pin until the canary's first live
notify run on the new pin has succeeded, whether every receiver is dry or not. The README SHALL
NOT offer turning notify off with `CASCADE_NOTIFY` as a rollout step.

#### Scenario: All receivers dry, publish changed

- **WHEN** a `.github` change touches `cascade-publish` but not `cascade-notify`, and every receiver has `CASCADE_DRY_RUN` unset or `true`
- **THEN** the README allows all five repos to move to the new pin together, with the dry-run checks in one receiver after its merge, and keeps every receiver but the Phase 4 canary dry until the canary's first live publish on the new pin has succeeded

#### Scenario: One receiver already live, publish changed

- **WHEN** a `.github` change touches `cascade-publish` but not `cascade-notify`, and one receiver has `CASCADE_DRY_RUN` set to `false`
- **THEN** the README makes one live receiver the canary and keeps every other receiver, live or dry, on its old pin until the canary's first live publish run on the new pin has succeeded

#### Scenario: Notify changed

- **WHEN** a `.github` change touches `cascade-notify`, whether every receiver is dry or not
- **THEN** the README moves one repo first as the canary and keeps every other repo on its old pin until the canary's first live notify run on the new pin has succeeded, and it does not ask any repo to set `CASCADE_NOTIFY` to `off`

#### Scenario: Change touches neither action

- **WHEN** a `.github` change touches only `.github/scripts/cascade/wiring-check.sh`, which neither action runs
- **THEN** the README lets all five repos move to the new pin together, live or dry, with the dry-run checks in one receiver after its merge

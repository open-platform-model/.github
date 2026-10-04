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
variable and every `GIT_CONFIG_*` header variable unset. A git read of the calling repo that
needs credentials SHALL receive the `GITHUB_TOKEN` header through `GIT_CONFIG_*` only for that
one git call, never written to `.git/config`, a file, `GITHUB_ENV` or a step output.

#### Scenario: Task sees no token

- **WHEN** `compute` runs `task -x deps:cascade` in a run where `GITHUB_TOKEN` is available to the job
- **THEN** the task's environment holds neither `GH_TOKEN` nor `GITHUB_TOKEN` nor an authorization header

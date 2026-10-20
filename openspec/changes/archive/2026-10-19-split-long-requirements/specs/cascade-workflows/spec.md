## MODIFIED Requirements

### Requirement: No Actions cache from repo code reaches a publish job

No step of `cascade-receive.yml`, `cascade-gates.yml`, `cascade-notify` or `cascade-publish` SHALL save or restore an Actions cache: `compute` SHALL install Go with `cache: false`, and none of them SHALL use a cache action or a `type=gha` build cache.

#### Scenario: compute's Go install

- **WHEN** a receiver calls `cascade-receive.yml` with `setup-go: true`
- **THEN** the `Set up Go` step passes `cache: false`, so its post step saves no module or build cache after the repo's task ran

### Requirement: Compute installs pinned, checksummed tools

`cascade-receive.yml`'s `compute` job SHALL install Task and CUE with `wiring/install-tools.sh` from the `.github` checkout, before any repo code runs: each archive from a fixed GitHub release URL over HTTPS only, checked with `sha256sum` against a table in that script (Task v3.53.1; CUE per `cue-version`, v0.17.1 today), and SHALL fail when the checksum differs, when the requested `cue-version` has no table entry (exit 2), or when the runner is not Linux x64.

#### Scenario: Unknown CUE version

- **WHEN** a caller passes `cue-version: v0.18.0`, which the table lacks
- **THEN** the `compute` job fails at the install step, before any repo code runs

#### Scenario: Tampered archive

- **WHEN** the downloaded Task archive's sha256 differs from the table
- **THEN** the install step fails and nothing is added to `PATH`

### Requirement: Daily mirror drift check

`cascade-mirror-drift.yml` (job `Mirror drift`) SHALL read, from the `main` of catalog_opm, library, opm-operator and cli, every file whose sha256 `mirror_sources` records, and SHALL fail, with an error annotation naming the receiver, the path and both hashes, when one differs, and with one naming the receiver and path when a file cannot be read; it SHALL check every file before it exits. It SHALL never be a required check.

#### Scenario: A receiver changed its classes

- **WHEN** cli's `main` holds a `.tasks/cascade/classes` the mirror was not written from
- **THEN** the next daily run fails, naming cli, `.tasks/cascade/classes`, the sha256 found and the recorded one

#### Scenario: Every mirror current

- **WHEN** every recorded file on every receiver's `main` has its recorded sha256
- **THEN** the run passes and prints one `ok` line per file, fourteen in all (each receiver's `pins.sh`, `classes` and `cascade.sh`, and library's and opm-operator's `lib.sh`)

#### Scenario: A file cannot be read

- **WHEN** the request for one file fails
- **THEN** the run fails naming that file and still reports every other file

## REMOVED Requirements

### Requirement: Hardened workflow shape
**Reason**: Split into requirements that each state one behavior.
**Migration**: See "Cascade workflows and actions have a fixed shape", "Run blocks take context values through env", "Reusable cascade workflows hold no secret" and "The App key is read only by the caller's own job".

### Requirement: Scripts come from the pinned .github commit
**Reason**: Split into requirements that each state one behavior.
**Migration**: See "Callers pin the cascade by full SHA", "The composite actions run their scripts from their own directory", "The receive workflow checks the scripts out at its own commit" and "The repo-name derivation runs inline before any script".

### Requirement: App token minting
**Reason**: Split into requirements that each state one behavior.
**Migration**: See "The App token is minted after every check that could stop the job", "The mint uses a fixed owner and a non-empty repository list", "The App token has a fixed scope" and "The App token is neither passed nor persisted".

### Requirement: Repo code never holds a token
**Reason**: Split into requirements that each state one behavior.
**Migration**: See "Repo code runs with no token variable", "Repo code runs with no runner command file path", "A credentialed git read gets the header for one call", "Compute reads with the token before repo code runs" and "Compute output written after repo code is untrusted".

### Requirement: Rollout order for a new pin
**Reason**: Split into requirements that each state one behavior.
**Migration**: See "The pinning reference states the rollout order", "The pinning reference defines when a change touches an action", "A change that touches neither action has no canary", "A publish-only change while every receiver is dry", "A publish-only change once a receiver is live", "A notify-only change moves one upstream first" and "A change that touches both actions follows both rules".

### Requirement: The renamed controller repo answers to both names
**Reason**: Split into three requirements that each state one behavior.
**Migration**: See "The renamed controller repo gets the same answers", "A target list keeps the old repo name" and "same_repo treats the two names as one repo".

## ADDED Requirements

### Requirement: Cascade workflows and actions have a fixed shape

`cascade-receive.yml` and `cascade-gates.yml` SHALL be callable only through `workflow_call`; `cascade-notify` and `cascade-publish` SHALL be composite actions under `.github/actions/`. Every job SHALL declare `permissions:` explicitly. Every third-party `uses:` SHALL be pinned to a full commit SHA with the version in a comment.

#### Scenario: A workflow with no explicit permissions

- **WHEN** a job of `cascade-receive.yml` or `cascade-gates.yml` declares no `permissions:`
- **THEN** that breaks the rule that every job SHALL declare `permissions:` explicitly

### Requirement: Run blocks take context values through env

No `run:` block SHALL contain a `${{ }}` expression; every context value SHALL reach a script through `env:`.

#### Scenario: Inline expression rejected

- **WHEN** a `run:` block in one of the three workflows contains `${{`
- **THEN** the offline wiring suite fails

### Requirement: Reusable cascade workflows hold no secret

No reusable workflow SHALL declare a `secrets:` input, read a secret or declare an Environment, because a reusable-workflow job sees the caller's Environment variables but not its Environment secrets unless the caller passes `secrets: inherit` (sandbox cycle E1).

#### Scenario: Reusable job does not see the Environment secret

- **WHEN** a reusable-workflow job declares `environment: cascade` and its caller passes no `secrets:`
- **THEN** `secrets.CASCADE_APP_PRIVATE_KEY` is empty in that job, so no reusable cascade workflow mints the token

### Requirement: The App key is read only by the caller's own job

The App key SHALL be read only as the `cascade` Environment secret `CASCADE_APP_PRIVATE_KEY`, by the caller's own job that declares `environment: cascade`, and passed to the composite action as its `private-key` input; no caller SHALL pass `secrets:` or `secrets: inherit` to a reusable cascade workflow.

#### Scenario: Caller passes no secrets

- **WHEN** an upstream's own `Notify downstream` job declares `environment: cascade` and runs the
  `cascade-notify` action with `private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}`
- **THEN** the action mints the App token from the caller repo's `cascade` Environment, and no
  reusable workflow receives a secret

#### Scenario: Caller passes secrets: inherit

- **WHEN** a caller passes `secrets: inherit` to a reusable cascade workflow
- **THEN** that caller breaks the rule that no caller SHALL pass `secrets:` or `secrets: inherit` to a reusable cascade workflow

### Requirement: Callers pin the cascade by full SHA

Callers SHALL reference `cascade-notify`, `cascade-publish`, `cascade-receive.yml` and `cascade-gates.yml` by the full 40-character SHA of a commit on `open-platform-model/.github` `main` (owner decision 24 for the actions, extended by the supervisor to the reusable workflows), never by a branch or tag, and one repo SHALL use one SHA in all its cascade references.

#### Scenario: Reference by a branch

- **WHEN** a caller references `cascade-publish` by a branch or tag
- **THEN** that caller breaks the rule that callers SHALL reference it by the full 40-character SHA of a commit on `open-platform-model/.github` `main`, never by a branch or tag

### Requirement: The composite actions run their scripts from their own directory

The scripts SHALL run at that same commit, with no input naming another `.github` ref: the composite actions SHALL run them from their own directory (`GITHUB_ACTION_PATH`) and SHALL NOT check out `open-platform-model/.github`. The commit is that of "Callers pin the cascade by full SHA".

#### Scenario: A pinned action runs its own commit's code

- **WHEN** opm-operator, with `sha_pinning_required` on, runs `cascade-publish@<sha>`
- **THEN** the action's scripts come from `<sha>`, not from `.github` `main`

### Requirement: The receive workflow checks the scripts out at its own commit

The scripts SHALL run at that same commit, with no input naming another `.github` ref; each `cascade-receive.yml` job that needs them SHALL check out `open-platform-model/.github` to `org-github` with `persist-credentials: false`, at the ref its `Own commit` step wrote, after that step has checked that `job.workflow_repository` is `open-platform-model/.github` and `job.workflow_sha` is a full 40-character SHA, and failed otherwise. The commit is that of "Callers pin the cascade by full SHA".

#### Scenario: The receive workflow checks its scripts out at its own SHA

- **WHEN** `cascade-sandbox-down` calls `cascade-receive.yml@<sha>`
- **THEN** both jobs check out `open-platform-model/.github` at `<sha>`

#### Scenario: Unknown own commit

- **WHEN** `job.workflow_sha` is empty or not a full SHA
- **THEN** the job fails in its `Own commit` step instead of checking out the default branch

### Requirement: The repo-name derivation runs inline before any script

The repo-name derivation (`Guard`) SHALL be written inline in the workflow or action and run before any script.

#### Scenario: Guard before the scripts

- **WHEN** a workflow or action runs a script
- **THEN** the repo-name derivation (`Guard`) has run before it, written inline in the workflow or action

### Requirement: The App token is minted after every check that could stop the job

The App token SHALL be minted only inside the `cascade-notify` or `cascade-publish` composite action, run by a caller job that declares `environment: cascade`, as the step directly before its first use and after every check that could still stop the job.

#### Scenario: Branch run cannot reach the key

- **WHEN** a job that declares `environment: cascade` runs from a ref other than `main`
- **THEN** GitHub refuses the deployment before any step runs and no token is minted

### Requirement: The mint uses a fixed owner and a non-empty repository list

The App token SHALL be minted from the `client-id` and `private-key` inputs the caller fills with `vars.CASCADE_APP_CLIENT_ID` and `secrets.CASCADE_APP_PRIVATE_KEY`, with `owner: open-platform-model` and a non-empty `repositories` list. The step before the mint SHALL fail when that list is empty.

#### Scenario: Empty repository list

- **WHEN** the repository list computed for the mint is empty
- **THEN** the job fails before the mint step and no token exists

### Requirement: The App token has a fixed scope

Notify's token SHALL be scoped to its targets with `permission-contents: write` only; publish's token SHALL be scoped to the calling repo with `permission-contents: write`, `permission-pull-requests: write` and `permission-issues: write`.

#### Scenario: Notify token scope

- **WHEN** the `cascade-notify` action mints the App token
- **THEN** the token is scoped to its targets with `permission-contents: write` only

#### Scenario: Publish token scope

- **WHEN** the `cascade-publish` action mints the App token
- **THEN** the token is scoped to the calling repo with `permission-contents: write`, `permission-pull-requests: write` and `permission-issues: write`

### Requirement: The App token is neither passed nor persisted

The App token SHALL NOT be passed between jobs, written to a file, placed on a command line or kept past its job; git SHALL receive it as a masked `http.https://github.com/.extraheader` value through `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_0` and `GIT_CONFIG_VALUE_0`.

#### Scenario: Token handed to another job

- **WHEN** a job passes the token to another job, writes it to a file or places it on a command line
- **THEN** that job breaks the rule that the token SHALL NOT be passed between jobs, written to a file, placed on a command line or kept past its job

#### Scenario: Git receives the token as a header

- **WHEN** git needs the token
- **THEN** git receives it as a masked `http.https://github.com/.extraheader` value through `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_0` and `GIT_CONFIG_VALUE_0`

### Requirement: Repo code runs with no token variable

Every command that runs code from the calling repo (its cascade tasks, its `pins.sh`, and the G2 task in a release-head worktree) SHALL run with `GH_TOKEN`, `GITHUB_TOKEN`, the read-token variable and every `GIT_CONFIG_*` header variable unset.

#### Scenario: Task sees no token

- **WHEN** `compute` runs `task -x deps:cascade` in a run where `GITHUB_TOKEN` is available to the job
- **THEN** the task's environment holds neither `GH_TOKEN` nor `GITHUB_TOKEN` nor an authorization header

### Requirement: Repo code runs with no runner command file path

Every command that runs code from the calling repo (its cascade tasks, its `pins.sh`, and the G2 task in a release-head worktree) SHALL also run with `GITHUB_ENV`, `GITHUB_PATH`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`, `GITHUB_STATE` and every exported `ACTIONS_*` variable unset, so repo code inherits no path to a runner command file.

#### Scenario: Task cannot write the step's outputs or environment

- **WHEN** a repo's `deps:cascade` task, or a release head's task under G2, appends `action=push` to `$GITHUB_OUTPUT` and a variable to `$GITHUB_ENV`
- **THEN** both variables are unset in the task's environment and the step's output and environment files are unchanged

### Requirement: A credentialed git read gets the header for one call

A git read of the calling repo that needs credentials SHALL receive the `GITHUB_TOKEN` header through `GIT_CONFIG_*` only for that one git call, never written to `.git/config`, a file, `GITHUB_ENV` or a step output.

#### Scenario: Header for one git call only

- **WHEN** a git read of the calling repo that needs credentials runs
- **THEN** the `GITHUB_TOKEN` header comes through `GIT_CONFIG_*` for that one git call only and is never written to `.git/config`, a file, `GITHUB_ENV` or a step output

### Requirement: Compute reads with the token before repo code runs

In `compute`, every read that needs `GITHUB_TOKEN` (the release-PR list, the release heads' fetch, the cascade PR, the branch tips and the upstream releases for the breaking check) SHALL happen in steps that run before the first step that runs repo code, and no step from that one on SHALL be given `GITHUB_TOKEN`, a secret or any other token.

#### Scenario: No token after repo code

- **WHEN** `cascade-receive.yml` is read
- **THEN** the `Read gates` and `Read state` steps are the only `compute` steps given `GITHUB_TOKEN`, and both come before `Gates`, `Run the task` and `Body, title and labels`

#### Scenario: Breaking check without a token

- **WHEN** `Body, title and labels` runs the breaking check for a moved pin
- **THEN** it reads the upstream releases fetched by `Read state` and makes no API call

### Requirement: Compute output written after repo code is untrusted

Steps are no boundary inside a job (repo code can reach the runner's files, the checkout actions' post steps and, with `sudo`, the job's read-only token and the artifact runtime token), so the outputs, summary, artifacts and Actions cache entries `compute` writes after that point SHALL be treated as untrusted by every later job. That point is the first step that runs repo code, named in the requirement "Compute reads with the token before repo code runs".

#### Scenario: Output written after repo code

- **WHEN** `compute` writes an output, the summary, an artifact or an Actions cache entry after the first step that runs repo code
- **THEN** every later job treats it as untrusted

### Requirement: Mirror drift runs daily with a read-only token

`open-platform-model/.github` SHALL run a workflow, `cascade-mirror-drift.yml` (job `Mirror drift`), daily and on dispatch, with `contents: read` at the top level and on the job, no secret and only the run's own `GITHUB_TOKEN`, and a checkout without persisted credentials.

#### Scenario: Mirror drift permissions

- **WHEN** `cascade-mirror-drift.yml` is read
- **THEN** the workflow runs daily and on dispatch, has `contents: read` at the top level and on the job, holds no secret and only the run's own `GITHUB_TOKEN`, and checks out without persisted credentials

### Requirement: Product repos restore no cache in their publish workflows

Repo code that runs on `main` can write the cache of `main`'s scope (through a cache step that saves after it ran, or with the artifact runtime token it can read), so every product repo's publish workflows SHALL restore no cache either; the wiring check enforces that in each repo.

#### Scenario: Publish workflow restores a cache

- **WHEN** a product repo's publish workflow restores an Actions cache
- **THEN** the wiring check enforces the rule that every product repo's publish workflows SHALL restore no cache

### Requirement: Compute installs no version range

No version range (such as `3.x`) SHALL be installed. The install is that of the requirement "Compute installs pinned, checksummed tools".

#### Scenario: Version range

- **WHEN** the `compute` job is asked to install Task or CUE as a version range such as `3.x`
- **THEN** that breaks the rule that no version range SHALL be installed

### Requirement: Compute keeps setup-go SHA-pinned without a cache

`setup-go` SHALL stay SHA-pinned with `cache: false`.

#### Scenario: setup-go reference

- **WHEN** `cascade-receive.yml` is read
- **THEN** `setup-go` is SHA-pinned and passes `cache: false`

### Requirement: The pinning reference states the rollout order

The pinning reference (`references/cascade-pinning.md`) SHALL state the order in which the product repos move to a new `.github` SHA (owner decision 37). One receiver SHALL take the new pin as a dry run and pass the dry-run checks.

#### Scenario: Dry run first

- **WHEN** a product repo moves to a new `.github` SHA
- **THEN** one receiver takes the new pin as a dry run and passes the dry-run checks, in the order the pinning reference states

### Requirement: The pinning reference defines when a change touches an action

The pinning reference (`references/cascade-pinning.md`) SHALL define that a change touches an action when it changes any file that action runs: its `action.yml` and every script it calls or sources, directly or through another script, so a change to the resolver or its `lib/` touches `cascade-publish` and a change to `wiring/lib.sh` touches both actions.

#### Scenario: Resolver library changed

- **WHEN** a `.github` change touches only `.github/scripts/cascade/lib/common.sh`, which `cascade-publish` runs through `cascade-resolve.sh`
- **THEN** the pinning reference counts it as touching `cascade-publish`, not as touching neither action

### Requirement: A change that touches neither action has no canary

A change that touches neither `cascade-publish` nor `cascade-notify` SHALL have no canary: all five repos MAY move together, live or dry, with the dry-run checks in one receiver after its pin PR has merged.

#### Scenario: Change touches neither action

- **WHEN** a `.github` change touches only `.github/scripts/cascade/wiring-check.sh`, which neither action runs
- **THEN** the pinning reference lets all five repos move to the new pin together, live or dry, with the dry-run checks in one receiver after its merge

### Requirement: A publish-only change while every receiver is dry

For a change that touches `cascade-publish` and not `cascade-notify`: while every receiver is dry-run (`CASCADE_DRY_RUN` is not `false`, in any letter case, in any receiver), all five repos MAY move together, the canary is the Phase 4 canary (the first receiver whose `CASCADE_DRY_RUN` is set to `false`), and every other receiver SHALL stay dry until the canary's first live publish run on the new pin has succeeded.

#### Scenario: All receivers dry, publish changed

- **WHEN** a `.github` change touches `cascade-publish` but not `cascade-notify`, and every receiver has `CASCADE_DRY_RUN` unset or `true`
- **THEN** the pinning reference allows all five repos to move to the new pin together, with the dry-run checks in one receiver after its merge, and keeps every receiver but the Phase 4 canary dry until the canary's first live publish on the new pin has succeeded

### Requirement: A publish-only change once a receiver is live

For a change that touches `cascade-publish` and not `cascade-notify`: once any receiver is live, the canary SHALL be one live receiver, and every other receiver, live or dry, SHALL stay on the old pin until that run has succeeded. That run is the one of "A publish-only change while every receiver is dry".

#### Scenario: One receiver already live, publish changed

- **WHEN** a `.github` change touches `cascade-publish` but not `cascade-notify`, and one receiver has `CASCADE_DRY_RUN` set to `false`
- **THEN** the pinning reference makes one live receiver the canary and keeps every other receiver, live or dry, on its old pin until the canary's first live publish run on the new pin has succeeded

### Requirement: A notify-only change moves one upstream first

For a change that touches `cascade-notify` and not `cascade-publish`, which has no dry run, one upstream (core or a receiver) SHALL move first as the canary and every other repo SHALL stay on the old pin until the canary's first live notify run on the new pin has succeeded, whether every receiver is dry or not. The pinning reference (`references/cascade-pinning.md`) SHALL NOT offer turning notify off with `CASCADE_NOTIFY` as a rollout step.

#### Scenario: Notify changed

- **WHEN** a `.github` change touches `cascade-notify` but not `cascade-publish`, whether every receiver is dry or not
- **THEN** the pinning reference moves one upstream (core or a receiver) first as the canary and keeps every other repo on its old pin until the canary's first live notify run on the new pin has succeeded, and it does not ask any repo to set `CASCADE_NOTIFY` to `off`

### Requirement: A change that touches both actions follows both rules

A change that touches both actions SHALL follow the notify rule and the publish rule together: once any receiver is live, the canary SHALL be a live receiver, and no other repo SHALL move until both its first live publish run and its first live notify run on the new pin have succeeded. The rules are in the requirements "A notify-only change moves one upstream first", "A publish-only change while every receiver is dry" and "A publish-only change once a receiver is live".

#### Scenario: Both actions changed, one receiver live

- **WHEN** a `.github` change touches both `cascade-publish` and `cascade-notify`, and one receiver has `CASCADE_DRY_RUN` set to `false`
- **THEN** the pinning reference makes a live receiver the canary and keeps every other repo on its old pin until both the canary's first live publish run and its first live notify run on the new pin have succeeded

### Requirement: The renamed controller repo gets the same answers

While the repo `opm-operator` is renamed `opm-controller`, every fixed map in `wiring/lib.sh` keyed by a receiver or a source SHALL give `opm-operator` and `opm-controller` the same answer (`expect_pair` differing only in the repo name it prints), so a run of the renamed repo works at a pinned `.github` commit on both sides of the GitHub rename.

#### Scenario: The renamed repo as a receiver

- **WHEN** `receiver_sources`, `g3_upstreams`, `publish_paths`, `receiver_classes` and `mirror_sources` are asked for `opm-controller`
- **THEN** each prints what it prints for `opm-operator`

### Requirement: A target list keeps the old repo name

While the repo `opm-operator` is renamed `opm-controller`, a value that names a repo GitHub must find (the target lists of `notify_targets`, which set the App token's `repositories:`, and the upstreams G3 reads through the API) SHALL keep `opm-operator` only.

#### Scenario: A target list keeps the old name

- **WHEN** `notify_targets library` runs
- **THEN** it prints `opm-operator cli`, not `opm-controller`

### Requirement: same_repo treats the two names as one repo

While the repo `opm-operator` is renamed `opm-controller`, `same_repo <a> <b>` SHALL exit 0 for two equal names and for the pair `opm-operator`, `opm-controller`, and 1 otherwise.

#### Scenario: Two names, one repo

- **WHEN** `same_repo opm-controller opm-operator` and `same_repo opm-operator cli` run
- **THEN** the first exits 0 and the second exits 1

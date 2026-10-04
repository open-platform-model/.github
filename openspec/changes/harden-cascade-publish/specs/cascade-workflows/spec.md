## MODIFIED Requirements

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

## ADDED Requirements

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

## MODIFIED Requirements

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

- **WHEN** opm-controller, with `sha_pinning_required` on, runs `cascade-publish@<sha>`
- **THEN** the action's scripts come from `<sha>`, not from `.github` `main`

#### Scenario: The receive workflow checks its scripts out at its own SHA

- **WHEN** `cascade-sandbox-down` calls `cascade-receive.yml@<sha>`
- **THEN** both jobs check out `open-platform-model/.github` at `<sha>`

#### Scenario: Unknown own commit

- **WHEN** `job.workflow_sha` is empty or not a full SHA
- **THEN** the job fails in its `Own commit` step instead of checking out the default branch

### Requirement: Daily mirror drift check

`open-platform-model/.github` SHALL run a workflow, `cascade-mirror-drift.yml` (job
`Mirror drift`), daily and on dispatch, with `contents: read` at the top level and on the job,
no secret and only the run's own `GITHUB_TOKEN`, and a checkout without persisted credentials.
It SHALL read, from the `main` of catalog_opm, library, opm-controller and cli, every file whose
sha256 `mirror_sources` records, and SHALL fail, with an error annotation naming the receiver,
the path and both hashes, when one differs, and with one naming the receiver and path when a
file cannot be read; it SHALL check every file before it exits. It SHALL never be a required
check.

#### Scenario: A receiver changed its classes

- **WHEN** cli's `main` holds a `.tasks/cascade/classes` the mirror was not written from
- **THEN** the next daily run fails, naming cli, `.tasks/cascade/classes`, the sha256 found and the recorded one

#### Scenario: Every mirror current

- **WHEN** every recorded file on every receiver's `main` has its recorded sha256
- **THEN** the run passes and prints one `ok` line per file, fourteen in all (each receiver's `pins.sh`, `classes` and `cascade.sh`, and library's and opm-controller's `lib.sh`)

#### Scenario: A file cannot be read

- **WHEN** the request for one file fails
- **THEN** the run fails naming that file and still reports every other file

## REMOVED Requirements

### Requirement: The renamed controller repo answers to both names

**Reason**: The rename of opm-operator to opm-controller is done, and every receiver's and source's
own rename has merged; the maps name `opm-controller` only.

**Migration**: none; a caller still pinned to the earlier `.github` commit keeps running that
commit's code until its pin moves.

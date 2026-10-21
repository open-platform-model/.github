## MODIFIED Requirements

### Requirement: Daily mirror drift check

`cascade-mirror-drift.yml` (job `Mirror drift`) SHALL read, from the `main` of catalog_opm, library, opm-controller and cli, every file whose sha256 `mirror_sources` records, and SHALL fail, with an error annotation naming the receiver, the path and both hashes, when one differs, and with one naming the receiver and path when a file cannot be read; it SHALL check every file before it exits. It SHALL never be a required check.

#### Scenario: A receiver changed its classes

- **WHEN** cli's `main` holds a `.tasks/cascade/classes` the mirror was not written from
- **THEN** the next daily run fails, naming cli, `.tasks/cascade/classes`, the sha256 found and the recorded one

#### Scenario: Every mirror current

- **WHEN** every recorded file on every receiver's `main` has its recorded sha256
- **THEN** the run passes and prints one `ok` line per file, fourteen in all (each receiver's `pins.sh`, `classes` and `cascade.sh`, and library's and opm-controller's `lib.sh`)

#### Scenario: A file cannot be read

- **WHEN** the request for one file fails
- **THEN** the run fails naming that file and still reports every other file

### Requirement: The composite actions run their scripts from their own directory

The scripts SHALL run at that same commit, with no input naming another `.github` ref: the composite actions SHALL run them from their own directory (`GITHUB_ACTION_PATH`) and SHALL NOT check out `open-platform-model/.github`. The commit is that of "Callers pin the cascade by full SHA".

#### Scenario: A pinned action runs its own commit's code

- **WHEN** opm-controller, with `sha_pinning_required` on, runs `cascade-publish@<sha>`
- **THEN** the action's scripts come from `<sha>`, not from `.github` `main`

## REMOVED Requirements

### Requirement: The renamed controller repo gets the same answers

**Reason**: The rename of opm-operator to opm-controller is done and every receiver's and source's own rename has merged; the maps name `opm-controller` only.

**Migration**: none; a caller still pinned to the earlier `.github` commit keeps running that commit's code until its pin moves.

### Requirement: A target list keeps the old repo name

**Reason**: The rename of opm-operator to opm-controller is done and every receiver's and source's own rename has merged; the maps name `opm-controller` only.

**Migration**: none; a caller still pinned to the earlier `.github` commit keeps running that commit's code until its pin moves.

### Requirement: same_repo treats the two names as one repo

**Reason**: The rename of opm-operator to opm-controller is done and every receiver's and source's own rename has merged; the maps name `opm-controller` only.

**Migration**: none; a caller still pinned to the earlier `.github` commit keeps running that commit's code until its pin moves.

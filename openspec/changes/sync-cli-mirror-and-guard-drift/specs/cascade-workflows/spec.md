## ADDED Requirements

### Requirement: Daily mirror drift check

`open-platform-model/.github` SHALL run a workflow, `cascade-mirror-drift.yml` (job
`Mirror drift`), daily and on dispatch, with `contents: read` at the top level and on the job,
no secret and only the run's own `GITHUB_TOKEN`, and a checkout without persisted credentials.
It SHALL read, from the `main` of catalog_opm, library, opm-operator and cli, every file whose
sha256 `mirror_sources` records, and SHALL fail, with an error annotation naming the receiver,
the path and both hashes, when one differs, and with one naming the receiver and path when a
file cannot be read; it SHALL check every file before it exits. It SHALL never be a required
check.

#### Scenario: A receiver changed its classes

- **WHEN** cli's `main` holds a `.tasks/cascade/classes` the mirror was not written from
- **THEN** the next daily run fails, naming cli, `.tasks/cascade/classes`, the sha256 found and the recorded one

#### Scenario: Every mirror current

- **WHEN** every recorded file on every receiver's `main` has its recorded sha256
- **THEN** the run passes and prints one `ok` line per file

#### Scenario: A file cannot be read

- **WHEN** the request for one file fails
- **THEN** the run fails naming that file and still reports every other file

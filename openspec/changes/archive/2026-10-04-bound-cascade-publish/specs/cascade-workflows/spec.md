## ADDED Requirements

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

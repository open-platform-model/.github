## ADDED Requirements

### Requirement: The release key needs the release Environment

In every workflow file, the wiring check SHALL treat as a release-key reader every job any of
whose strings is an expression (a `${{ }}` in a string, or a whole `if:`) naming
`secrets.RELEASE_APP_PRIVATE_KEY` without regard to case or spaces, and every job with
`secrets: inherit`. Each reader SHALL declare `environment: release` as that exact string, and
every job whose Environment is `release` in any case (a string or a map's `name`) SHALL be a
reader. A mismatch SHALL print `release key readers without environment: release` or
`environment: release on jobs that do not read the release key` and exit 1. The rule needs no
config key.

#### Scenario: Release job without the Environment

- **WHEN** `release.yml`'s `release-please` job passes `${{ secrets.RELEASE_APP_PRIVATE_KEY }}` to `create-github-app-token` and declares no Environment
- **THEN** the check exits 1 naming `release.yml:release-please`

#### Scenario: The key in lower case

- **WHEN** a job reads `${{ secrets.release_app_private_key }}` and declares `environment: release`
- **THEN** that job passes the rule

#### Scenario: The Environment on a job that does not read the key

- **WHEN** a job declares `environment: Release` and reads no release key
- **THEN** the check exits 1 naming that job

#### Scenario: Inherited secrets

- **WHEN** a job calls a reusable workflow with `secrets: inherit`
- **THEN** the check exits 1, since such a job cannot declare an Environment

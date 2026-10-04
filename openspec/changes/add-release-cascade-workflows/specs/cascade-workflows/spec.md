## Purpose

Rules every reusable release-cascade workflow in `.github` follows: action pinning, explicit
permissions, untrusted-input handling, where the shared scripts come from, and how the
`opm-cascade` App token is minted and used.

## ADDED Requirements

### Requirement: Hardened workflow shape

`cascade-notify.yml`, `cascade-receive.yml` and `cascade-gates.yml` SHALL be callable only through
`workflow_call`. Every job SHALL declare `permissions:` explicitly. Every third-party `uses:` SHALL
be pinned to a full commit SHA with the version in a comment. No `run:` block SHALL contain a
`${{ }}` expression; every context value SHALL reach a script through `env:`. No reusable
workflow SHALL declare a `secrets:` input; the App key SHALL be read only as the `cascade`
Environment secret `CASCADE_APP_PRIVATE_KEY`, inside a job that declares `environment: cascade`.

#### Scenario: Inline expression rejected

- **WHEN** a `run:` block in one of the three workflows contains `${{`
- **THEN** the offline wiring suite fails

#### Scenario: Caller passes no secrets

- **WHEN** a repo calls `cascade-notify.yml` with no `secrets:` key
- **THEN** the notify job still mints the App token from the caller repo's `cascade` Environment

### Requirement: Repo name from GITHUB_REPOSITORY

Every job SHALL derive the repo name once, in its first step, from `GITHUB_REPOSITORY`, and SHALL
fail when the owner part is not exactly `open-platform-model` or the name part is empty. Every
later use of the repo name SHALL read that step's output; `github.event.repository.name` SHALL
NOT be used.

#### Scenario: Foreign owner

- **WHEN** `GITHUB_REPOSITORY` is `someone-else/core`
- **THEN** the first step fails and no later step runs

### Requirement: Scripts come from the org .github repo

Each job that needs the shared scripts or the resolver SHALL check out
`open-platform-model/.github` at the input `org-github-ref` (default `main`) to `org-github`, with
`persist-credentials: false`. The first step of every job SHALL fail with "org-github-ref may
differ from main only in a sandbox repo" when `org-github-ref` is not `main` and the calling repo
does not match `^open-platform-model/cascade-sandbox-`.

#### Scenario: Production repo with a branch ref

- **WHEN** `library` calls `cascade-receive.yml` with `org-github-ref: feat/x`
- **THEN** every job fails in its first step with the message above

#### Scenario: Sandbox repo with a branch ref

- **WHEN** `cascade-sandbox-down` calls `cascade-receive.yml` with `org-github-ref: feat/x`
- **THEN** the scripts and the resolver are checked out from `feat/x`

### Requirement: App token minting

The App token SHALL be minted only in a job that declares `environment: cascade`, as the step
directly before its first use and after every check that could still stop the job, from
`vars.CASCADE_APP_CLIENT_ID` and `secrets.CASCADE_APP_PRIVATE_KEY`, with `owner:
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

# cascade-wiring-check Specification

## Purpose
The release-cascade wiring check (workspace RELEASING.md, section "Two-job split"): the one
script, kept in `.github` and copied byte for byte into the five product repos, that holds each
repo's cascade caller workflows to the shapes the `.github` README documents; its per-repo
config; how a repo keeps its copy in step with its pin; and the online check that the pin is on
`.github` `main`.

## Requirements

### Requirement: Canonical wiring check

`.github/scripts/cascade/wiring-check.sh` SHALL be the one wiring check of the five product repos.
Run from a repo root as `wiring-check.sh [--pin-on-main] [<config>]` (default
`.tasks/cascade/wiring-check.yaml`)
with mikefarah `yq` v4, it SHALL compare the repo's cascade caller workflows with the caller
shapes the README of the same `.github` commit documents, print every mismatch on stderr, and
exit 1 when there was one; on success it SHALL print
`cascade wiring: ok, .github <sha> (<pin comment>)` and exit 0. A missing tool, a missing
config or a bad config SHALL exit 2. It SHALL check:

- no workflow file uses a YAML anchor or alias, merge keys included;
- the key-holding jobs `release.yml:notify-downstream` and (receivers) `deps-cascade.yml:publish`:
  exact job keys, name, step name, timeout, `environment: cascade`, `runs-on: ubuntu-latest`,
  permissions, one step at a full-SHA cascade action with exact `with` keys, the client id and
  key expressions; notify's `needs`, `if:` and `tag` against the config; publish's `needs`,
  `if:` (with `inputs.gates_only != true`), `dry-run`, `gates-only` and `labels-managed`;
- `release.yml`'s workflow `env`: a map, or absent, whose keys are all in the config's
  `env-allow`;
- for a receiver, the `deps-cascade.yml` and `cascade-gates.yml` triggers, top-level and job
  permissions, job keys, concurrency group and the reusable calls' inputs;
- in every workflow file: the App key read only by the key-holding jobs, where a reader is any
  expression (a `${{ }}` in a string, or a whole `if:`) that names the key without regard to
  case or uses the secrets context other than as `secrets.<name>` (`secrets[…]` with any index,
  `secrets.*`, or the whole context given to a function such as `toJSON(secrets)`); the cascade
  Environment, named in any case or as an expression, only on those jobs; no call into
  `.github`, matched without regard to case, passing `secrets:`;
- in every workflow the config's `publish-workflows` lists: no action whose name contains
  `cache`, `actions/setup-go` only with `cache: false`, `actions/setup-node` only with
  `package-manager-cache: false` and no `cache`, no other input whose name contains `cache`
  except `no-cache`, and no string containing `type=gha`;
- every `.github` reference, matched without regard to case, at one full SHA with the config's
  pin comment;
- the CI job the config names runs exactly the step `bash .tasks/cascade/wiring-check.sh
  --pin-on-main` with only `env: {GH_TOKEN: ${{ github.token }}}` besides its name, on every
  pull request (no path filter, no `if:`, no `continue-on-error`, no `shell` or
  `working-directory` on the step or in `defaults.run`).

#### Scenario: A variant spelling of the key

- **WHEN** a job other than the two key-holding jobs reads `secrets['cascade_app_private_key']` or `toJSON( secrets )`
- **THEN** the check names that file and path and exits 1

#### Scenario: An aliased Environment and a computed secret name

- **WHEN** a new job declares `environment: *e` (an alias of the notify job's `&e cascade`) and reads `secrets[format('CASCADE_APP_{0}', 'PRIVATE_KEY')]`
- **THEN** the check refuses the alias and names the reader, and exits 1

#### Scenario: A mixed-case call into .github

- **WHEN** a CI workflow calls `Open-Platform-Model/.github/.github/workflows/cascade-receive.yml@main` with `secrets: inherit`
- **THEN** the check reports the call passing secrets and the unexpected reference, and exits 1

#### Scenario: A publish workflow restores a cache

- **WHEN** a workflow listed in `publish-workflows` runs `actions/setup-go` without `cache: false`, or a build with `cache-from: type=gha`
- **THEN** the check names the step and exits 1

#### Scenario: A gates-only publish

- **WHEN** a receiver's `publish` `if:` lacks `inputs.gates_only != true`, or its step lacks the `gates-only` input
- **THEN** the check exits 1

#### Scenario: Current callers after the caller edit

- **WHEN** the check runs on any of the five product repos' workflows with that repo's config, after the `harden-cascade-publish` follow-up edits (the receiver caller edit, the CI step, no cache in the publish workflows)
- **THEN** it prints `cascade wiring: ok` and exits 0

### Requirement: Per-repo wiring config

Each product repo's values SHALL live in `.tasks/cascade/wiring-check.yaml`, read as data and
never sourced, with exactly the keys `pin-comment` (words), `receiver` (boolean), `env-allow`
(list of upper-case variable names), `publish-workflows` (list of workflow file names, including
`release.yml`), `ci` (`workflow`, `job`), `notify` (`needs`, `if`, `tag`), for a receiver
only, `publish` (`labels-managed`, boolean), and optionally `extra-references` (a list of maps
with exactly the keys `file`, a workflow file name, and `kind`, whose only value is `resolver`).
The check SHALL refuse, as a config error, an unknown key, a wrong type, a `publish-workflows`
list without `release.yml`, an `extra-references` item with another key, file name or kind, and an
`env-allow` entry that is not `CUE_*`, `OPM_*`, `REGISTRY` or `IMAGE_NAME`: the names are allowed
rather than denied, because too many variables make a shell, git, gh, node, curl or the dynamic
loader run code, read other config or redirect traffic (`BASH_ENV`, `GIT_*`, `GH_*`, `NODE_*`,
`LD_*`, `XDG_*`, `SSL_*`, `CURL_*`, `*_PROXY` and more).

#### Scenario: Allow-list widened to a code-running variable

- **WHEN** a repo adds `BASH_ENV` to `env-allow` and to `release.yml`'s `env`
- **THEN** the check exits 2 naming the entry

#### Scenario: Allow-list widened to a proxy or a git hook directory

- **WHEN** a repo adds `HTTPS_PROXY` or `GIT_TEMPLATE_DIR` to `env-allow`
- **THEN** the check exits 2 naming the entry

#### Scenario: An extra reference of an unknown kind

- **WHEN** a repo lists `extra-references: [{file: module-deps.yml, kind: action}]`, or an item with a third key, or a `file` with a path
- **THEN** the check exits 2 naming the item

### Requirement: The pin is on .github main

With `--pin-on-main`, after every shape matched, the check SHALL ask
`gh api repos/open-platform-model/.github/compare/<sha>...main --jq .status` (with `GH_TOKEN`)
and SHALL exit 1 unless it prints `identical` or `ahead`, so a commit GitHub resolves under the
`.github` name but that exists only in a fork (an imposter commit) is refused. A failed API call
SHALL exit 1. Without the flag the check SHALL make no request. The required CI step SHALL pass
the flag.

#### Scenario: A fork-only SHA

- **WHEN** every `.github` reference names a commit that exists only in a fork of `.github`, so the compare status is `behind` or `diverged`
- **THEN** the CI step exits 1 naming the SHA and the status

### Requirement: Byte-identical copies

Each product repo SHALL keep the script at `.tasks/cascade/wiring-check.sh` byte-identical to
`.github/scripts/cascade/wiring-check.sh` at the `.github` SHA its cascade references pin, and
SHALL replace it in the same PR that moves the pin. The README SHALL give the command that
fetches the copy at a SHA and the command that compares it. With `--pin-on-main`, after the pin
was found on `.github` `main`, the check SHALL fetch that file at the pinned SHA
(`gh api -H 'Accept: application/vnd.github.raw'
repos/open-platform-model/.github/contents/.github/scripts/cascade/wiring-check.sh?ref=<sha>`)
and compare it byte for byte with the script file it is running; a difference SHALL print
`differs from .github/scripts/cascade/wiring-check.sh at .github <sha>` and exit 1, and a failed
request SHALL print `cannot fetch` and exit 1. Without the flag, the check SHALL print after its
ok line `cascade wiring: the copy was not compared with .github <sha> (offline; --pin-on-main
compares it)` and make no request.

#### Scenario: Pin bump

- **WHEN** a repo moves its cascade pin to a new `.github` SHA
- **THEN** the same PR replaces `.tasks/cascade/wiring-check.sh` with the file at that SHA, and `cmp` against it reports no difference

#### Scenario: A copy that drifted

- **WHEN** the CI step runs a copy that differs by one byte from the file at the pinned SHA
- **THEN** the check exits 1 naming the copy and the SHA

#### Scenario: Offline run

- **WHEN** `task cascade:wiring:check` runs the check without `--pin-on-main` on matching shapes
- **THEN** it prints the ok line and then that the copy was not compared, makes no request, and exits 0

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

### Requirement: Declared extra references

Each `extra-references` item SHALL add one expected `.github` reference of its kind in its file.
A `resolver` reference is a step whose `with.repository` is `open-platform-model/.github` in any
case. A declared reference SHALL be held to the rules of the fixed references: the one full SHA
shared by every `.github` reference and the config's pin comment. A reference neither fixed nor
declared, and a declared one that is missing, SHALL fail `.github references` with exit 1.

#### Scenario: opm-operator's module dependency bot

- **WHEN** opm-operator's config lists `extra-references: [{file: module-deps.yml, kind: resolver}]` and `module-deps.yml` checks out `.github` at the same SHA with `# .github main`
- **THEN** the check passes

#### Scenario: The extra reference at another SHA

- **WHEN** the declared `module-deps.yml` checkout names a different SHA from the other references
- **THEN** the check exits 1 with `one .github SHA`

#### Scenario: An undeclared second resolver

- **WHEN** a workflow checks out `.github` and the config does not declare it
- **THEN** the check exits 1 with `.github references`

### Requirement: Resolver checkouts pass no credentials

Every resolver checkout of `.github`, fixed or declared, SHALL use `actions/checkout` at a full
SHA with exactly the `with` keys `path`, `persist-credentials`, `ref` and `repository`, and
`persist-credentials` SHALL be the boolean `false`. Anything else SHALL fail with exit 1 naming
the file and step.

#### Scenario: A token on the resolver checkout

- **WHEN** a resolver checkout passes `token: ${{ secrets.GITHUB_TOKEN }}`
- **THEN** the check exits 1 naming that checkout

### Requirement: Nothing reaches the CI wiring step

In the CI workflow and job the config names, the wiring check SHALL refuse with exit 1: a
workflow or job `env` that is not absent or a plain map, or that names a variable outside `CUE_*`,
`OPM_*`, `REGISTRY` and `IMAGE_NAME`; a `container` or `services` on the job; and any step before
the wiring step that is not `uses:` of another repository's action at a full 40-hex SHA with only
the keys `id`, `name`, `uses` and `with`. With `--pin-on-main`, the check SHALL exit 1 before any
request when `BASH_ENV` or `ENV` is set.

#### Scenario: BASH_ENV in the CI job env

- **WHEN** the CI job sets `env: {BASH_ENV: ./x}`, or the CI workflow sets `CASCADE_GH`
- **THEN** the check exits 1 naming the env keys outside the allowed names

#### Scenario: A run step before the wiring step

- **WHEN** a `run:` step that writes to `$GITHUB_ENV` comes before the wiring step
- **THEN** the check exits 1 naming that step

#### Scenario: Pinned setup actions before the wiring step

- **WHEN** only `actions/checkout`, `actions/setup-go` and `go-task/setup-task` at full SHAs come before the wiring step, and `run:` steps follow it
- **THEN** that part of the check passes

### Requirement: Runbook for a failed API call

The README SHALL tell an admin what to do when the required wiring step fails because a GitHub API
request failed (`cannot compare` or `cannot fetch`): re-run the job; if the outage or rate limit
lasts, an admin MAY merge with admin bypass only a PR that changes nothing under `.github/**` or
`.tasks/**`, after every other required check passed; `--pin-on-main` SHALL never be removed from
the step. A `not on .github main` or `differs from` failure SHALL never be bypassed.

#### Scenario: GitHub API outage

- **WHEN** the wiring step fails with `cannot compare` on a PR that changes only Go code, and re-runs keep failing
- **THEN** the runbook allows an admin bypass merge once every other required check is green, and forbids it for a PR touching `.tasks/cascade/wiring-check.sh`

# cascade-wiring-check Specification

## Purpose
The release-cascade wiring check (workspace RELEASING.md, section "Two-job split"): the one
script, kept in `.github` and copied byte for byte into the five product repos, that holds each
repo's cascade caller workflows to the shapes the `.github` cascade reference files document; its per-repo
config; how a repo keeps its copy in step with its pin; and the online check that the pin is on
`.github` `main`.

## Requirements

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

### Requirement: Nothing reaches the CI wiring step

In the CI workflow and job the config names, the wiring check SHALL refuse with exit 1: a workflow or job `env` that is not absent or a plain map, or that names a variable outside `CUE_*`, `OPM_*`, `REGISTRY` and `IMAGE_NAME`; a `container` or `services` on the job; and any step before the wiring step that is not `uses:` of another repository's action at a full 40-hex SHA with only the keys `id`, `name`, `uses` and `with`.

#### Scenario: BASH_ENV in the CI job env

- **WHEN** the CI job sets `env: {BASH_ENV: ./x}`, or the CI workflow sets `CASCADE_GH`
- **THEN** the check exits 1 naming the env keys outside the allowed names

#### Scenario: A run step before the wiring step

- **WHEN** a `run:` step that writes to `$GITHUB_ENV` comes before the wiring step
- **THEN** the check exits 1 naming that step

#### Scenario: Pinned setup actions before the wiring step

- **WHEN** only `actions/checkout`, `actions/setup-go` and `go-task/setup-task` at full SHAs come before the wiring step, and `run:` steps follow it
- **THEN** that part of the check passes

### Requirement: A cite-lint call is a plain call

Every job whose `uses` is `cite-lint.yml` of `open-platform-model/.github` (any case), in any workflow file and declared or not, SHALL hold only the keys `name`, `permissions`, `uses` and `with`. Its `permissions` SHALL be the map `contents: read` exactly, and its `with` SHALL hold only `paths` and `exclude`. No string of the job SHALL name the `secrets` context, `secrets: inherit` included. Anything else SHALL fail with exit 1 naming the file and job.

#### Scenario: A declared call at the pin
- **WHEN** a repo declares `{file: ci.yml, kind: cite-lint}` and `ci.yml` holds a job with `permissions: {contents: read}` and `uses: .../cite-lint.yml@<the pinned SHA> # <pin comment>`
- **THEN** the check passes, on core too

#### Scenario: A call that holds a write scope or a secret
- **WHEN** the calling job sets `contents: write`, adds another permission, omits `permissions`, sets `secrets: inherit` or passes `${{ secrets.X }}` in an input
- **THEN** the check exits 1 with `cite-lint.yml calls that break the plain-call rule`

#### Scenario: A call that sets the enh pin
- **WHEN** the call passes `enh-ref`
- **THEN** the check exits 1 with `cite-lint.yml calls that break the plain-call rule`

#### Scenario: A call at another SHA or without the comment
- **WHEN** the call names a SHA that differs from the other references, or lacks the pin comment
- **THEN** the check exits 1 with `one .github SHA` or `pin comment on`

### Requirement: A cite-lint call runs on a safe trigger

A workflow file that holds a job calling `cite-lint.yml` SHALL NOT trigger on `pull_request_target` or `workflow_run`, in a map, list or string form of `on`, because those events run in the base repository context. The check SHALL fail with exit 1 naming the file and trigger.

#### Scenario: A base-context trigger
- **WHEN** the file with the call also triggers on `pull_request_target`
- **THEN** the check exits 1 with `cite-lint.yml calls that break the plain-call rule`

### Requirement: The canonical wiring check is one script

`.github/scripts/cascade/wiring-check.sh` SHALL be the one wiring check of the five product repos. A missing tool, a missing config or a bad config SHALL exit 2.

#### Scenario: A missing config

- **WHEN** `wiring-check.sh` runs in a repo whose config is missing
- **THEN** it exits 2

### Requirement: The wiring check compares the callers with the documented shapes

Run from a repo root as `wiring-check.sh [--pin-on-main] [<config>]` (default `.tasks/cascade/wiring-check.yaml`) with mikefarah `yq` v4, it SHALL compare the repo's cascade caller workflows with the caller shapes the cascade reference files of the same `.github` commit document (`references/cascade-workflows.md` for the caller shapes), print every mismatch on stderr, and exit 1 when there was one; on success it SHALL print `cascade wiring: ok, .github <sha> (<pin comment>)` and exit 0.

#### Scenario: Current callers after the caller edit

- **WHEN** the check runs on any of the five product repos' workflows with that repo's config, after the `harden-cascade-publish` follow-up edits (the receiver caller edit, the CI step, no cache in the publish workflows)
- **THEN** it prints `cascade wiring: ok` and exits 0

### Requirement: The wiring check refuses YAML anchors and aliases

`.github/scripts/cascade/wiring-check.sh` SHALL check: no workflow file uses a YAML anchor or alias, merge keys included.

#### Scenario: A merge key

- **WHEN** a workflow file uses a merge key `<<`
- **THEN** the check reports it, because no workflow file may use a YAML anchor or alias, merge keys included

### Requirement: Key-holding jobs have a fixed shape

`.github/scripts/cascade/wiring-check.sh` SHALL check: the key-holding jobs `release.yml:notify-downstream` and (receivers) `deps-cascade.yml:publish`: exact job keys, name, step name, timeout, `environment: cascade`, `runs-on: ubuntu-latest`, permissions, one step at a full-SHA cascade action with exact `with` keys, the client id and key expressions.

#### Scenario: A key-holding job with another timeout

- **WHEN** the `notify-downstream` job of `release.yml` has a timeout other than the exact one
- **THEN** the check reports the mismatch

### Requirement: Key-holding jobs match the config

`.github/scripts/cascade/wiring-check.sh` SHALL check: the key-holding jobs `release.yml:notify-downstream` and (receivers) `deps-cascade.yml:publish`: notify's `needs`, `if:` and `tag` against the config; publish's `needs`, `if:` (with `inputs.gates_only != true`), `dry-run`, `gates-only` and `labels-managed`.

#### Scenario: A gates-only publish

- **WHEN** a receiver's `publish` `if:` lacks `inputs.gates_only != true`, or its step lacks the `gates-only` input
- **THEN** the check exits 1

### Requirement: The wiring check limits the workflow env of release.yml

`.github/scripts/cascade/wiring-check.sh` SHALL check: `release.yml`'s workflow `env`: a map, or absent, whose keys are all in the config's `env-allow`.

#### Scenario: Env key outside the allow-list

- **WHEN** `release.yml`'s workflow `env` holds a key that is not in the config's `env-allow`
- **THEN** the check reports it

### Requirement: The wiring check holds a receiver's workflows to a fixed shape

`.github/scripts/cascade/wiring-check.sh` SHALL check: for a receiver, the `deps-cascade.yml` and `cascade-gates.yml` triggers, top-level and job permissions, job keys, concurrency group and the reusable calls' inputs.

#### Scenario: A receiver trigger that differs

- **WHEN** a receiver's `deps-cascade.yml` has a trigger other than the documented one
- **THEN** the check reports the mismatch

### Requirement: The App key is read only by the key-holding jobs

`.github/scripts/cascade/wiring-check.sh` SHALL check: in every workflow file: the App key read only by the key-holding jobs, where a reader is any expression (a `${{ }}` in a string, or a whole `if:`) that names the key without regard to case or uses the secrets context other than as `secrets.<name>` (`secrets[…]` with any index, `secrets.*`, or the whole context given to a function such as `toJSON(secrets)`). The key-holding jobs are named in "Key-holding jobs have a fixed shape".

#### Scenario: A variant spelling of the key

- **WHEN** a job other than the two key-holding jobs reads `secrets['cascade_app_private_key']` or `toJSON( secrets )`
- **THEN** the check names that file and path and exits 1

### Requirement: The cascade Environment is declared only on the key-holding jobs

`.github/scripts/cascade/wiring-check.sh` SHALL check: in every workflow file: the cascade Environment, named in any case or as an expression, only on those jobs. Those jobs are the key-holding jobs of "Key-holding jobs have a fixed shape".

#### Scenario: An aliased Environment and a computed secret name

- **WHEN** a new job declares `environment: *e` (an alias of the notify job's `&e cascade`) and reads `secrets[format('CASCADE_APP_{0}', 'PRIVATE_KEY')]`
- **THEN** the check refuses the alias and names the reader, and exits 1

### Requirement: No call into .github passes secrets

`.github/scripts/cascade/wiring-check.sh` SHALL check: in every workflow file: no call into `.github`, matched without regard to case, passing `secrets:`.

#### Scenario: A mixed-case call into .github

- **WHEN** a CI workflow calls `Open-Platform-Model/.github/.github/workflows/cascade-receive.yml@main` with `secrets: inherit`
- **THEN** the check reports the call passing secrets and the unexpected reference, and exits 1

### Requirement: Publish workflows use no Actions cache

`.github/scripts/cascade/wiring-check.sh` SHALL check: in every workflow the config's `publish-workflows` lists: no action whose name contains `cache`, `actions/setup-go` only with `cache: false`, `actions/setup-node` only with `package-manager-cache: false` and no `cache`, no other input whose name contains `cache` except `no-cache`, and no string containing `type=gha`.

#### Scenario: A publish workflow restores a cache

- **WHEN** a workflow listed in `publish-workflows` runs `actions/setup-go` without `cache: false`, or a build with `cache-from: type=gha`
- **THEN** the check names the step and exits 1

### Requirement: Every .github reference is at one full SHA with the pin comment

`.github/scripts/cascade/wiring-check.sh` SHALL check: every `.github` reference, matched without regard to case, at one full SHA with the config's pin comment.

#### Scenario: References at two SHAs

- **WHEN** two `.github` references of a repo name different SHAs
- **THEN** the check reports it, because every `.github` reference SHALL be at one full SHA with the config's pin comment

### Requirement: The CI job runs exactly the wiring step

`.github/scripts/cascade/wiring-check.sh` SHALL check: the CI job the config names runs exactly the step `bash .tasks/cascade/wiring-check.sh --pin-on-main` with only `env: {GH_TOKEN: ${{ github.token }}}` besides its name, on every pull request (no path filter, no `if:`, no `continue-on-error`, no `shell` or `working-directory` on the step or in `defaults.run`).

#### Scenario: A path filter on the CI job

- **WHEN** the CI workflow the config names has a path filter
- **THEN** the check reports it, because the CI job SHALL run on every pull request

### Requirement: The wiring config holds exactly the documented keys

Each product repo's values SHALL live in `.tasks/cascade/wiring-check.yaml`, read as data and never sourced, with exactly the keys named in the scenario "The config keys".

#### Scenario: The config keys

- **WHEN** a product repo's `.tasks/cascade/wiring-check.yaml` is read
- **THEN** it holds exactly the keys `pin-comment` (words), `receiver` (boolean), `env-allow` (list of upper-case variable names), `publish-workflows` (list of workflow file names, including `release.yml`), `ci` (`workflow`, `job`), `notify` (`needs`, `if`, `tag`), for a receiver only, `publish` (`labels-managed`, boolean), and optionally `extra-references` (a list of maps with exactly the keys `file`, a workflow file name, and `kind`, whose value is `resolver` or `cite-lint`)

### Requirement: The wiring check refuses an unknown key, a wrong type or a publish-workflows list without release.yml

The check SHALL refuse, as a config error, an unknown key, a wrong type, a `publish-workflows` list without `release.yml`.

#### Scenario: An unknown config key

- **WHEN** a repo adds a key that is not one of the documented keys to `.tasks/cascade/wiring-check.yaml`
- **THEN** the check refuses it as a config error

### Requirement: The wiring check refuses a bad extra-references item

The check SHALL refuse, as a config error, an `extra-references` item with another key, file name or kind, a `resolver` item on a non-receiver, naming the same file and kind twice, or naming `release.yml`, `deps-cascade.yml`, `cascade-gates.yml` or `cascade-task.yml` (files that hold a fixed reference).

#### Scenario: An extra reference of an unknown kind

- **WHEN** a repo lists `extra-references: [{file: module-deps.yml, kind: action}]`, or an item with a third key, or a `file` with a path
- **THEN** the check exits 2 naming the item

#### Scenario: An extra reference beside a fixed one

- **WHEN** a receiver lists `{file: cascade-task.yml, kind: resolver}` or `{file: release.yml, kind: resolver}`, lists `module-deps.yml` twice, or core lists a `resolver` item
- **THEN** the check exits 2 naming the item

### Requirement: The wiring check allows only named env variables

The check SHALL refuse, as a config error, an `env-allow` entry that is not `CUE_*`, `OPM_*`, `REGISTRY` or `IMAGE_NAME`: the names are allowed rather than denied, because too many variables make a shell, git, gh, node, curl or the dynamic loader run code, read other config or redirect traffic (`BASH_ENV`, `GIT_*`, `GH_*`, `NODE_*`, `LD_*`, `XDG_*`, `SSL_*`, `CURL_*`, `*_PROXY` and more).

#### Scenario: Allow-list widened to a code-running variable

- **WHEN** a repo adds `BASH_ENV` to `env-allow` and to `release.yml`'s `env`
- **THEN** the check exits 2 naming the entry

#### Scenario: Allow-list widened to a proxy or a git hook directory

- **WHEN** a repo adds `HTTPS_PROXY` or `GIT_TEMPLATE_DIR` to `env-allow`
- **THEN** the check exits 2 naming the entry

### Requirement: Each product repo keeps a byte-identical copy of the wiring check

Each product repo SHALL keep the script at `.tasks/cascade/wiring-check.sh` byte-identical to `.github/scripts/cascade/wiring-check.sh` at the `.github` SHA its cascade references pin, and SHALL replace it in the same PR that moves the pin.

#### Scenario: Pin bump

- **WHEN** a repo moves its cascade pin to a new `.github` SHA
- **THEN** the same PR replaces `.tasks/cascade/wiring-check.sh` with the file at that SHA, and `cmp` against it reports no difference

### Requirement: The wiring-check reference gives the fetch and compare commands

The wiring-check reference (`references/cascade-wiring-check.md`) SHALL give the command that fetches the copy at a SHA and the command that compares it.

#### Scenario: Commands in the reference

- **WHEN** a product repo moves its cascade pin
- **THEN** the wiring-check reference gives the command that fetches the copy at a SHA and the command that compares it

### Requirement: The check compares the copy with the file at the pinned SHA

With `--pin-on-main`, after the pin was found on `.github` `main`, the check SHALL fetch that file at the pinned SHA (`gh api -H 'Accept: application/vnd.github.raw' repos/open-platform-model/.github/contents/.github/scripts/cascade/wiring-check.sh?ref=<sha>`) and compare it byte for byte with the script file it is running.

#### Scenario: A matching copy

- **WHEN** the CI step runs a copy that is byte-identical to the file at the pinned SHA
- **THEN** the check fetches that file and finds no difference

### Requirement: The check reports a copy that differs or cannot be fetched

With `--pin-on-main`, after the pin was found on `.github` `main`, a difference SHALL print `differs from .github/scripts/cascade/wiring-check.sh at .github <sha>` and exit 1, and a failed request SHALL print `cannot fetch` and exit 1.

#### Scenario: A copy that drifted

- **WHEN** the CI step runs a copy that differs by one byte from the file at the pinned SHA
- **THEN** the check exits 1 naming the copy and the SHA

#### Scenario: A failed fetch

- **WHEN** the request for the file at the pinned SHA fails
- **THEN** the check prints `cannot fetch` and exits 1

### Requirement: Without the flag the check does not compare the copy

Without `--pin-on-main`, the check SHALL print after its ok line `cascade wiring: the copy was not compared with .github <sha> (offline; --pin-on-main compares it)` and make no request.

#### Scenario: Offline run

- **WHEN** `task cascade:wiring:check` runs the check without `--pin-on-main` on matching shapes
- **THEN** it prints the ok line and then that the copy was not compared, makes no request, and exits 0

### Requirement: The wiring check finds the release-key readers and holds them to the release Environment

In every workflow file, the wiring check SHALL treat as a release-key reader every job any of whose strings is an expression (a `${{ }}` in a string, or a whole `if:`) naming `secrets.RELEASE_APP_PRIVATE_KEY` without regard to case or spaces, and every job with `secrets: inherit`. Each reader SHALL declare `environment: release` as that exact string, and every job whose Environment is `release` in any case (a string or a map's `name`) SHALL be a reader.

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

### Requirement: A release key mismatch prints a message and exits 1

A mismatch of the release-key readers and `environment: release` is the one named in the requirement "The wiring check finds the release-key readers and holds them to the release Environment". A mismatch SHALL print `release key readers without environment: release` or `environment: release on jobs that do not read the release key` and exit 1. The rule needs no config key.

#### Scenario: Mismatch message

- **WHEN** a job reads the release key and declares no `environment: release`
- **THEN** the check prints `release key readers without environment: release` and exits 1

### Requirement: A declared extra reference adds one expected reference

Each `extra-references` item SHALL add one expected `.github` reference of its kind in its file. A `resolver` reference SHALL be a step whose `with.repository` ends in `/.github` in any case, or is an expression. A `cite-lint` reference SHALL be a job whose `uses` is `open-platform-model/.github/.github/workflows/cite-lint.yml` at the pinned SHA.

#### Scenario: opm-operator's module dependency bot

- **WHEN** opm-operator's config lists `extra-references: [{file: module-deps.yml, kind: resolver}]` and `module-deps.yml` checks out `.github` at the same SHA with `# .github main`
- **THEN** the check passes

### Requirement: A declared reference follows the fixed rules

A declared reference SHALL be held to the rules of the fixed references: the one full SHA shared by every `.github` reference and the config's pin comment.

#### Scenario: The extra reference at another SHA

- **WHEN** the declared `module-deps.yml` checkout names a different SHA from the other references
- **THEN** the check exits 1 with `one .github SHA`

### Requirement: An undeclared or missing reference fails

A reference neither fixed nor declared, and a declared one that is missing, SHALL fail `.github references` with exit 1.

#### Scenario: An undeclared second resolver

- **WHEN** a workflow checks out `.github` and the config does not declare it
- **THEN** the check exits 1 with `.github references`

#### Scenario: A declared reference that is missing

- **WHEN** the config declares an `extra-references` item and its file holds no such reference
- **THEN** the check fails `.github references` with exit 1

### Requirement: A resolver checkout uses fixed inputs

Every resolver checkout of `.github`, fixed or declared, SHALL use `actions/checkout` at a full SHA with exactly the `with` keys `path`, `persist-credentials`, `ref` and `repository`, and `persist-credentials` SHALL be the boolean `false`. Anything else SHALL fail with exit 1 naming the file and step.

#### Scenario: A token on the resolver checkout

- **WHEN** a resolver checkout passes `token: ${{ secrets.GITHUB_TOKEN }}`
- **THEN** the check exits 1 naming that checkout

### Requirement: A step counts as a .github checkout by its repository input

A step counts as a `.github` checkout when its `with.repository` ends in `/.github` (any owner, any case) or contains `${{`. A step whose `repository` input is an expression, and a `run:` step that names `open-platform-model/.github` (or `}}` or `repository_owner` followed by `/.github`), SHALL fail with exit 1.

#### Scenario: A checkout through repository_owner

- **WHEN** `cascade-task.yml` gains `actions/checkout@v4` with `repository: ${{ github.repository_owner }}/.github`, `ref: main` and a token
- **THEN** the check exits 1 naming the expression, the checkout and the unexpected reference

#### Scenario: A clone in a run step

- **WHEN** a `run:` step runs `git clone https://github.com/open-platform-model/.github`
- **THEN** the check exits 1 naming that step

### Requirement: The wiring check exits before any request when BASH_ENV or ENV is set

With `--pin-on-main`, the check SHALL exit 1 before any request when `BASH_ENV` or `ENV` is set.

#### Scenario: ENV set with the flag

- **WHEN** `--pin-on-main` is given and `ENV` is set
- **THEN** the check exits 1 before any request

### Requirement: The runbook confirms the pinned SHA first

The wiring-check reference (`references/cascade-wiring-check.md`) SHALL tell an admin what to do when the required wiring step fails because a GitHub API request failed (`cannot compare` or `cannot fetch`): first confirm with `gh api repos/open-platform-model/.github/commits/<sha>` that GitHub knows the pinned SHA, since `cannot compare` is also printed for an unknown SHA, which is a finding and never an outage.

#### Scenario: Unknown SHA

- **WHEN** the wiring step fails with `cannot compare` and `gh api repos/open-platform-model/.github/commits/<sha>` returns 404
- **THEN** the runbook treats it as a pin to fix and allows no admin bypass

### Requirement: The runbook allows an admin bypass only for a PR outside .github and .tasks

The wiring-check reference (`references/cascade-wiring-check.md`) SHALL tell an admin what to do when the required wiring step fails because a GitHub API request failed (`cannot compare` or `cannot fetch`): re-run the job; if the outage or rate limit lasts, an admin MAY merge with admin bypass only a PR that changes nothing under `.github/**` or `.tasks/**`, after every other required check passed. For an unknown SHA see "The runbook confirms the pinned SHA first".

#### Scenario: GitHub API outage

- **WHEN** the wiring step fails with `cannot compare` on a PR that changes only Go code, and re-runs keep failing
- **THEN** the runbook allows an admin bypass merge once every other required check is green, and forbids it for a PR touching `.tasks/cascade/wiring-check.sh`

### Requirement: The runbook keeps the flag and never bypasses a pin failure

The wiring-check reference (`references/cascade-wiring-check.md`) SHALL tell an admin what to do when the required wiring step fails because a GitHub API request failed (`cannot compare` or `cannot fetch`): `--pin-on-main` SHALL never be removed from the step. A `not on .github main` or `differs from` failure SHALL never be bypassed.

#### Scenario: A pin failure is never bypassed

- **WHEN** the wiring step fails with `not on .github main` or `differs from`
- **THEN** the runbook allows no admin bypass

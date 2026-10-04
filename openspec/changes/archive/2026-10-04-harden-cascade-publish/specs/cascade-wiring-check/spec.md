## ADDED Requirements

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
`release.yml`), `ci` (`workflow`, `job`), `notify` (`needs`, `if`, `tag`) and, for a receiver
only, `publish` (`labels-managed`, boolean). The check SHALL refuse, as a config error, an
unknown key, a wrong type, a `publish-workflows` list without `release.yml`, and an `env-allow`
entry that is not `CUE_*`, `OPM_*`, `REGISTRY` or `IMAGE_NAME`: the names are allowed rather
than denied, because too many variables make a shell, git, gh, node, curl or the dynamic loader
run code, read other config or redirect traffic (`BASH_ENV`, `GIT_*`, `GH_*`, `NODE_*`, `LD_*`,
`XDG_*`, `SSL_*`, `CURL_*`, `*_PROXY` and more).

#### Scenario: Allow-list widened to a code-running variable

- **WHEN** a repo adds `BASH_ENV` to `env-allow` and to `release.yml`'s `env`
- **THEN** the check exits 2 naming the entry

#### Scenario: Allow-list widened to a proxy or a git hook directory

- **WHEN** a repo adds `HTTPS_PROXY` or `GIT_TEMPLATE_DIR` to `env-allow`
- **THEN** the check exits 2 naming the entry

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
fetches the copy at a SHA and the command that compares it.

#### Scenario: Pin bump

- **WHEN** a repo moves its cascade pin to a new `.github` SHA
- **THEN** the same PR replaces `.tasks/cascade/wiring-check.sh` with the file at that SHA, and `cmp` against it reports no difference

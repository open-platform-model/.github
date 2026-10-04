## ADDED Requirements

### Requirement: Canonical wiring check

`.github/scripts/cascade/wiring-check.sh` SHALL be the one wiring check of the five product repos.
Run from a repo root as `wiring-check.sh [<config>]` (default `.tasks/cascade/wiring-check.yaml`)
with mikefarah `yq` v4, it SHALL compare the repo's cascade caller workflows with the caller
shapes the README of the same `.github` commit documents, print every mismatch on stderr, and
exit 1 when there was one; on success it SHALL print
`cascade wiring: ok, .github <sha> (<pin comment>)` and exit 0. A missing tool, a missing
config or a bad config SHALL exit 2. It SHALL check:

- the key-holding jobs `release.yml:notify-downstream` and (receivers) `deps-cascade.yml:publish`:
  exact job keys, name, step name, timeout, `environment: cascade`, `runs-on: ubuntu-latest`,
  permissions, one step at a full-SHA cascade action with exact `with` keys, the client id and
  key expressions; notify's `needs`, `if:` and `tag` against the config; publish's `needs`,
  `if:` (with `inputs.gates_only != true`), `dry-run`, `gates-only` and `labels-managed`;
- `release.yml`'s workflow `env`: a map, or absent, whose keys are all in the config's
  `env-allow`;
- for a receiver, the `deps-cascade.yml` and `cascade-gates.yml` triggers, top-level and job
  permissions, job keys, concurrency group and the reusable calls' inputs;
- in every workflow file: the App key read only by the key-holding jobs, matched without regard
  to case and also as `secrets[…]` or `toJSON(secrets)`; the cascade Environment, named in any
  case or as an expression, only on those jobs; no call into `.github` passing `secrets:`;
- every `.github` reference at one full SHA with the config's pin comment;
- the CI job the config names runs `task cascade:wiring:check` as a plain step on every pull
  request (no path filter, no `if:`, no `continue-on-error`).

#### Scenario: A variant spelling of the key

- **WHEN** a job other than the two key-holding jobs reads `secrets['cascade_app_private_key']` or `toJSON( secrets )`
- **THEN** the check names that file and path and exits 1

#### Scenario: A gates-only publish

- **WHEN** a receiver's `publish` `if:` lacks `inputs.gates_only != true`, or its step lacks the `gates-only` input
- **THEN** the check exits 1

#### Scenario: Current callers after the caller edit

- **WHEN** the check runs on any of the five product repos' workflows with that repo's config, after the `harden-cascade-publish` caller edit
- **THEN** it prints `cascade wiring: ok` and exits 0

### Requirement: Per-repo wiring config

Each product repo's values SHALL live in `.tasks/cascade/wiring-check.yaml`, read as data and
never sourced, with exactly the keys `pin-comment` (words), `receiver` (boolean), `env-allow`
(list of upper-case variable names), `ci` (`workflow`, `job`), `notify` (`needs`, `if`, `tag`)
and, for a receiver only, `publish` (`labels-managed`, boolean). The check SHALL refuse, as a
config error, an unknown key, a wrong type, and an `env-allow` entry that names a variable which
makes a shell, node, git or the dynamic loader run code (for example `BASH_ENV`, `ENV`,
`NODE_OPTIONS`, `SHELLOPTS`, `PS4`, `LD_PRELOAD`, `PATH`) or any `GITHUB_*`, `ACTIONS_*`,
`RUNNER_*` or `CASCADE_*` name.

#### Scenario: Allow-list widened to a code-running variable

- **WHEN** a repo adds `BASH_ENV` to `env-allow` and to `release.yml`'s `env`
- **THEN** the check exits 2 naming the entry

### Requirement: Byte-identical copies

Each product repo SHALL keep the script at `.tasks/cascade/wiring-check.sh` byte-identical to
`.github/scripts/cascade/wiring-check.sh` at the `.github` SHA its cascade references pin, and
SHALL replace it in the same PR that moves the pin. The README SHALL give the command that
fetches the copy at a SHA and the command that compares it.

#### Scenario: Pin bump

- **WHEN** a repo moves its cascade pin to a new `.github` SHA
- **THEN** the same PR replaces `.tasks/cascade/wiring-check.sh` with the file at that SHA, and `cmp` against it reports no difference

## MODIFIED Requirements

### Requirement: Canonical wiring check

`.github/scripts/cascade/wiring-check.sh` SHALL be the one wiring check of the five product repos.
Run from a repo root as `wiring-check.sh [--pin-on-main] [<config>]` (default
`.tasks/cascade/wiring-check.yaml`)
with mikefarah `yq` v4, it SHALL compare the repo's cascade caller workflows with the caller
shapes the cascade reference files of the same `.github` commit document (`references/cascade-workflows.md` for the caller shapes), print every mismatch on stderr, and
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

### Requirement: Byte-identical copies

Each product repo SHALL keep the script at `.tasks/cascade/wiring-check.sh` byte-identical to
`.github/scripts/cascade/wiring-check.sh` at the `.github` SHA its cascade references pin, and
SHALL replace it in the same PR that moves the pin. The wiring-check reference (`references/cascade-wiring-check.md`) SHALL give the command that
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

### Requirement: Runbook for a failed API call

The wiring-check reference (`references/cascade-wiring-check.md`) SHALL tell an admin what to do when the required wiring step fails because a GitHub API
request failed (`cannot compare` or `cannot fetch`): first confirm with
`gh api repos/open-platform-model/.github/commits/<sha>` that GitHub knows the pinned SHA, since
`cannot compare` is also printed for an unknown SHA, which is a finding and never an outage;
re-run the job; if the outage or rate limit
lasts, an admin MAY merge with admin bypass only a PR that changes nothing under `.github/**` or
`.tasks/**`, after every other required check passed; `--pin-on-main` SHALL never be removed from
the step. A `not on .github main` or `differs from` failure SHALL never be bypassed.

#### Scenario: Unknown SHA

- **WHEN** the wiring step fails with `cannot compare` and `gh api repos/open-platform-model/.github/commits/<sha>` returns 404
- **THEN** the runbook treats it as a pin to fix and allows no admin bypass

#### Scenario: GitHub API outage

- **WHEN** the wiring step fails with `cannot compare` on a PR that changes only Go code, and re-runs keep failing
- **THEN** the runbook allows an admin bypass merge once every other required check is green, and forbids it for a PR touching `.tasks/cascade/wiring-check.sh`

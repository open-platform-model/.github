## Purpose

The canonical resolver stub the repo tasks test against, the resolver's offline test suite, and
the `.github` CI checks that run them. Source: Phase 2 cascade contract §2.10, §2.11 and §7, and
workspace RELEASING.md, section "Rulesets on main".

## ADDED Requirements

### Requirement: Canonical stub

`.github/scripts/cascade/stub-resolve.sh` SHALL be byte-identical to the stub text in the Phase 2
cascade contract §7, executable, with sha256
`970130f7d55c07f5b86d4f5b6f392330427ff923eb34f93553656bcd4b893d9c`. For every case the stub
supports, the stub and the real resolver in fixture mode SHALL agree on exit code and stdout,
excluding prerelease identifiers that mix numeric and alphanumeric forms, duplicate holds, holds
inside `newest`, and warning text.

#### Scenario: Checksum drift

- **WHEN** one byte of `stub-resolve.sh` changes
- **THEN** the offline suite fails naming the file and both checksums

#### Scenario: Agreement on a beta line

- **WHEN** the stub table and the fixtures both make `v2.0.0-beta.2` the newest published core above `v2.0.0-beta.1`
- **THEN** `newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1` prints `v2.0.0-beta.2` and exits 0 from both

### Requirement: Offline test suite

`.github/scripts/cascade/test/run.sh` SHALL run with no network access, print `PASS <case>` or
`FAIL <case>: <reason>` per case, and exit 0 when all pass and 1 otherwise. It SHALL put
`test/shim/` first on `PATH` and set `CASCADE_FIXTURE_DIR`; the resolver SHALL have no fixture
code path of its own. The `curl` shim SHALL accept only the resolver's curl shape (anything else
is exit 2), log its argument vector to `$CASCADE_FIXTURE_DIR/curl.log`, and answer from
`<dir>/http/<host>/<path>` (`?` written as `%3F`) with status from `<file>.status` (default 200
if the body exists, else 404; several lines consumed one per request, the last repeating) and
headers from `<file>.headers`. The `git` shim SHALL answer `ls-remote` from
`<dir>/git/<repo>.refs` and pass every other subcommand to the real `git`. Fixtures SHALL be
captured from real GHCR, proxy and git answers. The suite SHALL cover every case listed in the
Phase 2 cascade contract §2.10 and assert from `curl.log` that `-q` is always the first
argument.

#### Scenario: Runs without network

- **WHEN** `bash .github/scripts/cascade/test/run.sh` runs on a machine with no network
- **THEN** every case runs and the exit code reflects only the assertions

#### Scenario: A real curl call is caught

- **WHEN** resolver code calls `curl` with a flag outside the allowed shape
- **THEN** the shim exits 2 and the case fails

#### Scenario: Pagination limit

- **WHEN** the fixture for a GHCR tag list chains 21 pages through `Link` headers
- **THEN** the case asserts `newest` exits 1

### Requirement: Required CI check for .github

`.github/workflows/cascade-resolver.yml` SHALL run on every `pull_request` and on `push` to
`main` with no path filter, with `permissions: contents: read`, as one job named
`Resolver tests` with `timeout-minutes: 10`. It SHALL check out the repo with a SHA-pinned
`actions/checkout` and `persist-credentials: false`, confirm mikefarah `yq` v4, run `shellcheck`
on every `*.sh` under `.github/scripts/cascade` and on the two shims, run `actionlint` from a
pinned, checksum-verified release on `.github/workflows/*.yml`, and run the offline suite. It
MUST NOT change `mention-guard.yml` or `tag-ledger.yml`.

#### Scenario: Unrelated PR still reports

- **WHEN** a PR changes only `README.md`
- **THEN** `Resolver tests` runs and reports a status

#### Scenario: Failing test fails the check

- **WHEN** a case in the offline suite fails
- **THEN** the `Resolver tests` job fails

### Requirement: Live smoke workflow

`.github/workflows/cascade-resolver-live.yml` SHALL run on `workflow_dispatch` and on a weekly
schedule, never as a required check, with `permissions: contents: read`. It SHALL assert, against
the real services, that `newest cue opmodel.dev/core@v2 --current <the newest real version>`
exits 3, that the newest it finds is in-major and not a dev build, and that
`published opm-cli <newest cli>` exits 0.

#### Scenario: Live run on dispatch

- **WHEN** the owner dispatches the live workflow
- **THEN** it queries GHCR and GitHub anonymously and passes when the invariants hold

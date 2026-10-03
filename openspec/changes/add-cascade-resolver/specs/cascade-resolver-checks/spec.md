## Purpose

The canonical resolver stub the repo tasks test against, the resolver's offline test suite, and
the `.github` CI checks that run them. Source: Phase 2 cascade contract, version 1, §2.10, §2.11
and §7 (kept with this change as `contract.md`), and workspace RELEASING.md, section "Rulesets on
main".

## ADDED Requirements

### Requirement: Canonical stub

`.github/scripts/cascade/stub-resolve.sh` SHALL be executable and have sha256
`970130f7d55c07f5b86d4f5b6f392330427ff923eb34f93553656bcd4b893d9c`, the checksum of the stub text
the four repos copy into `.tasks/cascade/testdata/`. For every case the stub supports, the stub
and the real resolver in fixture mode SHALL agree on exit code and stdout. Excluded from the
agreement: prerelease identifiers that mix numeric and alphanumeric forms, duplicate holds, holds
inside `newest`, warning text, malformed arguments, malformed steering files, `next-patch` of a
prerelease, and `check-files` on an invalid file.

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
captured from real GHCR, proxy and git answers. Git in the tests SHALL ignore the caller's
global and system git config (`GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`) and use a
fixed author and committer, so a test gives the same result locally and on a bare runner. The
suite SHALL hide any `cue` binary from `PATH`. It SHALL cover at least:

- SemVer order: `alpha.2` < `alpha.10`, `beta.10` > `beta.2`, `v2.0.0` > `v2.0.0-beta.10`,
  `rc.1` > `beta.9`, `alpha.beta` > `alpha.1`, `alpha.1` < `alpha.a`, `alpha` < `alpha.1`, build
  metadata ignored; `semver-cmp` output and exit codes; `semver-sort`; `next-patch`;
- dev builds and pseudo-versions excluded; the major restriction with a v3 present and the
  new-major warning (prerelease and release); a proxy `v2/@v/list` 404 giving no warning;
- the stable-current rule with and without `--pre`;
- an unpublished newest keeping the pin; a skip to an older published candidate; three
  unpublished candidates (exit 3 with the warning); ten unpublished (exit 1); never backwards;
- holds: capping, expired, below current, duplicate, missing `reason`, bad `expires`;
- frozen: exact file, directory prefix, trailing `/`, `dir2` not matched by `dir`, a file entry
  not matched by its parent directory, malformed entries, empty files, verbatim copies of
  library's and cli's committed `.cascade-frozen`;
- `pin-of` from a captured modulefile, a dep followed by another dep, dep absent; `language-of`
  found and absent;
- GHCR token 403 and tags 404 (`newest` 1, `published` 3); `published oci` with both `Accept`
  types and the tag as given;
- 5xx then 200, four 5xx, a 429 retry; a relative-`Link` pagination walk and 21 pages;
- a draft or asset-less release skipped; a missing second asset;
- `--expect` published on the third poll, never published with a fake clock, above a hold and
  a prerelease against a stable current ignored;
- `-q` first in every `curl.log` line; no request to `api.github.com` and no token value sent;
  warning keys for `release` and `opm-cli`; the `--json` shape;
- `classify`, `title` and `body` against throwaway git repos: every pattern form and an invalid
  one, every title type and subject form, empty diff, untracked file, byte-identical reruns,
  `| none | - | - | - |`, a hostile tag, an unknown source, the lint failing on a planted bare
  mention, a mention in Notes passing through unchanged;
- the stub checksum and the stub-agreement cases.

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
on every `*.sh` under `.github/scripts` and on the two shims, run `actionlint` from a
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
the real services, read-only: `newest cue opmodel.dev/core@v2 --current v2.0.0-0` finds the
newest published core, which SHALL be in-major and not a dev build, and a second run with that
result as `--current` SHALL exit 3; `newest opm-cli --current v1.0.0-0` finds the newest cli,
for which `published opm-cli` SHALL exit 0, and a second run with it as `--current` SHALL exit
3.

#### Scenario: Live run on dispatch

- **WHEN** the owner dispatches the live workflow
- **THEN** it queries GHCR and GitHub anonymously and passes when the invariants hold

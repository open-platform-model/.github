## MODIFIED Requirements

### Requirement: Live smoke workflow

`.github/workflows/cascade-resolver-live.yml` SHALL run on `workflow_dispatch` and on a weekly schedule, never as a required check, with `permissions: contents: read`. It SHALL assert, against the real services, read-only: `newest cue opmodel.dev/core@v2 --current v2.0.0-0` finds the newest published core, which SHALL be in-major and not a dev build, and a second run with that result as `--current` SHALL exit 3.

#### Scenario: Live run on dispatch

- **WHEN** the owner dispatches the live workflow
- **THEN** it queries GHCR and GitHub anonymously and passes when the invariants hold

## REMOVED Requirements

### Requirement: Canonical stub
**Reason**: Split into two requirements that each state one behavior.
**Migration**: See "The canonical stub has a fixed checksum" and "The stub agrees with the real resolver".

### Requirement: Offline test suite
**Reason**: Split into requirements that each state one behavior; the list of cases the suite covers moves into the scenarios of "The offline suite covers the resolver".
**Migration**: See "The offline suite runs without network", "The offline suite puts shims first on PATH", "The curl shim answers from fixtures", "The git shim answers from fixtures", "Fixtures are captured from real answers", "Offline suite git ignores the caller's config" and "The offline suite covers the resolver".

### Requirement: Required CI check for .github
**Reason**: Split into requirements that each state one behavior.
**Migration**: See "Resolver tests run on every change", "Resolver tests set up pinned tools", "Resolver tests lint scripts and workflows", "Resolver tests run both offline suites" and "Resolver tests add no job and change no other workflow".

### Requirement: Offline wiring test suite
**Reason**: Split into requirements that each state one behavior; the list of cases the suite covers moves into the scenarios of "The wiring suite covers the cascade scripts".
**Migration**: See "The wiring suite runs offline with fakes", "The wiring suite uses the real resolver for offline subcommands only" and "The wiring suite covers the cascade scripts".

## ADDED Requirements

### Requirement: Live smoke workflow asserts the newest cli

The live smoke workflow SHALL assert, against the real services and read-only, that `newest opm-cli --current v1.0.0-0` finds the newest cli, for which `published opm-cli` SHALL exit 0, and that a second run with it as `--current` SHALL exit 3.

#### Scenario: Newest cli is stable

- **WHEN** the live workflow runs `newest opm-cli --current v1.0.0-0` and then runs it again with the answer as `--current`
- **THEN** `published opm-cli` exits 0 for the answer and the second run exits 3

### Requirement: The canonical stub has a fixed checksum

`.github/scripts/cascade/stub-resolve.sh` SHALL be executable and have sha256 `970130f7d55c07f5b86d4f5b6f392330427ff923eb34f93553656bcd4b893d9c`, the checksum of the stub text the four repos copy into `.tasks/cascade/testdata/`.

#### Scenario: Checksum drift

- **WHEN** one byte of `stub-resolve.sh` changes
- **THEN** the offline suite fails naming the file and both checksums

### Requirement: The stub agrees with the real resolver

For every case the stub supports, the stub and the real resolver in fixture mode SHALL agree on exit code and stdout. Excluded from the agreement: prerelease identifiers that mix numeric and alphanumeric forms, duplicate holds, holds inside `newest`, warning text, malformed arguments, malformed steering files, `next-patch` of a prerelease, and `check-files` on an invalid file.

#### Scenario: Agreement on a beta line

- **WHEN** the stub table and the fixtures both make `v2.0.0-beta.2` the newest published core above `v2.0.0-beta.1`
- **THEN** `newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1` prints `v2.0.0-beta.2` and exits 0 from both

### Requirement: The offline suite runs without network

`.github/scripts/cascade/test/run.sh` SHALL run with no network access, print `PASS <case>` or `FAIL <case>: <reason>` per case, and exit 0 when all pass and 1 otherwise. A case file name given on the command line that does not exist SHALL be a failure.

#### Scenario: Runs without network

- **WHEN** `bash .github/scripts/cascade/test/run.sh` runs on a machine with no network
- **THEN** every case runs and the exit code reflects only the assertions

### Requirement: The offline suite puts shims first on PATH

The suite SHALL put `test/shim/` first on `PATH` and set `CASCADE_FIXTURE_DIR`; the resolver SHALL have no fixture code path of its own. The suite SHALL put a `cue` that refuses to run first on `PATH`, so no case can depend on `cue`.

#### Scenario: A case that calls cue fails

- **WHEN** a case runs code that needs `cue`
- **THEN** the `cue` first on `PATH` refuses to run and the case fails

### Requirement: The curl shim answers from fixtures

The `curl` shim SHALL accept only the resolver's curl shape (anything else is exit 2) and log its argument vector to `$CASCADE_FIXTURE_DIR/curl.log`. It SHALL answer from `<dir>/http/<host>/<path>` (`?` written as `%3F`) with status from `<file>.status` (default 200 if the body exists, else 404; several lines consumed one per request, the last repeating) and headers from `<file>.headers`.

#### Scenario: A real curl call is caught

- **WHEN** resolver code calls `curl` with a flag outside the allowed shape
- **THEN** the shim exits 2 and the case fails

### Requirement: The git shim answers from fixtures

The `git` shim SHALL answer `ls-remote` (after leading `-C` and `-c` options) from `<dir>/git/<repo>.refs` and fail it when `<repo>.refs.fail` exists (always when empty, else for the first N calls). It SHALL log the isolation variables and every credential helper or extraheader the real `git config` would see with the same options, and pass every other command to the real `git`.

#### Scenario: A failing ls-remote fixture

- **WHEN** `<repo>.refs.fail` exists for a repo and a case runs `git ls-remote` for it
- **THEN** the `git` shim fails the call

### Requirement: Fixtures are captured from real answers

Fixtures SHALL be captured from real GHCR, proxy and git answers.

#### Scenario: A fixture answer

- **WHEN** a case reads a GHCR, proxy or git answer from the fixture directory
- **THEN** that answer was captured from the real service

### Requirement: Offline suite git ignores the caller's config

Git in the tests SHALL ignore the caller's global and system git config (`GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`) and use a fixed author and committer, so a test gives the same result locally and on a bare runner.

#### Scenario: Caller's git config is not read

- **WHEN** the caller's global git config sets an author
- **THEN** the commits of the test repos still carry the fixed author and committer

### Requirement: The offline suite covers the resolver

The offline suite SHALL cover at least the cases listed in the scenarios of this requirement.

#### Scenario: Pagination limit

- **WHEN** the fixture for a GHCR tag list chains 21 pages through `Link` headers
- **THEN** the case asserts `newest` exits 1

#### Scenario: SemVer cases

- **WHEN** the case list of the suite is read
- **THEN** the suite SHALL cover SemVer order: `alpha.2` < `alpha.10`, `beta.10` > `beta.2`, `v2.0.0` > `v2.0.0-beta.10`, `rc.1` > `beta.9`, `alpha.beta` > `alpha.1`, `alpha.1` < `alpha.a`, `alpha` < `alpha.1`, build metadata ignored; `semver-cmp` output and exit codes; `semver-sort`; `next-patch`

#### Scenario: Candidate cases

- **WHEN** the case list of the suite is read
- **THEN** the suite SHALL cover dev builds and pseudo-versions excluded; the major restriction with a v3 present and the new-major warning (prerelease and release); a proxy `v2/@v/list` 404 giving no warning; the stable-current rule with and without `--pre`
- **AND** it SHALL cover an unpublished newest keeping the pin; a skip to an older published candidate; three unpublished candidates (exit 3 with the warning); ten unpublished (exit 1); never backwards

#### Scenario: Steering file cases

- **WHEN** the case list of the suite is read
- **THEN** the suite SHALL cover holds: capping, expired, below current, duplicate, missing `reason`, bad `expires`
- **AND** it SHALL cover frozen: exact file, directory prefix, trailing `/`, `dir2` not matched by `dir`, a file entry not matched by its parent directory, malformed entries, empty files, verbatim copies of library's and cli's committed `.cascade-frozen`

#### Scenario: Query cases

- **WHEN** the case list of the suite is read
- **THEN** the suite SHALL cover `pin-of` from a captured modulefile, a dep followed by another dep, dep absent; `language-of` found and absent; GHCR token 403 and tags 404 (`newest` 1, `published` 3); `published oci` with both `Accept` types and the tag as given

#### Scenario: Request and release cases

- **WHEN** the case list of the suite is read
- **THEN** the suite SHALL cover 5xx then 200, four 5xx, a 429 retry; a relative-`Link` pagination walk and 21 pages
- **AND** it SHALL cover a draft or asset-less release skipped; a missing second asset; a failing `git ls-remote` tried 4 times and one retried to success; `git ls-remote` isolated from a credentialed caller checkout and run with the 60-second stall limit

#### Scenario: Expect and output cases

- **WHEN** the case list of the suite is read
- **THEN** the suite SHALL cover `--expect` published on the third poll, never published with a fake clock, above a hold and a prerelease against a stable current ignored
- **AND** it SHALL cover `-q` first in every `curl.log` line; no request to `api.github.com` and no token value sent; warning keys for `release` and `opm-cli`; the `--json` shape

#### Scenario: Classify, title and body cases

- **WHEN** the case list of the suite is read
- **THEN** the suite SHALL cover `classify`, `title` and `body` against throwaway git repos: every pattern form and an invalid one, every title type and subject form, empty diff, untracked file, byte-identical reruns, `| none | - | - | - |`, a hostile tag, an unknown source, the lint failing on a planted bare mention, a grep that cannot run `-P` failing the lint, a mention in Notes passing through unchanged
- **AND** it SHALL cover the stub checksum and the stub-agreement cases

### Requirement: Resolver tests run on every change

`.github/workflows/cascade-resolver.yml` SHALL run on every `pull_request` and on `push` to `main` with no path filter, with `permissions: contents: read`, as one job named `Resolver tests` with a `timeout-minutes` of at least 10 (raised only when the suites need it; the job name never changes).

#### Scenario: Unrelated PR still reports

- **WHEN** a PR changes only `README.md`
- **THEN** `Resolver tests` runs and reports a status

### Requirement: Resolver tests set up pinned tools

The job `Resolver tests` SHALL check out the repo with a SHA-pinned `actions/checkout` and `persist-credentials: false`, confirm mikefarah `yq` v4, and install go-task from a pinned, checksum-verified release (the wiring suite runs `task`).

#### Scenario: Checkout keeps no credentials

- **WHEN** the job `Resolver tests` checks out the repo
- **THEN** it uses a SHA-pinned `actions/checkout` with `persist-credentials: false`

### Requirement: Resolver tests lint scripts and workflows

The job `Resolver tests` SHALL run a pinned, checksum-verified `shellcheck` release (not the runner image's own) on every `*.sh` under `.github/scripts` and on every test shim (the resolver's `curl` and `git` shims and the wiring suite's `gh` shim). It SHALL run `actionlint` from a pinned, checksum-verified release on `.github/workflows/*.yml` (which includes the two reusable cascade workflows).

#### Scenario: A shim is linted

- **WHEN** the job `Resolver tests` runs
- **THEN** `shellcheck` covers the resolver's `curl` and `git` shims and the wiring suite's `gh` shim, and `actionlint` covers the two reusable cascade workflows

### Requirement: Resolver tests validate the OpenSpec specs

The job `Resolver tests` SHALL install the OpenSpec CLI at one pinned version with `npm install --ignore-scripts`, after `actionlint` and before the offline suites. It SHALL then run `openspec validate --all --strict --no-interactive` and fail when the CLI version differs from the pin or when the validation exits non-zero.

#### Scenario: A spec with a long requirement fails the job

- **WHEN** a PR adds a requirement whose body is longer than 500 characters
- **THEN** `openspec validate --all --strict --no-interactive` exits non-zero and the `Resolver tests` job fails

#### Scenario: A different CLI version fails the job

- **WHEN** the installed OpenSpec CLI reports a version other than the pin
- **THEN** the step fails before it validates and the `Resolver tests` job fails

#### Scenario: The validation reports on every pull request

- **WHEN** a PR changes only `README.md`
- **THEN** the `Resolver tests` job runs the OpenSpec validation and reports a status

### Requirement: Resolver tests run both offline suites

The job `Resolver tests` SHALL run both offline suites: the resolver suite and the wiring suite.

#### Scenario: Failing test fails the check

- **WHEN** a case in the offline suite fails
- **THEN** the `Resolver tests` job fails

#### Scenario: Failing wiring case fails the check

- **WHEN** a case in the wiring suite fails and every resolver case passes
- **THEN** the `Resolver tests` job fails

### Requirement: Resolver tests add no job and change no other workflow

The workflow `.github/workflows/cascade-resolver.yml` SHALL add no new job and no new check context. It MUST NOT change `mention-guard.yml` or `tag-ledger.yml`.

#### Scenario: One job in the workflow

- **WHEN** the jobs of `.github/workflows/cascade-resolver.yml` are listed
- **THEN** only `Resolver tests` appears, and `mention-guard.yml` and `tag-ledger.yml` are unchanged

### Requirement: The wiring suite runs offline with fakes

`bash .github/scripts/cascade/wiring/test/run.sh` SHALL test the wiring scripts with no network: local bare git repos served as `origin` through `file://` URLs, a `gh` shim selected through `CASCADE_GH` that answers from fixture files and logs every call, and a toy `Taskfile.yml`. It SHALL print `PASS` or `FAIL` per case and exit 0 only when every case passes.

#### Scenario: Wiring suite runs without network

- **WHEN** the wiring suite runs on a machine with no network access
- **THEN** every case passes and the `gh` shim log shows no call that the case did not expect

### Requirement: The wiring suite uses the real resolver for offline subcommands only

The wiring suite SHALL use the real `cascade-resolve.sh` as `CASCADE_RESOLVER` for its offline subcommands only (`title`, `body`, `classify`, `semver-cmp`); no case SHALL call `newest`, `published` or `pin-of`.

#### Scenario: Offline subcommands only

- **WHEN** a wiring case needs the answer of `title`, `body`, `classify` or `semver-cmp`
- **THEN** it gets it from the real `cascade-resolve.sh` through `CASCADE_RESOLVER`, and no case calls `newest`, `published` or `pin-of`

### Requirement: The wiring suite covers the cascade scripts

The wiring suite SHALL cover at least the cases listed in the scenarios of this requirement.

#### Scenario: Amended bot commit is a human commit

- **WHEN** the fixture branch holds a bot-authored commit whose committer is a human
- **THEN** the case asserts the receiver picks mode `merge`, not `rebuild`

#### Scenario: Payload and receiver cases

- **WHEN** the case list of the wiring suite is read
- **THEN** the suite SHALL cover payload validation (eight tags, nine tags, a bad tag, a tag with a trailing newline, a control character in the source, an unknown source, extra keys); every receiver mode, including a bot commit a human amended
- **AND** it SHALL cover the cascade-PR filter (a fork PR on `deps/cascade`, a same-repo PR by a human, two matching PRs); the derived-file merge conflict and a hard conflict; merge mode running `main`'s task when the branch changed it

#### Scenario: Guard, title and Notes cases

- **WHEN** the case list of the wiring suite is read
- **THEN** the suite SHALL cover every row of the workflows guard under both rule values; the title rules (not retitled, retitled with `!` kept, the title-rise comment firing once, a marker pasted into the Notes, a body with no marker)
- **AND** it SHALL cover the breaking check over several releases with one breaking release in the middle and with an API error; Notes extraction with the marker, without it, and with a CRLF body that must not grow across two runs

#### Scenario: Publish cases

- **WHEN** the case list of the wiring suite is read
- **THEN** the suite SHALL cover the publish refusals (a PR-number mismatch, an unknown label, an unknown action, a bundle touching `.tasks/cascade/pins.sh`, `Taskfile.yml` or a symlink, a mode change, a non-bot commit, a rebuild that would drop a human commit, a merge commit whose tree is not the merge of its parents)
- **AND** it SHALL cover publish deriving the title, body and labels itself (a forged title, planted body text, a dropped `need-human-review` or `deps-cascade:breaking`); the per-receiver allow-lists and the mirrors of each receiver's `pins.sh`; the action table

#### Scenario: Notify, workflow and gate cases

- **WHEN** the case list of the wiring suite is read
- **THEN** the suite SHALL cover the notify payload bytes and target map; the org `.github` ref guard and the repo-name derivation, run from the inline step text of every job in the three workflows; that no repo-code command sees a token; the pinned tool installer
- **AND** it SHALL cover the release-key rule of the wiring check; and the gate status mapping with truncation

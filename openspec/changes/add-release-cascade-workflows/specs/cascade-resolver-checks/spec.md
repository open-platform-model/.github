## MODIFIED Requirements

### Requirement: Required CI check for .github

`.github/workflows/cascade-resolver.yml` SHALL run on every `pull_request` and on `push` to
`main` with no path filter, with `permissions: contents: read`, as one job named
`Resolver tests` with a `timeout-minutes` of at least 10 (raised only when the suites need
it; the job name never changes). It SHALL check out the repo with a SHA-pinned
`actions/checkout` and `persist-credentials: false`, confirm mikefarah `yq` v4, install go-task
from a pinned, checksum-verified release (the wiring suite runs `task`), run a pinned,
checksum-verified `shellcheck` release (not the runner image's own) on every `*.sh` under
`.github/scripts` and on every test shim (the resolver's `curl` and `git` shims and the wiring
suite's `gh` shim), run `actionlint` from a pinned, checksum-verified release on
`.github/workflows/*.yml` (which includes the three reusable cascade workflows), and run both
offline suites: the resolver suite and the wiring suite. It SHALL add no new job and no new
check context. It MUST NOT change `mention-guard.yml` or `tag-ledger.yml`.

#### Scenario: Unrelated PR still reports

- **WHEN** a PR changes only `README.md`
- **THEN** `Resolver tests` runs and reports a status

#### Scenario: Failing test fails the check

- **WHEN** a case in the offline suite fails
- **THEN** the `Resolver tests` job fails

#### Scenario: Failing wiring case fails the check

- **WHEN** a case in the wiring suite fails and every resolver case passes
- **THEN** the `Resolver tests` job fails

## ADDED Requirements

### Requirement: Offline wiring test suite

`bash .github/scripts/cascade/wiring/test/run.sh` SHALL test the wiring scripts with no network:
local bare git repos served as `origin` through `file://` URLs, a `gh` shim selected through
`CASCADE_GH` that answers from fixture files and logs every call, the real
`cascade-resolve.sh` as `CASCADE_RESOLVER` for its offline subcommands only (`title`, `body`,
`classify`, `semver-cmp`; no case calls `newest`, `published` or `pin-of`), and a toy
`Taskfile.yml`. It SHALL print `PASS` or `FAIL` per case and
exit 0 only when every case passes. It SHALL cover at least: payload validation (eight tags, nine
tags, a bad tag, an unknown source, extra keys); every receiver mode, including a bot commit a
human amended; the cascade-PR filter (a fork PR on `deps/cascade`, a same-repo PR by a human, two
matching PRs); the derived-file merge conflict and a hard conflict; every row of the workflows
guard under both rule values; the title rules (not retitled, retitled with `!` kept, the
title-rise comment firing once, a marker pasted into the Notes, a body with no marker); the
breaking check over several releases with one breaking release in the middle and with an API
error; Notes extraction with the marker, without it, and with a CRLF body that must not grow
across two runs; the publish refusals (a PR-number mismatch, an unknown label, an unknown action,
a title that does not recompute); the action table; the notify payload bytes and target map; the
org `.github` ref guard and the repo-name derivation, run from the inline step text of every
job in the three workflows; that no repo-code command sees a token; and the gate status mapping
with truncation.

#### Scenario: Wiring suite runs without network

- **WHEN** the wiring suite runs on a machine with no network access
- **THEN** every case passes and the `gh` shim log shows no call that the case did not expect

#### Scenario: Amended bot commit is a human commit

- **WHEN** the fixture branch holds a bot-authored commit whose committer is a human
- **THEN** the case asserts the receiver picks mode `merge`, not `rebuild`

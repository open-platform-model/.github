## Why

The release cascade (workspace RELEASING.md, section "The cascade") has every repo run its own
`task deps:cascade`, and all four tasks must answer the same questions the same way: which
upstream version is the newest, whether it is really published, whether a pin is held or
frozen, and what the cascade PR is called. Today those answers are scattered and partial:

- `.tasks/deps/latest-tag.sh` (workspace root) resolves the opm CLI and the operator from git
  tags plus a download probe, but has no major restriction, no retry and sorts with the
  `sed 's/-/~/' | sort -rV` trick (`latest-tag.sh:37`), which gets SemVer precedence wrong for
  mixed numeric and alphanumeric prerelease identifiers.
- `.tasks/deps/templates.sh:51-77` walks GHCR tag lists but keeps stable versions only.
- `cli/.github/scripts/publish-templates.sh:94-105` holds a second copy of that walk.
- Nothing resolves Go modules from `proxy.golang.org`, reads `.cascade-hold` or
  `.cascade-frozen` (RELEASING.md, section "Cascade files"), or computes the title and body
  RELEASING.md, sections "Title from diff class" and "The receiver", define.

RELEASING.md, section "Rollout and changes", makes this change the first Phase 2 step: the
shared resolver lives in `.github` and every `add-deps-cascade-task` depends on it. The
interface is fixed in advance by the Phase 2 cascade contract, version 1 (committed with this
change as `contract.md`), so the four repo changes are written in parallel against its stub.

`.github` has no OpenSpec workspace and no CI check of its own. RELEASING.md, section
"Rulesets on main", requires "the CI check its `add-cascade-resolver` change adds" on
`.github`; this change adds it.

## What Changes

- **OpenSpec in `.github`.** Already landed as this branch's first commit
  (`chore(openspec): initialize openspec`), with a config fit for an org repo of workflows and
  bash scripts.
- **The resolver CLI** `.github/scripts/cascade/cascade-resolve.sh` with libraries under
  `.github/scripts/cascade/lib/`, per Phase 2 cascade contract §2 and §4:
  - `newest` across four kinds (`cue` from GHCR, `go` from the Go proxy, `release` and
    `opm-cli` from git tags plus anonymous asset download probes), restricted to the current
    major, never moving backwards, honouring holds, with a new-major warning and an optional
    `--expect` wait;
  - `published` (including an `oci` kind for docs bundles), `pin-of`, `language-of`;
  - `.cascade-frozen` and `.cascade-hold` readers (`frozen`, `is-frozen`, `hold`,
    `check-files`);
  - `semver-cmp`, `semver-sort`, `next-patch`;
  - `classify`, `title`, `body`: the cascade PR's title and body from a repo's `classes` file
    and `pins.sh`, including the mention lint.
  - Exit codes 0 (yes or moved), 3 (nothing to do or no), 1 (error), 2 (usage).
- **The canonical stub** `.github/scripts/cascade/stub-resolve.sh`, byte-identical to contract
  §7 (sha256 `970130f7…3d9c`), which the four repo changes copy into their test data.
- **The contract itself**, version 1, as `openspec/changes/add-cascade-resolver/contract.md`, so
  the specs' source archives with the change instead of living only in a scratch directory.
- **An offline test suite** `.github/scripts/cascade/test/run.sh` with PATH shims for `curl`
  and `git` answering from captured fixtures, covering every case in contract §2.10 and the
  plan review's additions, plus a stub-agreement test.
- **Departures from the contract**, each reported to the supervisor: Notes pass through
  unchanged (workspace RELEASING.md wins over contract §9.13); an `--expect` version confirmed
  published joins the candidates and the wait is timed from requested sleeps (§2.9); `pin-of`
  never shells out to `cue` (§2.6); `next-patch` refuses a prerelease; `CASCADE_SOURCE` is
  validated; `shellcheck` in CI covers every script under `.github/scripts`.
- **CI.** `.github/workflows/cascade-resolver.yml`, job `Resolver tests`, on every PR and push
  to `main` with no path filter: `shellcheck`, `actionlint`, then the offline suite. A
  separate non-required `.github/workflows/cascade-resolver-live.yml` (weekly and on dispatch)
  checks read-only invariants against the real services.
- **README.** A `cascade` section appended after the `tag-ledger` section.

Not in this change:

- The notify and receive workflows (`add-release-cascade-workflows`, Phase 3), the
  `deps-cascade:breaking` label and the title-retention logic (contract §9.8, §4.3).
- Any repo's `deps:cascade` task, `pins.sh` or `classes` file (each repo's
  `add-deps-cascade-task`).
- Replacing the workspace `.tasks/deps/*.sh` helpers or the cli's `publish-templates.sh` GHCR
  walk (Phase 5 rewire, contract §10).
- The README's `COMMIT_MESSAGES` wording for mention-guard (the separate BLANK-squash sweep).
- Making `Resolver tests` a required check: that is an owner ruleset step after merge
  (RELEASING.md, section "Rulesets on main").

## Capabilities

### New Capabilities

- `cascade-resolver`: version resolution for the cascade: query kinds, SemVer order, candidate
  rules, holds, frozen pins, retries and `--expect`, the consistent-set helpers, exit codes and
  output format.
- `cascade-pr-text`: path classification, the cascade PR title and body, and the mention lint.
- `cascade-resolver-checks`: the canonical stub, the offline test suite and the `.github` CI
  check plus the live smoke workflow.

### Modified Capabilities

None (`.github` has no main specs yet).

## Impact

- **New files only** under `.github/scripts/cascade/`, `.github/workflows/` and
  `openspec/changes/add-cascade-resolver/`, plus a README section. `mention-guard.yml`,
  `tag-ledger.yml` and their scripts are untouched; `actionlint` and `shellcheck` already pass
  on them.
- **Callers.** catalog_opm, library, opm-operator and cli call the resolver through
  `CASCADE_RESOLVER` or `../.github/.github/scripts/cascade/cascade-resolve.sh` (contract §3);
  the Phase 3 receive workflow checks out `.github` at `main`. The CLI surface and exit codes
  become an interface those callers rely on; changing them later means a contract revision.
- **Runtime needs:** `bash`, `curl`, `jq`, `git`, mikefarah `yq` v4. No credentials; hosts
  contacted: `ghcr.io`, `proxy.golang.org` (or `CASCADE_GOPROXY`), `github.com` (git and
  release downloads). Never `api.github.com`.
- **Depends on:** nothing.
- **Depended on by:** `add-deps-cascade-task` in catalog_opm, library, opm-operator and cli (S5
  of their tests needs this resolver merged), and `add-release-cascade-workflows` (Phase 3).
- **Owner step after merge:** add `Resolver tests` to the `.github` ruleset on `main`.
- **Release class:** none; `.github` does not release. PR title per contract §10:
  `feat(cascade): add the shared cascade resolver`.

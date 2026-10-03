## Context

The interface is already fixed. The Phase 2 cascade contract (version 1, committed verbatim
with this change as `contract.md` so it archives with it, cited below as "contract §N") defines the resolver's subcommands,
exit codes, query kinds, file schemas, title and body format, the stub and the test cases, and
four repo changes are being written against it in parallel. This design does not reopen any of
that. It records how the code is laid out, which existing code it borrows from, and where it
adds anything the contract leaves open. Where the contract and workspace RELEASING.md disagree,
RELEASING.md wins and the conflict goes to the supervisor (contract preamble).

State of `.github` at `origin/main` (`6b2eac2`):

- Two workflows: `mention-guard.yml` (required org-wide by path from `main`) and
  `tag-ledger.yml` (daily). Two bash scripts: `.github/scripts/tag-ledger.sh` (252 lines) and
  `ledger-integrity.sh` (132 lines). These set the style: `set -euo pipefail`, a `die()` helper,
  `jq` for JSON, SHA-pinned actions (`tag-ledger.yml:72` pins `actions/checkout` to
  `3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`).
- No tests, no Taskfile, no Go module, no release-please. `actionlint` (v1.7.12) and
  `shellcheck` pass on the current tree.

Prior art in the workspace, read and borrowed from, never called:

- `.tasks/deps/latest-tag.sh`: candidates from `git ls-remote`, at most 10 probed (`:37`),
  anonymous `HEAD` of `releases/download/<tag>/<asset>` (`:52`), only 404 means "not
  consumable" (`:55`), everything else aborts. Kept: the method. Dropped: its `sort -rV` order,
  bare-version output and curl `--retry`.
- `.tasks/deps/templates.sh:51-77`: anonymous GHCR token, paginated `tags/list?n=1000`, more
  than 20 pages fails (`:65`). Kept: the walk. Changed: prereleases are candidates, and
  "published" is a manifest `HEAD`, not tag presence.
- `.tasks/deps/test-latest-tag.sh:15-31`: PATH shims for `git` and `curl` with a `curl.log`.
  Extended to answer bodies and headers from fixture files (contract §2.10).

## Goals / Non-Goals

**Goals:**

- One resolver that implements contract §2 and §4 exactly, so the four repo tasks and the
  Phase 3 workflow get identical answers and identical PR text.
- Every behaviour in contract §2.10 covered by an offline test that runs in CI and locally
  with `bash .github/scripts/cascade/test/run.sh` and no network.
- A deterministic required check for `.github` (`Resolver tests`) that cannot block unrelated
  PRs.

**Non-Goals:**

- Notify and receive workflows, labels, branch handling, `deps-cascade:breaking`, keeping a
  human retitle (Phase 3, `add-release-cascade-workflows`).
- Any repo-side task, `pins.sh` or `classes` file.
- Replacing workspace `.tasks/deps/*.sh` or the cli's `publish-templates.sh` GHCR walk now.
- Authenticated GitHub API use. The resolver never sends a token (contract §2.2).

## Decisions

### Layout

```
.github/scripts/cascade/
  cascade-resolve.sh        # entry point: arg parsing, dispatch, exit codes
  stub-resolve.sh           # contract §7, byte for byte, mode 0755
  lib/common.sh             # die/warn/usage, version regex, tool checks (yq must be mikefarah v4)
  lib/semver.sh             # semver_valid, semver_cmp, semver_sort, next_patch, candidate filter
  lib/http.sh               # http_get / http_head: the one curl shape, retries, status mapping
  lib/ghcr.sh               # token, tags walk with Link pagination, manifest HEAD, modulefile blob
  lib/goproxy.sh            # @v/list, @v/<v>.info, new-major probe path
  lib/release.sh            # git ls-remote candidates, asset download probes
  lib/query.sh              # query kinds and pin keys, published, pin-of, language-of
  lib/files.sh              # .cascade-frozen and .cascade-hold readers and validation
  lib/newest.sh             # candidate pipeline, holds, never-backwards, --expect, --json
  lib/classify.sh           # classes-file matcher
  lib/title.sh, lib/body.sh # contract §4.3, §4.4, the mention lint
  test/run.sh               # table test; exit 0 pass, 1 fail
  test/lib.sh               # assertions, sandbox, shim setup
  test/shim/curl, test/shim/git
  test/fixtures/<case>/http/<host>/<path>[.status|.headers], test/fixtures/<case>/git/<repo>.refs
.github/workflows/cascade-resolver.yml       # job "Resolver tests"
.github/workflows/cascade-resolver-live.yml  # weekly + dispatch, never required
```

`cascade-resolve.sh` resolves its own directory with `${BASH_SOURCE[0]}` and sources `lib/`, so
it works from any working directory and through the absolute path repos use (contract §3).

### Command syntax and exit codes

Exactly contract §2.6, with the exit table of §2.3: 0 success or yes, 3 nothing to do or no, 1
error, 2 usage. A malformed version argument, an unknown flag, a missing argument and a `cue`
coordinate whose `@vN` disagrees with `--current`'s major are all 2, and so is a `--repo-root`
that is not a directory (a missing steering file inside an existing root is still an empty
file). `newest --json` prints its object on exit 3 too, with `moved: false` and `target` equal
to `--current`; without `--json`, stdout on exit 3 stays empty. Stdout carries only the
answer; every diagnostic goes to stderr prefixed `cascade-resolve: `. Warnings are also
appended to `$CASCADE_WARNINGS` as `<pin-key>\t<message>` when that variable is set (§2.2).

Environment read: `CASCADE_WARNINGS`, `CASCADE_GOPROXY` (default `https://proxy.golang.org`),
`CASCADE_TODAY`, `CASCADE_SLEEP` (default `sleep`), `CASCADE_MAX_WAIT` (default 600),
`CASCADE_BASE`, `CASCADE_SOURCE`, `CASCADE_TAGS`, `CASCADE_NOTES_FILE`. Nothing else, and no
token variable.

### Network requests

All through `lib/http.sh`, which issues only the contract §2.9 curl shape
(`curl -q -sS --connect-timeout 10 --max-time 60 -o <body> -D <headers> -w '%{http_code}' [-I]
[-L] [-H ...] <url>`) into a per-run `mktemp -d` directory removed by an `EXIT` trap.

| Purpose | Request | Answer handling |
| --- | --- | --- |
| GHCR token | `GET https://ghcr.io/token?scope=repository:<repo>:pull&service=ghcr.io` | 200: token via `jq -r .token`; 403/404: unknown or private package |
| GHCR tags | `GET https://ghcr.io/v2/<repo>/tags/list?n=1000`, then each `Link: <...>; rel="next"` | 200: `.tags[]`; 404: unknown; page 21: exit 1 |
| GHCR published | `HEAD .../manifests/<v>`, `Accept: application/vnd.oci.image.manifest.v1+json` | 200 yes, 404 no |
| OCI published | same, `Accept` also `application/vnd.oci.image.index.v1+json`, tag as given | 200 yes, 404 no, unknown package: 3 with warning |
| Modulefile | `GET .../manifests/<v>` then `GET .../blobs/<digest>` of the `application/vnd.cue.modulefile.v1` layer | 200 or exit 1 |
| Go list | `GET $CASCADE_GOPROXY/<path>/@v/list` | 200: lines; 404/410 on the new-major probe: none |
| Go published | `GET .../@v/<v>.info` | 200 yes, 404/410 no |
| Release candidates | `git ls-remote --tags --refs https://github.com/open-platform-model/<repo> 'refs/tags/v*'` | non-zero git exit: exit 1 |
| Release published | `HEAD -L https://github.com/open-platform-model/<repo>/releases/download/<v>/<asset>` per asset | all 200 yes; any 404 no |

A GHCR `Link` header is relative (`</v2/<repo>/tags/list?last=...&n=1000>; rel="next"`), so
the next URL is `https://ghcr.io` plus the link when it starts with `/`, and the link itself
only when it is an absolute `https://ghcr.io/` URL; any other host is exit 1 (the token is never
sent elsewhere).

`<repo>` for `cue` is `open-platform-model/<module path without @vN>`, which matches the CUE
registry mapping `opmodel.dev=ghcr.io/open-platform-model` (research: the short
`open-platform-model/core` answers 403). The anonymous GHCR bearer token is sent only to `ghcr.io`, as an `Authorization` header
argument; the test shim logs that argument, and fixture tokens are dummies.

The modulefile parse for `pin-of` and `language-of` never uses `cue`, even when it is on `PATH`
(a departure from contract §2.6, which allows either): one parser means local runs and CI test
the same code. `pin-of` scans for the line holding `"<dep>": {`, fails with exit 1 if the key
appears more than once, and takes the first `v: "<version>"` before that block's closing `}`, so
a following dep's `v:` is never read. `language-of` takes the `version:` inside the
`language: {` block. Both are `awk` over the plain `module.cue` blob.

Retries: `000`, `429` and `5xx` get 4 attempts in all with `${CASCADE_SLEEP:-sleep}` 2, 4 and 8
between them, then exit 1. Any other status outside a request's expected set is exit 1 with
"answered `<code>`; refusing to guess" (§2.9).

### SemVer

`semver_cmp` is written by hand in bash per SemVer 2.0.0 §11 (contract §2.5): numeric
major/minor/patch, release above prerelease, identifiers compared left to right (numeric by
value, alphanumeric by ASCII via `LC_ALL=C` string compare, numeric below alphanumeric), longer
list above its prefix, build metadata ignored. `semver_sort` is a merge sort over `semver_cmp`
(in-process, no subshell per comparison). `newest` filters before it sorts: only in-major
candidates strictly above `--current` reach the sort, so a GHCR list of hundreds of tags
(mostly `-0.dev.` builds) sorts a handful.
`next_patch` accepts only a release (`vX.Y.Z`); a prerelease or build-metadata input is exit 2.
Every version-advance input in the four repos is a release today (templates `1.0.3`, fixtures
`0.x.y`).
Candidate filtering drops anything that fails the version regex, `-0.dev.`/`-dev.` builds, Go
pseudo-versions, other majors, and prereleases when `--current` is a release and `--pre` is
absent; duplicates by build metadata collapse.

### Steering files

`lib/files.sh` reads `.cascade-frozen` and `.cascade-hold` with `yq -o=json` and validates them
with `jq` against the RELEASING.md, section "Cascade files", schemas as tightened by contract
§2.7 and §2.8: required keys, no unknown keys, non-empty strings, valid `max`, `YYYY-MM-DD`
`expires`, safe `path` (no leading `/`, no `..`), at most one hold per pin. Any violation is
exit 1 naming the file, the entry index and the key. Every reading subcommand validates first,
so a malformed file can never be half-applied.

### Title and body

Implemented in the resolver, not per repo (contract §9.1). `classify` applies the five pattern
forms of contract §4.1 in file order with "unmatched is shipped". `title` and `body` compute
the merge-base, the changed paths (diff plus untracked, not ignored) and the moved pins from
`pins.sh <merge-base>` against `pins.sh WORKTREE`, then render §4.3 and §4.4 byte for byte. The
mention lint uses `grep -P '(?<![\w@])@[A-Za-z0-9]'`, the prefix of mention-guard's own
pattern (`mention-guard.yml:50`), and it deliberately has no bot-handle exemption: the cascade
never needs to name a bot. Notes are copied byte for byte and neither linted nor edited: see
"Notes pass through" below.

`body` on an empty diff still exits 0 and prints the whole layout with an empty title marker
(`<!-- cascade-title:  -->`), so the Phase 3 workflow always gets the same shape; `title` is the
command that answers 3. The labels marker joins the union of the moved pins' labels with `,`, each
label once, in first-seen order. `CASCADE_SOURCE` is checked against the five cascade repos
(`core`, `catalog_opm`, `library`, `opm-operator`, `cli`); any other value is dropped with a
warning together with its tags, since the dispatch payload is untrusted. A dropped source or
tag is named only in a safe form (every character outside `[A-Za-z0-9._/-]` replaced by `?`,
cut to 64 characters), so a hostile payload cannot plant a mention that would fail the lint and
stall the cascade. Changed paths use `git diff --no-renames`, so a rename counts both its old
and new path. A warnings line without a tab renders under key `-`. An explicit `--warnings` file
or a `CASCADE_NOTES_FILE` that does not exist is exit 1 (a caller bug, not "no warnings"); the
default warnings file may be missing.

### Stub

`stub-resolve.sh` is committed as the exact text of contract §7. Extracting the fenced block
from the contract and running `sha256sum` gives
`970130f7d55c07f5b86d4f5b6f392330427ff923eb34f93553656bcd4b893d9c`, and the extract passes
`shellcheck` (checked while writing this design). `test/run.sh` asserts that checksum and runs
the stub-agreement cases with the exclusions §2.10 lists.

### CI

`cascade-resolver.yml`: `on: pull_request` and `push: branches: [main]`, no `paths:` filter;
`permissions: contents: read`; one job, `name: Resolver tests`, `runs-on: ubuntu-latest`,
`timeout-minutes: 10`. Steps: checkout (the SHA `tag-ledger.yml` pins, `persist-credentials:
false`), `yq --version` must report mikefarah v4, `shellcheck -x` on `find .github/scripts -name
'*.sh' -print0` plus the two shims (wider than contract §2.11, which names only
`.github/scripts/cascade`, to match the repo's validation gate; `tag-ledger.sh` and
`ledger-integrity.sh` pass today), `actionlint` on `.github/workflows/*.yml`, then
`bash .github/scripts/cascade/test/run.sh`.

`cascade-resolver-live.yml`: `workflow_dispatch` plus a weekly `schedule`, `permissions:
contents: read`, job `Resolver live smoke`, the invariants of contract §2.11. "The newest real
version" comes from the resolver itself: `newest cue opmodel.dev/core@v2 --current v2.0.0-0`
(below every v2 prerelease) must exit 0 with an in-major, non-dev version; a second run with that
result as `--current` must exit 3. The same pair runs for `opm-cli` from `v1.0.0-0`, plus
`published opm-cli <newest>` exiting 0. Never required.

### Tests

`test/lib.sh` isolates git from the caller: it exports `GIT_CONFIG_GLOBAL=/dev/null`,
`GIT_CONFIG_NOSYSTEM=1`, `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`,
`GIT_COMMITTER_EMAIL` and fixed dates, and creates repos with `git -c init.defaultBranch=main
init`, so a signing key, hook or template in the user's config cannot change a result and a bare
runner with no identity can commit. `test/run.sh` builds `PATH` from the shim directory plus the
directories of the tools the resolver needs, with no `cue`, so the cue-free parse is what runs
everywhere. The `curl` shim and the per-case fixture directory are the only network.

## Research & Decisions

### Language

**Context**: the resolver must run in four repos' tasks and a Phase 3 job that has no secrets.
**Explored**: research report r-resolver; existing `.github` scripts; workspace
`.tasks/deps/*`.
**Options considered**:
1. Bash with curl, jq, git, yq: matches every existing script here and in `.tasks/deps`;
   needs a hand-written SemVer comparator.
2. Go with `golang.org/x/mod/semver`: exact SemVer for free, real unit tests; adds a module, a
   toolchain step in every receiver and build latency.
**Decision**: bash (contract §2.1).
**Rationale**: no toolchain for callers, same style as the repo; the SemVer risk is contained
to one function with the table cases contract §2.10 lists.

### Running `actionlint` in CI

**Context**: the contract's CI steps (§2.11) are `shellcheck` and `test/run.sh`; the
supervisor's task for this change adds "actionlint/shellcheck as applicable". `actionlint` is
not preinstalled on `ubuntu-latest`.
**Options considered**:
1. Skip it in CI, run it locally only: no extra download, but workflow mistakes reach `main`.
2. Download the release binary with its published checksum file, pinned version and hash
   verified in the step.
3. Run the `rhysd/actionlint` container pinned by digest: one line, but a third-party image
   with no hash we can review in the diff.
**Decision**: option 2: a pinned `actionlint` release tarball, verified against a checksum
written in the workflow, in the same `Resolver tests` job.
**Rationale**: it checks `mention-guard.yml` and `tag-ledger.yml` too (both clean today), costs
a few seconds, and the hash in the workflow makes a supply-chain change visible in review. It
adds a step to contract §2.11 without changing any listed one; reported to the supervisor.

### Retry budget and `--expect`

**Context**: RELEASING.md names no retry budget; the research's "10 minutes" came from the
task text.
**Decision**: contract §2.9 and §9.2: 4 attempts over about 14 s for transient answers;
`--expect` polls `published` every 30 s up to `--max-wait` (default 600 s) and then answers with
what is published plus a warning. Without `--expect` there is no wait, so a genuine "nothing
newer" costs one pass.
**Rationale**: the proxy can lag a fresh library tag; the daily sweep catches anything the
wait misses, so running out is not an error.

Two clarifications of contract §2.9, reported to the supervisor:

- Elapsed time is the sum of the sleep intervals the resolver asked for (polls × 30 s), never
  the wall clock or `$SECONDS`, so a faked `CASCADE_SLEEP` makes the "never appears" case instant.
- An `--expect` version confirmed published joins the candidate set of the normal pass, even
  when the upstream list does not hold it yet. Without this the contract's own test case (a
  version absent from `@v/list` that becomes published on the third poll) could not answer that
  version. It was already checked against the major, prerelease and hold rules before the wait.

### Notes pass through

**Context**: contract §4.4 and §9.13 neutralize a mention in Notes by inserting U+200D after the
`@`. Workspace RELEASING.md, section "Title from diff class", says the body has "a `## Notes`
section the bot never edits". §9.13 is a supervisor choice not confirmed by the owner, and the
contract preamble says RELEASING.md wins.
**Decision**: Notes are copied byte for byte, not edited and not linted. The lint covers the
title and every body line above the `cascade-notes` marker.
**Rationale**: it follows RELEASING.md. A human mention in Notes is human text that
mention-guard reports on the PR body (advisory for a bot-authored PR) and that never reaches
`main` under the `BLANK` squash message. Reported to the supervisor as a contract conflict; if
the owner wants neutralization, RELEASING.md changes first and the body gains it in a follow-up.

### Contract §9 choices recorded

- §9.1: title and body live in the resolver (see "Title and body").
- §9.2: retry budget and the `--expect` wait (see "Retry budget and `--expect`").
- §9.3: prereleases are candidates only when `--current` is a prerelease or with `--pre`, so the
  stable catalog line never moves onto an `-rc`.
- §9.4: every printed version is `v`-prefixed, unlike workspace `latest-tag.sh`.
- §9.5: `published oci` exists for the cli's docs-bundle check, which warns and never holds; the
  tag is used exactly as given (`docs/library:1.0.0-beta.3`).
- §9.8: `deps-cascade:breaking` is not computed here.
- §9.13: not followed; see "Notes pass through".

### Unknown or private GHCR packages

**Context**: an anonymous token request for a private package answers 403, the same as for a
missing one (research §3a).
**Decision**: `newest` exits 1 (the repo already pins the package, so it must exist and be
public); `published` exits 3 with a "may be private" warning (contract §2.4).
**Rationale**: a silently kept pin for a package someone forgot to make public is the failure
mode `templates.sh` already documents.

## Risks / Trade-offs

- **Hand-written SemVer** could be wrong at an edge → the full contract §2.10 order table runs
  in CI, plus the stub-agreement cases on every version shape OPM publishes.
- **`yq` on runners.** The contract states `ubuntu-latest` ships mikefarah `yq` v4; not
  verified on a runner here → the CI job prints `yq --version` first and the resolver exits 1
  without it, so a runner change fails loudly instead of misreading a file.
- **GHCR or proxy answer shapes change** → the live smoke workflow runs weekly against the real
  services and is never required, so drift shows up without blocking PRs.
- **The CLI is now an interface** for four repos and Phase 3 → any change to subcommands, exit
  codes or output needs a contract revision and the stub checksum in every copy.
- **Title and body in one place** (contract §9.1) means repo S5 tests need this resolver
  merged first; the merge order in contract §10 puts `.github` first.
- **Notes pass through** unchanged, so a human mention there stays a live mention each time the
  bot re-posts the body. Whether GitHub notifies again on an edit that keeps the same mention was
  not verified here; the body never reaches `main` either way.
- **README edits overlap** the sibling branch `docs/mention-guard-blank-squash`, which rewrites
  the mention-guard part of `README.md` and `mention-guard.yml`. The cascade section is appended
  after the `tag-ledger` section so the two merge cleanly; whichever merges second reruns
  `actionlint`, because `Resolver tests` lints every workflow.

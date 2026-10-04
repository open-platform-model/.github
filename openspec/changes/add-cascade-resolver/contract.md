# Phase 2 cascade contract (version 1.1)

Version 1.1 is version 1 plus the supervisor's clarifications C1 to C10 in §11 (2026-10-04).
Where §11 and an earlier section differ, §11 wins; the superseded passages are marked in place.
The stub (§7) and its checksum are unchanged and still say "contract version 1".

This contract binds five changes that are built in parallel:

| Repo | Change | Owns |
| --- | --- | --- |
| `.github` | `add-cascade-resolver` (runs `openspec init` first) | the resolver CLI, its stub, its tests, its CI check |
| `catalog_opm` | `add-deps-cascade-task` | `deps:cascade`, `deps:cascade:title`, `deps:cascade:body`, `deps:cascade:test`, `pins.sh`, `classes` |
| `library` | `add-deps-cascade-task` | same |
| `opm-operator` | `add-deps-cascade-task` | same |
| `cli` | `add-deps-cascade-task` | same |

The design source is workspace `RELEASING.md` (sections "The cascade", "What each repo's task
moves", "Gates", "Cascade files", "Rollout and changes"). Cite it as "workspace RELEASING.md,
section <name>" and cite this file as "Phase 2 cascade contract §N". Where this contract and
RELEASING.md disagree, RELEASING.md wins, and the agent reports the conflict to the supervisor
instead of picking. Known conflicts already reported are listed in §9.

Each repo change is written against this contract and the stub in §7, so it does not need the
real resolver to exist. The only exception is the title and body test (§8, scenario S5), which
runs once the real resolver is available.

---

## 1. Split of work

- **The resolver owns everything shared**: version lookups, semver, holds, frozen pins, the PR
  title and the PR body. One implementation, tested once.
- **Each repo owns its data and its file edits**:
  - `.tasks/cascade/pins.sh`, which reports the repo's logical pins;
  - `.tasks/cascade/classes`, the path-class map;
  - the `deps:cascade` script that moves pins;
  - the four Taskfile tasks in §5.
- `deps:cascade:title` and `deps:cascade:body` are thin wrappers that call the resolver's
  `title` and `body` subcommands with the repo's `pins.sh` and `classes`. This keeps the title
  and body format identical in every repo, which the Phase 3 receive workflow parses.

---

## 2. The resolver

### 2.1 Language, tools and location

- **Language.** Bash, with `curl`, `jq`, `git` and `yq`. `yq` means mikefarah `yq` v4
  (`ubuntu-latest` ships it; the workspace has v4.53.3). The resolver checks
  `yq --version` for `mikefarah` and exits 1 if it is missing. No Go, no Node.
- **Location** in the `open-platform-model/.github` repo:

  ```
  .github/scripts/cascade/cascade-resolve.sh   # the CLI (executable); sources lib/
  .github/scripts/cascade/lib/*.sh             # semver, http, ghcr, goproxy, release, files, title, body
  .github/scripts/cascade/stub-resolve.sh      # the canonical stub, byte-identical to §7
  .github/scripts/cascade/test/run.sh          # offline test suite; exit 0 pass, 1 fail
  .github/scripts/cascade/test/shim/{curl,git} # PATH shims that answer from fixtures (§2.10)
  .github/scripts/cascade/test/fixtures/       # canned HTTP and git answers (§2.10)
  .github/workflows/cascade-resolver.yml       # job name: "Resolver tests"
  .github/workflows/cascade-resolver-live.yml  # non-required live smoke (§2.11)
  openspec/                                     # from `openspec init`
  ```

  The path really is `.github/.github/scripts/...` in the workspace, because the repo is named
  `.github` and holds a `.github/` directory.
- **Style.** Follow `tag-ledger.sh` (`set -euo pipefail`, `die()` to stderr). `shellcheck`
  clean.

### 2.2 Common conventions

- **Versions** are always printed and accepted in full `v`-prefixed SemVer form: `v2.0.0-beta.2`,
  `v4.5.1`, `v1.0.0-beta.7`. This differs from `latest-tag.sh`, which prints a bare version.
  Callers add the `v` before calling, for pins stored bare (the samples' `version: "4.4.4"`,
  identity `Version: "1.0.3"`), and remove it when writing back. The one exception is the `oci`
  kind's tag argument (§2.4), which is used exactly as given.
- **A valid version** matches
  `^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$`.
  Anything else in an upstream list is ignored. Malformed input to an argument is exit 2.
- **Never a candidate:**
  - CUE dev builds: any version containing `-0.dev.` or `-dev.`;
  - Go pseudo-versions: ending in `[0-9]{14}-[0-9a-f]{12}`;
  - build metadata: `+...` is stripped before comparing; a tag that differs only in build
    metadata is a duplicate.
- **Stdout** carries only the answer. **Stderr** carries diagnostics, prefixed
  `cascade-resolve: `.
- **Warnings.**
  - Every warning is printed to stderr as `cascade-resolve: warning: <message>`.
  - When `CASCADE_WARNINGS` is set, the resolver also appends one line to that file:
    `<pin-key><TAB><message>`, with the pin key from the §2.4 table (never the bare
    coordinate of a `release` or `opm-cli` query).
  - Messages put every version, module path and file path in backticks, and never contain an
    `@` that is not preceded by a word character (§4.4).
- **`--repo-root DIR`** defaults to the current directory. `.cascade-hold` and `.cascade-frozen`
  are read from there. A missing file means an empty file.
- **No credentials.** The resolver never sends a token anywhere and never calls
  `api.github.com`. GHCR is read with the anonymous pull token. GitHub releases are read with
  `git ls-remote` and anonymous download `HEAD` requests. It needs no secrets, which suits the
  Phase 3 `compute` job.

### 2.3 Exit codes (all subcommands)

| Code | Meaning |
| --- | --- |
| 0 | Success. For `newest`: a version newer than `--current` is printed and the pin should move. For predicates (`published`, `is-frozen`, `hold`): yes. |
| 3 | Nothing to do, or "no". For `newest`: stay at `--current`, stdout empty. For predicates: no. For `title`: the diff is empty. |
| 1 | Error: network failure after retries, an unexpected HTTP status, a malformed `.cascade-*` file, a missing tool, a lint failure. Never falls back to an older or a guessed version. |
| 2 | Usage error: unknown subcommand or flag, missing argument, malformed version argument. |

A new major is never an exit code. It is a warning (§2.6).

### 2.4 Query kinds

| Kind | Coordinate | Pin key (holds, frozen, warnings) | Candidates from | "Published" means |
| --- | --- | --- | --- | --- |
| `cue` | `<module path>@v<N>`, as written in `cue.mod/module.cue` (`opmodel.dev/core@v2`, `testing.opmodel.dev/modules/cli/podinfo@v0`) | the coordinate | GHCR tags list of `open-platform-model/<module path without @vN>` | `HEAD /v2/<repo>/manifests/<v>` with `Accept: application/vnd.oci.image.manifest.v1+json` answers 200 |
| `go` | the module path (`github.com/open-platform-model/library`); a `/vN` suffix is required for N ≥ 2 | the module path | `$GOPROXY_BASE/<path>/@v/list` (never `@latest`, which skips prereleases) | `GET .../@v/<v>.info` answers 200 |
| `release` | a repo name under `open-platform-model` (`opm-operator`), plus one or more `--asset NAME` | `github.com/open-platform-model/<repo>` | `git ls-remote --tags --refs https://github.com/open-platform-model/<repo> 'refs/tags/v*'` | every asset answers 200 to an anonymous `HEAD -L` at `https://github.com/open-platform-model/<repo>/releases/download/<v>/<asset>`. A draft and an asset-less release both answer 404. |
| `opm-cli` | none | `github.com/open-platform-model/cli` | as `release cli` | `release cli --asset opm-linux-amd64.tar.gz --asset checksums.txt` |
| `oci` (only for `published`) | an image repo path under ghcr.io (`open-platform-model/docs/library`) | the path | none | `HEAD` of the manifest at the given tag, with `Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json`, answers 200. The tag is used exactly as given: no `v` is added and none is required (the docs bundles are tagged bare, `docs/library:1.0.0-beta.3`). |

GHCR details:

- Token: `GET https://ghcr.io/token?scope=repository:<repo>:pull&service=ghcr.io`.
- Tags: `GET https://ghcr.io/v2/<repo>/tags/list?n=1000`, following `Link: <...>; rel="next"`.
  More than 20 pages is exit 1.
- A token answer of 403 or 404, or a tags answer of 404 (`NAME_UNKNOWN`), means "unknown or
  private package":
  - `newest` exits 1, because the repo already pins it, so it must exist;
  - `published` exits 3 with a warning that the package may be private.

Proxy details: `GOPROXY_BASE` is `CASCADE_GOPROXY`, defaulting to `https://proxy.golang.org`.
A 404 or 410 on `.info` means "not published yet". A 404 or 410 on a `@v/list` used for the
new-major probe (§2.6) means "no new major" (live: `library/v2/@v/list` answers 404).

### 2.5 Ordering and candidate rules

- **Order** is SemVer 2.0.0 precedence, implemented once as `semver_cmp` in `lib/semver.sh`:
  - compare major, minor and patch numerically;
  - a version without a prerelease ranks above the same version with one;
  - prerelease identifiers are compared left to right: two numeric identifiers numerically, two
    alphanumeric identifiers in ASCII order, and a numeric identifier always ranks below an
    alphanumeric one; a longer list ranks above its own prefix;
  - build metadata is ignored.

  The `sed 's/-/~/' | sort -V` trick does not implement the numeric-versus-alphanumeric rule
  (`v1.0.0-alpha.beta` vs `v1.0.0-alpha.1`), so the real resolver MUST NOT use it. The stub
  (§7) still uses it; the stub-agreement test excludes those cases (§2.10). A hand-rolled `jq`
  comparator is forbidden; it got `v2.0.0` wrong in research.
- **Major restriction.** Candidates are only versions whose major equals the major of
  `--current`. For `cue`, the coordinate's `@vN` must agree with that major, or it is exit 2.
- **Prereleases.**
  - If `--current` is a prerelease, prereleases are candidates. This covers the beta lines:
    core, library, the operator and the cli.
  - If `--current` is a release, only releases are candidates, unless `--pre` is passed. This
    covers the stable opm catalog `v4.x` and the fixtures and templates.
- **Never backwards.**
  - Candidates are the in-major versions strictly greater than `--current`, newest first.
  - The resolver checks at most the 10 newest for "published". The first one that is published
    is the newest. An unpublished candidate is skipped with a stderr line.
  - If the cap of 10 was reached and none of the 10 is published, it is exit 1, because
    something is wrong upstream.
  - If there are fewer than 10 candidates and none is published, it is exit 3, with the
    warning "no published version newer than `<current>`; newest tagged `<v>` is not published
    yet".
  - If no candidate is greater than `--current`, it is exit 3.
  - If `--current` is newer than every published version, it is exit 3, with the warning
    "`<current>` is newer than the newest published `<v>`".
- **Hold.** See §2.8. The target is `min(newest, hold max)`. If the target is not greater than
  `--current`, it is exit 3.

### 2.6 Subcommands

```
cascade-resolve.sh newest <kind> [<coordinate>] --current <v> [--asset NAME]... [--pre]
                          [--repo-root DIR] [--expect <v>] [--max-wait SECONDS] [--json]
cascade-resolve.sh published <kind> [<coordinate>] <v-or-tag> [--asset NAME]...
cascade-resolve.sh pin-of <module>@v<N> <v> <dep-module>@v<M>
cascade-resolve.sh language-of <module>@v<N> <v>
cascade-resolve.sh frozen <pin-key> [--repo-root DIR]
cascade-resolve.sh is-frozen <repo-relative-path> <pin-key> [--repo-root DIR]
cascade-resolve.sh hold <pin-key> [--repo-root DIR]
cascade-resolve.sh check-files [--repo-root DIR]
cascade-resolve.sh semver-cmp <a> <b>
cascade-resolve.sh semver-sort            # stdin, one version per line; stdout ascending
cascade-resolve.sh next-patch <v>
cascade-resolve.sh classify --classes FILE           # stdin paths; stdout "<class>\t<path>"
cascade-resolve.sh title --classes FILE --pins SCRIPT [--base REF] [--repo-root DIR]
cascade-resolve.sh body  --classes FILE --pins SCRIPT [--base REF] [--repo-root DIR]
                         [--warnings FILE]
```

#### `newest`

- Prints the target on exit 0, and nothing on exit 3.
- **New major.** It also checks whether any published version of major + 1 exists: the same
  GHCR repo or git tags; on the proxy, `<path>/v<N+1>/@v/list`, except that the probe from Go
  major 0 to 1 uses the unsuffixed path (Go has no `/v1`). If one exists, it warns "new major
  available: `<v>`", adding "(prerelease)" when it is one. It never moves to it.
- **`--json`** is for humans and the Phase 3 workflow only. Repo tasks MUST NOT use it, because
  the stub does not support it. Its shape:

  ```json
  {"pin": "...", "kind": "...", "current": "...", "newest": "...", "target": "...",
   "moved": true, "hold": {"max": "...", "expires": "..."}, "newer_major": "...",
   "warnings": ["..."]}
  ```

  `hold` and `newer_major` are `null` when absent.

#### `published`

Exits 0 if that exact version is published, 3 if not, and 1 on error.

#### `pin-of`

Prints the version that `<module>@<v>` itself pins for `<dep-module>`. This is the consistent-set
helper: the core version a given catalog release pins.

- It reads the module's GHCR manifest. It takes the layer with media type
  `application/vnd.cue.modulefile.v1` and fetches `/v2/<repo>/blobs/<digest>`, which is a plain
  `module.cue`.
- It extracts `"<dep-module>": { v: "<version>" }`. Parse with `cue` if it is on `PATH`,
  otherwise use the `grep -FA5 '"<dep>"' | grep -oP 'v:\s*"\K[^"]+'` idiom.
- Exit 3 if the dep is absent. Exit 1 on error.

#### `language-of`

Prints `language.version` from the same module file. Exit 3 if the file has none.

#### `semver-cmp`

Prints exactly one of `-1`, `0` or `1` on stdout and exits 0. A malformed argument is exit 2.

#### `title` and `body`

See §4.

### 2.7 `.cascade-frozen` reader

- **Schema** (RELEASING.md "Cascade files"): `frozen:` is a list of `{path, pins, reason}`.
  `path` is a non-empty, repo-relative file or directory with no leading `/` and no `..`. `pins`
  is a non-empty list of pin keys. `reason` is a non-empty string. Unknown keys are an error.
- **A trailing `/`** on `path` is stripped before matching (the stub does the same).
- **`frozen <pin-key>`** prints every `path` whose `pins` contains the key, one per line. It
  exits 0 even when there are none.
- **`is-frozen <path> <pin-key>`** exits 0 when some entry lists the key and its `path` equals
  `<path>` or is a directory prefix of it (`entry + "/"` is a prefix of `<path>`). Otherwise it
  exits 3. Callers always pass the file they are about to edit (`<dir>/cue.mod/module.cue`,
  never `<dir>`), so a file entry matches.
- A malformed file is exit 1 for every subcommand that reads it.

### 2.8 `.cascade-hold` reader

- **Schema:** `holds:` is a list of `{pin, max, reason, expires}`. `max` is a valid version.
  `expires` is `YYYY-MM-DD`. All four keys are required. Unknown keys are an error.
- **In date** means today is on or before `expires`. Today is the UTC date
  (`date -u +%F`), or `CASCADE_TODAY` when set (for tests).
- **`hold <pin-key>`**:
  - an in-date hold prints `max` and exits 0;
  - an expired hold prints nothing, exits 3 and warns "hold on `<pin>` expired `<date>`; moving
    again";
  - no entry exits 3.
- **Inside `newest`:**
  - an in-date hold caps the target at `max`, and the resolver warns "held at `<max>` until
    `<expires>`: <reason>" whenever the newest is above `max`;
  - a hold with `max` below `--current` never moves the pin down: the result is exit 3, with the
    warning "hold `max` `<max>` is below the current pin `<current>`".
- **Several entries for one pin** are exit 1.
- **`check-files`** validates both files and exits 0 or 1. Every repo task calls it first.

### 2.9 Retry, timeouts and `--expect`

- **Every request** uses exactly this curl shape, which the test shim (§2.10) implements and
  nothing else:

  ```
  curl -q -sS --connect-timeout 10 --max-time 60 -o <body-file> -D <header-file>
       -w '%{http_code}' [-I] [-L] [-H <header>]... <url>
  ```

  - `-q` must be the first argument, so `~/.curlrc` never applies;
  - no curl `--retry`, because the resolver does its own retries so they are testable.
- **Transient answers:** status `000` (no connection or a timeout), `429` and `5xx`. They are
  retried up to 4 attempts in all, sleeping 2, 4 and 8 seconds between them. After that it is
  exit 1. The sleep command is `${CASCADE_SLEEP:-sleep}`, so tests can fake it.
- **Not-published answers:** a 404, or a 410 on the proxy. These are never retried.
- **Any other status** is exit 1 with "answered `<code>`; refusing to guess".
- **`--expect <v>`** is a hint from the dispatch payload. The payload is untrusted, so it is
  never part of the answer.
  - It applies only when `<v>` is a valid version, in-major, greater than `--current`, allowed by
    the prerelease rule (§2.5), and not above an in-date hold's `max`. Otherwise it is ignored
    with a stderr line.
  - When it applies and `<v>` is not published yet, `newest` polls `published <kind> <coord> <v>`
    every 30 seconds until it answers 0, or until `--max-wait` seconds have passed (default
    `${CASCADE_MAX_WAIT:-600}`). It does not consult the candidate list for this: a library tag
    is often missing from the proxy `@v/list` right after `release-please` runs.
  - After the wait (or when `<v>` was already published), `newest` makes its normal pass. The
    answer is always the newest published candidate, never `<v>` itself unless it is that.
  - When the wait runs out, it warns "expected `<v>` is not published after `<n>`s" and answers
    with what is published. That is not an error, because the daily sweep catches up.
  - Without `--expect`, it makes a single pass.
  - Phase 2 repo tasks pass `--expect` only when the env `CASCADE_EXPECT` names this pin (§5.4).

### 2.10 Offline mode and the resolver's own tests

- **Fixture mode is a PATH shim, not resolver code.** `test/run.sh` puts `test/shim/` first on
  `PATH` and sets `CASCADE_FIXTURE_DIR=<dir>`. The resolver itself has no fixture branch; it
  calls `curl` and `git` as in production.
  - The `curl` shim accepts only the §2.9 shape (anything else is exit 2), appends its full
    argument vector to `$CASCADE_FIXTURE_DIR/curl.log`, and answers a `GET` or `HEAD` of
    `https://<host>/<path>?<query>` from `<dir>/http/<host>/<path>`, with `?` written as `%3F`
    (`<dir>/http/ghcr.io/v2/open-platform-model/opmodel.dev/core/tags/list%3Fn=1000`).
  - The status comes from `<file>.status`. It defaults to 200 if the body file exists, and 404
    otherwise.
  - Response headers come from `<file>.headers`, which is how pagination `Link` headers are
    given.
  - A status file may hold several lines. They are consumed one per request, and the last line
    repeats. This is how retries are tested.
  - The `git` shim answers `git ls-remote` of a repo from `<dir>/git/<repo>.refs`, in ls-remote
    output format, and passes every other subcommand to the real `git` (the `title` and `body`
    tests need it).
- **`CASCADE_TODAY`** and **`CASCADE_SLEEP`** (above) make holds and retries deterministic.
- **`test/run.sh`** is a table test. Its fixtures are captured from the real answers in the
  research (core v2 tags with `-0.dev.` interleaved, `catalogs/opm` v4, the proxy list for
  `library`, cli and operator refs, and the `catalogs/opm` v4.5.1 modulefile). Required cases:
  - `alpha.2` < `alpha.10`; `beta.10` > `beta.2`; `v2.0.0` > `v2.0.0-beta.10`;
    `rc.1` > `beta.9`; build metadata ignored;
  - `v1.0.0-alpha.beta` > `v1.0.0-alpha.1`; `v1.0.0-alpha.1` < `v1.0.0-alpha.a`;
    `v1.0.0-alpha` < `v1.0.0-alpha.1`; `semver-cmp` prints `-1`, `0` or `1` and exits 0;
  - `-0.dev.` and `-dev.` are excluded, and so are pseudo-versions;
  - the major restriction holds with a v3 present, and the new-major warning is printed
    (prerelease and release); a proxy `v2/@v/list` 404 gives no warning;
  - the stable-current rule: no prerelease unless `--pre`;
  - an unpublished newest keeps the pin (exit 3); a skip to an older published candidate that
    is still newer than the current one; 3 candidates all unpublished give exit 3 with the
    warning; 10 or more candidates with the newest 10 unpublished give exit 1;
  - never backwards when the current is newer than the newest published;
  - a hold that caps, an expired hold, a hold below the current, a duplicate hold, a hold
    missing `reason`;
  - frozen: an exact file, a directory prefix, a trailing `/`, `dir2` not matched by `dir`, a
    file entry not matched by its parent directory, malformed entries;
  - `pin-of` from a canned modulefile; dep absent gives 3;
  - GHCR token 403 and tags 404: `newest` gives 1, `published` gives 3;
  - `published oci` sends both `Accept` types and uses the tag as given;
  - a 5xx then 200 recovers; four 5xx give exit 1; a 429 retries;
  - a GHCR `Link` pagination walk; 21 pages give exit 1;
  - a draft or asset-less release is skipped; a missing second asset is skipped;
  - `--expect` on a version absent from the `@v/list` that becomes published on the third poll;
    `--expect` that never appears (a warning and the published answer, with a fake clock);
    `--expect` above a hold, or a prerelease against a stable current, is ignored;
  - `curl` is always called with `-q` first (asserted from `curl.log`);
  - warnings for `release` and `opm-cli` queries are keyed `github.com/open-platform-model/<repo>`;
  - `title`, `body` and `classify` against a throwaway git repo built in the test, covering
    every rule in §4, including the mention lint failing on a planted bare `@word` in the
    generated part, and a `@user` in Notes passing through neutralized with a warning
    (superseded by §11 C1: the `@user` passes through byte for byte, with no warning);
  - the stub: `sha256sum stub-resolve.sh` equals the §7 checksum, and for every stub-supported
    case the stub and the real resolver in fixture mode agree on exit code and stdout. Excluded
    from the agreement: prerelease identifiers mixing numeric and alphanumeric forms (the stub's
    sort trick is wrong there), duplicate holds (the stub takes the first, the resolver exits 1),
    holds inside `newest`, and warnings text.

### 2.11 The `.github` CI check

- **`cascade-resolver.yml`:**
  - triggers on `pull_request` and on `push` to `main`, with **no path filter**, so that the
    required check reports on every PR;
  - one job named `Resolver tests`, with `timeout-minutes: 10` and
    `permissions: contents: read`;
  - steps: checkout (SHA-pinned, as in `tag-ledger.yml`), `shellcheck` on every file from
    `find .github/scripts/cascade -name '*.sh' -print0` plus `test/shim/curl` and
    `test/shim/git` (no `**` glob, which needs `globstar`), then `test/run.sh`.
- This is the check that RELEASING.md "Rulesets on main" will require on `.github`.
- **`cascade-resolver-live.yml`** runs on `workflow_dispatch` and weekly. It is never
  required. It runs read-only invariants against the real services:
  - `newest cue opmodel.dev/core@v2 --current <the newest real version it finds>` gives 3;
  - the result is in-major and not a dev build;
  - `published opm-cli <newest>` gives 0.

---

## 3. Finding the resolver

Every repo task finds the resolver the same way, in this order:

1. The env `CASCADE_RESOLVER`, if set: an absolute path to `cascade-resolve.sh`, or to a stub.
   A relative path is an error.
2. Otherwise, the local workspace default: the main checkout of this repo (the parent of
   `git rev-parse --path-format=absolute --git-common-dir`), then
   `../.github/.github/scripts/cascade/cascade-resolve.sh` from there. Using the common dir
   makes this work inside `.claude/worktrees/*` too.

The variable is declared **at task level on each of the four cascade tasks**, never as a global
`vars:` entry (a global `sh:` var runs for every task, and outside a git checkout it prints
`fatal:` noise and yields a relative path). A YAML anchor shared by the four tasks is fine:

```yaml
vars:
  CASCADE_RESOLVER_PATH:
    sh: |
      if [ -n "${CASCADE_RESOLVER:-}" ]; then
        case "$CASCADE_RESOLVER" in /*) ;; *) echo "CASCADE_RESOLVER must be absolute" >&2; exit 1 ;; esac
        printf '%s\n' "$CASCADE_RESOLVER"; exit 0
      fi
      common=$(git rev-parse --path-format=absolute --git-common-dir) || exit 1
      printf '%s\n' "$(dirname "$common")/../.github/.github/scripts/cascade/cascade-resolve.sh"
```

- A failing `sh:` var stops the task, so a checkout without git fails loudly instead of
  producing a relative path.
- Every cascade task exports `CASCADE_RESOLVER: '{{.CASCADE_RESOLVER_PATH}}'` to its script.
- Every cascade task has the precondition `test -x '{{.CASCADE_RESOLVER_PATH}}'`, with the
  message "cascade resolver not found: check out open-platform-model/.github beside this repo,
  or set CASCADE_RESOLVER".

**In CI** (Phase 3 fixes this; Phase 2 only reserves it):

- The receive workflow checks out the repo at `$GITHUB_WORKSPACE/repo`.
- It checks out `open-platform-model/.github` at `ref: main`, `path: org-github`, with
  `persist-credentials: false`. It is never inside the repo checkout, so it can never show up in
  the repo's diff.
- It sets `CASCADE_RESOLVER=$GITHUB_WORKSPACE/org-github/.github/scripts/cascade/cascade-resolve.sh`.

**Invoking a task.** go-task turns any failing command into exit 201, unless it is run with
`-x` / `--exit-code` (checked on task 3.52.0: `exit 3` gives 201 plain and 3 with `-x`). Every
caller, including tests, the Phase 3 workflow and humans checking the gate, MUST run
`task -x deps:cascade` (and `-x` for title and body) to see 0, 3 or other.

---

## 4. Title, body and class map (implemented once, in the resolver)

### 4.1 Inputs every repo provides

**`.tasks/cascade/classes`** is the path-class map. Each line is `<class> <pattern>`. `#` starts
a comment, and blank lines are ignored. The classes are `release-tool`, `test` and `shipped`.
The first matching line wins. **A path that matches no line is `shipped`.** Pattern forms:

| Form | Matches |
| --- | --- |
| `dir/` (ends in `/`) | every path under `dir/` |
| `a/b.yaml` (has a `/`, no `*`) | exactly that path |
| `name` (no `/`, no `*`) | exactly that root-level path |
| `*_test.go` (no `/`, has `*`) | a basename glob, at any depth |
| `**/name/` | any path with a directory segment `name` at any depth, including the root |

**`.tasks/cascade/pins.sh <ref>`** is an executable script.

- `<ref>` is `WORKTREE` (read files on disk) or a git ref (read with `git show <ref>:<path>`).
- It prints one TSV line per logical upstream pin:
  `<pin-key>\t<display>\t<class>\t<version>\t<labels>`.
  - `version` is `v`-prefixed.
  - `labels` is a comma-separated list, or empty. These labels apply when that pin moved.
  - A pin missing at that ref is omitted.
- It exits 0, or 1 on error.
- It lists upstream pins only. A repo's own fixture or template versions are not pins.

### 4.2 Base and diff

- **Base ref:** `--base`, otherwise the env `CASCADE_BASE`, otherwise `origin/main`.
- **Compare point:** `M = git merge-base <base> HEAD`.
- **Changed paths:** `git diff --name-only M` (committed and uncommitted tracked changes),
  plus untracked files that are not ignored (`git ls-files --others --exclude-standard`).
- **Moved pins:** run `pins.sh M` and `pins.sh WORKTREE`. A pin moved when its key is in both
  and the versions differ. The order is the order of `pins.sh WORKTREE`.

### 4.3 `title`

- **Type:**
  - `fix(deps)` if any changed path classifies as `shipped`;
  - else `test(fixtures)` if any is `test`;
  - else `ci(deps)` if any is `release-tool`.
  - No changed paths: print nothing, exit 3.
- **Subject:**
  - one moved pin: `bump <display> to <to>`;
  - two: `bump <A> to <a> and <B> to <b>`;
  - three: `bump <A> to <a>, <B> to <b> and <C> to <c>`;
  - four or more: `bump <N> upstream pins`;
  - none moved but paths changed: `refresh cascade-managed files`.
- The output is exactly `<type>: <subject>`, one line.
- `<to>` is `v`-prefixed. RELEASING.md's example "opm catalog to 4.4.5" is illustrative; the
  `v` form is the contract.
- It never emits `!` and never a type other than those three. Keeping a human retitle, and
  never lowering a type, is the Phase 3 workflow's job, done through the marker in §4.4.

### 4.4 `body`

Output is exactly this layout. It is deterministic: no timestamps, and the same inputs give the
same bytes.

```markdown
<!-- cascade-title: <title as §4.3> -->
<!-- cascade-labels: <comma list, or empty> -->
## Moved pins

| Pin | Class | From | To |
| --- | --- | --- | --- |
| <display> (`<pin-key>`) | <class> | `<from>` | `<to>` |

Changed files: <n> shipped, <n> test, <n> release-tool.

## Triggering releases

- `<source>` `<tag>`

## Warnings

- `<pin-key>`: <message>

## Notes

<!-- cascade-notes: the bot keeps everything below this line -->
<contents of CASCADE_NOTES_FILE, byte for byte (§11 C1), if set and non-empty>
```

- **Moved pins.** With no moved pin, the table has one row:
  `| none | - | - | - |`.
- **`cascade-labels`** is the union of the `labels` column of the moved pins. For example,
  library's core row carries `need-human-review`. `deps-cascade:breaking` is NOT computed in
  Phase 2; the Phase 3 workflow adds it.
- **Triggering releases** come from the env `CASCADE_SOURCE` (one of `core`, `catalog_opm`,
  `library`, `opm-operator`, `cli`) and `CASCADE_TAGS` (space-separated).
  - Each tag must match `^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$`. Anything else is dropped, with a
    warning.
  - With nothing valid, the section is the single line
    `- None recorded (daily sweep or manual run).`.
- **Warnings** come from `--warnings`, which defaults to `<git-dir>/cascade/warnings`.
  - Lines are de-duplicated, keeping the first occurrence.
  - A pin key of `-` renders without the key prefix.
  - With none, the section is `- None.`.
- **`## Notes`** is always the last section. The Phase 3 workflow carries over the existing
  PR's Notes content through `CASCADE_NOTES_FILE`. *Superseded by §11 C1: Notes are copied byte
  for byte, neither linted nor neutralized, and no warning is added; the rest of this bullet is
  version 1 text.* Notes are human text, so they are not linted:
  every `@` that matches the mention pattern below gets a zero-width joiner (U+200D) inserted
  right after it, and the body adds the warning "`-`: neutralized <n> mention(s) in Notes". The
  insertion is idempotent, because a neutralized `@` no longer matches.
- **Mention lint.** Before printing, `title` and `body` check everything they generate (the
  whole title; the body above the `cascade-notes` marker line) against the mention-guard
  pattern `(?<![\w@])@[A-Za-z0-9]` (`grep -P`). A match is exit 1, naming the line.
  `opmodel.dev/core@v2` passes, because the `@` follows a word character.

---

## 5. The per-repo task interface

### 5.1 Tasks

Every repo adds the following tasks (in `Taskfile.yml`, or in an included `.tasks/*.yaml`, as
long as the invoked name is exactly as below):

| Task | Does | Exit |
| --- | --- | --- |
| `deps:cascade` | runs `.tasks/cascade/cascade.sh`; moves pins in the working tree only (no commit, no push, no branch) | 0 if the working tree changed, 3 if not, other on error |
| `deps:cascade:title` | `"$CASCADE_RESOLVER" title --classes .tasks/cascade/classes --pins .tasks/cascade/pins.sh` | as §4.3 |
| `deps:cascade:body` | `"$CASCADE_RESOLVER" body --classes .tasks/cascade/classes --pins .tasks/cascade/pins.sh` | 0, or 1 on error |
| `deps:cascade:test` | runs `.tasks/cascade/test.sh` (§8) | 0 pass, 1 fail |

All scripts live under `.tasks/cascade/`: `cascade.sh`, `pins.sh`, `classes`, `test.sh`,
`testdata/stub-resolve.sh` (§7), `testdata/older.tsv` and `testdata/s1-calls.txt` (§8).

### 5.2 Rules every `deps:cascade` follows

1. **Clean start.** It refuses (exit 1) when `git status --porcelain --untracked-files=all` is
   non-empty, unless `CASCADE_ALLOW_DIRTY=1`. With `CASCADE_ALLOW_DIRTY=1` it records a
   snapshot at the start and compares at the end (rule 13):

   ```bash
   snapshot() {
     { git status --porcelain --untracked-files=all
       git diff HEAD --binary
       git ls-files -z --others --exclude-standard | xargs -0 -r sha256sum
     } | sha256sum
   }
   ```

2. **State directory.** `STATE=$(git rev-parse --git-dir)/cascade`; `mkdir -p` it, and truncate
   `$STATE/warnings`. Export `CASCADE_WARNINGS=$STATE/warnings`, so the resolver appends there.
   The repo's own warnings use the same `<pin-key>\t<message>` format. Helper binaries (the opm
   CLI, rule 11) go under `$STATE/bin`, never in the tree.
3. **Validate the steering files.** Run `"$CASCADE_RESOLVER" check-files --repo-root .` first.
4. **Registries.** It sets its own registry env and never inherits a local default:
   - `CUE_REGISTRY` and `OPM_REGISTRY` are set to
     `opmodel.dev=ghcr.io/open-platform-model,registry.cue.works`;
   - the cli and the operator add `testing.opmodel.dev=ghcr.io/open-platform-model,` in front
     (both resolve `testing.opmodel.dev/modules/<repo>/*` fixtures);
   - the operator Taskfile's local `localhost:5000` default must not leak in.
5. **Resolve everything, then edit.** The task runs in three phases:
   - **A, resolve.** Every resolver call that decides a target (`newest`, `pin-of`, `hold`)
     runs before any file is edited. For each pin it calls
     `newest ... --current <pin now> --repo-root .` and handles the exit with a `case`:
     `0` means move to the printed version; `3` means leave it; anything else exits the task
     with that failure. An error in phase A therefore leaves the tree unchanged.
   - **B, tools.** If any pin will move, prepare the opm CLI binary (rule 11) from the
     unmodified tree.
   - **C, edit**, in the order of rule 12. A failure in phase C exits non-zero and may leave a
     partly edited tree; callers discard the tree on any exit other than 0 or 3.

   No `|| true`, no `2>/dev/null ||` fallbacks, and no `set +e` around resolver or tool calls.
6. **Explicit versions only, and only where something moved.**
   - `cue mod get` names only `opmodel.dev/*` and `testing.opmodel.dev/*` deps, each as
     `<module>@<exact resolved version>`, never a bare major.
   - `cue mod get` and `cue mod tidy` run only in a module where at least one pin moved, and
     `tidy` runs once per such module. A module where nothing moved is never touched, so a run
     with nothing to move leaves even an untidy `module.cue` alone.
   - `go get <module>@<exact version>`, then `go mod tidy`, only when a Go pin moved.
   - Third-party pins (`cue.dev/x/k8s.io@v0`, `cuelang.org/go`, k8s, Flux, `CUE_VERSION`,
     kind) are never named. If `tidy` raised a third-party pin, that is a warning, not a revert.
7. **Consistent set.** Where a file pins a catalog and core together, catalog_opm excepted:
   - the catalog moves to `newest cue opmodel.dev/catalogs/opm@v4`;
   - `C` = the catalog target if it moved, otherwise the file's current catalog version (so
     core still converges when the catalog does not move);
   - core goes to `pin-of opmodel.dev/catalogs/opm@v4 C opmodel.dev/core@v2`, but only if that
     is greater than the file's current core. Otherwise core stays, with the warning "core
     `<cur>` is ahead of the core `<x>` that catalog `<C>` pins" (see §9.10);
   - **files that pin core but no catalog** (operator `test/fixtures/catalogs/provider`, cli
     `tests/fixtures/valid/*`) take core from the same rule, with `C` = the repo's
     representative catalog (§6), never from `newest cue opmodel.dev/core@v2`;
   - **holds.** Core derived through `pin-of` honours `hold opmodel.dev/core@v2`. If an in-date
     hold `max` is below the `pin-of` value, the catalog cannot move without raising core (MVS
     raises it anyway), so the catalog stays at its current version and core stays too, with the
     warning "catalog `<t>` needs core `<c>`, above the hold `<max>`; catalog held too";
   - library is different (§6.2).
8. **Frozen pins.**
   - Before any text edit of a version literal, it calls `is-frozen <file> <pin-key>` with the
     exact repo-relative file it is about to edit. Exit 0 means skip that file for that pin.
   - Before `cue mod get` in a module, it calls `is-frozen <dir>/cue.mod/module.cue <pin-key>`
     for each key it would name (never `is-frozen <dir>`). A frozen key is left out of the
     `get`.
   - After `tidy` in a module, it checks that the `v:` of every key frozen for that file is
     byte-unchanged. `cue mod get` of another key can raise a frozen one by MVS; if that
     happened, it exits 1 naming the file and the key ("freeze the whole module, or hold the
     upstream").
9. **New majors.** These come only from the resolver's warning. The task never edits an import
   path or a `@vN` key.
10. **`language.version`.** For each moved CUE upstream, compare `language-of <module> <target>`
    with the repo's pinned CUE version (RELEASING.md "What each repo's task moves": "the local
    `CUE_VERSION`"), never with the `cue version` on `PATH`. The pinned version is read from
    one file each repo names in its `design.md`: the `CUE_VERSION` workflow env where a
    workflow sets one (catalog_opm `branch-publish.yml`, opm-operator `test.yml`), otherwise
    the `cue` version its required PR CI installs (library `cue.yml`, cli `pr.yml`). If the
    upstream is newer, warn. Exit 3 from `language-of` means no warning. If the pinned version
    cannot be read, warn with key `-` and continue.
11. **Version advance happens once per PR** (fixtures, the cli templates, the operator's provider
    catalog). For each such module `F`, with identity file `I`:
    - `M` = `git merge-base "${CASCADE_BASE:-origin/main}" HEAD`.
    - `B` = `M`'s declared version in `I` (`git show M:<I>`, the `^Version:` line).
    - `F` changed is decided by this shared function, copied as is into every repo's
      `cascade.sh`:

      ```bash
      # f_changed M FDIR IFILE: exit 0 when FDIR differs from M in any path other than
      # IFILE, or when IFILE differs from M outside its ^Version: line; exit 1 otherwise.
      f_changed() {
        local m="$1" d="$2" i="$3" p
        while IFS= read -r p; do
          [ "$p" = "$i" ] || return 0
        done < <({ git diff --name-only "$m" -- "$d"
                   git ls-files --others --exclude-standard -- "$d"; } | sort -u)
        git cat-file -e "$m:$i" 2>/dev/null || return 0
        if diff -q <(git show "$m:$i" | grep -v '^Version:') \
                   <(grep -v '^Version:' "$i") >/dev/null; then
          return 1
        fi
        return 0
      }
      ```

    - The target is: `B` if `F` did not change; else `next-patch(B)` if
      `published cue <F module>@vN v<B>` answers 0; else `B`, because `B` is still pending and
      unpublished, so it is not bumped again.
    - Write the target with the opm CLI's own setter (`opm module version set <ver> <dir>`, or
      `opm catalog version set` for a catalog fixture), only when it differs from the file.
    - The binary is prepared in phase B (rule 5), before any pin edit, so a library move that
      breaks compilation cannot stop the task from producing its diff:
      - the operator runs `GOBIN=$STATE/bin go install github.com/open-platform-model/cli/cmd/opm@<current .opm-cli-version>`;
      - the cli runs `go build -o $STATE/bin/opm ./cmd/opm` from the unmodified tree.
    - Running the task twice must give the same file. That is the idempotence check in §8.
12. **Writing order.** Shipped pins first, then test pins and fixtures, then version advances,
    then fixture consumers, then the repo's regenerators (`go mod tidy`; cli `operator:sync`),
    and `.opm-cli-version` last.
13. **The result.** Exit 0 if the working tree changed, otherwise exit 3. "Changed" means
    `git status --porcelain --untracked-files=all` is non-empty, or, under
    `CASCADE_ALLOW_DIRTY=1`, that `snapshot` (rule 1) differs from the start.
14. **Never touches:**
    - `.cascade-frozen` and `.cascade-hold`;
    - `.release-please-manifest.json`, `release-please-config.json` and `CHANGELOG.md`;
    - anything under `.github/`;
    - `.opm-docs-version` and docs-kit refs;
    - catalog_opm's `src/identity/identity.cue` and `src/RELEASE`;
    - `cue-versions.yml`;
    - any `language.version`.
15. **Network** is used read-only. The task never publishes and never runs a `publish` or
    `seed` task against a real registry.

### 5.3 Path-class maps (the `.tasks/cascade/classes` file, verbatim)

**catalog_opm**

```
release-tool .opm-cli-version
shipped src/
```

There are no test paths: the `@if(fixtures)` files live under `src/` and ship.

**library**

```
test testdata/
test modules/
test *_test.go
```

`opm/schema/loader.go`, `go.mod` and `go.sum` fall through to `shipped`.

**opm-operator**

```
release-tool .opm-cli-version
test config/samples/
test test/
test **/testdata/
test *_test.go
```

**cli**

```
test hack/platform/
test hack/kind-platform.yaml
test examples/
test tests/
test **/testdata/
test *_test.go
```

`templates/`, `internal/operator/`, `go.mod` and `go.sum` fall through to `shipped`.

### 5.4 Env the tasks accept

| Env | Used by | Meaning |
| --- | --- | --- |
| `CASCADE_RESOLVER` | all | the resolver path (§3); absolute |
| `CASCADE_BASE` | title, body, version advance | the base ref; default `origin/main`. Tests pass a commit SHA (§8). |
| `CASCADE_ALLOW_DIRTY` | `deps:cascade` | `1` skips the clean-tree check; the result is then judged by snapshot (§5.2 rules 1 and 13) |
| `CASCADE_EXPECT` | `deps:cascade` | space-separated `<pin-key>=<v>`; the task passes `--expect <v>` for a matching pin. Phase 3 builds it from the payload. |
| `CASCADE_SOURCE`, `CASCADE_TAGS`, `CASCADE_NOTES_FILE` | body | §4.4 |
| `CASCADE_TODAY`, `CASCADE_MAX_WAIT` | passed through to the resolver | tests |
| `CASCADE_TEST_SET` | `deps:cascade:test` | `offline` or `all` (default `all`); §8 |

---

## 6. What each repo's task moves

The class column is the one `pins.sh` prints. "Key" is the pin key.

### 6.1 catalog_opm

| Pin (display) | Key | Class | Where | Resolve | Write |
| --- | --- | --- | --- | --- | --- |
| core | `opmodel.dev/core@v2` | shipped | `src/cue.mod/module.cue` | `newest cue opmodel.dev/core@v2` (no consistent set: the catalog is core's direct consumer) | in `src/`: `cue mod get opmodel.dev/core@<v>`, then `cue mod tidy` |
| opm CLI | `github.com/open-platform-model/cli` | release-tool | `.opm-cli-version` | `newest opm-cli` | one line, `<v>\n` |

- It operates on the explicit path `src/cue.mod/module.cue` only. It never globs, because
  `.build/` and `.claude/worktrees/` hold other `module.cue` files.
- If `task generate:index:check` would fail after a core move, regenerate `src/INDEX.md` in the
  same run (shipped class).
- The title is never `!`. `ci(deps)` occurs only when core did not move.

### 6.2 library

| Pin (display) | Key | Class | Where | Labels |
| --- | --- | --- | --- | --- |
| core | `opmodel.dev/core@v2` | shipped | `DefaultSchemaModule` in `opm/schema/loader.go` | `need-human-review` |
| opm catalog | `opmodel.dev/catalogs/opm@v4` | test | `testdata/parity/cue.mod/module.cue` (the representative file) | |

Order:

1. **Core.** `newest cue opmodel.dev/core@v2 --current <loader value>`. On 0, rewrite the
   constant to `opmodel.dev/core@<v>`. Then `DefaultSchemaVersion()` and
   `registrytest.DefaultCoreVersion` follow, with no second literal.
2. **Text re-pin.** In `testdata/cue.mod/module.cue` and every
   `testdata/render/**/cue.mod/module.cue` (glob, never a list; today 30 files), rewrite only the
   `v:` inside the `"opmodel.dev/core@v2": {` block to the loader's value, in files where it
   differs.
   - Skip frozen files (§5.2 rule 8).
   - Never run `cue mod tidy` there: the synthetic `testing.opmodel.dev/library-render/*` deps
     do not resolve, and they never move.
3. **Catalog.** `newest cue opmodel.dev/catalogs/opm@v4 --current <parity value>`.
   - Then `pin-of` the target's core. If that is newer than the loader's core, the catalog
     stays, with the warning "catalog `<t>` needs core `<c>`, newer than `DefaultSchemaModule`
     `<d>`; advance core first".
   - `K` = the catalog target if it moved, otherwise the parity value.
4. **Explicit module loop.** For every module in `CUE_MODULE_GLOBS` (`modules/*`,
   `testdata/modules/*`, `testdata/parity`, `testdata/parity/opm_platform`):
   - a module is in scope when its core differs from the loader value, or it has the catalog
     and its catalog is below `K` (so a file that lags the parity file catches up; a file
     above `K` is never lowered);
   - for a module in scope, run `cue mod get` with core at the loader value, plus the catalog
     at `K` where that module has the catalog, then `cue mod tidy`.

   This uses explicit versions. It does not call `task cue:deps:update`, which resolves the
   catalog at its bare major and ignores holds. It may refactor `cue:deps:update` to accept
   explicit versions and share the loop.
5. **Warnings.** Add `-` "`docs/getting-started.md` still names `<old core>`" when that file
   names a core version other than the loader's.

- Library has no `.opm-cli-version` and no release-tool class.
- `.cascade-frozen` exists, with 12 Go test files. The task edits no Go literal except the
  loader, so the frozen check matters only for the text re-pin and the module loop.

### 6.3 opm-operator

| Pin (display) | Key | Class | Where |
| --- | --- | --- | --- |
| library | `github.com/open-platform-model/library` | shipped | `go.mod` |
| opm catalog | `opmodel.dev/catalogs/opm@v4` | test | `config/samples/opmodel.dev_v1alpha1_platform.yaml` (`version:` after the `opmodel.dev/catalogs/opm@v4:` key, stored bare) |
| core | `opmodel.dev/core@v2` | test | `test/fixtures/modules/hello/cue.mod/module.cue` (representative) |
| opm CLI | `github.com/open-platform-model/cli` | release-tool | `.opm-cli-version` |

Moves:

1. **library.** `newest go github.com/open-platform-model/library`, then `go get ...@<v>` and
   `go mod tidy`.
2. **Catalog and core**, consistent set (§5.2 rule 7):
   - the sample `version:` (bare);
   - `test/fixtures/catalog.go`'s `CatalogVersion()` literal (bare; root `platform-pins.sh`
     misses it);
   - `cue mod get` and `tidy` in `test/fixtures/modules/{hello,hello_web,podinfo,redis}` and
     `test/fixtures/catalogs/provider` (core only there, with core from the representative
     catalog through `pin-of`).
3. **Version advance** (§5.2 rule 11) for those four modules and the provider catalog.
4. **Consumers in the same PR.**
   - `test/fixtures/modulepackages/*/cue.mod/module.cue`: text re-pin of catalog, core and the
     fixture module version.
   - `test/fixtures/modules/*/moduleinstance.yaml` and
     `config/samples/opmodel.dev_v1alpha1_moduleinstance.yaml`: the fixture version.
   - CI seeds the new fixture versions (`examples:seed`, `examples:consumers`), so following in
     the same PR is safe here.
   - It may call `task examples:pin` if that accepts explicit versions. Its failure is never
     swallowed (the root `fixtures.sh`'s `>/dev/null 2>&1 || printf` must not be copied).
5. **opm CLI.** `newest opm-cli`, writing `.opm-cli-version` last.

Never touched: the Jellyfin sample, `ocirepository.yaml`, `internal/source/testdata/minimal-module`
(no deps), and `hack/fixtures.sh`. That file is byte-identical with the cli's and linted at the
root, so cascade logic lives in `.tasks/cascade/` only.

### 6.4 cli

| Pin (display) | Key | Class | Where |
| --- | --- | --- | --- |
| library | `github.com/open-platform-model/library` | shipped | `go.mod` |
| opm-operator | `github.com/open-platform-model/opm-operator` | shipped | `PinnedOperatorVersion` in `internal/operator/manifest.go` |
| opm catalog | `opmodel.dev/catalogs/opm@v4` | shipped | `templates/minimal/cue.mod/module.cue` (representative) |
| core | `opmodel.dev/core@v2` | shipped | `templates/minimal/cue.mod/module.cue` (representative) |

Moves:

1. **library.** `newest go`, then `go get` and `go mod tidy`.
2. **Operator.** `newest release opm-operator --asset install.yaml`, then
   `task operator:sync VERSION=<v>`, which moves `manifest.go` and `dist/install.yaml` together.
3. **Catalog and core** (consistent set) in:
   - `templates/{minimal,standard,advanced}`;
   - `hack/platform` (never `cue.dev/x/k8s.io`);
   - `examples`;
   - `tests/fixtures/modules/podinfo`;
   - `tests/e2e/testdata/operator-owned`;
   - the six stale-testdata `cue.mod` files from RELEASING.md "What each repo's task moves",
     naming only the `opmodel.dev` keys each file has (the two `tests/fixtures/valid/*` files
     pin core only: §5.2 rule 7);
   - `hack/kind-platform.yaml`: the `version:` after the `opmodel.dev/catalogs/opm@v4:` key,
     bare.
4. **Version advance** (§5.2 rule 11) for the three templates (module `opmodel.dev/templates/<name>@v1`)
   and the podinfo fixture (`testing.opmodel.dev/modules/cli/podinfo@v0`).
5. **The podinfo pin in its consumers** (`examples`, `tests/e2e/testdata/operator-owned`)
   follows the podinfo target from step 4 **in the same PR**, as in the operator.
   - Why: PR CI seeds a job-local registry from the tree only (`pr.yml` "Unit Tests" and
     "Fixtures" jobs; `hack/fixtures.sh seed`), so it holds the tree's podinfo version and no
     older one. `internal/cmdutil/instance_arg_test.go` and `hack/fixtures.sh consumers` both
     resolve through that registry (`OPM_REGISTRY` when set). A consumer left on the previous
     podinfo would fail both on every cascade PR that advances podinfo.
   - How: the consumers' catalog and core move through step 3 first (`cue mod get` and `tidy`,
     with podinfo still at its published version). Then the podinfo `v:` in each consumer's
     `cue.mod/module.cue` is rewritten as text to the step 4 target, only if it differs. The
     task never runs `cue mod get` or `tidy` in a consumer after that rewrite, because the new
     podinfo is not published yet. PR CI's `hack/fixtures.sh consumers` check verifies the
     result against the seeded registry.
6. **Docs bundles.** When library or the operator moved, run `go run ./hack/docskit-dump pins`
   on the edited tree (it reports library, operator and the core derived from the linked
   library's `DefaultSchemaModule`). For each project and pin it prints, call
   `published oci open-platform-model/docs/<project> <pin>` with the pin bare, exactly as
   `release-pin-check.sh` looks it up (no `v`; `docs/library:1.0.0-beta.3` answers 200, the
   `v`-prefixed tag 404).
   - On 3, warn: "docs bundle for `<project>` `<pin>` is not published; G1 will fail the next
     release PR until it is". This covers a core docs pin that changed only because the library
     move changed `DefaultSchemaModule`.
   - The pins still move.
   - If `docskit-dump` fails to build (a breaking library), warn with key `-` and continue; the
     PR's own CI then shows the break.

- `.cascade-frozen` lists Go test files only. The task edits no Go literal except through
  `operator:sync`.

---

## 7. The stub (canonical text, contract version 1)

Each repo copies this byte for byte to `.tasks/cascade/testdata/stub-resolve.sh` (mode 0755).
`.github` ships the same bytes at `.github/scripts/cascade/stub-resolve.sh` and tests that it
agrees with the real resolver (§2.10). Do not edit a copy; change the contract instead.

The file is the text between the fences below, ending with a single newline. Its checksum is:

```
sha256 970130f7d55c07f5b86d4f5b6f392330427ff923eb34f93553656bcd4b893d9c
```

Every repo's `test.sh` and `.github`'s `test/run.sh` assert `sha256sum` of their copy equals this
value, and fail naming the file otherwise. Any edit to the stub text changes this value in the
same contract revision.

The table `CASCADE_STUB_TABLE` is a TSV file. Each row is one of:

```
newest	<kind>	<coordinate or ->	<version | ERROR>
warn	<kind>	<coordinate or ->	<message>
published	<kind>	<coordinate or ->	<version>
pin-of	<module@vN>	<version>	<dep@vM>	<dep version>
language-of	<module@vN>	<version>	<language version>
```

```bash
#!/usr/bin/env bash
# Cascade resolver stub, contract version 1 (Phase 2 cascade contract §7).
# Byte-identical in open-platform-model/.github and every repo's
# .tasks/cascade/testdata/. Answers from the TSV file $CASCADE_STUB_TABLE.
set -euo pipefail
die() { printf 'stub-resolve: %s\n' "$1" >&2; exit "${2:-1}"; }
[ -n "${CASCADE_STUB_TABLE:-}" ] || die "CASCADE_STUB_TABLE is not set"
[ -z "${CASCADE_STUB_LOG:-}" ] || printf '%s\n' "$*" >>"$CASCADE_STUB_LOG"
cmp_v() { # semver_cmp a b -> -1|0|1
  local a="${1%%+*}" b="${2%%+*}" lo
  [ "$a" = "$b" ] && { echo 0; return; }
  lo=$(printf '%s\n%s\n' "$a" "$b" | sed 's/-/~/' | sort -V | head -n1 | sed 's/~/-/')
  if [ "$lo" = "$a" ]; then echo -1; else echo 1; fi
}
col() { awk -F'\t' -v a="$1" -v b="$2" -v c="$3" -v n="$4" \
  '$1==a && $2==b && $3==c {print $n; exit}' "$CASCADE_STUB_TABLE"; }
cmd="${1:-}"; [ -n "$cmd" ] || die "usage: stub-resolve.sh <subcommand> ..." 2; shift
pos=(); cur=""; root="."
while [ $# -gt 0 ]; do
  case "$1" in
    --current) cur="$2"; shift 2 ;;
    --repo-root) root="$2"; shift 2 ;;
    --asset|--expect|--max-wait) shift 2 ;;
    --pre) shift ;;
    --json) die "--json is not supported by the stub" 2 ;;
    --*) die "unknown flag $1" 2 ;;
    *) pos+=("$1"); shift ;;
  esac
done
coord() { if [ "${pos[0]}" = opm-cli ]; then echo -; else echo "${pos[1]}"; fi; }
pinkey() { # §2.4 pin key for kind $1, coordinate $2
  case "$1" in
    opm-cli) echo github.com/open-platform-model/cli ;;
    release) echo "github.com/open-platform-model/$2" ;;
    *) echo "$2" ;;
  esac
}
case "$cmd" in
  newest)
    [ -n "$cur" ] || die "--current is required" 2
    k="${pos[0]}"; c=$(coord)
    if [ -n "${CASCADE_WARNINGS:-}" ]; then
      awk -F'\t' -v b="$k" -v c="$c" -v w="$(pinkey "$k" "$c")" \
        '$1=="warn" && $2==b && $3==c {print w "\t" $4}' \
        "$CASCADE_STUB_TABLE" >>"$CASCADE_WARNINGS"
    fi
    v=$(col newest "$k" "$c" 4)
    [ -n "$v" ] || die "no newest row for $k $c"
    [ "$v" != ERROR ] || die "simulated resolver error for $k $c"
    if [ "$(cmp_v "$v" "$cur")" = 1 ]; then echo "$v"; exit 0; fi
    exit 3 ;;
  published)
    k="${pos[0]}"; c=$(coord)
    if [ "$k" = opm-cli ]; then v="${pos[1]}"; else v="${pos[2]}"; fi
    awk -F'\t' -v b="$k" -v c="$c" -v v="$v" \
      '$1=="published" && $2==b && $3==c && $4==v {f=1} END {exit !f}' \
      "$CASCADE_STUB_TABLE" && exit 0
    exit 3 ;;
  pin-of)
    v=$(awk -F'\t' -v m="${pos[0]}" -v v="${pos[1]}" -v d="${pos[2]}" \
      '$1=="pin-of" && $2==m && $3==v && $4==d {print $5; exit}' "$CASCADE_STUB_TABLE")
    [ -n "$v" ] || exit 3; echo "$v" ;;
  language-of)
    v=$(col language-of "${pos[0]}" "${pos[1]}" 4); [ -n "$v" ] || exit 3; echo "$v" ;;
  check-files) exit 0 ;;
  frozen)
    f="$root/.cascade-frozen"; [ -f "$f" ] || exit 0
    K="${pos[0]}" yq -r '.frozen[] | select(.pins[] == strenv(K)) | .path' "$f" ;;
  is-frozen)
    f="$root/.cascade-frozen"; [ -f "$f" ] || exit 3
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      p="${p%/}"
      case "${pos[0]}" in "$p"|"$p"/*) exit 0 ;; esac
    done < <(K="${pos[1]}" yq -r '.frozen[] | select(.pins[] == strenv(K)) | .path' "$f")
    exit 3 ;;
  hold)
    f="$root/.cascade-hold"; [ -f "$f" ] || exit 3
    today="${CASCADE_TODAY:-$(date -u +%F)}"
    line=$(K="${pos[0]}" yq -r '.holds[] | select(.pin == strenv(K)) | .max + " " + .expires' "$f")
    [ -n "$line" ] || exit 3
    [[ ! "${line#* }" < "$today" ]] || exit 3
    echo "${line%% *}" ;;
  semver-cmp) cmp_v "${pos[0]}" "${pos[1]}" ;;
  next-patch) awk -F. -v OFS=. '{$NF=$NF+1; print}' <<<"${pos[0]}" ;;
  *) die "subcommand $cmd is not supported by the stub" 2 ;;
esac
```

The stub does not apply holds inside `newest`, does no `title`, `body` or `classify`, and no
retries. Those are tested once in `.github`. Its `semver-cmp` is correct only for prereleases
of the form `(alpha|beta|rc)(.N)*`, which is every version the OPM repos publish.

---

## 8. Shared test approach (`task deps:cascade:test`)

Every repo's `.tasks/cascade/test.sh` follows the same shape. It exits 0 when every scenario
passes and 1 otherwise, printing `PASS <scenario>` / `FAIL <scenario>: <reason>`.

**Checks before the scenarios** (both sets):

- `sha256sum testdata/stub-resolve.sh` equals the §7 checksum.
- `pins.sh WORKTREE` and `pins.sh HEAD` print the same rows on a clean sandbox copy.

**Sandbox per scenario.** No `git worktree`, nothing touches the real checkout:

1. Copy the current tree into `$(mktemp -d)/r`:
   `git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf - | tar -xf - -C <dir>/r`.
   - library: also `cp -a` the main checkout's `.cue-cache/mod` if it exists. Never symlink it.
     Run `chmod -R u+w` before cleanup.
2. `git init -q`, `git add -A`, `git commit -q -m base` in the copy.
3. Apply the scenario's setup edits, if any, then `git add -A && git commit -q -m setup`.
4. `export CASCADE_BASE=$(git rev-parse HEAD)`: a SHA, never the symbolic `HEAD`, and kept for
   every run in the scenario. With `HEAD`, the merge-base would move with each commit and a
   second advance would go unseen.
5. Export:
   - `CASCADE_RESOLVER=<repo>/.tasks/cascade/testdata/stub-resolve.sh`;
   - `CASCADE_STUB_TABLE=<the scenario table, built as below>`;
   - `CASCADE_STUB_LOG`;
   - `CASCADE_TODAY=2026-10-03`.
6. Run `task -x deps:cascade` inside the copy and capture the exit code.
7. Clean up with a `trap`.

**Stub tables are built at test time**, never committed with current versions, so a pin move on
`main` never breaks the test:

- **Current rows** come from the unmodified copy: one `newest` row per `pins.sh WORKTREE` row
  (the test maps each pin key to its kind and coordinate); for repos with a consistent set, a
  `pin-of opmodel.dev/catalogs/opm@v4 <tree catalog> opmodel.dev/core@v2 <tree core>` row; and a
  `published cue <F module>@vN v<B>` row for every version-advance module, with `B` read from
  its identity file.
- **Older rows** are the only static data: `testdata/older.tsv` lists, per pin key, an older
  real published version, plus the real `pin-of` row for the older catalog. The test asserts
  with the stub's `semver-cmp` that each older version is strictly older than the tree's value,
  and fails with "`older.tsv` `<key>` `<v>` is not older than the tree's `<t>`; pick an older
  published version" otherwise.

**Scenarios.** Each repo provides `testdata/older.tsv` and `testdata/s1-calls.txt`.

| ID | Set | Setup | Assert |
| --- | --- | --- | --- |
| S1 no-op | offline | the copy as is; current rows only | exit 3; `git status --porcelain` is empty; the stub log, normalized (each version replaced by `V`, lines sorted), equals `testdata/s1-calls.txt`, the repo's expected call list (it includes `check-files`, every `newest`, the `pin-of` for core, and the cli's and operator's version-advance calls if any); every `newest` line carries `--current` and `--repo-root` |
| S3 error | offline | the copy as is; the `newest` row of the first pin the task resolves set to `ERROR` | exit is neither 0 nor 3; `git status --porcelain` is empty (phase A fails before any edit, §5.2 rule 5) |
| S6 dirty tree | offline | the copy with an untracked file | exit 1, and nothing else changed |
| S2 older pins | all | in the copy, set every pin in the repo's §6 table (every location the task moves) to its `older.tsv` version; current rows give the tree's versions | exit 0; the diff between the copy and the original tree is empty except for the version-advance paths, which the test lists as a golden list; then `git add -A && git commit`, keeping `CASCADE_BASE` at the setup SHA, and a second `task -x deps:cascade` gives exit 3 and leaves every identity version unchanged (no second advance); the older versions are real, so `cue mod get` and `go get` resolve, using network or a warm cache |
| S4 frozen | all | S2 setup, plus a temporary entry the test appends to `.cascade-frozen` (creating it if absent, keeping the repo's real entries) that freezes one moved `cue.mod/module.cue` for every OPM key it pins. Each repo names its choice in `design.md`; catalog_opm can only pick `src/cue.mod/module.cue`. | every frozen file is byte-unchanged; exit 0 (the other pins still move) |
| S5 title and body | all | only when `CASCADE_RESOLVER_REAL` points at the real resolver; after S2 | `title` prints the expected one line for that repo; `body` holds both markers, one table row per moved pin, the label `need-human-review` (library only), and `## Notes` last |

**Where it runs.** `CASCADE_TEST_SET=offline` runs the two checks plus S1, S3 and S6; they need
no GHCR or proxy access. `CASCADE_TEST_SET=all` (the default, for local runs) runs everything.

- **Required job, offline set.** One step, `task -x deps:cascade:test` with
  `CASCADE_TEST_SET=offline`, added to an existing required job. *The job column is corrected by
  §11 C6: catalog_opm `Validate catalog`, library `Go tests`, opm-operator `Lint`, cli `Lint`.*

  | Repo | Workflow | Job | Note |
  | --- | --- | --- | --- |
  | catalog_opm | `ci.yml` | `Validate catalog` | has `setup-task` |
  | library | `test.yml` | `Go tests` | has `setup-task` |
  | opm-operator | `test.yml` | `Run on Ubuntu` | has `setup-task` |
  | cli | `pr.yml` | `Unit Tests` | add a `go-task/setup-task` step, SHA-pinned as the other repos pin it |

- **Network job, full set.** A new workflow `.github/workflows/cascade-task.yml` per repo, job
  `Cascade task (network)`, `timeout-minutes: 20`, `permissions: contents: read`. It is **not
  a required check**, so a GHCR or proxy blip never blocks an unrelated PR. Triggers:
  `pull_request` with paths `.tasks/cascade/**`, `Taskfile.yml`, `.tasks/*.yaml` and the
  workflow file itself; `workflow_dispatch`; and a weekly `schedule`. Once `.github` has merged,
  it also checks out `open-platform-model/.github` at `main` (`path: org-github`,
  `persist-credentials: false`) and sets `CASCADE_RESOLVER_REAL`, so S5 runs.

**What the Phase 2 gate means** (RELEASING.md "Phases"):

- "a run against an older pin produces the expected diff" is S2.
- "a run on `main` exits 3" is judged **against the set that is published at the time of the
  run**. It cannot hold on day one: every repo is behind today. For example, the operator is on
  library beta.1 against beta.3, and on catalog `4.4.4` against `v4.5.1`.
- So each repo's gate is shown after a **catch-up PR**: a separate PR whose diff is exactly what
  `task -x deps:cascade` produces on `main`, titled with `task -x deps:cascade:title`. It may
  need hand fixes if catalog `v4.5.x` breaks fixtures. The catch-up PR is not part of
  `add-deps-cascade-task`.
- **Owner and order.** The supervisor opens every catch-up PR (through a writing agent in a
  worktree) and merges it after review. They go tier by tier, because a `fix(deps)` catch-up
  cuts a release that puts the next tier behind again:
  1. catalog_opm, then library (library's catalog pin waits for catalog_opm's catch-up
     release to publish);
  2. opm-operator, after library's catch-up release is published;
  3. cli, after the operator's catch-up release is published.

  Each tier's release PR is merged under the normal release rules before the next tier runs.
  A repo's gate is met when `task -x deps:cascade` on its `main` exits 3 right after its
  catch-up merges. A later upstream release (for example a cli release moving catalog_opm's and
  the operator's `.opm-cli-version`) does not reopen a gate that was met.

---

## 9. Choices the supervisor made here (owner may override)

These are not in RELEASING.md or the owner's selections. Each one is recorded in the change's
`design.md` as "Phase 2 cascade contract §9.N".

1. **Title and body live in the resolver**, not in four copies. The per-repo tasks still exist,
   as RELEASING.md's change row requires. Cost: repo-side title and body tests (S5) need the real
   resolver.
2. **Retry budget.** Transient answers get 4 attempts over about 14 s. `--expect` waits up to
   600 s, polling every 30 s, and then answers with what is published plus a warning, not an
   error. RELEASING.md names no budget.
3. **Prereleases count only when the current pin is a prerelease, or with `--pre`.** A stable
   catalog line never moves onto an `-rc`.
4. **Output is always `v`-prefixed**, unlike `latest-tag.sh`.
5. **The cli docs bundle is a warning, not a hold.** "Published" stays as RELEASING.md defines
   it. The risk to G1 step 6 surfaces on the cascade PR.
6. **Fixture consumers follow in the same PR in both repos.** PR CI seeds the tree's fixtures,
   so a consumer must pin the tree's fixture version. In the cli the consumer's podinfo pin is
   a text rewrite after its catalog and core move, never followed by `tidy` (§6.4 step 5).
7. **The Phase 2 gate is met through a catch-up PR per repo**, tier by tier, opened and merged
   by the supervisor (§8).
8. **`deps-cascade:breaking` is computed in Phase 3**, not in Phase 2.
9. **`task -x` is mandatory** for every caller (§3).
10. **Core never moves backwards to match a catalog. Reported to the owner.** RELEASING.md "The
    cascade" says both "core moves to the version that catalog pins" and "Pins never move
    backwards". When a file's core is already ahead of the catalog's pin, the two conflict; the
    contract keeps the file's core and warns (§5.2 rule 7). The owner may instead want core
    lowered to the catalog's pin.
11. **A hold on core holds the catalog too** in consistent-set files, because MVS would raise a
    held core as soon as the catalog moved (§5.2 rule 7).
12. **The task's tests are split**: an offline set in an existing required job, and a network
    set in a new, non-required job (§8). RELEASING.md names no placement.
13. **Notes are neutralized, not linted** (§4.4), so a human `@mention` in Notes never stops the
    cascade. *Superseded by §11 C1: Notes pass through byte for byte.*

---

## 10. Conventions for the five PRs

- **OpenSpec.** One change per repo, with gates in `tasks.md`. Run `openspec verify`; the
  archive rides the implementing PR. `.github` runs `openspec init` as its first commit.
- **Titles.**
  - `.github`: `feat(cascade): add the shared cascade resolver`. `.github` has no
    release-please, so the type is descriptive only.
  - The four repos: `ci(cascade): add the deps:cascade tasks`. This is tooling under `.tasks/`,
    the Taskfile and CI workflows, and must not cut a release. If a repo's PR title check
    rejects a scope, use `ci: add the deps:cascade tasks`.
- **No edits outside the change's repo.** In particular, the root `.tasks/deps/*.sh` scripts
  stay as they are; the Phase 5 rewire replaces them.
- **Merge order** for the supervisor: `.github` first. The four repo PRs can merge once the
  offline set and S2 and S4 pass with the stub, and S5 passes against the merged resolver.

---

## 11. Version 1.1 clarifications (supervisor, 2026-10-04)

Binding for every Phase 2 branch. They come from the Phase 2 implementation reviews; each repo
change cites them as "Phase 2 cascade contract §11 Cn".

- **C1 Notes.** The bot never edits the `## Notes` section: everything below the
  `cascade-notes` marker is passed through byte for byte, with no neutralization and no
  warning. The mention lint covers the title and the body above the Notes marker. mention-guard
  still checks the whole PR body on `opened` and `synchronize`, so a bare `@mention` a human
  types in Notes fails mention-guard on the bot's next push; that is accepted. Workspace
  RELEASING.md "Title from diff class" is amended to say the bot "lints the title and the body
  above the Notes marker". Supersedes §4.4 (neutralization), the §2.10 Notes case and §9.13.
- **C2 `--expect`.** An `--expect` version confirmed published (before or during the wait)
  joins the candidates of the normal pass, even when the upstream list does not hold it yet; it
  stays subject to the major, prerelease and hold rules. Time waited for `--max-wait` is the sum
  of the sleeps the resolver requested, never the wall clock. Clarifies §2.9.
- **C3 `is-frozen` order.** `is-frozen` is read-only and may be called before `newest` (in
  phase A of §5.2 rule 5) as well as before an edit.
- **C4 CI layout.** Every repo's `cascade-task.yml` checks the repo out at `path: repo` and
  `open-platform-model/.github` at `path: org-github` beside it (catalog_opm's layout), so the
  org checkout is never inside the repo's tree. Applies to §8 "Network job" as §3 already says
  for Phase 3.
- **C5 Stub table.** `test.sh` passes `CASCADE_STUB_TABLE` to every stub call, `semver-cmp`
  included.
- **C6 Required job.** The offline task-test step runs inside each repo's required job as
  workspace RELEASING.md "Rulesets on main" names it: catalog_opm `Validate catalog`, library
  `Go tests`, opm-operator `Lint`, cli `Lint`. Corrects the §8 job column.
- **C7 Offline test needs no resolver.** `deps:cascade:test` does not require
  `CASCADE_RESOLVER` (nor the §3 default path) to exist; the offline set runs entirely on the
  stub. Only S5 uses the real resolver, through `CASCADE_RESOLVER_REAL`.
- **C8 Never lower.** Pins never move backwards, and a consumer's catalog or core is never
  lowered, the cli's podinfo consumers included. The cli rule for those consumers (§6.4 step 5):
  for `cue mod get` and `tidy`, the consumer's podinfo pin is first set to the podinfo version
  published at the merge base, and after `tidy` it is rewritten as text to the step 4 target.
- **C9 `language.version`.** The warning in §5.2 rule 10 compares against the single pinned CUE
  version file each repo names in its `design.md` (no change now). Comparing against the lower
  of the `setup-cue` version and `go.mod`'s `cuelang.org/go` is a follow-up.
- **C10 Version advance.** A version advance keeps `main`'s declared version when that version
  is not yet published, and otherwise takes `main`'s version plus one patch (§5.2 rule 11, as
  written). Workspace RELEASING.md "The receiver" is amended to say so.

---

## Review notes

The review's 31 findings were all applied, some with a different fix than the one suggested.
None was rejected outright. Where the fix differs:

- **2 (static stub tables).** Applied as suggested, plus a static `pin-of` row for the older
  catalog in `older.tsv`, which S2 needs and which cannot be derived from the tree.
- **8 (cli builds `./bin/opm` after `go get`).** Solved by the phase split in §5.2 rule 5: all
  resolution first, then the opm binary from the unmodified tree into `$STATE/bin` (never
  `./bin`, so the tree stays clean), then edits. The same split makes S3 offline and
  edit-free.
- **9 (S1 and untidy `main`).** Took the first option only: `get` and `tidy` run only in
  modules where a pin moved. Requiring a tidy `main` would be a second gate with no owner.
- **11 (mention lint on Notes).** Took the neutralize option (zero-width joiner plus a
  warning) rather than plain pass-through, because the Phase 3 workflow re-posts Notes on every
  update and a pass-through would re-ping on each one. *Superseded by §11 C1: Notes pass through byte for byte.*
- **12 (test placement).** S3 moved from the S2 setup to the unmodified copy so it is offline;
  the network job got `timeout-minutes: 20` instead of 10, given cold caches.
- **14 (semver).** The real resolver must implement precedence by hand and may no longer use
  the `sort -V` trick at all; the stub keeps it, documented as correct for the
  `(alpha|beta|rc)(.N)*` forms OPM publishes, and the agreement test excludes the mixed cases.
- **21 (docs bundles).** Instead of a separate warning for the derived core pin, the task runs
  `hack/docskit-dump pins` on the edited tree and checks every pin it reports, which covers the
  derived core by the same path `release-pin-check.sh` uses.
- **23 (`language.version`).** RELEASING.md's "local `CUE_VERSION`" has no single file in
  library and cli (they pin the `cue` version inline in a workflow), so each repo names its
  source in `design.md`; the rule only forbids the `cue` on `PATH`.
- **24 (core stays ahead).** Kept the never-backwards behaviour and recorded it as §9.10 for
  the owner, because RELEASING.md states both rules and only the owner can rank them.
- **26 (S4 tests nothing).** Applied to every repo, appending to the real `.cascade-frozen`
  rather than replacing it, so library's and cli's real entries are still exercised.
- **28 (catch-up order).** The "gate stays met" sentence is added so that a later cli release
  moving `.opm-cli-version` does not count as a gate failure.
- **17 (stub drift).** The checksum in §7 was computed from the final stub text by extracting
  the fenced block to a file and running `sha256sum`. Any edit to the stub changes it, so the
  contract must be updated in the same step. The stub passes `shellcheck`, and its warning keys
  were checked for `opm-cli` and `release`.

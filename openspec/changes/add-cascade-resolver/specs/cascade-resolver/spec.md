## Purpose

The shared resolver every repo's `task deps:cascade` calls to decide which published upstream
version a pin moves to, and whether a pin is held or frozen. Source: workspace RELEASING.md,
section "The receiver", and the Phase 2 cascade contract, version 1, §2 (kept with this change
as `contract.md`).

## ADDED Requirements

### Requirement: One entry point with fixed exit codes

The resolver SHALL be the executable `.github/scripts/cascade/cascade-resolve.sh`, taking the
subcommands `newest`, `published`, `pin-of`, `language-of`, `frozen`, `is-frozen`, `hold`,
`check-files`, `semver-cmp`, `semver-sort`, `next-patch`, `classify`, `title` and `body`. Every
subcommand SHALL exit 0 for success or yes, 3 for nothing to do or no, 1 for an error and 2 for a
usage error. Stdout SHALL carry only the answer; diagnostics SHALL go to stderr prefixed
`cascade-resolve: `. The resolver SHALL work when invoked by absolute path from any working
directory.

#### Scenario: Unknown subcommand

- **WHEN** `cascade-resolve.sh frobnicate` runs
- **THEN** it exits 2 and stdout is empty

#### Scenario: Malformed version argument

- **WHEN** `cascade-resolve.sh semver-cmp 2.0.0 v2.0.0` runs
- **THEN** it exits 2, because `2.0.0` lacks the leading `v`

#### Scenario: Missing tool

- **WHEN** the `yq` on `PATH` is not mikefarah `yq` v4
- **THEN** any subcommand that reads a steering file exits 1 naming the missing tool

### Requirement: Versions are full v-prefixed SemVer

The resolver SHALL accept and print versions only in the form
`^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$`,
except the tag argument of `published oci`, which it SHALL use exactly as given. Upstream
entries that do not match SHALL be ignored.

#### Scenario: Printed with the v

- **WHEN** `newest` resolves catalog version 4.5.1
- **THEN** it prints `v4.5.1`

#### Scenario: OCI tag used as given

- **WHEN** `published oci open-platform-model/docs/library 1.0.0-beta.3` runs
- **THEN** the manifest request uses the tag `1.0.0-beta.3` with no `v` added

### Requirement: SemVer 2.0.0 precedence

The resolver SHALL order versions by SemVer 2.0.0 precedence: numeric major, minor and patch; a
release above the same version with a prerelease; prerelease identifiers left to right, numeric
by value, alphanumeric in ASCII order, numeric below alphanumeric, a longer list above its
prefix; build metadata ignored. It MUST NOT use the `sed 's/-/~/' | sort -V` trick or a `jq`
comparator. `semver-cmp` SHALL print exactly one of `-1`, `0`, `1` and exit 0; `semver-sort`
SHALL print stdin's versions ascending, one per line, and exit 2 when a line is not a valid
version.

#### Scenario: Numeric identifiers compare by value

- **WHEN** `semver-cmp v2.0.0-alpha.2 v2.0.0-alpha.10` runs
- **THEN** it prints `-1`

#### Scenario: Release above prerelease

- **WHEN** `semver-cmp v2.0.0 v2.0.0-beta.10` runs
- **THEN** it prints `1`

#### Scenario: Alphanumeric above numeric identifier

- **WHEN** `semver-cmp v1.0.0-alpha.beta v1.0.0-alpha.1` runs
- **THEN** it prints `1`

#### Scenario: Longer list above its prefix

- **WHEN** `semver-cmp v1.0.0-alpha v1.0.0-alpha.1` runs
- **THEN** it prints `-1`

#### Scenario: Build metadata ignored

- **WHEN** `semver-cmp v1.0.0+a v1.0.0+b` runs
- **THEN** it prints `0`

#### Scenario: Sort ascending

- **WHEN** `semver-sort` reads `v2.0.0`, `v2.0.0-beta.10`, `v2.0.0-beta.2` and `v2.0.0-alpha.1`
- **THEN** it prints `v2.0.0-alpha.1`, `v2.0.0-beta.2`, `v2.0.0-beta.10`, `v2.0.0` and exits 0

### Requirement: Candidate rules for newest

`newest <kind> [<coordinate>] --current <v>` SHALL consider only versions that are valid, are
not CUE dev builds (containing `-0.dev.` or `-dev.`) or Go pseudo-versions, share `--current`'s
major, and are strictly greater than `--current`. Prereleases SHALL be candidates only when
`--current` is a prerelease or `--pre` is given. It SHALL probe at most the 10 newest
candidates, newest first, and answer the first published one. It SHALL exit 3 with empty stdout
when no candidate is newer, when fewer than 10 candidates exist and none is published (warning
that the newest tagged is not published yet), and when `--current` is newer than every
published version (with a warning). It SHALL exit 1 when the 10 newest candidates are all
unpublished. A `cue` coordinate whose `@vN` disagrees with `--current`'s major SHALL be exit 2.

#### Scenario: Dev builds skipped

- **WHEN** the core GHCR tags hold `v2.0.0-beta.2` and `v2.0.0-0.dev.1791060556.g34fd471`, and `--current` is `v2.0.0-beta.1`
- **THEN** `newest cue opmodel.dev/core@v2` prints `v2.0.0-beta.2` and exits 0

#### Scenario: Stable line ignores prereleases

- **WHEN** `--current` is `v4.4.4` and the newest tag is `v4.6.0-rc.1` with `v4.5.1` published
- **THEN** `newest` prints `v4.5.1`, and with `--pre` it prints `v4.6.0-rc.1`

#### Scenario: Unpublished newest keeps the pin

- **WHEN** the only candidate above `--current` is tagged but its manifest answers 404
- **THEN** `newest` exits 3 with empty stdout and warns that it is not published yet

#### Scenario: Skip to an older published candidate

- **WHEN** the newest candidate is unpublished and the next one, still above `--current`, is published
- **THEN** `newest` prints the second one and exits 0

#### Scenario: Ten unpublished candidates

- **WHEN** at least 10 candidates exist and the newest 10 are all unpublished
- **THEN** `newest` exits 1

#### Scenario: Never backwards

- **WHEN** `--current` is newer than every published version
- **THEN** `newest` exits 3 and warns that the current pin is newer than the newest published

### Requirement: Query kinds and what published means

The resolver SHALL support these kinds, with "published" defined per kind:

- `cue <module>@vN`: candidates from the anonymous GHCR tag list of
  `open-platform-model/<module>`, following `Link: <...>; rel="next"` pagination (a relative
  link resolved against `https://ghcr.io`) and failing beyond 20 pages;
  published when the manifest `HEAD` with `Accept: application/vnd.oci.image.manifest.v1+json`
  answers 200.
- `go <module path>`: candidates from `<proxy>/<path>/@v/list`, never `@latest`; published when
  `@v/<v>.info` answers 200. The proxy base SHALL be `CASCADE_GOPROXY`, default
  `https://proxy.golang.org`.
- `release <repo> --asset NAME...`: candidates from `git ls-remote --tags --refs` of
  `https://github.com/open-platform-model/<repo>`; published when every asset answers 200 to an
  anonymous `HEAD -L` of its release download URL.
- `opm-cli`: `release cli --asset opm-linux-amd64.tar.gz --asset checksums.txt`.
- `oci <repo>` (for `published` only): the manifest `HEAD` accepting the OCI manifest and index
  types.

The resolver MUST NOT send credentials to any host and MUST NOT call `api.github.com`. `git
ls-remote` SHALL run outside any repository with no system, global or environment git config,
no credential helper and `GIT_TERMINAL_PROMPT=0`, so a caller's persisted checkout token or
credential helper never reaches `github.com` and git never prompts. For an
unknown or private GHCR package, `newest` SHALL exit 1 (token 403 or 404, or tags 404) and
`published` SHALL exit 3 with a warning that the package may be private (token 403 or 404;
`published` reads no tag list, and a manifest 404 is a plain "no").

#### Scenario: Draft release skipped

- **WHEN** the newest operator tag's `install.yaml` download answers 404 and the previous tag's answers 200
- **THEN** `newest release opm-operator --asset install.yaml` prints the previous tag

#### Scenario: Missing second asset

- **WHEN** a cli tag's `opm-linux-amd64.tar.gz` answers 200 but its `checksums.txt` answers 404
- **THEN** `published opm-cli <tag>` exits 3

#### Scenario: Go prerelease from the list

- **WHEN** the proxy list for `github.com/open-platform-model/library` holds `v1.0.0-beta.3` unsorted among older versions, its `.info` answers 200, and `--current` is `v1.0.0-beta.1`
- **THEN** `newest go github.com/open-platform-model/library` prints `v1.0.0-beta.3`

#### Scenario: Private package

- **WHEN** the GHCR token request for a package answers 403
- **THEN** `newest cue` for it exits 1 and `published cue` for it exits 3 with a warning

#### Scenario: Caller's git credentials stay home

- **WHEN** `newest release` runs from inside a checkout whose local, global and environment git config carry an `AUTHORIZATION` extraheader and a credential helper, with `GIT_DIR` set to it
- **THEN** `git ls-remote` sees neither, runs with `GIT_TERMINAL_PROMPT=0`, and the answer is unchanged

#### Scenario: No token leaves the process

- **WHEN** any subcommand runs with `GITHUB_TOKEN` and `GH_TOKEN` set
- **THEN** no request carries either value and no request goes to `api.github.com`

### Requirement: New major is a warning only

`newest` SHALL check whether a published version of major N+1 exists (the same GHCR repo or git
tags; on the proxy `<path>/v<N+1>/@v/list`, or the unsuffixed path when moving from Go major 0 to
1) and, if so, warn "new major available" with that version, marking a prerelease. It MUST NOT
answer a version of another major, and the new major MUST NOT change the exit code.

#### Scenario: v3 present

- **WHEN** core has published `v3.0.0-alpha.1` and newer v2 versions above `--current`
- **THEN** `newest cue opmodel.dev/core@v2` prints the newest v2 and warns `new major available: v3.0.0-alpha.1 (prerelease)`

#### Scenario: Proxy has no next major

- **WHEN** `<proxy>/github.com/open-platform-model/library/v2/@v/list` answers 404
- **THEN** no new-major warning is printed and the exit code is unaffected

### Requirement: Requests, retries and the expect wait

Every request SHALL use the curl shape `curl -q -sS --connect-timeout 10 --max-time 60 -o <body>
-D <headers> -w '%{http_code}' [-I] [-L] [-H <header>]... <url>`, with `-q` first and no curl
`--retry`. Status `000`, `429` and `5xx` SHALL be retried up to 4 attempts in all, sleeping 2, 4
and 8 seconds through `${CASCADE_SLEEP:-sleep}`, then exit 1. A `git ls-remote` SHALL abort a transfer stalled for 60 seconds
(`http.lowSpeedLimit=1`, `http.lowSpeedTime=60`), and a failed one SHALL get the same 4
attempts and sleeps. A 404 (or 410 on the proxy) SHALL
mean not published and SHALL NOT be retried. Any other unexpected status SHALL be exit 1; the
resolver MUST NOT fall back to an older or guessed version. `--expect <v>` SHALL apply only when
`<v>` is valid, in-major, above `--current`, allowed by the prerelease rule and not above an
in-date hold; when it applies and `<v>` is unpublished, `newest` SHALL poll `published` every 30
seconds up to `--max-wait` seconds (default `${CASCADE_MAX_WAIT:-600}`), then make its normal
pass. Elapsed time SHALL be the sum of the sleep intervals the resolver requested, never the wall
clock, so a faked `CASCADE_SLEEP` makes the wait instant. An `--expect` version confirmed
published (before or during the wait) SHALL join the candidate set of the normal pass even when
the upstream list does not hold it yet; it stays subject to every other candidate rule. Running
out of time SHALL warn and answer what is published, not fail. `<v>` SHALL never be the answer
unless it is the newest published candidate.

#### Scenario: Transient error recovers

- **WHEN** a request answers 503 once and then 200
- **THEN** the resolver answers normally after one fake sleep of 2 seconds

#### Scenario: Four transient errors

- **WHEN** a request answers 503 four times
- **THEN** the resolver exits 1

#### Scenario: Expected version appears late

- **WHEN** `--expect v1.0.0-beta.4` names a version absent from the proxy list whose `.info` answers 404 twice and then 200
- **THEN** `newest` polls three times, adds `v1.0.0-beta.4` to the candidates and prints it

#### Scenario: Expected version never appears

- **WHEN** the expected version is still unpublished when `--max-wait` runs out, with `CASCADE_SLEEP` faked
- **THEN** `newest` returns without real waiting, warns that it is not published after the wait and answers the newest published candidate, or exits 3 if none is newer

#### Scenario: Expect above a hold is ignored

- **WHEN** `--expect` names a version above an in-date hold's `max`
- **THEN** no wait happens and a stderr line says the hint was ignored

### Requirement: Steering files

The resolver SHALL read `.cascade-frozen` and `.cascade-hold` from `--repo-root` (default the
current directory), treating a missing file as empty. `.cascade-frozen` entries SHALL have
exactly the keys `path` (non-empty, repo-relative, no leading `/`, no `..`), `pins` (non-empty
list) and `reason` (non-empty). `.cascade-hold` entries SHALL have exactly `pin`, `max` (a valid
version), `reason` (with no bare mention, since a warning quotes it) and `expires`
(`YYYY-MM-DD`), with at most one entry per pin. A violation SHALL
be exit 1 for every subcommand that reads the file. `check-files` SHALL validate both files.
`frozen <pin-key>` SHALL print every frozen path for the key. `is-frozen <path> <pin-key>` SHALL
exit 0 when an entry lists the key and its path (trailing `/` stripped) equals `<path>` or is a
directory prefix of it, else 3. `hold <pin-key>` SHALL print `max` and exit 0 for an in-date hold
(today is `CASCADE_TODAY` or the UTC date, in date through `expires`), and exit 3 for an expired
hold (with a warning) or no hold. An empty file, `frozen: []` and `holds: []` SHALL be valid.

#### Scenario: Directory entry with trailing slash

- **WHEN** `.cascade-frozen` freezes `tests/e2e/` for `opmodel.dev/core@v2`
- **THEN** `is-frozen tests/e2e/testdata/x/cue.mod/module.cue opmodel.dev/core@v2` exits 0

#### Scenario: Sibling directory not matched

- **WHEN** `.cascade-frozen` freezes `dir` and the path is `dir2/cue.mod/module.cue`
- **THEN** `is-frozen` exits 3

#### Scenario: Entry without a reason

- **WHEN** a `.cascade-hold` entry has no `reason`
- **THEN** `check-files` exits 1 naming the entry and the missing key

#### Scenario: Empty steering files

- **WHEN** `.cascade-frozen` is empty and `.cascade-hold` holds `holds: []`
- **THEN** `check-files` exits 0

#### Scenario: Real frozen files

- **WHEN** `.cascade-frozen` is a verbatim copy of library's or cli's committed file
- **THEN** `check-files` exits 0

#### Scenario: Expired hold

- **WHEN** `CASCADE_TODAY` is after a hold's `expires`
- **THEN** `hold` exits 3 with empty stdout and warns that the hold expired

### Requirement: Holds inside newest

An in-date hold SHALL cap `newest`'s target at its `max`, warning "held at `<max>` until
`<expires>`" with the reason when the newest published is above it. A hold whose `max` is below
`--current` SHALL never move the pin down: `newest` SHALL exit 3 with a warning.

#### Scenario: Hold caps the target

- **WHEN** library is held at `v1.0.0-beta.2`, `--current` is `v1.0.0-beta.1`, and `v1.0.0-beta.3` is published
- **THEN** `newest go github.com/open-platform-model/library` prints `v1.0.0-beta.2` and warns that it is held

#### Scenario: Hold below current

- **WHEN** the hold's `max` is below `--current`
- **THEN** `newest` exits 3 and warns that the hold is below the current pin

### Requirement: Consistent-set helpers

`pin-of <module>@vN <v> <dep>@vM` SHALL print the version that published `<module>` at `<v>` pins
for `<dep>`, read from the `application/vnd.cue.modulefile.v1` layer of its GHCR manifest, and
exit 3 when the dep is absent. It SHALL take only the first `v:` inside that dep's `{ ... }`
block, never a `v:` of a later dep, and exit 1 when the dep key appears more than once. The parse
SHALL NOT depend on whether `cue` is on `PATH`. `language-of <module>@vN <v>` SHALL print that
module file's `language.version`, exiting 3 when there is none. `next-patch <v>` SHALL print a
release `<v>` with its patch number plus one; a prerelease or build-metadata `<v>` SHALL be exit
2.

#### Scenario: Catalog's core pin

- **WHEN** the `opmodel.dev/catalogs/opm` v4.5.1 module file pins `"opmodel.dev/core@v2": { v: "v2.0.0-beta.1" }`
- **THEN** `pin-of opmodel.dev/catalogs/opm@v4 v4.5.1 opmodel.dev/core@v2` prints `v2.0.0-beta.1`

#### Scenario: Dependency absent

- **WHEN** the module file has no entry for the named dep
- **THEN** `pin-of` exits 3 with empty stdout

#### Scenario: Dependency followed by another

- **WHEN** the module file pins `opmodel.dev/catalogs/opm@v4` at `v4.4.4` and the next dep `opmodel.dev/core@v2` at `v2.0.0-beta.1`
- **THEN** `pin-of <module> <v> opmodel.dev/catalogs/opm@v4` prints only `v4.4.4`

#### Scenario: Language version

- **WHEN** the module file has `language: { version: "v0.16.0" }`
- **THEN** `language-of` prints `v0.16.0`, and for a file without `language` it exits 3

#### Scenario: Next patch

- **WHEN** `next-patch v1.0.3` runs
- **THEN** it prints `v1.0.4`, and `next-patch v1.0.0-beta.3` exits 2

### Requirement: Warnings and JSON output

Every warning SHALL be printed to stderr as `cascade-resolve: warning: <message>` and, when
`CASCADE_WARNINGS` names a file, appended there as `<pin-key>\t<message>`, keyed by the pin key
(for `release` and `opm-cli`, `github.com/open-platform-model/<repo>`). Messages SHALL put
versions and paths in backticks and contain no `@` that is not preceded by a word character.
`newest --json` SHALL print one object with `pin`, `kind`, `current`, `newest`, `target`,
`moved`, `hold`, `newer_major` and `warnings`, with `hold` and `newer_major` `null` when absent.

#### Scenario: JSON shape

- **WHEN** `newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1 --json` moves to `v2.0.0-beta.2` with no hold
- **THEN** it prints one JSON object whose `target` is `v2.0.0-beta.2`, `moved` is `true`, and `hold` and `newer_major` are `null`

#### Scenario: Release warning key

- **WHEN** `newest opm-cli --current v1.0.0-beta.4` warns with `CASCADE_WARNINGS` set
- **THEN** the appended line starts with `github.com/open-platform-model/cli` and a tab

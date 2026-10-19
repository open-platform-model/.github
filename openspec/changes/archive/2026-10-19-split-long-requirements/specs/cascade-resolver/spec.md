## MODIFIED Requirements

### Requirement: One entry point with fixed exit codes

The resolver SHALL be the executable `.github/scripts/cascade/cascade-resolve.sh`, taking the subcommands `newest`, `published`, `pin-of`, `language-of`, `frozen`, `is-frozen`, `hold`, `check-files`, `semver-cmp`, `semver-sort`, `next-patch`, `classify`, `title` and `body`. Every subcommand SHALL exit 0 for success or yes, 3 for nothing to do or no, 1 for an error and 2 for a usage error. Stdout SHALL carry only the answer; diagnostics SHALL go to stderr prefixed `cascade-resolve: `.

#### Scenario: Unknown subcommand

- **WHEN** `cascade-resolve.sh frobnicate` runs
- **THEN** it exits 2 and stdout is empty

#### Scenario: Malformed version argument

- **WHEN** `cascade-resolve.sh semver-cmp 2.0.0 v2.0.0` runs
- **THEN** it exits 2, because `2.0.0` lacks the leading `v`

#### Scenario: Missing tool

- **WHEN** the `yq` on `PATH` is not mikefarah `yq` v4
- **THEN** any subcommand that reads a steering file exits 1 naming the missing tool

## REMOVED Requirements

### Requirement: SemVer 2.0.0 precedence
**Reason**: Split into two requirements that each state one behavior.
**Migration**: See "The resolver orders versions by SemVer 2.0.0 precedence" and "semver-cmp and semver-sort have fixed output".

### Requirement: Candidate rules for newest
**Reason**: Split into three requirements that each state one behavior.
**Migration**: See "Newest considers only valid candidates", "Newest probes the ten newest candidates" and "Newest exits 3 when nothing newer is published".

### Requirement: Query kinds and what published means
**Reason**: Split into requirements that each state one behavior.
**Migration**: See "Cue queries read the GHCR tag list", "Go queries read the module proxy", "Release queries read git tags and release assets", "OCI queries accept the manifest and index types", "The resolver sends no credentials", "git ls-remote runs isolated from the caller's git config" and "Unknown or private GHCR packages".

### Requirement: Requests, retries and the expect wait
**Reason**: Split into requirements that each state one behavior.
**Migration**: See "Requests use one curl shape", "Transient failures are retried four times", "A 404 means not published", "Expect applies only to a plausible version", "The expect wait counts requested sleep", "A confirmed expected version joins the candidates" and "Running out of expect wait time is not a failure".

### Requirement: Steering files
**Reason**: Split into requirements that each state one behavior.
**Migration**: See "Steering files are read from the repo root", "Frozen entries have fixed keys", "Hold entries have fixed keys", "A steering file violation is exit 1", "frozen and is-frozen read the frozen file" and "hold reads the hold file".

### Requirement: Consistent-set helpers
**Reason**: Split into four requirements that each state one behavior.
**Migration**: See "pin-of prints the pin a module version holds", "pin-of reads one dependency block", "language-of prints the module language version" and "next-patch prints the next patch".

### Requirement: Warnings and JSON output
**Reason**: Split into two requirements that each state one behavior.
**Migration**: See "Warnings go to stderr and the warnings file" and "newest --json prints one object".

### Requirement: Proposed tags are on their repo's main
**Reason**: Split into requirements that each state one behavior.
**Migration**: See "Newest answers only candidates whose tag is on main", "Go, release and core pins check their own tag", "Catalog and module pins check a prefixed tag", "The tag check uses git only", "Other pins and published do not check tags" and "tag-on-main answers the check for one version".

## ADDED Requirements

### Requirement: The resolver runs from any directory

The resolver SHALL work when invoked by absolute path from any working directory.

#### Scenario: Run by absolute path

- **WHEN** `/abs/path/cascade-resolve.sh semver-cmp v1.0.0 v1.0.1` runs from a directory that is not the script's
- **THEN** it works and prints `-1`

### Requirement: The resolver orders versions by SemVer 2.0.0 precedence

The resolver SHALL order versions by SemVer 2.0.0 precedence: numeric major, minor and patch; a release above the same version with a prerelease; prerelease identifiers left to right, numeric by value, alphanumeric in ASCII order, numeric below alphanumeric, a longer list above its prefix; build metadata ignored. It MUST NOT use the `sed 's/-/~/' | sort -V` trick or a `jq` comparator.

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

### Requirement: semver-cmp and semver-sort have fixed output

`semver-cmp` SHALL print exactly one of `-1`, `0`, `1` and exit 0; `semver-sort` SHALL print stdin's versions ascending, one per line, and exit 2 when a line is not a valid version.

#### Scenario: Sort ascending

- **WHEN** `semver-sort` reads `v2.0.0`, `v2.0.0-beta.10`, `v2.0.0-beta.2` and `v2.0.0-alpha.1`
- **THEN** it prints `v2.0.0-alpha.1`, `v2.0.0-beta.2`, `v2.0.0-beta.10`, `v2.0.0` and exits 0

#### Scenario: Sort rejects an invalid line

- **WHEN** `semver-sort` reads `v1.0.0` and `1.0.1`
- **THEN** it exits 2, because `1.0.1` is not a valid version

### Requirement: Newest considers only valid candidates

`newest <kind> [<coordinate>] --current <v>` SHALL consider only versions that are valid, are not CUE dev builds (containing `-0.dev.` or `-dev.`) or Go pseudo-versions, share `--current`'s major, and are strictly greater than `--current`. Prereleases SHALL be candidates only when `--current` is a prerelease or `--pre` is given. A `cue` coordinate whose `@vN` disagrees with `--current`'s major SHALL be exit 2.

#### Scenario: Dev builds skipped

- **WHEN** the core GHCR tags hold `v2.0.0-beta.2` and `v2.0.0-0.dev.1791060556.g34fd471`, and `--current` is `v2.0.0-beta.1`
- **THEN** `newest cue opmodel.dev/core@v2` prints `v2.0.0-beta.2` and exits 0

#### Scenario: Stable line ignores prereleases

- **WHEN** `--current` is `v4.4.4` and the newest tag is `v4.6.0-rc.1` with `v4.5.1` published
- **THEN** `newest` prints `v4.5.1`, and with `--pre` it prints `v4.6.0-rc.1`

### Requirement: Newest probes the ten newest candidates

`newest` SHALL probe at most the 10 newest candidates, newest first, and answer the first published one. It SHALL exit 1 when the 10 newest candidates are all unpublished.

#### Scenario: Skip to an older published candidate

- **WHEN** the newest candidate is unpublished and the next one, still above `--current`, is published
- **THEN** `newest` prints the second one and exits 0

#### Scenario: Ten unpublished candidates

- **WHEN** at least 10 candidates exist and the newest 10 are all unpublished
- **THEN** `newest` exits 1

### Requirement: Newest exits 3 when nothing newer is published

`newest` SHALL exit 3 with empty stdout when no candidate is newer, when fewer than 10 candidates exist and none is published (warning that the newest tagged is not published yet), and when `--current` is newer than every published version (with a warning).

#### Scenario: Unpublished newest keeps the pin

- **WHEN** the only candidate above `--current` is tagged but its manifest answers 404
- **THEN** `newest` exits 3 with empty stdout and warns that it is not published yet

#### Scenario: Never backwards

- **WHEN** `--current` is newer than every published version
- **THEN** `newest` exits 3 and warns that the current pin is newer than the newest published

### Requirement: Cue queries read the GHCR tag list

A `cue <module>@vN` query SHALL take candidates from the anonymous GHCR tag list of `open-platform-model/<module>`, following `Link: <...>; rel="next"` pagination (a relative link resolved against `https://ghcr.io`) and failing beyond 20 pages. A version SHALL be published when the manifest `HEAD` with `Accept: application/vnd.oci.image.manifest.v1+json` answers 200.

#### Scenario: Cue version is published

- **WHEN** the manifest `HEAD` of a `cue` candidate, sent with `Accept: application/vnd.oci.image.manifest.v1+json`, answers 200
- **THEN** the candidate is published

### Requirement: Go queries read the module proxy

A `go <module path>` query SHALL take candidates from `<proxy>/<path>/@v/list`, never `@latest`. A version SHALL be published when `@v/<v>.info` answers 200. The proxy base SHALL be `CASCADE_GOPROXY`, default `https://proxy.golang.org`.

#### Scenario: Go prerelease from the list

- **WHEN** the proxy list for `github.com/open-platform-model/library` holds `v1.0.0-beta.3` unsorted among older versions, its `.info` answers 200, and `--current` is `v1.0.0-beta.1`
- **THEN** `newest go github.com/open-platform-model/library` prints `v1.0.0-beta.3`

### Requirement: Release queries read git tags and release assets

A `release <repo> --asset NAME...` query SHALL take candidates from `git ls-remote --tags --refs` of `https://github.com/open-platform-model/<repo>`. A version SHALL be published when every asset answers 200 to an anonymous `HEAD -L` of its release download URL. `opm-cli` SHALL be `release cli --asset opm-linux-amd64.tar.gz --asset checksums.txt`.

#### Scenario: Draft release skipped

- **WHEN** the newest operator tag's `install.yaml` download answers 404 and the previous tag's answers 200
- **THEN** `newest release opm-operator --asset install.yaml` prints the previous tag

#### Scenario: Missing second asset

- **WHEN** a cli tag's `opm-linux-amd64.tar.gz` answers 200 but its `checksums.txt` answers 404
- **THEN** `published opm-cli <tag>` exits 3

### Requirement: OCI queries accept the manifest and index types

For `oci <repo>` (for `published` only), published SHALL be decided by the manifest `HEAD` accepting the OCI manifest and index types.

#### Scenario: OCI manifest request

- **WHEN** `published oci <repo> <tag>` runs
- **THEN** the manifest `HEAD` accepts the OCI manifest and index types, and that request decides whether the tag is published

### Requirement: The resolver sends no credentials

The resolver MUST NOT send credentials to any host and MUST NOT call `api.github.com`.

#### Scenario: No token leaves the process

- **WHEN** any subcommand runs with `GITHUB_TOKEN` and `GH_TOKEN` set
- **THEN** no request carries either value and no request goes to `api.github.com`

### Requirement: git ls-remote runs isolated from the caller's git config

`git ls-remote` SHALL run outside any repository with no system, global or environment git config, no credential helper and `GIT_TERMINAL_PROMPT=0`, so a caller's persisted checkout token or credential helper never reaches `github.com` and git never prompts.

#### Scenario: Caller's git credentials stay home

- **WHEN** `newest release` runs from inside a checkout whose local, global and environment git config carry an `AUTHORIZATION` extraheader and a credential helper, with `GIT_DIR` set to it
- **THEN** `git ls-remote` sees neither, runs with `GIT_TERMINAL_PROMPT=0`, and the answer is unchanged

### Requirement: Unknown or private GHCR packages

For an unknown or private GHCR package, `newest` SHALL exit 1 (token 403 or 404, or tags 404) and `published` SHALL exit 3 with a warning that the package may be private (token 403 or 404; `published` reads no tag list, and a manifest 404 is a plain "no").

#### Scenario: Private package

- **WHEN** the GHCR token request for a package answers 403
- **THEN** `newest cue` for it exits 1 and `published cue` for it exits 3 with a warning

### Requirement: Requests use one curl shape

Every request SHALL use the curl shape `curl -q -sS --connect-timeout 10 --max-time 60 -o <body> -D <headers> -w '%{http_code}' [-I] [-L] [-H <header>]... <url>`, with `-q` first and no curl `--retry`.

#### Scenario: Request shape

- **WHEN** the resolver makes a request
- **THEN** its curl command line starts with `-q`, has the options of the curl shape and has no `--retry`

### Requirement: Transient failures are retried four times

Status `000`, `429` and `5xx` SHALL be retried up to 4 attempts in all, sleeping 2, 4 and 8 seconds through `${CASCADE_SLEEP:-sleep}`, then exit 1. A `git ls-remote` SHALL abort a transfer stalled for 60 seconds (`http.lowSpeedLimit=1`, `http.lowSpeedTime=60`), and a failed one SHALL get the same 4 attempts and sleeps.

#### Scenario: Transient error recovers

- **WHEN** a request answers 503 once and then 200
- **THEN** the resolver answers normally after one fake sleep of 2 seconds

#### Scenario: Four transient errors

- **WHEN** a request answers 503 four times
- **THEN** the resolver exits 1

### Requirement: A 404 means not published

A 404 (or 410 on the proxy) SHALL mean not published and SHALL NOT be retried. Any other unexpected status SHALL be exit 1; the resolver MUST NOT fall back to an older or guessed version.

#### Scenario: A 404 is not retried

- **WHEN** a request answers 404
- **THEN** the version is not published and the resolver makes no second attempt

### Requirement: Expect applies only to a plausible version

`--expect <v>` SHALL apply only when `<v>` is valid, in-major, above `--current`, allowed by the prerelease rule and not above an in-date hold. When it applies and `<v>` is unpublished, `newest` SHALL poll `published` every 30 seconds up to `--max-wait` seconds (default `${CASCADE_MAX_WAIT:-600}`), then make its normal pass.

#### Scenario: Expect above a hold is ignored

- **WHEN** `--expect` names a version above an in-date hold's `max`
- **THEN** no wait happens and a stderr line says the hint was ignored

### Requirement: The expect wait counts requested sleep

Elapsed time SHALL be the sum of the sleep intervals the resolver requested, never the wall clock, so a faked `CASCADE_SLEEP` makes the wait instant.

#### Scenario: Faked sleep makes the wait instant

- **WHEN** `newest` waits for an expected version with `CASCADE_SLEEP` faked
- **THEN** the wait ends after the requested sleep intervals sum to `--max-wait`, with no real waiting

### Requirement: A confirmed expected version joins the candidates

An `--expect` version confirmed published (before or during the wait) SHALL join the candidate set of the normal pass even when the upstream list does not hold it yet; it stays subject to every other candidate rule. `<v>` SHALL never be the answer unless it is the newest published candidate.

#### Scenario: Expected version appears late

- **WHEN** `--expect v1.0.0-beta.4` names a version absent from the proxy list whose `.info` answers 404 twice and then 200
- **THEN** `newest` polls three times, adds `v1.0.0-beta.4` to the candidates and prints it

### Requirement: Running out of expect wait time is not a failure

Running out of time SHALL warn and answer what is published, not fail.

#### Scenario: Expected version never appears

- **WHEN** the expected version is still unpublished when `--max-wait` runs out, with `CASCADE_SLEEP` faked
- **THEN** `newest` returns without real waiting, warns that it is not published after the wait and answers the newest published candidate, or exits 3 if none is newer

### Requirement: Steering files are read from the repo root

The resolver SHALL read `.cascade-frozen` and `.cascade-hold` from `--repo-root` (default the current directory), treating a missing file as empty. An empty file, `frozen: []` and `holds: []` SHALL be valid.

#### Scenario: Empty steering files

- **WHEN** `.cascade-frozen` is empty and `.cascade-hold` holds `holds: []`
- **THEN** `check-files` exits 0

### Requirement: Frozen entries have fixed keys

`.cascade-frozen` entries SHALL have exactly the keys `path` (non-empty, repo-relative, no leading `/`, no `..`), `pins` (non-empty list) and `reason` (non-empty).

#### Scenario: Real frozen files

- **WHEN** `.cascade-frozen` is a verbatim copy of library's or cli's committed file
- **THEN** `check-files` exits 0

### Requirement: Hold entries have fixed keys

`.cascade-hold` entries SHALL have exactly `pin`, `max` (a valid version), `reason` (with no bare mention, since a warning quotes it) and `expires` (`YYYY-MM-DD`), with at most one entry per pin.

#### Scenario: Two holds for one pin

- **WHEN** a `.cascade-hold` file holds two entries for the same `pin`
- **THEN** a subcommand that reads the file exits 1

### Requirement: A steering file violation is exit 1

A violation SHALL be exit 1 for every subcommand that reads the file. `check-files` SHALL validate both files.

#### Scenario: Entry without a reason

- **WHEN** a `.cascade-hold` entry has no `reason`
- **THEN** `check-files` exits 1 naming the entry and the missing key

### Requirement: frozen and is-frozen read the frozen file

`frozen <pin-key>` SHALL print every frozen path for the key. `is-frozen <path> <pin-key>` SHALL exit 0 when an entry lists the key and its path (trailing `/` stripped) equals `<path>` or is a directory prefix of it, else 3.

#### Scenario: Directory entry with trailing slash

- **WHEN** `.cascade-frozen` freezes `tests/e2e/` for `opmodel.dev/core@v2`
- **THEN** `is-frozen tests/e2e/testdata/x/cue.mod/module.cue opmodel.dev/core@v2` exits 0

#### Scenario: Sibling directory not matched

- **WHEN** `.cascade-frozen` freezes `dir` and the path is `dir2/cue.mod/module.cue`
- **THEN** `is-frozen` exits 3

### Requirement: hold reads the hold file

`hold <pin-key>` SHALL print `max` and exit 0 for an in-date hold (today is `CASCADE_TODAY` or the UTC date, in date through `expires`), and exit 3 for an expired hold (with a warning) or no hold.

#### Scenario: Expired hold

- **WHEN** `CASCADE_TODAY` is after a hold's `expires`
- **THEN** `hold` exits 3 with empty stdout and warns that the hold expired

### Requirement: pin-of prints the pin a module version holds

`pin-of <module>@vN <v> <dep>@vM` SHALL print the version that published `<module>` at `<v>` pins for `<dep>`, read from the `application/vnd.cue.modulefile.v1` layer of its GHCR manifest, and exit 3 when the dep is absent.

#### Scenario: Catalog's core pin

- **WHEN** the `opmodel.dev/catalogs/opm` v4.5.1 module file pins `"opmodel.dev/core@v2": { v: "v2.0.0-beta.1" }`
- **THEN** `pin-of opmodel.dev/catalogs/opm@v4 v4.5.1 opmodel.dev/core@v2` prints `v2.0.0-beta.1`

#### Scenario: Dependency absent

- **WHEN** the module file has no entry for the named dep
- **THEN** `pin-of` exits 3 with empty stdout

### Requirement: pin-of reads one dependency block

`pin-of` SHALL take only the first `v:` inside that dep's `{ ... }` block, never a `v:` of a later dep, and exit 1 when the dep key appears more than once. The parse SHALL NOT depend on whether `cue` is on `PATH`.

#### Scenario: Dependency followed by another

- **WHEN** the module file pins `opmodel.dev/catalogs/opm@v4` at `v4.4.4` and the next dep `opmodel.dev/core@v2` at `v2.0.0-beta.1`
- **THEN** `pin-of <module> <v> opmodel.dev/catalogs/opm@v4` prints only `v4.4.4`

### Requirement: language-of prints the module language version

`language-of <module>@vN <v>` SHALL print that module file's `language.version`, exiting 3 when there is none.

#### Scenario: Language version

- **WHEN** the module file has `language: { version: "v0.16.0" }`
- **THEN** `language-of` prints `v0.16.0`, and for a file without `language` it exits 3

### Requirement: next-patch prints the next patch

`next-patch <v>` SHALL print a release `<v>` with its patch number plus one; a prerelease or build-metadata `<v>` SHALL be exit 2.

#### Scenario: Next patch

- **WHEN** `next-patch v1.0.3` runs
- **THEN** it prints `v1.0.4`, and `next-patch v1.0.0-beta.3` exits 2

### Requirement: Warnings go to stderr and the warnings file

Every warning SHALL be printed to stderr as `cascade-resolve: warning: <message>` and, when `CASCADE_WARNINGS` names a file, appended there as `<pin-key>\t<message>`, keyed by the pin key (for `release` and `opm-cli`, `github.com/open-platform-model/<repo>`). Messages SHALL put versions and paths in backticks and contain no `@` that is not preceded by a word character.

#### Scenario: Release warning key

- **WHEN** `newest opm-cli --current v1.0.0-beta.4` warns with `CASCADE_WARNINGS` set
- **THEN** the appended line starts with `github.com/open-platform-model/cli` and a tab

### Requirement: newest --json prints one object

`newest --json` SHALL print one object with `pin`, `kind`, `current`, `newest`, `target`, `moved`, `hold`, `newer_major` and `warnings`, with `hold` and `newer_major` `null` when absent.

#### Scenario: JSON shape

- **WHEN** `newest cue opmodel.dev/core@v2 --current v2.0.0-beta.1 --json` moves to `v2.0.0-beta.2` with no hold
- **THEN** it prints one JSON object whose `target` is `v2.0.0-beta.2`, `moved` is `true`, and `hold` and `newer_major` are `null`

### Requirement: Newest answers only candidates whose tag is on main

For a pin whose versions are tags of an `open-platform-model` repo (the pins of "Go, release and core pins check their own tag" and "Catalog and module pins check a prefixed tag"), `newest` SHALL answer a published candidate only when its tag's commit is reachable from that repo's `main`. A candidate whose tag is not on `main`, or is missing, SHALL be skipped with the warning "`<v>` is published but its tag is not on `<repo>` main; skipped", and the walk SHALL continue with the next candidate.

#### Scenario: A forged tag

- **WHEN** the Go proxy lists library `v1.2.0` and `v1.1.0`, both published, and the `v1.2.0` tag points to a commit not on library's `main`
- **THEN** `newest go github.com/open-platform-model/library --current v1.0.0` prints `v1.1.0` and warns that `v1.2.0`'s tag is not on main

### Requirement: Go, release and core pins check their own tag

The checked tag SHALL be `v<x>` of the repo for these pins: `go github.com/open-platform-model/<repo>` (with or without `/vN`), `release <repo>`, `opm-cli` and `cue opmodel.dev/core@vN` (repo `core`).

#### Scenario: Core tag checked

- **WHEN** `newest cue opmodel.dev/core@v2` finds `v2.0.0-beta.2` published
- **THEN** it checks the tag `v2.0.0-beta.2` of `core` against `main`

### Requirement: Catalog and module pins check a prefixed tag

The checked tag SHALL carry a prefix for these pins: `cue opmodel.dev/catalogs/opm@vN` (repo `catalog_opm`, tag `opm-v<x>`), `cue opmodel.dev/modules/opm_operator@vN` (repo `opm-operator`, tag `opm_operator-v<x>`) and `cue opmodel.dev/modules/opm_controller@vN` (repo `opm-controller`, tag `opm_controller-v<x>`, the module's train after `opm-operator` is renamed `opm-controller`).

#### Scenario: Catalog tags carry their prefix

- **WHEN** `newest cue opmodel.dev/catalogs/opm@v4` finds `v4.6.0` published
- **THEN** it checks the tag `opm-v4.6.0` of `catalog_opm` against `main`

#### Scenario: Operator module tags carry their prefix

- **WHEN** `tag-on-main opmodel.dev/modules/opm_operator@v0 v0.2.0` runs and the tag `opm_operator-v0.2.0` of `opm-operator` points to a commit not on its `main`
- **THEN** it exits 3, and for `v0.1.0`, whose tag `opm_operator-v0.1.0` is on `main`, it exits 0

#### Scenario: Controller module tags carry their prefix

- **WHEN** `tag-on-main opmodel.dev/modules/opm_controller@v0 v0.2.0` runs and the tag `opm_controller-v0.2.0` of `opm-controller` points to a commit not on its `main`
- **THEN** it exits 3, and for `v0.1.0`, whose tag `opm_controller-v0.1.0` is on `main`, it exits 0

### Requirement: The tag check uses git only

The resolver SHALL learn whether a tag is on `main` with git only (a tree-less bare clone of the repo and a fetch of the one tag, isolated like `git ls-remote`: no system or global config, no credential helper, no prompt), never with `api.github.com`; a git failure after four attempts SHALL be exit 1, never a guess.

#### Scenario: Git failure

- **WHEN** the clone of the source repo fails four times
- **THEN** `newest` exits 1

### Requirement: Other pins and published do not check tags

Other pins, those not named in "Go, release and core pins check their own tag" and "Catalog and module pins check a prefixed tag" (fixtures, templates, `oci`), SHALL NOT be checked, and `published` SHALL NOT check.

#### Scenario: Published does not check a tag

- **WHEN** `published` runs for a version whose tag is not on its repo's `main`
- **THEN** it makes no tag check and answers from the publication check only

### Requirement: tag-on-main answers the check for one version

`tag-on-main <pin-key> <v>` SHALL answer whether the tag of `<v>` is reachable from its repo's `main`, for one version: exit 0 when the tag is on `main` or the pin has no tag to check, 3 when the tag is missing or off `main`, 1 on a git failure after four attempts.

#### Scenario: One version checked on its own

- **WHEN** the `v1.2.0` tag of library points to a commit not on library's `main`
- **THEN** `tag-on-main github.com/open-platform-model/library v1.2.0` exits 3, and `tag-on-main example.com/mod v0.2.0` exits 0 without a clone

## ADDED Requirements

### Requirement: Proposed tags are on the main of their repo

For a pin whose versions are tags of an `open-platform-model` repo, `newest` SHALL answer a
published candidate only when its tag's commit is reachable from that repo's `main`: `go
github.com/open-platform-model/<repo>` (with or without `/vN`, tag `v<x>`), `release <repo>` and
`opm-cli` (tag `v<x>`), `cue opmodel.dev/core@vN` (repo `core`, tag `v<x>`), `cue
opmodel.dev/catalogs/opm@vN` (repo `catalog_opm`, tag `opm-v<x>`) and `cue
opmodel.dev/modules/opm_controller@vN` (repo `opm-controller`, tag `opm_controller-v<x>`). A candidate whose tag is not on
`main`, or is missing, SHALL be skipped with the warning "`<v>` is published but its tag is not on
`<repo>` main; skipped", and the walk SHALL continue with the next candidate. The resolver SHALL
learn this with git only (a tree-less bare clone of the repo and a fetch of the one tag, isolated
like `git ls-remote`: no system or global config, no credential helper, no prompt), never with
`api.github.com`; a git failure after four attempts SHALL be exit 1, never a guess. Other pins
(fixtures, templates, `oci`) SHALL NOT be checked, and `published` SHALL NOT check.
`tag-on-main <pin-key> <v>` SHALL answer the same check for one version: exit 0 when the tag is
on `main` or the pin has no tag to check, 3 when the tag is missing or off `main`, 1 on a git
failure after four attempts.

#### Scenario: A forged tag

- **WHEN** the Go proxy lists library `v1.2.0` and `v1.1.0`, both published, and the `v1.2.0` tag points to a commit not on library's `main`
- **THEN** `newest go github.com/open-platform-model/library --current v1.0.0` prints `v1.1.0` and warns that `v1.2.0`'s tag is not on main

#### Scenario: Catalog tags carry their prefix

- **WHEN** `newest cue opmodel.dev/catalogs/opm@v4` finds `v4.6.0` published
- **THEN** it checks the tag `opm-v4.6.0` of `catalog_opm` against `main`

#### Scenario: One version checked on its own

- **WHEN** the `v1.2.0` tag of library points to a commit not on library's `main`
- **THEN** `tag-on-main github.com/open-platform-model/library v1.2.0` exits 3, and `tag-on-main example.com/mod v0.2.0` exits 0 without a clone

#### Scenario: Git failure

- **WHEN** the clone of the source repo fails four times
- **THEN** `newest` exits 1

#### Scenario: Controller module tags carry their prefix

- **WHEN** `tag-on-main opmodel.dev/modules/opm_controller@v0 v0.2.0` runs and the tag `opm_controller-v0.2.0` of `opm-controller` points to a commit not on its `main`
- **THEN** it exits 3, and for `v0.1.0`, whose tag `opm_controller-v0.1.0` is on `main`, it exits 0

## MODIFIED Requirements

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

- **WHEN** the newest controller tag's `install.yaml` download answers 404 and the previous tag's answers 200
- **THEN** `newest release opm-controller --asset install.yaml` prints the previous tag

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

## REMOVED Requirements

### Requirement: Proposed tags are on their repo's main

**Reason**: Retitled for the rename of opm-operator to opm-controller: a scenario named after the old repo is replaced, and OpenSpec 1.12 refuses a MODIFIED that drops one.

**Migration**: see the requirement that replaces it in this change.

## ADDED Requirements

### Requirement: Catalog and controller module pins check a prefixed tag

The checked tag SHALL carry a prefix for these pins: `cue opmodel.dev/catalogs/opm@vN` (repo `catalog_opm`, tag `opm-v<x>`) and `cue opmodel.dev/modules/opm_controller@vN` (repo `opm-controller`, tag `opm_controller-v<x>`).

#### Scenario: Catalog tags carry their prefix

- **WHEN** `newest cue opmodel.dev/catalogs/opm@v4` finds `v4.6.0` published
- **THEN** it checks the tag `opm-v4.6.0` of `catalog_opm` against `main`

#### Scenario: Controller module tags carry their prefix

- **WHEN** `tag-on-main opmodel.dev/modules/opm_controller@v0 v0.2.0` runs and the tag `opm_controller-v0.2.0` of `opm-controller` points to a commit not on its `main`
- **THEN** it exits 3, and for `v0.1.0`, whose tag `opm_controller-v0.1.0` is on `main`, it exits 0

## MODIFIED Requirements

### Requirement: Release queries read git tags and release assets

A `release <repo> --asset NAME...` query SHALL take candidates from `git ls-remote --tags --refs` of `https://github.com/open-platform-model/<repo>`. A `release <repo> --asset NAME...` version SHALL be published when every asset answers 200 to an anonymous `HEAD -L` of its release download URL. `opm-cli` SHALL be `release cli --asset opm-linux-amd64.tar.gz --asset checksums.txt`.

#### Scenario: Draft release skipped

- **WHEN** the newest controller tag's `install.yaml` download answers 404 and the previous tag's answers 200
- **THEN** `newest release opm-controller --asset install.yaml` prints the previous tag

#### Scenario: Missing second asset

- **WHEN** a cli tag's `opm-linux-amd64.tar.gz` answers 200 but its `checksums.txt` answers 404
- **THEN** `published opm-cli <tag>` exits 3

## REMOVED Requirements

### Requirement: Catalog and module pins check a prefixed tag

**Reason**: Retitled for the rename of opm-operator to opm-controller: a scenario named after the old repo is replaced, and OpenSpec refuses a MODIFIED that drops one.

**Migration**: see the requirement that replaces it in this change.

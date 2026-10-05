## MODIFIED Requirements

### Requirement: Proposed tags are on their repo's main

For a pin whose versions are tags of an `open-platform-model` repo, `newest` SHALL answer a
published candidate only when its tag's commit is reachable from that repo's `main`: `go
github.com/open-platform-model/<repo>` (with or without `/vN`, tag `v<x>`), `release <repo>` and
`opm-cli` (tag `v<x>`), `cue opmodel.dev/core@vN` (repo `core`, tag `v<x>`), `cue
opmodel.dev/catalogs/opm@vN` (repo `catalog_opm`, tag `opm-v<x>`) and `cue
opmodel.dev/modules/opm_operator@vN` (repo `opm-operator`, tag `opm_operator-v<x>`) and `cue
opmodel.dev/modules/opm_controller@vN` (repo `opm-controller`, tag `opm_controller-v<x>`, the
module's train after `opm-operator` is renamed `opm-controller`). A candidate whose tag is not on
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

#### Scenario: Operator module tags carry their prefix

- **WHEN** `tag-on-main opmodel.dev/modules/opm_operator@v0 v0.2.0` runs and the tag `opm_operator-v0.2.0` of `opm-operator` points to a commit not on its `main`
- **THEN** it exits 3, and for `v0.1.0`, whose tag `opm_operator-v0.1.0` is on `main`, it exits 0

#### Scenario: One version checked on its own

- **WHEN** the `v1.2.0` tag of library points to a commit not on library's `main`
- **THEN** `tag-on-main github.com/open-platform-model/library v1.2.0` exits 3, and `tag-on-main example.com/mod v0.2.0` exits 0 without a clone

#### Scenario: Git failure

- **WHEN** the clone of the source repo fails four times
- **THEN** `newest` exits 1

#### Scenario: Controller module tags carry their prefix

- **WHEN** `tag-on-main opmodel.dev/modules/opm_controller@v0 v0.2.0` runs and the tag `opm_controller-v0.2.0` of `opm-controller` points to a commit not on its `main`
- **THEN** it exits 3, and for `v0.1.0`, whose tag `opm_controller-v0.1.0` is on `main`, it exits 0

## ADDED Requirements

### Requirement: The allow-lists are keyed by receiver

The allow-lists SHALL live in `.github` (`wiring/lib.sh`), keyed by the receiver, never read from the receiver's tree.

#### Scenario: cli's controller module pin file

- **WHEN** cli's task commit changes `internal/controller/pin.go`
- **THEN** `publish` accepts the path, and refuses `internal/controller/install.go`

#### Scenario: cli's embedded controller CRDs

- **WHEN** cli's task commit changes `internal/controller/crds/platforms.opmodel.dev.yaml`, a CRD manifest `hack/controller-pin` writes beside the pin
- **THEN** `publish` accepts the path, and refuses `internal/controller/crds/crds.go`
- **AND** it refuses a commit that adds or deletes a manifest there (status other than `M`), so a module version that changes the CRD set needs a human

### Requirement: The deny-list wins over every allow-list

The deny-list SHALL be `.github/**`, `.tasks/**`, any `Taskfile*`, `hack/**` (except cli's `hack/kind-platform.yaml` and `hack/platform/cue.mod/module.cue`), `*.sh`, any `CODEOWNERS`, `release-please-config.json`, `.release-please-manifest.json`, `.cascade-frozen`, `.cascade-hold` and, for opm-controller, `modules/**` (its controller module moves only through its own `module-deps.yml`), and SHALL win over the allow-list.

#### Scenario: A bundle that edits the cascade task

- **WHEN** `compute`'s commit changes `UPSTREAM_VERSION` and `.tasks/cascade/pins.sh`
- **THEN** `publish` refuses naming `.tasks/cascade/pins.sh` and mints no token

#### Scenario: A bundle that edits the Taskfile

- **WHEN** `compute`'s commit changes `Taskfile.yml`
- **THEN** `publish` refuses before the mint

#### Scenario: The controller's module

- **WHEN** an opm-controller bot commit changes `modules/opm_controller/cue.mod/module.cue`
- **THEN** `publish` refuses it, although any other `cue.mod/module.cue` is allowed

### Requirement: The cli mirror reports the controller release and module pins

For cli, the mirrored pin report SHALL show the library, the controller release and the controller module (`github.com/open-platform-model/opm-controller` and `opmodel.dev/modules/opm_controller@v0`, from `PinnedControllerVersion` and `PinnedModuleVersion` in `internal/controller/pin.go`), the opm catalog and core.

#### Scenario: cli's module pin in the body

- **WHEN** cli's `internal/controller/pin.go` moves `PinnedModuleVersion` from `0.1.0` to `0.2.0`
- **THEN** the mirrored pin report shows `opmodel.dev/modules/opm_controller@v0` moving from `v0.1.0` to `v0.2.0`, as cli's own `pins.sh` does

#### Scenario: cli's controller pin file in the body

- **WHEN** cli's `main` holds `internal/controller/pin.go` with `PinnedControllerVersion = "v1.0.0-beta.9"` and `PinnedModuleVersion = "0.2.0"`
- **THEN** the mirrored pin report has the rows `github.com/open-platform-model/opm-controller` (`opm-controller`, `v1.0.0-beta.9`) and `opmodel.dev/modules/opm_controller@v0` (`opm-controller module`, `v0.2.0`)

## MODIFIED Requirements

### Requirement: The payload source allowlists

The allowlists SHALL be: `catalog_opm` accepts `core`, `cli`; `library` accepts `core`, `catalog_opm`; `opm-controller` accepts `catalog_opm`, `library`, `cli`; `cli` accepts `catalog_opm`, `library`, `opm-controller`; `cascade-sandbox-down` accepts `cascade-sandbox-up`. A receiver outside this list SHALL fail with "not a cascade receiver".

#### Scenario: Receiver outside the list

- **WHEN** a receiver that is not in the allowlists runs `compute`
- **THEN** it fails with "not a cascade receiver"

### Requirement: Merge mode merges main into the branch

`merge` SHALL check out `origin/deps/cascade` and run `git merge --no-edit origin/main`: when only derived files conflict (`go.mod`, `go.sum`, any `cue.mod/module.cue`, cli's `internal/controller/pin.go` and its `internal/controller/crds/*.yaml` manifests), it SHALL take `main`'s side, commit `Merge origin/main into deps/cascade` and let the task regenerate them; any other conflict SHALL abort the merge and give mode `conflict` with the conflicting paths.

#### Scenario: Only derived files conflict

- **WHEN** the merge of `origin/main` conflicts only in `go.mod` and `go.sum`
- **THEN** `compute` takes `main`'s side, commits `Merge origin/main into deps/cascade` and lets the task regenerate them

#### Scenario: Another file conflicts

- **WHEN** the merge of `origin/main` conflicts in a file that is not a derived file
- **THEN** `compute` aborts the merge and gives mode `conflict` with the conflicting paths

### Requirement: Publish bounds the increment before it mints

For `push` and `recreate`, `publish` SHALL, with `GITHUB_TOKEN` and plain git only and before the token exists, bound the increment (requirements "Publish bounds the increment's commits", "Publish limits what a single-parent commit changes", "Publish checks merge commits", "The allow-lists are keyed by receiver", "The deny-list wins over every allow-list", "Publish refuses to drop a human commit" and "Publish checks the tag of each moved pin").

#### Scenario: Increment comes first

- **WHEN** `publish` verifies a `push` plan
- **THEN** it bounds the increment before any token exists

### Requirement: The mirror records the sha256 of receiver files

`.github` (`wiring/lib.sh`, `mirror_sources`) SHALL record, per receiver, the sha256 of each receiver file its publish mirrors copy or were read from: `.tasks/cascade/pins.sh`, `.tasks/cascade/classes`, the `.tasks/cascade/lib.sh` that `pins.sh` sources where it does (library, opm-controller), and, for catalog_opm, library, opm-controller and cli, the `.tasks/cascade/cascade.sh` its allow-list (`publish_paths`) was read from.

#### Scenario: Recorded files of a receiver

- **WHEN** the recorded files of cli are read
- **THEN** they hold the sha256 of `.tasks/cascade/pins.sh`, `.tasks/cascade/classes` and `.tasks/cascade/cascade.sh` on the receiver

## REMOVED Requirements

### Requirement: The renamed repo records the same files

**Reason**: The rename of opm-operator to opm-controller is done and every receiver's and source's own rename has merged; the maps name `opm-controller` only.

**Migration**: none; a caller still pinned to the earlier `.github` commit keeps running that commit's code until its pin moves.

### Requirement: Allow-lists live in .github

**Reason**: Retitled for the rename of opm-operator to opm-controller: a scenario named after the old repo is replaced, and OpenSpec refuses a MODIFIED that drops one.

**Migration**: see the requirement that replaces it in this change.

### Requirement: The deny-list wins over the allow-list

**Reason**: Retitled for the rename of opm-operator to opm-controller: a scenario named after the old repo is replaced, and OpenSpec refuses a MODIFIED that drops one.

**Migration**: see the requirement that replaces it in this change.

### Requirement: The cli mirror reports the controller pins

**Reason**: Retitled for the rename of opm-operator to opm-controller: a scenario named after the old repo is replaced, and OpenSpec refuses a MODIFIED that drops one.

**Migration**: see the requirement that replaces it in this change.

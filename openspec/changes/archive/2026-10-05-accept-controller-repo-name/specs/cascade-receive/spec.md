## MODIFIED Requirements

### Requirement: Payload is a validated hint

On a `repository_dispatch` run `compute` SHALL accept the payload only when `source` is a string
in the receiver's allowlist and `tags` is an array of 1 to 8 strings each matching the tag shape
for that source; unknown keys SHALL be ignored. A `source` or tag holding a control character
(U+0000 to U+001F or U+007F) SHALL make the payload invalid, and each tag SHALL be matched whole,
so a tag with a trailing newline is refused. Allowlists: `catalog_opm` accepts `core`, `cli`;
`library` accepts `core`, `catalog_opm`; `opm-operator` and `opm-controller` (its name after the
rename) accept `catalog_opm`, `library`, `cli`; `cli` accepts `catalog_opm`, `library`,
`opm-operator`, `opm-controller`; `cascade-sandbox-down` accepts
`cascade-sandbox-up`. A receiver outside this list SHALL fail with "not a cascade receiver". A
valid payload SHALL set `CASCADE_SOURCE`, `CASCADE_TAGS` and one `CASCADE_EXPECT` pair built from
the last tag (`catalog_opm` tags lose their `opm-` prefix). An invalid payload SHALL be dropped
whole with a warning and a summary line naming why, and the run SHALL continue as a sweep. The
payload SHALL never set a label. Only `cascade-sandbox-down` SHALL export
`CASCADE_EXTRA_SOURCES=cascade-sandbox-up`. `publish` SHALL read the payload from the event
itself, with the same validation, never from `compute`.

#### Scenario: Hostile payload

- **WHEN** the payload is `{"source":"evil","tags":["@x"]}`
- **THEN** the payload is dropped with a warning, the run behaves as a sweep, and no mention appears in any text the bot writes

#### Scenario: Nine tags

- **WHEN** the payload carries nine valid tags
- **THEN** the whole payload is dropped and the run continues as a sweep

#### Scenario: Tag with a trailing newline

- **WHEN** the payload for cli is `{"source":"library","tags":["v1.0.0\n","v1.0.1"]}`
- **THEN** the whole payload is dropped and the run continues as a sweep

#### Scenario: The renamed repo's release reaches cli

- **WHEN** cli receives `{"source":"opm-controller","tags":["v1.0.0-beta.9"]}`
- **THEN** the payload is valid and `CASCADE_EXPECT` is `github.com/open-platform-model/opm-controller=v1.0.0-beta.9`

### Requirement: Mode selection

`compute` SHALL pick the mode from the remote `deps/cascade` tip (`OLD`) and the cascade PR:

| State | Mode |
| --- | --- |
| the cascade PR carries `deps-cascade:hold` | `skip` |
| no `OLD` | `fresh` |
| `OLD` set and no open cascade PR | `recreate` |
| open cascade PR, every commit in `origin/main..origin/deps/cascade` has author and committer email `337635439+opm-cascade[bot]@users.noreply.github.com` | `rebuild` |
| open cascade PR, any other author or committer in that range | `merge` |

`fresh`, `rebuild` and `recreate` SHALL start from `origin/main`. `merge` SHALL check out
`origin/deps/cascade` and run `git merge --no-edit origin/main`: when only derived files conflict
(`go.mod`, `go.sum`, any `cue.mod/module.cue`, cli's `internal/operator/pin.go` or, after cli's
rename, `internal/controller/pin.go`), it SHALL take `main`'s side, commit `Merge origin/main into deps/cascade` and let
the task regenerate them; any other conflict SHALL abort the merge and give mode `conflict` with
the conflicting paths. The bot SHALL never rebase and never drop a human commit.

#### Scenario: Human commit survives

- **WHEN** a human pushed a commit to `deps/cascade` and a new upstream release arrives
- **THEN** the human commit is an ancestor of the new tip and the bot's commit is on top

#### Scenario: Bot-only branch is rebuilt

- **WHEN** the branch holds only bot commits and a new upstream release arrives
- **THEN** the branch is rebuilt from `origin/main` to one bot commit and the PR number is unchanged

### Requirement: Publish bounds the bot's increment

For `push` and `recreate`, `publish` SHALL take as the bot's increment the new tip's commits that
`origin/main` does not have and, for a `push` whose old tip is an ancestor of the new one, that
the old tip does not have either. It SHALL refuse the plan, before any token exists, when the
increment has more than two commits, a root commit or a commit with more than two parents; when a
commit's author or committer email is not the bot's; when a single-parent commit changes a path
with a status other than `M`, changes a mode, has a mode other than `100644` or `100755` (a
symlink `120000` or gitlink `160000`), or changes a path outside the receiver's allow-list or
inside the deny-list; and when a merge commit's second parent is not on `origin/main` or its tree
differs from `git merge-tree --write-tree` of its parents in a path that is not a derived path
carrying the second parent's content. The allow-lists SHALL live in `.github` (`wiring/lib.sh`),
keyed by the receiver, never read from the receiver's tree. The deny-list SHALL be `.github/**`,
`.tasks/**`, any `Taskfile*`, `hack/**` (except cli's `hack/kind-platform.yaml` and
`hack/platform/cue.mod/module.cue`), `*.sh`, any `CODEOWNERS`, `release-please-config.json`,
`.release-please-manifest.json`, `.cascade-frozen`, `.cascade-hold` and, for opm-operator
under either of its names (`opm-controller` after the rename), `modules/**` (its module moves
only through its own `module-deps.yml`), and SHALL win
over the allow-list. When a `push` does not contain the old tip and `origin/main..old` holds a commit the
bot did not make, `publish` SHALL refuse; it SHALL refuse a `recreate` whenever `origin/main..old`
holds such a commit, since `recreate` rebuilds the branch on `main`; `close` SHALL then keep the
branch and delete only a bot-only one. For every pin whose version differs between the merge
base and the new tip (read with the `.github` pin mirror), `publish` SHALL run the resolver's
`tag-on-main` itself and SHALL refuse when the tag is not on its repo's `main` or the check
fails, so a forged tag is refused even when `compute` skipped the resolver.

#### Scenario: A bundle that edits the cascade task

- **WHEN** `compute`'s commit changes `UPSTREAM_VERSION` and `.tasks/cascade/pins.sh`
- **THEN** `publish` refuses naming `.tasks/cascade/pins.sh` and mints no token

#### Scenario: A bundle that edits the Taskfile

- **WHEN** `compute`'s commit changes `Taskfile.yml`
- **THEN** `publish` refuses before the mint

#### Scenario: A symlink

- **WHEN** `compute`'s commit turns an allowed path into a symlink
- **THEN** `publish` refuses before the mint

#### Scenario: A commit the bot did not make

- **WHEN** the bundle's commit has a human committer
- **THEN** `publish` refuses before the mint

#### Scenario: A rebuild over a human commit

- **WHEN** the remote branch holds a human commit and the plan's new tip does not contain it
- **THEN** `publish` refuses with "would drop commits", and `close` keeps such a branch

#### Scenario: A pin moved to a forged tag

- **WHEN** the new tip moves a pin to `v0.2.0` and that tag of its repo is not on `main`
- **THEN** `publish` refuses with "whose tag is not on its repo's main" before the mint

#### Scenario: A recreate over a kept human commit

- **WHEN** a branch `close` kept for its human commit has no PR, so `compute` plans `recreate`
- **THEN** `publish` refuses with "recreate would drop commits" before the mint

#### Scenario: Merge mode with a human commit

- **WHEN** the branch holds a human commit that changes `.tasks/` and the bot merges `main` and commits a pin move
- **THEN** `publish` accepts: the human commit is not in the increment, and the bot's merge and pin commits pass

#### Scenario: cli's operator module pin file

- **WHEN** cli's task commit changes `internal/operator/pin.go`
- **THEN** `publish` accepts the path, and refuses `internal/operator/manifest.go` or `internal/operator/dist/install.yaml`
- **AND** it accepts `internal/controller/pin.go`, the same file after cli's rename

#### Scenario: opm-operator's module

- **WHEN** an opm-operator bot commit changes `modules/opm_operator/cue.mod/module.cue`
- **THEN** `publish` refuses it, although any other `cue.mod/module.cue` is allowed

#### Scenario: The renamed repo's module

- **WHEN** an `opm-controller` bot commit changes `modules/opm_controller/cue.mod/module.cue`
- **THEN** `publish` refuses it, although any other `cue.mod/module.cue` is allowed

### Requirement: Publish refuses a stale mirror

`.github` (`wiring/lib.sh`, `mirror_sources`) SHALL record, per receiver, the sha256 of each
receiver file its publish mirrors copy or were read from: `.tasks/cascade/pins.sh`,
`.tasks/cascade/classes`, the `.tasks/cascade/lib.sh` that `pins.sh` sources where it does
(library, opm-operator), and, for catalog_opm, library, opm-operator and cli, the
`.tasks/cascade/cascade.sh` its allow-list (`publish_paths`) was read from. For
`push` and `recreate`, `publish` SHALL, before it reads the bundle, runs the workflows guard or
bounds the increment, and before any token exists, read each recorded file on the receiver's
`origin/main` and refuse the plan when its sha256 differs from the recorded one or the file is
missing there, with one message naming the receiver, the path, the sha256 found (or `missing`)
and the recorded sha256. `close`, `conflict` and `too_long` SHALL NOT be refused for a stale
mirror. The mirror of each receiver's `pins.sh` SHALL report the same rows as that receiver's
own `pins.sh` on its `main`: for cli, the library, the controller release and the controller
module (`github.com/open-platform-model/opm-controller` and
`opmodel.dev/modules/opm_controller@v0`, from `PinnedControllerVersion` and
`PinnedModuleVersion` in `internal/controller/pin.go`; before cli's rename
`github.com/open-platform-model/opm-operator` and `opmodel.dev/modules/opm_operator@v0` from
`internal/operator/pin.go`), the opm catalog and core. `opm-controller` SHALL have the same
recorded files and hashes as `opm-operator` until the renamed repo's own change to them.

#### Scenario: pins.sh changed on main

- **WHEN** the receiver's `main` holds a `.tasks/cascade/pins.sh` whose sha256 is not the recorded one, and `compute` planned a `push`
- **THEN** `publish` refuses with "the .github mirror of <receiver> is stale: .tasks/cascade/pins.sh on its main has sha256 <found>, the mirror was written from <recorded>" and mints no token

#### Scenario: classes removed from main

- **WHEN** the receiver's `main` has no `.tasks/cascade/classes`
- **THEN** `publish` refuses naming `.tasks/cascade/classes` with sha256 `missing`

#### Scenario: cascade.sh changed on main

- **WHEN** cli's `main` holds a `.tasks/cascade/cascade.sh` whose sha256 is not the recorded one, while its `pins.sh`, `lib.sh` and `classes` are unchanged, and `compute` planned a `push`
- **THEN** `publish` refuses naming `.tasks/cascade/cascade.sh` and mints no token

#### Scenario: A stale mirror does not hold a close

- **WHEN** the receiver's `main` holds a `pins.sh` the mirror was not written from, and `compute` planned `close`, `conflict` or `too_long`
- **THEN** `publish` verifies the plan as it would with a current mirror

#### Scenario: An unrelated change on main

- **WHEN** `main` changed only files the mirrors do not copy
- **THEN** the mirror check passes and `publish` verifies the plan as before

#### Scenario: cli's module pin in the body

- **WHEN** cli's `internal/operator/pin.go` moves `PinnedModuleVersion` from `0.1.0` to `0.2.0`
- **THEN** the mirrored pin report shows `opmodel.dev/modules/opm_operator@v0` moving from `v0.1.0` to `v0.2.0`, as cli's own `pins.sh` does

#### Scenario: cli's pin file after its rename

- **WHEN** cli's `main` holds `internal/controller/pin.go` with `PinnedControllerVersion = "v1.0.0-beta.9"` and `PinnedModuleVersion = "0.2.0"`
- **THEN** the mirrored pin report has the rows `github.com/open-platform-model/opm-controller` (`opm-controller`, `v1.0.0-beta.9`) and `opmodel.dev/modules/opm_controller@v0` (`opm-controller module`, `v0.2.0`)

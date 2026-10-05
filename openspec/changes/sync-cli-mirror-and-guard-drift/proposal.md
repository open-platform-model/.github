## Why

`publish` (`receive-publish.sh verify`) trusts only `.github` code, so it carries a mirror of each
receiver's cascade task: the paths the task may write (`publish_paths`), a copy of its
`pins.sh` (`receiver_pins`) and its `classes` (`receiver_classes`), all in `wiring/lib.sh`.
cli#307 (`23a2c552`, "install the operator from its module") deleted
`internal/operator/manifest.go` and `internal/operator/dist/install.yaml`. cli's `pins.sh` now
reads `internal/operator/pin.go` and reports a new row, `opmodel.dev/modules/opm_operator@v0`,
and its task writes `pin.go` through `hack/operator-pin`. The mirror still reads `manifest.go`,
so on today's cli `main` it reports neither the operator nor the operator module pin (0 of 150
recent commits agree), and it would refuse every task commit that moves `pin.go` as a path the
task "never writes" (issue 18).

Nothing noticed the drift: the mirror is a hand copy, and the first sign would have been a
confusing refusal or a wrong PR body on the first live run. A stale mirror should stop publish
with a message that says what moved, and should show up red long before a live run hits it.

## What Changes

- **The cli mirror follows cli `main` (`bd4d1a7c`).** `publish_paths cli` allows
  `internal/operator/pin.go` and no longer `manifest.go` or `dist/install.yaml`; `pins_cli` reads
  `pin.go` and reports both the operator release and the operator module rows, as cli's
  `pins.sh` does; `is_derived_path` treats `internal/operator/pin.go` as derived (the task
  regenerates it) and drops the two deleted files. `changelog_source` maps the module pin to
  opm-operator's `opm_operator-` tags, so the breaking check sees a breaking module release.
- **The other mirrors re-checked against `main`.** catalog_opm (`0560990`), library (`ca7c56b`)
  and opm-operator (`53ccaab`) need no pin, class or path change. opm-operator's repo-scope
  `deps:cascade` never touches its operator module (`modules/opm_operator`, moved only by its
  own `module-deps.yml`), so `publish_denied` now refuses `modules/**` for opm-operator.
- **Publish refuses a stale mirror.** `mirror_sources` in `wiring/lib.sh` records the sha256 of
  every receiver file the mirror copies: `.tasks/cascade/pins.sh`, the `.tasks/cascade/lib.sh`
  it sources (library, opm-operator) and `.tasks/cascade/classes`. For a `push` or `recreate`,
  `verify` reads those files on the receiver's `origin/main` first and refuses, before any other
  check and before the mint, naming the receiver, the file and both hashes, when one differs
  or is missing.
- **A daily drift check.** A new read-only workflow, `cascade-mirror-drift.yml` (job
  `Mirror drift`, daily and on dispatch, `contents: read`, the run's own token, no secret), runs
  `wiring/mirror-drift.sh`, which fetches each product receiver's mirrored files from `main` and
  fails when a hash differs or a file cannot be read.
- **README.** The allow-list table, the deny-list, "Keeping the mirrors in step" (the hashes, the
  refusal, the drift check, the merge order) and two residual-risk notes.

Not in this change: any receiver repo (each picks this up with its next `.github` pin bump), the
resolver (`tag_source` still maps no module path, so the module pin's tag is not checked against
opm-operator's `main`; named as residual risk), rulesets or repo settings.

## Capabilities

### Modified Capabilities

- `cascade-receive`: the derived paths of merge mode, the deny-list of the bot's increment, and
  a new refusal of a stale mirror.
- `cascade-workflows`: a new daily, read-only drift check of the mirrors.

## Impact

- Scripts: `.github/scripts/cascade/wiring/lib.sh`, `wiring/receive-publish.sh`, new
  `wiring/mirror-drift.sh`; tests in `wiring/test/` (`lib`, `bound`, `compute` cases, the toy
  receiver's `pins.sh`, new `drift` cases).
- Workflow: new `.github/workflows/cascade-mirror-drift.yml`.
- Callers: the five receivers' `cascade-publish` action runs this code once their `.github` pin
  moves to this change's squash commit; no caller shape changes. cli's cascade publishes nothing
  correct until then (its mirror is stale today).

Depends on: nothing. Later: every receiver's pin bump; any receiver change to its `pins.sh`,
its `lib.sh` or its `classes` needs a `.github` change like this one first.

## Context

`publish` renders the cascade PR text and bounds the bot's commits with `.github` code only
(change `bound-cascade-publish`). For that it mirrors three things of each receiver's
`.tasks/cascade/`: the paths the task writes, `pins.sh` and `classes`. The mirror was read on
2026-10-04; cli#307 changed cli's `pins.sh` and task the next day.

## Goals / Non-Goals

Goals: the mirrors match every receiver's `main`; a stale mirror stops publish with a clear
refusal; drift is visible within a day.

Non-goals: generating the mirror from the receivers (publish must not run receiver code), the
resolver's module tag check, changing any receiver.

## Decisions

### D1: The cli mirror copies cli's `pins.sh` at `bd4d1a7c`

`pins_cli` MUST read `internal/operator/pin.go` at the ref and print, when it exists, the
`PinnedOperatorVersion` row (`github.com/open-platform-model/opm-operator`, display
`opm-operator`) and the `PinnedModuleVersion` row (`opmodel.dev/modules/opm_operator@v0`,
display `opm-operator module`, the bare version `v`-prefixed), each only when non-empty, both
class `shipped`, with the same sed expressions as cli's `pins.sh`. `publish_paths cli` MUST allow
`^internal/operator/pin\.go$` in place of `manifest.go` and `dist/install.yaml`.
`is_derived_path` MUST accept `internal/operator/pin.go` (exact path) and no longer any
`manifest.go` or `internal/operator/dist/install.yaml`: cli's task rewrites `pin.go` from the
merged tree, as it did `manifest.go`. `changelog_source opmodel.dev/modules/opm_operator@v0`
MUST print `opm-operator opm_operator-`, the module's release tags (release-please component
`opm_operator`).

### D2: opm-operator's module is denied

`publish_denied opm-operator modules/*` MUST hold. The repo-scope task never writes there
(`CASCADE_SCOPE=repo`); the module scope publishes through opm-operator's own `module-deps.yml`,
never through `cascade-publish`, and opm-operator's rule is that a PR changing the module changes
nothing else. The generic `cue.mod/module.cue` allow-list entry would otherwise accept
`modules/opm_operator/cue.mod/module.cue`.

### D3: Hashes of the mirrored files, checked on `origin/main`

`mirror_sources <receiver>` prints `<path> <sha256>` per mirrored file and exits 1 for a
non-receiver. The files are `.tasks/cascade/pins.sh` and `.tasks/cascade/classes` for every
receiver, plus `.tasks/cascade/lib.sh` for library and opm-operator, whose `pins.sh` sources it
for its parsing helpers (`dep_v`, `loader_core`, `go_require_v`, `yaml_version_after`,
`cue_dep_v`, `valid_v`). Hashing `lib.sh` costs false alarms when a task-only helper there
changes (it has not changed since either repo's cascade landed), but without it a parser change
there would slip past the guard.

The four product receivers also record `.tasks/cascade/cascade.sh`, the file `publish_paths` was
read from. Without it a receiver that changes only `cascade.sh` passes the guard while the
allow-list is stale: opm-operator `6a14adb..53ccaab` added `CASCADE_SCOPE=module`, which writes
`modules/opm_operator/cue.mod/module.cue`, without touching `pins.sh`, `lib.sh` or `classes`, and
the generic `cue.mod/module.cue` entry would have accepted that path. `cascade.sh` changes more
often than `pins.sh`, so this costs more false alarms; each one is a prompt to re-read the
allow-list, which is the point. Code `cascade.sh` only runs (cli's `hack/operator-pin`, Taskfile
tasks) is not hashed: a change there that writes a new path still ends in the path refusal, and
hashing every program a task calls would turn every unrelated edit into a stop. The sandbox
records no `cascade.sh`: the suite's toy receiver carries its own test task.

For `push` and `recreate`, `verify` MUST, after fetching `origin/main` and before the bundle,
the workflows guard and the increment, compute `sha256` of `git show origin/main:<path>` for
each source (`missing` when it is not a blob there) and refuse with

```
refusing the plan: the .github mirror of <receiver> is stale: <path> on its main has sha256
<have>, the mirror was written from <want>; update the mirror and mirror_sources in
wiring/lib.sh, then move the .github pin
```

(one line). `close`, `conflict` and `too_long` do not read the mirror and are not refused: a
stale mirror must not keep a stale PR open. The suite proves it: each of the three is computed,
then `main`'s `pins.sh` moves, and verify still passes the plan. `origin/main` is the receiver's `main` that `verify`
already fetched; the mirror copies `main`'s files, and the pins at the new tip are read with
them. A receiver's change to a mirrored file and its pin bump to the `.github` commit that
mirrors it should land in one PR; between the two merges publish refuses, which is the
intended fail-closed state.

The archived sandbox receiver keeps an entry (hashes of its last `main`), and the wiring suite's
toy receiver now carries the sandbox's own `pins.sh` byte for byte, so every publish case runs
through the check. The one compute case that needs a pin label commits a labelled toy
`pins.sh` to its own `main`.

### D4: `mirror-drift.sh` and `cascade-mirror-drift.yml`

`mirror-drift.sh [<receiver>...]` (default `MIRROR_RECEIVERS` = catalog_opm library
opm-operator cli; the sandbox is archived and private, so the run's token cannot read it)
requests per file

```
gh api -H 'Accept: application/vnd.github.raw' repos/open-platform-model/<r>/contents/<path>?ref=main
```

through `${CASCADE_GH:-gh}` with `GH_TOKEN`, hashes the bytes and prints `ok <r> <path>`,
`DRIFT <r> <path>: <the refusal text above>` with an `::error::` annotation, or, when the
request fails (any non-zero gh exit, a 404 included), `ERROR <r> <path>: <first 200 bytes of
stderr>` with `::error::cannot read <path> from the main of <r>`; it checks every file before it
exits. Exit 0 all match, 1 any drift or error, 2 an unknown receiver.

The workflow: `on: schedule` (`23 6 * * *`) and `workflow_dispatch`; top-level and job
`permissions: contents: read`; one job `drift`, name `Mirror drift`, `ubuntu-latest`, 5-minute
timeout, concurrency group `cascade-mirror-drift`; steps: `actions/checkout` at the SHA the other
workflows use with `persist-credentials: false`, then the script with `GH_TOKEN: ${{
github.token }}`. It is never a required check (a schedule-only workflow never reports on a
PR). A separate workflow, not a job in `cascade-resolver-live.yml`, because that one runs
weekly.

## Research & Decisions

- **Proof that the mirrors match.** Each receiver's real `pins.sh` from `origin/main` and the
  mirror, on its last 150 first-parent `main` commits: catalog_opm, library, opm-operator and
  cli 150/150 equal (equal output, or both failing on the same old malformed pin). The old cli
  mirror differs on 150/150. Every `classes` file's non-comment lines equal `receiver_classes`.
- **Proof that the allow-lists are complete.** Each receiver's own suite from `origin/main`
  (`CASCADE_TEST_SET=all`, real resolver for the title and body scenarios) with its sandboxes
  kept: catalog_opm 13, library 15, opm-operator 22, cli 21 checks passed. Every changed path in
  every kept sandbox passes `publish_path_ok` with status `M`, except each suite's planted
  untracked file and opm-operator's `M5` sandbox, whose `modules/opm_operator/cue.mod/module.cue`
  comes from `deps:cascade:module` and is refused by D2 as intended. cli's distinct changed
  paths include `internal/operator/pin.go`.
- **Options for the guard.** (a) Generate the mirror at publish time from the receiver's
  `pins.sh`: rejected, publish must not run receiver code. (b) Compare outputs of the receiver's
  `pins.sh` and the mirror in `compute`: rejected, `compute` is untrusted. (c) Hash the source
  files, chosen: plain `git show` in publish, no receiver code, and a hash change is exactly the
  event that needs a human to re-read the mirror.

### D5: The operator module's tags

`tag_source` maps `opmodel.dev/modules/opm_operator@v[0-9]*` to `opm-operator opm_operator-`, the
same prefix `changelog_source` already uses. `newest` (cli's module lane) then skips a published
module version whose tag is off opm-operator's `main`, and publish's `tag-on-main` refuses a
moved module pin with such a tag. Safe today: the one release, `opm_operator-v0.1.0`, is
`8dc24b3` on opm-operator `main`. Before this, the pin had no tag source, so both checks exited
0 for it.

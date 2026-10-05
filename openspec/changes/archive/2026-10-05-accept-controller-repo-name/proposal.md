## Why

The owner renames the repo `open-platform-model/opm-operator` to `opm-controller` (with its CUE
module `opmodel.dev/modules/opm_controller@v0` on a new tag train `opm_controller-v*`, and cli's
pin file `internal/controller/pin.go` with `PinnedControllerVersion`). GitHub renames in place,
and every cascade job derives the repo name from `GITHUB_REPOSITORY`, so the name a run sees
flips the instant the rename happens, whatever `.github` commit the caller pinned. Every map in
`wiring/lib.sh` ends `*) return 1`: a receiver whose pinned `.github` commit does not know
`opm-controller` fails closed on its first run after the rename (receive, gates and notify).

So the renamed repo needs its new-name arms in a `.github` commit it is pinned to **before** the
rename. This change adds them, keeping every old-name arm, so the cascade works on both sides of
the rename. A later change (`retire-operator-repo-name`) flips the lists that cannot hold both
names and drops the old ones.

## What Changes

- **Every map keyed by a receiver or a source accepts both names, with the same values:**
  `notify_targets` (as a source: `opm-controller` notifies `cli`), `receiver_sources`,
  `g3_upstreams` (as a receiver), `expect_pair`, `changelog_repos`, `publish_paths`,
  `publish_denied` (`modules/**` of either name), `receiver_classes`, `receiver_pins` (the
  parser renamed `pins_opm_controller`) and `mirror_sources` (one arm for both names, with
  today's hashes, so the renamed repo's publish and the daily drift run stay green until its own
  rename PR changes its hashed files). A helper `same_repo` pairs the two names, so
  `changelog_repos` leaves out the receiver under either name.
- **Values that name the repo as a source accept both names:** cli's `receiver_sources` lists
  `opm-operator` and `opm-controller`; `changelog_repos` lists both (a release list that cannot
  be read is already a note, not an error); the resolver's body source allow-list
  (`CASCADE_SOURCES` in `lib/prtext.sh`) holds both.
- **Pin keys and the module train:** `changelog_source` and the resolver's `tag_source`
  (`lib/release.sh`) map `github.com/open-platform-model/opm-controller` and
  `opmodel.dev/modules/opm_controller@v0` to repo `opm-controller`, tags `v*` and
  `opm_controller-v*`, beside the old keys.
- **cli's pin file under both paths:** `pins_cli` reads `internal/controller/pin.go`
  (`PinnedControllerVersion`, rows `opm-controller` and `opm-controller module`) and falls back
  to `internal/operator/pin.go` with the old rows; `publish_paths cli` and `is_derived_path`
  accept both paths.
- **Kept on the old name:** the target lists of `notify_targets` (they set the App token's
  `repositories:`, and a name GitHub does not know fails the mint for every target), cli's
  `g3_upstreams` value (read by API, which fails on a repo that does not exist yet),
  `MIRROR_RECEIVERS` and tag-ledger `REPOS` (both read the repo by name; the new name would fail
  until the rename). `wiring-check.sh` is not edited, so the pin bump needs no copy re-sync.
- **README:** a paragraph on the rename window and the two allow-list rows.

Not in this change: any receiver repo, the GitHub rename, rulesets or repo settings, and the
flip of the lists named above (owner steps and `retire-operator-repo-name`).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cascade-workflows`: a new requirement that the renamed repo is accepted under both names.
- `cascade-notify`: `opm-controller` is a source.
- `cascade-receive`: the allowlists, the derived paths, the deny-list and the pin mirror accept
  both names and both cli pin files.
- `cascade-gates`: G3 upstreams of `opm-controller`.
- `cascade-pr-text`: `opm-controller` is a triggering source.
- `cascade-resolver`: the `opm_controller-v*` train is checked against `main`.

## Impact

- Scripts: `.github/scripts/cascade/wiring/lib.sh`, `lib/release.sh`, `lib/prtext.sh`; tests in
  `wiring/test/cases/{lib,bound,notify}.sh` and `test/cases/{newest,prtext}.sh`.
- Callers: `cascade-notify`, `cascade-receive.yml`, `cascade-publish` and `cascade-gates.yml` in
  core, catalog_opm, library, opm-operator and cli run this code once their pin moves. This
  diff touches `wiring/lib.sh`, so it touches both `cascade-notify` and `cascade-publish`
  (workspace RELEASING.md, section "Moving the cascade pin"): the pin moves canary first under
  owner decision 37. Required pins before the GitHub rename: opm-operator (it runs as
  `opm-controller` afterwards) and cli (it accepts `opm-controller` as a source). library is the
  natural canary: its next beta release is planned before the rename and notifies
  `opm-operator` and `cli`. catalog_opm and core gain nothing from this pin and may skip it.

Depends on: the 0f9c6ac pin round (receivers on `.github` 0f9c6ac). Later:
`retire-operator-repo-name`, after the rename and the opm-controller and cli rename PRs merge.

## Why

`accept-controller-repo-name` let every cascade map answer to both `opm-operator` and
`opm-controller`, so the cascade kept working through the GitHub rename. Three things that change
cannot do wait for the rename and the receivers' own rename PRs:

- The target lists of `notify_targets` set the App token's `repositories:`; after the rename they
  must name `opm-controller`, and they cannot hold both names. Until they flip, a release of
  catalog_opm, library or cli mints a token for a stale name and its notify fails (the release
  freeze).
- The mirror hashes: opm-controller's rename PR changes three of its four hashed
  `.tasks/cascade/` files and cli's rename PR two of its three. Until `mirror_sources` records
  the merged files, a live publish of either refuses every plan and the daily drift run is red.
- The old name and its two-name plumbing are a trace the owner wants gone (no aliases, no
  traces).

This change flips the cascade to `opm-controller` only. It replaces the earlier plan's three
steps (a one-line `MIRROR_RECEIVERS` PR at the rename, a hash-neutral flip, then a hash round,
and a later tag-ledger cleanup) with one merge and one pin round, since the owner runs the whole
cutover in one sitting and the shorter freeze those splits bought does not matter there.

## What Changes

- **New name only, everywhere in `wiring/lib.sh`:** the target lists (`catalog_opm` notifies
  `library opm-controller cli`, `library` notifies `opm-controller cli`, `cli` notifies
  `catalog_opm opm-controller`), `receiver_sources`, `g3_upstreams` (cli reads `opm-controller`),
  `expect_pair`, `changelog_source` (`github.com/open-platform-model/opm-controller`,
  `opmodel.dev/modules/opm_controller@v0`), `changelog_repos`, `publish_paths`,
  `publish_denied`, `receiver_classes`, `receiver_pins`, `mirror_sources`. `same_repo` goes.
- **cli's pin file:** `internal/controller/pin.go` only (`pins_cli`, `publish_paths cli`,
  `is_derived_path`).
- **Resolver:** `tag_source` maps only `opmodel.dev/modules/opm_controller@vN`;
  `CASCADE_SOURCES` lists `opm-controller` only.
- **Unpinned readers on `.github` main:** `MIRROR_RECEIVERS` and tag-ledger `REPOS` name
  `opm-controller`. Both take effect at merge, with no pin. The ledger keeps its `opm-operator`
  rows and records the same tags again under `opm-controller` on its next run (no finding).
- **Mirror hashes (at cutover):** opm-controller's `pins.sh`, `lib.sh`, `classes`, `cascade.sh`
  and cli's `pins.sh`, `classes`, `cascade.sh`, read from their merged mains, and the read
  commits in the comment and README.
- **`wiring-check.sh` comments** name opm-controller, so every pin PR of this round re-syncs the
  byte-identical copy (`.tasks/cascade/wiring-check.sh`).
- **Tests, fixture (`test/fixtures/git/opm-controller.refs`), specs and README** follow. The
  `mention-guard.yml` comment names opm-controller.

Not in this change: any receiver repo, the pin bumps, rulesets or repo settings (owner steps).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cascade-notify`, `cascade-receive`, `cascade-gates`, `cascade-pr-text`, `cascade-resolver`,
  `cascade-wiring-check`, `cascade-workflows`, `tag-ledger`: `opm-controller` replaces
  `opm-operator`; requirements whose scenarios were named after the old repo are retitled
  (REMOVED plus ADDED); the two-name requirement is removed.

## Impact

- Scripts: `wiring/lib.sh`, `lib/release.sh`, `lib/prtext.sh`, `wiring-check.sh` (comments);
  workflows `tag-ledger.yml` (`REPOS`), `mention-guard.yml` (comment); every test suite.
- Callers: the five product repos run this code once their pin moves. The diff touches
  `wiring/lib.sh`, so both `cascade-notify` and `cascade-publish` (owner decision 37): canary
  first. **cli is the canary**: it needs this pin before its own release anyway (its target list
  names `opm-controller`), and that release's live notify mints a token for `catalog_opm
  opm-controller`, proving the new-name mint. After it succeeds: catalog_opm, library,
  opm-controller and core. Every pin PR also replaces `.tasks/cascade/wiring-check.sh`.
- `cascade-mirror-drift.yml` and `tag-ledger.yml` change behaviour at merge (unpinned).

Depends on: `accept-controller-repo-name` merged and pinned in opm-operator and cli before the
GitHub rename; the GitHub rename; the opm-controller rename PR and the cli rename PR merged
(their merged mains give the hashes). Later: the cli release, then the downstream follow-ups.

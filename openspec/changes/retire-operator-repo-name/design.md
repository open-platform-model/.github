## Context

`accept-controller-repo-name` (merged and pinned before the rename) made every receiver- and
source-keyed map answer to both names. After the GitHub rename, the opm-controller rename PR and
the cli rename PR merge on that pin while all receivers are `CASCADE_DRY_RUN=true`. This change
is the one `.github` round that follows.

## Goals / Non-Goals

**Goals:** one merge and one canary-first pin round that ends the release freeze, records the
final mirror hashes, and leaves no `opm-operator` in `.github` outside the archive.

**Non-Goals:** receiver PRs, ruleset edits, the cli release.

## Decisions

### D1: One round instead of B1, B2 and the MIRROR_RECEIVERS PR

The split rounds existed to shorten the freeze (flip right after the rename, hashes later). The
owner merges everything in one sitting, so the freeze is that sitting. The hashes need the merged
rename PRs; so does the flip's purpose (the cli release needs the flip pinned). So everything
lands together, after both rename PRs merge. `MIRROR_RECEIVERS` rides along: between the rename
and this merge the drift run reads `opm-operator` through GitHub's redirect and goes red once
the controller PR merges anyway; it is never required.

### D2: tag-ledger REPOS is not in this change

Before the rename, `git ls-remote` of `opm-controller` fails, which fails the whole run, so the
new name cannot be added early. After the rename, `git ls-remote` of `opm-operator` still follows
GitHub's redirect, but `tag-ledger.sh` `api_get` calls `curl` without `-L`: the ruleset listing
of the old name answers HTTP 301 and `check_ruleset` exits 3, so every ledger run fails until
`REPOS` names the new repo. This change merges only after both rename PRs and their releases, so
the flip cannot wait for it. It merges on its own as `scan-controller-in-tag-ledger`, right after
the rename and unpinned (`tag-ledger.yml` runs from `.github` `main`).

### D3: Hashes from merged mains, at cutover

A hash read from a PR head can differ from the squash merge. The `mirror_sources` entries for
`opm-controller` and `cli` MUST be computed from `origin/main` of each repo after its rename PR
merged, with `git show origin/main:.tasks/cascade/<file> | sha256sum`, and the read commits
written into the comment above `publish_paths` and the README's "Keeping the mirrors in step".
Until then the entries carry the pre-rename hashes and three `TODO(cutover)` comments (both arms
and the `publish_paths` comment); the change is not archived before they are recorded.
A hash only says the file is the one read; the paths the allow-lists hold must be re-read from
the same merged mains before the hashes are recorded: every path `cascade.sh` writes, and every
path the programs it runs write (cli's `hack/controller-pin`: `internal/controller/pin.go` and
`internal/controller/crds/<name>.yaml`).

### D4: cli is the canary

The diff touches `cascade-notify` and `cascade-publish`. The canary must release on the new pin
and its notify must mint for a new name. cli's release needs this pin first anyway (its target
list), and it notifies `catalog_opm opm-controller`. catalog_opm would prove the same but needs
a release nobody plans.

### D5: wiring-check.sh comments

The two comments that name the repo change, so each pin PR also replaces the receiver's
byte-identical copy. The rename PRs of opm-controller and cli MUST NOT touch their copy; it stays
equal to the pinned `accept-controller-repo-name` commit until this round.

## Risks / Trade-offs

- [A receiver goes live before this pin] -> a live publish of opm-controller or cli refuses every
  plan as a stale mirror; keep `CASCADE_DRY_RUN=true` until this pin is in place.
- [A rename PR's hashed file changes again after the hashes are read] -> the drift run goes red
  within a day; read the hashes after the last merge in that repo.
- [cli's cascade task writes more than `pin.go`] -> after cli's rename `hack/controller-pin` also
  rewrites the embedded CRD manifests in `internal/controller/crds/`; `publish_paths cli` accepts
  them, and `is_derived_path` lists them, so a `merge` conflict only in them takes `main`'s side
  like `pin.go` (task 1.5). A module version that adds or drops a CRD is a status `A`/`D` change,
  which `publish` refuses: a human lands that bump (supervisor default 2026-10-06, kept: widening
  the status rule would let the bot add files). Until then every cli cascade run, which carries all
  of cli's pins, is refused at publish; the human commits the bump on `deps/cascade`, and later bot
  runs build on that tip (`check_increment` leaves the old tip's commits out) and rewrite the
  manifest in place (status `M`). The allow-list re-check at cutover (task 4.1)
  reads what `hack/controller-pin` writes, not only `cascade.sh`.
- [Old-name rows in the tag ledger] -> data, not code; the ledger is append-only by design.

## Rollout

1. Merge after the opm-controller and cli rename PRs, with the hashes filled in.
2. Dispatch `cascade-mirror-drift.yml`; expect fourteen `ok` lines.
3. Pin round: cli first; after its release's notify succeeds, catalog_opm, library,
   opm-controller and core, each replacing `.tasks/cascade/wiring-check.sh`.

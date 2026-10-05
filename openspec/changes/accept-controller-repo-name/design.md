## Context

The cascade's fixed maps live in `wiring/lib.sh` and the resolver's tag sources in
`lib/release.sh`; both run at the `.github` commit each caller pins. The repo name comes from
`GITHUB_REPOSITORY` (Guard step), so it changes at the GitHub rename with no pin involved.
Receivers are on 0f9c6ac; all four are `CASCADE_DRY_RUN=true`.

## Goals / Non-Goals

**Goals:** a `.github` commit that works for the renamed repo before and after the rename, with
no change in behaviour for any other repo; no hash change; no `wiring-check.sh` change.

**Non-Goals:** flipping a target list, dropping an old name, new mirror hashes (all in
`retire-operator-repo-name`, after the rename and the receivers' rename PRs).

## Decisions

### D1: Receiver and source keys accept both names; values only where a miss is harmless

A case arm `opm-operator | opm-controller)` costs nothing when one name never occurs. A *value*
naming the repo is different: `notify_targets` values set the App token's `repositories:` (a
name GitHub does not know fails the mint for every target) and cli's `g3_upstreams` value is
read through the API (a 404 is an evaluator error). Those MUST keep `opm-operator` here.
`receiver_sources` and `CASCADE_SOURCES` values are allow-lists (an unused entry is inert), and
`changelog_repos` values are fetched with a failure recorded as `<repo>.failed`, which only
matters when a pin of that repo moved; both MAY hold both names.

### D2: One mirror arm for both names, today's hashes

`mirror_sources opm-operator | opm-controller)` keeps the 53ccaab hashes. After the rename, until
the controller rename PR merges, the renamed repo's `main` still holds those files, so a live
publish and the drift run stay green. Recording new hashes needs the merged rename PR and is
`retire-operator-repo-name`'s job.

### D3: `same_repo <a> <b>`

`changelog_repos` must leave out the receiver itself, under either name, or a receiver would
fetch its own releases through the old name's redirect. `same_repo` exits 0 for equal names and
for the pair `opm-operator`/`opm-controller`; the map test that the notify and receive edges
invert uses it too. It is removed with the old name.

### D4: cli's pin file, new path first

`pins_cli` tries `internal/controller/pin.go` (`PinnedControllerVersion`; rows
`github.com/open-platform-model/opm-controller` "opm-controller" and
`opmodel.dev/modules/opm_controller@v0` "opm-controller module", the display strings cli's
renamed `pins.sh` MUST print, since they become PR titles) and falls back to
`internal/operator/pin.go` with the old rows. Never both: cli has one pin file at any commit.

### D5: What stays out

`MIRROR_RECEIVERS` and tag-ledger `REPOS` read the repo by name on `.github` `main` (not pinned);
`opm-controller` 404s before the rename, so both flip in `retire-operator-repo-name`.
`wiring-check.sh` (comments only) is byte-copied into five repos; editing it now would add a copy
re-sync to every pin PR of this round.

## Risks / Trade-offs

- [After the rename, cli's G3 reads `opm-operator` through GitHub's rename redirect] -> unverified
  for `gh pr list`; at worst G3 is an evaluator error on a cli release PR during the freeze,
  which the freeze already rules out.
- [Old-pinned receivers after the rename] -> catalog_opm, library and cli releases mint a token
  for `opm-operator` and fail notify: the release freeze from the rename until the next pin is
  load-bearing (workspace RELEASING.md).

## Rollout

Pin canary first (owner decision 37; this diff touches `cascade-notify` and `cascade-publish`):
library, then its next release's live notify succeeds, then opm-operator and cli. catalog_opm
and core MAY skip this pin. Owner steps, not tasks.

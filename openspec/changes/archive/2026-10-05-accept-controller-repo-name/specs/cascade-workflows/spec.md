## ADDED Requirements

### Requirement: The renamed controller repo answers to both names

While the repo `opm-operator` is renamed `opm-controller`, every fixed map in `wiring/lib.sh`
keyed by a receiver or a source SHALL give `opm-operator` and `opm-controller` the same answer
(`expect_pair` differing only in the repo name it prints),
so a run of the renamed repo works at a pinned `.github` commit on both sides of the GitHub
rename. A value that names a repo GitHub must find (the target lists of `notify_targets`, which
set the App token's `repositories:`, and the upstreams G3 reads through the API) SHALL keep
`opm-operator` only. `same_repo <a> <b>` SHALL exit 0 for two equal names and for the pair
`opm-operator`, `opm-controller`, and 1 otherwise.

#### Scenario: The renamed repo as a receiver

- **WHEN** `receiver_sources`, `g3_upstreams`, `publish_paths`, `receiver_classes` and `mirror_sources` are asked for `opm-controller`
- **THEN** each prints what it prints for `opm-operator`

#### Scenario: A target list keeps the old name

- **WHEN** `notify_targets library` runs
- **THEN** it prints `opm-operator cli`, not `opm-controller`

#### Scenario: Two names, one repo

- **WHEN** `same_repo opm-controller opm-operator` and `same_repo opm-operator cli` run
- **THEN** the first exits 0 and the second exits 1

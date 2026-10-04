## Purpose

Which repos the daily tag-ledger check scans for release-tag drift and tag-ruleset drift, and
how adding a repo to that set, or removing one, affects the append-only ledger. Source:
workspace `AGENTS.md`, section "Release Tags Are Immutable", and workspace RELEASING.md, section
"Release order".

## ADDED Requirements

### Requirement: Scanned repos

The `tag-ledger` workflow SHALL scan exactly these `open-platform-model` repos: `core`,
`library`, `catalog_opm`, `cli`, `opm-operator` and `opm`. `release-flow-sandbox`, which is in
the workspace immutable-tag scope, SHALL stay excluded until the owner decides whether the ledger
covers it. A scanned repo that cannot be read SHALL fail the run, not drop out of the scan. Each
scanned repo SHALL get the same treatment, with no per-repo exceptions:

- every tag is recorded in the ledger;
- a recorded tag that is deleted or changed is a finding;
- the org rulesets `tags-immutable`, `tags-create-app-only` and `release-branches` are asserted.

The job summary's `Repos:` line SHALL name all six repos. The README's tag-ledger scope SHALL
list the same six repos as the workflow.

#### Scenario: An opm tag is recorded

- **WHEN** a trusted run finds `opm` tag `v1.0.0-beta.1` with commit `83a4756d4fe53c7b704d871e232d432fd5c96921` and no ledger row for it
- **THEN** the run appends the row `opm`, `v1.0.0-beta.1`, the object SHA, the peeled SHA and the run time, and reports no finding for it

#### Scenario: A moved opm tag is drift

- **WHEN** the ledger records `opm` `v1.0.0-beta.1` at one commit and `git ls-remote` now shows it at another, with no matching row in `tag-ledger/acknowledged.tsv`
- **THEN** the run reports `tag CHANGED` for `opm` `v1.0.0-beta.1` as a finding, opens or comments on the drift issue, and fails

#### Scenario: A missing opm tag ruleset is a finding

- **WHEN** the org ruleset `tags-immutable` does not apply to `opm`
- **THEN** the run reports a finding naming `opm` and `tags-immutable`, exactly as it would for `core`

#### Scenario: The summary names every scanned repo

- **WHEN** any run completes
- **THEN** its job summary contains `Repos: core library catalog_opm cli opm-operator opm.`

### Requirement: Joining and leaving the scan

Adding a repo to the scanned set SHALL NOT change, reorder or remove any existing ledger row,
and SHALL NOT need a bootstrap run. The first run after the addition SHALL record that repo's
current tags as new rows. Removing a repo from the set SHALL NOT report its recorded tags as
deleted. Its rows SHALL stay in the ledger, and comparison SHALL resume if the repo is added
back.

#### Scenario: First run after opm joins

- **WHEN** the ledger holds rows for the five earlier repos only and the next trusted run scans the six repos with no tag moved anywhere
- **THEN** every earlier row is byte-identical afterwards, the only new rows are `opm`'s tags and tags released since the previous run, no finding is reported, and no issue is opened

#### Scenario: Reverting the scope is silent

- **WHEN** the ledger holds `opm` rows and a run scans only the five earlier repos
- **THEN** no `opm` row is reported as deleted and every `opm` row is kept

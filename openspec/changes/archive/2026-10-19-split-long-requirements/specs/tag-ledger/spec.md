## REMOVED Requirements

### Requirement: Scanned repos
**Reason**: Split into three requirements that each state one behavior.
**Migration**: See "The tag-ledger scan covers exactly six repos", "Every scanned repo gets the same treatment" and "The summary and the reference name the scanned repos".

## ADDED Requirements

### Requirement: The tag-ledger scan covers exactly six repos

The `tag-ledger` workflow SHALL scan exactly these `open-platform-model` repos: `core`, `library`, `catalog_opm`, `cli`, `opm-operator` and `opm`. `release-flow-sandbox`, which is in the workspace immutable-tag scope, SHALL stay excluded until the owner decides whether the ledger covers it. A scanned repo that cannot be read SHALL fail the run, not drop out of the scan.

#### Scenario: An unreadable repo fails the run

- **WHEN** a scanned repo cannot be read during a run
- **THEN** the run fails and the repo does not drop out of the scan

### Requirement: Every scanned repo gets the same treatment

Each scanned repo SHALL get the same treatment, with no per-repo exceptions:

- every tag is recorded in the ledger;
- a recorded tag that is deleted or changed is a finding;
- the org ruleset `tags-immutable` is asserted, and a missing one is a finding;
- the org rulesets `tags-create-app-only` and `release-branches` are asserted when they apply to the repo, and a missing one is reported only as a pending warning, not a finding.

#### Scenario: An opm tag is recorded

- **WHEN** a trusted run finds `opm` tag `v1.0.0-beta.1` with commit `83a4756d4fe53c7b704d871e232d432fd5c96921` and no ledger row for it
- **THEN** the run appends the row `opm`, `v1.0.0-beta.1`, the object SHA, the peeled SHA and the run time, and reports no finding for it

#### Scenario: A moved opm tag is drift

- **WHEN** the ledger records `opm` `v1.0.0-beta.1` at one commit and `git ls-remote` now shows it at another, with no matching row in `tag-ledger/acknowledged.tsv`
- **THEN** the run reports `tag CHANGED` for `opm` `v1.0.0-beta.1` as a finding, opens or comments on the drift issue, and fails

#### Scenario: A missing opm tag ruleset is a finding

- **WHEN** the org ruleset `tags-immutable` does not apply to `opm`
- **THEN** the run reports a finding naming `opm` and `tags-immutable`, exactly as it would for `core`

### Requirement: The summary and the reference name the scanned repos

The job summary's `Repos:` line SHALL name all six repos. The tag-ledger reference (`references/tag-ledger.md`) SHALL name the workflow's repo list as the scope and SHALL NOT list a second copy of it.

#### Scenario: The summary names every scanned repo

- **WHEN** any run completes
- **THEN** its job summary contains `Repos: core library catalog_opm cli opm-operator opm.`

## Why

The comment rule of the enhancement format says that a Go or CUE comment may name an enhancement id only beside a reason in words, never as a decision number and never alone. `enh cite-lint` checks it. Each repo needs the same check at the same `enh` version, and one place must bump that version. `.github` has no such workflow, and its own rule text still tells authors to cite `0011:D9`.

## What Changes

- Add `.github/workflows/cite-lint.yml`: a reusable workflow (`workflow_call` only) that builds `enh` from `open-platform-model/enhancements` at one pinned commit and runs `enh cite-lint` on the calling repo. The pin is the default of its `enh-ref` input and is the only place that holds it.
- Add cases for the workflow to the wiring test suite: a new case file `.github/scripts/cascade/wiring/test/cases/citelint.sh`, named in the `files=` list of `run.sh`. One count in `cases/static.sh` (README pins) narrows to the four cascade references.
- Replace the rule text in `openspec/config.yaml` that tells authors to cite `NNNN:Dn` with the new comment rule, and add `references:` with the `opm-enhancements` store.
- Replace the one archived citation of a decision number (`0011:D7` in `add-release-cascade-workflows/contract.md`) with `enhancement 0011` and the decision title.
- Document the workflow and one caller example in `README.md`.

No repo calls the workflow yet: the per-repo changes of the same programme add the calls. Planned callers: core, library, catalog_opm, cli, opm-operator, modules, opmodel.dev, opm-portal, docs-kit, opm-suite-installer.

## Capabilities

### New Capabilities
- `cite-lint-workflow`: the reusable workflow that runs `enh cite-lint` at a pinned `enh` commit, with its inputs, permissions, pins and failure behaviour.

### Modified Capabilities

## Impact

- Files: `.github/workflows/cite-lint.yml` (new), `.github/scripts/cascade/wiring/test/{run.sh,cases/citelint.sh,cases/static.sh}`, `openspec/config.yaml`, one archived `contract.md`, `README.md`.
- Network at run time, in the callers' jobs only: `github.com` (two checkouts), the Go module proxy and checksum database (tool dependencies), the Go release feed (`actions/setup-go`).
- Depends on: nothing in this repo. The default pin names a commit on the unmerged branch `openspec-store-design` of `enhancements`; the enhancement-store migration (swarm task T5.9) moves it to the merged `main` commit.
- Later work: `wiring-check.sh` (the canonical copy that core, library, catalog_opm, cli and opm-operator keep) accepts only the cascade `.github` references and one `resolver` kind. A caller of `cite-lint.yml` in those five repos fails that check until a separate change adds a reference kind for it. This change does not touch `wiring-check.sh`.
- No `.github` ruleset or setting changes. Making the lint required org-wide is an owner step, later.

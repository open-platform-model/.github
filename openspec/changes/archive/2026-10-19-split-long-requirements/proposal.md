## Why

OpenSpec 1.14.1 raises the warning "Requirement text is very long (>500 characters)" from INFO to WARNING. `openspec validate --strict` fails on any warning, and no config key or flag turns the check off: the limit is a constant in the validator. The warning is right on the merits. A long requirement usually holds several behaviors, and one behavior per requirement makes each one testable by its own scenarios.

Today 55 requirements in 9 main specs of this repo are over the limit (measured on `origin/main` 48e9ead with `openspec validate --all --strict`: 55 WARNING lines, 0 ERROR). The repo gate `openspec validate --all --strict` therefore cannot pass. This change rewrites those requirements so that `--strict` passes again with no rule lost or changed, and adds the gate to CI so that the specs stay short.

## What Changes

- Rewrite the 55 long requirements, in two batches of whole specs, as splits or moves into scenarios (design.md says which form and why):
  - .github-B1 (28): `cascade-receive` 13, `cascade-resolver` 9, `cascade-resolver-checks` 5, `tag-ledger` 1.
  - .github-B2 (27): `cascade-workflows` 9, `cascade-wiring-check` 8, `cascade-gates` 4, `cascade-pr-text` 4, `cascade-notify` 2.
- The spec `cite-lint-workflow` has no long requirement and stays untouched. No spec of this repo has a placeholder Purpose.
- Add a step to the existing `Resolver tests` job of `.github/workflows/cascade-resolver.yml` that installs OpenSpec 1.14.1 from the pinned npm version and runs `openspec validate --all --strict --no-interactive`. The repo has no Taskfile, so CI is the only gate. The step adds no job and no check context. The spec of that workflow gets one new requirement that states the step.
- Change one sentence of `AGENTS.md`: it says CI runs the first three commands of its table, and it runs all four after this change.

No requirement or scenario changes its meaning. No script, no other workflow and no open change of another author is touched. `openspec/changes/` holds no other open change today.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cascade-receive`, `cascade-resolver`, `cascade-resolver-checks`, `tag-ledger` (batch B1): long requirements split or shortened. Delta specs are written unit by unit, not in this proposal step.
- `cascade-workflows`, `cascade-wiring-check`, `cascade-gates`, `cascade-pr-text`, `cascade-notify` (batch B2): same.
- `cascade-resolver-checks` also gains one ADDED requirement for the new CI step (batch order in design.md).

## Impact

- Files: `openspec/specs/*` through this change's deltas (at archive), `.github/workflows/cascade-resolver.yml`, `AGENTS.md`.
- Callers: no repo calls the changed spec text. The workflow change affects the required check `Resolver tests` of this repo only: every pull request now also runs the OpenSpec gate, so a PR that adds a long requirement fails that check. The owner must know this before merge.
- Depends on: nothing open. The 1.14.1 skill bump landed in this repo as PR 26. Later changes depend on this one: any new spec text here must pass the gate.
- Delivery: one PR, one commit per task group (Principle IV of `openspec/config.yaml`).
- Proposal gate: the owner reads this change before any delta is written.

## Enhancement

None.

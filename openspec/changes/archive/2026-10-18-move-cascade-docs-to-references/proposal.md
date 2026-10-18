## Why

The README held the agent-facing detail of every workflow of this repo. It is now a short overview, and the detail lives in one file per topic under `references/`. Five requirements still say "the README SHALL ...", and the canonical wiring-check script prints a citation of a README heading that no longer exists.

## What Changes

- Requirements that name the README now name the `references/` file that holds the text: the rollout order, the canonical wiring check, the byte-identical copies, the runbook for a failed API call and the scanned repos.
- `wiring-check.sh`: the header comment and the `differs from` message cite `references/cascade-wiring-check.md` instead of a README heading. No check changes.
- The wiring tests read the caller shapes, the bump procedure and the CI step from the `references/cascade-*.md` files instead of the README.

## Capabilities

### New Capabilities

### Modified Capabilities
- `cascade-workflows`: the rollout order is stated in the pinning reference.
- `cascade-wiring-check`: the shapes, the copy commands and the API-failure runbook are in the cascade reference files.
- `tag-ledger`: the scope is documented by naming the workflow's repo list.

## Impact

- Files: `.github/scripts/cascade/wiring-check.sh`, `.github/scripts/cascade/wiring/test/`, `README.md`, `references/`.
- Callers: core, library, catalog_opm, cli and opm-operator keep a byte-identical copy of `wiring-check.sh`. Each copy changes only when its repo moves its cascade pin to a `.github` commit that carries this change. Until then the check still passes, because it compares each copy with the file at its own pin.
- Depends on: nothing. No ruleset or setting change.

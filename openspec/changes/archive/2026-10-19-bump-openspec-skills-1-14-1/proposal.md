## Why

OpenSpec 1.14.1 makes the over-500-character requirement check a WARNING. `--strict` fails on any warning, and no flag turns the check off. The repo moves to 1.14.1 now so its generated skills match the tool that every other repo uses. A later change rewrites the long requirements of this repo and adds a 1.14.1 strict gate.

## What Changes

- Regenerate the `openspec-*` skills in `.claude/skills/` with 1.14.1 (`generatedBy: "1.14.1"`).
- All eleven skills are pristine 1.12.0 output today, so the update is a plain overwrite. No local edit exists to merge.
- Leave `openspec/config.yaml` untouched.
- This repo has no OpenSpec CLI pin, no Taskfile and no CLI gate. This change adds none.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. The change has no spec delta (`skip_specs: true`).

## Impact

- Files: `.claude/skills/openspec-*/SKILL.md` only. No workflow, script or spec text changes, and `mention-guard` and `tag-ledger` are not touched.
- Agent instruction files change, so the diff is reviewed as code and scanned for hidden Unicode.

## Enhancement

None.

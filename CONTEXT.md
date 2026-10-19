# open-platform-model/.github: where do I go?

Router only. Facts and rules are in `AGENTS.md`.

| Task | Read first | Then |
| --- | --- | --- |
| Change what `mention-guard` scans or allows, add a bot exception, or understand why a PR failed it | `references/mention-guard.md` | `.github/workflows/` |
| Change the tag drift check, the ledger, the ruleset assertions, or answer a drift issue | `references/tag-ledger.md` | `tag-ledger/`, `.github/scripts/` |
| Change the shared comment lint, its inputs or its tool pin | `references/cite-lint.md` | `.github/workflows/` |
| Change how a version is resolved, a resolver subcommand, an exit code or the stub | `references/cascade-resolver.md` | `.github/scripts/cascade/` |
| Change a cascade workflow, a composite action or a caller shape | `references/cascade-workflows.md` | `.github/workflows/`, `.github/actions/` |
| Change a dry-run rule, a repo variable or a stop switch of the cascade | `references/cascade-switches.md` | `.github/actions/` |
| Change what `compute` or `publish` may do, an allow-list path or a receiver mirror because a receiver's own file changed | `references/cascade-security.md` | `.github/scripts/cascade/wiring/` |
| Roll a change out to the product repos, move a pin or pick a canary | `references/cascade-pinning.md` | `.github/scripts/cascade/wiring/` |
| Change the wiring check, its config or a failure of its CI step | `references/cascade-wiring-check.md` | `.github/scripts/cascade/` |
| Change a script that is not part of the cascade, or any workflow not named above | `openspec/config.yaml` | `.github/scripts/`, `.github/workflows/` |
| Add or change code owners, Dependabot or the actionlint config | `AGENTS.md` | `.github/` |
| Start a feature change or alter a spec | `openspec/config.yaml` | `openspec/` |
| Choose a commit type or write a commit message, PR title or PR body | `references/git-text.md` at the workspace root | `AGENTS.md` |
| Read the human overview | `README.md` | |

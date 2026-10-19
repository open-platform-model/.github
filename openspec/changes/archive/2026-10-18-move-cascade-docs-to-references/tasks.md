## 1. The docs

- [x] 1.1 Split the README into `references/` files, add the agent files, and point the wiring tests at the cascade reference files; verify the two offline suites, `shellcheck` and `actionlint` pass, then commit `docs: split AGENTS.md into facts, a router and reference files`

## 2. The script citation

- [x] 2.1 Change the header comment and the `differs from` message of `wiring-check.sh` to cite `references/cascade-wiring-check.md`; verify the wiring suite ends with 0 failed and `shellcheck` is clean, then commit `docs(cascade): cite the wiring-check reference in the check`

## 3. The specs

- [x] 3.1 Write the MODIFIED requirements; verify `openspec validate move-cascade-docs-to-references --strict`, then commit `docs(openspec): move the cascade doc requirements to references`

## Workflow follow-up

- Archive the change on the branch with `chore(openspec): archive move-cascade-docs-to-references`.

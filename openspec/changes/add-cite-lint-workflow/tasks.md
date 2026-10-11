## 1. The workflow and its static cases

- [ ] 1.1 Add `.github/workflows/cite-lint.yml` as the design says; verify with `actionlint .github/workflows/*.yml` (exit 0 with the repo's `.github/actionlint.yaml`) and a zizmor offline run with no finding on the file
- [ ] 1.2 Run the two shell steps of the workflow against a scratch repo with a bad and a good Go file and verify: a 40-hex `enh-ref` passes, `main` and a short SHA fail, `../x`, `/etc` and `-n` fail, a clean run exits 0 and a decision number exits 1 with `path:line` lines
- [ ] 1.3 Add the `cite-lint.yml` block to `.github/scripts/cascade/wiring/test/cases/static.sh` (design D7) and verify `bash .github/scripts/cascade/wiring/test/run.sh` ends with 0 failed
- [ ] 1.4 `actionlint`, `shellcheck` on the test cases, the wiring test suite and `openspec validate --all --strict` green, then commit `feat(cite-lint): add the shared cite-lint workflow`

## 2. The rule text and the references

- [ ] 2.1 Replace the `Comments` bullet of `openspec/config.yaml` that cites `0011:D9` with the new comment rule, and add `references:` with `- id: opm-enhancements` and its `remote`; verify `grep -rnE '[0-9]{4}:(D|OQ)[0-9]+' openspec/config.yaml` prints nothing and `openspec instructions proposal --change add-cite-lint-workflow --json` still reads the config
- [ ] 2.2 Replace `0011:D7` in `openspec/changes/archive/2026-10-04-add-release-cascade-workflows/contract.md` with `enhancement 0011 ("<decision title>")`; verify `git grep -nE '[0-9]{4}:(D|OQ)[0-9]+' -- . ':!openspec/changes/add-cite-lint-workflow'` prints nothing
- [ ] 2.3 `openspec validate --all --strict` green, then commit `docs(openspec): state the comment rule without decision numbers`

## 3. The README

- [ ] 3.1 Add a `cite-lint` section to `README.md`: what the workflow checks, its inputs, how a repo calls it (one example with the SHA pin form callers use), where the pin lives and how it moves; verify the example `uses:` line has the form of the existing `cascade-gates.yml` example and that `grep -n cite-lint README.md` finds the section
- [ ] 3.2 `openspec validate --all --strict` green, then commit `docs: document the cite-lint workflow`

## Workflow follow-up

- Verify with `openspec-verify-change`, review, then archive the change on the branch with `chore(openspec): archive add-cite-lint-workflow`.

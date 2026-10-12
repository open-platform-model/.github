## 1. The pin

- [x] 1.1 Set the default of `enh-ref` in `.github/workflows/cite-lint.yml` to the `main` commit `e0335b2ec44e659c0191bc3523d79d17f26f8e7d` and fix its comments; verify `actionlint` and the `citelint.sh` cases pass, then commit `fix(cite-lint): pin enh at the merged main commit`

## 2. The wiring check

- [ ] 2.1 Add the kind `cite-lint` and the plain-call rule to `wiring-check.sh` with cases in `cases/wiringcheck.sh`; verify `bash .github/scripts/cascade/wiring/test/run.sh` ends with 0 failed and `shellcheck` is clean, then commit `feat(cascade): let the wiring check accept a cite-lint call`

## 3. The README

- [ ] 3.1 Document the declaration in `README.md` beside the cite-lint call example; verify the suite and `openspec validate pin-merged-cite-lint --strict`, then commit `docs: declare the cite-lint call for the wiring check`

## Workflow follow-up

- Verify with `openspec-verify-change`, review, then archive the change on the branch with `chore(openspec): archive pin-merged-cite-lint`.

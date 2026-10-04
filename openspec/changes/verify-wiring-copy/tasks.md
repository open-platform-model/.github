Gates for every section (the repo's Validation Gates): `shellcheck` on every `*.sh` under
`.github/scripts/` and on every test shim; `actionlint` on `.github/workflows/*.yml`;
`bash .github/scripts/cascade/test/run.sh` and `bash .github/scripts/cascade/wiring/test/run.sh`;
`openspec validate --all --strict`. All run offline. Design references are to this change's
`design.md` (D1 to D4). The planning artifacts are committed first as
`docs(openspec): plan verify-wiring-copy`.

## 1. The copy compares itself with the pinned file

- [x] 1.1 `wiring-check.sh`: capture `${BASH_SOURCE[0]}`; with `--pin-on-main`, after `compare`, fetch the canonical file at the SHA (raw) and `cmp` it; the offline note after the ok line; header comment (D1)
- [x] 1.2 Test helper `gh_fx_file` (a fixture answer whose stdout is a file's exact bytes); cases: identical copy passes, a one-byte drift fails, a failed fetch fails, a failed compare makes no fetch, offline prints the note and makes no request, the copy run from the fixture's `.tasks/cascade/` as CI runs it; existing `--pin-on-main` and ok cases adapted
- [x] 1.3 Gates green, then commit `fix(cascade): compare the wiring check copy with the pinned file`

## 2. Declared extra references and credential-free resolver checkouts

- [ ] 2.1 `wiring-check.sh`: the `extra-references` key and its strict validation; expected references from it; the resolver checkout shape rule (D2, D3)
- [ ] 2.2 Cases: a declared `module-deps.yml` resolver passes; at another SHA, undeclared, declared but missing, without the pin comment fail; config refusals (wrong type, item keys, kind, file path); a token, an `ssh-key`, `persist-credentials: true` and a non-checkout action on a resolver checkout fail
- [ ] 2.3 Proof outside the suite (recorded in the PR body): the new script, offline, against core, catalog_opm, library and cli `origin/main` with their configs, and against opm-operator `origin/main` with its wave-2 config plus `extra-references`
- [ ] 2.4 Gates green, then commit `fix(cascade): let a repo declare extra pinned resolver checkouts`

## 3. README

- [ ] 3.1 The wiring-check section: the copy comparison and its limit, `extra-references` with opm-operator's value, the resolver checkout rule; "Keeping the copy in sync" and pin-bump steps 3 and 4 say CI compares the copy (D1, D2, D3)
- [ ] 3.2 Runbook for a failed API call (D4)
- [ ] 3.3 Gates green (the README-shape cases still pass), then commit `docs(cascade): document the copy comparison and the API-failure runbook`

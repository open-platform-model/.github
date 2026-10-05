Gates for every section (the repo's Validation Gates): `shellcheck` on every `*.sh` under
`.github/scripts/` and on every test shim; `actionlint` on `.github/workflows/*.yml`;
`bash .github/scripts/cascade/test/run.sh` and `bash .github/scripts/cascade/wiring/test/run.sh`;
`openspec validate --all --strict`. All run offline. The planning artifacts are committed first
as `docs(openspec): plan scan-controller-in-tag-ledger`.

## 1. The ledger scans opm-controller

- [ ] 1.1 `tag-ledger.yml` `REPOS`: `core library catalog_opm cli opm-controller opm`
- [ ] 1.2 README tag-ledger scope names `opm-controller`
- [ ] 1.3 Gates green, then commit `ci(tag-ledger): scan opm-controller in place of opm-operator`

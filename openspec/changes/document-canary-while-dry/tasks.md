Gates (the repo's Validation Gates): `shellcheck` on every `*.sh` under `.github/scripts/` and on
every test shim; `actionlint` on `.github/workflows/*.yml`; `bash .github/scripts/cascade/test/run.sh`
and `bash .github/scripts/cascade/wiring/test/run.sh` (its static cases read the README's caller
shapes, which this change leaves alone); `openspec validate --all --strict`. The planning
artifacts are committed first as `docs(openspec): plan document-canary-while-dry`.

## 1. README

- [x] 1.1 "Pinning and bumps" step 2 and step 4: the rollout order of owner decision 37, including what "dry" means for notify
- [x] 1.2 Wiring-check config table: opm-operator's seven `publish-workflows`, checked against its `.tasks/cascade/wiring-check.yaml` on `main`
- [x] 1.3 Stale lines: the `mention-guard` squash settings, the copy-sync guard without required review, the `module-deps.yml` residual risk, `sha_pinning_required` in every repo; two accepted risks in "What stays open"
- [x] 1.4 Gates green, then commit `docs(cascade): allow all receivers to move together while dry`

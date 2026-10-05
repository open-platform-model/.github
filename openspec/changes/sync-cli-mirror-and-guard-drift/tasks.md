Gates for every section (the repo's Validation Gates): `shellcheck` on every `*.sh` under
`.github/scripts/` and on every test shim; `actionlint` on `.github/workflows/*.yml`;
`bash .github/scripts/cascade/test/run.sh` and `bash .github/scripts/cascade/wiring/test/run.sh`;
`openspec validate --all --strict`. All run offline. Design references are to this change's
`design.md` (D1 to D4). The planning artifacts are committed first as
`docs(openspec): plan sync-cli-mirror-and-guard-drift`.

## 1. The mirrors follow the receivers' main

- [ ] 1.1 `lib.sh`: `publish_paths cli` allows `internal/operator/pin.go` instead of `manifest.go` and `dist/install.yaml`; `pins_cli` reads `pin.go` and prints the operator and operator module rows; `is_derived_path` takes `internal/operator/pin.go` and drops the deleted files; `changelog_source` maps the module pin; `publish_denied` refuses opm-operator's `modules/**`; the read commits in the comment (D1, D2)
- [ ] 1.2 Cases: the cli mirror reports the module row; cli's allow-list takes `pin.go` and refuses the deleted files and `hack/operator-pin`; opm-operator refuses `modules/opm_operator/**`; derived paths; the module's changelog source
- [ ] 1.3 Proof outside the suite (recorded in the PR body): each receiver's real `pins.sh` against the mirror on its last 150 `main` commits; `classes` against `receiver_classes`; each receiver's own cascade suite from `origin/main` with its sandboxes kept, every changed path through `publish_path_ok`
- [ ] 1.4 Gates green, then commit `fix(cascade): follow cli's operator module pin in the publish mirror`

## 2. Publish refuses a stale mirror

- [ ] 2.1 `lib.sh`: `mirror_sources` with the sha256 of each receiver's `pins.sh`, `lib.sh` (library, opm-operator) and `classes` on `main`, `MIRROR_RECEIVERS`, `mirror_stale_text` (D3)
- [ ] 2.2 `receive-publish.sh`: `check_mirror` first in `push` and `recreate`, against `origin/main`; header comment (D3)
- [ ] 2.3 Test toy: the sandbox's own `pins.sh` byte for byte; the labelled toy `pins.sh` committed by the one compute case that needs it; cases: a changed `pins.sh` on main refuses with both hashes and before the path checks, a removed `classes` refuses with `missing`, an unrelated change on main passes, every receiver records its files
- [ ] 2.4 Gates green, then commit `fix(cascade): refuse a stale publish mirror`

## 3. The daily drift check

- [ ] 3.1 `wiring/mirror-drift.sh` (D4)
- [ ] 3.2 `.github/workflows/cascade-mirror-drift.yml` (D4)
- [ ] 3.3 Cases (`wiring/test/cases/drift.sh`): matching files pass; a changed file fails naming receiver, file and both hashes; a failed read fails and the rest is still checked; an unknown receiver is usage; the default reads the ten product files; the workflow is read-only, daily, secret-free and keeps no credentials
- [ ] 3.4 Live run of the script against the four receivers (recorded in the PR body)
- [ ] 3.5 Gates green, then commit `ci(cascade): check the publish mirrors against the receivers daily`

## 4. README

- [ ] 4.1 Allow-list table (cli), deny-list (opm-operator `modules/**`), "Keeping the mirrors in step" (hashes, refusal, drift check, merge order, how to prove a mirror), the drift workflow next to the live checks, residual risk (stale mirror halts a receiver; the module pin's tag is not checked against `main`)
- [ ] 4.2 Gates green (the README-shape cases still pass), then commit `docs(cascade): document the mirror hashes and the drift check`

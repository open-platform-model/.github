Gates for every section (the repo's Validation Gates): `shellcheck` on every `*.sh` under
`.github/scripts/` and on every test shim; `actionlint` on `.github/workflows/*.yml`;
`bash .github/scripts/cascade/test/run.sh` and `bash .github/scripts/cascade/wiring/test/run.sh`;
`openspec validate --all --strict`. All run offline. The planning artifacts are committed first
as `docs(openspec): plan retire-operator-repo-name`. Section 4 waits for the cutover (design D3);
archive only after it.

## 1. The cascade names opm-controller only

- [x] 1.1 `wiring/lib.sh`: flip the three target lists; `opm-controller` only in `receiver_sources`, `g3_upstreams`, `expect_pair`, `changelog_source`, `changelog_repos`, `publish_paths`, `publish_denied`, `receiver_classes`, `receiver_pins`, `mirror_sources`; drop `same_repo`; cli's pin file `internal/controller/pin.go` only; `MIRROR_RECEIVERS`
- [x] 1.2 `lib/release.sh` `tag_source` and `lib/prtext.sh` `CASCADE_SOURCES` drop the old name
- [x] 1.3 Cases follow; `git mv test/fixtures/git/opm-operator.refs test/fixtures/git/opm-controller.refs`; cli's e2e fixture path `tests/e2e/testdata/controller-owned`
- [x] 1.4 Gates green, then commit `refactor(cascade)!: name opm-controller only in the cascade maps`
- [x] 1.5 `publish_paths cli` and `is_derived_path` accept cli's `internal/controller/crds/<name>.yaml`, which `hack/controller-pin` writes beside the pin (never `crds.go` or a subdirectory); cases in `wiring/test/cases/{bound,lib}.sh`; README allow-list table; gates green, then commit `feat(cascade): accept cli's embedded controller CRDs`

## 2. Workflows and the canonical wiring check

- [x] 2.1 The two `wiring-check.sh` comments (D5), the wiring-check case fixture `Controller module deps` and the `mention-guard.yml` comment name `opm-controller`. `tag-ledger.yml` `REPOS` and the README tag-ledger scope are not in this change: they belong to `scan-controller-in-tag-ledger` (D2), and no commit here touches them
- [x] 2.2 Gates green, then commit `ci(cascade): name opm-controller in the wiring-check and mention-guard comments`

## 3. README

- [x] 3.1 Every repo, module and path name; the rename-window paragraph removed
- [x] 3.2 Gates green, then commit `docs(cascade): name opm-controller in the README`

## 4. Mirror hashes from the merged mains (cutover)

- [ ] 4.1 Re-check the allow-lists before reading the hashes (CUTOVER P4.4): every path opm-controller's and cli's merged `.tasks/cascade/cascade.sh` writes (`git diff 53ccaab origin/main` and `git diff bd4d1a7c origin/main` on it) **and** every path the programs it runs write (cli's `hack/controller-pin` on `origin/main`: `grep -n 'pinFile\|crdDir\|WriteFile\|CreateTemp\|Rename\|Remove' hack/controller-pin/main.go`; today `internal/controller/pin.go` and `internal/controller/crds/<name>.yaml`, staged as `.<name>.*.tmp` and renamed in place, and a dropped manifest is `os.Remove`d, status `D`; opm-controller's equivalents likewise) matches a `publish_paths <receiver>` pattern and none hits `publish_denied`; a written file that is not derived but should be goes into `is_derived_path` too. A missing path is added here, with cases, before 4.2. A CRD a module version adds or drops stays status `A`/`D`, refused: a human lands that bump
- [ ] 4.2 After the opm-controller and cli rename PRs merge: `git show origin/main:.tasks/cascade/<file> | sha256sum` for opm-controller's `pins.sh`, `lib.sh`, `classes`, `cascade.sh` and cli's `pins.sh`, `classes`, `cascade.sh`; write them into `mirror_sources`, drop the three `TODO(cutover)` comments (`wiring/lib.sh`: the `publish_paths` comment and the `opm-controller` and `cli` arms of `mirror_sources`), and record the two read commits (short SHAs) in the `publish_paths` comment and the README's "Keeping the mirrors in step"
- [ ] 4.3 Check the cli mirror against cli's real `pins.sh` on its merged main (`CASCADE_PINS_REPO=cli bash .github/scripts/cascade/wiring/pins.sh origin/main` against `.tasks/cascade/pins.sh origin/main` in a cli checkout), and the opm-controller mirror likewise
- [ ] 4.4 `! git grep -n 'TODO(cutover)' -- .github README.md` (no comment left), gates green, then commit `fix(cascade): record the renamed receivers' mirror hashes`

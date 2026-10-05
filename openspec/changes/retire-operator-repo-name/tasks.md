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

## 2. Workflows and the canonical wiring check

- [ ] 2.1 `tag-ledger.yml` `REPOS` scans `opm-controller` (D2); the `mention-guard.yml` comment; the two `wiring-check.sh` comments (D5) and the wiring-check case fixture `Controller module deps`
- [ ] 2.2 Gates green, then commit `ci(tag-ledger): scan opm-controller in place of opm-operator`

## 3. README

- [ ] 3.1 Every repo, module and path name; the rename-window paragraph removed
- [ ] 3.2 Gates green, then commit `docs(cascade): name opm-controller in the README`

## 4. Mirror hashes from the merged mains (cutover)

- [ ] 4.1 After the opm-controller and cli rename PRs merge: `git show origin/main:.tasks/cascade/<file> | sha256sum` for opm-controller's `pins.sh`, `lib.sh`, `classes`, `cascade.sh` and cli's `pins.sh`, `classes`, `cascade.sh`; write them into `mirror_sources`, drop both `TODO(cutover)` comments, and record the two read commits (short SHAs) in the `publish_paths` comment and the README's "Keeping the mirrors in step"
- [ ] 4.2 Check the cli mirror against cli's real `pins.sh` on its merged main (`CASCADE_PINS_REPO=cli bash .github/scripts/cascade/wiring/pins.sh origin/main` against `.tasks/cascade/pins.sh origin/main` in a cli checkout), and the opm-controller mirror likewise
- [ ] 4.3 Gates green, then commit `fix(cascade): record the renamed receivers' mirror hashes`

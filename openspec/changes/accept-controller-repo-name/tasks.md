Gates for every section (the repo's Validation Gates): `shellcheck` on every `*.sh` under
`.github/scripts/` and on every test shim; `actionlint` on `.github/workflows/*.yml`;
`bash .github/scripts/cascade/test/run.sh` and `bash .github/scripts/cascade/wiring/test/run.sh`;
`openspec validate --all --strict`. All run offline. The planning artifacts are committed first
as `docs(openspec): plan accept-controller-repo-name`.

## 1. The maps accept both names

- [x] 1.1 `wiring/lib.sh`: `same_repo`; both names in the keys of `notify_targets`, `receiver_sources`, `g3_upstreams`, `expect_pair`, `changelog_repos`, `publish_paths`, `publish_denied`, `receiver_classes`, `receiver_pins` and `mirror_sources` (today's hashes); cli's `receiver_sources` value and the `changelog_repos` list hold both; target lists, cli's `g3_upstreams` value and `MIRROR_RECEIVERS` unchanged (D1, D2, D3, D5)
- [x] 1.2 `wiring/lib.sh`: `changelog_source` maps `github.com/open-platform-model/opm-controller` and `opmodel.dev/modules/opm_controller@v0`; `pins_cli` reads `internal/controller/pin.go` first (D4); `publish_paths cli` and `is_derived_path` take both pin paths; `pins_opm_operator` renamed `pins_opm_controller`
- [x] 1.3 `lib/release.sh`: `tag_source` maps `opmodel.dev/modules/opm_controller@v[0-9]*` to `opm-controller opm_controller-`; `lib/prtext.sh`: `CASCADE_SOURCES` holds `opm-controller`
- [x] 1.4 Cases: notify, receive, G3, expect pair, changelog sources and repos, classes, paths, mirror and derived paths under the new name; the edge-inversion test pairs the names; cli's mirror after its pin file moves; resolver `tag-on-main` on the `opm_controller-` train; the body accepts `opm-controller` as a source
- [x] 1.5 Gates green, then commit `feat(cascade): accept opm-controller beside opm-operator`

## 2. README

- [ ] 2.1 "The opm-operator rename" paragraph under Cascade workflows; the allow-list rows of opm-operator and cli
- [ ] 2.2 Gates green, then commit `docs(cascade): document the opm-operator rename window`

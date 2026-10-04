Gates for every section (the repo's Validation Gates): `shellcheck` on every `*.sh` under
`.github/scripts/` and on every test shim; `actionlint` on `.github/workflows/*.yml`;
`bash .github/scripts/cascade/test/run.sh` and `bash .github/scripts/cascade/wiring/test/run.sh`;
`openspec validate --all --strict`. All run offline. Design references are to this change's
`design.md` (D1 to D9). The planning artifacts are committed first as
`docs(openspec): plan bound-cascade-publish`.

## 1. The resolver refuses tags that are not on main

- [x] 1.1 `lib/release.sh`: `on_main <repo> <tag>` (tree-less bare clone once per repo per run, fetch of the one tag, `merge-base --is-ancestor`, the `ls_remote_tags` isolation, four attempts) and `tag_source` (pin key to repo and tag prefix) (D5)
- [x] 1.2 `lib/newest.sh` `probe_first`: skip a published candidate whose tag is not on main, with the warning; the script header and README name the check
- [x] 1.3 Test shim `git`: `clone` and `fetch` of a `https://github.com/open-platform-model/<repo>` URL answer from a fixture repo `$CASCADE_FIXTURE_DIR/git/<repo>.git` (fail when absent); every existing case that walks a tagged kind gets a fixture repo with its tags on main; new cases: a forged go tag skipped for the older one, a catalog tag with `opm-`, a tag missing, a clone failing four times (exit 1), no credentials or config reaching the clone
- [x] 1.4 Gates green, then commit `fix(cascade): propose only upstream tags that are on their repo's main`

## 2. Publish bounds the increment and renders the PR text

- [x] 2.1 `lib.sh`: `publish_paths`, `publish_path_ok`, the deny-list, `receiver_classes`, `receiver_pins` for catalog_opm, library, opm-operator, cli and cascade-sandbox-down (D1, D2); new `wiring/pins.sh`
- [x] 2.2 `receive-publish.sh verify`: the increment range, the drop check, the per-commit checks (D1); the scratch worktree, filtered warnings, payload from the event, Notes from the live PR, the resolver's `title` and `body`, the final title, the body limits and the derived labels with the publish-side breaking check (D2); `close` keeps a branch with human commits
- [x] 2.3 `receive-compute.sh text`: copy the task's warnings to `$CASCADE_T/warnings.tsv`; `cascade-receive.yml` uploads it; `cascade-publish/action.yml` passes `CASCADE_EVENT` and `CASCADE_PAYLOAD` to verify
- [x] 2.4 Cases: the refusals of D1 (a bundle touching `.tasks/cascade/pins.sh`, `Taskfile.yml`, a symlink, a mode change, an added file, a non-bot author, a non-bot committer, three commits, a merge whose tree differs, a rebuild over a human commit, `close` keeping a human branch); merge mode with a human commit accepted; derived text (a forged plan title ignored, planted body text gone, Notes from the live PR, warnings filtered); labels (a plan without `need-human-review` or `deps-cascade:breaking` gets them, a failed release read keeps the plan's claim, act never removes them); the existing publish cases adapted
- [x] 2.5 Cases: `publish_path_ok` per receiver (each allowed path, the deny-list over the allow-list, cli's two hack paths); `receiver_pins` per receiver against fixture trees copied from each receiver's `origin/main` files
- [x] 2.6 Gates green, then commit `fix(cascade): bound what publish accepts from compute`
- [x] 2.7 Proof outside the suite (recorded in the PR body, not committed): each receiver's real `pins.sh` and the mirror agree on its `origin/main` history; each receiver's offline cascade suite leaves only paths `publish_path_ok` accepts

## 3. Compute: main's task in merge mode, payload tags, pinned tools

- [x] 3.1 `receive-compute.sh run`: the merge-mode overlay of `main`'s `.tasks/` and `Taskfile*`, `CASCADE_ALLOW_DIRTY=1`, the commit without those paths (D3)
- [x] 3.2 `lib.sh validate_payload`: control characters refused, tags checked NUL-delimited with `valid_tag` (D4)
- [x] 3.3 New `wiring/install-tools.sh` (D7); `cascade-receive.yml` runs it instead of `setup-cue` and `setup-task`
- [x] 3.4 Cases: a merge-mode branch whose human commit changes `.tasks/cascade/cascade.sh` runs `main`'s task and keeps the branch's file; the toy task honours `CASCADE_ALLOW_DIRTY`; a trailing-newline tag and a control character in `source` dropped; the installer against a fixture archive (good checksum, bad checksum, unknown CUE version, `setup-cue` off); static cases for the install step
- [x] 3.5 Gates green, then commit `fix(cascade): run main's task in merge mode and pin compute's tools`

## 4. The release key needs the release Environment

- [x] 4.1 `wiring-check.sh`: the release-key rule (D6); header and README list it
- [x] 4.2 Cases: a reader without the Environment, with it, the key in lower case and with spaces, `environment: Release` on a non-reader, a map Environment, `secrets: inherit`, the fixture's existing shapes still passing
- [x] 4.3 Gates green, then commit `feat(cascade): bind the release key to the release Environment in the wiring check`

## 5. This repo's governance and the residual risk

- [x] 5.1 `.github/CODEOWNERS` (D8); `mention-guard.yml` at the `actions/github-script` SHA
- [x] 5.2 Static cases: every workflow of this repo has top-level `permissions:` and only SHA-pinned `uses:` with a version comment
- [x] 5.3 README: the increment bounds, the mirrors and how to keep them in step, tags on main, pinned tools, the release-key rule, the residual risk (D9); a workspace `RELEASING.md` patch for the supervisor
- [x] 5.4 Gates green, then commit `ci: add code owners, pin mention-guard and record the residual risk`

## 6. Review fixes

- [x] 6.1 `receive-publish.sh verify` refuses a `recreate` when `origin/main..old` holds a commit the bot did not make; case: the branch `close` kept, planned as `recreate` on the next run
- [x] 6.2 The resolver's `tag-on-main <pin-key> <v>`; `receive-publish.sh verify` runs it on every moved pin and refuses one not on main; cases in both suites (the wiring suite's git shim hands the clone to the resolver's)
- [x] 6.3 README and D9: residual risk of merge mode's non-task branch code and of opm-operator's own `module-deps.yml` publisher; opm-operator mirror recheck through `05d0396`

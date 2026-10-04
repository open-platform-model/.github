Gates for every section (the repo's Validation Gates): `shellcheck` (pinned v0.11.0) on every
`*.sh` under `.github/scripts/` and on every test shim; `actionlint` (pinned v1.7.12) on
`.github/workflows/*.yml`; `bash .github/scripts/cascade/test/run.sh` and
`bash .github/scripts/cascade/wiring/test/run.sh`; `openspec validate --all --strict`. All run
offline. Design references are to this change's `design.md` (D1 to D5). The planning artifacts
are committed first as `docs(openspec): plan harden-cascade-publish`.

## 1. Gates-only runs never publish

- [ ] 1.1 `cascade-publish/action.yml`: add the required input `gates-only` (description names the caller expression) and pass it to `Verify the plan` and `Act` as `CASCADE_PUBLISH_GATES_ONLY` (D1 point 2)
- [ ] 1.2 `receive-publish.sh`: a `gates_only_switch` checked first in `verify` and `act`, before the dry-run input, the plan and any API call; `true` refuses with "a gates-only run never publishes", any value but `false` refuses; header documents the variable
- [ ] 1.3 `cascade-receive.yml`: `compute` outputs `action` and `ok` computed from `inputs.gates-only` (D1 point 3); the header comment says so; `receive-compute.sh init` records a gates-only run as a dry run
- [ ] 1.4 README receiver caller shape: `inputs.gates_only != true` in the `publish` `if:` and `gates-only: ${{ inputs.gates_only == true }}` on the `Publish` step; the stop-switch paragraph and the variables table say `false` in any letter case
- [ ] 1.5 Cases: a complete plan from a real compute run with `CASCADE_PUBLISH_GATES_ONLY=true` (verify and act refuse, no gh call, nothing pushed, no `publish=true`); the input empty, unset, `False`, `TRUE`; a gates-only compute run whose release head forges `action=push`/`ok=true` (outputs stay `action=gates-only`, `dry_run=true`); static checks of the action input, the two output expressions and the README caller; wiring suite green
- [ ] 1.6 Gates green, then commit `fix(cascade): refuse to publish from a gates-only run`

## 2. Repo code is cut off from the command files and tokens

- [ ] 2.1 `lib.sh` `run_repo_code`: also unset `GITHUB_ENV`, `GITHUB_PATH`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`, `GITHUB_STATE`, every exported `ACTIONS_*` and every `GIT_CONFIG_KEY_<n>`/`GIT_CONFIG_VALUE_<n>` (D3); add the `changelog_repos` map
- [ ] 2.2 `gates-eval.sh read|run` (D2): `read` lists, evaluates G3, fetches the heads and writes `gates-read.json`; `run` runs G2 from it with no token and writes `gates.json`
- [ ] 2.3 `receive-compute.sh`: new step `gates-read`; `gates` runs `gates-eval.sh run`; `state` also fetches the upstream releases into `$CASCADE_T/releases/`; `breaking_check` reads those files only; `text` no longer masks or needs a token
- [ ] 2.4 `cascade-receive.yml`: the `Read gates` and `Read state` steps before `Gates`; `Gates` with `!cancelled() && steps.gates-read.outcome == 'success'` and no token; `Body, title and labels` without `GH_TOKEN`; header comment states the residual risk (design, "What a step boundary does not stop")
- [ ] 2.5 Cases: the toy task appends to `$GITHUB_OUTPUT`, `$GITHUB_ENV`, `$GITHUB_PATH`, `$GITHUB_STEP_SUMMARY` and `$GITHUB_STATE` when set, and the step files stay unchanged in `run`, `text` and G2; `run_repo_code` hides each variable, an `ACTIONS_*` one and `GIT_CONFIG_KEY_3`; `text` makes no gh call and passes with no token; the breaking check from prefetched files, from a failed prefetch, and no prefetch in `skip` mode; G2 from `gates-read.json` and a head that could not be fetched; the static check that no `compute` step from `Gates` on is given a token; existing gates and compute cases moved to the new steps; wiring suite green
- [ ] 2.6 Gates green, then commit `fix(cascade): keep repo code away from runner command files and tokens`

## 3. The canonical wiring check

- [ ] 3.1 Add `.github/scripts/cascade/wiring-check.sh` and its config format (D4)
- [ ] 3.2 Add `wiring/test/cases/wiringcheck.sh` (run by the wiring suite): a fixture repo built from the README caller shapes plus a `release.yml`, `cascade-task.yml` and CI workflow passes for a receiver and for core; one mutation per check refuses (keys, names, timeouts, needs as string and list, `if:`, `tag`, env allow-list and a non-map env, `runs-on`, permissions, triggers, concurrency, extra `with` keys, gates-only `if:` and input, `labels-managed: "false"`, every variant spelling of the key and the Environment, `secrets: inherit`, two SHAs, a missing pin comment, a CI path filter, a CI `if:` and `continue-on-error`); config errors exit 2 (unknown key, `BASH_ENV` and `GITHUB_TOKEN` in `env-allow`, `publish` on core, a string `receiver`)
- [ ] 3.3 README: "The wiring check" lists what the script checks, the config with each repo's values, and how a repo syncs and compares its copy (D5); the pin-bump steps name the copy
- [ ] 3.4 Gates green, then commit `feat(cascade): add the canonical wiring check`

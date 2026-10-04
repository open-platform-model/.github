Gates for every section (the repo's Validation Gates): `shellcheck` (pinned v0.11.0) on every
`*.sh` under `.github/scripts/` and on every test shim; `actionlint` (pinned v1.7.12) on
`.github/workflows/*.yml`; `bash .github/scripts/cascade/test/run.sh` and
`bash .github/scripts/cascade/wiring/test/run.sh`; `openspec validate --all --strict`. All run
offline. Design references are to this change's `design.md` (D1 to D5). The planning artifacts
are committed first as `docs(openspec): plan harden-cascade-publish`.

## 1. Gates-only runs never publish

- [x] 1.1 `cascade-publish/action.yml`: add the required input `gates-only` (description names the caller expression) and pass it to `Verify the plan` and `Act` as `CASCADE_PUBLISH_GATES_ONLY` (D1 point 2)
- [x] 1.2 `receive-publish.sh`: a `gates_only_switch` checked first in `verify` and `act`, before the dry-run input, the plan and any API call; `true` refuses with "a gates-only run never publishes", any value but `false` refuses; header documents the variable
- [x] 1.3 `cascade-receive.yml`: `compute` outputs `action` and `ok` computed from `inputs.gates-only` (D1 point 3); the header comment says so; `receive-compute.sh init` records a gates-only run as a dry run
- [x] 1.4 README receiver caller shape: `inputs.gates_only != true` in the `publish` `if:` and `gates-only: ${{ inputs.gates_only == true }}` on the `Publish` step; the stop-switch paragraph and the variables table say `false` in any letter case
- [x] 1.5 Cases: a complete plan from a real compute run with `CASCADE_PUBLISH_GATES_ONLY=true` (verify and act refuse, no gh call, nothing pushed, no `publish=true`); the input empty, unset, `False`, `TRUE`; a gates-only compute run whose release head forges `action=push`/`ok=true` (outputs stay `action=gates-only`, `dry_run=true`); static checks of the action input, the two output expressions and the README caller; wiring suite green
- [x] 1.6 Gates green, then commit `fix(cascade): refuse to publish from a gates-only run`

## 2. Repo code is cut off from the command files and tokens

- [x] 2.1 `lib.sh` `run_repo_code`: also unset `GITHUB_ENV`, `GITHUB_PATH`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY`, `GITHUB_STATE`, every exported `ACTIONS_*` and every `GIT_CONFIG_KEY_<n>`/`GIT_CONFIG_VALUE_<n>` (D3); add the `changelog_repos` map
- [x] 2.2 `gates-eval.sh read|run` (D2): `read` lists, evaluates G3, fetches the heads and writes `gates-read.json`; `run` runs G2 from it with no token and writes `gates.json`
- [x] 2.3 `receive-compute.sh`: new step `gates-read`; `gates` runs `gates-eval.sh run`; `state` also fetches the upstream releases into `$CASCADE_T/releases/`; `breaking_check` reads those files only; `text` no longer masks or needs a token
- [x] 2.4 `cascade-receive.yml`: the `Read gates` and `Read state` steps before `Gates`; `Gates` with `!cancelled() && steps.gates-read.outcome == 'success'` and no token; `Body, title and labels` without `GH_TOKEN`; header comment states the residual risk (design, "What a step boundary does not stop")
- [x] 2.5 Cases: the toy task appends to `$GITHUB_OUTPUT`, `$GITHUB_ENV`, `$GITHUB_PATH`, `$GITHUB_STEP_SUMMARY` and `$GITHUB_STATE` when set, and the step files stay unchanged in `run`, `text` and G2; `run_repo_code` hides each variable, an `ACTIONS_*` one and `GIT_CONFIG_KEY_3`; `text` makes no gh call and passes with no token; the breaking check from prefetched files, from a failed prefetch, and no prefetch in `skip` mode; G2 from `gates-read.json` and a head that could not be fetched; the static check that no `compute` step from `Gates` on is given a token; existing gates and compute cases moved to the new steps; wiring suite green
- [x] 2.6 Gates green, then commit `fix(cascade): keep repo code away from runner command files and tokens`

## 3. The canonical wiring check

- [x] 3.1 Add `.github/scripts/cascade/wiring-check.sh` and its config format (D4)
- [x] 3.2 Add `wiring/test/cases/wiringcheck.sh` (run by the wiring suite): a fixture repo built from the README caller shapes plus a `release.yml`, `cascade-task.yml` and CI workflow passes for a receiver and for core; one mutation per check refuses (keys, names, timeouts, needs as string and list, `if:`, `tag`, env allow-list and a non-map env, `runs-on`, permissions, triggers, concurrency, extra `with` keys, gates-only `if:` and input, `labels-managed: "false"`, every variant spelling of the key and the Environment, `secrets: inherit`, two SHAs, a missing pin comment, a CI path filter, a CI `if:` and `continue-on-error`); config errors exit 2 (unknown key, `BASH_ENV` and `GITHUB_TOKEN` in `env-allow`, `publish` on core, a string `receiver`)
- [x] 3.3 README: "The wiring check" lists what the script checks, the config with each repo's values, and how a repo syncs and compares its copy (D5); the pin-bump steps name the copy
- [x] 3.4 Gates green, then commit `feat(cascade): add the canonical wiring check`

## 4. Review fixes: G3, publish caches, wiring-check bypasses

- [x] 4.1 `lib.sh` `g3_eval` (moved from `gates-eval.sh`); `gates-eval.sh read|run` no longer evaluate or carry G3; `gates-post.sh` lists the heads, evaluates G3 once and posts it on every head, takes only `freshness` from `gates.json`, and handles a missing artifact or entry per G2 mode (D6); `receive-compute.sh` summary lists G2 only
- [x] 4.2 `cascade-receive.yml`: `cache: false` on `Set up Go` (D7); the header names the checkout post steps, the artifact runtime token and the Actions cache (design, "What a step boundary does not stop")
- [x] 4.3 Cases: G3 problem, fork and API error cases in `gates-post.sh`; a forged `settled` in `gates.json` ignored; the mapping per head; a missing artifact posts G3 and G2 per mode; a live head without an entry; static cases for compute's `cache: false`, no cache action or `type=gha` in any cascade workflow or action, and G3 only in `gates-post.sh`
- [x] 4.4 Gates green, then commit `fix(cascade): evaluate G3 in the job that runs no repo code`
- [x] 4.5 `wiring-check.sh`: refuse YAML anchors and aliases; a key reader is any expression using the secrets context other than `secrets.<name>`; `.github` references and calls matched without case; `env-allow` only `CUE_*`, `OPM_*`, `REGISTRY`, `IMAGE_NAME`; the `publish-workflows` key and its cache rule (D7); the CI step `bash .tasks/cascade/wiring-check.sh --pin-on-main` with `GH_TOKEN`, exact keys and no `defaults.run`; `--pin-on-main` (D8)
- [x] 4.6 Cases: the review's alias plus `format()` repro, a merge key, `secrets.*`, `join(secrets)`, an index in an `if:`, a named secret and plain text passing; mixed-case calls and references; every review env name and `CURL_CA_BUNDLE`, `LD_PRELOAD`, `BASH_ENV`, `CASCADE_X` refused, the registry names allowed; each cache form refused and the cache-off shapes passing; config errors for `publish-workflows`; the CI step variants; `--pin-on-main` with identical, ahead, behind, diverged, an API error, a shape mismatch (no call) and usage
- [x] 4.7 Gates green, then commit `fix(cascade): close the wiring check's bypasses and check publish caches`
- [x] 4.8 README, design (D6 to D8, refreshed repo SHAs and results), proposal and spec deltas (`cascade-gates`, `cascade-workflows`, `cascade-wiring-check`); the workspace RELEASING.md edit is handed to the supervisor as a patch (it lives in another repo)

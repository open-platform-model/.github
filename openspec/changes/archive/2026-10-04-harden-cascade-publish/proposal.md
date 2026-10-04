## Why

The review of the five `join-release-cascade` changes found three gaps in the cascade wiring
merged by `add-release-cascade-workflows` (PR 9, `2376ffa`). They must close before any receiver
sets `CASCADE_DRY_RUN` to `false` (workspace RELEASING.md, sections "Two-job split" and "Stop
switches"; the owner's "go" of 2026-10-04 to "the two `.github` fixes" before Phase 4):

1. **A gates-only run can unlock publish.** On a gates-only run, `compute`'s `action` output
   comes from the `Gates` step, which runs the code of every open `release-please--*` head. That
   code can write `GITHUB_OUTPUT`, so it can forge `action=push`; the caller's `publish` job
   reads no gates-only switch of its own, and once `CASCADE_DRY_RUN=false` only the missing
   `cascade-plan` artifact stops `publish`. Any write collaborator can push a `release-please--*`
   branch, since no ruleset covers it.
2. **Repo code can reach the runner's command files.** `run_repo_code` (`wiring/lib.sh`) unsets
   the tokens but not `GITHUB_ENV`, `GITHUB_PATH`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY` or
   `GITHUB_STATE`, and two steps that hold `GITHUB_TOKEN` (`Gates`, `Body, title and labels`)
   run repo code themselves, while `PR state` holds it after the release heads' code ran.
3. **Five wiring checks drifted.** Each product repo's `.tasks/cascade/wiring-check.sh` started
   from the same contract text, but library now matches the variant spellings of the key and the
   Environment, catalog_opm and opm-operator compare the notify and publish values, and core,
   catalog_opm and cli still miss `secrets['…']`, `toJSON(secrets)` and a lower-case `cascade`.
   A check that differs per repo cannot be reviewed once.

The review of this change's first version found more, fixed here too: G3 travelled through
files release-head code can rewrite; repo code in `compute` can write the Actions cache that
cli's and opm-operator's release jobs restore (a poisoned module cache or image layer would ship
unreviewed); the new wiring check could be bypassed with a YAML alias plus
`secrets[format(…)]` or a mixed-case `.github` reference, its `env-allow` deny-list missed
proxy, TLS, git-hook and XDG variables, and it accepted a pin to a commit that exists only in a
fork of `.github`.

## What Changes

- **Gates-only runs never publish.** The caller's `publish` `if:` adds
  `inputs.gates_only != true`, and the caller passes `cascade-publish` a new required input
  `gates-only: ${{ inputs.gates_only == true }}`. `receive-publish.sh` refuses, before any token
  exists, a run whose `gates-only` input is not exactly `false` (verify and act). In
  `cascade-receive.yml`, a gates-only run's `action` output is the literal `gates-only` and its
  `compute-ok` is `false`, both computed from the input, and `compute` treats it as a dry run.
  Offline cases forge `compute`'s outputs and a valid plan on a gates-only run and show that
  publish refuses.
- **Repo code is cut off from the runner's command files, and no step after it holds a token.**
  `run_repo_code` also unsets `GITHUB_ENV`, `GITHUB_PATH`, `GITHUB_OUTPUT`,
  `GITHUB_STEP_SUMMARY`, `GITHUB_STATE`, every `ACTIONS_*` variable and every
  `GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n`. `compute` does every read that needs `GITHUB_TOKEN`
  (the release-PR list, G3, the release heads' fetch, the cascade PR, the branch tips and the
  upstream releases for the breaking check) in two `Read` steps before the first step that runs
  repo code; the steps that run repo code and every step after them get no token. The design
  states what this does not stop: in one job, repo code can still find the command files on
  disk, leave a process running, rewrite the scripts and, with the runner's `sudo`, read the
  job's read-only token. So every `compute` output after the first repo-code step stays a hint,
  and every decision that matters is read from the caller's inputs and variables or re-derived
  by `publish`.
- **One canonical wiring check.** `.github/scripts/cascade/wiring-check.sh` is the union of the
  five scripts (library's case-insensitive key and Environment scans, catalog_opm's and
  opm-operator's job values, the env allow-list and `runs-on` rules) plus the reviewers' open
  probes (caller permissions, triggers, the CI job that runs it), driven by a per-repo
  `.tasks/cascade/wiring-check.yaml` (`pin-comment`, `receiver`, `env-allow`,
  `publish-workflows`, `ci`, `notify`, `publish`). It refuses YAML anchors and aliases, any use
  of the secrets context but `secrets.<name>` outside the key-holding steps, `.github`
  references in any case, `env-allow` names other than `CUE_*`, `OPM_*`, `REGISTRY` and
  `IMAGE_NAME`, and any Actions cache in the listed publish workflows. The required CI step
  runs it with `--pin-on-main`, which proves the pinned SHA is on `.github` `main` through the
  compare API. Each product repo keeps a byte-identical copy at `.tasks/cascade/wiring-check.sh`.
  An offline mutation suite runs it against the README's caller shapes.
- **G3 in `Post gates`.** `gates-post.sh` evaluates G3 from the API itself and takes only G2
  from `compute`'s `gates.json`.
- **No cache in reach of repo code.** `compute` installs Go with `cache: false`; the residual
  risk text names the Actions cache, the checkout post steps and the artifact runtime token.
- **README**: the receiver caller shape, the `cascade-publish` inputs, the stop switch wording
  ("`false` in any letter case", because GitHub compares strings without case), the
  wiring-check section and how a repo syncs its copy.

Not in this change: the per-repo caller edits and the copies of the script (each repo's pin bump
PR), a ruleset on `release-please--*` (owner), moving G2 into its own job, and making the G2
statuses trustworthy against a malicious release head (G2 runs that head's own task by design).

## Capabilities

### New Capabilities

- `cascade-wiring-check`: the canonical wiring-check script, its per-repo config and how a
  product repo keeps its copy.

### Modified Capabilities

- `cascade-receive`: `cascade-publish` takes `gates-only`; a gates-only run never publishes;
  the stop switch is `false` in any letter case.
- `cascade-workflows`: repo code runs without the runner's command-file variables, no
  `compute` step after the first repo-code step is given a token, and no cache repo code can
  write reaches a publish job.
- `cascade-gates`: G3 is evaluated in `Post gates`, never read from `compute`; a missing
  artifact still gets G3.

## Impact

- Workflows and scripts: `.github/workflows/cascade-receive.yml`,
  `.github/actions/cascade-publish/action.yml`, `wiring/lib.sh`, `wiring/receive-compute.sh`,
  `wiring/receive-publish.sh`, `wiring/gates-eval.sh`, `wiring/gates-post.sh`, the new
  `.github/scripts/cascade/wiring-check.sh`, the wiring suite and `README.md`.
- Callers: catalog_opm, library, opm-operator and cli (`deps-cascade.yml`: the `publish` `if:`
  and the new `gates-only` input) and all five product repos (the script copy and config, the
  CI step with `--pin-on-main`, and `cache: false` or no `type=gha` in their publish workflows)
  apply the edits in the PR that moves their pin to this change's squash SHA. `cascade-publish` without
  `gates-only` fails closed, so a repo that bumps the pin without the edit cannot publish.
- Rollout: the diff touches `cascade-publish`, so the canary rule applies (README "Pinning and
  bumps", step 2): the other receivers stay on `2376ffa` until the canary's first live publish
  has succeeded.
- Depends on: `add-release-cascade-workflows` (merged). Later: every receiver's
  `CASCADE_DRY_RUN=false` and the Phase 4 pin bumps.

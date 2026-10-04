## MODIFIED Requirements

### Requirement: Receive interface and job split

`.github/workflows/cascade-receive.yml` SHALL take the inputs `dry-run` (boolean, required),
`gates-only` (boolean, default false), `g2-mode` and `g3-mode` (string, default `warn`; any value
other than `warn` or `enforce` fails `compute`), `setup-go` (boolean, default false; Go from
`repo/go.mod`), `setup-cue` (boolean, default true) and `cue-version` (string, default
`v0.17.1`), SHALL run two jobs, and SHALL output `action`,
`dry-run` and `compute-ok` (true only when every `compute` step succeeded and the run is not
gates-only). The third job,
`publish`, is the caller's own: it needs the reusable job, declares `environment: cascade`, and
runs the composite action `.github/actions/cascade-publish` with the inputs `dry-run`
(required), `gates-only` (required), `labels-managed` (default `false`), `client-id` and
`private-key`:

| Job | Where | Environment | Permissions | Timeout |
| --- | --- | --- | --- | --- |
| `compute` | `cascade-receive.yml` | none | `contents: read`, `pull-requests: read` | 45 min |
| `gates` | `cascade-receive.yml` | none | `contents: read`, `statuses: write`, `pull-requests: read` | 10 min |
| `publish` | the caller, running `cascade-publish` | `cascade` | `contents: read`, `pull-requests: read` | 15 min |

`compute` runs the repo's task and holds no secret. `publish` runs only `git`, `gh`, `jq` and the
`.github` scripts of the pinned action, never a repo task or repo code, and fails on any ref other than
`refs/heads/main`. Task (3.x) is always installed, and
`compute` SHALL fail unless `yq --version` reports mikefarah. The bot SHALL never enable
auto-merge on a cascade PR (every cascade PR is merged by a human).

#### Scenario: Bad gate mode

- **WHEN** a caller passes `g2-mode: strict`
- **THEN** `compute` fails and `publish` does not run

### Requirement: Dry run fails closed

`publish` SHALL run only when `compute-ok` is `true`, the `dry-run` output is `false`, the
`action` output is one of `push`, `recreate`, `close`, `conflict` or `too_long`, and, read by
the caller's `publish` job itself rather than from `compute`, the `dry_run` dispatch input is not
true, the `gates_only` dispatch input is not true, the repo variable `CASCADE_DRY_RUN` is `false`
and the run's ref is `refs/heads/main`. GitHub compares strings without regard to case, so
`CASCADE_DRY_RUN` set to `false` in any letter case (`False`, `FALSE`) makes the receiver live,
and every other value, unset included, keeps it dry. The caller SHALL pass `cascade-publish` the
input `dry-run` as
`${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}`, and the action itself SHALL
publish only when that input is exactly `false`: `true` SHALL publish nothing, mint no token and
succeed; any other value, empty or missing included, SHALL fail before the mint. So the stop
switch holds even when a caller's `if:` is wrong. `publish` SHALL also refuse, before minting, a
plan whose `effective_dry_run` is true. `compute` SHALL
treat a run from any ref other than `refs/heads/main`, and a gates-only run, as a dry run
whatever the input says. In a
dry run `compute` SHALL still write the job summary with the line "DRY RUN: nothing was pushed",
the mode, action, tips, title, labels, gate results, the body and the diff (capped at 200 KB in
the summary, in full as `diff.patch` in the `cascade-plan` artifact). Notify ignores dry run.

#### Scenario: Dry run pushes nothing

- **WHEN** the caller passes `dry-run: true` and the task moves a pin
- **THEN** the summary shows the diff and "DRY RUN: nothing was pushed", and no branch, PR, label or comment changes

#### Scenario: Forged dry-run output

- **WHEN** the caller passes `dry-run: true` and repo code in `compute` makes its `dry_run` output read `false`
- **THEN** `publish` is still skipped

#### Scenario: Caller if: lets a dry run through

- **WHEN** `CASCADE_DRY_RUN` is `true` and a caller's `publish` job runs anyway because its `if:` omits the switch
- **THEN** `cascade-publish` writes a notice, mints no token and pushes nothing

#### Scenario: Dry-run input not a boolean

- **WHEN** `cascade-publish` gets `dry-run` empty or `False`
- **THEN** it fails before the mint and pushes nothing

#### Scenario: Branch run is a dry run

- **WHEN** the caller is dispatched from a branch with `dry_run: false`
- **THEN** `compute` sets `dry_run` to true and `publish` is skipped

#### Scenario: Stop switch in another letter case

- **WHEN** a receiver sets `CASCADE_DRY_RUN` to `FALSE`
- **THEN** the caller's expressions treat it as `false`, the `dry-run` input is `false`, and the receiver publishes as with `false`

## ADDED Requirements

### Requirement: Gates-only runs never publish

A gates-only receiver run SHALL never mint the App token or write to the repo. The caller's
`publish` job SHALL read its own `gates_only` dispatch input in its `if:`
(`inputs.gates_only != true`) and SHALL pass `cascade-publish` the required input `gates-only`
as `${{ inputs.gates_only == true }}`. `cascade-publish` SHALL check that input before the
dry-run input, the plan or any API call, in both `verify` and `act`: exactly `false` continues;
`true` SHALL fail with "a gates-only run never publishes"; any other value, empty or missing
included, SHALL fail. Neither check SHALL read an output of the reusable job. For a gates-only
run, `cascade-receive.yml` SHALL output `action` `gates-only` and `compute-ok` `false`, computed
from its `gates-only` input rather than from a step that ran repo code.

#### Scenario: Forged outputs on a gates-only run

- **WHEN** release-head code in a gates-only run makes `compute` report `action=push`, `compute-ok=true` and `dry-run=false`, uploads a plan that would verify, and `CASCADE_DRY_RUN` is `false`
- **THEN** the caller's `publish` job is skipped by its own `inputs.gates_only` check, and `cascade-publish`, if it ran anyway, refuses before the mint and pushes nothing

#### Scenario: Missing gates-only input

- **WHEN** a caller bumps its pin and runs `cascade-publish` without the `gates-only` input
- **THEN** `verify` fails before reading the plan and no token is minted

#### Scenario: Gates-only outputs come from the input

- **WHEN** `cascade-receive.yml` is read
- **THEN** `compute`'s `action` output is `gates-only` and its `ok` output is `false` whenever the `gates-only` input is true, whatever any step wrote

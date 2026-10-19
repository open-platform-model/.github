# cascade-receive Specification

## Purpose
The reusable receive workflow and the composite publish action each downstream repo runs from its `deps-cascade.yml`: they run the
repo's `task -x deps:cascade`, keeps one rolling `deps/cascade` PR up to date without ever
needing the Workflows permission, and never lets the job that runs repo code hold the App key.

## Requirements

### Requirement: Receive interface and job split

`.github/workflows/cascade-receive.yml` SHALL take the inputs `dry-run` (boolean, required), `gates-only` (boolean, default false), `g2-mode` and `g3-mode` (string, default `warn`; any value other than `warn` or `enforce` fails `compute`) and the setup inputs of the requirement "Receive setup inputs", SHALL run two jobs, and SHALL output `action`, `dry-run` and `compute-ok` (true only when every `compute` step succeeded and the run is not gates-only).

#### Scenario: Bad gate mode

- **WHEN** a caller passes `g2-mode: strict`
- **THEN** `compute` fails and `publish` does not run

### Requirement: The cascade PR is the bot's own same-repo PR

The cascade PR SHALL be the open PR on head `deps/cascade` and base `main` that is not from a
fork, whose head repository owner is `open-platform-model` and whose author is
`app/opm-cascade`. More than one such PR SHALL fail the job. A fork PR or a human-authored PR on a
branch named `deps/cascade` SHALL never be read, edited or closed.

#### Scenario: Fork PR on deps/cascade

- **WHEN** a fork opens a PR from its own `deps/cascade` branch
- **THEN** the receiver ignores it and reads neither its title nor its body

### Requirement: Mode selection

`compute` SHALL pick the mode from the remote `deps/cascade` tip (`OLD`) and the cascade PR, as the scenario "Mode table" says. `fresh`, `rebuild` and `recreate` SHALL start from `origin/main`. The bot SHALL never rebase and never drop a human commit.

#### Scenario: Human commit survives

- **WHEN** a human pushed a commit to `deps/cascade` and a new upstream release arrives
- **THEN** the human commit is an ancestor of the new tip and the bot's commit is on top

#### Scenario: Bot-only branch is rebuilt

- **WHEN** the branch holds only bot commits and a new upstream release arrives
- **THEN** the branch is rebuilt from `origin/main` to one bot commit and the PR number is unchanged

#### Scenario: Mode table

- **WHEN** `compute` reads the remote `deps/cascade` tip (`OLD`) and the cascade PR
- **THEN** it picks the mode of the row that matches:

| State | Mode |
| --- | --- |
| the cascade PR carries `deps-cascade:hold` | `skip` |
| no `OLD` | `fresh` |
| `OLD` set and no open cascade PR | `recreate` |
| open cascade PR, every commit in `origin/main..origin/deps/cascade` has author and committer email `337635439+opm-cascade[bot]@users.noreply.github.com` | `rebuild` |
| open cascade PR, any other author or committer in that range | `merge` |

### Requirement: Final title

The final title SHALL be the computed title unless the PR is retitled: an open cascade PR whose body has a `<!-- cascade-title: <T> -->` line above the Notes marker with a non-empty `<T>` that differs from the PR's current title. A retitled PR SHALL keep its current title unchanged, `!` included, for good. The bot SHALL never add `!`.

#### Scenario: Human retitle kept

- **WHEN** a human retitled the PR to `feat(deps): sandbox` and the computed title is `fix(deps): bump up to v0.5.0`
- **THEN** the title stays `feat(deps): sandbox`, the body marker carries the computed title, and no title-rise comment is posted

#### Scenario: Marker pasted into the Notes

- **WHEN** the only `cascade-title` marker in the body sits below the Notes marker
- **THEN** the PR counts as not retitled

### Requirement: Action table

`compute` SHALL pick exactly one action: `skip` for mode `skip`; `conflict` for mode `conflict`;
`too_long` when the body exceeds 65000 bytes (Notes are never truncated); `close` when the final
tree equals `origin/main` and a cascade PR is open or `OLD` is set; `noop` when the tree equals
`origin/main` with no PR and no `OLD`; otherwise `push`, which also covers a title, body or label
change when the tip is unchanged.

#### Scenario: Upstream already merged by hand

- **WHEN** `main` caught up with every pin the open cascade PR moved
- **THEN** the action is `close`, and `publish` comments, closes the PR and deletes the branch under a lease

### Requirement: Conflict and too-long states are visible

For `conflict`, `publish` SHALL add `deps-cascade:conflict` and `deps-cascade`, post the conflict
comment only when the label was not already present, push nothing and succeed. For `too_long`, it
SHALL post the too-long comment only when its newest comment is not already that comment, push
and edit nothing, and fail, so the run stays red until a human trims the Notes.

#### Scenario: No comment spam

- **WHEN** two runs in a row end in `conflict`
- **THEN** the conflict comment is posted once

### Requirement: Publish renders the PR text

For `push` and `recreate`, `publish` SHALL check the new tip out into a scratch worktree outside the repo checkout and run the resolver's `title` and `body` there with the `.github` mirror of the receiver's `classes` and `pins.sh` (`wiring/pins.sh`, which reads only `git show`), the payload from the event, the live PR's Notes and `compute`'s filtered warnings. The body SHALL be the one rendered there, never `compute`'s `body.md`.

#### Scenario: Text planted above the Notes marker

- **WHEN** `compute`'s `body.md` starts with a link and a misleading summary above the Notes marker
- **THEN** the PR body `publish` writes holds the resolver's sections from `.github` code and none of that text

#### Scenario: Notes come from the live PR

- **WHEN** `compute`'s `body.md` carries other text below the Notes marker than the live PR
- **THEN** `publish` keeps the live PR's Notes

### Requirement: Receive setup inputs

`.github/workflows/cascade-receive.yml` SHALL take the inputs `setup-go` (boolean, default false; Go from `repo/go.mod`), `setup-cue` (boolean, default true) and `cue-version` (string, default `v0.17.1`).

#### Scenario: Setup defaults

- **WHEN** a caller passes none of `setup-go`, `setup-cue` and `cue-version`
- **THEN** Go is not set up, CUE is set up, and the CUE version is `v0.17.1`

### Requirement: Receive jobs have fixed environment, permissions and timeouts

The jobs `compute`, `gates` and `publish` SHALL have the environment, permissions and timeout of the table in the scenario "Job limits". `compute` SHALL run the repo's task and hold no secret. `publish` SHALL run only `git`, `gh`, `jq` and the `.github` scripts of the pinned action, never a repo task or repo code, and SHALL fail on any ref other than `refs/heads/main`.

#### Scenario: Job limits

- **WHEN** the jobs of the receive workflow and of the caller are read
- **THEN** each job has the environment, permissions and timeout of this table:

| Job | Where | Environment | Permissions | Timeout |
| --- | --- | --- | --- | --- |
| `compute` | `cascade-receive.yml` | none | `contents: read`, `pull-requests: read` | 45 min |
| `gates` | `cascade-receive.yml` | none | `contents: read`, `statuses: write`, `pull-requests: read` | 10 min |
| `publish` | the caller, running `cascade-publish` | `cascade` | `contents: read`, `pull-requests: read` | 15 min |

### Requirement: The publish job is the caller's own

The third job, `publish`, is the caller's own: it SHALL need the reusable job, declare `environment: cascade`, and run the composite action `.github/actions/cascade-publish` with the inputs `dry-run` (required), `gates-only` (required), `labels-managed` (default `false`), `client-id` and `private-key`.

#### Scenario: The caller's publish job

- **WHEN** a caller's `deps-cascade.yml` is read
- **THEN** its `publish` job needs the reusable job, declares `environment: cascade` and runs `.github/actions/cascade-publish` with the inputs `dry-run`, `gates-only`, `labels-managed`, `client-id` and `private-key`

### Requirement: Compute checks its tools

Task (3.x) is always installed, and `compute` SHALL fail unless `yq --version` reports mikefarah.

#### Scenario: yq is not mikefarah

- **WHEN** `yq --version` does not report mikefarah
- **THEN** `compute` fails

### Requirement: The bot never enables auto-merge

The bot SHALL never enable auto-merge on a cascade PR (every cascade PR is merged by a human).

#### Scenario: A pushed cascade PR

- **WHEN** `publish` opens or updates a cascade PR
- **THEN** auto-merge stays off and a human merges the PR

### Requirement: Publish runs only when every live condition holds

`publish` SHALL run only when `compute-ok` is `true`, the `dry-run` output is `false`, the `action` output is one of `push`, `recreate`, `close`, `conflict` or `too_long`, and, read by the caller's `publish` job itself rather than from `compute`, the `dry_run` dispatch input is not true, the `gates_only` dispatch input is not true, the repo variable `CASCADE_DRY_RUN` is `false` and the run's ref is `refs/heads/main`.

#### Scenario: Forged dry-run output

- **WHEN** the caller passes `dry-run: true` and repo code in `compute` makes its `dry_run` output read `false`
- **THEN** `publish` is still skipped

### Requirement: The stop switch variable is case-insensitive

GitHub compares strings without regard to case, so `CASCADE_DRY_RUN` set to `false` in any letter case (`False`, `FALSE`) SHALL make the receiver live, and every other value, unset included, SHALL keep it dry.

#### Scenario: Stop switch in another letter case

- **WHEN** a receiver sets `CASCADE_DRY_RUN` to `FALSE`
- **THEN** the caller's expressions treat it as `false`, the `dry-run` input is `false`, and the receiver publishes as with `false`

### Requirement: The publish action publishes only on a false dry-run input

The caller SHALL pass `cascade-publish` the input `dry-run` as `${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}`, and the action itself SHALL publish only when that input is exactly `false`: `true` SHALL publish nothing, mint no token and succeed; any other value, empty or missing included, SHALL fail before the mint. So the stop switch holds even when a caller's `if:` is wrong. `publish` SHALL also refuse, before minting, a plan whose `effective_dry_run` is true.

#### Scenario: Caller if: lets a dry run through

- **WHEN** `CASCADE_DRY_RUN` is `true` and a caller's `publish` job runs anyway because its `if:` omits the switch
- **THEN** `cascade-publish` writes a notice, mints no token and pushes nothing

#### Scenario: Dry-run input not a boolean

- **WHEN** `cascade-publish` gets `dry-run` empty or `False`
- **THEN** it fails before the mint and pushes nothing

### Requirement: Compute treats other refs and gates-only runs as dry runs

`compute` SHALL treat a run from any ref other than `refs/heads/main`, and a gates-only run, as a dry run whatever the input says.

#### Scenario: Branch run is a dry run

- **WHEN** the caller is dispatched from a branch with `dry_run: false`
- **THEN** `compute` sets `dry_run` to true and `publish` is skipped

### Requirement: A dry run still writes the summary

In a dry run `compute` SHALL still write the job summary with the line "DRY RUN: nothing was pushed", the mode, action, tips, title, labels, gate results, the body and the diff (capped at 200 KB in the summary, in full as `diff.patch` in the `cascade-plan` artifact). Notify ignores dry run.

#### Scenario: Dry run pushes nothing

- **WHEN** the caller passes `dry-run: true` and the task moves a pin
- **THEN** the summary shows the diff and "DRY RUN: nothing was pushed", and no branch, PR, label or comment changes

### Requirement: Payload is a validated whole

On a `repository_dispatch` run `compute` SHALL accept the payload only when `source` is a string in the receiver's allowlist and `tags` is an array of 1 to 8 strings each matching the tag shape for that source; unknown keys SHALL be ignored. An invalid payload SHALL be dropped whole with a warning and a summary line naming why, and the run SHALL continue as a sweep. The payload SHALL never set a label.

#### Scenario: Hostile payload

- **WHEN** the payload is `{"source":"evil","tags":["@x"]}`
- **THEN** the payload is dropped with a warning, the run behaves as a sweep, and no mention appears in any text the bot writes

#### Scenario: Nine tags

- **WHEN** the payload carries nine valid tags
- **THEN** the whole payload is dropped and the run continues as a sweep

### Requirement: Payload strings are matched whole

A `source` or tag holding a control character (U+0000 to U+001F or U+007F) SHALL make the payload invalid, and each tag SHALL be matched whole, so a tag with a trailing newline is refused.

#### Scenario: Tag with a trailing newline

- **WHEN** the payload for cli is `{"source":"library","tags":["v1.0.0\n","v1.0.1"]}`
- **THEN** the whole payload is dropped and the run continues as a sweep

### Requirement: The payload source allowlists

The allowlists SHALL be: `catalog_opm` accepts `core`, `cli`; `library` accepts `core`, `catalog_opm`; `opm-operator` and `opm-controller` (its name after the rename) accept `catalog_opm`, `library`, `cli`; `cli` accepts `catalog_opm`, `library`, `opm-operator`, `opm-controller`; `cascade-sandbox-down` accepts `cascade-sandbox-up`. A receiver outside this list SHALL fail with "not a cascade receiver".

#### Scenario: Receiver outside the list

- **WHEN** a receiver that is not in the allowlists runs `compute`
- **THEN** it fails with "not a cascade receiver"

### Requirement: A valid payload sets the cascade variables

A valid payload SHALL set `CASCADE_SOURCE`, `CASCADE_TAGS` and one `CASCADE_EXPECT` pair built from the last tag (`catalog_opm` tags lose their `opm-` prefix). Only `cascade-sandbox-down` SHALL export `CASCADE_EXTRA_SOURCES=cascade-sandbox-up`.

#### Scenario: The renamed repo's release reaches cli

- **WHEN** cli receives `{"source":"opm-controller","tags":["v1.0.0-beta.9"]}`
- **THEN** the payload is valid and `CASCADE_EXPECT` is `github.com/open-platform-model/opm-controller=v1.0.0-beta.9`

### Requirement: Publish reads the payload from the event

`publish` SHALL read the payload from the event itself, with the same validation, never from `compute`.

#### Scenario: Payload in the plan differs from the event

- **WHEN** the plan from `compute` carries a payload that differs from the event's payload
- **THEN** `publish` validates and uses the event's payload

### Requirement: Merge mode merges main into the branch

`merge` SHALL check out `origin/deps/cascade` and run `git merge --no-edit origin/main`: when only derived files conflict (`go.mod`, `go.sum`, any `cue.mod/module.cue`, cli's `internal/operator/pin.go` or, after cli's rename, `internal/controller/pin.go`), it SHALL take `main`'s side, commit `Merge origin/main into deps/cascade` and let the task regenerate them; any other conflict SHALL abort the merge and give mode `conflict` with the conflicting paths.

#### Scenario: Only derived files conflict

- **WHEN** the merge of `origin/main` conflicts only in `go.mod` and `go.sum`
- **THEN** `compute` takes `main`'s side, commits `Merge origin/main into deps/cascade` and lets the task regenerate them

#### Scenario: Another file conflicts

- **WHEN** the merge of `origin/main` conflicts in a file that is not a derived file
- **THEN** `compute` aborts the merge and gives mode `conflict` with the conflicting paths

### Requirement: Compute runs the task and commits its result

`compute` SHALL refuse a dirty `repo/` tree, run `task -x deps:cascade` with `CASCADE_BASE=origin/main` (exit 3: no commit; any exit other than 0 or 3: job error), commit the result as `opm-cascade[bot]` with the computed title as the only line, and require the title computed before the commit to equal the title computed after it.

#### Scenario: Task exits 3

- **WHEN** `task -x deps:cascade` exits 3
- **THEN** `compute` makes no commit, and any exit other than 0 or 3 is a job error

### Requirement: Merge mode runs main's task

In mode `merge`, when the branch's `.tasks/` or root `Taskfile*` differ from `origin/main`'s, `compute` SHALL put `origin/main`'s versions in the work tree before the task runs, run the task with `CASCADE_ALLOW_DIRTY=1`, and leave those paths out of the commit, so the task, `pins.sh` and the body task are always `main`'s.

#### Scenario: A branch that edits the task

- **WHEN** a human commit on `deps/cascade` changes `.tasks/cascade/cascade.sh` and `main` moved since
- **THEN** `compute` runs `main`'s `cascade.sh`, and the bot's commit leaves `.tasks/` as the branch has it

### Requirement: Compute scratch files stay under the runner temp folder

All scratch files SHALL live under `$RUNNER_TEMP/cascade/`, never in `repo/` or `org-github/`.

#### Scenario: Scratch files

- **WHEN** `compute` writes a scratch file
- **THEN** the file is under `$RUNNER_TEMP/cascade/` and not in `repo/` or `org-github/`

### Requirement: Compute uploads the warnings file

`compute` SHALL upload the task's warnings file as `warnings.tsv` in the plan artifact.

#### Scenario: Warnings in the plan artifact

- **WHEN** `compute` finishes a run
- **THEN** the plan artifact holds the task's warnings file as `warnings.tsv`

### Requirement: Notes are kept byte for byte

With an open cascade PR the Notes SHALL be every byte after the first line equal to `<!-- cascade-notes: the bot keeps everything below this line -->` (one trailing `\r` removed for the comparison), or the whole old body when no such line exists, and SHALL be passed to the body task through `CASCADE_NOTES_FILE` unchanged.

#### Scenario: CRLF body is stable

- **WHEN** a human edited the PR body on the web so it has CRLF line ends, and two runs follow with no upstream change
- **THEN** the body after the second run is byte-identical to the body after the first

#### Scenario: Body rewritten by a human

- **WHEN** the open PR's body has no Notes marker line
- **THEN** the whole old body becomes the Notes of the new body

### Requirement: Title rise posts one comment

When the computed type ranks above both the current title's type and the marker's type (`ci` 1, `test` 2, `fix` 3, `feat` 4, other 0), `publish` SHALL post the title-rise comment once and SHALL NOT change the title.

#### Scenario: Computed type rises

- **WHEN** the computed type is `feat`, the current title's type is `fix` and the marker's type is `fix`
- **THEN** `publish` posts the title-rise comment once and does not change the title

### Requirement: Planned labels are a union

The planned labels SHALL be the union of `deps-cascade`, the `cascade-labels` marker of the new body, and `deps-cascade:breaking` when any non-draft release of a moved pin's upstream with a version `v` where `from < v <= to` has `BREAKING CHANGES` in its body.

#### Scenario: Breaking release in the middle of the range

- **WHEN** the pin moves from `v1.0.0` to `v1.3.0` and only `v1.2.0`'s release body contains `BREAKING CHANGES`
- **THEN** the planned labels include `deps-cascade:breaking`

### Requirement: The breaking check covers the whole range

The breaking check SHALL cover the whole range between the pin on `main` and the pin on the branch, never read the payload, ignore pins of third-party modules, and on an API error add no label and write a summary warning.

#### Scenario: API error in the breaking check

- **WHEN** the release read of the breaking check fails with an API error
- **THEN** `compute` adds no `deps-cascade:breaking` label and writes a summary warning

### Requirement: Publish derives the labels again

`publish` SHALL derive the labels again with `.github` code: the marker from the body it renders itself, and the breaking check from the `.github` mirror of the receiver's pins and the releases it reads itself; when its release read fails it SHALL keep the plan's `deps-cascade:breaking` and write a notice; every other planned label is ignored.

#### Scenario: A plan that drops the labels

- **WHEN** a library plan moves core but lists only `deps-cascade`, and an upstream release in the range is breaking
- **THEN** `publish` adds `need-human-review` and `deps-cascade:breaking` itself

### Requirement: The bot only adds labels

The bot SHALL only add labels, with one exception: it removes `deps-cascade:conflict` after a successful push; it SHALL never remove `need-human-review` or `deps-cascade:breaking`.

#### Scenario: A live label is never removed

- **WHEN** the open cascade PR carries `need-human-review` and the new plan derives no such label
- **THEN** `publish` removes nothing but, at most, `deps-cascade:conflict`

### Requirement: Publish keeps the five bot labels

Outside cli (`labels-managed: false`) `publish` SHALL create or update the five labels `deps-cascade`, `deps-cascade:conflict`, `deps-cascade:hold`, `deps-cascade:breaking` and `need-human-review` with the colours and descriptions of workspace RELEASING.md, section "Labels"; with `labels-managed: true` it SHALL fail with "declare it in .github/labels.yml" when any of them is missing.

#### Scenario: Labels outside cli

- **WHEN** `publish` runs in a receiver with `labels-managed: false`
- **THEN** it creates or updates the five labels with the colours and descriptions of workspace RELEASING.md, section "Labels"

#### Scenario: Managed labels missing

- **WHEN** `publish` runs with `labels-managed: true` and one of the five labels is missing
- **THEN** it fails with "declare it in .github/labels.yml"

### Requirement: The workflows guard limits what the bot pushes

The bot SHALL push only updates GitHub cannot read as a workflow change. With `D1 = git diff --name-only origin/main NEW -- .github/workflows/` and `D2 = git diff --name-only OLD NEW -- .github/workflows/` (in-place updates only), the push rule SHALL be that of the scenario "Guard table" for each mode and each rule value. The bot SHALL never call the update-branch API or a server-side merge.

#### Scenario: Main changed a workflow under a bot-only PR

- **WHEN** `WF_GUARD_RULE` is `strict`, the PR has only bot commits, and `main` changed `.github/workflows/touch.yml` since the branch was built
- **THEN** the action is `recreate`: the old PR is closed with a comment, the branch is deleted and pushed fresh, a new PR opens with the old Notes and its `deps-cascade:breaking` and `need-human-review` labels, and the old PR names the new one

#### Scenario: Main changed a workflow under a human commit

- **WHEN** `WF_GUARD_RULE` is `strict`, the PR has a human commit, and `main` changed a workflow file
- **THEN** the action is `conflict`: no push, the label `deps-cascade:conflict` is added and the workflows conflict comment is posted once

#### Scenario: Guard table

- **WHEN** the bot decides whether to push in a mode, under the rule constant `WF_GUARD_RULE`
- **THEN** the push is allowed or refused by this table:

| Mode | Push allowed (`strict`) | Push allowed (`tree`) | Otherwise |
| --- | --- | --- | --- |
| `fresh` | `D1` empty | `D1` empty | job error |
| `rebuild` | `D1` and `D2` empty | `D1` empty | `strict`: action `recreate` |
| `recreate` | `D1` empty | `D1` empty | job error |
| `merge` | `D1` and `D2` empty | `D1` empty | action `conflict`, reason `workflows` |

### Requirement: The workflows guard rule ships as tree

The rule constant `WF_GUARD_RULE` SHALL ship as `tree` (sandbox cycle E4c: GitHub accepted, from the App without the Workflows permission, both an in-place lease update across a workflow change on `main` and a pushed merge commit bringing that change in); `strict` SHALL stay implemented for the case GitHub tightens the rule.

#### Scenario: Main changed a workflow under a bot-only PR, shipped rule

- **WHEN** `WF_GUARD_RULE` is `tree`, the PR has only bot commits, and `main` changed `.github/workflows/touch.yml` since the branch was built
- **THEN** the action is `push`: the same PR is rebuilt in place under the lease, Notes and labels unchanged

#### Scenario: Main changed a workflow under a human commit, shipped rule

- **WHEN** `WF_GUARD_RULE` is `tree`, the PR has a human commit, and `main` changed a workflow file
- **THEN** the action is `push`: `main` is merged into the branch, the human commit stays an ancestor, and the merge commit is pushed

### Requirement: Publish treats the plan as untrusted

`publish` SHALL treat the uploaded plan as untrusted and, with `GITHUB_TOKEN` and plain git only, before the token exists: refuse an unknown action or a label outside the five bot-relevant labels; re-derive the cascade PR and refuse a PR-number mismatch; stop with "deps/cascade moved since compute; the next run retries" when the remote tip differs from the planned old tip.

#### Scenario: Human push between compute and publish

- **WHEN** a human pushes to `deps/cascade` after `compute` read the tip
- **THEN** `publish` fails before minting the token and the next run retries

#### Scenario: Forged plan

- **WHEN** the plan names a PR number that is not the bot's cascade PR
- **THEN** `publish` refuses before minting the token

### Requirement: Publish verifies the bundle before it mints

For `push` and `recreate`, `publish` SHALL, with `GITHUB_TOKEN` and plain git only and before the token exists, verify the bundle, require its tip to equal the planned new tip, re-run the workflows guard, and lint the body above the Notes marker for a bare mention.

#### Scenario: Bundle tip differs from the plan

- **WHEN** the tip of the verified bundle is not the planned new tip
- **THEN** `publish` refuses before minting the token

### Requirement: Publish bounds the increment before it mints

For `push` and `recreate`, `publish` SHALL, with `GITHUB_TOKEN` and plain git only and before the token exists, bound the increment (requirements "Publish bounds the increment's commits", "Publish limits what a single-parent commit changes", "Publish checks merge commits", "Allow-lists live in .github", "The deny-list wins over the allow-list", "Publish refuses to drop a human commit" and "Publish checks the tag of each moved pin").

#### Scenario: Increment comes first

- **WHEN** `publish` verifies a `push` plan
- **THEN** it bounds the increment before any token exists

### Requirement: Publish renders the text before it mints

For `push` and `recreate`, `publish` SHALL, with `GITHUB_TOKEN` and plain git only and before the token exists, render the title, body and labels itself (requirement "Publish renders the PR text").

#### Scenario: Text comes first

- **WHEN** `publish` verifies a `push` plan
- **THEN** it renders the title, body and labels itself before any token exists

### Requirement: Publish builds comments from fixed texts and pushes under a lease

Every comment SHALL be built inside `publish` from fixed texts, and `publish` SHALL lint every comment it builds for a bare mention, with `GITHUB_TOKEN` and plain git only and before the token exists. Every push and branch delete SHALL carry a lease on the planned old tip (an empty lease where the branch must not exist).

#### Scenario: A comment with a bare mention

- **WHEN** a comment that `publish` builds holds a bare mention
- **THEN** the lint fails before the token exists, whatever the action

#### Scenario: A push under a lease

- **WHEN** `publish` pushes a branch or deletes one
- **THEN** the push or delete carries a lease on the planned old tip, empty where the branch must not exist

### Requirement: A hold added after compute stops publish

When the re-derived cascade PR carries `deps-cascade:hold` that `compute` did not see, `publish` SHALL mint no token and publish nothing, and SHALL end with a notice, not a failure (stop switch 1 used as documented).

#### Scenario: Hold added between compute and publish

- **WHEN** a human adds `deps-cascade:hold` to the cascade PR after `compute` planned a `push`
- **THEN** `publish` writes a notice, skips the mint and every write, and the run is not red

### Requirement: A gates-only run never writes

A gates-only receiver run SHALL never mint the App token or write to the repo. The caller's `publish` job SHALL read its own `gates_only` dispatch input in its `if:` (`inputs.gates_only != true`) and SHALL pass `cascade-publish` the required input `gates-only` as `${{ inputs.gates_only == true }}`.

#### Scenario: Forged outputs on a gates-only run

- **WHEN** release-head code in a gates-only run makes `compute` report `action=push`, `compute-ok=true` and `dry-run=false`, uploads a plan that would verify, and `CASCADE_DRY_RUN` is `false`
- **THEN** the caller's `publish` job is skipped by its own `inputs.gates_only` check, and `cascade-publish`, if it ran anyway, refuses before the mint and pushes nothing

### Requirement: cascade-publish checks the gates-only input first

`cascade-publish` SHALL check the `gates-only` input before the dry-run input, the plan or any API call, in both `verify` and `act`: exactly `false` continues; `true` SHALL fail with "a gates-only run never publishes"; any other value, empty or missing included, SHALL fail. Neither check SHALL read an output of the reusable job.

#### Scenario: Missing gates-only input

- **WHEN** a caller bumps its pin and runs `cascade-publish` without the `gates-only` input
- **THEN** `verify` fails before reading the plan and no token is minted

### Requirement: Receive outputs for a gates-only run

For a gates-only run, `cascade-receive.yml` SHALL output `action` `gates-only` and `compute-ok` `false`, computed from its `gates-only` input rather than from a step that ran repo code.

#### Scenario: Gates-only outputs come from the input

- **WHEN** `cascade-receive.yml` is read
- **THEN** `compute`'s `action` output is `gates-only` and its `ok` output is `false` whenever the `gates-only` input is true, whatever any step wrote

### Requirement: Publish bounds the increment's commits

For `push` and `recreate`, `publish` SHALL take as the bot's increment the new tip's commits that `origin/main` does not have and, for a `push` whose old tip is an ancestor of the new one, that the old tip does not have either. It SHALL refuse the plan, before any token exists, when the increment has more than two commits, a root commit or a commit with more than two parents, or when a commit's author or committer email is not the bot's.

#### Scenario: A commit the bot did not make

- **WHEN** the bundle's commit has a human committer
- **THEN** `publish` refuses before the mint

#### Scenario: Merge mode with a human commit

- **WHEN** the branch holds a human commit that changes `.tasks/` and the bot merges `main` and commits a pin move
- **THEN** `publish` accepts: the human commit is not in the increment, and the bot's merge and pin commits pass

### Requirement: Publish limits what a single-parent commit changes

For `push` and `recreate`, `publish` SHALL refuse the plan, before any token exists, when a single-parent commit of the increment changes a path with a status other than `M`, changes a mode, has a mode other than `100644` or `100755` (a symlink `120000` or gitlink `160000`), or changes a path outside the receiver's allow-list or inside the deny-list.

#### Scenario: A symlink

- **WHEN** `compute`'s commit turns an allowed path into a symlink
- **THEN** `publish` refuses before the mint

### Requirement: Publish checks merge commits

For `push` and `recreate`, `publish` SHALL refuse the plan, before any token exists, when a merge commit's second parent is not on `origin/main` or its tree differs from `git merge-tree --write-tree` of its parents in a path that is not a derived path carrying the second parent's content.

#### Scenario: Second parent off main

- **WHEN** a merge commit of the increment has a second parent that is not on `origin/main`
- **THEN** `publish` refuses the plan before the mint

### Requirement: Allow-lists live in .github

The allow-lists SHALL live in `.github` (`wiring/lib.sh`), keyed by the receiver, never read from the receiver's tree.

#### Scenario: cli's operator module pin file

- **WHEN** cli's task commit changes `internal/operator/pin.go`
- **THEN** `publish` accepts the path, and refuses `internal/operator/manifest.go` or `internal/operator/dist/install.yaml`
- **AND** it accepts `internal/controller/pin.go`, the same file after cli's rename

### Requirement: The deny-list wins over the allow-list

The deny-list SHALL be `.github/**`, `.tasks/**`, any `Taskfile*`, `hack/**` (except cli's `hack/kind-platform.yaml` and `hack/platform/cue.mod/module.cue`), `*.sh`, any `CODEOWNERS`, `release-please-config.json`, `.release-please-manifest.json`, `.cascade-frozen`, `.cascade-hold` and, for opm-operator under either of its names (`opm-controller` after the rename), `modules/**` (its module moves only through its own `module-deps.yml`), and SHALL win over the allow-list.

#### Scenario: A bundle that edits the cascade task

- **WHEN** `compute`'s commit changes `UPSTREAM_VERSION` and `.tasks/cascade/pins.sh`
- **THEN** `publish` refuses naming `.tasks/cascade/pins.sh` and mints no token

#### Scenario: A bundle that edits the Taskfile

- **WHEN** `compute`'s commit changes `Taskfile.yml`
- **THEN** `publish` refuses before the mint

#### Scenario: opm-operator's module

- **WHEN** an opm-operator bot commit changes `modules/opm_operator/cue.mod/module.cue`
- **THEN** `publish` refuses it, although any other `cue.mod/module.cue` is allowed

#### Scenario: The renamed repo's module

- **WHEN** an `opm-controller` bot commit changes `modules/opm_controller/cue.mod/module.cue`
- **THEN** `publish` refuses it, although any other `cue.mod/module.cue` is allowed

### Requirement: Publish refuses to drop a human commit

When a `push` does not contain the old tip and `origin/main..old` holds a commit the bot did not make, `publish` SHALL refuse; it SHALL refuse a `recreate` whenever `origin/main..old` holds such a commit, since `recreate` rebuilds the branch on `main`; `close` SHALL then keep the branch and delete only a bot-only one.

#### Scenario: A rebuild over a human commit

- **WHEN** the remote branch holds a human commit and the plan's new tip does not contain it
- **THEN** `publish` refuses with "would drop commits", and `close` keeps such a branch

#### Scenario: A recreate over a kept human commit

- **WHEN** a branch `close` kept for its human commit has no PR, so `compute` plans `recreate`
- **THEN** `publish` refuses with "recreate would drop commits" before the mint

### Requirement: Publish checks the tag of each moved pin

For `push` and `recreate`, and for every pin whose version differs between the merge base and the new tip (read with the `.github` pin mirror), `publish` SHALL run the resolver's `tag-on-main` itself and SHALL refuse when the tag is not on its repo's `main` or the check fails, so a forged tag is refused even when `compute` skipped the resolver.

#### Scenario: A pin moved to a forged tag

- **WHEN** the new tip moves a pin to `v0.2.0` and that tag of its repo is not on `main`
- **THEN** `publish` refuses with "whose tag is not on its repo's main" before the mint

### Requirement: Publish filters compute's warnings

`publish` SHALL pass `compute`'s warnings to the resolver after a line filter: at most 100 lines of at most 500 printable bytes with no `<`, `>`, `[`, `]`, `://`, `#<digit>` or bare mention; dropped lines are counted in one added warning.

#### Scenario: A warning with a link

- **WHEN** `compute`'s warnings hold a line with `://`
- **THEN** `publish` drops that line and adds one warning that counts the dropped lines

### Requirement: Publish computes the final title itself

`publish` SHALL compute the final title from the title its own resolver run renders and the live PR; a different planned title SHALL be a notice.

#### Scenario: Planned title differs

- **WHEN** the title in the plan differs from the title `publish` computes
- **THEN** `publish` uses its own title and writes a notice

### Requirement: Publish refuses an oversize body or an empty push diff

`publish` SHALL refuse a body rendered for a `push` or `recreate` that is over 65000 bytes, and an empty diff for a push.

#### Scenario: Empty diff for a push

- **WHEN** the rendered diff for a `push` is empty
- **THEN** `publish` refuses

### Requirement: The mirror records the sha256 of receiver files

`.github` (`wiring/lib.sh`, `mirror_sources`) SHALL record, per receiver, the sha256 of each receiver file its publish mirrors copy or were read from: `.tasks/cascade/pins.sh`, `.tasks/cascade/classes`, the `.tasks/cascade/lib.sh` that `pins.sh` sources where it does (library, opm-operator), and, for catalog_opm, library, opm-operator and cli, the `.tasks/cascade/cascade.sh` its allow-list (`publish_paths`) was read from.

#### Scenario: Recorded files of a receiver

- **WHEN** the recorded files of cli are read
- **THEN** they hold the sha256 of `.tasks/cascade/pins.sh`, `.tasks/cascade/classes` and `.tasks/cascade/cascade.sh` on the receiver

### Requirement: The renamed repo records the same files

`opm-controller` SHALL have the same recorded files and hashes as `opm-operator` until the renamed repo's own change to them.

#### Scenario: Controller records

- **WHEN** the recorded files of `opm-controller` and `opm-operator` are compared before the renamed repo changes them
- **THEN** the files and hashes are equal

### Requirement: Publish refuses a plan from a stale mirror

For `push` and `recreate`, `publish` SHALL, before it reads the bundle, runs the workflows guard or bounds the increment, and before any token exists, read each recorded file on the receiver's `origin/main` and refuse the plan when its sha256 differs from the recorded one or the file is missing there, with one message naming the receiver, the path, the sha256 found (or `missing`) and the recorded sha256.

#### Scenario: pins.sh changed on main

- **WHEN** the receiver's `main` holds a `.tasks/cascade/pins.sh` whose sha256 is not the recorded one, and `compute` planned a `push`
- **THEN** `publish` refuses with "the .github mirror of <receiver> is stale: .tasks/cascade/pins.sh on its main has sha256 <found>, the mirror was written from <recorded>" and mints no token

#### Scenario: classes removed from main

- **WHEN** the receiver's `main` has no `.tasks/cascade/classes`
- **THEN** `publish` refuses naming `.tasks/cascade/classes` with sha256 `missing`

#### Scenario: cascade.sh changed on main

- **WHEN** cli's `main` holds a `.tasks/cascade/cascade.sh` whose sha256 is not the recorded one, while its `pins.sh`, `lib.sh` and `classes` are unchanged, and `compute` planned a `push`
- **THEN** `publish` refuses naming `.tasks/cascade/cascade.sh` and mints no token

#### Scenario: An unrelated change on main

- **WHEN** `main` changed only files the mirrors do not copy
- **THEN** the mirror check passes and `publish` verifies the plan as before

### Requirement: A stale mirror does not hold other actions

`close`, `conflict` and `too_long` SHALL NOT be refused for a stale mirror.

#### Scenario: A stale mirror does not hold a close

- **WHEN** the receiver's `main` holds a `pins.sh` the mirror was not written from, and `compute` planned `close`, `conflict` or `too_long`
- **THEN** `publish` verifies the plan as it would with a current mirror

### Requirement: The mirrored pins report matches the receiver's

The mirror of each receiver's `pins.sh` SHALL report the same rows as that receiver's own `pins.sh` on its `main`.

#### Scenario: Same rows

- **WHEN** a receiver's own `pins.sh` and its `.github` mirror read the same `main`
- **THEN** both report the same rows

### Requirement: The cli mirror reports the controller pins

For cli, the mirrored pin report SHALL show the library, the controller release and the controller module (`github.com/open-platform-model/opm-controller` and `opmodel.dev/modules/opm_controller@v0`, from `PinnedControllerVersion` and `PinnedModuleVersion` in `internal/controller/pin.go`; before cli's rename `github.com/open-platform-model/opm-operator` and `opmodel.dev/modules/opm_operator@v0` from `internal/operator/pin.go`), the opm catalog and core.

#### Scenario: cli's module pin in the body

- **WHEN** cli's `internal/operator/pin.go` moves `PinnedModuleVersion` from `0.1.0` to `0.2.0`
- **THEN** the mirrored pin report shows `opmodel.dev/modules/opm_operator@v0` moving from `v0.1.0` to `v0.2.0`, as cli's own `pins.sh` does

#### Scenario: cli's pin file after its rename

- **WHEN** cli's `main` holds `internal/controller/pin.go` with `PinnedControllerVersion = "v1.0.0-beta.9"` and `PinnedModuleVersion = "0.2.0"`
- **THEN** the mirrored pin report has the rows `github.com/open-platform-model/opm-controller` (`opm-controller`, `v1.0.0-beta.9`) and `opmodel.dev/modules/opm_controller@v0` (`opm-controller module`, `v0.2.0`)

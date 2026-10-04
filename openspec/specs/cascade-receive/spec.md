# cascade-receive Specification

## Purpose
The reusable receive workflow and the composite publish action each downstream repo runs from its `deps-cascade.yml`: they run the
repo's `task -x deps:cascade`, keeps one rolling `deps/cascade` PR up to date without ever
needing the Workflows permission, and never lets the job that runs repo code hold the App key.

## Requirements

### Requirement: Receive interface and job split

`.github/workflows/cascade-receive.yml` SHALL take the inputs `dry-run` (boolean, required),
`gates-only` (boolean, default false), `g2-mode` and `g3-mode` (string, default `warn`; any value
other than `warn` or `enforce` fails `compute`), `setup-go` (boolean, default false; Go from
`repo/go.mod`), `setup-cue` (boolean, default true) and `cue-version` (string, default
`v0.17.1`), SHALL run two jobs, and SHALL output `action`,
`dry-run` and `compute-ok` (true only when every `compute` step succeeded). The third job,
`publish`, is the caller's own: it needs the reusable job, declares `environment: cascade`, and
runs the composite action `.github/actions/cascade-publish` with the inputs `dry-run`
(required), `labels-managed` (default `false`), `client-id` and `private-key`:

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
true, the repo variable `CASCADE_DRY_RUN` is exactly `false` and the run's ref is
`refs/heads/main`. The caller SHALL pass `cascade-publish` the input `dry-run` as
`${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}`, and the action itself SHALL
publish only when that input is exactly `false`: `true` SHALL publish nothing, mint no token and
succeed; any other value, empty or missing included, SHALL fail before the mint. So the stop
switch holds even when a caller's `if:` is wrong. `publish` SHALL also refuse, before minting, a
plan whose `effective_dry_run` is true. `compute` SHALL
treat a run from any ref other than `refs/heads/main` as a dry run whatever the input says. In a
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

### Requirement: Payload is a validated hint

On a `repository_dispatch` run `compute` SHALL accept the payload only when `source` is a string
in the receiver's allowlist and `tags` is an array of 1 to 8 strings each matching the tag shape
for that source; unknown keys SHALL be ignored. Allowlists: `catalog_opm` accepts `core`, `cli`;
`library` accepts `core`, `catalog_opm`; `opm-operator` accepts `catalog_opm`, `library`, `cli`;
`cli` accepts `catalog_opm`, `library`, `opm-operator`; `cascade-sandbox-down` accepts
`cascade-sandbox-up`. A receiver outside this list SHALL fail with "not a cascade receiver". A
valid payload SHALL set `CASCADE_SOURCE`, `CASCADE_TAGS` and one `CASCADE_EXPECT` pair built from
the last tag (`catalog_opm` tags lose their `opm-` prefix). An invalid payload SHALL be dropped
whole with a warning and a summary line naming why, and the run SHALL continue as a sweep. The
payload SHALL never set a label. Only `cascade-sandbox-down` SHALL export
`CASCADE_EXTRA_SOURCES=cascade-sandbox-up`.

#### Scenario: Hostile payload

- **WHEN** the payload is `{"source":"evil","tags":["@x"]}`
- **THEN** the payload is dropped with a warning, the run behaves as a sweep, and no mention appears in any text the bot writes

#### Scenario: Nine tags

- **WHEN** the payload carries nine valid tags
- **THEN** the whole payload is dropped and the run continues as a sweep

### Requirement: The cascade PR is the bot's own same-repo PR

The cascade PR SHALL be the open PR on head `deps/cascade` and base `main` that is not from a
fork, whose head repository owner is `open-platform-model` and whose author is
`app/opm-cascade`. More than one such PR SHALL fail the job. A fork PR or a human-authored PR on a
branch named `deps/cascade` SHALL never be read, edited or closed.

#### Scenario: Fork PR on deps/cascade

- **WHEN** a fork opens a PR from its own `deps/cascade` branch
- **THEN** the receiver ignores it and reads neither its title nor its body

### Requirement: Mode selection

`compute` SHALL pick the mode from the remote `deps/cascade` tip (`OLD`) and the cascade PR:

| State | Mode |
| --- | --- |
| the cascade PR carries `deps-cascade:hold` | `skip` |
| no `OLD` | `fresh` |
| `OLD` set and no open cascade PR | `recreate` |
| open cascade PR, every commit in `origin/main..origin/deps/cascade` has author and committer email `337635439+opm-cascade[bot]@users.noreply.github.com` | `rebuild` |
| open cascade PR, any other author or committer in that range | `merge` |

`fresh`, `rebuild` and `recreate` SHALL start from `origin/main`. `merge` SHALL check out
`origin/deps/cascade` and run `git merge --no-edit origin/main`: when only derived files conflict
(`go.mod`, `go.sum`, any `cue.mod/module.cue`, `internal/operator/dist/install.yaml`,
`manifest.go`), it SHALL take `main`'s side, commit `Merge origin/main into deps/cascade` and let
the task regenerate them; any other conflict SHALL abort the merge and give mode `conflict` with
the conflicting paths. The bot SHALL never rebase and never drop a human commit.

#### Scenario: Human commit survives

- **WHEN** a human pushed a commit to `deps/cascade` and a new upstream release arrives
- **THEN** the human commit is an ancestor of the new tip and the bot's commit is on top

#### Scenario: Bot-only branch is rebuilt

- **WHEN** the branch holds only bot commits and a new upstream release arrives
- **THEN** the branch is rebuilt from `origin/main` to one bot commit and the PR number is unchanged

### Requirement: Task run, commit and Notes

`compute` SHALL refuse a dirty `repo/` tree, run `task -x deps:cascade` with
`CASCADE_BASE=origin/main` (exit 3: no commit; any exit other than 0 or 3: job error), commit
the result as `opm-cascade[bot]` with the computed title as the only line, and require the title
computed before the commit to equal the title computed after it. All scratch files SHALL live
under `$RUNNER_TEMP/cascade/`, never in `repo/` or `org-github/`. With an open cascade PR the
Notes SHALL be every byte after the first line equal to `<!-- cascade-notes: the bot keeps
everything below this line -->` (one trailing `\r` removed for the comparison), or the whole old
body when no such line exists, and SHALL be passed to the body task through
`CASCADE_NOTES_FILE` unchanged.

#### Scenario: CRLF body is stable

- **WHEN** a human edited the PR body on the web so it has CRLF line ends, and two runs follow with no upstream change
- **THEN** the body after the second run is byte-identical to the body after the first

#### Scenario: Body rewritten by a human

- **WHEN** the open PR's body has no Notes marker line
- **THEN** the whole old body becomes the Notes of the new body

### Requirement: Final title

The final title SHALL be the computed title unless the PR is retitled: an open cascade PR whose
body has a `<!-- cascade-title: <T> -->` line above the Notes marker with a non-empty `<T>` that
differs from the PR's current title. A retitled PR SHALL keep its current title unchanged, `!`
included, for good. When the computed type ranks above both the current title's type and the
marker's type (`ci` 1, `test` 2, `fix` 3, `feat` 4, other 0), `publish` SHALL post the title-rise
comment once and SHALL NOT change the title. The bot SHALL never add `!`.

#### Scenario: Human retitle kept

- **WHEN** a human retitled the PR to `feat(deps): sandbox` and the computed title is `fix(deps): bump up to v0.5.0`
- **THEN** the title stays `feat(deps): sandbox`, the body marker carries the computed title, and no title-rise comment is posted

#### Scenario: Marker pasted into the Notes

- **WHEN** the only `cascade-title` marker in the body sits below the Notes marker
- **THEN** the PR counts as not retitled

### Requirement: Labels

The planned labels SHALL be the union of `deps-cascade`, the `cascade-labels` marker of the new
body, and `deps-cascade:breaking` when any non-draft release of a moved pin's upstream with a
version `v` where `from < v <= to` has `BREAKING CHANGES` in its body. The breaking check SHALL
cover the whole range between the pin on `main` and the pin on the branch, never read the
payload, ignore pins of third-party modules, and on an API error add no label and write a summary
warning. The bot SHALL only add labels, with one exception: it removes `deps-cascade:conflict`
after a successful push. Outside cli (`labels-managed: false`) `publish` SHALL create or update
the five labels `deps-cascade`, `deps-cascade:conflict`, `deps-cascade:hold`,
`deps-cascade:breaking` and `need-human-review` with the colours and descriptions of workspace
RELEASING.md, section "Labels"; with `labels-managed: true` it SHALL fail with "declare it in
.github/labels.yml" when any of them is missing.

#### Scenario: Breaking release in the middle of the range

- **WHEN** the pin moves from `v1.0.0` to `v1.3.0` and only `v1.2.0`'s release body contains `BREAKING CHANGES`
- **THEN** the planned labels include `deps-cascade:breaking`

### Requirement: Action table

`compute` SHALL pick exactly one action: `skip` for mode `skip`; `conflict` for mode `conflict`;
`too_long` when the body exceeds 65000 bytes (Notes are never truncated); `close` when the final
tree equals `origin/main` and a cascade PR is open or `OLD` is set; `noop` when the tree equals
`origin/main` with no PR and no `OLD`; otherwise `push`, which also covers a title, body or label
change when the tip is unchanged.

#### Scenario: Upstream already merged by hand

- **WHEN** `main` caught up with every pin the open cascade PR moved
- **THEN** the action is `close`, and `publish` comments, closes the PR and deletes the branch under a lease

### Requirement: Workflows guard

The bot SHALL push only updates GitHub cannot read as a workflow change. With
`D1 = git diff --name-only origin/main NEW -- .github/workflows/` and
`D2 = git diff --name-only OLD NEW -- .github/workflows/` (in-place updates only), and the rule
constant `WF_GUARD_RULE`, which ships as `tree` (sandbox cycle E4c: GitHub accepted, from the
App without the Workflows permission, both an in-place lease update across a workflow change on
`main` and a pushed merge commit bringing that change in); `strict` stays implemented for the
case GitHub tightens the rule:

| Mode | Push allowed (`strict`) | Push allowed (`tree`) | Otherwise |
| --- | --- | --- | --- |
| `fresh` | `D1` empty | `D1` empty | job error |
| `rebuild` | `D1` and `D2` empty | `D1` empty | `strict`: action `recreate` |
| `recreate` | `D1` empty | `D1` empty | job error |
| `merge` | `D1` and `D2` empty | `D1` empty | action `conflict`, reason `workflows` |

The bot SHALL never call the update-branch API or a server-side merge.

#### Scenario: Main changed a workflow under a bot-only PR, shipped rule

- **WHEN** `WF_GUARD_RULE` is `tree`, the PR has only bot commits, and `main` changed `.github/workflows/touch.yml` since the branch was built
- **THEN** the action is `push`: the same PR is rebuilt in place under the lease, Notes and labels unchanged

#### Scenario: Main changed a workflow under a human commit, shipped rule

- **WHEN** `WF_GUARD_RULE` is `tree`, the PR has a human commit, and `main` changed a workflow file
- **THEN** the action is `push`: `main` is merged into the branch, the human commit stays an ancestor, and the merge commit is pushed

#### Scenario: Main changed a workflow under a bot-only PR

- **WHEN** `WF_GUARD_RULE` is `strict`, the PR has only bot commits, and `main` changed `.github/workflows/touch.yml` since the branch was built
- **THEN** the action is `recreate`: the old PR is closed with a comment, the branch is deleted and pushed fresh, a new PR opens with the old Notes and its `deps-cascade:breaking` and `need-human-review` labels, and the old PR names the new one

#### Scenario: Main changed a workflow under a human commit

- **WHEN** `WF_GUARD_RULE` is `strict`, the PR has a human commit, and `main` changed a workflow file
- **THEN** the action is `conflict`: no push, the label `deps-cascade:conflict` is added and the workflows conflict comment is posted once

### Requirement: Publish verifies before it mints

`publish` SHALL treat the uploaded plan as untrusted and, with `GITHUB_TOKEN` and plain git only,
before the token exists: refuse an unknown action or a label outside the five bot-relevant labels;
re-derive the cascade PR and refuse a PR-number mismatch; stop with "deps/cascade moved since
compute; the next run retries" when the remote tip differs from the planned old tip; for `push`
and `recreate` verify the bundle, require its tip to equal the planned new tip and re-run the
workflows guard; recompute the final title from the live PR and refuse a mismatch or a computed
title outside `fix(deps)`, `test(fixtures)` and `ci(deps)`; and lint the body above the Notes
marker and every comment it builds for a bare mention. Every comment SHALL be built inside
`publish` from fixed texts. Every push and branch delete SHALL carry a lease on the planned old
tip (an empty lease where the branch must not exist). When the re-derived cascade PR carries
`deps-cascade:hold` that `compute` did not see, `publish` SHALL mint no token and publish nothing,
and SHALL end with a notice, not a failure (stop switch 1 used as documented).

#### Scenario: Hold added between compute and publish

- **WHEN** a human adds `deps-cascade:hold` to the cascade PR after `compute` planned a `push`
- **THEN** `publish` writes a notice, skips the mint and every write, and the run is not red

#### Scenario: Human push between compute and publish

- **WHEN** a human pushes to `deps/cascade` after `compute` read the tip
- **THEN** `publish` fails before minting the token and the next run retries

#### Scenario: Forged plan

- **WHEN** the plan names a PR number that is not the bot's cascade PR
- **THEN** `publish` refuses before minting the token

### Requirement: Conflict and too-long states are visible

For `conflict`, `publish` SHALL add `deps-cascade:conflict` and `deps-cascade`, post the conflict
comment only when the label was not already present, push nothing and succeed. For `too_long`, it
SHALL post the too-long comment only when its newest comment is not already that comment, push
and edit nothing, and fail, so the run stays red until a human trims the Notes.

#### Scenario: No comment spam

- **WHEN** two runs in a row end in `conflict`
- **THEN** the conflict comment is posted once

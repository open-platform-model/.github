# cascade-gates Specification

## Purpose
Gates G2 `cascade/freshness` and G3 `cascade/settled` (workspace RELEASING.md, section "Gates"):
how the receiver evaluates them on open release PRs, how they are posted as commit statuses, and
the per-PR reusable workflow that keeps both contexts present on every PR.

## Requirements

### Requirement: Gate scope

Gates SHALL be evaluated only on open PRs with base `main` whose head ref starts with
`release-please--` and whose head repository is the base repository. Fork PRs SHALL never be
evaluated and no PR head SHALL ever be checked out by the per-PR workflow.

#### Scenario: Fork release-named PR

- **WHEN** a fork opens a PR from a branch named `release-please--branches--main`
- **THEN** it is treated as not a release PR and both contexts read `n/a: not a release PR`

### Requirement: G2 freshness

For each release PR in scope, the receiver's `compute` job SHALL add a detached worktree of the
PR head under `$RUNNER_TEMP/cascade/`, run the head's own `task -x deps:cascade` there with
`CASCADE_BASE` set to the head and with `CASCADE_EXPECT`, `CASCADE_SOURCE`, `CASCADE_TAGS` and
`CASCADE_NOTES_FILE` unset, and rate the result: exit 3 is `ok: shipped pins current`; exit 0
with any changed path the head's `classes` file classifies as `shipped` is a problem whose
message lists the moved shipped pins (`behind: <display> <from>→<to>`); exit 0 with no shipped
path is `ok: only test/release-tool pins behind`; any other exit is an evaluator error. The
worktree SHALL be removed also on error. This evaluation SHALL run before any pin work in the run,
and its results SHALL be uploaded as the artifact `cascade-gates` even when a later step fails.

#### Scenario: Shipped pin behind

- **WHEN** core published `v2.0.0-beta.3` while the library release PR still pins `v2.0.0-beta.2` in a shipped path
- **THEN** G2 is a problem with the message `behind: core v2.0.0-beta.2→v2.0.0-beta.3`

#### Scenario: Held pin

- **WHEN** the release head's `.cascade-hold` caps that pin at its current version
- **THEN** G2 is `ok: shipped pins current`

### Requirement: G3 settled

For each G3 upstream of the receiver (`catalog_opm`: `core`; `library`: `core`, `catalog_opm`;
`opm-operator`: `catalog_opm`, `library`; `cli`: `catalog_opm`, `library`, `opm-operator`;
`cascade-sandbox-down`: `cascade-sandbox-up`), G3 SHALL be a problem when the upstream's own
cascade PR (same filter as the receiver's) has a title starting `fix(deps)` or `feat(deps)`
(`<upstream> has open cascade #<n>`), or when an open PR labelled `autorelease: pending` in the
upstream has a `**deps:**` bullet in its body (`<upstream> release #<n> pending with deps`).
Otherwise G3 SHALL be `ok: upstreams settled`; an API error is an evaluator error. The
release-tool edges from cli SHALL never count. G3 SHALL be evaluated by the receiver's `gates`
job, which runs no repo code, from API reads made with `GITHUB_TOKEN`, once per run when at
least one release PR is in scope, and posted on every in-scope release PR head. It SHALL never
be read from a file or output of `compute`, which ran release-head code before writing them.

#### Scenario: Upstream cascade open

- **WHEN** library's cascade PR titled `fix(deps): bump core to v2.0.0-beta.3` is open and cli has a release PR
- **THEN** cli's G3 is a problem with the message `library has open cascade #<n>`

#### Scenario: Forged settled result

- **WHEN** release-head code makes `gates.json` report G3 `ok` while an upstream cascade PR titled `fix(deps)` is open
- **THEN** the `gates` job ignores that entry's G3 field and posts the problem it evaluated itself

### Requirement: Status mapping

Statuses SHALL be posted with `GITHUB_TOKEN` (so their integration is GitHub Actions) as
contexts `cascade/freshness` and `cascade/settled` on the release PR head, with the run URL as
`target_url` and the description cut to 140 characters with `…`:

| Mode | Clean | Problem | Evaluator error |
| --- | --- | --- | --- |
| `warn` | `success`, `ok: …` | `success`, `WARN: <msg>` | `success`, `WARN: gate could not run, see the run` |
| `enforce` | `success`, `ok: …` | `failure`, `<msg>` | `error`, `could not evaluate, see the run` |

The `gates` job SHALL run after `compute` unless it was cancelled, also in dry runs and gates-only
runs. It SHALL list the open same-repo release PR heads with `GITHUB_TOKEN` and post only on
them, posting nothing and failing when that list cannot be read. Because `compute` runs repo
code before it writes `gates.json`, the `gates` job SHALL take only each entry's G2 result from
it, only for a listed head, and SHALL skip any other entry with a warning. A listed head without
a G2 result (the `cascade-gates` artifact is missing, or it has no entry for that head) SHALL get
no `cascade/freshness` status and a warning in `warn`, and `error`, `could not evaluate, see the
run` in `enforce`; its `cascade/settled` status SHALL be posted either way.

#### Scenario: Forged gate entry

- **WHEN** `gates.json` holds an entry whose `sha` is not the head of an open same-repo release PR
- **THEN** no status is posted on that commit and the run warns that it skipped it

#### Scenario: Warn mode problem

- **WHEN** G2 finds a problem and `g2-mode` is `warn`
- **THEN** `cascade/freshness` is `success` with a description starting `WARN: `

#### Scenario: Long description

- **WHEN** a problem message is 300 characters long
- **THEN** the posted description is 140 characters ending in `…`

#### Scenario: Missing artifact

- **WHEN** `compute` uploaded no `cascade-gates` artifact and a release PR is open, with both modes `warn`
- **THEN** the `gates` job posts `cascade/settled` from its own G3 evaluation and no `cascade/freshness` status

### Requirement: Per-PR gates workflow

`.github/workflows/cascade-gates.yml` SHALL take the inputs `g2-mode` and `g3-mode`, run one job named `Cascade gates` with `permissions: {statuses: write, actions:
write}`, check out nothing, and: on a PR that is not a same-repo release PR post both contexts as
`success`, `n/a: not a release PR`; on a same-repo release PR post both as `pending`, "evaluating
in Deps cascade" in `enforce` mode only, then start `deps-cascade.yml` on `main` with
`gates_only=true` using `GITHUB_TOKEN`. When that start fails it SHALL post both contexts as
`error`, `could not dispatch Deps cascade, see the run` in `enforce` mode or `success`,
`WARN: gate could not run, see the run` in `warn` mode, and then fail. A gates-only receiver run
SHALL evaluate and post the gates and stop: it never runs the task on `main` and never publishes.

#### Scenario: Ordinary PR

- **WHEN** a PR from `feat/x` opens in a receiver repo
- **THEN** `cascade/freshness` and `cascade/settled` are both `success` with `n/a: not a release PR`

#### Scenario: Release PR head moves

- **WHEN** release-please pushes a new head to an open release PR
- **THEN** a gates-only `deps-cascade.yml` run starts and posts both contexts on the new head

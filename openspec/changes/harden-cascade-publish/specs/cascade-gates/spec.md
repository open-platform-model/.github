## MODIFIED Requirements

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

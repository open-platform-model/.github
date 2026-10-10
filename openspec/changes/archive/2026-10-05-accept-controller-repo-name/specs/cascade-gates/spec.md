## MODIFIED Requirements

### Requirement: G3 settled

For each G3 upstream of the receiver (`catalog_opm`: `core`; `library`: `core`, `catalog_opm`;
`opm-operator` and `opm-controller`: `catalog_opm`, `library`; `cli`: `catalog_opm`, `library`,
`opm-operator`; `cascade-sandbox-down`: `cascade-sandbox-up`), G3 SHALL be a problem when the
upstream's own
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

#### Scenario: The renamed repo's upstreams

- **WHEN** `opm-controller` has a release PR
- **THEN** its G3 reads the cascade state of `catalog_opm` and `library`

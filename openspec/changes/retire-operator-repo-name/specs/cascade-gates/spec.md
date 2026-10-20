## MODIFIED Requirements

### Requirement: G3 is a problem when an upstream has an open cascade PR

For each G3 upstream of the receiver (`catalog_opm`: `core`; `library`: `core`, `catalog_opm`; `opm-controller`: `catalog_opm`, `library`; `cli`: `catalog_opm`, `library`, `opm-controller`; `cascade-sandbox-down`: `cascade-sandbox-up`), G3 SHALL be a problem when the upstream's own cascade PR (same filter as the receiver's) has a title starting `fix(deps)` or `feat(deps)` (`<upstream> has open cascade #<n>`).

#### Scenario: Upstream cascade open

- **WHEN** library's cascade PR titled `fix(deps): bump core to v2.0.0-beta.3` is open and cli has a release PR
- **THEN** cli's G3 is a problem with the message `library has open cascade #<n>`

#### Scenario: The renamed repo's upstreams

- **WHEN** `opm-controller` has a release PR
- **THEN** its G3 reads the cascade state of `catalog_opm` and `library`

### Requirement: G3 is a problem when an upstream release PR is pending with deps

For each G3 upstream of the receiver (`catalog_opm`: `core`; `library`: `core`, `catalog_opm`; `opm-controller`: `catalog_opm`, `library`; `cli`: `catalog_opm`, `library`, `opm-controller`; `cascade-sandbox-down`: `cascade-sandbox-up`), G3 SHALL be a problem when an open PR labelled `autorelease: pending` in the upstream has a `**deps:**` bullet in its body (`<upstream> release #<n> pending with deps`).

#### Scenario: Release PR pending with deps

- **WHEN** an open PR labelled `autorelease: pending` in the upstream has a `**deps:**` bullet in its body
- **THEN** G3 is a problem with the message `<upstream> release #<n> pending with deps`

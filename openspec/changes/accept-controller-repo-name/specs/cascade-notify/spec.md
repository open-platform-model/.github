## MODIFIED Requirements

### Requirement: Source and targets are fixed

The source SHALL be the calling repo's name; a caller SHALL NOT be able to choose it. The
targets SHALL come from this fixed map, and a source outside it SHALL fail the job with "not a
cascade source":

| Source | Targets |
| --- | --- |
| `core` | `catalog_opm`, `library` |
| `catalog_opm` | `library`, `opm-operator`, `cli` |
| `library` | `opm-operator`, `cli` |
| `opm-operator` or `opm-controller` | `cli` |
| `cli` | `catalog_opm`, `opm-operator` |
| `cascade-sandbox-up` | `cascade-sandbox-down` |

`opm-controller` is the name GitHub gives `opm-operator` at its rename; a target list SHALL
name only the repo's old name until a later change flips it, because the targets set the App
token's `repositories:`.

The `tag` input SHALL match `^opm-v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$` when the source is
`catalog_opm`, and `^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$` for every other source, or the
job SHALL fail before the token is minted.

#### Scenario: Unknown source

- **WHEN** a repo outside the map runs the `cascade-notify` action
- **THEN** the job fails with "not a cascade source" and mints no token

#### Scenario: Catalog tag shape

- **WHEN** `catalog_opm` calls it with `tag: v4.5.1`
- **THEN** the job fails before the mint because the tag lacks the `opm-` prefix

#### Scenario: The renamed repo releases

- **WHEN** `opm-controller` calls it with `tag: v1.0.0-beta.9`
- **THEN** the target is `cli`

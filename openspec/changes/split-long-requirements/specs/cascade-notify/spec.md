## MODIFIED Requirements

### Requirement: Notify interface

`.github/actions/cascade-notify/action.yml` SHALL be a composite action taking the inputs `tag` (required), `client-id` and `private-key` (both required). It SHALL NOT have a dry-run mode; the repo variable `CASCADE_NOTIFY=off` is checked by the caller job's `if:`.

#### Scenario: Caller switch off

- **WHEN** an upstream sets `CASCADE_NOTIFY=off` and its caller job carries `vars.CASCADE_NOTIFY != 'off'` in its `if:`
- **THEN** the notify job is skipped and no dispatch is sent

## REMOVED Requirements

### Requirement: Source and targets are fixed
**Reason**: Split into requirements that each state one behavior.
**Migration**: See "The source is the calling repo's name", "Targets come from a fixed map", "A target list names only the old repo name" and "The tag input matches a fixed shape".

## ADDED Requirements

### Requirement: The upstream runs the notify action as its only step

The upstream SHALL run it as the only step of its own job named `Notify downstream`, which declares `environment: cascade`, `permissions: {contents: read}` and `timeout-minutes: 20`, and passes `vars.CASCADE_APP_CLIENT_ID` and `secrets.CASCADE_APP_PRIVATE_KEY`. It is the `.github/actions/cascade-notify/action.yml` composite action of the requirement "Notify interface".

#### Scenario: Notify downstream job

- **WHEN** an upstream calls the notify action
- **THEN** it runs it as the only step of its own job named `Notify downstream`, which declares `environment: cascade`, `permissions: {contents: read}` and `timeout-minutes: 20`, and passes `vars.CASCADE_APP_CLIENT_ID` and `secrets.CASCADE_APP_PRIVATE_KEY`

### Requirement: The source is the calling repo's name

The source SHALL be the calling repo's name; a caller SHALL NOT be able to choose it.

#### Scenario: A caller names another source

- **WHEN** a caller tries to choose a source other than its own repo name
- **THEN** the source is still the calling repo's name

### Requirement: Targets come from a fixed map

The targets SHALL come from this fixed map, and a source outside it SHALL fail the job with "not a cascade source". The map is the table in the scenario "Target map".

#### Scenario: Unknown source

- **WHEN** a repo outside the map runs the `cascade-notify` action
- **THEN** the job fails with "not a cascade source" and mints no token

#### Scenario: The renamed repo releases

- **WHEN** `opm-controller` calls it with `tag: v1.0.0-beta.9`
- **THEN** the target is `cli`

#### Scenario: Target map

- **WHEN** the `cascade-notify` action runs for a source
- **THEN** the targets are those of this table:

| Source | Targets |
| --- | --- |
| `core` | `catalog_opm`, `library` |
| `catalog_opm` | `library`, `opm-operator`, `cli` |
| `library` | `opm-operator`, `cli` |
| `opm-operator` or `opm-controller` | `cli` |
| `cli` | `catalog_opm`, `opm-operator` |
| `cascade-sandbox-up` | `cascade-sandbox-down` |

### Requirement: A target list names only the old repo name

`opm-controller` is the name GitHub gives `opm-operator` at its rename; a target list SHALL name only the repo's old name until a later change flips it, because the targets set the App token's `repositories:`.

#### Scenario: Target list with the new name

- **WHEN** a target list names `opm-controller`
- **THEN** that breaks the rule that a target list SHALL name only the repo's old name until a later change flips it

### Requirement: The tag input matches a fixed shape

The `tag` input SHALL match `^opm-v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$` when the source is `catalog_opm`, and `^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$` for every other source, or the job SHALL fail before the token is minted.

#### Scenario: Catalog tag shape

- **WHEN** `catalog_opm` calls it with `tag: v4.5.1`
- **THEN** the job fails before the mint because the tag lacks the `opm-` prefix

#### Scenario: Tag shape of another source

- **WHEN** a source other than `catalog_opm` calls it with `tag: opm-v4.5.1`
- **THEN** the job fails before the mint because the tag does not match `^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$`

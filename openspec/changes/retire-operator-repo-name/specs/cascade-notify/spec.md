## MODIFIED Requirements

### Requirement: Dispatch payload

For each target the job SHALL send `POST /repos/open-platform-model/<target>/dispatches` with
exactly this body, built with `jq` and never by string interpolation:
`{"event_type":"upstream-released","client_payload":{"source":"<source>","tags":["<tag>"]}}`.
It SHALL try every target even after one fails, make up to 3 attempts per target with a 5 and then a 15 second
wait between them, write one summary line per target with its HTTP result, and fail the job when
any target still failed.

#### Scenario: Payload bytes

- **WHEN** `library` notifies with tag `v1.0.0-beta.4`
- **THEN** `opm-controller` and `cli` each receive `{"event_type":"upstream-released","client_payload":{"source":"library","tags":["v1.0.0-beta.4"]}}`

#### Scenario: One target down

- **WHEN** the first target answers 500 three times and the second answers 204
- **THEN** the second target is still dispatched, the summary lists both results, and the job fails

### Requirement: Go proxy wait for library

When the source is `library`, the job SHALL poll
`https://proxy.golang.org/github.com/open-platform-model/library/@v/<tag>.info` every 30 seconds
for up to 10 minutes before dispatching, and on timeout SHALL log a warning and dispatch anyway.
This wait SHALL never fail the job.

#### Scenario: Proxy lags

- **WHEN** the proxy never serves the tag within 10 minutes
- **THEN** the job logs a warning and still dispatches to `opm-controller` and `cli`

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
| `catalog_opm` | `library`, `opm-controller`, `cli` |
| `library` | `opm-controller`, `cli` |
| `opm-controller` | `cli` |
| `cli` | `catalog_opm`, `opm-controller` |
| `cascade-sandbox-up` | `cascade-sandbox-down` |

## REMOVED Requirements

### Requirement: A target list names only the old repo name

**Reason**: The rename of opm-operator to opm-controller is done and every receiver's and source's own rename has merged; the maps name `opm-controller` only.

**Migration**: none; a caller still pinned to the earlier `.github` commit keeps running that commit's code until its pin moves.

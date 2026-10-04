## Purpose

The composite notify action an upstream repo runs after its release is published, which tells
each downstream receiver through `repository_dispatch` that a new upstream version exists.

## ADDED Requirements

### Requirement: Notify interface

`.github/actions/cascade-notify/action.yml` SHALL be a composite action taking the inputs `tag`
(required), `org-github-ref` (default `main`), `client-id` and `private-key` (both required). The
upstream runs it as the only step of its own job named `Notify downstream`, which declares
`environment: cascade`, `permissions: {contents: read}` and `timeout-minutes: 20`, and passes
`vars.CASCADE_APP_CLIENT_ID` and `secrets.CASCADE_APP_PRIVATE_KEY`. It SHALL NOT have a dry-run
mode; the repo variable `CASCADE_NOTIFY=off` is checked by the caller job's `if:`.

#### Scenario: Caller switch off

- **WHEN** an upstream sets `CASCADE_NOTIFY=off` and its caller job carries `vars.CASCADE_NOTIFY != 'off'` in its `if:`
- **THEN** the notify job is skipped and no dispatch is sent

### Requirement: Source and targets are fixed

The source SHALL be the calling repo's name; a caller SHALL NOT be able to choose it. The
targets SHALL come from this fixed map, and a source outside it SHALL fail the job with "not a
cascade source":

| Source | Targets |
| --- | --- |
| `core` | `catalog_opm`, `library` |
| `catalog_opm` | `library`, `opm-operator`, `cli` |
| `library` | `opm-operator`, `cli` |
| `opm-operator` | `cli` |
| `cli` | `catalog_opm`, `opm-operator` |
| `cascade-sandbox-up` | `cascade-sandbox-down` |

The `tag` input SHALL match `^opm-v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$` when the source is
`catalog_opm`, and `^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$` for every other source, or the
job SHALL fail before the token is minted.

#### Scenario: Unknown source

- **WHEN** a repo outside the map runs the `cascade-notify` action
- **THEN** the job fails with "not a cascade source" and mints no token

#### Scenario: Catalog tag shape

- **WHEN** `catalog_opm` calls it with `tag: v4.5.1`
- **THEN** the job fails before the mint because the tag lacks the `opm-` prefix

### Requirement: Dispatch payload

For each target the job SHALL send `POST /repos/open-platform-model/<target>/dispatches` with
exactly this body, built with `jq` and never by string interpolation:
`{"event_type":"upstream-released","client_payload":{"source":"<source>","tags":["<tag>"]}}`.
It SHALL try every target even after one fails, make up to 3 attempts per target with a 5 and then a 15 second
wait between them, write one summary line per target with its HTTP result, and fail the job when
any target still failed.

#### Scenario: Payload bytes

- **WHEN** `library` notifies with tag `v1.0.0-beta.4`
- **THEN** `opm-operator` and `cli` each receive `{"event_type":"upstream-released","client_payload":{"source":"library","tags":["v1.0.0-beta.4"]}}`

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
- **THEN** the job logs a warning and still dispatches to `opm-operator` and `cli`

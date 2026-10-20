## MODIFIED Requirements

### Requirement: A source outside the allowlist is dropped

A source outside `core`, `catalog_opm`, `library`, `opm-controller`, `cli` and the names in `CASCADE_EXTRA_SOURCES` SHALL be dropped with a warning, and its tags with it.

#### Scenario: Unknown source dropped

- **WHEN** `CASCADE_SOURCE` is `evil` and `CASCADE_TAGS` is `v1.0.0`
- **THEN** the section is `- None recorded (daily sweep or manual run).` and a warning names the dropped source

#### Scenario: The renamed repo as a source

- **WHEN** `CASCADE_SOURCE` is `opm-controller` and `CASCADE_TAGS` is `v1.0.0-beta.9`
- **THEN** the section is ``- `opm-controller` `v1.0.0-beta.9` `` and no warning names the source

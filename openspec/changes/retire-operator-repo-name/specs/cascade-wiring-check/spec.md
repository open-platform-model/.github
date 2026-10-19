## ADDED Requirements

### Requirement: Declared extra .github references

Each `extra-references` item SHALL add one expected `.github` reference of its kind in its file.
A `resolver` reference is a step whose `with.repository` ends in `/.github` in any case, or is an
expression. A `cite-lint` reference is a job whose `uses` is
`open-platform-model/.github/.github/workflows/cite-lint.yml` at the pinned SHA. A declared reference SHALL be held to the rules of the fixed references: the one full SHA
shared by every `.github` reference and the config's pin comment. A reference neither fixed nor
declared, and a declared one that is missing, SHALL fail `.github references` with exit 1.

#### Scenario: The controller module's dependency bot

- **WHEN** opm-controller's config lists `extra-references: [{file: module-deps.yml, kind: resolver}]` and `module-deps.yml` checks out `.github` at the same SHA with `# .github main`
- **THEN** the check passes

#### Scenario: The extra reference at another SHA

- **WHEN** the declared `module-deps.yml` checkout names a different SHA from the other references
- **THEN** the check exits 1 with `one .github SHA`

#### Scenario: An undeclared second resolver

- **WHEN** a workflow checks out `.github` and the config does not declare it
- **THEN** the check exits 1 with `.github references`

## REMOVED Requirements

### Requirement: Declared extra references

**Reason**: Retitled for the rename of opm-operator to opm-controller: a scenario named after the old repo is replaced, and OpenSpec 1.12 refuses a MODIFIED that drops one.

**Migration**: see the requirement that replaces it in this change.

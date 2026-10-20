## ADDED Requirements

### Requirement: A declared extra reference adds an expected reference

Each `extra-references` item SHALL add one expected `.github` reference of its kind in its file. A `resolver` reference SHALL be a step whose `with.repository` ends in `/.github` in any case, or is an expression. A `cite-lint` reference SHALL be a job whose `uses` is `open-platform-model/.github/.github/workflows/cite-lint.yml` at the pinned SHA.

#### Scenario: The controller module's dependency bot

- **WHEN** opm-controller's config lists `extra-references: [{file: module-deps.yml, kind: resolver}]` and `module-deps.yml` checks out `.github` at the same SHA with `# .github main`
- **THEN** the check passes

## REMOVED Requirements

### Requirement: A declared extra reference adds one expected reference

**Reason**: Retitled for the rename of opm-operator to opm-controller: a scenario named after the old repo is replaced, and OpenSpec refuses a MODIFIED that drops one.

**Migration**: see the requirement that replaces it in this change.

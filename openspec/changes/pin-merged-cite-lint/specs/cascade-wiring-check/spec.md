## MODIFIED Requirements

### Requirement: Per-repo wiring config

Each product repo's values SHALL live in `.tasks/cascade/wiring-check.yaml`, read as data and
never sourced, with exactly the keys `pin-comment` (words), `receiver` (boolean), `env-allow`
(list of upper-case variable names), `publish-workflows` (list of workflow file names, including
`release.yml`), `ci` (`workflow`, `job`), `notify` (`needs`, `if`, `tag`), for a receiver
only, `publish` (`labels-managed`, boolean), and optionally `extra-references` (a list of maps
with exactly the keys `file`, a workflow file name, and `kind`, whose value is `resolver` or `cite-lint`).
The check SHALL refuse, as a config error, an unknown key, a wrong type, a `publish-workflows`
list without `release.yml`, an `extra-references` item with another key, file name or kind, a
`resolver` item on a non-receiver, naming the same file and kind twice, or naming `release.yml`,
`deps-cascade.yml`, `cascade-gates.yml` or `cascade-task.yml` (files that hold a fixed
reference), and an
`env-allow` entry that is not `CUE_*`, `OPM_*`, `REGISTRY` or `IMAGE_NAME`: the names are allowed
rather than denied, because too many variables make a shell, git, gh, node, curl or the dynamic
loader run code, read other config or redirect traffic (`BASH_ENV`, `GIT_*`, `GH_*`, `NODE_*`,
`LD_*`, `XDG_*`, `SSL_*`, `CURL_*`, `*_PROXY` and more).

#### Scenario: Allow-list widened to a code-running variable

- **WHEN** a repo adds `BASH_ENV` to `env-allow` and to `release.yml`'s `env`
- **THEN** the check exits 2 naming the entry

#### Scenario: Allow-list widened to a proxy or a git hook directory

- **WHEN** a repo adds `HTTPS_PROXY` or `GIT_TEMPLATE_DIR` to `env-allow`
- **THEN** the check exits 2 naming the entry

#### Scenario: An extra reference of an unknown kind

- **WHEN** a repo lists `extra-references: [{file: module-deps.yml, kind: action}]`, or an item with a third key, or a `file` with a path
- **THEN** the check exits 2 naming the item

#### Scenario: An extra reference beside a fixed one

- **WHEN** a receiver lists `{file: cascade-task.yml, kind: resolver}` or `{file: release.yml, kind: resolver}`, lists `module-deps.yml` twice, or core lists a `resolver` item
- **THEN** the check exits 2 naming the item

### Requirement: Declared extra references

Each `extra-references` item SHALL add one expected `.github` reference of its kind in its file.
A `resolver` reference is a step whose `with.repository` ends in `/.github` in any case, or is an
expression. A `cite-lint` reference is a job whose `uses` is
`open-platform-model/.github/.github/workflows/cite-lint.yml` at the pinned SHA. A declared reference SHALL be held to the rules of the fixed references: the one full SHA
shared by every `.github` reference and the config's pin comment. A reference neither fixed nor
declared, and a declared one that is missing, SHALL fail `.github references` with exit 1.

#### Scenario: opm-operator's module dependency bot

- **WHEN** opm-operator's config lists `extra-references: [{file: module-deps.yml, kind: resolver}]` and `module-deps.yml` checks out `.github` at the same SHA with `# .github main`
- **THEN** the check passes

#### Scenario: The extra reference at another SHA

- **WHEN** the declared `module-deps.yml` checkout names a different SHA from the other references
- **THEN** the check exits 1 with `one .github SHA`

#### Scenario: An undeclared second resolver

- **WHEN** a workflow checks out `.github` and the config does not declare it
- **THEN** the check exits 1 with `.github references`

## ADDED Requirements

### Requirement: A cite-lint call is a plain call

Every job whose `uses` is `cite-lint.yml` of `open-platform-model/.github` (any case), in any workflow file and declared or not, SHALL hold only the keys `name`, `permissions`, `uses` and `with`. Its `permissions` SHALL be the map `contents: read` exactly, and its `with` SHALL hold only `paths` and `exclude`. No string of the job SHALL name the `secrets` context, `secrets: inherit` included. Anything else SHALL fail with exit 1 naming the file and job.

#### Scenario: A declared call at the pin
- **WHEN** a repo declares `{file: ci.yml, kind: cite-lint}` and `ci.yml` holds a job with `permissions: {contents: read}` and `uses: .../cite-lint.yml@<the pinned SHA> # <pin comment>`
- **THEN** the check passes, on core too

#### Scenario: A call that holds a write scope or a secret
- **WHEN** the calling job sets `contents: write`, adds another permission, omits `permissions`, sets `secrets: inherit` or passes `${{ secrets.X }}` in an input
- **THEN** the check exits 1 with `cite-lint.yml calls that break the plain-call rule`

#### Scenario: A call that sets the enh pin
- **WHEN** the call passes `enh-ref`
- **THEN** the check exits 1 with `cite-lint.yml calls that break the plain-call rule`

#### Scenario: A call at another SHA or without the comment
- **WHEN** the call names a SHA that differs from the other references, or lacks the pin comment
- **THEN** the check exits 1 with `one .github SHA` or `pin comment on`

### Requirement: A cite-lint call runs on a safe trigger

A workflow file that holds a job calling `cite-lint.yml` SHALL NOT trigger on `pull_request_target` or `workflow_run`, in a map, list or string form of `on`, because those events run in the base repository context. The check SHALL fail with exit 1 naming the file and trigger.

#### Scenario: A base-context trigger
- **WHEN** the file with the call also triggers on `pull_request_target`
- **THEN** the check exits 1 with `cite-lint.yml calls that break the plain-call rule`

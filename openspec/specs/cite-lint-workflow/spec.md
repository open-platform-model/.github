# cite-lint-workflow Specification

## Purpose
The shared workflow that checks the Go and CUE comments of a repo against the comment rule of the enhancement format, with one pinned `enh` version for every repo that calls it.

## Requirements

### Requirement: Reusable call-only workflow

`.github/workflows/cite-lint.yml` SHALL be a reusable workflow whose only trigger is `workflow_call`. It SHALL declare no `secrets` input and no job in an Environment, and SHALL read no secret.

#### Scenario: Trigger and secrets
- **WHEN** the workflow file is read
- **THEN** `on` holds the key `workflow_call` and no other key
- **AND** `on.workflow_call.secrets` is absent and no step names the `secrets` context

### Requirement: Typed inputs with defaults

The workflow SHALL take three optional string inputs: `paths` (default `.`), `exclude` (default empty) and `enh-ref` (default a full 40-hex commit SHA). `paths` and `exclude` SHALL hold one item per line.

#### Scenario: A caller passes nothing
- **WHEN** a caller passes no input
- **THEN** the lint runs on the whole repo with no exclude pattern at the default `enh-ref`

### Requirement: One pinned enh commit

The workflow SHALL build `enh` from `tools/enh` of `open-platform-model/enhancements` at the commit in `enh-ref`, and SHALL refuse a value that is not 40 lowercase hex characters before any checkout. The default of `enh-ref` SHALL be the only place in this repo that holds the pin, and SHALL be a commit of the `main` branch of `enhancements` that carries the merged tool. The tool's own `go.mod` SHALL decide the Go version, which `actions/setup-go` installs; the job SHALL NOT download a toolchain.

#### Scenario: A branch name is passed
- **WHEN** `enh-ref` is `main`
- **THEN** the job fails with an error naming the rule
- **AND** no checkout of `open-platform-model/enhancements` runs

#### Scenario: A bump
- **WHEN** the default of `enh-ref` changes in a commit of this repo
- **THEN** every caller that pins `.github` at that commit uses the new `enh` commit, and no other file changes

### Requirement: Input paths stay inside the repo

The workflow SHALL fail on a `paths` item that is absolute, starts with `-`, or holds a `..` path segment. It SHALL pass each `exclude` item as one `--exclude=<item>` argument and the paths after `--`.

#### Scenario: A path leaves the repo
- **WHEN** `paths` holds `../other`
- **THEN** the job fails before the lint runs

#### Scenario: An exclude item looks like a flag
- **WHEN** `exclude` holds `--root=/etc`
- **THEN** the tool receives it as the pattern value of one `--exclude=` argument and lints the repo root unchanged

### Requirement: Findings fail the job

The workflow SHALL run `enh cite-lint` with `--root` set to the checkout of the calling repo and SHALL fail when the tool exits non-zero. The tool prints each finding as `path:line: rule: message`.

#### Scenario: A decision number in a comment
- **WHEN** a Go comment in the calling repo holds a decision number or a lone id
- **THEN** the job fails and the log lists the finding with its path and line

#### Scenario: A clean repo
- **WHEN** no Go or CUE comment breaks the rule
- **THEN** the job succeeds

### Requirement: The repo under test is data

The workflow SHALL only read the calling repo: it SHALL run no file of it, and SHALL check the tool out beside the repo, not inside it, so the lint never reads the tool's files.

#### Scenario: A fork pull request
- **WHEN** a pull request from a fork calls the workflow
- **THEN** no code of the fork runs and the job holds only a read-only token

### Requirement: Least privilege and pins

The workflow SHALL set `permissions: {}` at the top and `contents: read` on its job, SHALL set `timeout-minutes` on the job, and SHALL pin every `uses:` to a full commit SHA with a version comment. It SHALL keep no expression inside a `run:` block.

#### Scenario: Static check
- **WHEN** the wiring test suite runs
- **THEN** it checks each of these properties of `cite-lint.yml` and passes

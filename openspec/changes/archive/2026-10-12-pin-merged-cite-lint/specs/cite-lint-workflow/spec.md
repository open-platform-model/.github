## MODIFIED Requirements

### Requirement: One pinned enh commit

The workflow SHALL build `enh` from `tools/enh` of `open-platform-model/enhancements` at the commit in `enh-ref`, and SHALL refuse a value that is not 40 lowercase hex characters before any checkout. The default of `enh-ref` SHALL be the only place in this repo that holds the pin, and SHALL be a commit of the `main` branch of `enhancements` that carries the merged tool. The tool's own `go.mod` SHALL decide the Go version, which `actions/setup-go` installs; the job SHALL NOT download a toolchain.

#### Scenario: A branch name is passed
- **WHEN** `enh-ref` is `main`
- **THEN** the job fails with an error naming the rule
- **AND** no checkout of `open-platform-model/enhancements` runs

#### Scenario: A bump
- **WHEN** the default of `enh-ref` changes in a commit of this repo
- **THEN** every caller that pins `.github` at that commit uses the new `enh` commit, and no other file changes

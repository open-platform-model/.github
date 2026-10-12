## Why

Each product repo will call `cite-lint.yml` from its CI. Two things block that. The default `enh-ref` of the workflow names the head of an old, unmerged branch of `enhancements`, which lacks the tightened lint. And the wiring check, kept as a byte-identical copy in core, library, catalog_opm, cli and opm-operator, accepts only the cascade `.github` references and a `resolver` kind, so a repo that adds the call fails its own check.

## What Changes

- `cite-lint.yml`: the default of `enh-ref` becomes the `main` commit of `enhancements` that carries the merged tool (`e0335b2ec44e659c0191bc3523d79d17f26f8e7d`). The comments no longer say the pin is on an unmerged branch.
- `wiring-check.sh`: a second `extra-references` kind, `cite-lint`. It declares a job that calls `cite-lint.yml`. The call is pinned by the same single `.github` SHA and pin comment as every other reference. The job holds no secret and no write permission; the check refuses one that does. A `resolver` stays receiver-only; `cite-lint` is allowed in every repo, core included.
- Test cases for the accepted call and each refusal; `README.md` says how a repo declares the kind.

## Capabilities

### New Capabilities

### Modified Capabilities
- `cite-lint-workflow`: the default pin is a commit of `main`.
- `cascade-wiring-check`: the `extra-references` config accepts the kind `cite-lint`, and a declared call is held to a plain-call rule.

## Impact

- Files: `.github/workflows/cite-lint.yml`, `.github/scripts/cascade/wiring-check.sh`, `.github/scripts/cascade/wiring/test/cases/wiringcheck.sh`, `README.md`.
- Callers: none yet. The five product repos copy the new `wiring-check.sh` in stage 2, one change per repo; each copy MUST be byte for byte this merged file.
- Go for the tool: `go.mod` of `enh` at the pin says `go 1.26.9` with no `toolchain` line. `actions/setup-go` reads it, installs that version, and `GOTOOLCHAIN: local` finds it. No job change is needed.
- Depends on: nothing. Later: the stage-2 changes in core, library, catalog_opm, cli and opm-operator.
- No ruleset or setting change.

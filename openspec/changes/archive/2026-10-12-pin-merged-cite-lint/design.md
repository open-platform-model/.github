## Context

The wiring check already holds every `.github` reference to one full SHA and the repo's pin comment (section "The pin" of the script). A call of a reusable workflow is a job-level `uses:`, which the reference scan already lists. The missing parts are a way to declare it and a rule about what the calling job may hold.

## Decisions

### D1: One new kind under `extra-references`

The kind `cite-lint` joins `resolver`. Its expected reference is `<file> open-platform-model/.github/.github/workflows/cite-lint.yml`. Reason: the file and kind keys, the duplicate rule and the fixed-file refusal already exist; no new config key means old configs stay valid. Reversible: cheap.

### D2: Pin rules are the existing ones

The call shares the single SHA and the pin comment of the other references; no separate pin. Reason: the five copies of the check come from one `.github` commit and a repo bumps its `.github` pin as one unit, so a cite-lint SHA that differs from the cascade SHA would only hide drift. Whoever bumps the pin bumps the call.

### D3: The calling job is a plain call

Per `cite-lint.yml` job in any workflow file, declared or not:
- keys only `name`, `permissions`, `uses`, `with`;
- `permissions` is the map `{contents: read}` exactly, so the job holds no write scope (a called workflow cannot widen its caller's grant);
- `with` keys only `paths` and `exclude`: the `enh` pin lives in the callee, a caller never passes `enh-ref`;
- no string anywhere in the job names `secrets` in any case (this covers `secrets: inherit` and a `secrets.X` input value);
- the file does not trigger on `pull_request_target` or `workflow_run`, which run in the base repository context.

Reason: the callee reads the repo and runs none of its code, so the safe caller is one that cannot give it anything else. A rule on the whole file's trigger costs a CI workflow nothing: `ci.yml` runs on `pull_request`.

### D4: `resolver` stays receiver-only

The receiver check moves from the whole `extra-references` list to the `resolver` kind. Core, which is no receiver, can declare `cite-lint`.

## Risks

- A repo wanting a job `if:` or `needs:` on the call is refused. Accepted: a required lint that can be skipped is the thing the key rule prevents. Widen by a later change if a repo needs it.
- The check scans all workflow files for the call, so an undeclared call fails `.github references` as any undeclared reference does.
- `go 1.26.9` must exist for `setup-go` to install. Not verified here (no network from the sandbox); the first caller run proves it.

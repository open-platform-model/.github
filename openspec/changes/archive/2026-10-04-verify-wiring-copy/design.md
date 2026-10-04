## Context

`wiring-check.sh` runs from each product repo's tree (`bash .tasks/cascade/wiring-check.sh
--pin-on-main` in the required CI job). Its pin check asks the `compare` API that the one `.github`
SHA is on `main`. Copies are kept identical by the pin-bump procedure and review only.

## Goals / Non-Goals

Goals: CI refuses a copy that is not the file at the pinned SHA; a repo can declare a known extra
resolver checkout without weakening the one-SHA rule; an operator knows what to do when the API
call fails.

Non-goals: making the self-comparison tamper-proof (see D1), supporting extra `uses:` references,
changing any product repo.

## Decisions

### D1: The running script compares itself with the pinned file

With `--pin-on-main`, after the `compare` check passed, the check MUST request

```
gh api -H 'Accept: application/vnd.github.raw' \
  repos/open-platform-model/.github/contents/.github/scripts/cascade/wiring-check.sh?ref=<sha>
```

(through `${CASCADE_GH:-gh}`, with the step's `GH_TOKEN`) into a temp file and `cmp` it with
`${BASH_SOURCE[0]}`, the file bash is running. A failed request MUST print `cannot fetch
.github/scripts/cascade/wiring-check.sh at .github <sha>` and exit 1; a difference MUST print
`<path> differs from .github/scripts/cascade/wiring-check.sh at .github <sha>` and exit 1. The
raw media type returns the blob bytes unchanged (checked against 7b9ad1b: `cmp` equal to `git
show`). The request runs only after the shapes and `compare` passed, so a fork-only SHA is never
fetched and a shape failure makes no request.

Without the flag the check makes no request and prints, after the ok line, `cascade wiring: the
copy was not compared with .github <sha> (offline; --pin-on-main compares it)`. The ok line stays
first and unchanged, so the README's "printed `cascade wiring: ok, …`" instructions still hold.

Limit, stated in the README: the comparison runs from the copy under test, so it catches drift
and stale copies but does not replace review. An edited copy passes when the same PR also deletes
the comparison, or changes what runs around the CI step: a workflow or job `env` with `BASH_ENV`
(a sourced file that redefines `cmp`) or `CASCADE_GH` (a fake gh that returns the running copy),
an earlier step that writes either to `GITHUB_ENV`, or a process left behind that swaps the file
after bash opened it. The CI shape rule refuses those routes (D5); an earlier SHA-pinned action
can still write `GITHUB_ENV` or `GITHUB_PATH`, so any change to the CI workflow is reviewed as a
change to the check.
CODEOWNERS on `/.tasks/` and the `main` ruleset (owner decision 28) remain the guard against a
deliberate edit. Running the canonical file fetched by the CI step instead of the copy was
considered and rejected here: the CI step's shape is itself enforced by the copy, so it moves the
same trust one file over, and it would change the CI step in five repos.

### D2: `extra-references`, kind `resolver` only

Config key `extra-references` (optional; absent means `[]`): a list of maps with exactly the keys
`file` (a workflow file name, `^[A-Za-z0-9._-]+\.ya?ml$`) and `kind`. The only kind is `resolver`:
a step whose `with.repository` is any owner's `.github` in any case, or an expression (D3). Each entry adds one
`<file> resolver` to the expected reference list, so a declared reference is held to the same
rules as the fixed ones: the one SHA across all references and the pin comment. One entry per
reference; a missing or surplus reference fails `.github references`. Any other type, item key or
kind is a config error (exit 2). After review the key was narrowed to its one use: only a
receiver may set it, a file may be named once, and never a file that holds a fixed reference
(`release.yml`, `deps-cascade.yml`, `cascade-gates.yml`, `cascade-task.yml`), so it cannot admit
a second resolver beside the fixed one or a checkout inside a key-holding workflow.

`uses:` kinds (an extra action or reusable-workflow call) are not offered: the key-holding jobs
are the only callers of the cascade actions, and every reader of the App key is already pinned to
those jobs. A new kind is a `.github` change.

opm-operator's value: `extra-references: [{file: module-deps.yml, kind: resolver}]` (its
`main` has `module-deps.yml` job `compute`, step "Clone the cascade resolver", with
`repository: open-platform-model/.github`, `ref: <sha> # .github main`, `path: org-github`,
`persist-credentials: false`).

### D3: A resolver checkout passes no credentials

Every resolver checkout, fixed or declared, MUST use `actions/checkout@<40 hex>` and have exactly
the `with` keys `path`, `persist-credentials`, `ref`, `repository`, with `persist-credentials`
the boolean `false`. That refuses `token`, `ssh-key` and `github-server-url`, so no secret
reaches a `.github` checkout. All four receivers' `cascade-task.yml` and opm-operator's
`module-deps.yml` on `main` already have this shape.

After review, a `.github` checkout is any step whose `with.repository` ends in `/.github` (any
owner, any case) or is an expression, since `${{ github.repository_owner }}/.github` with a
token passed the literal match; such a step also counts as a `resolver` reference. An
expression-valued `repository` on any step, and a `run:` step that names
`open-platform-model/.github` (or `}}` or `repository_owner` followed by `/.github`), fail
outright: no repo uses either.

### D4: Runbook for a failed API call

Both requests are needed for the required job, so an API outage, a secondary rate limit or a
`GITHUB_TOKEN` hourly limit fails it with `cannot compare` or `cannot fetch`. The README runbook:
re-run the failed job; check GitHub status and `gh api rate_limit`; if the failure persists, an
admin MAY merge with `gh pr merge --admin` only a PR whose changed files include nothing under
`.github/**` or `.tasks/**`, after every other required check passed and the offline
`task cascade:wiring:check` passed on the PR head; never remove `--pin-on-main` from the step or
edit the copy to skip a request. `not on .github main` and `differs from` are findings, never
outages, and never bypassed.

### D5: Nothing reaches the CI wiring step from around it

Added after review. In the config's CI workflow and job: `env` (workflow and job) is absent or a
plain map whose names match the fixed env-allow pattern (`CUE_*`, `OPM_*`, `REGISTRY`,
`IMAGE_NAME`), not the repo's `env-allow` list, since library and cli set `CUE_REGISTRY` and
`OPM_REGISTRY` there with an empty list; the job has no `container` or `services` (a service can
mount the workspace); and every step before the wiring step is `uses:` of another repo's action
at a full SHA (`owner/repo[/path]@<40 hex>`) with only `id`, `name`, `uses` and `with`. A `run:`
step, a local action, a tag ref, or a step `env`, `if` or `shell` before it fails. Steps after
it are free. Under `--pin-on-main` the script also exits 1 when `BASH_ENV` or `ENV` is set; that
is a tripwire, since bash sources `BASH_ENV` before the script runs and that file can unset it.
`CASCADE_GH` stays (the tests use it); the env rule keeps it out of CI.

core, library and cli `main` pass. catalog_opm `main` runs a step before the wiring step that
writes `OPM_CLI_VERSION` to `GITHUB_ENV`, so its re-pin PR moves the wiring step above it.

## Risks / Trade-offs

- One more API request per CI run; the job's token allows 1000 requests an hour per repo.
- Until a repo bumps its pin to a commit with this change, its copy has no comparison.

## Context

`.github` holds org-wide workflows other repos reference by SHA. `cascade-gates.yml` and `cascade-receive.yml` are the existing reusable workflows: `workflow_call` only, typed inputs, `permissions: {}` at the top, least privilege per job. `mention-guard.yml` is a different shape: a plain `pull_request` workflow that an org ruleset requires. The wiring test suite (`.github/scripts/cascade/wiring/test/cases/static.sh`) holds the cascade reusable workflows to a fixed list of static rules.

`enh` is a Go program in `tools/enh` of `open-platform-model/enhancements`, its own module (`github.com/open-platform-model/enhancements/tools/enh`) with a `go.sum`. `enh cite-lint [flags] [PATH ...]` takes `--root`, `--exclude` (repeatable) and `--files-from`; it exits 0 when clean, 1 on findings and 2 on a usage error. Read at the default pin, commit `6c0c338dcc59747c83adf876313ffcab1276d184` (`tools/enh/cmd/table.go`, `tools/enh/internal/citelint/citelint.go`).

## Goals / Non-Goals

**Goals:**
- Any repo runs `enh cite-lint` in its CI with one `uses:` job and no tool setup of its own.
- One file in this repo holds the `enh` pin.
- The workflow has no secret, a read-only token, and runs no code of the repo under test.

**Non-Goals:**
- Making the lint a required check of any repo or of the org (an owner ruleset step, later).
- Any caller. The per-repo changes add them.
- Changing `wiring-check.sh` (see Risks).

## Research & Decisions

### D1. Check out the tool and build it, instead of `go run <module>@<commit>`

Options: (a) `go run github.com/open-platform-model/enhancements/tools/enh@<sha>`; (b) a second `actions/checkout` of `enhancements` at the SHA, then `go build` in `tools/enh`.

Chosen: (b). Git verifies the commit object, so the tool is exactly the pinned tree and no module proxy sits between. The default pin is a commit on an unmerged branch; a proxy resolves a commit only through refs it can see, while a checkout fetches any commit of the repo by SHA. The Go version comes from the tool's own `go.mod` through `actions/setup-go` `go-version-file`. Cost: one more `uses:` line and about one minute of build. The tool's dependencies stay checked by its `go.sum` and the Go checksum database (`GOFLAGS=-mod=readonly`, `GOTOOLCHAIN=local`).

### D2. Inputs: `paths`, `exclude`, `enh-ref`

Strings only, because `workflow_call` has no list type. `paths` and `exclude` hold one item per line. The caller states the paths, since repos differ (`vendor/` and `.git` are already skipped by the tool, so the default excludes nothing). `enh-ref` has a default so no caller names the pin; a caller may override it to test a newer tool, and the value must be a 40-hex SHA (a branch or tag name is mutable and is refused).

### D3. Inputs reach the shell only through `env:`

`inputs.*` of a reusable workflow are untrusted when a caller passes untrusted data. The first step reads them from `env`, checks them, and writes the tool arguments to `$RUNNER_TEMP/cite-lint.args` as NUL-separated words: the `--exclude=<item>` flags, then `--`, then the paths. The last step reads that file with `mapfile -d ''`. One check, no second parse, and a pattern or path that starts with `-` cannot become a flag. `enh-ref` is also used as `ref:` of the checkout (a `with:` value, not shell text), after the check.

### D4. No Guard or Own-commit step

The cascade workflows derive a repo name and check scripts out of `.github` at their own commit. This workflow does neither: it holds no script of this repo and needs no repo name. The static cases for the cascade workflows (Guard first, same Guard text, Own commit) stay as they are and do not apply; a separate block of cases covers `cite-lint.yml` (D7).

### D5. No cache

`actions/setup-go` runs with `cache: false`. The build is short, and a restored cache is a way into the tool binary.

### D6. Reusable workflow, not a direct `pull_request` workflow

`mention-guard` follows the second pattern because the org requires it. Making cite-lint org-required is an owner ruleset decision for later. A reusable workflow lets each repo choose its paths and excludes, and the owner can still require the caller job by name.

### D7. A case file in the wiring test suite

`static.sh` lists its reusable workflows by name and holds cascade-only rules. The cases for `cite-lint.yml` are a new file, `cases/citelint.sh`, named in the `files=` list of `run.sh`. It checks: only `workflow_call`; no `secrets` input; no Environment; no `secrets.` text; `permissions` explicit on every job; every `uses:` a full SHA with a version comment; no expression inside `run:`; `timeout-minutes` set; and that the `enh-ref` default is 40-hex. It also runs the `Check inputs` and `Lint` steps on their own, the second with a stub `enh` that prints its arguments. It repeats none of the cascade-only rules.

### Network requests

| Host | What | On failure |
| --- | --- | --- |
| `github.com` | `actions/checkout` fetches the calling repo and `open-platform-model/enhancements` at the SHA | the step fails, the job is red |
| `go.dev` / the Go release feed | `actions/setup-go` downloads the Go version named in the tool's `go.mod` | the step fails |
| `proxy.golang.org`, `sum.golang.org` | `go build` downloads the tool's dependencies and checks them | the step fails |

No retry is added: a red job is re-run by hand. The job sends no secret to any host.

## Risks / Trade-offs

- [`openspec validate --all --strict` fails today] Nine existing main specs have a requirement text over 500 characters, which CLI 1.14.1 flags in strict mode; they fail on `main` too and this change does not touch them. → The checks of this change are `validate add-cite-lint-workflow --strict` and `validate --all`; rewriting the nine specs is a separate change.
- [`wiring-check.sh` rejects a caller] The canonical `wiring-check.sh` (copied into core, library, catalog_opm, cli, opm-operator) compares every `open-platform-model/.github` reference of a repo with a fixed list, and its README says a new kind of reference is a change to the script. A caller of `cite-lint.yml` therefore fails that check in those five repos. → A separate change to `wiring-check.sh`, its tests and the README adds the kind; it must merge before the callers. Raised in the task report, not done here.
- [The default pin is a commit of an unmerged branch] If that branch is deleted or its history rewritten, the checkout fails. → The programme moves the pin to the merged `main` commit before any caller merges; the comment at the pin says so.
- [`enhancements` becomes private] The default token has no access to another private repo, so the tool checkout fails. → Not planned; a token input would be a new decision.
- [A cold build takes time] About one minute without a cache. → `timeout-minutes: 10`.
- [A fork pull request reads attacker files] The files are only read by `enh`, a Go program that lexes comments. A parser fault in the pinned tool is the only route. → Accepted; the job has no secret and a read-only token.

## Open Questions

None that change the specs or the tasks.

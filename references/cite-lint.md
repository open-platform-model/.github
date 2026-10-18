# cite-lint: the shared comment-rule check

Covers what the `cite-lint` reusable workflow checks, its inputs, where its tool pin lives and how a
repo calls and declares it. The workflow is in `.github/workflows/`. The citation form itself is in
the workspace `references/enhancements.md`.

## What it checks

The workflow runs `enh cite-lint` on the Go and CUE comments of the repo that calls it. The rule: a
comment names an enhancement id only beside a reason in words, as in `(enhancement NNNN)`. It never
holds a decision number, also not in a string literal, and never holds only an id. A finding fails
the job, and the log lists it as `path:line: rule: message`.

The workflow is `workflow_call` only. It has no secret, `permissions: {}` at the top and
`contents: read` on its one job. It reads the calling repo and runs no file of it, so a pull request
from a fork is safe. It builds `enh` from `tools/enh` of the `enhancements` repo at one commit.

| Input | Default | Meaning |
| --- | --- | --- |
| `paths` | `.` | Paths to lint, one per line, relative to the repo root. Go and CUE files only. |
| `exclude` | none | Path patterns to skip, one per line. The tool already skips `.git`, `node_modules`, `vendor` and `.cue-cache`. |
| `enh-ref` | the pin | Full 40-hex commit of `enhancements`. A branch or tag name fails the job. |

## The pin

The default of `enh-ref` in the workflow is the only place that holds the `enh` commit, so every
repo checks comments with the same tool. A caller never passes `enh-ref`. To move the pin, change the
default in the workflow. A repo gets the new commit when it bumps its `.github` pin. The default is
a commit on `main` of `enhancements` that carries the merged tool. Move it only to a later commit of
`main`. The tool's `go.mod` sets the Go version and `actions/setup-go` installs it, so the job needs
no toolchain download.

## How a repo calls it

Pin the workflow by full SHA with the comment `.github main`, as for the cascade workflows. Call it
on `pull_request` or `push`. The caller job grants `contents: read`.

```yaml
name: Cite lint
on:
  pull_request:
permissions: {}
jobs:
  cite-lint:
    name: Cite lint
    permissions:
      contents: read
    uses: open-platform-model/.github/.github/workflows/cite-lint.yml@<sha> # .github main
    with:
      paths: |
        cmd
        internal
      exclude: |
        testdata/
```

## Declaring the call for the wiring check

A repo that runs the wiring check lists the file that holds the call in `extra-references` of its
wiring-check config in `.tasks/cascade/`. Core lists it too.

```yaml
extra-references:
  - {file: ci.yml, kind: cite-lint}
```

The check then holds the call to the same rules as the other references: the one `.github` SHA and
the pin comment of the repo. It also refuses a call that is not plain. The job has only the keys
`name`, `permissions`, `uses` and `with`. Its `permissions` are exactly `contents: read`. It passes
only `paths` and `exclude`, never `enh-ref`. No string of the job names `secrets`. The file does not
trigger on `pull_request_target` or `workflow_run`. A call that is not declared fails the check like
any other undeclared reference.

Nothing requires the check yet. Making it required is an owner ruleset step.

## Pitfalls

- Passing `enh-ref` from a caller: the wiring check refuses it. Move the default here.
- Pinning the tool to a branch or a tag: the job fails. Use a full commit on `main` of `enhancements`.
- A caller that triggers on `pull_request_target`: the wiring check refuses the file.
- Adding a path filter to a call you want required: a filtered required check never reports on other PRs.

## Check before you finish

- [ ] The workflow still has no secret and `contents: read` on its one job.
- [ ] The `enh` pin is a full commit that is on `main` of `enhancements`.
- [ ] A new caller input is documented in the table above and in the wiring check's plain-call rule.
- [ ] The offline test suites pass.

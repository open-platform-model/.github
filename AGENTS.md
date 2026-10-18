# open-platform-model/.github

The org meta repo. It holds the workflow that the org ruleset requires on every pull request
(`mention-guard`), a daily release-tag drift check (`tag-ledger`), a shared comment lint
(`cite-lint`) and the code of the release cascade. It has no Go module, no Taskfile and no
release-please: nothing here is released or versioned. The cross-repo release design is in the
workspace `RELEASING.md`.

## Branches

- `main` is the only long-lived code branch. Every change lands by pull request, squash only, and
  the PR branch is deleted on merge. Other repos read this repo at `main` (the org ruleset reads
  `mention-guard` by path) or at a full SHA of a `main` commit (the cascade and `cite-lint`). So a
  broken merge here breaks every repo.
- `tag-ledger` is a data branch. The daily job appends the tag ledger to it with plain pushes. No
  code lands on it. A hand edit of a ledger row is a finding of the next run.
- A reviewed tag drift is acknowledged on `main`, never on `tag-ledger`. Reason: the ledger branch
  takes pushes from the job's own token, so a row there could silence a finding with no review.

## Rules

- Every workflow sets `permissions:` per workflow or job, starting from `{}` or `contents: read`,
  and widens only with a comment that names why. Reason: a stolen token does least harm.
- Third-party actions are pinned to a full commit SHA with the tag in a comment. Checkouts use
  `persist-credentials: false` unless the job pushes. A script never sends a token to a host that
  does not need it.
- Scripts are bash with `set -euo pipefail`, a helper that writes the error to stderr and exits, and a clean
  `shellcheck`. Tools beyond coreutils are named in the script header and checked at start. Exit
  codes are part of the interface and are documented in the header.
- Network access goes through one wrapper per script, so a test can replace it with a PATH shim that
  answers from fixture files. No required test needs the network. A live check is a separate,
  non-required workflow.
- A check that a ruleset requires has no path filter. Reason: a filtered required check never
  reports on other PRs and blocks them.
- Nothing may break `mention-guard` or `tag-ledger`. A change to `mention-guard` applies to the whole
  org at merge.
- Callers pin the cascade by full SHA, and the pin moves by the rollout procedure, never by
  Dependabot. This repo's Dependabot config therefore ignores `open-platform-model/.github*`.
- Callers keep a byte-identical copy of the wiring-check script. Change the check here and move the
  pin. Never edit a copy.
- Tests in `.github/scripts/cascade/wiring/test/` read the caller shapes and the wiring check's CI
  step from the cascade files in `references/`. Those files keep the bold lead-in line and the
  fenced block of each shape for that reason.
- The `openspec/config.yaml` rules and principles also bind every change. A change is a set of
  mergeable sections, one PR per change, one commit per section.

## Layout

```text
.github/workflows/       mention-guard, tag-ledger, cite-lint and the cascade workflows with their test and drift workflows
.github/actions/         the two composite cascade actions: notify and publish
.github/scripts/         tag-ledger and ledger-integrity scripts
.github/scripts/cascade/ the resolver, its tests and the wiring check
.github/scripts/cascade/wiring/ scripts of the cascade workflows, their shared maps and their tests
tag-ledger/              acknowledged tag drift, one row per accepted state
openspec/                OpenSpec specs, changes and the rules for writing them
references/              one file per topic: mention-guard, tag-ledger, cite-lint, the cascade
.claude/skills/          the OpenSpec skills
```

The `.github/` folder also holds `CODEOWNERS`, the Dependabot config and the actionlint config.

## Commands

There is no Taskfile. Run these from the repo root before you push. CI runs the first three.

| Command | What it does | When |
| --- | --- | --- |
| `shellcheck` on every `*.sh` under `.github/scripts/` | Lints the scripts and the test shims | Any script change |
| `actionlint .github/workflows/*.yml` | Lints the workflows | Any workflow change |
| `bash` on each `test/run.sh` under `.github/scripts/` | Runs the offline suites (the resolver, and the workflow scripts with the wiring check) | Any change under `.github/scripts/`, any change to a cascade reference file |
| `openspec validate --all --strict` | Validates specs and changes | Any change under `openspec/` |

The wiring suite needs `task` (go-task), `yq`, `jq` and `git`.

## Style

Prose follows the workspace `STYLE.md`. A commit is `type(scope): lowercase subject`. This repo does
not release, so the type is descriptive: `feat` for behavior other repos call, `fix`, `ci` for
workflow-only work, `test`, `docs`, `chore`. Scopes in use: `cascade`, `cite-lint`, `mention-guard`,
`tag-ledger`, `openspec`.

@CONTEXT.md

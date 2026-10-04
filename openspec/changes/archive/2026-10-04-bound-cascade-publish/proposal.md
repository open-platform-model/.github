## Why

The release-cascade security pass of 2026-10-04 (supervisor plan, change W1-gh) found that
`publish`, the boundary the cascade design relies on, re-derives the plan's title shape, its
labels and its workflow paths, but not *which files* the bot's commits change, *who* made them,
or the PR text above the Notes marker. `compute` runs repo code (the receiver's task on `main`
merged with `deps/cascade`, and in cli and opm-operator also new dependency code), so a hostile
`compute` can today:

- push a bot-attributed `fix(deps)` commit that also edits `Taskfile.yml`, `.tasks/**`, release
  configs or any other non-workflow file, under a routine title (findings RC-1, PUB-1, CAS-R2);
- drop `need-human-review` and `deps-cascade:breaking` from a new PR, and write any text above
  the Notes marker (RC-1, PUB-2);
- in merge mode, run the `deps/cascade` branch tip's own `Taskfile.yml` and `.tasks/` on a
  `main`-ref run (missed finding of the receive review);
- force-push over human commits on `deps/cascade` with a forged mode (PUB-4).

Three smaller gaps sit beside it: a dispatch tag with a trailing newline passes the payload check
(RC-2); `compute` installs Task as `3.x` and CUE with no checksum (RC-4); and the resolver
proposes any tag the Go proxy or `git ls-remote` lists, so a tag forged with the release App key
on an unmerged commit would become a cascade PR (missed finding of the repo review). The org
governance changes (owner decisions 28 to 31) also need two things from this repo: a wiring-check
rule that the release key is read only under `environment: release`, and CODEOWNERS plus a
SHA-pinned `mention-guard` here.

## What Changes

- **Publish bounds the bot's increment.** `receive-publish.sh verify` computes the commits the
  push adds (the new tip's commits that neither `main` nor, for a fast-forward of the old tip as
  in merge mode, the old tip has) and refuses the plan unless every commit is authored and committed
  by `BOT_EMAIL`, there are at most two, each non-merge commit changes only paths on a
  per-receiver allow-list held in `wiring/lib.sh` (never in the receiver's tree), with status
  `M`, no mode change and no symlink or gitlink, and each merge commit's tree equals
  `git merge-tree --write-tree` of its parents except for derived paths that carry `main`'s
  content. A deny-list always wins over the allow-list: `.github/**`, `.tasks/**`, `Taskfile*`,
  `hack/**` (but cli's two hack data files), `*.sh`, `CODEOWNERS`, the release-please files,
  `.cascade-frozen` and `.cascade-hold`.
- **Publish never drops human commits.** A push that does not contain the old remote tip is
  refused when `origin/main..old` holds a commit the bot did not make; `close` keeps such a
  branch instead of deleting it. `recreate` stays exempt (the plan's item 9).
- **Publish renders the PR text and labels itself.** `.github` holds a mirror of each
  receiver's `pins.sh` and `classes` (`wiring/lib.sh`, run through `wiring/pins.sh`). Verify
  checks the new tip out into a scratch worktree and runs the resolver's own `title` and `body`
  there with those mirrors, the dispatch payload read from the event (not from `compute`), the
  live PR's Notes, and `compute`'s warnings filtered line by line. The final title, the body and
  the labels come from that run: `need-human-review` from the mirrored pin labels, and
  `deps-cascade:breaking` from the mirrored pins and the upstream releases verify reads itself.
  `compute`'s `body.md` and titles are hints only; act never removes `need-human-review` or
  `deps-cascade:breaking`.
- **Merge mode runs `main`'s task.** Before the task runs on a merged branch, `compute` puts
  `origin/main`'s `.tasks/` and `Taskfile*` in the work tree, runs the task with
  `CASCADE_ALLOW_DIRTY=1`, and commits everything but those paths.
- **Payload tags with control characters are refused.** `validate_payload` checks each tag
  NUL-delimited with the anchored bash match and refuses any control character in `source` or a
  tag.
- **Pinned tools.** `compute` installs Task v3.53.1 and CUE from fixed release URLs and checks
  each archive's sha256 against a table in `.github` (`wiring/install-tools.sh`); a `cue-version`
  with no table entry fails.
- **The resolver refuses a tag that is not on its repo's `main`.** For a pin whose versions are
  tags of an org repo (`go github.com/open-platform-model/<repo>`, `release`, `opm-cli`, and the
  `cue` modules `opmodel.dev/core` and `opmodel.dev/catalogs/opm`), `newest` skips, with a
  warning, a published candidate whose tag commit is not reachable from that repo's `main`. It
  learns this with a tree-less clone of the repo through the same isolated git as `ls-remote`
  (no credentials, no `api.github.com`).
- **Wiring check: the release key needs `environment: release`.** Every job that reads
  `RELEASE_APP_PRIVATE_KEY` (any case, any `secrets` form, or `secrets: inherit`) declares
  `environment: release`, and only those jobs do.
- **This repo:** `.github/CODEOWNERS`; `mention-guard.yml` runs `actions/github-script` at a
  full SHA; every workflow already declares `permissions:`, and a static case keeps it so.
- **Residual risk, written down:** G2 still runs release-head code inside a `main`-ref run; the
  cache sink is closed by the publish-workflows rule; the `.github` mirrors must follow a
  receiver's `pins.sh` and `classes`.

Not in this change: the receivers' pin bumps and copies of the wiring check (wave 2), rulesets,
repo settings and secrets (supervisor and owner), the per-repo workflow hardening (the
`harden-release-workflows` changes), moving G2 out of a `main`-ref run.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cascade-receive`: publish bounds the increment, derives title, body and labels with `.github`
  code, keeps human commits, and validates payload tags without control characters; merge mode
  runs `main`'s task.
- `cascade-resolver`: `newest` refuses a tag not reachable from its repo's `main`.
- `cascade-workflows`: compute installs Task and CUE from pinned, checksummed archives; every
  workflow of this repo declares permissions and pins its actions.
- `cascade-wiring-check`: the release-key rule.
- `cascade-resolver-checks`: the wiring suite covers the new refusals.

## Impact

- Scripts and workflows: `wiring/lib.sh`, `wiring/receive-publish.sh`,
  `wiring/receive-compute.sh`, new `wiring/pins.sh` and `wiring/install-tools.sh`,
  `lib/release.sh` and `lib/newest.sh` (resolver), `wiring-check.sh`,
  `.github/workflows/cascade-receive.yml`, `.github/actions/cascade-publish/action.yml`,
  `.github/workflows/mention-guard.yml`, new `.github/CODEOWNERS`, both offline suites, README.
- Callers: no caller shape changes. Each receiver picks the change up with its wave-2 pin bump;
  the wiring check's new rule then needs its `release` Environment edit (the
  `harden-release-workflows` changes) merged first.
- A receiver that later changes its `pins.sh`, `classes` or the paths its task writes needs the
  `.github` mirror and allow-list changed before its pin moves, or publish refuses its plans.
- Depends on: `harden-cascade-publish` (merged as PR 11, `fe0e11b`). Later: wave 2's pin bumps.

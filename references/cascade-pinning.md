# Pinning the cascade and rolling out a change

Covers how product repos pin the cascade code of this repo by SHA, the rollout steps after a change
here, which repos move first for which kind of change, and how to roll back. The workflows, the
trust bounds and the wiring check are other topics.

## The pin

Each product repo names `cascade-notify`, `cascade-publish`, `cascade-receive.yml` and
`cascade-gates.yml` by the full 40-character SHA of a commit on this repo's `main`, never by a
branch or tag. Every product repo has `sha_pinning_required` on, which refuses an action named by
branch. The `ref:` of the `open-platform-model/.github` checkout in each receiver's cascade-task
workflow (the CI job that tests the repo's `deps:cascade` task against the resolver; core has none)
carries the same SHA, so CI tests the resolver the receiver runs. Any other checkout of `.github` a
repo needs (the operator's module-deps workflow) is declared in its wiring config and carries the
same SHA too. A repo uses one SHA in all these references.

Pinning the reusable workflows as well as the actions keeps the scripts and the plan consistent: the
receive workflow runs the scripts of its own commit, so a workflow at `main` with an action at a SHA
would mix compute and publish script versions (the `plan.json` between them). The two actions run
their scripts from their own directory, and the receive workflow checks them out at its own
`job.workflow_sha`. A pinned reference therefore runs exactly that commit's code, and no input names
another `.github` ref.

A merge to `main` here changes nothing in a product repo's cascade (its callers, its receiver and its
cascade-task workflow) until that repo moves its pin. Two things do not wait for a pin:
`mention-guard` applies at once through the org ruleset, and a laptop `task deps:cascade` uses the
sibling `.github` checkout as it stands. A repo whose `dependabot.yml` configures the
`github-actions` ecosystem ignores `open-platform-model/.github*`, so Dependabot never moves one
reference alone.

## Rolling out a change

1. **Merge, then take the squash SHA.** Merge the `.github` PR once its `Resolver tests` job is green
   (both offline suites, the static checks, `shellcheck` and `actionlint`). No sandbox proves a
   change, so a change of behavior comes with suite cases. Take the full SHA of the squash commit on
   `main` (`git rev-parse origin/main` right after fetching, or the PR's merge commit) and check it is
   on `main`: `gh api repos/open-platform-model/.github/compare/<SHA>...main --jq .status` must print
   `identical` or `ahead`. This repo is squash-only and deletes the PR branch on merge, so a branch
   commit prints `diverged`. Pin the squash SHA, never a branch commit.
2. **Dry run in one receiver** (catalog_opm, library, opm-operator or cli; core has no receiver). Set
   that repo's variable `CASCADE_DRY_RUN` to `true` if it is not already, and note the old value. Open
   and merge its pin PR as in steps 3 and 4. Run
   `gh workflow run deps-cascade.yml -R open-platform-model/<receiver>` and check that:
   - the run succeeds, its `Compute` log shows `scripts from open-platform-model/.github <SHA>`, and
     `Publish` is skipped;
   - the summary's mode and action match `task -x deps:cascade` run locally on that repo's `main`;
   - the receiver's next PR shows `cascade/freshness` and `cascade/settled`;
   - its cascade-task workflow, run by `workflow_dispatch`, checks the resolver out at `<SHA>` and
     passes.

   Then set `CASCADE_DRY_RUN` back. A dry run skips `Publish`, and notify runs only on a release. A
   change to `cascade-publish` or `cascade-notify` therefore first meets real GitHub on the first
   live publish run, or on the first release of an upstream that pins it.
3. **Pin PR in each other repo** among core, catalog_opm, library, opm-operator and cli. Title it
   `ci(deps): pin the cascade to .github <first 7 of the SHA>`. It replaces the SHA in every cascade
   reference and the copy of the wiring check, and changes nothing else. If the change altered an
   input or a caller shape, the caller edit and the wiring-config edit ride the same PR. Find the
   references with `grep -rn -A1 'open-platform-model/.github' .github/workflows`: the `uses:` lines
   and the `repository:` line of the cascade-task checkout, whose `ref:` the `-A1` prints on the next
   line (comment lines also match and need no change). The operator's module-deps workflow has a
   second such checkout, declared in its config's `extra-references`. Before the PR is opened,
   `bash .tasks/cascade/wiring-check.sh --pin-on-main` passes.
4. **Merge each** after its CI is green and its "Verify the cascade wiring" step printed
   `cascade wiring: ok, .github <SHA> (.github main)`. That step runs the same check with
   `--pin-on-main`, so it has confirmed the SHA is on `main` here and that the copy is the file at
   that SHA. The order of the merges does not matter, because a repo runs only its own pin. The only
   limits are the canary rules below.

To roll back, move the pins back the same way. No canary is needed for a SHA the repo already ran.
Watch every first live run on a new pin and roll back if one fails.

## Which repos move when

It depends on which action the diff touches. A diff touches an action when it changes any file that
action runs: its `action.yml` and every script it calls or sources, directly or through another
script. `cascade-notify` runs the notify script and `wiring/lib.sh`. `cascade-publish` runs the
receive-publish script, `wiring/lib.sh`, the pin parser, the resolver and everything in its `lib/`.
So a change to `wiring/lib.sh` touches both, and a change to the resolver or its `lib/` touches
`cascade-publish`. When unsure, count the file as touched.

- **Neither action:** no canary. All five repos may move together, live or dry. The only requirement
  is the dry-run checks above in one receiver after its pin PR has merged.
- **`cascade-publish` only, every receiver dry** (none has `CASCADE_DRY_RUN` set to `false`): all five
  may move together, with the dry-run checks in one receiver after its merge, because no receiver
  publishes. The canary is the first receiver whose `CASCADE_DRY_RUN` is set to `false`. It has the
  first live publish on the new pin, and every other receiver stays dry until that run has succeeded.
- **`cascade-publish` only, any receiver live:** one live receiver is the canary. It moves first and
  takes the dry-run checks. Every other receiver, live or dry, stays on the old pin until the
  canary's first live publish run on the new pin has succeeded.
- **`cascade-notify` only:** a dry run does not help, because notify has no dry run. It runs live on
  every release of an upstream, whatever `CASCADE_DRY_RUN` says. One upstream (core or a receiver)
  moves first as the canary. Every other repo stays on the old pin until the canary's first live
  notify run on the new pin, on its next release, has succeeded. A receiver canary takes the dry-run
  checks. With core as the canary, the first receiver to move after it takes them.
- **Both actions:** the notify rule holds, plus the publish rule for the receivers' state. While every
  receiver is dry, every receiver but the publish canary also stays dry until the canary's first live
  publish on the new pin has succeeded. Once any receiver is live, the canary is a live receiver, and
  no other repo moves until both its first live publish run and its first live notify run on the new
  pin have succeeded.

## Pitfalls

- Pinning a branch commit: it can print `diverged`. Pin the squash SHA on `main`.
- A pin PR that changes more than the SHAs and the wiring-check copy, unless the change altered an
  input or a caller shape.
- A repo that carries two different `.github` SHAs: the wiring check refuses it.
- Turning notify off with `CASCADE_NOTIFY` as a rollout step: use a canary.
- Trusting a sandbox run as proof: add suite cases for a change of behavior.

## Check before you finish

- [ ] The SHA you pin prints `identical` or `ahead` against `main`.
- [ ] You named which action the diff touches, and the canary rule that follows.
- [ ] `CASCADE_DRY_RUN` is back at its old value after a dry run.
- [ ] Every pin PR passed its wiring step with the expected `cascade wiring: ok` line.

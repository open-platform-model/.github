# The cascade workflows and their callers

Covers the reusable workflows and composite actions that run the release cascade and the caller shape
each product repo uses. The scripts are in
`.github/scripts/cascade/wiring/`, with every fixed map (who notifies whom, which sources a
receiver accepts, tag shapes) in the `lib.sh` there. The switches, the trust bounds, the pin
procedure and the wiring check are other topics. The design is the cascade part of the workspace `RELEASING.md`.

## The parts

Two reusable workflows and two composite actions run the cascade in the product repos. The
`opm-cascade` App key is each repo's `cascade` Environment secret `CASCADE_APP_PRIVATE_KEY`, with the
variable `CASCADE_APP_CLIENT_ID`. A reusable-workflow job that declares `environment: cascade` sees
the caller's Environment variables but not its secrets (unless the caller passes `secrets: inherit`,
which no caller does). So every job that mints the App token is the caller's own: it declares
`environment: cascade` and passes the key to a composite action as an input. No reusable workflow
takes or reads a secret. Callers pin every cascade workflow and action to a full commit SHA.

| Part | Kind | Jobs or caller job | Does |
| --- | --- | --- | --- |
| `cascade-notify` | composite action | the caller's `Notify downstream` (`cascade` Environment) | After a release is published: checks the tag, waits for the Go proxy (library only), and sends `repository_dispatch` `upstream-released` with `{source, tags}` to each downstream repo. |
| `cascade-receive.yml` | reusable workflow | `Compute`, `Post gates` | Runs the repo's `task -x deps:cascade` on the rolling `deps/cascade` branch with no secret in reach and plans the result. Posts G2 (from `compute`) and G3 (evaluated in `Post gates`) on open release PRs. Outputs `action`, `dry-run` and `compute-ok`, which are hints only because `compute` ran repo code. |
| `cascade-publish` | composite action | the caller's `Publish` (`cascade` Environment) | Refuses a gates-only run, verifies the plan, then pushes, opens, edits, recreates, closes or labels the cascade PR. Never runs repo code. |
| `cascade-gates.yml` | reusable workflow | `Cascade gates` | Per PR (`pull_request_target`, nothing checked out): `n/a` on both gate contexts for an ordinary PR, and a gates-only receiver run for a release PR. |

Every job's and every action's first step, `Guard`, derives the repo name from `GITHUB_REPOSITORY`
and refuses a repo outside `open-platform-model`.

## Caller shapes

`<sha>` stands for the full SHA of a commit on `main` of this repo. These three blocks are the
shapes that the wiring check enforces. Tests in `.github/scripts/cascade/wiring/test/` read them
from this file, so keep the bold lead-in line and the fenced block of each as they are.

**Notify caller** (in each upstream's release workflow; `needs`, `if` and `tag` per repo):

```yaml
  notify-downstream:
    name: Notify downstream
    needs: [release-please, publish]
    if: needs.release-please.outputs.release_created == 'true' && vars.CASCADE_NOTIFY != 'off'
    runs-on: ubuntu-latest
    environment: cascade
    timeout-minutes: 20
    permissions:
      contents: read
    steps:
      - name: Notify downstream
        uses: open-platform-model/.github/.github/actions/cascade-notify@<sha> # .github main
        with:
          tag: ${{ needs.release-please.outputs.tag_name }}
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

**Receiver caller** (the deps-cascade workflow in catalog_opm, library, opm-controller and cli):

```yaml
name: Deps cascade

on:
  repository_dispatch:
    types: [upstream-released]
  schedule:
    - cron: '17 5 * * *'
  workflow_dispatch:
    inputs:
      dry_run:
        description: Compute and show the diff in the job summary; push nothing
        type: boolean
        default: false
      gates_only:
        description: Evaluate and post the release-PR gates only (sent by Cascade gates)
        type: boolean
        default: false

permissions: {}

concurrency:
  group: ${{ github.ref != 'refs/heads/main' && format('deps-cascade-{0}', github.ref) || (inputs.gates_only && 'deps-cascade-gates' || 'deps-cascade') }}
  cancel-in-progress: false

jobs:
  cascade:
    name: Deps cascade
    permissions:
      contents: read
      pull-requests: read
      statuses: write
    uses: open-platform-model/.github/.github/workflows/cascade-receive.yml@<sha> # .github main
    with:
      dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
      gates-only: ${{ inputs.gates_only == true }}
      g2-mode: ${{ vars.CASCADE_G2_MODE || 'warn' }}
      g3-mode: ${{ vars.CASCADE_G3_MODE || 'warn' }}
      setup-go: false

  publish:
    name: Publish
    needs: cascade
    if: >-
      !cancelled()
      && needs.cascade.outputs.compute-ok == 'true'
      && needs.cascade.outputs.dry-run == 'false'
      && inputs.dry_run != true
      && inputs.gates_only != true
      && vars.CASCADE_DRY_RUN == 'false'
      && github.ref == 'refs/heads/main'
      && contains(fromJSON('["push","recreate","close","conflict","too_long"]'), needs.cascade.outputs.action)
    runs-on: ubuntu-latest
    environment: cascade
    timeout-minutes: 15
    permissions:
      contents: read
      pull-requests: read
    steps:
      - name: Publish
        uses: open-platform-model/.github/.github/actions/cascade-publish@<sha> # .github main
        with:
          dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
          gates-only: ${{ inputs.gates_only == true }}
          labels-managed: false
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

Real runs on `main` share the group `deps-cascade`. Gates-only runs use `deps-cascade-gates`, and
runs from any other ref (always dry runs) use `deps-cascade-<ref>`, so neither replaces a pending
real run.

**Per-PR gates caller** (the cascade-gates workflow in the same four repos):

```yaml
name: Cascade gates
on:
  pull_request_target:
    types: [opened, reopened, synchronize]
permissions: {}
concurrency:
  group: cascade-gates-${{ github.event.pull_request.number }}
  cancel-in-progress: true
jobs:
  gates:
    name: Cascade gates
    permissions:
      statuses: write
      actions: write
    uses: open-platform-model/.github/.github/workflows/cascade-gates.yml@<sha> # .github main
    with:
      g2-mode: ${{ vars.CASCADE_G2_MODE || 'warn' }}
      g3-mode: ${{ vars.CASCADE_G3_MODE || 'warn' }}
```

## Pitfalls

- Passing `secrets: inherit` or `secrets:` to a call into this repo: the wiring check refuses it.
- Reading `CASCADE_APP_PRIVATE_KEY` in any job but the two caller-owned key-holding jobs.
- Trusting a `compute` output as a switch: `publish` re-derives its switches from the caller's inputs.
- Naming a cascade workflow or action by branch or tag: every product repo requires a full SHA.
- Changing a caller shape here without the matching wiring-check rule and test.

## Check before you finish

- [ ] The three caller blocks still have their bold lead-in line, and the wiring check passes on them.
- [ ] A new input is in the caller shape, the wiring check and a suite case.
- [ ] No reusable workflow reads or takes a secret.

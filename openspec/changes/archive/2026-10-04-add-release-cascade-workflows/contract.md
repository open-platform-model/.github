# Phase 3 wiring contract (version 2)

Version 2 applies the contract review (blocker 1, majors 2 to 9, minors 10 to 20, nits 21 to
24). "Review notes" at the end lists what was rejected or applied differently, and why.

Binding for every Phase 3 branch: `.github` `add-release-cascade-workflows`, and
`join-release-cascade` in core, catalog_opm, library, opm-operator and cli. Each change cites it
as "Phase 3 wiring contract §N".

Sources, highest authority first:

1. The owner decisions in `owner-selections-verbatim.md`. The relevant ones are 3, 5, 7, 11, 12, 13, 19 and 22.
2. Workspace `RELEASING.md` on `main`, especially "The cascade", "Gates", "Stop switches", "Owner settings" and "Rollout and changes".
3. The Phase 2 contract (version 1.1, `.github` `openspec/changes/archive/2026-10-04-add-cascade-resolver/contract.md`, cited as "P2 §N") and the `.github` main specs.
4. This file.

Where this file adds something RELEASING.md does not say, §14 lists the amendment to make. If a
branch finds a conflict with 1 to 3, it stops and reports to the supervisor. It must not pick a
side.

Facts checked on 2026-10-04:

- The `opm-cascade[bot]` user id is `337635439`, so the bot's commit email is
  `337635439+opm-cascade[bot]@users.noreply.github.com`.
- The App id is `5184172` and its client id is `Iv23liZLkQZh0Z4MuLyI`. Workflows read the client
  id from `vars.CASCADE_APP_CLIENT_ID`, never as a literal.
- `.github` is public.
- `cascade-sandbox-up` is still **private**. See §11.1.
- The `cascade` Environment in the sandbox allows deployments from `main` only.
- The App has one private key. Every `cascade` Environment (seven repos) holds that same key, and
  a token minted from it can be scoped to any repo the App is installed on. Whoever can run a
  job in any `cascade` Environment can therefore reach all seven repos with the App's
  permissions. The Environment's `main`-only branch policy and the `main` rulesets are the
  controls (§11.5).

---

## 1. Changes and merge order

| # | Repo | Change | Content |
| --- | --- | --- | --- |
| A | `.github` | `add-release-cascade-workflows` | the three reusable workflows, their scripts and tests (§2); the one-line resolver change for sandbox sources (§11.2); seed PRs for the sandbox repos; the sandbox results recorded in the change's `design.md`, including the E4c decision on the workflows guard rule (§7.6) and the shared-key reach (§11.5) |
| B1 | core | `join-release-cascade` | notify job only (§4.5) |
| B2 | catalog_opm | `join-release-cascade` | split out `verify-published`; notify job; receiver; gates caller |
| B3 | library | `join-release-cascade` | notify job (with the Go proxy wait); receiver; gates caller |
| B4 | opm-operator | `join-release-cascade` | notify job; receiver; gates caller |
| B5 | cli | `join-release-cascade` | notify job (including the recovery path); receiver; gates caller |

Order:

- **A merges only after the sandbox cycle (§11) is green** and E1, E1b and E2 to E5 are
  recorded. Run the cycle against A's branch through `@<branch>` and `org-github-ref` (§2.4).
- **The RELEASING.md amendments of §14 land before A merges or in the same review round**, as a
  workspace PR the supervisor merges just before A. A must not merge with RELEASING.md still
  describing a different behaviour.
- B1 to B5 may be written in parallel with A. They merge only after A has merged, because they call `@main`.
- Before any B with a receiver merges, the supervisor sets the repo variable
  `CASCADE_DRY_RUN=true` in that repo (owner decision 22 covers this). The receiver is live only
  when the variable is exactly `false` (§9.1), so an unset variable is also a dry run, but the
  explicit `true` makes the state visible. The schedule must never fire a live run.
- Among the Bs any order works. A dispatch to a repo with no receiver yet returns 204 and starts
  nothing.
- **Phase 3 gate:** the full sandbox cycle is green, and a `workflow_dispatch` dry run in each of
  the four receivers shows the diff that `task -x deps:cascade` gives locally on `main`. Today
  that is exit 3, so the expected result is "noop".
  - This gate does not exercise the push, title and body path in a production repo; the sandbox
    cycle covers that path in a real repo. The production check moves to the Phase 4 gate: before
    `CASCADE_DRY_RUN` is set to `false` in a receiver, that receiver must have shown at least one
    non-noop dry-run summary (from a real upstream release or a sweep), whose title, labels and
    body the supervisor read and found correct. §15 item 5 records this for Phase 4.

Every join PR title is `ci: join the release cascade`. `ci` does not release.

---

## 2. Shared files in `.github`

### 2.1 Layout

```text
.github/workflows/cascade-notify.yml      reusable (workflow_call): notify downstream
.github/workflows/cascade-receive.yml     reusable (workflow_call): receiver (compute, gates, publish)
.github/workflows/cascade-gates.yml       reusable (workflow_call): per-PR gate status for pull_request_target
.github/scripts/cascade/wiring/lib.sh     fixed maps (§3), validation, mention lint, title rank
.github/scripts/cascade/wiring/notify.sh
.github/scripts/cascade/wiring/receive-compute.sh
.github/scripts/cascade/wiring/receive-publish.sh
.github/scripts/cascade/wiring/gates-eval.sh   (G2 and G3 evaluation; runs inside compute)
.github/scripts/cascade/wiring/gates-post.sh   (posts the statuses from gates.json)
.github/scripts/cascade/wiring/test/      offline tests (§12)
```

### 2.2 Rules for all three reusable workflows

- **Pinning.** Every third-party `uses:` is pinned to a full commit SHA, with a version comment.
  Reuse the SHAs the repos already use:
  - `actions/checkout` `3d3c42e5aac5ba805825da76410c181273ba90b1` (v7.0.1), the pin `.github`
    already uses. Only the reusable workflows in `.github` check anything out, so this is the
    only checkout pin Phase 3 adds. A B branch that edits an existing job (catalog_opm's
    `verify-published`) keeps that file's existing checkout pin, so each file has one pin.
  - `actions/create-github-app-token` `bcd2ba49218906704ab6c1aa796996da409d3eb1` (v3.2.0)
  - `actions/setup-go` `b7ad1dad31e06c5925ef5d2fc7ad053ef454303e` (v7.0.0)
  - `cue-lang/setup-cue` `a93fa358375740cd8b0078f76355512b9208acb1` (v1.0.1)
  - `go-task/setup-task` `3be4020d41929789a01026e0e427a4321ce0ad44` (v2.0.0)
  - For upload and download artifact, the writer pins the current release by SHA.
- **Permissions.** Every job declares `permissions:` explicitly. opm-operator's default token is
  read-only, and nothing may rely on defaults.
- **No inline expressions in `run:`.** Never put `${{ }}` inside `run:`. Pass every context value
  through `env:` and quote it in the script. The payload, the PR titles and bodies, and the tags
  are all untrusted.
- **Where the scripts come from.** Each job that needs the scripts checks out
  `open-platform-model/.github` at `ref: ${{ inputs.org-github-ref }}`, `path: org-github`,
  `persist-credentials: false`, using the job's own `GITHUB_TOKEN` (`contents: read`). That
  checkout is the same one that holds the resolver (P2 §3, §11 C4).
- **Calling `gh`.** Scripts call `gh` only through `"${CASCADE_GH:-gh}"`, so tests can stub it (§12).
- **Scratch files.** Every file a job writes that is not a repo change (`gates.json`,
  `notes.md`, `body.md`, `plan.json`, `cascade.bundle`, `diff.patch`, the warnings file, the G2
  worktree) lives under `$RUNNER_TEMP/cascade/`, never under `repo/` or `org-github/`. A file
  inside `repo/` would make the task refuse a dirty tree (P2 §5.2 rule 1), be committed by
  `git add -A`, and be counted by the title as a changed path (P2 §4.2).
- **The repo name.** Every job derives the repo name once, in its first step, from
  `GITHUB_REPOSITORY`: the owner part must be exactly `open-platform-model` and the name part
  must be non-empty, or the job fails. The name is written to a step output, `repo`, and every
  later use (the §3.1 source, the §2.3 token scope, the §3 lookups) reads that output.
  `github.event.repository.name` is never used.
- **No secrets input.** No reusable workflow declares `secrets:`, and no caller passes `secrets:`
  or `secrets: inherit`. The only secret, `CASCADE_APP_PRIVATE_KEY`, is an Environment secret.
  It is read only by a job inside the reusable workflow that declares `environment: cascade`.
  GitHub resolves that Environment in the caller repo, because the run belongs to the caller.
  E1 (§11.4) proves this before A merges; §13.1 is the fallback.

### 2.3 Minting the App token

The token is minted only in a job that declares `environment: cascade`, and as the step directly
before its first use, after every check that could still stop the job. It is never passed between
jobs, written to a file, or kept past its job: `skip-token-revoke` is left unset, so it is revoked
at job end.

| Job | `owner` | `repositories` | Permissions |
| --- | --- | --- | --- |
| notify | `open-platform-model` | the target list from §3.1, comma-separated | `permission-contents: write` (needed for `POST /dispatches`) |
| receive `publish` | `open-platform-model` | the `repo` step output (§2.2) | `permission-contents: write`, `permission-pull-requests: write`, `permission-issues: write` |

Inputs: `client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}` and
`private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}`. `repositories` is never empty: the step
before the mint fails if the value it passes is empty, because `owner` without `repositories`
mints a token for every installed repo. Commit statuses are never posted with the App token
(§8.4), so the App's Commit statuses permission is unused (§14).

**Using the token with git.** The token never appears on a command line. Before the push, the
step runs `echo "::add-mask::$B64"` for the base64 form of `x-access-token:<token>`, then passes
the header to git through the environment:
`GIT_CONFIG_COUNT=1`, `GIT_CONFIG_KEY_0=http.https://github.com/.extraheader`,
`GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $B64"`. `set -x` is never used in a step that holds
the token.

### 2.4 `org-github-ref`

All three reusable workflows take the input `org-github-ref` (string, default `main`). It is the
`.github` ref the scripts and the resolver are checked out from.

- The first step of every job refuses to run when `org-github-ref != 'main'` and
  `github.repository` does not match `^open-platform-model/cascade-sandbox-`. The message is
  "org-github-ref may differ from main only in a sandbox repo".
- So production always runs `main`'s resolver and scripts. A sandbox can test a branch before A
  merges by calling `…/cascade-receive.yml@<branch>` with `org-github-ref: <branch>`.

---

## 3. Fixed maps (in `wiring/lib.sh`, the single source)

### 3.1 Notify edges (source → targets)

| Source repo | Dispatches to |
| --- | --- |
| `core` | `catalog_opm library` |
| `catalog_opm` | `library opm-operator cli` |
| `library` | `opm-operator cli` |
| `opm-operator` | `cli` |
| `cli` | `catalog_opm opm-operator` (release-tool only) |
| `cascade-sandbox-up` | `cascade-sandbox-down` |

- The source is always the `repo` step output (§2.2), derived from `GITHUB_REPOSITORY`. A caller
  cannot choose it.
- A repo not in this table makes notify fail with "not a cascade source".

### 3.2 Receiver allowlist (receiving repo ← accepted payload sources)

This is the inverse of §3.1:

| Receiver | Accepted sources |
| --- | --- |
| `catalog_opm` | `core cli` |
| `library` | `core catalog_opm` |
| `opm-operator` | `catalog_opm library cli` |
| `cli` | `catalog_opm library opm-operator` |
| `cascade-sandbox-down` | `cascade-sandbox-up` |

A receiver not in this table fails with "not a cascade receiver". core is not in it, because it
has no receiver.

### 3.3 Tag shape per source

| Source | Tag regex (also must match P2 §4.4 `TAG_RE`) |
| --- | --- |
| `catalog_opm` | `^opm-v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$` |
| every other source | `^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$` |

### 3.4 `CASCADE_EXPECT` pin keys

These keys match the `pins.sh` and `cascade.sh` keys on each repo's `main`, as checked
2026-10-04.

| Source | Pin key | Value |
| --- | --- | --- |
| `core` | `opmodel.dev/core@v2` | the tag |
| `catalog_opm` | `opmodel.dev/catalogs/opm@v4` | the tag with the leading `opm-` removed |
| `library` | `github.com/open-platform-model/library` | the tag |
| `opm-operator` | `github.com/open-platform-model/opm-operator` | the tag |
| `cli` | `github.com/open-platform-model/cli` | the tag |
| `cascade-sandbox-up` | `github.com/open-platform-model/cascade-sandbox-up` | the tag |

### 3.5 G3 upstreams (receiver → repos whose cascade state it checks)

| Receiver | G3 upstreams |
| --- | --- |
| `catalog_opm` | `core` |
| `library` | `core catalog_opm` |
| `opm-operator` | `catalog_opm library` |
| `cli` | `catalog_opm library opm-operator` |
| `cascade-sandbox-down` | `cascade-sandbox-up` |

The release-tool edges (cli → catalog_opm and cli → opm-operator) never count toward G3.

### 3.6 Sandbox-only resolver widening

`CASCADE_EXTRA_SOURCES` (§11.2) is exported only when `github.repository` is
`open-platform-model/cascade-sandbox-down`, and its value is the literal `cascade-sandbox-up`.
It is never an input and never comes from the payload.

### 3.7 Changelog sources for `deps-cascade:breaking` (pin key → repo and tag prefix)

This is the inverse of §3.4. It is used only by the §7.4 breaking check.

| Pin key | Repo | Tag for version `vX` |
| --- | --- | --- |
| `opmodel.dev/core@v2` | `core` | `vX` |
| `opmodel.dev/catalogs/opm@v4` | `catalog_opm` | `opm-vX` |
| `github.com/open-platform-model/library` | `library` | `vX` |
| `github.com/open-platform-model/opm-operator` | `opm-operator` | `vX` |
| `github.com/open-platform-model/cli` | `cli` | `vX` |
| `github.com/open-platform-model/cascade-sandbox-up` | `cascade-sandbox-up` | `vX` |

A moved pin whose key is not in this table (a third-party pin) is never checked.

---

## 4. Notify

### 4.1 Reusable workflow `cascade-notify.yml`

```yaml
on:
  workflow_call:
    inputs:
      tag:            {type: string, required: true}
      org-github-ref: {type: string, required: false, default: main}
jobs:
  notify:
    name: Notify downstream
    runs-on: ubuntu-latest
    environment: cascade
    timeout-minutes: 20
    permissions: {contents: read}
    steps: …
```

The steps, in order:

1. Derive the repo name (§2.2), then run the §2.4 guard.
2. Check out `org-github`.
3. **Validate.**
   - The source is the repo name, and it must be in §3.1.
   - `tag` must match §3.3 for that source.
   - The targets are taken from §3.1 and written to a step output as a comma list.
4. **Go proxy wait, only when the source is `library`.** This step is best effort.
   - Poll `https://proxy.golang.org/github.com/open-platform-model/library/@v/<tag>.info` every
     30 s for up to 10 minutes.
   - On timeout, log a warning and continue. The step never fails.
   - The receiver's `--expect` wait (P2 §11 C2) and the daily sweep cover what is left.
5. **Mint the token** as §2.3 describes, scoped to the target list.
6. **Dispatch** to each target in turn by running `notify.sh`, which does this:
   - It builds the body with `jq -n --arg`. It never builds JSON by string interpolation.
     ```json
     {"event_type":"upstream-released","client_payload":{"source":"<repo>","tags":["<tag>"]}}
     ```
   - It sends `gh api -X POST repos/open-platform-model/<target>/dispatches --input -`, with
     `GH_TOKEN` set to the App token.
   - It retries up to 3 attempts per target, with backoff of 5, 15 and 45 s.
   - It tries every target, even after one fails.
   - It writes one summary line per target (`target`, HTTP result) to `$GITHUB_STEP_SUMMARY`.
   - It exits 1 if any target still failed. The daily sweep covers a lost dispatch, but the red
     job makes it visible.

Notify never dry-runs. `CASCADE_DRY_RUN` belongs to the receiver.

### 4.2 Payload schema (`schema 1`, fixed)

- `event_type` is exactly `upstream-released`.
- `client_payload` has exactly two keys:
  - `source`: a string, the sending repo name.
  - `tags`: an array of 1 to 8 strings. Notify always sends exactly one.
- The payload carries nothing else. A future change of schema gets a new `event_type`, so this
  shape is never versioned in place.

### 4.3 Caller job (same shape in every upstream)

```yaml
  notify-downstream:
    name: Notify downstream
    needs: <per repo, §4.5>
    if: <per repo, §4.5> && vars.CASCADE_NOTIFY != 'off'
    permissions:
      contents: read
    uses: open-platform-model/.github/.github/workflows/cascade-notify.yml@main
    with:
      tag: <per repo, §4.5>
```

- A job that calls a reusable workflow cannot set `environment:`. The reusable job sets it (see
  RELEASING.md "Notify after publish").
- The caller grants only `contents: read`. The App token does the work.

### 4.4 `CASCADE_NOTIFY`

`CASCADE_NOTIFY` is a repo variable. Setting it to `off` skips notify in that repo, so that
repo's releases stop dispatching. It is a new stop switch; §14 lists the RELEASING.md amendment.

### 4.5 Where notify hooks in, per repo

| Repo | `needs` | `if` (before `&& vars.CASCADE_NOTIFY != 'off'`) | `tag` |
| --- | --- | --- | --- |
| core | `[release-please, publish-cue]` | `needs.release-please.outputs.release_created == 'true'` | `${{ needs.release-please.outputs.tag_name }}` |
| catalog_opm | `[release-please, publish-cue]` | `${{ !cancelled() && needs.publish-cue.outputs.published == 'true' }}` | `${{ needs.release-please.outputs.opm_tag_name }}` |
| library | `release-please` | `needs.release-please.outputs.releases_created == 'true'` | `${{ needs.release-please.outputs.tag_name }}` |
| opm-operator | `[release-please, publish-release]` | `needs.release-please.outputs.releases_created == 'true'` | `${{ needs.release-please.outputs.tag_name }}` |
| cli | `[release-please, goreleaser]` | `${{ !cancelled() && needs.goreleaser.result == 'success' && github.ref == 'refs/heads/main' }}` | `${{ needs.release-please.outputs.tag_name \|\| inputs.tag }}` |

In the `${{ }}` forms, the switch goes inside the braces:
`${{ !cancelled() && … && vars.CASCADE_NOTIFY != 'off' }}`.

**core**

- `publish-docs` never gates notify.
- A failed `publish-cue` skips notify, because the default `success()` applies. That is correct:
  nothing was published.

**catalog_opm.** This branch first splits verification out of `publish-cue`, then hooks notify
on `published`. Notify must never depend on `verify-published`.

- Remove the step "Verify the published build" from `publish-cue`, so `publish-cue` ends at
  "Publish CUE catalog". The fixture gate before publish stays in place.
- Add a new job `verify-published`:
  - `name: Verify the published build`
  - `needs: [release-please, publish-cue]`
  - `if: needs.publish-cue.outputs.published == 'true'`
  - `permissions: {contents: read, packages: read}`
  - Its steps:
    1. Check out the tag `opm_tag_name`.
    2. "Read the pinned opm CLI version".
    3. "Install opm".
    4. "Login to GHCR".
    5. The unchanged verify step, which reads `src/cue.mod/module.cue` and runs
       `opm catalog registry check … --compat`.
  - Keep the existing comment: it is an aid, not a gate (0011:D7).
- Keep `publish-docs` unchanged (`always() && published == 'true'`).

**library**

- The Go proxy wait is inside notify (§4.1 step 4).
- `publish-docs` does not gate notify.

**opm-operator**

- Notify waits for `publish-release`. The cli resolves the operator with the `release` kind,
  which needs the non-draft release with the `install.yaml` asset.
- The workflow-level `concurrency: release-${{ github.ref }}` already covers notify.

**cli**

- The `!cancelled()` is needed because `release-please` is skipped on the `workflow_dispatch`
  recovery path. With it, a manual run that finishes a draft notifies with `inputs.tag`.
- A manual run on an already published release fails the draft check, so `goreleaser` does not
  succeed and notify does not fire a second time.
- The `github.ref` guard keeps a branch dispatch away from the main-only Environment. A branch run
  would otherwise show a failed deployment.
- `publish-templates` is already a `need` of `goreleaser`.

**Sandbox up** (`cascade-sandbox-up`, §11): `needs: release` and `if: success()`. The tag is
`inputs.version`, and the call also passes `with: org-github-ref`.

---

## 5. Receiver caller (`deps-cascade.yml`, per receiving repo)

```yaml
name: Deps cascade

on:
  repository_dispatch:
    types: [upstream-released]
  schedule:
    - cron: '<§5.1>'
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
    uses: open-platform-model/.github/.github/workflows/cascade-receive.yml@main
    with:
      dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
      gates-only: ${{ inputs.gates_only == true }}
      g2-mode: ${{ vars.CASCADE_G2_MODE || 'warn' }}
      g3-mode: ${{ vars.CASCADE_G3_MODE || 'warn' }}
      setup-go: <§5.1>
      labels-managed: <§5.1>
```

- The caller reads `vars` itself, so nothing depends on how a called workflow sees `vars`.
- `inputs.dry_run` and `inputs.gates_only` are empty, and therefore false, on the dispatch and
  schedule triggers.
- **Dry run fails closed.** The receiver is live only when `CASCADE_DRY_RUN` is exactly `false`.
  Unset, deleted or any other value means dry run. Phase 4 sets `false`; it never deletes the
  variable.
- **Concurrency.** Real runs on `main` (dispatch, schedule, manual) share the RELEASING.md group
  `deps-cascade`: one run active and one pending. Two other kinds of run get their own groups,
  so they can never replace a pending real run:
  - gates-only runs on `main` (§8.3) use `deps-cascade-gates`;
  - runs from any other ref (always dry runs) use `deps-cascade-<ref>`.
- Within `deps-cascade`, a newer pending run still replaces an older pending one, as RELEASING.md
  accepts. What the replaced run loses is bounded: the version is re-resolved, the breaking label
  comes from the full pin range (§7.4), not the payload, and only its `CASCADE_EXPECT` wait and
  its "Triggering releases" line are lost. The next dispatch or the sweep covers both.

### 5.1 Per-repo values

| Repo | cron | `setup-go` | `labels-managed` |
| --- | --- | --- | --- |
| catalog_opm | `17 5 * * *` | false | false |
| library | `17 5 * * *` | false | false |
| opm-operator | `47 5 * * *` | true | false |
| cli | `17 6 * * *` | true | true |
| cascade-sandbox-down | none (it uses `workflow_dispatch`) | false | false |

- The crons are off the top of the hour and staggered by tier.
- `setup-cue` defaults to true with `cue-version` `v0.17.1`. The sandbox sets `setup-cue: false`.
- The reusable workflow installs Task (`3.x`) always. It checks that `yq --version` reports
  mikefarah and fails otherwise.

---

## 6. Reusable `cascade-receive.yml`

### 6.1 Interface

```yaml
on:
  workflow_call:
    inputs:
      dry-run:        {type: boolean, required: true}
      gates-only:     {type: boolean, required: false, default: false}
      g2-mode:        {type: string,  required: false, default: warn}   # warn | enforce
      g3-mode:        {type: string,  required: false, default: warn}   # warn | enforce
      setup-go:       {type: boolean, required: false, default: false}  # go-version-file: repo/go.mod
      setup-cue:      {type: boolean, required: false, default: true}
      cue-version:    {type: string,  required: false, default: v0.17.1}
      labels-managed: {type: boolean, required: false, default: false}
      org-github-ref: {type: string,  required: false, default: main}
```

A mode value other than `warn` or `enforce` makes `compute` fail.

It has three jobs:

| Job | Environment | Permissions | Holds the App key |
| --- | --- | --- | --- |
| `compute` | none | `contents: read`, `pull-requests: read` | no |
| `gates` | none | `statuses: write`, `pull-requests: read` | no (it uses `GITHUB_TOKEN`) |
| `publish` | `cascade` | `contents: read` | yes, minted inside |

### 6.2 `compute`

`compute` runs with a 45-minute timeout. It runs repo code (the task) and holds no secret. All
scratch files go under `$RUNNER_TEMP/cascade/` (§2.2), written `$T` below.

1. **Guards.** Derive the repo name (§2.2) and run §2.4. Then set `effective_dry_run` to
   `inputs.dry-run`, or to true when `github.ref != 'refs/heads/main'`. A branch run is always a
   dry run, because the Environment would refuse it anyway (E1b proves that refusal).
2. **Check out:**
   - the repo at `path: repo`, with `fetch-depth: 0` and `persist-credentials: false`;
   - `org-github` (§2.2).
3. **Toolchains,** as the inputs say: setup-go with `go-version-file: repo/go.mod`, setup-cue,
   and setup-task. Then the yq check. Then export
   `CASCADE_RESOLVER=$GITHUB_WORKSPACE/org-github/.github/scripts/cascade/cascade-resolve.sh`.
4. **Payload** (only when `github.event_name == 'repository_dispatch'`).
   - Read `toJSON(github.event.client_payload)` through `env:` and parse it with `jq`.
   - Valid means all of these:
     - `source` is a string in §3.2 for this repo;
     - `tags` is an array of 1 to 8 strings, each matching §3.3 for that source;
     - unknown keys are ignored.
   - **Valid:**
     - Export `CASCADE_SOURCE=<source>` and `CASCADE_TAGS=<tags space-joined>`.
     - Export `CASCADE_EXPECT`, built from §3.4: one `<key>=<value>` pair, from the last valid tag.
   - **Invalid:** drop the whole payload, write a `::warning::` and a summary line that says why,
     and continue as a sweep. An invalid payload is never fatal.
   - The payload never sets the breaking label. §7.4 computes it from the pin range.
   - On the sandbox-down repo only, export `CASCADE_EXTRA_SOURCES=cascade-sandbox-up` (§3.6).
5. **Gate evaluation** (§8.2). This runs before any pin work, so a later failure still leaves
   gate results.
   - It writes `$T/gates.json` and uploads it as the artifact `cascade-gates` (step
     `if: always()`, retention 1 day).
   - **`inputs.gates-only` is true:** stop here. Write the gate results to the summary, set the
     job output `action=gates-only`, and skip steps 6 to 14. `publish` never runs.
6. **PR state.** `cascade_pr` is a function in `lib.sh`, used here, by `publish` (§6.4) and by
   G3 (§8.2). It runs
   `gh pr list -R open-platform-model/<repo> --head deps/cascade --base main --state open --json number,title,body,labels,headRefOid,isCrossRepository,headRepositoryOwner,author`
   and keeps only entries with all of:
   - `isCrossRepository == false`;
   - `headRepositoryOwner.login == "open-platform-model"`;
   - `author.login == "app/opm-cascade"`.

   More than one entry after the filter fails the job ("more than one cascade PR"). A fork PR
   from a branch named `deps/cascade` is never the cascade PR: its title, body and number are
   never read. Then run `git ls-remote origin refs/heads/deps/cascade` to get `OLD`, the remote
   tip, or empty.
7. **Mode** (§7.1). This gives `mode` ∈ {`skip`, `fresh`, `rebuild`, `merge`, `recreate`,
   `conflict`}.
   - `skip` and `conflict` with no merge attempted jump to step 12.
8. **Prepare the branch:**
   - Set the bot identity: `git config user.name 'opm-cascade[bot]'` and
     `user.email '337635439+opm-cascade[bot]@users.noreply.github.com'`. This sets both author
     and committer, which §7.1 relies on.
   - `fresh`, `rebuild` and `recreate`: run `git checkout -B deps/cascade origin/main`.
   - `merge`: run `git checkout -B deps/cascade origin/deps/cascade`, then
     `git merge --no-edit origin/main` (§7.2).
9. **Notes.**
   - With an open cascade PR, write `$T/notes.md` from the old body:
     - Find the first line that equals
       `<!-- cascade-notes: the bot keeps everything below this line -->` after one trailing
       `\r` is removed from it (bodies edited on the web use CRLF). The Notes are every byte after
       that line's `\n`, kept byte for byte, CRLF included.
     - If no such line exists, the whole old body is the Notes, byte for byte. A human may have
       rewritten the body; that text is never lost.
   - Export `CASCADE_NOTES_FILE` pointing at it.
   - With no open PR, do not set it.
10. **Run the task, commit, and compute the title.** One fixed sequence:
    1. Assert `git -C repo status --porcelain` is empty. A dirty tree here is a job error.
    2. Run `task -x deps:cascade` in `repo`, with `CASCADE_BASE=origin/main` and the step 4 env.
       Exit 3 means no change: skip to 5 with no commit. Any exit other than 0 or 3 fails the
       job.
    3. On exit 0, compute `T_dirty` with `task -x deps:cascade:title` on the dirty tree (the
       resolver counts uncommitted and untracked changes, P2 §4.2).
    4. Commit with `git add -A && git commit -m "<T_dirty>"`. The subject only, no body.
    5. Compute `T_computed` with `task -x deps:cascade:title` on the clean tree. Exit 3 means no
       diff against `main`. After a commit, `T_computed` must equal `T_dirty`; a mismatch is a job
       error.
11. **Body, title and labels,** on the final tree, with `CASCADE_BASE=origin/main`:
    - The body: `task -x deps:cascade:body > $T/body.md`.
      - The resolver already lints the part it generates (P2 §4.4; §11 C1 scope).
      - A body over 65000 bytes sets action `too_long` (step 12). Notes are never truncated.
    - The final PR title: §7.3.
    - The labels: §7.4.
    - **Lint.** Run every other bot-generated string through `lib.sh`'s mention lint, with
      mention-guard's pattern `(?<![\w@])@[A-Za-z0-9]` (`grep -P`). That covers the merge commit
      subject, the PR comments of §7.5, and the summary lines that quote no payload. A match fails
      the job. Human text is never linted: the Notes, human commits, and a kept human title.
12. **Action:**

    | Condition | Action |
    | --- | --- |
    | `mode=skip` | `skip` |
    | `mode=conflict` | `conflict` |
    | the body is over 65000 bytes | `too_long` |
    | the final tree equals `origin/main`'s tree (`git diff --quiet origin/main HEAD`) and a PR is open, or `OLD` is set | `close` |
    | the same, with no PR and no `OLD` | `noop` |
    | otherwise | `push`, which also covers a title, body or label edit when `NEW == OLD` |

13. **Workflows guard (§7.6).** It can turn `push` into `recreate` or `conflict`.
14. **Outputs and artifact.**
    - Write `$T/plan.json`:
      - `mode`, `action`, `old_tip` (`OLD`, or empty), `new_tip` (`HEAD` sha)
      - `title`, `title_computed`, `title_marker_old`, `labels` (array), `pr_number` (or null)
      - `conflict_reason`, `conflict_files`, `carry_labels` (§6.4 `recreate`)
      - `effective_dry_run`
    - Build the bundle:
      - `push` and `recreate`: `git bundle create $T/cascade.bundle HEAD ^origin/main`.
      - In `merge` mode also add `^<OLD>`.
    - Upload `plan.json`, `body.md` and `cascade.bundle` as the artifact `cascade-plan`, with
      retention 1 day.
    - The job outputs are `action` and `dry_run` (`effective_dry_run`).
15. **Job summary.** Always written, in dry run and live. It holds:
    - the trigger, and whether the payload was accepted or dropped (and why);
    - the mode, the action, the old and new tip, the final title and the labels;
    - each gate result;
    - the body, inside a `<details>` block fenced with a backtick run longer than any inside it;
    - `git diff --stat origin/main HEAD`, and `git diff origin/main HEAD` capped at 200 KB with a
      "truncated, full diff in the cascade-plan artifact" line.
    - In a dry run also write the line "DRY RUN: nothing was pushed".
    - When dry-running, also upload `$T/diff.patch` in `cascade-plan`.

### 6.3 `gates`

- `needs: compute`. It runs `if: always() && needs.compute.result != 'cancelled'`.
- It downloads `cascade-gates`.
- **The artifact is missing** (compute failed before step 5, or the upload failed):
  - in `warn` for a context: log a warning and post nothing for it;
  - in `enforce` for a context: list the open same-repo release PRs (§8.2 scope) with
    `GITHUB_TOKEN` and post that context as `error`, `could not evaluate, see the run`, on each
    head. This replaces a `pending` the per-PR caller may have left. If even the list fails, the
    job fails.
- Otherwise it runs `gates-post.sh` with `GH_TOKEN: ${{ github.token }}` (§8.4).
- It runs in dry run and in gates-only runs too. Statuses are not pushes.

### 6.4 `publish`

- `needs: compute`.
- `if: needs.compute.result == 'success' && needs.compute.outputs.dry_run != 'true' && contains(fromJSON('["push","recreate","close","conflict","too_long"]'), needs.compute.outputs.action)`
- `environment: cascade`, `permissions: {contents: read, pull-requests: read}`, a 15-minute
  timeout.
- It runs only `git`, `gh`, `jq` and the `org-github` scripts. It never runs a repo task or repo
  code.
- **`plan.json` is untrusted.** `compute` ran repo code, which could have rewritten the plan
  before the upload. `publish` therefore re-derives everything it can and treats the plan as a
  request, not an order.

The steps:

1. Derive the repo name and run §2.4, then check out `org-github` and the repo (`path: repo`,
   `fetch-depth: 0`, `persist-credentials: false`). Download `cascade-plan` to `$T`.
2. **Verify before minting** (all with `GITHUB_TOKEN` and plain git; any failure stops the job
   before the token exists):
   - `action` is one of the five above, and `labels` is a subset of the five bot-relevant labels
     (step 4). Anything else: refuse.
   - Re-derive the cascade PR with `cascade_pr` (§6.2 step 6). `plan.pr_number` must equal its
     number, or both must be empty. A mismatch: refuse.
   - Fetch `origin main`, and read the remote `deps/cascade` tip with `git ls-remote` (fetch it
     when it exists). If that tip is not `old_tip` (or the branch exists when `old_tip` is empty), stop with "deps/cascade moved since compute; the next run
     retries". The job then fails; the pending run, the next dispatch or the sweep retries.
   - For `push` and `recreate`:
     - Run `git bundle verify`, then `git fetch $T/cascade.bundle HEAD:refs/cascade/new`.
     - Check that `refs/cascade/new` equals `new_tip`.
     - Re-run §7.6 with plain git.
   - For `close`: the re-derived PR (if any) is the bot's `deps/cascade` PR by the filter above;
     `close` never acts on any other PR or branch. Whether the tree equals `main` is compute's
     result and cannot be re-checked without running the task; a forged `close` can at worst
     close the bot's own PR, and the next run builds it again.
   - **Title.** Recompute the final title with `lib.sh`'s §7.3 function from the re-derived PR's
     live title, `T_marker` read from its live body (§7.3), and `plan.title_computed`. The same
     inputs decide the title-rise comment (step 5). `title_computed` must match
     `^(fix\(deps\)|test\(fixtures\)|ci\(deps\)): ` (the three P2 §4.3 types) and pass the mention lint. The recomputed title must equal
     `plan.title`.
   - **Body.** The part of `body.md` above the Notes marker passes the mention lint again.
   - **Comments.** Every comment `publish` posts is built inside `publish` from the fixed texts of
     §7.5 in `lib.sh`; the only inserted values are PR numbers and the `conflict_files` list. The
     built text passes the mention lint, or the job fails.
3. **Mint the token** (§2.3).
4. **Labels.**
   - `labels-managed: false`: run `gh label create <name> --color <hex> --description <text> --force`
     for the five bot-relevant labels of RELEASING.md "Labels": `deps-cascade`,
     `deps-cascade:conflict`, `deps-cascade:hold`, `deps-cascade:breaking` and
     `need-human-review`. Use the colours and descriptions exactly as that table gives them.
     `e2e-verified` is never created outside cli.
   - `labels-managed: true` (cli): check that all five exist. If any is missing, fail with
     "declare it in .github/labels.yml".
5. **Act.** Every push and every branch delete is a git push with a lease, using the token as
   §2.3 describes:
   - **`push`**
     - If `new_tip != old_tip`, push with
       `git push --force-with-lease=refs/heads/deps/cascade:<old_tip> origin refs/cascade/new:refs/heads/deps/cascade`.
     - An empty `old_tip` gives `--force-with-lease=refs/heads/deps/cascade:`, which requires
       the branch to be absent.
     - Then create the PR (`gh pr create --head deps/cascade --base main --title --body-file`), or
       edit it (`gh pr edit --title --body-file`, each only if changed).
     - Add the labels missing from `plan.labels`.
     - Remove `deps-cascade:conflict` if it is present.
   - **`recreate`**
     1. If a cascade PR is open, close it with comment C-recreate (§7.5).
     2. Delete the branch atomically:
        `git push --force-with-lease=refs/heads/deps/cascade:<old_tip> origin :refs/heads/deps/cascade`.
     3. Push with an empty lease.
     4. Create a new PR. The body already carries the old Notes from compute step 9.
     5. Add `plan.labels`, plus the old open PR's `deps-cascade:breaking` and
        `need-human-review` labels if it had them (`carry_labels`, re-read from the live PR in
        step 2). `deps-cascade:conflict` is not carried: the rebuilt branch has no conflict. A
        `recreate` with no open PR (a human closed it) carries nothing.
     6. Comment on the old PR "Continued in #<new>." (linted).
   - **`close`**
     1. Comment C-close.
     2. `gh pr close <n>`, if a PR is open.
     3. Delete the branch atomically, as in `recreate` step 2. A rejected lease skips the delete
        with a warning.
   - **`conflict`**
     1. Add `deps-cascade:conflict` and `deps-cascade`.
     2. Comment C-conflict, but only when the label was not already present, so there is no
        comment spam.
     3. Do not push. Exit 0. The label is the visible state.
   - **`too_long`**
     1. Comment C-too-long (§7.5), but only when the bot's newest comment on the PR is not
        already C-too-long.
     2. Do not push or edit. Exit 1, so the run stays red until a human trims the Notes.
   - **Title-rise comment.** Independently of the action, when §7.3 reports a rise on a kept
     human title, comment C-title-rise once (§7.3 says when).

The bot never removes `need-human-review`, `deps-cascade:breaking` or `deps-cascade:hold`. The
only label it removes is `deps-cascade:conflict`, after a successful push.

---

## 7. Branch strategy (never needs the Workflows permission)

The App has no Workflows permission (owner decision 5). GitHub refuses an App push when the
update changes `.github/workflows/*` in a way the App is not allowed to make. The exact rule is
undocumented; E2 to E5 measure it. By default this design pushes only updates that cannot be read
as a workflow change under either plausible rule:

- (a) the pushed tree compared to the default branch's tip;
- (b) the commits the update adds, compared to the old tip.

`PUT …/update-branch` and server-side merges are never used.

### 7.1 Mode selection

| State | Mode |
| --- | --- |
| open cascade PR (§6.2 step 6) carries `deps-cascade:hold` | `skip` (gates still evaluated) |
| no `OLD` | `fresh` |
| `OLD` set, no open cascade PR (the PR was closed and the branch left behind) | `recreate` |
| open cascade PR, and every commit in `origin/main..origin/deps/cascade` has both author email (`%ae`) and committer email (`%ce`) exactly `337635439+opm-cascade[bot]@users.noreply.github.com` | `rebuild` |
| open cascade PR, any other author or committer on that range | `merge` |

- A human who amends or rebases a bot commit keeps the bot as author but becomes the committer,
  so the branch is `merge`, never `rebuild`. No human work is reset away (RELEASING.md "One
  rolling PR per repo").
- A human who closes the cascade PR rejects that state. The next run starts it over (RELEASING.md
  runbook: closing lasts until the next run).

### 7.2 Merge mode

Run `git merge --no-edit origin/main` on `deps/cascade`.

- **Conflict only in derived files** (`go.mod`, `go.sum`, any `cue.mod/module.cue`,
  `internal/operator/dist/install.yaml`, `manifest.go`, matched by basename or path):
  1. For each, run `git checkout --theirs -- <file>` (main's side) and `git add`.
  2. Commit the merge with the subject `Merge origin/main into deps/cascade`.
  3. The task then regenerates them.
- **Any other conflicted path:** `git merge --abort`. Set `mode=conflict` with
  `conflict_reason=merge` and `conflict_files` set to the list.

### 7.3 Final PR title

RELEASING.md "Bump rule": "Once a human retitles a cascade PR, the bot stops rewriting the title."
This section implements exactly that.

- `T_old` is the open cascade PR's current title.
- `T_marker` is read from the PR's current body: the first line, with one trailing `\r`
  removed, that has the form `<!-- cascade-title: <T> -->` and comes before the Notes marker line
  (§6.2 step 9). A copy of the marker pasted into the Notes never counts. With no such line,
  `T_marker` is empty.
- **Retitled** means: an open PR, `T_marker` not empty, and `T_old != T_marker`. The body marker
  always carries the bot's `T_computed` of the last run, so the test stays stable across runs.
  A PR whose body has no marker (a human rewrote the whole body) counts as not retitled.
- **Not retitled:** the final title is `T_computed`.
- **Retitled:** the final title is `T_old`, unchanged, `!` included. The bot never rewrites it
  again, so it never lowers a type and never drops a `!`.
- **Title rise.** Type rank: `ci` is 1, `test` is 2, `fix` is 3, `feat` is 4, and any other type
  is 0, parsed from `^([a-z]+)(\([^)]*\))?(!)?: `. On a retitled PR, when
  `rank(T_computed) > rank(T_old)` and `rank(T_computed) > rank(T_marker)` (the computed class
  rose since the last run), `publish` posts C-title-rise (§7.5). This fires once per rise and
  never changes the title; a deliberate human downgrade stays.
- The bot itself never adds `!` (P2 §4.3) and never uses a type other than those the resolver
  emits.
- The bot's own commit subject is always `T_computed`, which is linted. It is never the human
  title.

### 7.4 Labels

`plan.labels` is the union of these:

- `deps-cascade`;
- the `cascade-labels` marker of the new body;
- `deps-cascade:breaking` when the breaking check finds a breaking release in the bump.

**Breaking check** (in `compute`, after §6.2 step 11, with `GITHUB_TOKEN` on the public API).
RELEASING.md defines the label by "an upstream changelog in the bump", and the bump spans every
release between the pin on `main` and the pin on the branch, so the check covers that whole range
and never reads the payload:

1. Take the moved pins from `repo/.tasks/cascade/pins.sh M` against `pins.sh WORKTREE`, with
   `M = git merge-base origin/main HEAD` (the same rule as P2 §4.2). Each gives `from` and `to`.
2. For each moved pin whose key is in §3.7, list that repo's releases:
   `gh api --paginate repos/open-platform-model/<repo>/releases --jq '.[] | select(.draft | not) | [.tag_name, ((.body // "") | test("BREAKING CHANGES"))] | @tsv'`.
3. Keep the tags with the §3.7 prefix whose version `v` satisfies `from < v <= to`, compared with
   `"$CASCADE_RESOLVER" semver-cmp`. Tags that are not valid versions are ignored.
4. If any kept release body contains `BREAKING CHANGES`, add the label.
5. An API error adds no label and writes a summary warning. The next run retries; labels are only
   ever added.

Labels are only ever added, with the single removal in §6.4.

### 7.5 Comments (fixed text in `lib.sh`, built by `publish`, linted)

- **C-conflict (merge):** "The cascade could not merge `main` into this branch. Conflicting paths:
  <list>. Run `git merge origin/main` locally, resolve, push, then remove `deps-cascade:conflict`."
- **C-conflict (workflows):** "`main` changed workflow files since this branch's last update
  (<list>), or this branch changes workflow files. The cascade App has no Workflows permission,
  so it cannot update this branch. Run `git merge origin/main` locally, push, then remove
  `deps-cascade:conflict`."
- **C-recreate:** "`main` changed workflow files since this branch was built. The cascade App has
  no Workflows permission, so it rebuilt the branch under a new PR. The Notes were carried over."
- **C-close:** "No diff against `main` any more. Closed by the release cascade."
- **C-too-long:** "The PR body is over GitHub's 65000-byte limit because of the Notes. The bot
  never truncates Notes, so it cannot update this PR. Trim the text below the Notes marker; the
  next run continues."
- **C-title-rise:** "The bot now titles this change `<type>`, which ranks above the current
  title. A human set the current title, so the bot keeps it. Retitle the PR if this change should
  release." (`<type>` is the type and scope of `T_computed` only, for example `fix(deps)`.)

### 7.6 Workflows guard

Two diffs decide what is allowed:

- `D1 = git diff --name-only origin/main NEW -- .github/workflows/`
- `D2 = git diff --name-only OLD NEW -- .github/workflows/` (only when `OLD` is set and the push
  updates it in place)

`lib.sh` holds one constant, `WF_GUARD_RULE`, with the value `strict` or `tree`.

| Mode → push | Allowed when (`strict`) | Allowed when (`tree`) | Otherwise |
| --- | --- | --- | --- |
| `fresh` | `D1` empty | `D1` empty | job error. The task never touches `.github/` (P2 §5.2 rule 14), so this is a bug. |
| `rebuild` | `D1` and `D2` empty | `D1` empty | `strict` with `D2` non-empty: action `recreate` |
| `recreate` | `D1` empty (no in-place update) | `D1` empty | job error |
| `merge` | `D1` and `D2` empty | `D1` empty | action `conflict`, `conflict_reason=workflows` |

Notes on these rules:

- `D1` empty means the new tree's workflow files equal `main`'s, so rule (a) passes.
- `D2` empty means the update adds no workflow change relative to the old tip, so rule (b)
  passes.
- `recreate` deletes the branch and creates it fresh, so only rule (a) applies.
- **A decides `WF_GUARD_RULE` inside the change, from E4c**, before A merges. It sets `tree`
  only when E4c records that GitHub accepts both an in-place `--force-with-lease` update across a
  workflow change on `main` and a push of a merge commit that brings `main`'s workflow change in.
  Otherwise it stays `strict`, the default. A records the E4c result and the chosen value in
  `design.md`. It is not a follow-up.
- Under `strict`, every workflow change on `main` (including Dependabot `github_actions` bumps)
  turns a bot-only PR into `recreate` (new PR number, review state lost) and a PR with a human
  commit into `conflict`. That cost is why E4c decides the rule.

---

## 8. Gates G2 `cascade/freshness` and G3 `cascade/settled`

### 8.1 Modes

| Mode | Gate finds a problem | Evaluator error |
| --- | --- | --- |
| `warn` (default) | `success`, description `WARN: <msg>` | `success`, `WARN: gate could not run, see the run` |
| `enforce` | `failure`, `<msg>` | `error`, `could not evaluate, see the run` |

- A clean result is always `success`. Its description starts `ok:`.
- Descriptions are capped at 140 characters, truncated with `…`.
- `target_url` is the run URL.
- The mode comes from `CASCADE_G2_MODE` and `CASCADE_G3_MODE`, which are repo variables read by
  the caller (§5). Phase 5 flips a variable and adds the context to the ruleset.

### 8.2 Evaluation (`gates-eval.sh`, inside `compute`)

The scope is open PRs on base `main` whose head ref starts with `release-please--` and whose head
repo equals the base repo (`isCrossRepository == false`). Fork PRs are never evaluated.

**G2.**

`<tmp>` is `$RUNNER_TEMP/cascade/g2-<n>` (§2.2), never inside `repo/`. Every file G2 reads
comes from `<tmp>`, the release head's own tree: `<tmp>/.tasks/cascade/classes` and
`<tmp>/.tasks/cascade/pins.sh`.

1. `git -C repo fetch origin <headRefOid>`, then
   `git -C repo worktree add --detach <tmp> <headRefOid>`.
2. In `<tmp>`, run `task -x deps:cascade` with `CASCADE_BASE=<headRefOid>`, under
   `env -u CASCADE_EXPECT -u CASCADE_SOURCE -u CASCADE_TAGS -u CASCADE_NOTES_FILE`, so no payload
   value reaches it.
3. Read the result:
   - **Exit 3:** `ok: shipped pins current`.
   - **Exit 0:** list the changed paths with
     `git -C <tmp> diff --name-only HEAD` plus
     `git -C <tmp> ls-files --others --exclude-standard` (no `status --porcelain` parsing), and
     classify them with `"$CASCADE_RESOLVER" classify --classes <tmp>/.tasks/cascade/classes`.
     - Any `shipped` path is a problem. The message lists the moved shipped pins from
       `<tmp>/.tasks/cascade/pins.sh <headRefOid>` against `pins.sh WORKTREE` (run in `<tmp>`),
       for example `behind: core v2.0.0-beta.2→v2.0.0-beta.3`.
     - Otherwise `ok: only test/release-tool pins behind`.
   - **Other exit:** evaluator error.
4. Remove the worktree (`git -C repo worktree remove --force <tmp>`), also on error.

This reuses the repo's own holds, frozen pins and consistent-set rules, so G2 can never disagree
with what the cascade would do.

The task runs repo code from the release head inside `compute`. That job holds no secret and only
read permissions. Release PR heads are written only by release-please (and catalog_opm's
identity advance) from `main` content. Accepted.

**G3.** For each upstream in §3.5, using the public API with `GITHUB_TOKEN`:

- **Problem A:** the upstream's open cascade PR, found with `cascade_pr` (§6.2 step 6, the same
  fork-proof filter), whose title starts `fix(deps)` or `feat(deps)`. The message is
  `<upstream> has open cascade #<n>`. A fork PR from a branch named `deps/cascade` never counts.
- **Problem B:** an open PR labelled `autorelease: pending` whose body contains a `**deps:**`
  bullet, which is how release-please lists a merged `fix(deps)`. The message is
  `<upstream> release #<n> pending with deps`.
- **Otherwise:** `ok: upstreams settled`.
- **API error:** evaluator error.
- **Accepted inaccuracies,** both left for the two-week warn period to show:
  - Problem B matches any `**deps:**` bullet, including one from a hand-made `fix(deps)` PR that
    was not a cascade PR (a false positive).
  - Problem A misses a cascade PR a human retitled to a type outside `fix(deps)`/`feat(deps)`,
    for example an unscoped `fix:` (a false negative).

**Output.** `gates.json` holds `[{"sha": "<headRefOid>", "pr": <n>, "freshness": {"state": "ok|problem|error", "msg": "…"}, "settled": {…}}]`.
`gates-post.sh` maps each entry through §8.1.

### 8.3 Per-PR caller (`cascade-gates.yml` in each of the four receivers)

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
    uses: open-platform-model/.github/.github/workflows/cascade-gates.yml@main
    with:
      g2-mode: ${{ vars.CASCADE_G2_MODE || 'warn' }}
      g3-mode: ${{ vars.CASCADE_G3_MODE || 'warn' }}
```

The reusable `cascade-gates.yml` has one job with no checkout of anything, so no PR code ever
runs. It takes the inputs `g2-mode`, `g3-mode` and `org-github-ref`. It has
`permissions: {statuses: write, actions: write}`.

- **Not a release PR** (the head ref does not start with `release-please--`, or the PR is from a
  fork): post both contexts as `success` with `n/a: not a release PR`. This keeps both contexts
  present on every PR, so they can be made required later.
- **A release PR from the same repo:**
  - In `enforce` mode, post both contexts as `pending` with "evaluating in Deps cascade".
  - In `warn` mode, post nothing.
  - Then run `gh workflow run deps-cascade.yml --ref main -f gates_only=true` with
    `GITHUB_TOKEN`. A `workflow_dispatch` sent with `GITHUB_TOKEN` does start a run. That run
    evaluates and posts the gates on the new head and stops (§6.2 step 5); it never runs the
    task on `main` and never publishes, and its concurrency group cannot displace a pending real
    run (§5).
  - **The dispatch fails** (for example `deps-cascade.yml` is disabled, stop switch 5): in
    `enforce` mode, post both contexts as `error`, `could not dispatch Deps cascade, see the run`,
    replacing the `pending`; in `warn` mode, post both as `success`, `WARN: gate could not run,
    see the run`. Then fail the job.
- It inlines its small script. It needs no `org-github` checkout, and `org-github-ref` exists
  only for §2.4 uniformity.

core has no gates caller. It has no upstream.

### 8.4 Who posts

Every status is posted with `GITHUB_TOKEN` (`gh api repos/{repo}/statuses/{sha} -f state -f context -f description -f target_url`).
That holds for both `gates` in the receiver and the per-PR caller. Both contexts therefore come
from GitHub Actions (integration id `15368`). Phase 5 requires
`{"context":"cascade/freshness","integration_id":15368}` and the same for `cascade/settled`.

---

## 9. Dry run and stop switches

### 9.1 `CASCADE_DRY_RUN`

This is a repo variable in each receiver. The receiver is live only when it is exactly `false`
(§5). Any other state, `true`, unset or deleted, means the receiver computes everything and
writes the summary and artifact (§6.2 steps 14 and 15), but `publish` is skipped: no push, no PR,
no label, no comment. Phase 4 goes live by setting `false`, never by deleting the variable.

- `gates` still posts statuses. That posting is the whole point of the warn phase.
- `workflow_dispatch` with `dry_run: true` does the same for one run.
- A run from any ref other than `main` is always a dry run.
- Notify ignores this variable (§4.1).

### 9.2 Stop switches

From smallest to largest:

1. `deps-cascade:hold` on the PR: `skip`.
2. A `.cascade-hold` entry: one pin.
3. `CASCADE_DRY_RUN` set to anything but `false`: the receiver never pushes.
4. **New:** `CASCADE_NOTIFY=off` in an upstream: it stops dispatching.
5. Disable `deps-cascade.yml`.
6. Suspend the `opm-cascade` App: notify and publish fail at token minting, and compute and
   gates keep running harmlessly.

**Gate statuses under the stop switches.** In `enforce` mode a `pending` status is replaced by
`error` when the per-PR dispatch fails (§8.3) or when `compute` fails before writing
`gates.json` (§6.3). One case remains: with `deps-cascade.yml` disabled (switch 5), a release PR
gets `error` from the per-PR caller, so it is blocked until the workflow is enabled again or the
mode is set back to `warn`. Phase 5 lists this in its notes when it flips a mode to `enforce`.

---

## 10. Per-repo join checklist (B1 to B5)

| | core | catalog_opm | library | opm-operator | cli |
| --- | --- | --- | --- | --- | --- |
| `release.yml` notify job (§4.5) | yes | yes, after the split | yes | yes | yes |
| `verify-published` split | | yes | | | |
| `deps-cascade.yml` (§5) | | yes | yes | yes, `setup-go` | yes, `setup-go`, `labels-managed` |
| `cascade-gates.yml` (§8.3) | | yes | yes | yes | yes |
| `labels.yml` | | | | | already declares all; unchanged |
| repo var `CASCADE_DRY_RUN=true` before merge (supervisor; live only at exactly `false`) | | yes | yes | yes | yes |

- Each B has an OpenSpec change with a spec delta, as the repo's workspace requires. The B2
  delta covers the verify split as its own requirement.
- Each B runs the repo's own lint on workflows (actionlint where the repo has it). It also runs
  `actionlint` from the scratchpad binary on the new files.
- None of the new jobs becomes a required check.
- Verification after merge, done by the supervisor:
  - `gh workflow run deps-cascade.yml -R open-platform-model/<repo> -f dry_run=true`. The summary
    must show mode `fresh` and action `noop` (or the expected diff).
  - `cascade/freshness` and `cascade/settled` must appear on the next PR.
- opm-operator: §2.2 pinning covers its `sha_pinning_required: true` for actions. The `@main`
  reusable call is E6 (§11.4).

---

## 11. Sandbox cycle (part of A)

### 11.1 Precondition: `cascade-sandbox-up` becomes public

- The resolver reads `release` sources anonymously (tags with a credential-free `git ls-remote`,
  assets with an anonymous `HEAD`), so it cannot see a private upstream.
- Giving it credentials would undo its isolation. Instead, the supervisor makes the upstream
  sandbox public under owner decision 22 ("the two sandbox repos"):
  `gh repo edit open-platform-model/cascade-sandbox-up --visibility public --accept-visibility-change-consequences`.
- It holds only a README and a tarball.
- `cascade-sandbox-down` stays private.

### 11.2 Resolver change (in A)

- In `lib/prtext.sh` line 11:
  `CASCADE_SOURCES=" core catalog_opm library opm-operator cli ${CASCADE_EXTRA_SOURCES:-} "`.
- Add one offline test case in `test/cases/prtext.sh`: an extra source is accepted when the
  variable is set, and dropped with the warning when it is not.
- Add a spec delta for `cascade-pr-text`.
- Production can never set the variable, because §3.6 sets it only on `cascade-sandbox-down` and
  never from a payload or an input. No other resolver change is made. The `release` kind already
  takes any repo name (`lib/query.sh` `REPO_RE`).

### 11.3 Sandbox contents (seeded by PRs in the sandbox repos, merged by the supervisor)

**`cascade-sandbox-up`**

- `README.md`.
- `.github/workflows/release.yml`, run by `workflow_dispatch` with input `version`. It has two
  jobs:
  - `release` (`permissions: {contents: write}`): runs `tar czf up.tar.gz README.md` and
    `gh release create "$V" up.tar.gz --target main --title "$V" --notes "sandbox $V"`, using
    `GITHUB_TOKEN`. The release is published, not a draft.
  - `notify-downstream`: as §4.3, with `tag: ${{ inputs.version }}` and
    `org-github-ref: <A's branch>`, calling `cascade-notify.yml@<A's branch>`.
- Seed release `v0.1.0`.

**`cascade-sandbox-down`**

- `UPSTREAM_VERSION` (`v0.1.0`).
- `Taskfile.yml`: the four cascade tasks with the task-level resolver var and the precondition
  from P2 §3.
- `.tasks/cascade/classes`:
  ```text
  shipped UPSTREAM_VERSION
  test fixtures/
  ```
- `.tasks/cascade/pins.sh`: one row for `github.com/open-platform-model/cascade-sandbox-up`,
  display `up`, class `shipped`.
- `.tasks/cascade/cascade.sh`:
  - check-files;
  - `newest release cascade-sandbox-up --asset up.tar.gz --current <cur>`, with `--expect` from
    `CASCADE_EXPECT` for that key;
  - write the result;
  - exit 0 on a write, 3 to stay, and the resolver's code on error;
  - `set -euo pipefail` and no `|| true`.
- `.github/workflows/ci.yml`: job `ci` on `pull_request`, which checks `UPSTREAM_VERSION`
  against `^v[0-9]+\.[0-9]+\.[0-9]+$`.
- `.github/workflows/touch.yml`: a dummy workflow that the tests edit.
- `.github/workflows/deps-cascade.yml`: as §5, with no schedule, `setup-cue: false`,
  `org-github-ref: <A's branch>`, calling `@<A's branch>`.
- `.github/workflows/cascade-gates.yml`: as §8.3, at `@<A's branch>`.
- Repo variable `CASCADE_DRY_RUN=false`, set by the supervisor, so the cycle runs live (§9.1).
  S9 sets it to `true` and back.

After A merges, the sandbox callers switch to `@main` (and drop `org-github-ref`) in one more
sandbox PR. Step S1 is then re-run once to confirm.

### 11.4 Sandbox runs and E-tests (results recorded in A's `design.md`; each with run URL)

| Id | Step | Pass |
| --- | --- | --- |
| E1 | S1: release `v0.2.0` in up | notify (`environment: cascade` inside the reusable workflow) mints a token. The down repo starts a `repository_dispatch` run whose actor is `opm-cascade[bot]`. A `workflow_dispatch` of down's caller from a non-main branch is a forced dry run, and publish never starts. |
| E1b | probe: on a branch `probe-env` of `cascade-sandbox-up`, a workflow `probe-env.yml` (`workflow_dispatch`) calls `cascade-notify.yml@<A's branch>` with `org-github-ref: <A's branch>` and a valid tag, with no dry-run short circuit; dispatch it with `--ref probe-env` | The `notify` job fails on the `cascade` Environment's branch policy before any step runs, and no token is minted. This is the only control against a branch that calls a modified reusable workflow to reach the key, so it must be observed, not assumed. Delete the branch afterwards. |
| E2 | S2: the receiver opens the PR | One PR on `deps/cascade` with author `app/opm-cascade`. Title `fix(deps): bump up to v0.2.0`. The body has the moved pin, the triggering release `cascade-sandbox-up v0.2.0` and the Notes marker. The commit author is the bot. `ci` and `mention-guard` run and pass on the App-pushed PR. |
| S3 | release `v0.3.0` | The same PR number, rebuilt to one commit, `UPSTREAM_VERSION` = `v0.3.0`, and the title updated. |
| S4 | a human commit (`fixtures/human.txt`) on the branch, then release `v0.4.0` | The human commit is an ancestor of the new tip (no rewrite). The bot commit is on top. The title is still `fix(deps)`. |
| E3/E4 | change `touch.yml` on `main` (via PR), then trigger the receiver: (a) with the human commit present, expect action `conflict` (workflows) with label and comment and no push; (b) after the human commit is gone (close the PR, rerun), expect `recreate`: a new PR number with the Notes carried; (c) separately, by hand with an App token from a probe job, record whether an in-place `--force-with-lease` update across the workflow change and a merge push are refused | (a) and (b) behave as §7.6 under `strict`. (c) decides `WF_GUARD_RULE` (§7.6); if it is set to `tree`, rerun (a) and (b) and expect `push` in both. |
| E5 | probe: `PUT …/pulls/<n>/update-branch` with the App token after a workflow change on `main` | Recorded only. The design never uses it. |
| E6 | probe: set `sha_pinning_required: true` on `cascade-sandbox-down` and run its caller at `@main` | If it is refused, opm-operator needs an owner decision (§15). Restore the setting afterwards. |
| E7 | a Dependabot PR in the sandbox | `cascade-gates.yml` posts `n/a` statuses. If the token is read-only there, record it as a Phase 5 blocker (§15). |
| S5 | edit the PR's Notes, release again | The Notes survive byte for byte. A bare `@word` typed in the Notes fails mention-guard on the bot's push (accepted, P2 §11 C1). |
| S6 | merge the PR (squash, as the supervisor) | The `main` commit message is exactly `<PR title> (#N)`, with no body. |
| S7 | open a fake `release-please--x` branch PR with `UPSTREAM_VERSION` behind | `cascade/freshness` shows `WARN: behind: up …`. On a non-release PR both contexts show `n/a`. |
| S8 | dispatch with `{"source":"evil","tags":["@x"]}` (from the owner's or supervisor's `gh`) | The payload is dropped with a warning, the run behaves as a sweep, and there is no mention. |
| S9 | `CASCADE_DRY_RUN=true` on down, release again | The summary shows the diff and "DRY RUN". Nothing is pushed. |
| S10 | retitle the open PR to `feat(deps): sandbox`, release again | The title stays `feat(deps): sandbox`; the body marker carries the computed title; no C-title-rise comment (computed `fix` ranks below `feat`). |
| S11 | push to the S7 PR's head while a dispatch run is pending (start a release, then push within the active run's window) | The per-PR caller's run is `gates_only` in group `deps-cascade-gates`; the pending `deps-cascade` run is not replaced and still shows the payload's triggering release. If the timing cannot be arranged, record the two runs' groups from their logs instead. |

**Probe tokens.** Every probe job (E3c, E4c, E5) mints its token with
`repositories: cascade-sandbox-down` and only the permissions the probe needs. A probe never
mints a token without `repositories`.

The Phase 0 owner pull-request-only bypass check (RELEASING.md step 7) is not part of the
cycle. It stays an owner check.

### 11.5 Sandbox security

- The sandboxes' `cascade` Environments hold the same App key as production (Facts). Anyone who
  can push to a sandbox's `main` can add a workflow there that mints a token for any of the seven
  repos.
- Before the sandbox Environments are used, the supervisor adds a `main` ruleset to both sandbox
  repos: pull request required, no required checks, owner bypass pull-request-only, the same
  shape as the product repos. The seeding PRs are then merged as PRs. §15 item 1 covers whether
  decision 22 includes this.
- A records this reach in `design.md`, and that rotating the one key rotates it everywhere.

---

## 12. Tests and CI in `.github` (A)

- **Offline tests** under `wiring/test/`, run by the existing required `.github` CI check. Do not
  add a new required context. They use local bare repos as `origin` (`file://`), a stub `gh`
  (`CASCADE_GH`), the P2 stub resolver, and a toy `Taskfile.yml`. They cover:
  - payload validation, including the 8-tag limit, a bad tag, an unknown source and extra keys;
  - each §7.1 mode, including a bot commit amended by a human (bot author, human committer),
    which must give `merge`;
  - the `cascade_pr` filter: a fork PR on `deps/cascade`, a same-repo PR by a human, and two
    matching PRs (job error);
  - the §7.2 derived-file conflict and the hard conflict;
  - every row of §7.6;
  - the §7.3 rules: not retitled, retitled and kept (`!` included), the title-rise comment
    firing once, a marker pasted into the Notes, and a body with no marker;
  - the §7.4 breaking check over a range of several releases, with one breaking release in the
    middle, and with an API error;
  - Notes extraction (with the marker, without it, and with a CRLF body, where the body must not
    grow across two runs);
  - the §6.4 step 2 refusals: a `pr_number` mismatch, an unknown label, an unknown action, and a
    title that does not recompute;
  - the §6.2 step 12 action table;
  - the `notify.sh` payload bytes and the target map;
  - the §2.4 guard and the §2.2 repo-name derivation (empty name, wrong owner);
  - the §5 concurrency-group expression for a main real run, a gates-only run and a branch run;
  - the §8.1 status mapping and truncation.
- **Static checks:**
  - `actionlint`: the `Resolver tests` job already runs it, pinned, on every workflow, so the
    three new workflows are covered with no change;
  - the tests and static checks run as steps in the existing `Resolver tests` job, so no new
    context appears. If they push the job past its `timeout-minutes: 10`, raise the timeout; the
    context name does not change.
  - `shellcheck` (already pinned at v0.11.0) on `wiring/**.sh`.
- **The receive and notify workflows themselves** are tested only by the sandbox cycle (§11).

---

## 13. Fallbacks (applied only if a sandbox test fails)

### 13.1 E1 fails (the Environment secret is not visible to a reusable-workflow job)

- Replace notify and publish with composite actions:
  - `.github/actions/cascade-notify/action.yml`;
  - `.github/actions/cascade-publish/action.yml`.
- Each caller then declares its own job with `environment: cascade`. It mints the token in that
  job and calls the composite action with `uses: open-platform-model/.github/.github/actions/…@main`.
- `compute` and `gates` stay in the reusable workflow. The receiver caller then has two jobs: the
  reusable `compute`/`gates`, and a local `publish` job that downloads `cascade-plan`.
- This is a contract change. The A branch reports it to the supervisor before implementing it.

### 13.2 E2 fails (a fresh branch at `main` plus a non-workflow commit is refused)

The design cannot work without the Workflows permission, which owner decision 5 forbids. Stop
and escalate. Do not grant the permission.

---

## 14. RELEASING.md amendments (a workspace PR, merged before or together with A)

These land before A merges (§1), so RELEASING.md never describes behaviour the merged workflows
do not have.

- "Stop switches": add `CASCADE_NOTIFY=off`. `CASCADE_DRY_RUN` is live only at exactly `false`.
- "Concurrency": the real runs keep the group `deps-cascade`; gates-only runs use
  `deps-cascade-gates` and branch runs `deps-cascade-<ref>`, so neither can replace a pending
  real run.
- "Two-job split": it is now three jobs. `compute` and `gates` hold no secret; `gates` posts the
  G2 and G3 statuses with `GITHUB_TOKEN`, not `publish` with the App token. `publish` re-derives
  the PR and refuses a plan it cannot verify (§6.4 step 2).
- "Owner settings": the App's Commit statuses permission is unused (§8.4). The owner may drop it;
  nothing in Phase 3 depends on it either way.
- "Gates": add the `CASCADE_G2_MODE` and `CASCADE_G3_MODE` variables. Statuses are posted by
  GitHub Actions (integration 15368). `n/a` success on non-release PRs. The per-PR caller
  dispatches a gates-only receiver run when a release PR head moves. This replaces the "missing
  on current head until the next dispatch" note. Add G3's accepted false positive and false
  negative (§8.2).
- "One rolling PR per repo": add `recreate`, which happens when `main` changed workflow files
  under a bot-only branch (only under `WF_GUARD_RULE=strict`), and the workflows
  `deps-cascade:conflict` case. A closed PR's leftover branch is recreated. A bot commit a human
  amended counts as a human commit.
- "The receiver": add the payload schema (exactly `source` and `tags`), the per-repo source
  allowlist, the rule that an invalid payload becomes a sweep, that a branch-ref run is a forced
  dry run, and that a fork PR on a branch named `deps/cascade` is never the cascade PR.
- "Bump rule": no change to the retitle rule (§7.3 implements it as written). Add the
  C-title-rise comment, and that `deps-cascade:breaking` covers every upstream release between
  the pin on `main` and the pin in the PR.
- "Notify after publish": the catalog_opm job is now named `verify-published`; library waits for
  the Go proxy, best effort, for 10 minutes.
- "Phases": Phase 4 "Clear the dry-run flag" becomes "set `CASCADE_DRY_RUN=false`", and a
  receiver goes live only after one non-noop dry-run summary was read and found correct (§1).

## 15. Open points for the supervisor or owner

1. **The sandbox visibility change** (§11.1). The supervisor applies it under decision 22. If the
   supervisor reads it as outside decision 22, ask the owner.
2. **E6.** If `sha_pinning_required` refuses the `@main` call in opm-operator, the owner chooses
   one of:
   - turn the setting off in opm-operator; or
   - pin opm-operator's calls to a `.github` commit SHA, which would mean a carve-out from
     decision 13.
3. **E7.** If Dependabot `pull_request_target` runs cannot post statuses, G2 and G3 cannot become
   required until that is solved. This is a Phase 5 item and does not block Phase 3.
4. **Sandbox rulesets** (§11.5). The supervisor adds a PR-required `main` ruleset to both sandbox
   repos before their Environments are used. Decision 22 names "the two sandbox repos" and "the
   `main` branch rulesets" separately; if the supervisor reads the sandbox rulesets as outside it,
   ask the owner before the cycle starts.
5. **Phase 4 gate** (§1). Each receiver must show one non-noop dry-run summary, read by the
   supervisor, before `CASCADE_DRY_RUN=false`. The Phase 3 gate cannot show it, because every
   pin is current today.
6. **Stuck `error` under switch 5** (§9.2). In `enforce` mode, a disabled `deps-cascade.yml`
   blocks release PRs until it is enabled again or the mode goes back to `warn`. Phase 5 notes
   this when it flips a mode.

---

## Review notes

Contract review of version 1: 1 blocker, 7 majors, 11 minors, 4 nits. All 24 findings are
accepted on substance and applied in version 2. The points below were rejected, or applied in a
different way than the review proposed, with the reason.

- **4 (title rule). The proposed fix is rejected; a different fix is applied.** The review asked
  the bot to raise a human title when `rank(T_computed) > rank(T_marker)`. That still rewrites a
  title after a human retitled it, which RELEASING.md "Bump rule" forbids ("Once a human retitles
  a cascade PR, the bot stops rewriting the title"). It also cannot detect "rose since the human
  acted": the marker is rewritten with `T_computed` on every run, so the test means "rose since
  the last run". Version 2 follows RELEASING.md as written: a retitled PR keeps its title for
  good, and when the computed class rises above it, `publish` posts C-title-rise once (§7.3,
  §7.5). The safety concern (a shipped bump under a non-releasing human title) becomes a visible
  prompt, and no owner decision is needed. The review's other two points are applied: `T_marker`
  is the first marker line above the Notes marker, with CRLF handled, and no marker means "not
  retitled". The RELEASING.md amendments now land before or with A (§1, §14).
- **2 (concurrency). Applied with a different group expression.** Real runs on `main` keep the
  RELEASING.md group name `deps-cascade`, rather than `deps-cascade-<ref>-run`, so RELEASING.md
  "Concurrency" stays true for them. Gates-only runs and branch runs get their own groups. One
  pending real run replacing another (dispatch over dispatch, or the schedule over a dispatch)
  stays accepted, as RELEASING.md says. With finding 3 applied, what the replaced run loses is
  only its `CASCADE_EXPECT` wait and its "Triggering releases" line (§5).
- **6 (`publish` trusts the plan). Applied except the `close` tree check.** `publish` cannot
  test `git diff --quiet origin/main` for a `close`. The tree that equals `main` is the task's
  output, which `publish` must never produce. The remote branch also legitimately differs from
  `main` when the close happens because `main` caught up. Version 2 limits `close` to the
  re-derived bot PR and the leased branch. A forged `close` can then at worst close the bot's own
  PR, and the next run rebuilds it (§6.4 step 2). The PR re-derivation, the label subset, the
  title recomputation and the lint of the body and comments are applied. Comments are now built
  inside `publish` from `lib.sh` texts rather than taken from the plan.
- **19 (weak Phase 3 gate). The test-only input is rejected; the alternative is taken.** A
  `workflow_dispatch` input that sets a pin back would add, in every production receiver on
  `main`, an input that changes pin resolution. A branch run cannot carry it either, because
  `compute` always builds from `origin/main`. The review's alternative is applied: the sandbox
  cycle covers the push, title and body path in a real repo, and the production check moves to
  the Phase 4 gate (§1, §14 "Phases", §15 item 5).
- **20 (sandbox security). Applied, with the ruleset flagged.** Probe tokens are scoped, and the
  shared-key reach goes into the Facts and A's `design.md`. The sandbox `main` rulesets are
  specified (§11.5). Whether decision 22 covers them is listed for the supervisor (§15 item 4)
  rather than assumed.
- **8 (E1b). Applied in `cascade-sandbox-up`, not down.** Down's receiver forces a dry run on any
  branch, so `publish` never starts there. Notify has no dry-run path, so a branch probe of
  `cascade-notify.yml` reaches the Environment check directly.
- **12 (token on the command line). Applied as `::add-mask::` plus `GIT_CONFIG_*` environment
  variables** rather than a credential helper. This keeps the header off argv with no helper
  script to quote.
- **15 (stuck `pending`). Applied and extended.** On a failed dispatch in `warn` mode, the per-PR
  caller also posts `WARN` success, so both modes leave a visible result. The one case left, a
  disabled workflow under `enforce`, is listed (§9.2, §15 item 6).
- **21 (checkout pin). Applied as one pin, v7.0.1.** Only the `.github` reusable workflows check
  anything out, and the callers have no checkout. actionlint already runs, pinned, on every
  `.github` workflow, so the review's "add actionlint" becomes "covered with no change". The
  timeout point is applied.
- **24 (body over 65000 bytes). Applied as the new action `too_long`.** It posts C-too-long once
  and exits 1, so the run stays red until a human trims the Notes.

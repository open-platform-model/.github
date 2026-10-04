# Phase 3 wiring contract (version 3.1)

**[v3.1]** Version 3.1 applies the contract v3 review (findings 1 to 10, "Version 3.1 notes" at
the end) with the supervisor's decisions: finding 2 option (a), every cascade reference
including each receiver's `cascade-task.yml` resolver checkout `ref:` carries the repo's one
SHA, and the bump grep is `grep -rn 'open-platform-model/.github' .github/workflows`; finding 3
re-arm (superseded in 3.1.1, below). It was written against `.github` PR #9
(`open-platform-model/.github#9`, head `99d93e5`, README "Pinning and bumps" and the archived
`add-release-cascade-workflows` design); ~~where the README still differs, §15 item 14 lists what A
must change~~ (**[v3.1.2]** the README no longer differs: §15 item 14 is done). Passages changed in 3.1 are marked `[v3.1]`; §2.4 and §10.1 were rewritten as
wholes. A branch cites this file as "Phase 3 wiring contract (version 3.1)".

**Changelog 3.1.1** (2026-10-04; the version a branch cites stays "version 3.1"): applies the
contract v3.1 review (`p3f-review.md`, findings 1, 2, 5, 6, 9, 10, 12, 13 and 14; findings 3, 4,
7, 8 and 11 are fixes in other files) and **owner decision 26, which drops the sandbox**: there is
no sandbox App, no re-arm and no sandbox step in a bump. A `.github` cascade change is proven by
its offline suites and then by a dry-run pin bump in one receiver (the canary) before the other
repos (§2.4 step 2). The wiring check now asserts exact key sets on the key-holding jobs and their
step, on `deps-cascade.yml`'s top level, and refuses startup-code variables in `release.yml`'s
workflow `env` (§10.1 item 6). Passages changed in 3.1.1 are marked `[v3.1.1]`; "Version 3.1.1
notes" at the end maps each finding. A branch that applied 3.1 re-applies §10.1 items 3, 6, 9 and
11 and the pre-merge check.

**Changelog 3.1.2** (2026-10-04, a correction made in place after this change was archived, so
the file does not mislead; the version a branch cites stays "version 3.1"): applies the final
cross-check of PR #9 (`p3g-crosscheck.md`, findings 1, 3, 6 and 7) with the supervisor's
decisions. (1) `.github` **does** delete branches on merge (`delete_branch_on_merge: true`, read
back 2026-10-04): merging A deletes `feat/add-release-cascade-workflows` at once, each B swaps
its pins to A's `main` squash SHA right away, and the sandbox callers' `a2950ce` pins do not
matter because the sandboxes are archived after Phase 3 (Facts, §2.4, §11.3, §15 items 10 and
12). (3) Canary rule: when a `.github` diff touches `cascade-publish` or `cascade-notify`, the
other repos stay on the old pin until the canary's first live publish (or notify) run has
succeeded (§2.4 steps 2 and 4). (6) §14 and §15 item 14 are marked done. (7) The §11.3
`[v3]` sandbox-move paragraph is struck through. Separately, the supervisor's addendum for the
five join changes (`p3-join-addendum.md`) makes the §10.1 item 6 wiring check stricter: a
per-repo allow-list of `release.yml` top-level `env` keys replaces the deny-list, and every
key-holding job must have `runs-on: ubuntu-latest`; the check guards against mistakes, while
review and the `main` ruleset guard against a deliberate edit. Passages changed in 3.1.2 are
marked `[v3.1.2]`.

Version 3 folds in what the sandbox cycle established (the `.github` branch at `4d6a616`, its
deviations 1 to 9), the sandbox verification ("Contract points the five join changes must
adopt"), owner decision 24, and the review-fix cycle (`a2950ce`, `e622c47`, `94fe628`). Version 2
applied the first contract review; its "Review notes" stay at the end, followed by "Version 3
notes".

**Every passage that changed from version 2 is marked `[v3]`.** A section heading marked `[v3]`
was rewritten as a whole; otherwise the mark sits on the changed paragraph or row. Unmarked text
is version 2 unchanged.

**[v3] What changed, in one list** (details in the marked sections):

1. **E1 failed, so the §13.1 fallback is the design.** Notify and publish are composite actions
   (`.github/actions/cascade-notify`, `.github/actions/cascade-publish`). Each caller owns the
   job that declares `environment: cascade` and passes the key to the action as an input. The
   reusable `cascade-notify.yml` no longer exists. `cascade-receive.yml` keeps `compute` and
   `gates` only (§2, §4, §5, §6).
2. **[v3.1] Every cascade reference is pinned to one full `.github` `main` commit SHA** per
   repo, with the comment `# .github main`: owner decision 24 (the two actions), extended by the
   supervisor to the two reusable workflows, because M2 ties compute's scripts to the workflow's
   own SHA and a mixed pin would mismatch compute and publish, and to the `ref:` of the resolver
   checkout in each receiver's `cascade-task.yml`, so CI tests the resolver the receiver runs
   (review findings 2 and 5). `@main` (decision 13) no longer applies to the cascade. A `.github`
   change reaches a product repo only through a bump PR (§2.4). The extension is the
   supervisor's derivation, not the owner's words, and goes to the owner in the phase report.
3. **`org-github-ref` is gone.** The actions run their scripts from their own directory
   (`$GITHUB_ACTION_PATH/../../scripts/cascade/wiring/`), and `cascade-receive.yml` checks its
   scripts out at its own `job.workflow_sha` (§2.2, §2.4, §6.2).
4. **The dry-run stop switch is enforced inside `cascade-publish`** through its required
   `dry-run` input: exactly `false` publishes, `true` publishes nothing and exits 0, any other
   value fails before the mint (§6.4, §9.1).
5. **`WF_GUARD_RULE` is `tree`** (E4c accepted both pushes). Under `tree`, `recreate` happens
   only for a closed PR's leftover branch, and a workflow change on the branch itself still gives
   `conflict` in merge mode (§7.6).
6. **The S5 and S6 expectations are corrected** (a bare mention in a bot PR body is advisory;
   GitHub appends `Co-authored-by` trailers despite BLANK) (§11.4).
7. **go-task's `exit status 3` error annotation is dropped** on a no-change run (§6.2 step 10).
8. **Exact caller YAML for every repo** (§4.6, §5.2), and the deltas each existing
   `join-release-cascade` branch must apply (§10.1). **[v3.1]** §10.1 is now a mechanical
   checklist per repo, including a CI-enforced `yq` wiring check (§10.1 item 6), the Dependabot
   ignore, the `cascade-task.yml` pin, the stale "no secret" wording, and the `compare` pre-merge
   check.

Binding for every Phase 3 branch: `.github` `add-release-cascade-workflows`, and
`join-release-cascade` in core, catalog_opm, library, opm-operator and cli. Each change cites it
as "Phase 3 wiring contract §N". **[v3]** A branch that cited a version 2 section checks the
section again: §2.4, §4, §5, §6.1, §6.4, §7.6, §10, §11 and §13.1 changed meaning. **[v3.1]**
Section numbers are unchanged from version 3; §2.4, §5.2 (the assertion paragraph), §10 and
§10.1 changed meaning.

Sources, highest authority first:

1. The owner decisions in `owner-selections-verbatim.md`. The relevant ones are 3, 5, 7, 11, 12, 13, 19, 22 and **[v3.1]** 24, which supersedes decision 13's `@main` for the cascade **actions**. The supervisor extended it to the two reusable workflows (because M2 ties compute's scripts to the workflow's own SHA, so a mixed pin would mismatch compute and publish across `plan.json`) and to the `cascade-task.yml` resolver checkout `ref:`; that extension is a supervisor decision, binding here, and is reported to the owner in the phase report. **[v3.1.1]** Decision 26 ("Drop it": no sandbox for future cascade-wiring changes; future wiring changes are tested offline and through a dry-run pin bump in one product repo first) supersedes decision 25 (the separate sandbox App, never created).
2. Workspace `RELEASING.md` on `main`, especially "The cascade", "Gates", "Stop switches", "Owner settings" and "Rollout and changes".
3. The Phase 2 contract (version 1.1, `.github` `openspec/changes/archive/2026-10-04-add-cascade-resolver/contract.md`, cited as "P2 §N") and the `.github` main specs.
4. This file.

Where this file adds something RELEASING.md does not say, §14 lists the amendment to make. If a
branch finds a conflict with 1 to 3, it stops and reports to the supervisor. It must not pick a
side. **[v3]** RELEASING.md on `main` (9ce8faa) still describes the version 2 shapes (a reusable
notify workflow that declares the Environment, a two-job split where `publish` posts the gates).
Until the §14 PR lands, this file wins over those passages; the conflict is known and owned by
the supervisor (B1), so a branch does not stop over it.

**[v3] Supervisor records (2026-10-04):**

- The supervisor granted the E6 `sha_pinning_required` toggle on `cascade-sandbox-down` to the
  sandbox-cycle agent, and confirms it. The agent toggled it from 14:08:36Z to 14:09:57Z and
  restored it to `false`. The record reads that way in `design.md` and `tasks.md`.
- The supervisor set the repo variable `CASCADE_DRY_RUN=true` in catalog_opm, library,
  opm-operator and cli (read back 2026-10-04: all four `true`). §1's "before any B with a receiver
  merges" precondition is met.
- The owner typed "Go for phase 3"; the supervisor triages review findings.

Facts checked on 2026-10-04:

- The `opm-cascade[bot]` user id is `337635439`, so the bot's commit email is
  `337635439+opm-cascade[bot]@users.noreply.github.com`.
- The App id is `5184172` and its client id is `Iv23liZLkQZh0Z4MuLyI`. Workflows read the client
  id from `vars.CASCADE_APP_CLIENT_ID`, never as a literal.
- `.github` is public.
- ~~**[v3]** `cascade-sandbox-up` is **public** (§11.1, done); `cascade-sandbox-down` is
  private.~~ **[v3.1.1]** Decision 26 (read back by the supervisor 2026-10-04): both sandboxes
  are private; `CASCADE_APP_PRIVATE_KEY` and `CASCADE_APP_CLIENT_ID` are deleted from both
  sandbox `cascade` Environments; the owner takes both off the `opm-cascade` installation (one
  click in the App settings); both sandboxes are archived after Phase 3. No sandbox App exists.
- The `cascade` Environment in the sandbox allows deployments from `main` only. **[v3]** E1b
  observed it: "Branch probe-env is not allowed to deploy to cascade", zero steps run.
- **[v3]** opm-operator has `sha_pinning_required: true` (read back 2026-10-04). E6 showed it
  refuses an **action** named by branch ("must be pinned to a full-length commit SHA") and does
  **not** refuse a reusable **workflow** named by branch or SHA. **[v3.1]** Decision 24 pins the
  actions; the supervisor's extension pins the workflows too (top, item 2).
- ~~**[v3]** `.github` has `delete_branch_on_merge: false`, so merging A does not delete
  `feat/add-release-cascade-workflows`. The sandbox callers pin `a2950ce` on that branch, and it
  must stay reachable until task 5.8 moves them (§11.3).~~ ~~**[v3.1.1]** The sandbox callers
  keep their `a2950ce` pins until the sandboxes are archived; nothing moves them (§11.3, §15 item
  10).~~ **[v3.1.2]** `.github` has `delete_branch_on_merge: true` (read back 2026-10-04), so
  merging A deletes `feat/add-release-cascade-workflows` at once. Each B therefore swaps its pins
  to A's `main` squash SHA right away (§2.4 "Before A merges"). The sandbox callers keep their
  `a2950ce` pins, and that does not matter: the sandboxes hold no key and are archived after
  Phase 3 (§11.3).
- **[v3.1.1]** `.github` merge settings are now PR_TITLE + BLANK and squash-only, the same as the
  five product repos (set by the supervisor 2026-10-04, review finding 9). Merging A therefore
  always makes one new squash commit on `main`, and A's branch commits (`99d93e5`, `a2950ce`)
  stay off `main`, so the §2.4 `compare` check prints `diverged` for them.
- **[v3.1]** A is `.github` PR #9, "feat(cascade): add the release-cascade notify and receive
  wiring", open, head `99d93e54608b9b8a6c469ee3b7c7fcffa391256b` (`a2950ce` code, `e622c47` seed
  pins, `94fe628` and `25fe15b` docs, `99d93e5` the in-PR archive). Its checks `Resolver tests`
  and `mention-guard` are green at that head (read back 2026-10-04). `25fe15b` applied the
  `.github` side of this review (README "Pinning and bumps", design, task 5.10) and changed no
  workflow behaviour, so no sandbox rerun.
- **[v3.1]** Repos with a Dependabot `github-actions` ecosystem: library, opm-operator, cli (each
  already ignores `open-platform-model/docs-kit*`). core and catalog_opm have no
  `.github/dependabot.yml`.
- **[v3.1]** Each receiver's `.github/workflows/cascade-task.yml` (on `main`, not added by the
  join branches) checks the resolver out with `repository: open-platform-model/.github` and
  `ref: main`. core has no `cascade-task.yml`.
- **[v3.1]** The required CI contexts on `main` (read back 2026-10-04): core `Validate schema`
  (`ci.yml` job `ci`), catalog_opm `Validate catalog` (`ci.yml` job `ci`), library `Go tests`
  (`test.yml` job `test`), opm-operator `Lint` (`lint.yml` job `lint`), cli `Lint` (`pr.yml` job
  `lint`; also `G4 operator-embed evidence` and `E2E (kind, embedded operator)`). Each of those
  jobs runs on every PR with no path filter and already installs Task.
- The App has one private key. Every `cascade` Environment (**[v3.1.1]** five product repos;
  the sandbox Environments no longer hold it, decision 26) holds that same key, and a token
  minted from it can be scoped to any repo the App is installed on. Whoever can run a job in any
  `cascade` Environment can therefore reach all five product repos with the App's permissions.
  The Environment's `main`-only branch policy, the `main` rulesets and the wiring check (§10.1
  item 6) are the controls (§11.5).

---

## 1. Changes and merge order

| # | Repo | Change | Content |
| --- | --- | --- | --- |
| A | `.github` | `add-release-cascade-workflows` | **[v3]** two reusable workflows (`cascade-receive.yml`, `cascade-gates.yml`), two composite actions (`cascade-notify`, `cascade-publish`), their scripts and tests (§2); the one-line resolver change for sandbox sources (§11.2); seed PRs for the sandbox repos; the sandbox results recorded in the change's `design.md`, including the E4c decision on the workflows guard rule (§7.6, `tree`) and the shared-key reach (§11.5); the README "Pinning and bumps" procedure (§2.4) |
| B1 | core | `join-release-cascade` | notify job only (§4.5, **[v3]** §4.6) |
| B2 | catalog_opm | `join-release-cascade` | split out `verify-published`; notify job; receiver; gates caller |
| B3 | library | `join-release-cascade` | notify job (with the Go proxy wait); receiver; gates caller |
| B4 | opm-operator | `join-release-cascade` | notify job; receiver; gates caller |
| B5 | cli | `join-release-cascade` | notify job (including the recovery path); receiver; gates caller |

Order:

- **A merges only after the sandbox cycle (§11) is green** and E1, E1b and E2 to E5 are
  recorded. **[v3]** Done: the cycle ran at `30a98c6`, and the review-fix re-runs R1 to R5 ran
  at `a2950ce` with the sandbox callers pinned to that SHA (§11.4). Merging A also waits for
  `.github` CI to run green on its PR. **[v3.1]** Done: PR #9 is green at `99d93e5` (Facts).
- **The RELEASING.md amendments of §14 land before A merges or in the same review round**, as a
  workspace PR the supervisor merges just before A. A must not merge with RELEASING.md still
  describing a different behaviour. **[v3]** Still open (verification finding B1).
- **[v3]** B1 to B5 may be written in parallel with A. They merge only after A has merged,
  because each pins the SHA of A's squash commit on `.github` `main` (§2.4), which exists only
  then. While A is open, a B branch develops against the A branch head the supervisor hands it
  (§2.4 "Before A merges"), and its last commit before merge swaps every cascade reference to
  the `main` SHA the supervisor hands it. **[v3.1]** The supervisor merges a B only after the
  §10.1 "Pre-merge check" passes, including the `compare` check that the pin is on `main`.
- Before any B with a receiver merges, the supervisor sets the repo variable
  `CASCADE_DRY_RUN=true` in that repo (owner decision 22 covers this). The receiver is live only
  when the variable is exactly `false` (§9.1), so an unset variable is also a dry run, but the
  explicit `true` makes the state visible. The schedule must never fire a live run. **[v3]**
  Done for all four receivers (supervisor records, top).
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

**[v3]** Every later pin-bump PR is titled `ci(deps): pin the cascade to .github <first 7 of the
SHA>` (§2.4). `ci(deps)` does not release either.

---

## 2. Shared files in `.github`

### 2.1 Layout [v3]

```text
.github/actions/cascade-notify/action.yml   composite: notify downstream (run in the caller's cascade job)
.github/actions/cascade-publish/action.yml  composite: verify the plan, mint, act (run in the caller's cascade job)
.github/workflows/cascade-receive.yml       reusable (workflow_call): receiver jobs compute and gates
.github/workflows/cascade-gates.yml         reusable (workflow_call): per-PR gate status for pull_request_target
.github/actionlint.yaml                     ignores only actionlint 1.7.12's unknown job.workflow_* message, only in cascade-receive.yml
.github/scripts/cascade/wiring/lib.sh     fixed maps (§3), validation, mention lint, title rank
.github/scripts/cascade/wiring/notify.sh
.github/scripts/cascade/wiring/receive-compute.sh
.github/scripts/cascade/wiring/receive-publish.sh
.github/scripts/cascade/wiring/gates-eval.sh   (G2 and G3 evaluation; runs inside compute)
.github/scripts/cascade/wiring/gates-post.sh   (posts the statuses from gates.json)
.github/scripts/cascade/wiring/test/      offline tests (§12)
```

`cascade-notify.yml` does not exist (deleted when the §13.1 fallback was applied).

### 2.2 Rules for the two reusable workflows and the two composite actions [v3]

This section was rewritten for the composite actions. The pinning, permissions, `run:`, `gh`,
scratch-file and repo-name rules are version 2 unchanged except where marked.

- **Pinning.** Every third-party `uses:` is pinned to a full commit SHA, with a version comment.
  Reuse the SHAs the repos already use:
  - `actions/checkout` `3d3c42e5aac5ba805825da76410c181273ba90b1` (v7.0.1), the pin `.github`
    already uses. **[v3]** Only `.github` code (the reusable workflows and `cascade-publish`)
    checks anything out, and the callers have no checkout step of their own, so this is the
    only checkout pin Phase 3 adds. A B branch that edits an existing job (catalog_opm's
    `verify-published`) keeps that file's existing checkout pin, so each file has one pin.
  - `actions/create-github-app-token` `bcd2ba49218906704ab6c1aa796996da409d3eb1` (v3.2.0)
  - `actions/setup-go` `b7ad1dad31e06c5925ef5d2fc7ad053ef454303e` (v7.0.0)
  - `cue-lang/setup-cue` `a93fa358375740cd8b0078f76355512b9208acb1` (v1.0.1)
  - `go-task/setup-task` `3be4020d41929789a01026e0e427a4321ce0ad44` (v2.0.0)
  - **[v3]** `actions/upload-artifact` `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` (v7.0.1) and
    `actions/download-artifact` `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` (v8.0.1), as shipped.
  - **[v3]** The composite actions pin their own third-party steps the same way, so a caller in
    opm-operator (`sha_pinning_required`) passes for the nested steps too. **[v3.1]** Shown by
    E6's receiver run (down 37208176173 at `30a98c6`, with `sha_pinning_required: true` and the
    same nested `uses:` set); R1 ran with the setting off and is not evidence for this.
- **[v3.1] References to the cascade code** (`cascade-notify`, `cascade-publish`,
  `cascade-receive.yml`, `cascade-gates.yml`, and the `ref:` of the resolver checkout in each
  receiver's `cascade-task.yml`) are pinned by every repo to one full `.github` `main` commit
  SHA, written `@<SHA> # .github main` on a `uses:` line and `ref: <SHA> # .github main` on the
  checkout (§2.4).
- **Permissions.** Every job declares `permissions:` explicitly. opm-operator's default token is
  read-only, and nothing may rely on defaults. **[v3]** That includes the caller-owned
  `notify-downstream` and `publish` jobs (§4.6, §5.2).
- **No inline expressions in `run:`.** Never put `${{ }}` inside `run:`. Pass every context value
  through `env:` and quote it in the script. The payload, the PR titles and bodies, and the tags
  are all untrusted.
- **[v3] Where the scripts come from.** There is no input naming a `.github` ref.
  - The two composite actions run their scripts from
    `$GITHUB_ACTION_PATH/../../scripts/cascade/wiring/`. The runner downloads the whole `.github`
    repo at the action's pinned ref, so the scripts are the pinned commit's. The actions have no
    second checkout of `.github`.
  - Each `cascade-receive.yml` job has an `Own commit` step right after `Guard`. It reads
    `job.workflow_repository` and `job.workflow_sha` through `env:`, fails unless they are
    `open-platform-model/.github` and a 40-hex SHA, and writes the SHA to a step output. The
    `Check out org .github` step then checks out `open-platform-model/.github` at
    `ref: ${{ steps.own.outputs.sha }}`, `path: org-github`, `persist-credentials: false`. That
    checkout also holds the resolver (P2 §3, §11 C4). R1 showed `job.workflow_sha` is the
    called workflow's own SHA (scripts logged from `a2950ce6d…` in both down jobs).
  - `cascade-gates.yml` checks nothing out and needs no scripts.
  - So a pinned reference runs exactly that commit's workflow, action and scripts. Version 2's
    `org-github-ref` and its sandbox-only guard are removed everywhere.
- **Calling `gh`.** Scripts call `gh` only through `"${CASCADE_GH:-gh}"`, so tests can stub it (§12).
- **Scratch files.** Every file a job writes that is not a repo change (`gates.json`,
  `notes.md`, `body.md`, `plan.json`, `cascade.bundle`, `diff.patch`, the warnings file, the G2
  worktree) lives under `$RUNNER_TEMP/cascade/`, never under `repo/` or `org-github/`. A file
  inside `repo/` would make the task refuse a dirty tree (P2 §5.2 rule 1), be committed by
  `git add -A`, and be counted by the title as a changed path (P2 §4.2).
- **The repo name.** Every job **[v3] and every composite action** derives the repo name once,
  in its first step (`Guard`), from `GITHUB_REPOSITORY`: the owner part must be exactly
  `open-platform-model` and the name part must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`, or the job
  fails. The name is written to a step output, `repo`, and every later use (the §3.1 source, the
  §2.3 token scope, the §3 lookups) reads that output. `github.event.repository.name` is never
  used.
- **[v3] Secrets.** E1 showed a reusable-workflow job with `environment: cascade` sees the
  caller's Environment **variables** but not its **secrets** unless the caller passes
  `secrets: inherit` (E1 probe: no `secrets:` → empty; `secrets: inherit` → visible). The rule
  is therefore:
  - No reusable workflow declares `secrets:` or reads a secret, and no caller passes `secrets:`
    or `secrets: inherit` anywhere. (`inherit` was rejected because it hands every caller secret
    to the called workflow.)
  - The only secret, `CASCADE_APP_PRIVATE_KEY`, is read only in a **caller-owned** job that
    declares `environment: cascade` (`notify-downstream`, `publish`), and passed with
    `vars.CASCADE_APP_CLIENT_ID` as the `private-key` and `client-id` inputs of a cascade
    composite action, which mints the token itself.
  - Those caller-owned jobs run only the pinned action. They have no checkout and no `run:` step
    of their own, so no repo code runs in a job that holds the key. **[v3.1.1]** `cascade-publish`
    checks the repo out but never runs it. The jobs also have no `env:`, `container:` or
    `services:`, and their step no `env:`, so no `BASH_ENV` or image can bring repo code in; the
    wiring check asserts their exact keys (§10.1 item 6).
  - **[v3.1]** So "no secret is passed" is true only of the reusable calls. A repo text that says
    the notify or publish job "passes no secret" or "holds no secret" is wrong; §10.1 item 9
    gives the replacement wording. `compute` and `gates` do hold no secret, and text saying so
    stays.

### 2.3 Minting the App token

The token is minted only **[v3] inside a cascade composite action, run by a caller job** that
declares `environment: cascade`, and as the step directly before its first use, after every
check that could still stop the job. It is never passed between jobs, written to a file, or kept
past its job: `skip-token-revoke` is left unset, so it is revoked at job end.

| **[v3]** Action | `owner` | `repositories` | Permissions |
| --- | --- | --- | --- |
| `cascade-notify` | `open-platform-model` | the target list from §3.1, comma-separated | `permission-contents: write` (needed for `POST /dispatches`) |
| `cascade-publish` | `open-platform-model` | the `repo` step output (§2.2) | `permission-contents: write`, `permission-pull-requests: write`, `permission-issues: write` |

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

### 2.4 Pinning by SHA, and the bump procedure [v3.1; step 2 v3.1.1]

Version 2's §2.4 (`org-github-ref` and its sandbox-only guard) is removed. Owner decision 24
replaces `@main` for the actions:

> "Pin by SHA in all five repos": "Every repo pins the cascade actions by SHA (uniform,
> strongest); every change to the cascade actions then needs five manual bump PRs." (This
> supersedes the @main part of item 13 for the cascade actions.)

Decision 24 names the two actions. The supervisor extended it (review findings 2 and 5) to the
two reusable workflows, because M2 ties `cascade-receive.yml`'s scripts to its own SHA, so
`cascade-receive.yml` at one commit and `cascade-publish` at another would mix compute and
publish script versions across `plan.json`; and to the resolver checkout in each receiver's
`cascade-task.yml`, because CI at `main`'s resolver would test code the receiver does not run.
That extension is the supervisor's derivation, binding for Phase 3, and goes to the owner in the
phase report. The `.github` README "Pinning and bumps" (PR #9 at `99d93e5`) says the same, and
this section matches it:

- **The pin.** In core, catalog_opm, library, opm-operator and cli, every cascade reference names
  a full 40-character SHA of a commit on `.github` `main`, never a branch or a tag, followed by
  exactly ` # .github main`. The references are:
  - every `uses: open-platform-model/.github/.github/…` line:
    `uses: open-platform-model/.github/.github/actions/cascade-notify@<SHA> # .github main`;
  - in catalog_opm, library, opm-operator and cli, the `ref:` of the step in
    `.github/workflows/cascade-task.yml` that checks out `repository: open-platform-model/.github`:
    `ref: <SHA> # .github main`.
- **One SHA per repo.** All of a repo's cascade references carry the same SHA: 1 reference in
  core (notify), 5 in each receiver (notify, `cascade-receive.yml`, `cascade-publish`,
  `cascade-gates.yml`, the `cascade-task.yml` resolver `ref:`). §10.1 item 6 checks it in CI on
  every PR.
- **What a pin runs.** The pinned commit's workflow or action, and that commit's scripts and
  resolver (§2.2). CI's `cascade-task.yml` tests the repo's `deps:cascade` task against that same
  resolver. **[v3.1.1]** A merge to `.github` `main` therefore changes nothing in a product
  repo's cascade (its notify job, its receiver and gates callers, its `cascade-task.yml`) until
  that repo moves its pin. Two things are not pinned and change at once: `mention-guard`, which
  the org ruleset runs from `.github` `main` on every PR, and a laptop `task deps:cascade`, which
  uses the sibling `.github` checkout as it stands.
- **Dependabot.** A repo whose `.github/dependabot.yml` configures the `github-actions`
  ecosystem (library, opm-operator, cli) ignores `open-platform-model/.github*`, so Dependabot
  never moves one reference on its own and breaks "one SHA per repo" (§10.1 item 7).
- **The bump procedure** (README "Pinning and bumps", in this order):
  1. Merge the `.github` PR (it has passed its offline suites, §12: the resolver and wiring
     suites, the static checks, shellcheck and actionlint), then take the full SHA of the squash
     commit it made on `main` (`git rev-parse origin/main` right after fetching, or the PR's
     merge commit), and check it is on `main`:
     `gh api repos/open-platform-model/.github/compare/<SHA>...main --jq .status` must print
     `identical` or `ahead`. A branch commit that a squash merge left behind prints `diverged`
     (read back 2026-10-04: `99d93e5...main` prints `diverged`). **[v3.1.1]** `.github` is
     squash-only (Facts), so every merge leaves its branch commits `diverged`.
  2. **[v3.1.1] Canary: a dry-run pin bump in one receiver first** (owner decision 26; there is
     no sandbox step, no sandbox App and no re-arm). The supervisor picks one receiver
     (catalog_opm, library, opm-operator or cli; core has no receiver, so it is never the
     canary) and:
     1. sets that repo's variable `CASCADE_DRY_RUN` to `true` if it is not already (decision 22),
        and notes its old value;
     2. opens and merges that repo's pin PR as in steps 3 and 4;
     3. runs `gh workflow run deps-cascade.yml -R open-platform-model/<canary>` on `main` and
        checks the run: it succeeds, the `Compute` log shows
        `scripts from open-platform-model/.github <SHA>`, `Publish` is skipped, and the summary's
        mode and action match `task -x deps:cascade` run locally on that repo's `main`;
     4. checks that the next PR on the canary shows `cascade/freshness` and `cascade/settled`, and
        that its `cascade-task.yml` (by `workflow_dispatch`, which every receiver's file has)
        checks the resolver out at `<SHA>` and passes;
     5. sets `CASCADE_DRY_RUN` back to the old value, then moves on to step 3 for the other repos.

     While the canary is dry, its cascade PR does not move; the next real run or the daily sweep
     catches it up. **What the canary does not exercise:** a dry run skips the `publish` job,
     and notify runs only on a release, so a change to `cascade-publish` or `cascade-notify` runs
     against real GitHub for the first time on the canary's next live receiver run (publish) or
     on the next release of an upstream that pins it (notify). The offline suites (stub `gh`,
     local bare repos, §12) are the only evidence before that. The supervisor watches that first
     live run and rolls back (step 4) if it fails. **[v3.1.2]** So that the first live run is the
     canary's alone: when the `.github` diff touches `cascade-publish` or `cascade-notify`, the
     other repos stay on the old pin until the canary's first live publish run (for
     `cascade-publish`) or notify run (for `cascade-notify`) has succeeded. A diff that touches
     neither moves on to step 3 right after the dry-run checks above.
  3. In each of core, catalog_opm, library, opm-operator and cli (**[v3.1.1]** the canary first,
     step 2), open one PR titled
     `ci(deps): pin the cascade to .github <first 7 of the SHA>` that replaces the SHA in every
     cascade reference and changes nothing else, unless the `.github` change altered an input,
     in which case the caller edit rides the same PR. Find them with
     `grep -rn -A1 'open-platform-model/.github' .github/workflows`: the hits are the `uses:`
     lines and the `repository:` line of the `cascade-task.yml` checkout, whose `ref:` the `-A1`
     prints on the next line (comment lines also match and need no change). In that PR,
     `gh api repos/open-platform-model/.github/compare/<SHA>...main --jq .status` prints
     `identical` or `ahead`, and `task cascade:wiring:check` (§10.1 item 6) passes, before the PR
     is opened.
  4. Merge each after its CI is green, the "Verify the cascade wiring" step printed
     `cascade wiring: ok, .github <SHA> (.github main)`, and the `compare` check passes for the
     SHA it pins. After the canary, the order of the other four does not matter, because a repo
     runs only its own pin. **[v3.1.2]** "After the canary" means after its dry-run checks, or,
     for a diff touching `cascade-publish` or `cascade-notify`, after its first live publish or
     notify run succeeded (step 2). To roll back, move the pins back the same way (no canary needed for a
     rollback to a SHA the repo already ran).
- **Before A merges** (B branches only). No `.github` `main` commit carries the cascade yet. A B
  branch pins its cascade references to the A branch head the supervisor hands it (today
  `99d93e54608b9b8a6c469ee3b7c7fcffa391256b`; A may move again, so the supervisor's hand-off
  wins), with the comment ` # feat/add-release-cascade-workflows`, the same comment the sandbox
  seeds carry, and with `PIN_COMMENT='feat/add-release-cascade-workflows'` in its wiring check
  (§10.1 item 6), so its CI and any spike run against real code and stay green. After A merges,
  the supervisor hands each B the squash SHA, and the B's last commit before merge,
  `ci: pin the cascade to .github main`, replaces every SHA and comment with
  `<SHA> # .github main` and sets `PIN_COMMENT='.github main'`. A B never merges with a branch
  SHA or a branch comment; the §10.1 pre-merge check refuses it. **[v3.1.2]** Merging A deletes
  its branch (`delete_branch_on_merge: true`, Facts), so after that the branch SHA is reachable
  only through `refs/pull/9/head`, which is not relied on: each B makes its pin commit with the
  squash SHA right away.
- **[v3.1.1] Sandbox.** The sandboxes take no part in a bump (decision 26). Their callers keep
  the `a2950ce` pins with ` # feat/add-release-cascade-workflows`, they hold no key, and they are
  archived after Phase 3. Task 5.8's sandbox pin move and S1 rerun are dropped (§11.3).
  **[v3.1.2]** That those pins name a commit on a deleted branch does not matter, since nothing
  runs there again.
- **Why `main`-only commits matter.** The Environment's `main`-only branch policy and each
  product repo's `main` ruleset still decide who can make a key-holding job run. A pin to an
  unmerged `.github` commit would run code no `.github` review approved. **[v3.1.1]** Only a B
  branch carries one, and only before A merges: its key-holding jobs cannot run off `main` (the
  Environment refuses them, E1b), and the §10.1 pre-merge check refuses to merge it.

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

### 4.1 Composite action `cascade-notify` [v3]

```yaml
# .github/actions/cascade-notify/action.yml
inputs:
  tag:         {required: true}   # the release tag that was just published
  client-id:   {required: true}   # vars.CASCADE_APP_CLIENT_ID of the cascade Environment
  private-key: {required: true}   # secrets.CASCADE_APP_PRIVATE_KEY of the cascade Environment
runs:
  using: composite
```

The job (`runs-on`, `environment: cascade`, `timeout-minutes: 20`, `permissions:
{contents: read}`) is the caller's (§4.3). The steps, in order:

1. **Guard:** derive the repo name (§2.2). There is no ref guard and no checkout; the scripts run
   from `$GITHUB_ACTION_PATH/../../scripts/cascade/wiring/notify.sh`.
2. *(removed: the `org-github` checkout)*
3. **Validate** (`notify.sh validate --tag`).
   - The source is the repo name, and it must be in §3.1.
   - `tag` must match §3.3 for that source.
   - The targets are taken from §3.1 and written to a step output as a comma list.
4. **Go proxy wait, only when the source is `library`.** This step is best effort.
   - Poll `https://proxy.golang.org/github.com/open-platform-model/library/@v/<tag>.info` every
     30 s for up to 10 minutes.
   - On timeout, log a warning and continue. The step never fails.
   - The receiver's `--expect` wait (P2 §11 C2) and the daily sweep cover what is left.
5. **Check the token scope** (an empty target list fails), then **mint the token** as §2.3
   describes, scoped to the target list.
6. **Dispatch** to each target in turn by running `notify.sh dispatch`, which does this:
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

### 4.3 Caller job (same shape in every upstream) [v3]

```yaml
  notify-downstream:
    name: Notify downstream
    needs: <per repo, §4.5>
    if: <per repo, §4.5> && vars.CASCADE_NOTIFY != 'off'
    runs-on: ubuntu-latest
    environment: cascade
    timeout-minutes: 20
    permissions:
      contents: read
    steps:
      - name: Notify downstream
        uses: open-platform-model/.github/.github/actions/cascade-notify@<SHA> # .github main
        with:
          tag: <per repo, §4.5>
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

- **The caller owns the Environment job** (E1). It is an ordinary job, so it can and must set
  `environment: cascade`; the key reaches the action only as an input. Version 2's "the
  reusable job sets it" is wrong and RELEASING.md "Notify after publish" is amended (§14).
- The job has exactly one step, the pinned action. No checkout, no `run:`.
- The caller grants only `contents: read`. The App token does the work.
- The Environment's `main`-only policy applies to this job: a run from another ref fails at the
  deployment check before any step runs (E1b). Only cli can start one (its `workflow_dispatch`
  recovery path), which is why its `if:` carries the `github.ref` guard (§4.5).
- Every successful notify creates a `cascade` deployment record in the repo. That is expected.

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

**Sandbox up** (`cascade-sandbox-up`, §11): `needs: release` and
`if: success() && vars.CASCADE_NOTIFY != 'off'`. The tag is `inputs.version`. **[v3]** No
`org-github-ref`; the action is pinned to `a2950ce6d314618c108cfdf2e978133c2ab09f4a`.
**[v3.1.1]** It stays there: the sandbox holds no key and is archived after Phase 3 (decision 26).

### 4.6 Exact notify jobs per repo [v3, new]

Each block is appended to the end of the repo's `.github/workflows/release.yml` `jobs:` map,
indented two spaces, after the jobs it `needs`. A short comment above the job is allowed and
must describe the caller-owned Environment job (not "the shared workflow mints the token in its
own Environment job"). Everything else is byte-for-byte. `<SHA>` is the `.github` `main` squash
SHA (§2.4).

**core** (B1)

```yaml
  notify-downstream:
    name: Notify downstream
    needs: [release-please, publish-cue]
    if: needs.release-please.outputs.release_created == 'true' && vars.CASCADE_NOTIFY != 'off'
    runs-on: ubuntu-latest
    environment: cascade
    timeout-minutes: 20
    permissions:
      contents: read
    steps:
      - name: Notify downstream
        uses: open-platform-model/.github/.github/actions/cascade-notify@<SHA> # .github main
        with:
          tag: ${{ needs.release-please.outputs.tag_name }}
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

**catalog_opm** (B2; after the `verify-published` split, §4.5)

```yaml
  notify-downstream:
    name: Notify downstream
    needs: [release-please, publish-cue]
    if: ${{ !cancelled() && needs.publish-cue.outputs.published == 'true' && vars.CASCADE_NOTIFY != 'off' }}
    runs-on: ubuntu-latest
    environment: cascade
    timeout-minutes: 20
    permissions:
      contents: read
    steps:
      - name: Notify downstream
        uses: open-platform-model/.github/.github/actions/cascade-notify@<SHA> # .github main
        with:
          tag: ${{ needs.release-please.outputs.opm_tag_name }}
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

**library** (B3; the Go proxy wait runs inside the action when the repo is `library`)

```yaml
  notify-downstream:
    name: Notify downstream
    needs: release-please
    if: needs.release-please.outputs.releases_created == 'true' && vars.CASCADE_NOTIFY != 'off'
    runs-on: ubuntu-latest
    environment: cascade
    timeout-minutes: 20
    permissions:
      contents: read
    steps:
      - name: Notify downstream
        uses: open-platform-model/.github/.github/actions/cascade-notify@<SHA> # .github main
        with:
          tag: ${{ needs.release-please.outputs.tag_name }}
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

**opm-operator** (B4)

```yaml
  notify-downstream:
    name: Notify downstream
    needs: [release-please, publish-release]
    if: needs.release-please.outputs.releases_created == 'true' && vars.CASCADE_NOTIFY != 'off'
    runs-on: ubuntu-latest
    environment: cascade
    timeout-minutes: 20
    permissions:
      contents: read
    steps:
      - name: Notify downstream
        uses: open-platform-model/.github/.github/actions/cascade-notify@<SHA> # .github main
        with:
          tag: ${{ needs.release-please.outputs.tag_name }}
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

**cli** (B5)

```yaml
  notify-downstream:
    name: Notify downstream
    needs: [release-please, goreleaser]
    if: ${{ !cancelled() && needs.goreleaser.result == 'success' && github.ref == 'refs/heads/main' && vars.CASCADE_NOTIFY != 'off' }}
    runs-on: ubuntu-latest
    environment: cascade
    timeout-minutes: 20
    permissions:
      contents: read
    steps:
      - name: Notify downstream
        uses: open-platform-model/.github/.github/actions/cascade-notify@<SHA> # .github main
        with:
          tag: ${{ needs.release-please.outputs.tag_name || inputs.tag }}
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

What changed from version 2 in all five: `uses:` moves from the job (reusable
`cascade-notify.yml@main`) to a single step (action `cascade-notify@<SHA> # .github main`); the
job gains `runs-on: ubuntu-latest`, `environment: cascade` and `timeout-minutes: 20`; `with:`
gains `client-id` and `private-key`. `needs`, `if` and `tag` are version 2's §4.5, unchanged.

---

## 5. Receiver caller (`deps-cascade.yml`, per receiving repo) [v3]

The receiver caller has **two jobs**: `cascade`, which calls the reusable `cascade-receive.yml`
(compute and gates), and the caller-owned `publish`, which declares `environment: cascade` and
runs the `cascade-publish` action (E1, §13.1). The shape below is the `.github` README's
"Receiver caller", which the static suite checks against the sandbox seed.

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
    uses: open-platform-model/.github/.github/workflows/cascade-receive.yml@<SHA> # .github main
    with:
      dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
      gates-only: ${{ inputs.gates_only == true }}
      g2-mode: ${{ vars.CASCADE_G2_MODE || 'warn' }}
      g3-mode: ${{ vars.CASCADE_G3_MODE || 'warn' }}
      setup-go: <§5.1>

  publish:
    name: Publish
    needs: cascade
    if: >-
      !cancelled()
      && needs.cascade.outputs.compute-ok == 'true'
      && needs.cascade.outputs.dry-run == 'false'
      && inputs.dry_run != true
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
        uses: open-platform-model/.github/.github/actions/cascade-publish@<SHA> # .github main
        with:
          dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
          labels-managed: <§5.1>
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

- The caller reads `vars` itself, so nothing depends on how a called workflow sees `vars`.
- `inputs.dry_run` and `inputs.gates_only` are empty, and therefore false, on the dispatch and
  schedule triggers.
- **Dry run fails closed.** The receiver is live only when `CASCADE_DRY_RUN` is exactly `false`.
  Unset, deleted or any other value means dry run. Phase 4 sets `false`; it never deletes the
  variable.
- **The stop switch is enforced in `.github` code** (verification M1, review-fix `a2950ce`).
  `cascade-publish`'s required `dry-run` input gets the same expression as the reusable job's
  `dry-run`, byte for byte:
  `${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}`. The action publishes only
  when the value is exactly `false`, does nothing and exits 0 on `true`, and fails before the
  mint on any other value (§6.4). A mistyped `if:` therefore cannot make a dry run publish.
- **The `publish` `if:`** repeats the switches only so that a dry run does not start a `cascade`
  Environment job (and leave a deployment record). It reads `inputs` and `vars` itself, and the
  reusable job's outputs only as an extra filter, never as the switch: those outputs come from
  the job that ran repo code (§6.2, m3). The `if:` is byte-for-byte as above in every receiver.
- **`compute-ok`** is `true` only when every `compute` step succeeded (its last step sets it), so
  `!cancelled()` plus `compute-ok == 'true'` replaces version 2's
  `needs.compute.result == 'success'`. A caller sees only the called workflow's overall result,
  which also counts the `gates` job; `!cancelled()` keeps a failed `gates` job from skipping
  `publish`.
- `publish` has no checkout or `run:` step of its own (§2.2). The action checks out the repo
  with `GITHUB_TOKEN` (`contents: read`) and downloads `cascade-plan` from the same run, which
  needs no extra permission (shown in the sandbox runs). It never runs the checked-out code.
  **[v3.1.1]** Nothing in the job may make the action's bash steps run it either: a job-level
  `env:` (for example `BASH_ENV: repo/x.sh`), a `container:` or `services:`, or a step-level
  `env:` would; the wiring check refuses all of them by exact key sets (§10.1 item 6), and the
  workflow-level `env:` and `defaults:` by `deps-cascade.yml`'s exact top-level keys.
- **No `secrets:`** on either job, and never `secrets: inherit` (§2.2).
- **Concurrency.** Real runs on `main` (dispatch, schedule, manual) share the RELEASING.md group
  `deps-cascade`: one run active and one pending. Two other kinds of run get their own groups,
  so they can never replace a pending real run:
  - gates-only runs on `main` (§8.3) use `deps-cascade-gates`;
  - runs from any other ref (always dry runs) use `deps-cascade-<ref>`.
  S11 showed it: the gates-only run and a pending dispatch run coexisted, and the pending run
  kept its payload. The group expression above is byte-for-byte; the static suite checks it in
  the README and the seed, and each B asserts its own with `yq`.
- Within `deps-cascade`, a newer pending run still replaces an older pending one, as RELEASING.md
  accepts. What the replaced run loses is bounded: the version is re-resolved, the breaking label
  comes from the full pin range (§7.4), not the payload, and only its `CASCADE_EXPECT` wait and
  its "Triggering releases" line are lost. The next dispatch or the sweep covers both.

### 5.1 Per-repo values [v3]

| Repo | cron | `setup-go` (reusable `cascade` job) | `labels-managed` (`cascade-publish` step) |
| --- | --- | --- | --- |
| catalog_opm | `17 5 * * *` | false | false |
| library | `17 5 * * *` | false | false |
| opm-operator | `47 5 * * *` | true | false |
| cli | `17 6 * * *` | true | true |
| cascade-sandbox-down | none (it uses `workflow_dispatch`) | false | false |

- **`labels-managed` moved** from the reusable workflow to the `cascade-publish` action (a string
  input, default `'false'`). `cascade-receive.yml` no longer has a `labels-managed` input, so
  passing it there is an actionlint error and a run failure. cli passes `labels-managed: true`
  to the action; the other three pass `labels-managed: false` explicitly.
- The crons are off the top of the hour and staggered by tier.
- `setup-cue` defaults to true with `cue-version` `v0.17.1`. The sandbox sets `setup-cue: false`.
  A receiver may pass `cue-version` explicitly when it pins its CUE version (catalog_opm does,
  `v0.17.1`); then the value moves with its other CUE pins.
- The reusable workflow installs Task (`3.x`) always. It checks that `yq --version` reports
  mikefarah and fails otherwise.

### 5.2 Exact receiver workflows per repo [v3, new]

Each is the whole `.github/workflows/deps-cascade.yml`, except that a header comment between
`name:` and `on:`, and short comments above a `with:` value, are allowed. A comment must not say
that the reusable workflow publishes, mints a token or declares the Environment. Every other
line is byte-for-byte. `<SHA>` is the `.github` `main` squash SHA (§2.4), the same SHA in both
`uses:` lines, in the repo's notify and gates callers, and **[v3.1]** in the `ref:` of its
`cascade-task.yml` resolver checkout.

The four files differ only in the cron, `setup-go`, `labels-managed` and catalog_opm's
`cue-version`. The common part is §5's block; the per-repo `jobs:` maps follow in full.

**catalog_opm** (B2): `cron: '17 5 * * *'`, and

```yaml
jobs:
  cascade:
    name: Deps cascade
    permissions:
      contents: read
      pull-requests: read
      statuses: write
    uses: open-platform-model/.github/.github/workflows/cascade-receive.yml@<SHA> # .github main
    with:
      dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
      gates-only: ${{ inputs.gates_only == true }}
      g2-mode: ${{ vars.CASCADE_G2_MODE || 'warn' }}
      g3-mode: ${{ vars.CASCADE_G3_MODE || 'warn' }}
      setup-go: false
      cue-version: v0.17.1

  publish:
    name: Publish
    needs: cascade
    if: >-
      !cancelled()
      && needs.cascade.outputs.compute-ok == 'true'
      && needs.cascade.outputs.dry-run == 'false'
      && inputs.dry_run != true
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
        uses: open-platform-model/.github/.github/actions/cascade-publish@<SHA> # .github main
        with:
          dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
          labels-managed: false
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

**library** (B3): `cron: '17 5 * * *'`, and

```yaml
jobs:
  cascade:
    name: Deps cascade
    permissions:
      contents: read
      pull-requests: read
      statuses: write
    uses: open-platform-model/.github/.github/workflows/cascade-receive.yml@<SHA> # .github main
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
        uses: open-platform-model/.github/.github/actions/cascade-publish@<SHA> # .github main
        with:
          dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
          labels-managed: false
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

**opm-operator** (B4): `cron: '47 5 * * *'`, and

```yaml
jobs:
  cascade:
    name: Deps cascade
    permissions:
      contents: read
      pull-requests: read
      statuses: write
    uses: open-platform-model/.github/.github/workflows/cascade-receive.yml@<SHA> # .github main
    with:
      dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
      gates-only: ${{ inputs.gates_only == true }}
      g2-mode: ${{ vars.CASCADE_G2_MODE || 'warn' }}
      g3-mode: ${{ vars.CASCADE_G3_MODE || 'warn' }}
      setup-go: true

  publish:
    name: Publish
    needs: cascade
    if: >-
      !cancelled()
      && needs.cascade.outputs.compute-ok == 'true'
      && needs.cascade.outputs.dry-run == 'false'
      && inputs.dry_run != true
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
        uses: open-platform-model/.github/.github/actions/cascade-publish@<SHA> # .github main
        with:
          dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
          labels-managed: false
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

**cli** (B5): `cron: '17 6 * * *'`, and

```yaml
jobs:
  cascade:
    name: Deps cascade
    permissions:
      contents: read
      pull-requests: read
      statuses: write
    uses: open-platform-model/.github/.github/workflows/cascade-receive.yml@<SHA> # .github main
    with:
      dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
      gates-only: ${{ inputs.gates_only == true }}
      g2-mode: ${{ vars.CASCADE_G2_MODE || 'warn' }}
      g3-mode: ${{ vars.CASCADE_G3_MODE || 'warn' }}
      setup-go: true

  publish:
    name: Publish
    needs: cascade
    if: >-
      !cancelled()
      && needs.cascade.outputs.compute-ok == 'true'
      && needs.cascade.outputs.dry-run == 'false'
      && inputs.dry_run != true
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
        uses: open-platform-model/.github/.github/actions/cascade-publish@<SHA> # .github main
        with:
          dry-run: ${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != 'false' }}
          labels-managed: true
          client-id: ${{ vars.CASCADE_APP_CLIENT_ID }}
          private-key: ${{ secrets.CASCADE_APP_PRIVATE_KEY }}
```

**What changed from version 2** in all four:

- `cascade-receive.yml@main` becomes `cascade-receive.yml@<SHA> # .github main`.
- `labels-managed` leaves the `cascade` job's `with:` (the input no longer exists there) and goes
  to the `cascade-publish` step.
- The new `publish` job (the whole block) is added.
- Header comments that say "the reusable publish job declares the cascade Environment itself" or
  "the shared workflow mints the App token" become wrong and must be rewritten.
- Unchanged: the triggers, `permissions: {}`, the concurrency block, the `cascade` job's name,
  permissions and its four switch inputs, and the crons.

**[v3.1] Each B asserts these shapes with `yq` in CI on every PR** (review finding 4), through
`task cascade:wiring:check` run as a step of the repo's existing required job (§10.1 item 6,
which gives the script verbatim). A verify step or a local-only test does not count, because a
later edit to the `if:` or the steps would go unchecked (the M1 risk). The assertions: for
`publish` (receivers) and `notify-downstream` (all five, so core gets the notify subset),
`environment == "cascade"`, `steps | length == 1`, permissions exactly
`{contents: read, pull-requests: read}` (publish) or `{contents: read}` (notify), the step's
`uses` matching `^open-platform-model/\.github/\.github/actions/cascade-(notify|publish)@[0-9a-f]{40}$`,
and the `client-id` and `private-key` inputs; **[v3.1.1]** the job's keys exactly `environment`,
`if`, `name`, `needs`, `permissions`, `runs-on`, `steps`, `timeout-minutes`, the step's keys
exactly `name`, `uses`, `with`, and the `with` keys exactly the action's inputs as passed here
(`tag`, `client-id`, `private-key`; `dry-run`, `labels-managed`, `client-id`, `private-key`);
`deps-cascade.yml`'s top-level keys exactly `concurrency`, `jobs`, `name`, `on`, `permissions`;
no `BASH_ENV`, `ENV` or `NODE_OPTIONS` in `release.yml`'s workflow-level `env`; no other value in any workflow passes
`secrets.CASCADE_APP_PRIVATE_KEY` and no other job declares `environment: cascade`; no call into
`.github` has a `secrets` key; the `concurrency.group` string, `jobs.publish.if` and the
`dry-run` value in both jobs equal §5; and every `.github` reference (`uses:` lines and the
`cascade-task.yml` resolver `ref:`) carries the same 40-hex SHA and the §2.4 comment.

---

## 6. Reusable `cascade-receive.yml`

### 6.1 Interface [v3]

```yaml
on:
  workflow_call:
    outputs:
      action:     {value: jobs.compute.outputs.action}   # push, recreate, close, conflict, too_long, skip, noop or gates-only
      dry-run:    {value: jobs.compute.outputs.dry_run}  # true when compute planned a dry run (forced off main)
      compute-ok: {value: jobs.compute.outputs.ok}       # true only when every compute step succeeded
    inputs:
      dry-run:        {type: boolean, required: true}
      gates-only:     {type: boolean, required: false, default: false}
      g2-mode:        {type: string,  required: false, default: warn}   # warn | enforce
      g3-mode:        {type: string,  required: false, default: warn}   # warn | enforce
      setup-go:       {type: boolean, required: false, default: false}  # go-version-file: repo/go.mod
      setup-cue:      {type: boolean, required: false, default: true}
      cue-version:    {type: string,  required: false, default: v0.17.1}
```

Removed from version 2: the inputs `labels-managed` (now on `cascade-publish`, §5.1) and
`org-github-ref` (§2.4). Added: the three outputs, which the caller's `publish` `if:` reads.

A mode value other than `warn` or `enforce` makes `compute` fail.

It has **two** jobs; the third, `publish`, is the caller's own job running the `cascade-publish`
action (§5, §6.4):

| Job | Name | Environment | Permissions | Holds the App key |
| --- | --- | --- | --- | --- |
| `compute` | `Compute` | none | `contents: read`, `pull-requests: read` | no |
| `gates` | `Post gates` | none | `contents: read`, `statuses: write`, `pull-requests: read` | no (it uses `GITHUB_TOKEN`) |
| caller `publish` | `Publish` | `cascade` | `contents: read`, `pull-requests: read` | yes, minted inside the action |

The caller's `cascade` job grants `contents: read`, `pull-requests: read`, `statuses: write`,
which covers both reusable jobs.

### 6.2 `compute`

`compute` runs with a 45-minute timeout. It runs repo code (the task) and holds no secret. All
scratch files go under `$RUNNER_TEMP/cascade/` (§2.2), written `$T` below.

1. **Guards.** **[v3]** `Guard` derives the repo name (§2.2); `Own commit` reads
   `job.workflow_sha` (§2.2). There is no ref guard. `Init` then sets `effective_dry_run` to
   `inputs.dry-run`, or to true when `github.ref != 'refs/heads/main'`. A branch run is always a
   dry run, because the Environment would refuse it anyway (E1b proves that refusal; E1's branch
   run showed `effective_dry_run: true` and Publish skipped).
2. **Check out:**
   - the repo at `path: repo`, with `fetch-depth: 0` and `persist-credentials: false`;
   - **[v3]** `org-github` at the `Own commit` SHA (§2.2).
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
       job. **[v3]** On exit 3, `repo_task` drops go-task's
       `::error title=Task '…' failed::exit status 3` line, so a no-change sweep shows no red
       annotation (R5: zero `##[error]` lines). Every other exit code keeps its annotation.
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
    - The job outputs are `action` and `dry_run` (`effective_dry_run`), **[v3]** plus `ok`,
      set by the job's last step (`Done`), so it is `true` only when every step succeeded. The
      workflow exposes them as `action`, `dry-run` and `compute-ok` (§6.1).
    - **[v3] These outputs are untrusted** (verification m3): repo code ran in the `Gates` and
      `Run the task` steps and can write the runner's env, path and output files, so it can
      forge `action`, `dry_run` and `ok`, and later compute steps that hold the read-only
      `GH_TOKEN` can run its code. The damage is bounded by compute's read-only permissions,
      by the caller's `publish` `if:` reading `inputs` and `vars` itself (§5), by the action's
      own `dry-run` input (§6.4), and by `verify` (§6.4 step 2). The same holds for
      `gates.json` before G2 and G3 become required checks (Phase 5, §15).
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
- Otherwise it runs `gates-post.sh` with `GH_TOKEN: ${{ github.token }}` (§8.4). **[v3]**
  `gates-post.sh` posts only on heads of PRs that are still open same-repo release PRs when it
  runs, so a stale `gates.json` entry never lands on a closed PR's head.
- It runs in dry run and in gates-only runs too. Statuses are not pushes.
- **[v3]** Its steps are `Guard`, `Own commit`, `Check out org .github` (at the own SHA),
  `Download the gate results` (`continue-on-error`), and `Post the statuses`. Timeout 10
  minutes.

### 6.4 `publish` [v3]

`publish` is no longer a job of `cascade-receive.yml`. It is the caller's `publish` job (§5,
exact YAML in §5.2) running the composite action `cascade-publish`:

```yaml
# .github/actions/cascade-publish/action.yml
inputs:
  dry-run:        {required: true}                    # exactly false publishes; true publishes nothing; anything else fails
  labels-managed: {required: false, default: 'false'} # cli: true
  client-id:      {required: true}
  private-key:    {required: true}
runs:
  using: composite
```

- The caller job: `needs: cascade`, the §5 `if:`, `environment: cascade`,
  `permissions: {contents: read, pull-requests: read}`, a 15-minute timeout.
- It runs only `git`, `gh`, `jq` and the scripts at the action's own commit
  (`$GITHUB_ACTION_PATH/../../scripts/cascade/wiring/receive-publish.sh`). It never runs a repo
  task or repo code.
- **`plan.json` is untrusted.** `compute` ran repo code, which could have rewritten the plan
  before the upload. `publish` therefore re-derives everything it can and treats the plan as a
  request, not an order.
- **The `dry-run` input is the stop switch** (verification M1). `receive-publish.sh` reads it
  (as `CASCADE_PUBLISH_DRY_RUN`) in both `verify` and `act`:
  - exactly `false`: publish;
  - exactly `true`: write a notice, set `publish=false`, skip the mint and `Act`, exit 0;
  - any other value (empty, missing, `False`, `TRUE`, `" false"`, `"false "`): fail in `verify`
    before the mint; `act` also refuses on its own.
  - GitHub does not enforce `required` on a composite action input, so the script's refusal of
    an empty value is the enforcement. **[v3.1]** R2's empty dispatch was replaced by the probe
    workflow's own input default (`probe-dry.yml` at `fb8e76c`, `default: 'true'`), not by
    GitHub or the action, so empty and missing are covered offline only; the action has no
    default and refuses an empty value.

The steps:

1. **[v3]** `Guard` (repo name, §2.2); `Main only` (fails unless `GITHUB_REF` is
   `refs/heads/main`, even if a caller's `if:` forgot it); check out the repo (`path: repo`,
   `fetch-depth: 0`, `persist-credentials: false`); download `cascade-plan` to
   `$RUNNER_TEMP/cascade/plan`. No `.github` checkout. Then `Verify the plan` with the
   `dry-run` input; it also sets `publish=false` when the plan says `effective_dry_run` or when
   `deps-cascade:hold` appeared on the PR since compute (that is not an error).
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

**[v3] Decided: `WF_GUARD_RULE=tree`** (commit `30a98c6`, `lib.sh` line 39). E4c accepted both
pushes (down runs 37207063750 and 37207085490): an in-place lease update across `main`'s workflow
change, and merge commit `c086837`, which touches `touch.yml` relative to its first parent. E5
(`update-branch` with the App token) was also accepted; it stays unused. `strict` stays in the
code and is tested through a copy of the scripts with the rule swapped.

What `tree` means in practice (this corrects sandbox deviation 3, per verification m1):

| Mode | `D1` empty | `D1` non-empty |
| --- | --- | --- |
| `fresh` | `push` | job error (the task never touches `.github/`) |
| `rebuild` | `push` (in place, whatever `D2` is) | job error |
| `recreate` | `recreate` | job error |
| `merge` | `push` (merge commit, whatever `D2` is) | `conflict`, `conflict_reason=workflows` |

- A workflow change on `main` alone no longer causes `recreate` or `conflict`; the branch is
  rebuilt or merged in place (E3/E4 (a) and (b) under `tree`, runs 37207979847 and 37207816358).
- `recreate` happens only when `OLD` is set and no cascade PR is open, that is a closed PR's
  leftover branch (§7.1).
- `conflict` (workflows) still happens in `merge` mode when the branch itself differs from `main`
  under `.github/workflows/`, for example a human workflow commit on `deps/cascade`.
- Under `tree`, C-recreate is never posted: action `recreate` then comes only from mode
  `recreate`, which by definition has no open PR to comment on (§6.4 `recreate` step 1). Its
  text stays for the `strict` copy. Nothing for the B branches.

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

### 8.3 Per-PR caller (`cascade-gates.yml` in each of the four receivers) [v3: pin and inputs only]

The whole file, identical in catalog_opm, library, opm-operator and cli (a header comment
between `name:` and `on:` is allowed; every other line byte-for-byte):

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
    uses: open-platform-model/.github/.github/workflows/cascade-gates.yml@<SHA> # .github main
    with:
      g2-mode: ${{ vars.CASCADE_G2_MODE || 'warn' }}
      g3-mode: ${{ vars.CASCADE_G3_MODE || 'warn' }}
```

The reusable `cascade-gates.yml` has one job with no checkout of anything, so no PR code ever
runs. It takes the inputs `g2-mode` and `g3-mode` only (**[v3]** `org-github-ref` is gone). It
has `permissions: {statuses: write, actions: write}` and a 5-minute timeout. **[v3]** What
changed from version 2 in the caller: only `@main` → `@<SHA> # .github main`.

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
- It inlines its small script and needs no `.github` checkout.
- **[v3]** E7 (sandbox, private `cascade-sandbox-down`, PR 2): a Dependabot
  `pull_request_target` run's token had `statuses: write` and posted `n/a`. The product repos are
  public, so this is a proxy (verification n2); it is not a Phase 5 blocker.
- **[v3]** S7: on a fake `release-please--x` PR with the pin behind, `cascade/freshness` showed
  `WARN: behind: up v0.9.0→v0.10.0`.

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

- **[v3] Where it is enforced.** Three places read the switch, from `inputs` and `vars` only:
  the reusable `dry-run` input (compute plans a dry run), the caller `publish` job's `if:` (no
  Environment job starts), and `cascade-publish`'s required `dry-run` input (the action refuses
  to mint unless it is exactly `false`). The last one is in `.github` code, so a typo in one
  repo's `if:` cannot make it live (§5, §6.4). Sandbox: R1 (`CASCADE_DRY_RUN=true`, plan
  `effective_dry_run: true`, Publish skipped, `deps/cascade` unchanged), R2 (action with `true`:
  notice, no mint, success; with `False`: refused before the mint), R3 (`false`: one PR update
  by the bot).
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

## 10. Per-repo join checklist (B1 to B5) [v3]

| | core | catalog_opm | library | opm-operator | cli |
| --- | --- | --- | --- | --- | --- |
| `release.yml` notify job (§4.5, exact §4.6) | yes | yes, after the split | yes | yes | yes |
| `verify-published` split | | yes | | | |
| `deps-cascade.yml` (§5, exact §5.2) | | yes, `cue-version` | yes | yes, `setup-go` | yes, `setup-go`; `labels-managed: true` on `cascade-publish` |
| `cascade-gates.yml` (§8.3) | | yes | yes | yes | yes |
| `labels.yml` | | | | | already declares all; unchanged |
| repo var `CASCADE_DRY_RUN=true` before merge (supervisor; live only at exactly `false`) | | done | done | done | done |
| **[v3.1]** `cascade-task.yml` resolver `ref:` pinned (§2.4, §10.1 item 3) | | yes | yes | yes | yes |
| **[v3.1]** cascade references, all one SHA (§2.4) | 1 | 5 | 5 | 5 | 5 |
| **[v3.1]** `task cascade:wiring:check` in the required CI job (§10.1 item 6) | yes, notify subset | yes | yes | yes | yes |
| **[v3.1.1]** `cascade:wiring:check` in the aggregate `check` task (§10.1 item 6) | yes | yes | yes | none (no aggregate task; CI step only) | yes |
| **[v3.1]** Dependabot ignore `open-platform-model/.github*` (§10.1 item 7) | | | yes | yes | yes |

- Each B has an OpenSpec change with a spec delta, as the repo's workspace requires. The B2
  delta covers the verify split as its own requirement.
- Each B runs the repo's own lint on workflows (actionlint where the repo has it). It also runs
  `actionlint` from the scratchpad binary on the new files. **[v3]** actionlint does not check
  that a composite action's inputs exist, so the §5.2 `yq` assertions are the check for
  `cascade-publish`'s `dry-run`, `labels-managed`, `client-id` and `private-key`.
- None of the new jobs becomes a required check. **[v3.1]** The wiring check is not a new job
  or context: it is a step in the existing required job (§10.1 item 6).
- **[v3]** Before A merges, a B pins the A branch head the supervisor hands it (§2.4 "Before A
  merges"); its last commit before merge swaps to the `main` SHA. **[v3.1]** The supervisor
  merges a B only after the §10.1 "Pre-merge check" passes, whose step 2 is
  `gh api repos/open-platform-model/.github/compare/<SHA>...main --jq .status` printing
  `identical` or `ahead`.
- Verification after merge, done by the supervisor:
  - **[v3.1]** `gh api repos/open-platform-model/.github/compare/<SHA>...main --jq .status`
    for the SHA now on the repo's `main` prints `identical` or `ahead`.
  - `gh workflow run deps-cascade.yml -R open-platform-model/<repo> -f dry_run=true`. The summary
    must show mode `fresh` and action `noop` (or the expected diff). **[v3]** The `Publish` job
    must show as skipped, and the `Compute` log must show
    `scripts from open-platform-model/.github <SHA>` with the repo's pinned SHA.
  - `cascade/freshness` and `cascade/settled` must appear on the next PR.
  - **[v3.1]** The repo's next `cascade-task.yml` run (or a `workflow_dispatch` of it, if it has
    one) checks the resolver out at `<SHA>`.
- **[v3] opm-operator:** decision 24 settles E6. With every cascade reference pinned by SHA and
  every third-party step inside the actions pinned by SHA, `sha_pinning_required: true` stays on
  and refuses nothing. No owner action is left for opm-operator.

### 10.1 Join checklist for the existing `join-release-cascade` branches [v3.1, rewritten; items 3, 6, 9, 11 and the pre-merge check v3.1.1]

All five branches were written to version 2 and none has merged. Each applies every item that
names it, on its own branch, in commits of its own (one commit per item group is fine), before
review. Items 1, 2 and 6 to 11 apply to all five; items 3 to 5 to the four receivers
(catalog_opm, library, opm-operator, cli). Branch heads checked on 2026-10-04: core `e88d3d2`,
catalog_opm `c6b314e`, library `4ca8064`, opm-operator `af5a103`, cli `c513fa8`.

**Per-repo facts** used below:

| | core (B1) | catalog_opm (B2) | library (B3) | opm-operator (B4) | cli (B5) |
| --- | --- | --- | --- | --- | --- |
| `RECEIVER` in the wiring check | `false` | `true` | `true` | `true` | `true` |
| cascade references (one SHA) | 1 | 5 | 5 | 5 | 5 |
| required job that runs the wiring check (file, job id, context) | `ci.yml` `ci`, "Validate schema" | `ci.yml` `ci`, "Validate catalog" | `test.yml` `test`, "Go tests" | `lint.yml` `lint`, "Lint" | `pr.yml` `lint`, "Lint" |
| `.github/dependabot.yml` `github-actions` ignore | none (no file; do not add one) | none (no file; do not add one) | add | add | add |
| `cascade-task.yml` resolver `ref:` to pin | none (no file) | yes | yes | yes | yes |
| `deps-cascade.yml` per-repo values (§5.1) | | cron `17 5 * * *`, `setup-go: false`, `cue-version: v0.17.1`, `labels-managed: false` | cron `17 5 * * *`, `setup-go: false`, `labels-managed: false` | cron `47 5 * * *`, `setup-go: true`, `labels-managed: false` | cron `17 6 * * *`, `setup-go: true`, `labels-managed: true` |

`<SHA>` below is the SHA of §2.4: the A branch head the supervisor hands the B while A is open
(comment `feat/add-release-cascade-workflows`), and the `.github` `main` squash SHA in the B's
final commit (comment `.github main`).

**1. `release.yml` notify job (all five).** Replace the `notify-downstream` job with the repo's
§4.6 block, byte for byte except `<SHA>` and the comment form of §2.4. It is the last job of the
`jobs:` map. A comment above the job may say only that the job is caller-owned, declares
`environment: cascade`, and passes the key to the pinned `cascade-notify` action as an input.
catalog_opm first applies the `verify-published` split (§4.5) in its own commit.

**2. Pin (all five).** Every `uses: open-platform-model/.github/.github/…` line in the repo
carries `@<SHA>` and the §2.4 comment, and every one carries the same `<SHA>`. Nothing names
`@main`, a branch or a tag.

**3. `cascade-task.yml` resolver pin (receivers).** In `.github/workflows/cascade-task.yml`, the
step with `repository: open-platform-model/.github` changes only its `ref:` line, from
`ref: main` to:

```yaml
          ref: <SHA> # .github main
```

(the branch comment while A is open). Its `actions/checkout` pin stays as it is (catalog_opm
`de0fac2e…` v6.0.2, the others `3d3c42e5…` v7.0.1). Rewrite the file's text that says the
resolver comes from `.github` `main` (the header comment) to say it comes from the pinned
`.github` commit.

**[v3.1.1]** library and opm-operator also carry a fallback that skips S5 when the resolver is
missing, written for the time before the resolver reached `.github` `main`. With the `ref:` pinned
to a commit that has it, the fallback is dead code that would turn a bad pin into a silent skip,
so it goes:

- **library** (`Cascade task tests (full set)` step): delete the comment above the step that says
  S5 runs against the real resolver "once open-platform-model/.github ships it on main, and prints
  SKIP S5 until then", and in its `run:` replace the `if [ -x "$real" ] … else … fi` block with
  ```bash
          [ -x "$real" ] || { echo "::error::no cascade resolver at the pinned .github commit" >&2; exit 1; }
          export CASCADE_RESOLVER_REAL="$real"
  ```
- **opm-operator** (`Point S5 at the resolver` step): delete the comment above it ("S5 runs only
  once the resolver is on .github main; until then the scenario reports SKIP"), and replace the
  `if [ -x "$r" ] … else … fi` block with
  ```bash
          [ -x "$r" ] || { echo "::error::no cascade resolver at the pinned .github commit" >&2; exit 1; }
          echo "CASCADE_RESOLVER_REAL=$r" >> "$GITHUB_ENV"
  ```

catalog_opm and cli already set `CASCADE_RESOLVER_REAL` unconditionally and have no fallback.

**4. `deps-cascade.yml` (receivers).** Make the file the §5 block with the repo's §5.2 `jobs:`
map and §5.1 values: pin `cascade-receive.yml` and `cascade-publish` per item 2; remove
`labels-managed` from the `cascade` job's `with:`; add the whole `publish` job. A header comment
between `name:` and `on:` and short comments above a `with:` value are allowed; none may say the
reusable workflow publishes, mints a token or declares the Environment. cli moves its
`labels-managed: true` and the `.github/labels.yml` comment to the `cascade-publish` step.

**5. `cascade-gates.yml` (receivers).** Only the `uses:` line changes, to
`uses: open-platform-model/.github/.github/workflows/cascade-gates.yml@<SHA> # .github main`
(§8.3). Every other line stays byte for byte.

**6. The wiring check, run in CI on every PR (all five).** This is what keeps the key-holding
jobs locked after merge (review finding 4); a verify step or a local-only test does not count.
**[v3.1.2]** The join changes apply the supervisor's addendum on top of the script below: the
`release.yml` workflow-`env` deny-list becomes a per-repo allow-list (core `CUE_VERSION`,
`CUE_REGISTRY`; catalog_opm `OPM_REGISTRY`, `CUE_REGISTRY`; opm-operator `REGISTRY`,
`IMAGE_NAME`, `CUE_VERSION`; library and cli none), and every key-holding job
(`notify-downstream`, `publish`) must have `runs-on: ubuntu-latest`. The check guards against
mistakes; review plus the `main` ruleset guard against a deliberate edit.

- Add the file `.tasks/cascade/wiring-check.sh` (core creates `.tasks/cascade/`) with exactly
  the content below, changing only `RECEIVER` (core: `RECEIVER=false`) and, while A is open,
  `PIN_COMMENT='feat/add-release-cascade-workflows'`. It is shellcheck-clean (v0.11.0) and was
  run against a cli-shaped and a core-shaped fixture built from §4.6, §5.2 and §8.3 (both pass)
  and 13 mutations (all refused: a changed `publish` `if:`, an extra `publish` step, notify
  `contents: write`, `secrets: inherit` on the receive call, the key read by another job, a
  second SHA, `@main`, `ref: main` on the resolver, a branch comment, `environment` dropped,
  `environment: cascade` on another job, a literal `dry-run: false`, a changed concurrency
  group). **[v3.1.1]** Re-run on 2026-10-04 with mikefarah yq v4.53.3: both fixtures pass; the
  13 mutations above plus 11 new ones are all refused (`env: {BASH_ENV: repo/x.sh}` on
  `publish`, a workflow-level `env:` and a `defaults:` in `deps-cascade.yml`, `container:` on
  `notify-downstream`, `services:` on `publish`, a step-level `env:` on the notify step, an
  `if:` on the publish step, an extra `with:` key on the publish step, and `BASH_ENV`, `ENV` or
  `NODE_OPTIONS` in `release.yml`'s workflow `env`); two allowed edits still pass (a
  `CUE_VERSION` in `release.yml`'s workflow `env`, a header comment in `deps-cascade.yml`); and
  the five repos' real `origin/main` workflows with the §4.6, §5.2 and §8.3 blocks applied (the
  reviewer's fixtures) all pass, including the existing workflow `env` in core, catalog_opm and
  opm-operator `release.yml`.

```bash
#!/usr/bin/env bash
# Checks the release-cascade caller shapes on every PR (Phase 3 wiring contract
# version 3.1, sections 5.2 and 10.1). Run from the repo root by
# `task cascade:wiring:check`; needs mikefarah yq v4. Prints every mismatch,
# then exits 1 if there was one.
# shellcheck disable=SC2016 # the single-quoted ${{ }} strings are GitHub expressions, compared literally
set -euo pipefail

RECEIVER=true              # core: false (notify only)
PIN_COMMENT='.github main' # before A merges: 'feat/add-release-cascade-workflows'

W=.github/workflows
yq --version | grep -q mikefarah || { echo "mikefarah yq v4 is required" >&2; exit 1; }

fail=0
bad() { echo "cascade wiring: $*" >&2; fail=1; }
eq() { [ "$2" = "$3" ] || bad "$1: expected [$2], got [$3]"; }
re() { [[ $3 =~ $2 ]] || bad "$1: [$3] does not match $2"; }

DRY='${{ inputs.dry_run == true || vars.CASCADE_DRY_RUN != '\''false'\'' }}'
GROUP='${{ github.ref != '\''refs/heads/main'\'' && format('\''deps-cascade-{0}'\'', github.ref) || (inputs.gates_only && '\''deps-cascade-gates'\'' || '\''deps-cascade'\'') }}'
PUBLISH_IF='!cancelled() && needs.cascade.outputs.compute-ok == '\''true'\'' && needs.cascade.outputs.dry-run == '\''false'\'' && inputs.dry_run != true && vars.CASCADE_DRY_RUN == '\''false'\'' && github.ref == '\''refs/heads/main'\'' && contains(fromJSON('\''["push","recreate","close","conflict","too_long"]'\''), needs.cascade.outputs.action)'

# A key-holding job has exactly these keys: no env, container, services,
# defaults or strategy, so nothing from the repo can run while it holds the key.
JOB_KEYS='["environment","if","name","needs","permissions","runs-on","steps","timeout-minutes"]'

# key_job <file> <job> <action> <permissions as sorted one-line JSON> <with keys as sorted one-line JSON>
# A job that holds the App key: the cascade Environment, exactly one step (the
# SHA-pinned cascade action, with no env, if or shell of its own), the key and
# client id only as that step's inputs, and no input the contract does not pass.
key_job() {
  local f=$W/$1 j=$2 n=$1:$2
  eq "$n keys" "$JOB_KEYS" "$(yq -o=json -I=0 ".jobs[\"$j\"] // {} | keys | sort" "$f")"
  eq "$n step keys" '["name","uses","with"]' "$(yq -o=json -I=0 ".jobs[\"$j\"].steps[0] // {} | keys | sort" "$f")"
  eq "$n with keys" "$5" "$(yq -o=json -I=0 ".jobs[\"$j\"].steps[0].with // {} | keys | sort" "$f")"
  eq "$n environment" cascade "$(yq -r ".jobs[\"$j\"].environment" "$f")"
  eq "$n permissions" "$4" "$(yq -o=json -I=0 ".jobs[\"$j\"].permissions | sort_keys(.)" "$f")"
  eq "$n step count" 1 "$(yq -r ".jobs[\"$j\"].steps | length" "$f")"
  re "$n uses" "^open-platform-model/\.github/\.github/actions/$3@[0-9a-f]{40}\$" "$(yq -r ".jobs[\"$j\"].steps[0].uses" "$f")"
  eq "$n client-id" '${{ vars.CASCADE_APP_CLIENT_ID }}' "$(yq -r ".jobs[\"$j\"].steps[0].with[\"client-id\"]" "$f")"
  eq "$n private-key" '${{ secrets.CASCADE_APP_PRIVATE_KEY }}' "$(yq -r ".jobs[\"$j\"].steps[0].with[\"private-key\"]" "$f")"
}

key_job release.yml notify-downstream cascade-notify '{"contents":"read"}' '["client-id","private-key","tag"]'
# Workflow-level env reaches the notify action's steps. release.yml keeps its
# own env (CUE_VERSION, registries), but nothing that makes a shell or node
# run code at startup.
eq "release.yml env: startup-code variables" "" \
  "$(yq -r '.env // {} | keys | .[] | select(. == "BASH_ENV" or . == "ENV" or . == "NODE_OPTIONS")' "$W/release.yml")"
if [ "$RECEIVER" = true ]; then
  key_job deps-cascade.yml publish cascade-publish '{"contents":"read","pull-requests":"read"}' '["client-id","dry-run","labels-managed","private-key"]'
  d=$W/deps-cascade.yml
  eq "deps-cascade.yml top-level keys" '["concurrency","jobs","name","on","permissions"]' "$(yq -o=json -I=0 'keys | sort' "$d")"
  eq "deps-cascade.yml concurrency.group" "$GROUP" "$(yq -r '.concurrency.group' "$d")"
  eq "deps-cascade.yml publish if" "$PUBLISH_IF" "$(yq -r '.jobs.publish.if' "$d")"
  eq "deps-cascade.yml cascade dry-run" "$DRY" "$(yq -r '.jobs.cascade.with["dry-run"]' "$d")"
  eq "deps-cascade.yml publish dry-run" "$DRY" "$(yq -r '.jobs.publish.steps[0].with["dry-run"]' "$d")"
  re "deps-cascade.yml cascade uses" '^open-platform-model/\.github/\.github/workflows/cascade-receive\.yml@[0-9a-f]{40}$' "$(yq -r '.jobs.cascade.uses' "$d")"
  re "cascade-gates.yml gates uses" '^open-platform-model/\.github/\.github/workflows/cascade-gates\.yml@[0-9a-f]{40}$' "$(yq -r '.jobs.gates.uses' "$W/cascade-gates.yml")"
fi

# Only the caller-owned jobs above read the key or declare the cascade
# Environment, and no call into .github passes secrets (inherit included).
want_key="release.yml:jobs.notify-downstream.steps.0.with.private-key"
want_env="release.yml:notify-downstream"
if [ "$RECEIVER" = true ]; then
  want_key=$(printf '%s\n%s' "deps-cascade.yml:jobs.publish.steps.0.with.private-key" "$want_key")
  want_env=$(printf '%s\n%s' "deps-cascade.yml:publish" "$want_env")
fi
got_key="" got_env="" got_sec=""
for f in "$W"/*.yml "$W"/*.yaml; do
  [ -e "$f" ] || continue
  b=${f##*/}
  got_key+=$(yq -r '.. | select(tag == "!!str" and test("secrets\.CASCADE_APP_PRIVATE_KEY")) | path | join(".")' "$f" | sed "s|^|$b:|")$'\n'
  got_env+=$(yq -r '.jobs // {} | to_entries[] | select(.value.environment == "cascade" or .value.environment.name == "cascade") | .key' "$f" | sed "s|^|$b:|")$'\n'
  got_sec+=$(yq -r '.jobs // {} | to_entries[] | select((.value.uses // "") | test("^open-platform-model/\\.github/")) | select(.value | has("secrets")) | .key' "$f" | sed "s|^|$b:|")$'\n'
done
eq "secrets.CASCADE_APP_PRIVATE_KEY readers" "$want_key" "$(printf '%s' "$got_key" | sed '/^$/d' | sort)"
eq "cascade Environment jobs" "$want_env" "$(printf '%s' "$got_env" | sed '/^$/d' | sort)"
eq "calls into .github that pass secrets" "" "$(printf '%s' "$got_sec" | sed '/^$/d')"

# Every .github reference (the uses: lines and the cascade-task.yml resolver
# ref) carries one full SHA and the pin comment.
refs=""
for f in "$W"/*.yml "$W"/*.yaml; do
  [ -e "$f" ] || continue
  b=${f##*/}
  refs+=$(yq -r '
    (.jobs // {} | to_entries[] | select((.value.uses // "") | test("^open-platform-model/\\.github/")) | .value.uses + " " + (.value.uses | line_comment)),
    (.jobs // {} | to_entries[] | (.value.steps // [])[] | select((.uses // "") | test("^open-platform-model/\\.github/")) | .uses + " " + (.uses | line_comment)),
    (.jobs // {} | to_entries[] | (.value.steps // [])[] | select(.with.repository == "open-platform-model/.github") | "resolver@" + (.with.ref // "") + " " + ((.with.ref // "") | line_comment))
  ' "$f" | sed "s|^|$b |")$'\n'
done
refs=$(printf '%s' "$refs" | sed '/^$/d' | sort)
# "<file> <target>" with the SHA and comment stripped.
want_refs="release.yml open-platform-model/.github/.github/actions/cascade-notify"
if [ "$RECEIVER" = true ]; then
  want_refs=$(printf '%s\n' \
    "cascade-gates.yml open-platform-model/.github/.github/workflows/cascade-gates.yml" \
    "cascade-task.yml resolver" \
    "deps-cascade.yml open-platform-model/.github/.github/actions/cascade-publish" \
    "deps-cascade.yml open-platform-model/.github/.github/workflows/cascade-receive.yml" \
    "release.yml open-platform-model/.github/.github/actions/cascade-notify" | sort)
fi
eq ".github references" "$want_refs" "$(printf '%s\n' "$refs" | sed -E 's/@[^ ]* .*$//' | sort)"
shas=$(printf '%s\n' "$refs" | sed -E 's/^[^ ]+ [^@]*@([^ ]*) .*$/\1/' | sort -u)
re "one .github SHA" '^[0-9a-f]{40}$' "$shas"
while IFS= read -r line; do
  eq "pin comment on [${line% *}]" "$PIN_COMMENT" "$(printf '%s' "$line" | sed -E 's/^[^ ]+ [^ ]+ //')"
done <<< "$refs"

[ "$fail" = 0 ] || exit 1
echo "cascade wiring: ok, .github $shas ($PIN_COMMENT)"
```

- Add the task to `Taskfile.yml`, next to `docs:pins:check`:

  ```yaml
    cascade:wiring:check:
      desc: Check the release-cascade caller workflows (Phase 3 wiring contract 10.1)
      cmds:
        - bash .tasks/cascade/wiring-check.sh
  ```

  **[v3.1.1]** In core, catalog_opm, library and cli, append one line to the `cmds` of the
  aggregate `check` task in `Taskfile.yml` (none of them lists `docs:pins:check` there; core,
  library and cli reach it through `docs:bundle:check`):

  ```yaml
        - task: cascade:wiring:check
  ```

  opm-operator has no aggregate check: neither its `Taskfile.yml` (only `default`, `tools:*` and
  `docs:*` at top level, plus includes) nor its `Makefile` (`all`, `fmt`, `vet`, `lint`, `build` and
  the cluster targets; no `check` or `test`) has one. Its equivalent is the required `lint.yml` `lint` job, which already runs
  `task docs:pins:check` as a step; the CI step below is all opm-operator adds. Do not add a
  `check` task or a Make target there.
- Add one step to the required job of the per-repo table, directly after its "Install Task"
  step (cli `pr.yml` `lint`: after the `go-task/setup-task` step):

  ```yaml
        - name: Verify the cascade wiring
          run: task cascade:wiring:check
  ```

  The step uses the runner's preinstalled mikefarah yq; the script refuses any other yq. cli's
  `ci.yml` `lint` job (push only, no Task) is left alone.
- What it asserts: the `notify-downstream` job (and in a receiver the `publish` job) has
  `environment: cascade`, exactly one step, permissions exactly `{contents: read}` (notify) or
  `{contents: read, pull-requests: read}` (publish), a step `uses` matching
  `^open-platform-model/\.github/\.github/actions/cascade-(notify|publish)@[0-9a-f]{40}$`, and
  `client-id`/`private-key` exactly `${{ vars.CASCADE_APP_CLIENT_ID }}` and
  `${{ secrets.CASCADE_APP_PRIVATE_KEY }}`; **[v3.1.1]** the job's keys are exactly
  `[environment, if, name, needs, permissions, runs-on, steps, timeout-minutes]` (so no `env:`,
  `container:`, `services:`, `defaults:` or `strategy:`), its step's keys exactly
  `[name, uses, with]`, and the `with` keys exactly `[client-id, private-key, tag]` (notify) or
  `[client-id, dry-run, labels-managed, private-key]` (publish), the inputs §4.1 and §6.4 define;
  `release.yml`'s workflow-level `env` has no `BASH_ENV`, `ENV` or `NODE_OPTIONS` (the other keys
  stay free, since core, catalog_opm and opm-operator set registries and CUE versions there); in
  a receiver, `deps-cascade.yml`'s top-level keys are exactly
  `[concurrency, jobs, name, on, permissions]`; `secrets.CASCADE_APP_PRIVATE_KEY` appears in no
  other workflow value and `environment: cascade` on no other job, across every file in
  `.github/workflows/`; no job that calls into `open-platform-model/.github` has a `secrets` key;
  in a receiver, the `concurrency.group`, the `publish` `if:`, and both `dry-run` values equal §5
  byte for byte, and `cascade-receive.yml` and `cascade-gates.yml` are named by a 40-hex SHA;
  and the set of `.github` references is exactly the expected one (core 1, receivers 5), with
  one SHA and the `PIN_COMMENT` comment on every one.
- Update or delete any existing repo test that asserts the version 2 shape.

**7. Dependabot ignore (library, opm-operator, cli).** In `.github/dependabot.yml`, in the
`package-ecosystem: "github-actions"` entry's existing `ignore:` list, after the docs-kit entry,
add:

```yaml
      # The cascade workflows, actions and resolver move together, one .github SHA per repo,
      # only through a ci(deps) pin PR (Phase 3 wiring contract 2.4; .github README
      # "Pinning and bumps"); a Dependabot bump would move one reference alone.
      - dependency-name: "open-platform-model/.github*"
```

The six-space indentation is the one the docs-kit entry already has in all three files. core and
catalog_opm add nothing.

**8. Docs in the branch (all five)** (AGENTS.md, README if it mentions the cascade, the change's
`proposal.md`, `design.md`, `tasks.md` and spec deltas):

- the notify job runs the pinned `cascade-notify` action in this repo's own caller-owned
  `cascade` Environment job; there is no reusable notify workflow;
- (receivers) the receiver is the reusable `cascade-receive.yml` (compute and gates, no secret)
  plus the caller-owned `publish` job running the pinned `cascade-publish` action;
- every cascade reference, the `cascade-task.yml` resolver `ref:` included, is pinned to one
  `.github` `main` SHA (owner decision 24 for the actions, the supervisor's extension for the
  rest), and a `.github` change reaches this repo only through a
  `ci(deps): pin the cascade to .github <sha7>` PR (§2.4); Dependabot ignores the references;
- `task cascade:wiring:check` runs in the required CI job on every PR;
- cite this file as "Phase 3 wiring contract (version 3.1)", and re-check every cited section
  number against it.

**9. Replace the "no secret" wording (all five; review finding 1).** Every requirement, scenario
or comment that says the notify or publish job, or "the job that starts it", "passes no secret"
or "holds no secret", or that the repo "MUST NOT pass any secret to the shared workflow" as the
whole rule, is rewritten to this (spec deltas use it as the requirement text, adapted to MUST;
comments may shorten it but keep every clause):

> The key is read only in the caller-owned `notify-downstream` or `publish` job, which declares
> `environment: cascade` and passes `secrets.CASCADE_APP_PRIVATE_KEY` only as the `private-key`
> input of the SHA-pinned cascade action; that job has no checkout or `run:` of its own, and no
> `env:`, `container:` or `services:` (the action checks out the repo but never runs it); no
> reusable call passes `secrets:` or `secrets: inherit`.

**[v3.1.1]** A branch that already adopted the 3.1 wording ("that job has no checkout and no
`run:` step") replaces it with the text above.

Known sites (review finding 1): core `specs/release-cascade/spec.md` lines 44 and 70 and
`proposal.md` line 10; cli `specs/release-cascade-wiring/spec.md` line 67 (a whole requirement,
"The shared cascade workflows are called at main with no secret passed": rewrite it as the
requirement above plus "at one pinned `.github` `main` SHA") and `proposal.md` line 54; the
comments at core `release.yml` 138, library `release.yml` 77, cli `release.yml` 270, and
catalog_opm and cli `deps-cascade.yml` 13. A sentence that says `compute` or `gates` holds no
secret is true and stays.

Each receiver's spec deltas also carry two requirements (wording the branch's own): the
receiver's publish job is a caller job in the `cascade` Environment that runs the pinned
`cascade-publish` action with the §5 `dry-run` expression; and the receiver never publishes
unless `CASCADE_DRY_RUN` is exactly `false`, enforced by the action as well as by the `if:`.
Every B's deltas carry one more: the cascade references are pinned to one `.github` `main` SHA
and checked by `task cascade:wiring:check` in the required CI job.

**10. Recovery text (all five).** Text that says a run fails at startup "because
`cascade-notify.yml` is missing or invalid on `.github` `main`" (core AGENTS.md has it) is
obsolete: a pinned SHA cannot go missing. The failure mode now is a bad pin, fixed by a pin PR.

**11. Re-grep (all five), last before review.** From the repo root on the branch:

```bash
{ git diff --name-only origin/main...HEAD; ls .github/workflows/cascade-task.yml 2>/dev/null; } | sort -u \
  | xargs grep -niE 'cascade-notify\.yml|org-github-ref|labels-managed|@main|ref: main|no secret|not pass any secret|holds no|main yet|ships it on|resolver is on|no checkout and no|re-arm|sandbox step|shared (cascade )?workflow[^.]*(mint|declare|publish)|reusable (notify|publish)'
```

**[v3.1.1]** The pattern gains `ships it on` and `resolver is on` (the item 3 fallback comments;
each adds one hit to library's and opm-operator's `cascade-task.yml`, so both count 3 before the
item 3 edit), `no checkout and no` (the 3.1 item 9 wording) and `re-arm|sandbox step` (decision
26: no branch text may describe a sandbox step in a bump).

Every hit is either fixed or one of: `labels-managed` on the `cascade-publish` step or in text
describing it; `@main` or `ref: main` in text about something other than the cascade (for
example docs-kit); "holds no secret" or "no secret" about `compute` or `gates` only; archived or
historical text that says it is superseded. Hits at the branch heads above (informational, before
any 3.1 edit; paths under `openspec/changes/join-release-cascade/` shortened):

- core: release.yml 3, AGENTS.md 1, design.md 14, proposal.md 6, `specs/release-cascade/spec.md`
  2, tasks.md 3.
- catalog_opm: cascade-gates.yml 2, cascade-task.yml 1, deps-cascade.yml 3, release.yml 2,
  AGENTS.md 2, design.md 10, proposal.md 6, tasks.md 5.
- library: cascade-gates.yml 1, cascade-task.yml 2, deps-cascade.yml 2, release.yml 2,
  AGENTS.md 1, design.md 8, proposal.md 5, `specs/cascade-wiring` 3, `specs/release-pipeline` 2,
  tasks.md 2.
- opm-operator: cascade-gates.yml 1, cascade-task.yml 2, deps-cascade.yml 3, release.yml 1,
  AGENTS.md 1, design.md 22, proposal.md 8, `specs/cascade-receiver` 2,
  `specs/release-automation` 1, tasks.md 7. Also remove any text that leaves E6 open or asks the
  owner about `sha_pinning_required` (decision 24 settled it).
- cli: cascade-gates.yml 1, cascade-task.yml 1, deps-cascade.yml 4, release.yml 3, AGENTS.md 2,
  design.md 10, proposal.md 7, `specs/release-cascade-wiring` 6, `specs/release-workflow` 1,
  tasks.md 12.

Then run the repo's gates: its own workflow lint (actionlint where it has it, and the scratchpad
`actionlint` on every changed workflow), `task cascade:wiring:check`, shellcheck on
`.tasks/cascade/wiring-check.sh` where the repo lints shell, and `openspec validate --strict` on
the change. actionlint does not check a composite action's inputs, so the wiring check is the
check for `cascade-publish`'s and `cascade-notify`'s inputs.

**Pre-merge check (the supervisor, per B, on the PR's final head):**

1. The final commit is `ci: pin the cascade to .github main`, and `<SHA>` is the `.github` `main`
   squash SHA the supervisor handed out.
2. `gh api repos/open-platform-model/.github/compare/<SHA>...main --jq .status` prints
   `identical` or `ahead`. `behind` or `diverged` (a branch commit, for example `99d93e5` or
   `a2950ce` after the squash merge) refuses the merge.
3. `grep -n "^PIN_COMMENT=" .tasks/cascade/wiring-check.sh` prints
   `PIN_COMMENT='.github main' …`, and `grep -n "^RECEIVER=" .tasks/cascade/wiring-check.sh`
   prints `false` for core and `true` for the other four.
4. The required job ran the "Verify the cascade wiring" step on that head and it printed
   `cascade wiring: ok, .github <SHA> (.github main)`.
5. **[v3.1.1]** `grep -rn -A1 'open-platform-model/.github' .github/workflows` shows no
   `@main`, no branch name and no SHA other than `<SHA>`; the `-A1` prints the `cascade-task.yml`
   `ref:` line under its `repository:` hit, which a plain grep cannot show.
6. The item 11 re-grep leaves only the allowed hits.
7. (library, opm-operator, cli) `.github/dependabot.yml` has the `open-platform-model/.github*`
   ignore under `github-actions`.
8. In a receiver, the repo variable `CASCADE_DRY_RUN` reads back `true`.

---

## 11. Sandbox cycle (part of A)

**[v3] Status: done.** The cycle ran at `30a98c6` (results in §11.4 and A's `design.md`
"Sandbox cycle"), and the review-fix re-runs R1 to R5 ran at `a2950ce` (§11.4 "Re-runs"). The
text below records how it was set up; the `[v3]` marks say what differs from what ran.

**[v3.1.1] The sandbox is dropped after Phase 3** (owner decision 26). It runs nothing more: its
`cascade` Environments hold no key or client id, both repos are private, the owner takes them off
the `opm-cascade` installation, and both are archived after Phase 3. A later `.github` cascade
change is proven by the offline suites and the canary of §2.4 step 2, not here.

### 11.1 Precondition: `cascade-sandbox-up` becomes public

- The resolver reads `release` sources anonymously (tags with a credential-free `git ls-remote`,
  assets with an anonymous `HEAD`), so it cannot see a private upstream.
- Giving it credentials would undo its isolation. Instead, the supervisor makes the upstream
  sandbox public under owner decision 22 ("the two sandbox repos"):
  `gh repo edit open-platform-model/cascade-sandbox-up --visibility public --accept-visibility-change-consequences`.
- It holds only a README and a tarball.
- `cascade-sandbox-down` stays private.
- **[v3]** Done: up is public. After the cycle it still is (verification m4, §15).
  **[v3.1.1]** Up is private again (decision 26).

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
  - `notify-downstream`: **[v3]** as §4.3 (caller-owned `cascade` job), with
    `tag: ${{ inputs.version }}`, running `cascade-notify@a2950ce6d314618c108cfdf2e978133c2ab09f4a`
    (comment `# feat/add-release-cascade-workflows`). Up also has an input `breaking`, which
    writes `BREAKING CHANGES` into the release notes.
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
- `.github/workflows/deps-cascade.yml`: **[v3]** as §5 (both jobs), with no schedule,
  `setup-cue: false`, `labels-managed: false`, both references at
  `a2950ce6d314618c108cfdf2e978133c2ab09f4a`. The static suite checks that every sandbox
  reference uses one full SHA and that the sandbox `publish` `if:` equals the README's.
- `.github/workflows/cascade-gates.yml`: as §8.3, at the same SHA.
- Repo variable `CASCADE_DRY_RUN=false`, set by the supervisor, so the cycle runs live (§9.1).
  S9 sets it to `true` and back.

~~**[v3]** After A merges, task 5.8 moves the sandbox callers to A's `main` squash SHA (never
`@main`, decision 24) with the comment `# .github main`, in one more sandbox PR per sandbox repo,
and re-runs S1 once to confirm. Until then the branch commit `a2950ce` must stay reachable: do
not delete `feat/add-release-cascade-workflows` (`.github` does not delete branches on merge)
before task 5.8 is done.~~ ~~**[v3.1]** Task 5.8 then deletes that branch from `origin` and
disarms the sandboxes (§11.5); every later bump re-arms them for its sandbox step only (§2.4 step
2).~~ **[v3.1.1]** Decision 26 drops the sandbox move and the S1 rerun: the sandboxes hold no key,
so S1 cannot run, and nothing will run there again. The sandbox callers keep `a2950ce` until the
repos are archived. ~~Task 5.8 shrinks to one step: once every B has merged at its `main` SHA and
both sandboxes are archived, delete `feat/add-release-cascade-workflows` from `origin` (§15
item 10). A's `tasks.md` says so (§15 item 14).~~ **[v3.1.2]** `.github` deletes branches on
merge (Facts), so merging A deletes `feat/add-release-cascade-workflows` and task 5.8 has no
branch step left; the sandbox pins to `a2950ce` do not matter once the sandboxes are archived.
After the archive, the sandbox entries in `wiring/lib.sh` are removed by a follow-up `.github`
PR (§15 item 10).

### 11.4 Sandbox runs and E-tests (results recorded in A's `design.md`; each with run URL)

| Id | Step | Pass |
| --- | --- | --- |
| E1 | S1: release `v0.2.0` in up | notify (`environment: cascade` inside the reusable workflow) mints a token. **[v3]** Failed as written; passed on the caller-owned job of §4.3 (results below). The down repo starts a `repository_dispatch` run whose actor is `opm-cascade[bot]`. A `workflow_dispatch` of down's caller from a non-main branch is a forced dry run, and publish never starts. |
| E1b | probe: on a branch `probe-env` of `cascade-sandbox-up`, a workflow `probe-env.yml` (`workflow_dispatch`) calls `cascade-notify.yml@<A's branch>` with `org-github-ref: <A's branch>` and a valid tag, with no dry-run short circuit; dispatch it with `--ref probe-env` (**[v3]** run against the fallback's caller-owned job) | The `notify` job fails on the `cascade` Environment's branch policy before any step runs, and no token is minted. This is the only control against a branch that calls a modified reusable workflow to reach the key, so it must be observed, not assumed. Delete the branch afterwards. |
| E2 | S2: the receiver opens the PR | One PR on `deps/cascade` with author `app/opm-cascade`. Title `fix(deps): bump up to v0.2.0`. The body has the moved pin, the triggering release `cascade-sandbox-up v0.2.0` and the Notes marker. The commit author is the bot. `ci` and `mention-guard` run and pass on the App-pushed PR. |
| S3 | release `v0.3.0` | The same PR number, rebuilt to one commit, `UPSTREAM_VERSION` = `v0.3.0`, and the title updated. |
| S4 | a human commit (`fixtures/human.txt`) on the branch, then release `v0.4.0` | The human commit is an ancestor of the new tip (no rewrite). The bot commit is on top. The title is still `fix(deps)`. |
| E3/E4 | change `touch.yml` on `main` (via PR), then trigger the receiver: (a) with the human commit present, expect action `conflict` (workflows) with label and comment and no push; (b) after the human commit is gone (close the PR, rerun), expect `recreate`: a new PR number with the Notes carried; (c) separately, by hand with an App token from a probe job, record whether an in-place `--force-with-lease` update across the workflow change and a merge push are refused | (a) and (b) behave as §7.6 under `strict`. (c) decides `WF_GUARD_RULE` (§7.6); if it is set to `tree`, rerun (a) and (b) and expect `push` in both. |
| E5 | probe: `PUT …/pulls/<n>/update-branch` with the App token after a workflow change on `main` | Recorded only. The design never uses it. |
| E6 | probe: set `sha_pinning_required: true` on `cascade-sandbox-down` and run its caller at `@main` | If it is refused, opm-operator needs an owner decision (§15). Restore the setting afterwards. **[v3]** Result: reusable workflows by branch or SHA ran; actions by branch were refused, by SHA accepted. The sandbox-cycle agent toggled the setting (14:08:36Z to 14:09:57Z, restored to `false`) under the supervisor's grant, which the supervisor confirms. `@main` was tested through a reusable workflow in up, because `.github` `main` has no cascade code yet (a proxy, n2). Settled by decision 24. |
| E7 | a Dependabot PR in the sandbox | `cascade-gates.yml` posts `n/a` statuses. If the token is read-only there, record it as a Phase 5 blocker (§15). |
| S5 | edit the PR's Notes, release again | The Notes survive byte for byte. **[v3]** A bare `@word` typed in the Notes gives mention-guard only an advisory notice on a bot-authored PR body, not a failure (mention-guard on `main` treats bot PR bodies as advisory); P2 §11 C1's "fails" is outdated. |
| S6 | merge the PR (squash, as the supervisor) | **[v3]** The `main` commit's first line is exactly `<PR title> (#N)`. GitHub still appends `Co-authored-by: opm-cascade[bot]` and other trailers despite BLANK. release-please reads the header and the footers (`BREAKING CHANGE`, `Release-As`); `Co-authored-by` is neither, so the release is unaffected. |
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

**[v3] Results of the cycle at `30a98c6`** (D = `cascade-sandbox-down`, U = `cascade-sandbox-up`;
every run and PR was opened and confirmed by the verification):

| Id | Result | Evidence | Note |
| --- | --- | --- | --- |
| E1 (first, reusable notify) | fail | U 37205835905 | Environment variable visible, Environment secret empty; mint failed. Led to §13.1. |
| E1 probe | data | U 37205963663, U PR 2 | no `secrets:` → secret empty; `secrets: inherit` → visible |
| E1 (fallback `038da12`) | pass | U 37206437700; D 37206458777; branch run D 37206547449 | dispatch HTTP 204; down run actor `opm-cascade[bot]`; token scoped to down only; branch run `effective_dry_run: true`, Publish skipped |
| E1b | pass | U 37206627490 | "Branch probe-env is not allowed to deploy to cascade"; no step ran |
| E2 | pass | D PR 5 | bot author and committer; title and body correct; ci, mention-guard, Cascade gates green. Title says `v0.2.1` because `v0.2.0` exists from the failed E1 run (releases are never deleted) |
| S3 | pass | D 37206696519 | same PR, one commit, `v0.3.0` |
| S4 | pass | D 37206803140 | merge mode; human commit kept as ancestor |
| E3/E4 (a), strict | pass | D 37206929569, sweep 37206991382 | workflows conflict, one comment, no push |
| E4c | both accepted | D 37207063750, 37207085490 | decided `tree` (§7.6) |
| E3/E4 (b2), strict | pass | D 37207250517, D PR 7 | fresh PR, nothing carried |
| E3/E4 (b), strict | pass | D 37207378831, D PR 9 | recreate; Notes byte-identical; `need-human-review` carried; "Continued in #9." Reached through (b2) plus a second workflow change on `main`, because the session's permission layer denied the agent's human-style lease push (deviation 6) |
| E3/E4 (b), tree | pass | D 37207816358 | rebuilt in place on PR 9 |
| E3/E4 (a), tree | pass | D 37207979847 | merge commit `c086837` pushed; human commit kept |
| E5 | recorded | D 37208052407 | `update-branch` with the App token accepted; never used |
| E6 | answered | D PR 12; runs 37208164124 to 37208176173 | see the E6 row above |
| E7 | pass | D PR 2, run 37205783292 | Dependabot token has `statuses: write`; `n/a` posted (private repo, a proxy) |
| S5 | pass (Notes) | D 37208315156; mention-guard 37208368685 | bare mention advisory only; Notes edit had no CRLF (CRLF covered offline only) |
| S6 | partial | D PR 9 (`5f4f893`) | first line exact; `Co-authored-by` trailers appended |
| S7 | pass | D PR 13, gates-only 37208464972 | `WARN: behind: up v0.9.0→v0.10.0` |
| S8 | pass | D 37208516941 | payload dropped with a warning, sweep, no mention |
| S9 | pass | D 37208598636 | dry run; Publish skipped; no branch or PR |
| S10 | pass | D PR 14, 37208784609 | human title kept; no title-rise comment |
| S11 | pass | D 37208904285, 37208922871 | pending dispatch run not replaced; kept its payload |

No token or key appears in any run log or plan artifact; no dry run pushed; no job ran repo code
while holding the key.

**[v3] Re-runs at `a2950ce`** (the review fixes; sandbox callers moved by up#6 and down#16):

| Run | Result | Evidence | Shows |
| --- | --- | --- | --- |
| R1, `CASCADE_DRY_RUN=true`, release `v0.15.0` | pass | U 37211493811, D 37211515507 | notify ran the action at `a2950ce` (HTTP 204); both down jobs logged scripts from `a2950ce6d…`, so `job.workflow_sha` is the called workflow's own SHA; plan `push` with `effective_dry_run: true`; Publish skipped; `deps/cascade` stayed at `c4965a0` |
| R2, dry-run input inside the action (probe down#17, removed by down#18) | pass | `true`: D 37211613251; empty: D 37211616082; `False`: D 37211773378 | `true`: notice, no mint, no Act, success. Empty: reached the script as `true` in this probe, so empty is covered offline only. `False`: refused before the mint. Nothing pushed. |
| R3, `CASCADE_DRY_RUN=false`, release `v0.16.0` | pass | U 37211875058, D 37211895079, gates 37211939078 | PR 14 updated in place to `9f3806c`: one commit, bot author and committer, human title kept; gates passed on the new head |
| R4, sweep | pass | D 37211972443 | rebuild changed nothing; old commit kept |
| R5, merge PR 14 (down main `9c504e9`), then sweep | pass | D 37212051452 | task exit 3 (noop) with zero `##[error]` lines |

Sandbox end state: `CASCADE_DRY_RUN=false` on down, down `main` at `v0.16.0`, no cascade PR
open, only down#2 (Dependabot) open.

### 11.5 Sandbox security

- The sandboxes' `cascade` Environments hold the same App key as production (Facts). Anyone who
  can push to a sandbox's `main` can add a workflow there that mints a token for any of the seven
  repos.
- Before the sandbox Environments are used, the supervisor adds a `main` ruleset to both sandbox
  repos: pull request required, no required checks, owner bypass pull-request-only, the same
  shape as the product repos. The seeding PRs are then merged as PRs. §15 item 1 covers whether
  decision 22 includes this.
- A records this reach in `design.md`, and that rotating the one key rotates it everywhere.
- **[v3]** Done: the rulesets were created (10:59Z) before the seeds (13:28Z); both sandboxes have
  only the two org admins as collaborators.
- ~~**[v3] Open after the cycle (verification m4):** up is still public, both sandbox `cascade`
  Environments still hold the production key, the rulesets require 0 approvals, and down has
  `CASCADE_DRY_RUN=false`.~~ **[v3.1.1]** Closed by decision 26: the supervisor deleted
  `CASCADE_APP_PRIVATE_KEY` and `CASCADE_APP_CLIENT_ID` from both sandbox `cascade` Environments
  and made up private (read back 2026-10-04).
- ~~**[v3.1] Disarmed between rollouts, re-armed per bump.**~~ **[v3.1.1]** Withdrawn. There is
  no re-arm (decision 26), so nobody needs to hold the PEM to restore it (review finding 10: a
  GitHub secret cannot be read back). The one disarm is deleting the key from the Environments,
  which is done. Taking the sandboxes off the `opm-cascade` installation is an extra step, not a
  disarm: the App has one installation for the org, and removing repos from it does not remove
  the key from their Environments (review finding 2). The owner does it by unchecking both
  sandboxes in the App's installation settings; the supervisor reads the repository list back.
  Archiving after Phase 3 ends the sandbox's reach for good. A's `design.md` records the end
  state this way (§15 item 14).

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
  - **[v3]** the §2.2 repo-name derivation (empty name, wrong owner); version 2's §2.4 ref guard
    no longer exists;
  - the §5 concurrency-group expression for a main real run, a gates-only run and a branch run;
  - the §8.1 status mapping and truncation.
  - **[v3]** the `cascade-publish` `dry-run` input (§6.4): `true`, missing, empty, `False`,
    `TRUE`, `" false"` and `"false "`, and `act` refusing on its own;
  - **[v3]** the exit-3 annotation drop (§6.2 step 10), and a real failure keeping its
    annotation.
- **Static checks:**
  - **[v3]** `static.sh` (in the wiring suite): the `Own commit` step text, its order and the
    checkout ref in both receive jobs; no `org-github-ref` anywhere; the actions run scripts only
    from `GITHUB_ACTION_PATH`; the `dry-run` input and its expression; the README's
    `@<sha> # .github main` pins; every sandbox reference one full SHA; the sandbox `publish`
    `if:` equal to the README's; the §5 concurrency group in the README and the seed.
  - **[v3]** `.github/actionlint.yaml` ignores only `property "workflow_(repository|sha)" is not
    defined in object type`, only in `cascade-receive.yml` (actionlint 1.7.12 does not know
    `job.workflow_*`).
  - `actionlint`: the `Resolver tests` job already runs it, pinned, on every workflow, so the
    **[v3.1]** two reusable workflows are covered with no change;
  - **[v3.1]** a static case that the README bump procedure uses the widened grep
    `grep -rn 'open-platform-model/.github' .github/workflows` (added in `25fe15b`);
  - the tests and static checks run as steps in the existing `Resolver tests` job, so no new
    context appears. If they push the job past its `timeout-minutes: 10`, raise the timeout; the
    context name does not change.
  - `shellcheck` (already pinned at v0.11.0) on `wiring/**.sh`.
- **The receive workflow and the two actions themselves** are tested only by the sandbox cycle
  (§11). **[v3.1.1]** That cycle covered A as merged. A later change to them is tested by these
  offline suites and then by the canary dry run (§2.4 step 2), which runs `compute` and `gates`
  for real but skips `publish`; `cascade-publish` and `cascade-notify` first run against real
  GitHub on the canary's next live run or the next upstream release (§2.4 step 2, §15 item 13).
- **[v3] Gates at `94fe628`** (local; `.github` CI has not run, no PR yet): shellcheck 0.11.0
  clean; actionlint 1.7.12 clean on the workflows and the seeds; resolver suite 338/0; wiring
  suite 396/0; `openspec validate --all --strict` 4/0. **[v3.1]** `.github` CI on PR #9 at
  `99d93e5`: `Resolver tests` and `mention-guard` green.

---

## 13. Fallbacks (applied only if a sandbox test fails)

### 13.1 E1 fails (the Environment secret is not visible to a reusable-workflow job) [v3: applied]

**[v3]** E1 failed, and this fallback is the shipped design. It is specified in §2.2, §4, §5 and
§6.4; the text below is version 2's plan, kept for the record. The differences from the plan:
the actions are pinned by SHA (decision 24), not `@main`; the action, not the caller job, mints
the token; and `labels-managed` and the `dry-run` switch are action inputs.

- Replace notify and publish with composite actions:
  - `.github/actions/cascade-notify/action.yml`;
  - `.github/actions/cascade-publish/action.yml`.
- Each caller then declares its own job with `environment: cascade`. It mints the token in that
  job and calls the composite action with `uses: open-platform-model/.github/.github/actions/…@main`
  (**[v3]** superseded: `@<SHA> # .github main`, §2.4).
- `compute` and `gates` stay in the reusable workflow. The receiver caller then has two jobs: the
  reusable `compute`/`gates`, and a local `publish` job that downloads `cascade-plan`.
- This is a contract change. The A branch reports it to the supervisor before implementing it.

### 13.2 E2 fails (a fresh branch at `main` plus a non-workflow commit is refused)

The design cannot work without the Workflows permission, which owner decision 5 forbids. Stop
and escalate. Do not grant the permission.

---

## 14. RELEASING.md amendments (a workspace PR, merged before or together with A) [v3]

These land before A merges (§1), so RELEASING.md never describes behaviour the merged workflows
do not have. ~~**[v3]** Still open (verification B1): workspace `main` (9ce8faa) has none of them,
and `origin/docs/release-cascade-followups` does not carry them either.~~ ~~**[v3.1.1]** The
amendments sit on the workspace branch `docs/releasing-phase3-wiring` at `6ec574e`, not merged
yet; workspace `main` (9ce8faa) still has none of them. On `main`, RELEASING.md lines 192-194
(the Environment "is declared inside the reusable notify workflow") and 285-296 ("two jobs",
`publish` posts G2 and G3) still say the opposite of what ships. That branch also needs the
3.1.1 items below before it merges.~~ **[v3.1.2]** Done on the branch: the workspace branch
`docs/releasing-phase3-wiring` at `c1e5266` carries every amendment below, the 3.1.1 items
included (final cross-check, 2026-10-04). It still merges before or with A (§15 item 7).

- "Stop switches": add `CASCADE_NOTIFY=off`. `CASCADE_DRY_RUN` is live only at exactly `false`.
  **[v3]** The switch is enforced by `cascade-publish`'s `dry-run` input as well as by the
  caller's `if:` (§9.1).
- "Concurrency": the real runs keep the group `deps-cascade`; gates-only runs use
  `deps-cascade-gates` and branch runs `deps-cascade-<ref>`, so neither can replace a pending
  real run.
- **[v3]** "Two-job split": it is now two reusable jobs plus one caller job. `compute` and
  `gates` run in `cascade-receive.yml` and hold no secret; `gates` posts the G2 and G3 statuses
  with `GITHUB_TOKEN`. `publish` is the caller's own job in the `cascade` Environment, running
  the `cascade-publish` action, which re-derives the PR and refuses a plan it cannot verify
  (§6.4 step 2). Say why: a reusable-workflow job does not see the caller's Environment secrets
  without `secrets: inherit`, which no caller passes (E1).
- **[v3]** "Notify after publish": notify is a caller-owned job that declares
  `environment: cascade` and runs the `cascade-notify` action with the key as an input (replace
  lines 192-194). The catalog_opm job is now named `verify-published`; library waits for the Go
  proxy, best effort, for 10 minutes.
- **[v3.1]** "Rollout and changes" (or wherever decision 13 is described): decision 24 pins the
  cascade actions by SHA; the supervisor extended it to the two reusable workflows and the
  `cascade-task.yml` resolver `ref:` (say so, and why). Every cascade reference in the five repos
  carries one `.github` `main` commit SHA per repo, checked in CI by `task cascade:wiring:check`
  and ignored by Dependabot. The §2.4 bump procedure is how a `.github` cascade change rolls out
  or back: the `compare` check that the SHA is on `main`; ~~the sandbox step (re-arm, move the
  sandbox pins, run, disarm)~~ **[v3.1.1]** the canary (one receiver's pin PR first, as a dry run
  with `CASCADE_DRY_RUN=true`, checked as §2.4 step 2 says, including that `cascade-publish` and
  `cascade-notify` first run live after it; **[v3.1.2]** and that for such a diff the other
  repos wait for that first live run to succeed); then one
  `ci(deps): pin the cascade to .github <sha7>` PR per remaining repo, found with
  `grep -rn -A1 'open-platform-model/.github' .github/workflows`, each with the `compare` check
  and `task cascade:wiring:check` passing.
- **[v3.1.1]** Decision 26 in "Rollout and changes" and wherever the sandbox is described: the
  sandbox is dropped and archived after Phase 3; remove "the supervisor restores the key", the
  re-arm and disarm steps, and any "uninstall the App" disarm (RELEASING.md 645-649 on the
  branch).
- **[v3.1.1]** Where RELEASING.md says a `.github` merge changes "nothing in a product repo, its
  CI included" (254-256 on the branch): it changes nothing in a product repo's cascade (callers,
  receiver, `cascade-task.yml`) until that repo moves its pin; `mention-guard` (from `.github`
  `main` through the org ruleset) and a laptop `task deps:cascade` (the sibling `.github`
  checkout) change at once.
- **[v3.1.1]** "Owner settings": `.github` is squash-only with PR_TITLE + BLANK, like the five
  product repos (review finding 9).
- "Owner settings": the App's Commit statuses permission is unused (§8.4). The owner may drop it;
  nothing in Phase 3 depends on it either way. **[v3]** opm-operator's `sha_pinning_required`
  stays on; decision 24 makes it pass.
- "Gates": add the `CASCADE_G2_MODE` and `CASCADE_G3_MODE` variables. Statuses are posted by
  GitHub Actions (integration 15368). `n/a` success on non-release PRs. The per-PR caller
  dispatches a gates-only receiver run when a release PR head moves. This replaces the "missing
  on current head until the next dispatch" note. Add G3's accepted false positive and false
  negative (§8.2).
- **[v3]** "One rolling PR per repo" (corrected per verification m1): with `WF_GUARD_RULE=tree`,
  a workflow change on `main` is merged or rebuilt into the open PR in place. `recreate` happens
  only for a closed PR's leftover branch. `deps-cascade:conflict` (workflows) happens only when
  the branch itself changes workflow files against `main` (for example a human workflow commit on
  `deps/cascade`) in merge mode. A bot commit a human amended counts as a human commit.
- "The receiver": add the payload schema (exactly `source` and `tags`), the per-repo source
  allowlist, the rule that an invalid payload becomes a sweep, that a branch-ref run is a forced
  dry run, and that a fork PR on a branch named `deps/cascade` is never the cascade PR.
- "Bump rule": no change to the retitle rule (§7.3 implements it as written). Add the
  C-title-rise comment, and that `deps-cascade:breaking` covers every upstream release between
  the pin on `main` and the pin in the PR.
- **[v3]** Mention guard (wherever P2 §11 C1's expectation is described): a bare mention in a
  bot-authored PR body (for example in the Notes) gives mention-guard only an advisory notice,
  not a failure (S5).
- **[v3]** Squash messages (decision 19's BLANK): GitHub still appends `Co-authored-by` and
  similar trailers to the squash commit; the first line is exactly `<PR title> (#N)`, and
  release-please is unaffected because it reads only the header and the `BREAKING CHANGE` and
  `Release-As` footers (S6).
- "Phases": Phase 4 "Clear the dry-run flag" becomes "set `CASCADE_DRY_RUN=false`", and a
  receiver goes live only after one non-noop dry-run summary was read and found correct (§1).
  **[v3]** Phase 5 notes add: repo code in `compute` can shape `gates.json` and the job outputs
  (verification m3, §6.2 step 14), to be weighed before G2 and G3 become required checks.

## 15. Open points for the supervisor or owner [v3]

1. ~~The sandbox visibility change (§11.1).~~ **[v3]** Done.
2. ~~E6.~~ **[v3]** Settled by owner decision 24 (pin by SHA in all five repos). Nothing left
   for opm-operator.
3. ~~E7.~~ **[v3]** Passed (statuses: write on the Dependabot token), shown in a private
   sandbox repo; the product repos are public, so it is a proxy. Not a Phase 5 blocker.
4. ~~Sandbox rulesets (§11.5).~~ **[v3]** Done before the seeds.
5. **Phase 4 gate** (§1). Each receiver must show one non-noop dry-run summary, read by the
   supervisor, before `CASCADE_DRY_RUN=false`. The Phase 3 gate cannot show it, because every
   pin is current today.
6. **Stuck `error` under switch 5** (§9.2). In `enforce` mode, a disabled `deps-cascade.yml`
   blocks release PRs until it is enabled again or the mode goes back to `warn`. Phase 5 notes
   this when it flips a mode.
7. **[v3] B1: RELEASING.md amendments** (§14) are not on workspace `main`. They must land before
   or with A.
8. ~~**[v3] `.github` PR and CI.**~~ **[v3.1]** Done: PR #9, green at `99d93e5`.
9. ~~**[v3.1] Sandbox reach after the cycle (m4, §11.5).**~~ **[v3.1.1]** Done by decision 26:
   the key and client id are gone from both sandbox Environments and up is private. Left: the
   owner unchecks both sandboxes in the `opm-cascade` installation (the supervisor reads the
   list back), and the supervisor archives both after Phase 3. No re-arm, ever.
10. ~~**[v3.1.1] Delete `feat/add-release-cascade-workflows`** from `origin` only after every B
    has merged at its `main` SHA (their pre-merge pins name `99d93e5` on it) and both sandboxes
    are archived (their pins name `a2950ce` on it) (§11.3).~~ **[v3.1.2]** Merging A deletes the
    branch (`delete_branch_on_merge: true`); each B pins A's `main` squash SHA at once (item 12),
    and the sandbox pins do not matter once both sandboxes are archived. Follow-up after the
    archive: a `.github` PR removes the sandbox entries from `wiring/lib.sh` (the notify edge,
    the receiver allowlist, the G3 upstreams, the `CASCADE_EXPECT` pair, the changelog source
    and the §3.6 `extra_sources` widening) and their wiring cases.
11. **[v3] m3 for Phase 5.** Repo code in `compute` can shape `gates.json` and the job outputs
    before G2 and G3 become required checks. Written down in A's design Risks; not fixed.
12. **[v3] B pin swap.** After A merges, hand each B the `.github` `main` squash SHA for its
    final pin commit (§2.4, §10). **[v3.1]** Before that, hand each B the A branch head to
    develop against (today `99d93e5`). Run the §10.1 pre-merge check on every B. **[v3.1.2]**
    Hand the squash SHA over right after A merges: the merge deletes A's branch.
13. **[v3.1] Report to the owner** in the phase report: the supervisor extended decision 24
    (actions) to the two reusable workflows and the `cascade-task.yml` resolver `ref:` (top,
    item 2). **[v3.1.1]** Also report the cost of decision 26: with no sandbox, a change to
    `cascade-publish` or `cascade-notify` first runs against real GitHub, with the production
    key, in a product repo (the canary's next live run, or the next upstream release); the
    canary dry run proves only `compute`, `gates`, the pins and the wiring check. Rollback is a
    pin PR back. **[v3.1.2]** The canary rule (§2.4 step 2) keeps that first live run to the
    canary alone: the other repos stay on the old pin until it has succeeded.
14. ~~**[v3.1.1] A-side follow-ups**~~ **[v3.1.2]** Done (`6b01380`, `7b5157b`; final
    cross-check 2026-10-04). They were (the `.github` README and A's archived change, before A
    merges): README "Pinning and bumps" replaces the sandbox step with the §2.4 step 2 canary,
    adds the per-PR `compare` check and `task cascade:wiring:check` to its bump steps 3 and 4
    (review finding 14), and uses `grep -rn -A1`; README "CI checks this repo out at `main`"
    (172-176) says the repo's cascade pin instead (finding 4); the archived `contract.md` is
    replaced by this version (finding 3); `design.md` says "five cascade references" in a
    receiver (finding 11), records the sandbox end state of §11.5, and task 5.8 says what §11.3
    now says.

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

## Version 3 notes [v3]

Sources folded in: the sandbox run report (`p3-sandbox-run.md`, deviations 1 to 9), the
verification (`p3-sandbox-verify.md`, findings B1, B2, M1 to M3, m1 to m4, n1, n2, and its
"Contract points the five join changes must adopt" 1 to 5), owner decision 24, and the
review-fix report at `94fe628`. Where each landed:

| Source | Where | How |
| --- | --- | --- |
| Deviation 1 (caller shapes) | §2.2, §4.3, §4.6, §5, §5.2, §6.1, §6.4 | adopted from README "Cascade workflows" at `94fe628` |
| Deviation 2 (opm-operator owner question) | §2.4, §10, §15 item 2 | settled by decision 24 |
| Deviation 3 (`tree` semantics) | §7.6, §14 | adopted as corrected by m1 |
| Deviations 4, 5 (S5, S6) | §11.4, §14 | expectations replaced |
| Deviation 6 ((b) via (b2)) | §11.4 results | recorded |
| Deviation 7 / M3 (E6 toggle) | top, §11.4 E6 row | recorded as the supervisor's grant, confirmed |
| Deviation 8 (release numbering) | §11.4 results, E2 | recorded |
| Deviation 9 / B1 (RELEASING.md) | §14, §15 item 7 | amendments extended; still owed |
| B2 (stale contract) | this file | version 3 |
| M1 (dry-run switch in one place) | §5, §6.4, §9.1, §12 | adopted as shipped in `a2950ce` (required `dry-run` input) |
| M2 (pinned action ran `main`'s scripts) | §2.2, §2.4, §6.2 | adopted as shipped, including the receive workflow's `Own commit` checkout, which went one step past the brief |
| m1 | §7.6 | applied |
| m2 (exit-3 annotation) | §6.2 step 10, §12 | adopted as shipped |
| m3 (repo code can forge compute outputs) | §6.2 step 14, §14, §15 item 11 | recorded; not fixed |
| m4 (sandbox reach) | §11.5, §15 item 9 | open |
| n1 (release-please reads footers too) | §11.4 S6, §14 | applied |
| n2 (proxies) | §8.3, §11.4 | labelled |
| Join point 2 (concurrency byte-for-byte) | §5, §5.2 | unchanged expression, now asserted with `yq` |

Choices this version makes that no source fixed, flagged for the supervisor:

- **Before A merges, B branches pin A's branch head** with a distinct comment and swap in a final
  commit (§2.4). The alternative, a literal `<SHA>` placeholder in committed YAML, would make
  actionlint and every repo lint fail on the branch, so the B branches could not show green
  gates before review.
- **Header and job comments are free text**; everything else in §4.6 and §5.2 is byte-for-byte.
  The forbidden phrasing (the reusable workflow publishes, mints, or declares the Environment) is
  named so a reviewer can check it.
- **catalog_opm keeps `cue-version: v0.17.1`**, which its branch already passes. It equals the
  default, so it changes nothing today; it only makes the CUE pin visible in that repo.

## Version 3.1 notes [v3.1]

Source: the contract v3 review (`p3s-review.md`, findings 1 to 10; it found no blockers in the
code) and the supervisor's decisions for findings 2 and 3. Checked against `.github` PR #9 at
`99d93e5` (README "Pinning and bumps", archived design "Branch references under
`sha_pinning_required`", "Migration Plan" and task 5.10) and the five join branches at the heads
in §10.1.

| Finding | Where | How |
| --- | --- | --- |
| 1 (major, "no secret" text the B branches would keep) | §2.2 Secrets, §10.1 items 9 and 11 | replacement wording given verbatim, known sites listed, re-grep pattern widened with `no secret`, `not pass any secret`, `holds no` (case-insensitive) |
| 2 (major, `cascade-task.yml` at `ref: main`) | top item 2, Facts, §2.2, §2.4, §5.2, §10, §10.1 item 3, §14 | option (a), supervisor decision: the resolver `ref:` carries the repo's one SHA; bump grep `grep -rn 'open-platform-model/.github' .github/workflows`; reference counts 1 and 5; "changes nothing" now true for CI too |
| 3 (major, bump step 2 impossible once disarmed) | §2.4 step 2, §11.3, §11.5, §15 item 9 | "re-arm", supervisor decision: disarmed is the resting state; step 2 re-arms (key restored, up public, under decision 22), runs, disarms. **[v3.1.1]** Superseded by decision 26: no sandbox step |
| 4 (major, `yq` assertions not a CI gate, notify unchecked) | §5.2, §10, §10.1 item 6 | a verbatim `wiring-check.sh` run by `task cascade:wiring:check` as a step of each repo's existing required job on every PR; asserts environment, step count, exact permissions, the action `uses` regex, the key and Environment only in the two jobs, no `secrets` on `.github` calls, §5 strings, one SHA and the comment; core runs the notify subset. Tested on two fixtures and 13 mutations |
| 5 (minor, decision 24 over-credited) | top item 2, Sources, Facts, §2.4, §14, §15 item 13 | "decision 24 (actions), extended by the supervisor to the two reusable workflows" (and the resolver `ref:`), with the M2 reason; flagged for the owner |
| 6 (minor, no mechanical main-SHA check) | §1, §2.4 steps 1 and 4, §10, §10.1 pre-merge check | `gh api repos/open-platform-model/.github/compare/<SHA>...main --jq .status` is `identical` or `ahead`; read back: `99d93e5...main` prints `diverged` |
| 7 (minor, Dependabot) | Facts, §2.4, §10, §10.1 item 7 | ignore `open-platform-model/.github*` in library, opm-operator, cli; core and catalog_opm have no `dependabot.yml` |
| 8 (nit, two comment strings) | §2.4, §10.1 | one form, ` # feat/add-release-cascade-workflows`, as the seeds have it; `PIN_COMMENT` in the wiring check follows it |
| 9 (nit, R2 empty case) | §6.4 | the probe's own input default, `probe-dry.yml` at `fb8e76c` |
| 10 (nit, citations) | §12, §2.2, §2.4 | "two reusable workflows"; R1 dropped, E6 receiver run 37208176173 cited; the B pre-merge pin is "the head the supervisor hands each B" |

Choices this version makes that no source fixed, flagged for the supervisor:

- **The wiring check lives in `.tasks/cascade/wiring-check.sh` behind `task cascade:wiring:check`**,
  one script text for all five with a `RECEIVER` flag, next to `docs:pins:check` (the existing
  pattern for a CI-run consistency check). A `.github`-hosted shared check was not chosen: it
  would be one more cascade reference to pin, and the repo's CI must not depend on fetching it.
- **`PIN_COMMENT` lets a B's CI stay green while it pins A's branch head**, and the final pin
  commit flips it; the pre-merge check reads it. Without it, the strict comment check would keep
  every B red until A merges.
- **The wiring check also pins `client-id` and `private-key` byte for byte** and refuses
  `environment: cascade` on any other job, beyond the review's list; both close the same M1-class
  gap (a later edit moving the key or the Environment).
- **The re-grep's allowed hits are listed** (compute and gates "hold no secret" stays true), so
  an implementer does not rewrite correct text.

## Version 3.1.1 notes [v3.1.1]

Sources: the contract v3.1 review (`p3f-review.md`: 4 major, 6 minor, 4 nit, no blockers) and
owner decision 26 (the sandbox is dropped; it supersedes decision 25). The version a branch cites
stays "version 3.1".

| Finding | Where | How |
| --- | --- | --- |
| 1 (major, the check did not enforce "no repo code in the key job") | §2.2 Secrets, §5, §5.2, §10.1 items 6 and 9, script | exact key sets on `notify-downstream` and `publish`, their step (`name`, `uses`, `with`) and their `with` keys; `deps-cascade.yml` top-level keys exact; no `BASH_ENV`, `ENV` or `NODE_OPTIONS` in `release.yml`'s workflow `env`; item 9 says "no checkout or `run:` of its own … the action checks out the repo but never runs it". Re-tested: 24 mutations refused, 2 allowed edits pass, the five real-workflow fixtures pass |
| 2 (major, "uninstall the App" is no disarm) | §11.5, §15 item 9 | the uninstall alternative and "re-arming also reinstalls" are gone; deleting the key from the Environments is the disarm, and it is done |
| 5 (minor, "nothing changes until the pin moves") | §2.4 "What a pin runs", §14 | narrowed to the repo's cascade; `mention-guard` and a laptop `task deps:cascade` change at once |
| 6 (minor, the `check` instruction pointed at nothing) | §10 table, §10.1 item 6 | append `- task: cascade:wiring:check` to `check`'s `cmds` in core, catalog_opm, library, cli; opm-operator has no aggregate check in its `Taskfile.yml` or `Makefile`, so its required `lint.yml` `lint` job step is the equivalent |
| 9 (minor, `diverged` relied on a squash merge) | Facts, §2.4 step 1, §14 | `.github` is squash-only with PR_TITLE + BLANK (supervisor, 2026-10-04) |
| 10 (minor, nobody holds the key to re-arm) and decision 26 | top, Sources, Facts, §2.4 step 2 and "Sandbox", §4.5, §11, §11.3, §11.5, §12, §14, §15 items 9, 10, 13 | no re-arm at all; future wiring changes: offline suites, then a dry-run pin bump in one receiver (the canary), then the other repos; what the canary does not cover is stated and goes to the owner |
| 12 (nit, library's "ships it on main" comment and dead fallback) | §10.1 items 3 and 11 | library and opm-operator replace the S5 skip fallback with a hard failure and drop its comments; the re-grep gains `ships it on`, `resolver is on` |
| 13 (nit, pre-merge step 5 could not show `ref:`) | §2.4 step 3, §10.1 pre-merge step 5, §14 | `grep -rn -A1 'open-platform-model/.github' .github/workflows` |
| 14 (nit, drifts) | §14, §15 item 14 | the amendments sit on `docs/releasing-phase3-wiring` at `6ec574e`, not merged; README bump steps 3-4 lack the per-PR `compare` and wiring check, listed as an A follow-up |

Not applied here, because the fix is in another file: findings 3 (A's archived `contract.md`), 4
(the README's "at `main`"), 7 and 8 (RELEASING.md's Phase 3 status and wiring-check text), 11
(A's `design.md`). §15 item 14 lists the A-side ones.

Choices this version makes that no source fixed, flagged for the supervisor:

- **`NODE_OPTIONS` joins `BASH_ENV` and `ENV`** in the `release.yml` workflow-`env` denylist. The
  notify action runs node steps (`actions/create-github-app-token`) that read it at startup, and
  `release.yml` keeps a free workflow `env` in three repos, so a denylist is the most the check
  can assert there. It is a lint against a mistaken edit, not a boundary: the `main` ruleset and
  review stay the control for a deliberate one. **[v3.1.2]** Superseded for the join changes by
  the supervisor's addendum: a per-repo allow-list of `release.yml` top-level `env` keys (core
  `CUE_VERSION`, `CUE_REGISTRY`; catalog_opm `OPM_REGISTRY`, `CUE_REGISTRY`; opm-operator
  `REGISTRY`, `IMAGE_NAME`, `CUE_VERSION`; library and cli none), and `runs-on: ubuntu-latest`
  on every key-holding job. It is still a lint against mistakes.
- **The canary is a receiver**, never core: only a receiver's dry run runs `compute` and `gates`.
  Which receiver is the supervisor's pick per bump.
- **The S5 fallback becomes a hard failure** rather than staying with a new message, so a pin to
  a commit without the resolver fails the network job instead of skipping S5.
- ~~**Task 5.8 keeps one step** (deleting A's branch), gated on every B merged and both sandboxes
  archived, because B pre-merge pins and the sandbox pins name commits on that branch.~~
  **[v3.1.2]** Moot: `.github` deletes branches on merge, so merging A deletes the branch (§11.3).

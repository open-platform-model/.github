## Context

`tag-ledger` is the daily detection side of the org rule "release tags are immutable". The
rulesets prevent tag changes, and this workflow notices if prevention fails or is switched off.

- **Workflow.** `.github/workflows/tag-ledger.yml` runs on a schedule (`17 4 * * *`) and on
  `workflow_dispatch` with a `bootstrap` input. It has a single job, `tag-ledger` (job id
  `check`), with permissions `contents: write`, `issues: write` and `actions: read`, and
  `timeout-minutes: 10`. The workflow-level `env` sets
  `REPOS: core library catalog_opm cli opm-operator` (`tag-ledger.yml:47`).
- **Integrity check.** `.github/scripts/ledger-integrity.sh` checks the ledger branch against the
  anchor artifact. It never reads `REPOS`.
- **Scan.** `.github/scripts/tag-ledger.sh` does the rest:
  - It lists tags per repo with `git ls-remote --tags https://github.com/$ORG/$repo.git`
    (`:73`).
  - It compares against `ledger.tsv`, but only for repos scanned in the run (`:92-98`, `:114`).
  - It appends new rows.
  - It asserts three org rulesets per repo through `api_get` (`:158-166`), which uses
    `GH_TOKEN` and falls back to an anonymous request on 401/403.
  - Every per-repo step is a plain `for repo in $REPOS` loop (`:69`, `:248`) with no per-repo
    branch.

Workspace `AGENTS.md`, section "Release Tags Are Immutable", sets the scope to `core`,
`library`, `catalog_opm`, `cli`, `opm-operator` and `opm`, plus the private
`release-flow-sandbox`. Workspace RELEASING.md, section "Release order" (lines 50-53), names
`opm` a releasing repo that is outside the cascade but inside the tag rule.

Live state on 2026-10-04:

| Item | Value |
| --- | --- |
| `opm` | public, default branch `main`, one tag `v1.0.0-beta.1` (lightweight, commit `83a4756d4fe53c7b704d871e232d432fd5c96921`) |
| `opm` org rulesets | `tags-immutable` 24307318, `tags-create-app-only` 24306688, `release-branches` 24306642, all `Organization`/`open-platform-model`, active; the same ids as `core` |
| `opm` releases | through `release.yml` with the `opm-release-please` App (`vars.RELEASE_APP_CLIENT_ID`), the bypass actor `tags-create-app-only` expects |
| ledger branch | `tag-ledger` at `7c54ec1`, 212 rows (core 28, library 48, catalog_opm 49, cli 41, opm-operator 46); last three runs green, no open drift issue |
| anonymous `GET /repos/open-platform-model/opm/rulesets?includes_parents=true&targets=tag` | 200 |

Phase 3 wiring contract (`p3-wiring-contract.md`) does not mention the tag ledger. Its §1 merge
order covers `add-release-cascade-workflows` and the five `join-release-cascade` changes only.
This change has no ordering constraint with them.

## Goals / Non-Goals

**Goals:**

- Make `tag-ledger` scan `opm` with exactly the treatment of the other five repos.
- Make the README's tag-ledger scope match `REPOS`.
- Make the README's mention-guard "Limits" paragraph say that a ruleset-required run ignores
  `edited`, and how to get a fresh scan.
- Show, by running the real script, that the five existing repos behave byte-identically.

**Non-Goals:**

- Any change to `tag-ledger.sh`, `ledger-integrity.sh` or the workflow's triggers, permissions,
  timeout, issue handling or step logic.
- Any change to `mention-guard.yml`.
- Scanning `release-flow-sandbox` or any private repo.
- A committed tag-ledger test suite.

## Decisions

### D1. One-line scope change in the workflow env

`tag-ledger.yml:47` MUST become `REPOS: core library catalog_opm cli opm-operator opm`, with
`opm` appended last so the existing order, and with it the order of the ledger rows each run
appends, is unchanged for the other five. No other line of `tag-ledger.yml` and no line of
either script MAY change.

- **Triggers:** unchanged, `schedule` `17 4 * * *` and `workflow_dispatch` (`bootstrap`).
- **Job name:** unchanged, `tag-ledger`. No ruleset requires it, and it never runs on PRs.
- **Permissions:** unchanged, `contents: write`, `issues: write`, `actions: read`.
- **Timeout:** unchanged, 10 minutes.

The run time grows by one `ls-remote` and up to six API calls, which is negligible.

### D2. Network requests added per run

| Request | Host and path | Auth | Expected | Failure handling (unchanged code) |
| --- | --- | --- | --- | --- |
| `git ls-remote --tags` | `github.com/open-platform-model/opm.git` | none | exit 0, one line per tag (two for an annotated tag) | non-zero aborts the scan (`set -e`, `:71-73`), the job fails, and the Report step files the failure as a finding |
| list tag rulesets | `api.github.com/repos/open-platform-model/opm/rulesets?includes_parents=true&targets=tag&per_page=100` | `GITHUB_TOKEN`, anonymous on 401/403 | 200 | 404 is a finding; any other status exits 3 (`:178-186`) |
| list branch rulesets | the same path with `targets=branch` | as above | 200 | as above |
| read ruleset | `api.github.com/repos/open-platform-model/opm/rulesets/{id}`, once for each of the three that exist | as above | 200 | non-200 is a finding (`:204-207`) |

`opm` is public, so `GITHUB_TOKEN` of `.github` can read it the same way it reads the other five.

### D3. README wording

**Tag-ledger scope** (`README.md:90-91`). Becomes:

> Scope: `core`, `library`, `catalog_opm`, `cli`, `opm-operator`, `opm` (the repos that
> release). `modules` is out of scope. The list is `REPOS` in the workflow.

**Mention-guard "Limits"** (`README.md:70-73`). Keeps its two existing limits and adds a third,
in this substance:

> A run required by the org ruleset fires only on `opened`, `synchronize` and `reopened`.
> GitHub ignores the `edited` type that `mention-guard.yml` lists, so editing a title or body
> after a run does not rescan it. "Re-run jobs" rescans the text from the original event, not
> the edit. For a fresh scan, push a commit, or close and reopen the PR.

The exact sentences are written at apply time. They MUST NOT contain a bare `@word` and MUST
stay consistent with workspace RELEASING.md, section "Owner settings" (lines 477-478).

### D4. Verification

Verification MUST run before each section's commit, from the scratchpad
(`p3-gh-ledger-*`). It MUST NOT dispatch `tag-ledger.yml` from the feature branch. Such a run
would find `main`'s anchor, push rows to the shared `tag-ledger` branch from an untrusted ref,
and upload an anchor artifact that the next `main` run ignores. Its rows would then show up as
"not written by a trusted run" notices and open the drift issue.

**V1, offline equivalence.** Run `tag-ledger.sh` from the worktree with PATH shims:

- **`git` shim.** Answers only `ls-remote --tags https://github.com/open-platform-model/<repo>.git`
  from `<fixtures>/<repo>.refs`, and exits 2 on anything else.
- **`curl` shim.** Accepts the `api_get` shape (`-sS -o <file> -w '%{http_code}' -H … <url>`). It
  writes the body from `<fixtures>/api/<path with ? as %3F>` and prints the status, defaulting to
  200 when the body exists and 404 when it does not.
- **Fixtures.** Captured once, read-only:
  - `git ls-remote --tags` for the six repos;
  - the tag and branch ruleset listings and the three ruleset bodies, read anonymously for
    `core` and `opm`.
- **Starting ledger.** `git show origin/tag-ledger:ledger.tsv`.
- **Environment.** `GH_TOKEN` unset, `ACK_FILE=tag-ledger/acknowledged.tsv`, and separate
  `FINDINGS` and `WARNINGS` files per run.

| Case | REPOS | Ledger | MUST hold |
| --- | --- | --- | --- |
| E-old | old five | copy A | exit 0; empty FINDINGS |
| E-new | new six | copy B | exit 0; empty FINDINGS; ledger B minus `opm` rows is byte-identical to ledger A; the added `opm` rows are exactly the rows of `opm.refs`; WARNINGS(B) is WARNINGS(A) plus the `opm` lines, each the matching `core` line with `core` replaced by `opm` |
| E-moved | new six | B plus an `opm` row whose SHA differs from `opm.refs` | `tag CHANGED` finding naming `opm` |
| E-deleted | new six | B plus an `opm` row for a tag absent from `opm.refs` | `tag DELETED` finding naming `opm` |
| E-revert | old five | ledger B (with `opm` rows) | empty FINDINGS; `opm` rows still present |
| E-ruleset | new six | B | with `tags-immutable` removed from the `opm` tag listing: a finding naming `opm` and `tags-immutable` |

**V2, read-only live run.** Run `tag-ledger.sh` once with the six repos against the real
services:

- use a scratch copy of the live ledger, with `GH_TOKEN` unset;
- the run makes at most 36 anonymous API calls, under the anonymous limit of 60 per hour.

It MUST exit 0 with an empty FINDINGS file. The appended rows MUST include
`opm v1.0.0-beta.1 83a4756d…` and otherwise only tags the remote gained after the ledger's last
row. It writes nothing outside the scratch directory.

**V3, after merge.** The supervisor reads the first scheduled run's job summary. It MUST show
`Repos: core library catalog_opm cli opm-operator opm.`, `New tags recorded:` at least 1, no
Drift section, and no new issue. This step is outside `tasks.md`, because it needs the merged
`main`.

### D5. Sections and commits

- **Section 1, tag-ledger scope.** `tag-ledger.yml` and the README scope line, verified by V1
  and V2. Commit `ci(tag-ledger): scan the opm repo for tag drift`.
- **Section 2, mention-guard Limits paragraph.** Commit
  `docs(mention-guard): say a ruleset run ignores edited`.

The archive is not part of this run. Per the repo config it rides the implementing PR later.

## Research & Decisions

### Which repos to add

- **Context.** `AGENTS.md` names seven repos in the immutable-tag scope. `REPOS` names five.
- **Options:**
  1. Add `opm` only.
  2. Add `opm` and `release-flow-sandbox`.
- **Decision:** add `opm` only.
- **Rationale.** `release-flow-sandbox` is private (`gh api repos/open-platform-model/release-flow-sandbox`
  reports `private`).
  - `tag-ledger.sh:73` reads tags anonymously, and a failed listing aborts the whole scan by
    design (`:71-72`). Adding it would turn every run red.
  - Covering private repos would need a token with read access to them. That is a change to the
    workflow's trust model (README "Token"), and it would cover a repo that exists to exercise
    the release flow. If the owner wants it covered, that is a separate change.
  - The same holds for `cascade-sandbox-up` and `cascade-sandbox-down`. They are throwaway
    sandboxes, and the Phase 3 wiring contract creates their tags only to simulate releases.

### How to test an unchanged script

- **Context.** `tag-ledger.sh` has no offline test suite. The repo's gate 3 runs only
  `.github/scripts/cascade/test/run.sh`, and `cascade-resolver.yml` runs only that suite.
- **Options:**
  1. A scratch-run equivalence check plus a read-only live run (V1, V2).
  2. Commit a `tag-ledger` test suite with shims, and wire it into CI.
- **Decision:** option 1.
- **Rationale.**
  - The change moves no script line, so the property worth proving is "same output for the five,
    and `opm` treated like them". V1 proves that against the real script and live-captured data.
  - Option 2 would add new files under `.github/scripts/`. It would also need a CI job, either
    inside `Resolver tests` (the wrong owner) or a new one that the owner would have to add to the
    `main` ruleset. And `.github` `add-release-cascade-workflows` is editing the same CI surface
    in parallel.
  - A committed suite is worth having as its own change.

### Finding 4 is a real defect

- **Context.** The Phase 2 README review routed finding 4 ("Limits" omits that a
  ruleset-required run ignores `edited`) to a follow-up.
- **Evidence:**
  - GitHub's ruleset docs: ruleset workflows run on the default `pull_request` types, and type
    filters are disregarded.
  - The org runs on core#86, modules#28 and modules#43 (from the Phase 1 review): a body edit
    was followed by no run, and only a reopen gave a fresh one.
  - `mention-guard.yml:101` reads `context.payload.pull_request`, so a re-run rescans stale
    text.
  - Workspace RELEASING.md lines 477-478 rely on the same fact.
- **Decision:** fix it here as section 2.
- **Rationale.** A reader of `mention-guard.yml:34` is misled today. The fix is one paragraph of
  the same README, and the supervisor's task names it.

## Risks / Trade-offs

- **The first run after merge appends `opm` rows and reports them as new.** This is expected, and
  it is not drift. → V3 confirms it, and no issue is opened because appended rows are neither
  findings nor notices.
- **`opm` later leaves an org ruleset**, for example if the owner scopes a ruleset by repo list
  instead of all repos. → From now on that is a finding, which is the point. The owner then fixes
  the ruleset, not this list.
- **README merge conflict with `add-release-cascade-workflows`.** → The edits are in different
  sections. Whichever branch merges second runs `git merge origin/main`.
- **The README wording about GitHub's `edited` handling relies on documented behaviour and org
  history, not on a GitHub guarantee.** → The wording describes what happens and how to get a
  fresh scan, which stays correct even if GitHub later starts honouring `edited`.

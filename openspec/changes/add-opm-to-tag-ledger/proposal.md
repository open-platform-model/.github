## Why

The `tag-ledger` drift check covers five of the six repos that release. The `opm` repo is
missing.

- Workspace `AGENTS.md`, section "Release Tags Are Immutable", puts `opm` in scope:
  "`core`, `library`, `catalog_opm`, `cli`, `opm-operator`, `opm`". Workspace commit `f4d7317`
  ("scope opm into the release-tag rules") added it there.
- Workspace RELEASING.md, section "Release order" (lines 50-53), says `opm` releases on its own
  train with release-please. Its tags are `vX.Y.Z` with no component prefix, and the first one is
  `v1.0.0-beta.1`. It "is still a releasing repo for 'Release Tags Are Immutable' in `AGENTS.md`
  and for 'Owner settings'".
- The ledger's scan list predates that. `.github/workflows/tag-ledger.yml:47` reads
  `REPOS: core library catalog_opm cli opm-operator`, and `README.md:90-91` repeats the five
  names as the scope.
- As a result, a moved or deleted `opm` tag, or an `opm` repo that drops out of the org
  `tags-immutable` ruleset, is never detected. Today `opm` has one tag (`refs/tags/v1.0.0-beta.1`, commit
  `83a4756d`) and the same three org rulesets as `core`: `tags-immutable` (24307318),
  `tags-create-app-only` (24306688) and `release-branches` (24306642), all active. Checked with
  `gh api repos/open-platform-model/opm/rulesets?includes_parents=true` on 2026-10-04.

The Phase 2 README review found a second, unrelated defect in the same file and routed it to a
follow-up. This change fixes it as well, in its own section, because it is a single paragraph
in a file this change already edits.

- The mention-guard "Limits" paragraph (`README.md:70-73`) does not say that a run required by
  a ruleset ignores the `edited` event.
- `mention-guard.yml:34` lists `edited` in `on:`, so a reader assumes that editing a title or
  body triggers a rescan. It does not.
  - GitHub's ruleset docs ("Require workflows to pass before merging") say ruleset workflows
    use the default `pull_request` types (`opened`, `synchronize`, `reopened`) and ignore type
    filters.
  - Org history agrees: on core#86, modules#28 and modules#43, a body edit was followed by no
    run, and only a close and reopen produced a fresh one.
  - The guard reads the title and body from `context.payload.pull_request`
    (`mention-guard.yml:101`, `:118-119`), so "Re-run jobs" rescans the old title and body. Commit
    messages are listed fresh through `pulls.listCommits` (`mention-guard.yml:120`).
- Workspace RELEASING.md, section "Owner settings" (lines 477-478), already states this as the
  premise of the `BLANK` squash decision.

## What Changes

- **Ledger scope.** In `.github/workflows/tag-ledger.yml`, change `REPOS` to
  `core library catalog_opm cli opm-operator opm`. Nothing else in the workflow or in
  `.github/scripts/tag-ledger.sh` changes: the script loops over `$REPOS` with no per-repo logic
  (`tag-ledger.sh:69`, `:248`).
  - `opm`'s tags are appended on the next trusted run.
  - Its three org rulesets are checked exactly as for the other five: `tags-immutable` is
    required, so a missing one is a finding; `tags-create-app-only` and `release-branches` are
    still `pending` in `tag-ledger.sh:250-251`, so a missing one is only a warning and the run
    stays green.
  - Existing ledger rows are untouched.
- **README, tag-ledger.** `README.md:90-91` gains `opm` in the scope list.
- **README, tag-ledger rulesets.** Step 4 of the tag-ledger list gains one sentence: all three
  rulesets now exist on every scanned repo, but the two planned ones stay pending in the script
  until a follow-up makes them required.
- **README, mention-guard Limits.** The paragraph at `README.md:70-73` states that:
  - a ruleset-required run does not re-fire on `edited`;
  - a re-run reads the title and body from the original event, while commit messages are listed
    fresh;
  - the way to get a fresh scan after editing a title or body is to close and reopen the PR, or
    push a commit.
- **Verification**, not committed: a read-only live run of `tag-ledger.sh` against a scratch copy
  of the ledger that records every response, then an offline equivalence run that replays those
  responses through `git`, `curl` and `date` PATH shims (`design.md`, D4). The six-case result
  table and the live-run summary go into the PR body.

Not in this change:

- Any behaviour change to `tag-ledger.sh`, `ledger-integrity.sh` or the workflow's steps,
  permissions, schedule or issue text.
- `mention-guard.yml` itself. Its `edited` type stays: it is harmless, and in this repo the
  workflow also runs as a normal workflow, where `edited` does fire.
- `release-flow-sandbox`. `AGENTS.md` lists it in the immutable-tag scope, but it is private,
  and `tag-ledger.sh:73` lists tags with an anonymous `git ls-remote`, which cannot read it
  (`design.md`, "Research & Decisions"). Whether it is covered is an open owner decision; until
  then it is excluded by name, not by an access rule.
- A committed offline test suite for `tag-ledger.sh`, and a CI job to run it. That is a follow-up
  (`design.md`, "Research & Decisions").
- Follow-ups, each its own change or PR:
  - The README intro (`README.md:3-4`, "hosts two things"), which no longer mentions the
    `cascade` section.
  - The workspace `.claude/skills/commit/SKILL.md` "five releasing repos" line.
  - The guard's own failure hint, `mention-guard.yml:145` ("**Fix:** edit the PR title in the web
    UI"), which names exactly the action that does not rescan. A separate PR changes it to edit
    the title, then push a commit or close and reopen the PR. It is separate because the org
    ruleset reads that file by path from `main`.
  - Workspace `AGENTS.md:206-210` ("Pending for `opm`", checked 2026-10-03) says `opm` is outside
    `tags-immutable` and `tags-create-app-only` with immutable releases off. Live on 2026-10-04,
    rulesets 24307318 and 24306688 apply to `opm` and immutable releases are on. A workspace PR
    moves `opm` to the active controls, as `AGENTS.md:213` asks.
  - Stale tag-ledger docs: `README.md:127-130` says bypass assertions are listed under "Not
    verified", but the summary heading is "Warnings (not verified, pending or acknowledged)"
    (`tag-ledger.yml:183`). `README.md:116-119` and the header comment at `tag-ledger.yml:14-16`
    still call `tags-create-app-only` and `release-branches` planned, although all three
    rulesets exist.
  - Make `tags-create-app-only` and `release-branches` required: change `pending` to `required`
    in `tag-ledger.sh:250-251`, and add an offline case for a missing `tags-create-app-only`.
    All three rulesets now apply to all six repos (V2 saw 18/18), so the pending state is over;
    until that change, a repo dropping out of either ruleset is only a warning. It goes with the
    stale-docs item above, since both come down to the end of the pending state.
  - A committed offline test suite for `tag-ledger.sh` (see above).

## Capabilities

### New Capabilities

- `tag-ledger`: the set of repos the daily tag-ledger check scans, and what joining or leaving
  that set does to the ledger. Only this part of `tag-ledger` is specified here. The rest of its
  behaviour predates OpenSpec in this repo and is documented in `README.md`.

### Modified Capabilities

None.

## Impact

- **Files:** `.github/workflows/tag-ledger.yml` (one line), `README.md` (three paragraphs) and this
  change's artifacts.
- **Affected workflows and scripts:** `tag-ledger.yml` (job `tag-ledger`, scheduled daily at
  04:17 UTC and `workflow_dispatch`) and `tag-ledger.sh`, unchanged.
  - No other repo calls them. The scanned repos are only read.
  - `mention-guard.yml`, which every org repo runs through ruleset 20657243, is not edited.
- **Network:** each run makes one more anonymous `git ls-remote --tags` to
  `github.com/open-platform-model/opm.git`, and three more ruleset listings to `api.github.com`
  with up to three detail reads. The `ls-remote` is anonymous; the API calls use the workflow
  token, retried anonymously on 401/403 (`tag-ledger.sh:158-166`).
- **First run after merge:** the next scheduled run appends `opm`'s tags (one today) as new rows,
  reports "New tags recorded: N" in the job summary and opens no issue. No bootstrap is needed.
  The anchor and integrity logic (`ledger-integrity.sh`) does not depend on `REPOS`.
- **Depends on:** nothing. Workspace RELEASING.md, section "Rollout and changes", does not order
  this change. It does not depend on `.github` `add-release-cascade-workflows`, nor that change
  on it. They share `README.md` only, in different sections, so whichever merges second takes
  `git merge origin/main`.
- **Depended on by:** nothing.
- **Gates:** the repo's validation gates (`shellcheck`, `actionlint`, the offline cascade suite,
  `openspec validate --all --strict`) plus the verification runs in `design.md`. The required
  checks on the PR are `Resolver tests` and `mention-guard`.
- **Owner steps:** none. After merge the supervisor reads the first scheduled run's summary
  (`design.md`, "Verification"), and never dispatches the workflow from the feature branch.
- **Release class:** none. `.github` does not release.

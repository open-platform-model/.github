## Context

The guide for this work is the approved rewrite guide of swarm openspec-requirement-split (section numbers below refer to it). The rule: the body of a requirement is the text between its header and the first line that starts with `#`, without blank, fenced and `**Key**:` lines; more than 500 UTF-16 units is a WARNING. The check runs on main specs and on ADDED blocks, not on MODIFIED blocks. A MODIFIED block that stays over 500 passes `validate <change> --strict` and then fails `validate --all --strict` after archive.

Measured on `origin/main` 48e9ead (OpenSpec 1.14.1): `validate --all --strict` prints 55 WARNING lines. Per spec (`validate <spec> --type spec --strict`): cascade-gates 4, cascade-notify 2, cascade-pr-text 4, cascade-receive 13, cascade-resolver 9, cascade-resolver-checks 5, cascade-wiring-check 8, cascade-workflows 9, tag-ledger 1, cite-lint-workflow 0. This equals the inventory of explore/T1.3 (55 in 9 specs). Excess kinds in that inventory: almost all "several behaviors" plus format or list.

## Research & Decisions

### D1. Which form per requirement

Options: (a) shorten in place with MODIFIED and move detail into new scenarios; (b) MODIFIED parent plus ADDED splits; (c2) REMOVED plus ADDED under new names; (d) RENAMED plus MODIFIED. Status quo (leave the warnings and drop `--strict`) is rejected: the human ordered the gate.

Decision: read each requirement, then pick by the guide table.

| The excess is | Form |
| --- | --- |
| Examples, lists, formats or rationale around one behavior | a |
| Several behaviors; the old scenarios fit the parent that stays | b |
| Several behaviors; the old scenarios belong to different behaviors | c2 |
| A name that must change with no change of rule | d, alone |

Most requirements of this repo hold several behaviors (T1.3 marks 52 of 55 as "several behaviors"), so b and c2 are the common forms and a is the second. The T1.3 kind label is a heuristic: the author reads the text. Reversibility: high (hours). A wrong split is fixed by a new rewrite before archive.

Trade-off: c2 gives the cleanest one-behavior blocks but it is the only form that may lose a scenario without an error, so it carries the ledger (D2). Form a and b keep every scenario by name, which the repo rule requires for MODIFIED.

### D2. Scenario ledger

The repo rule (`openspec/config.yaml`, specs) says a MODIFIED requirement keeps every scenario of the main spec, and a rename that drops one uses REMOVED plus ADDED. OpenSpec checks this for MODIFIED but does not check scenarios under c2. So this design.md holds, for every rewritten requirement, a ledger block in this form, written by the unit that writes the delta:

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |

plus a second table for each clause that leaves the body: old clause, new place. Rules: a, b and d keep each old name byte for byte under the same requirement; c2 shows each old name in one new requirement; a moved scenario keeps its WHEN and THEN byte for byte ("Changed text?" is "no" except where a clause table names the change); keywords SHALL and MUST stay in every body; citations (`Source:` lines, `workspace RELEASING.md` sections, reasons with an enhancement id) stay in the body of the block that carries the rule, never in a header; no `**Key**:` line, no `#####` heading and no fenced block in a body (loopholes). A unit adds its ledger blocks to this file in the same commit as its delta. Before a rename or split the unit greps the repo (excluding `openspec/changes/archive`) for the old header text: `references/`, `README.md` and the workflow comments cite some requirement names.

New ADDED requirements follow the repo rule "scenarios that demonstrate requirements" and include the rejected case when the behavior has one (for example the exit code of a refusal), using only words of the old body.

### D3. Batches and order

Decision: two units in sequence on one branch: B1 (28), then B2 (27), then the CI step, then `AGENTS.md`, then the final gate. T1.3 sets the batches (first-fit decreasing, cap 28, whole specs, no spec in two batches). Why B1 first: it is the larger one and holds `cascade-resolver-checks`, the spec that names the CI job, so the new CI requirement (D5) lands in a spec already open in this change. No collision exists: `openspec/changes/` holds no other open change, so no MODIFIED block of another author can go stale.

One caveat: the CI step must come after B2. With 27 warnings left, the step would fail its own PR. Inside one PR the group order is the commit order, and every group ends green under the repo gates, but `openspec validate --all --strict` is green only after group 2. Group 1 therefore ends green under gates 1 to 3 and under the guide gate of D4 (warnings fell by 28, no new ERROR).

### D4. The gate per unit

Run in a scratch copy of `openspec/`, never in the worktree, with the pinned 1.14.1 CLI. Paths for this repo: `WT` is the worktree `agent-swarm/openspec-requirement-split/worktrees/.github-split-long-requirements`, `CH` is `split-long-requirements`, `S` is a scratch folder. The block of guide section 6 runs unchanged:

- Baseline from `git -C $WT archive main openspec` (not from the worktree), copy of `$WT/openspec` for the change.
- It runs `validate $CH --strict`, `archive $CH --yes` in the copy, `validate --all --strict`, and fails on any line "Archive would refuse" and on any ERROR item (type, id, path) that main does not have.
- Unit B1: `N` = 28, so warnings must fall from 55 to 27. Unit B2: `N` = 55 and `LAST=1` (no unit follows in the rewrite, the CI step and `AGENTS.md` touch no spec text other than D5): after the archive `validate --specs --strict` must exit 0. Because this repo has no other open change, `validate --all --strict` is also expected to exit 0 and is reported.
- After each unit also run `openspec validate <spec> --type spec --strict --json` for the batch specs, and the scenario check of guide checklist item 3 (script `same:`, `new:`, `DIFF:`, `LOST:` lines) per rewritten requirement. A `DIFF` or `LOST` line stops the unit.
- `validate <change> --strict` alone is not enough: it skips long MODIFIED text.

### D5. The CI gate

Options: (1) a step in the existing `Resolver tests` job; (2) a new job in `cascade-resolver.yml`; (3) a new workflow; (4) a Taskfile with `openspec:check` (what cli does). The status quo is no gate.

Decision: option 1. Reasons: the human ruled "CI workflow step only, no Taskfile" because the repo has none (DECISIONS 2026-10-19 12:08). The spec of that workflow says it adds no new job and no new check context, and `Resolver tests` is the required check that already reports on every PR with no path filter (Principle III). A new job or workflow would add a check context that no ruleset requires, so it would not gate merges, or it would need an owner ruleset edit that this change must not do.

Details of the step, for task group 3:

- Name: `OpenSpec`. Position: after `actionlint`, before the offline suites, so a spec error fails fast.
- Install: `npm install --prefix "$RUNNER_TEMP/openspec" --ignore-scripts @fission-ai/openspec@1.14.1`, then add `$RUNNER_TEMP/openspec/node_modules/.bin` to `GITHUB_PATH`. Node and npm come with the runner image, so no new third-party action and no `setup-node` pin. The exact version is the pin; `--ignore-scripts` follows the supply-chain rule on install scripts. Open question for the implement unit: confirm that 1.14.1 needs no install script (it is verified by running the install in a scratch folder before the edit). If the package needs one, the unit stops and asks.
- Run: `OPENSPEC_TELEMETRY=0 openspec validate --all --strict --no-interactive`. Telemetry off keeps the job free of calls to hosts it does not need (Principle I).
- No new permission: the job keeps `contents: read`. The 10-minute timeout stays.
- `openspec --version` is printed and compared to `1.14.1`; a different version fails the step, so the pin cannot drift silently.
- The workflow comment header gains one line that names the step. The step list is stated in the spec through one new requirement in `cascade-resolver-checks` (ADDED, one behavior, scenarios: a spec with a long requirement fails the job; the job reports on every pull request). The existing requirement for this workflow is rewritten in B1 only for length, and its meaning stays: the new step is a separate requirement, so no existing clause changes.
- Consequence (negative): a required check now also fails when a future PR adds an over-500 requirement or breaks a spec; authors of specs must keep requirements short. Operational: the OpenSpec pin is one more version to bump by hand; the owner is whoever bumps the skills. The same version string is in `.claude/skills/*/SKILL.md` (`generatedBy`), so a bump touches both.
- Revisit trigger: OpenSpec 1.15 or a repo Taskfile.

Reversibility: high (hours); the step is removed by one commit.

### D6. Security

Assets: none new. Trust boundary: the job downloads one npm package at a pinned version on a runner with `contents: read` and no secrets. Baseline: the repo's workflow principles (`openspec/config.yaml`, Principle I) and the supply-chain rules (pin, no install scripts). Residual risk: the npm registry serves a tampered 1.14.1 (no checksum available through npm as the other steps have); owner: the repo owner; accepted because the job holds no secret and a read-only token. Alternative to lower it later: a lockfile with integrity hashes.

## Scenario ledger

Each unit appends its blocks here (form D2) in the commit of its delta.

### Batch .github-B1: scenario ledger

One table per rewritten requirement. "Changed text?" is "no" for every row: the scenario check of the guide prints `same:` for each of them. The group 1 delta holds 28 rewritten requirements.

### cascade-receive

Requirement "Receive interface and job split" (1662 characters, form a/b (MODIFIED, name kept)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Bad gate mode | Receive interface and job split, Bad gate mode | no |

Requirement "Dry run fails closed" (1529 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Dry run pushes nothing | A dry run still writes the summary, Dry run pushes nothing | no |
| Forged dry-run output | Publish runs only when every live condition holds, Forged dry-run output | no |
| Caller if: lets a dry run through | The publish action publishes only on a false dry-run input, Caller if: lets a dry run through | no |
| Dry-run input not a boolean | The publish action publishes only on a false dry-run input, Dry-run input not a boolean | no |
| Branch run is a dry run | Compute treats other refs and gates-only runs as dry runs, Branch run is a dry run | no |
| Stop switch in another letter case | The stop switch variable is case-insensitive, Stop switch in another letter case | no |

Requirement "Payload is a validated hint" (1335 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Hostile payload | Payload is a validated whole, Hostile payload | no |
| Nine tags | Payload is a validated whole, Nine tags | no |
| Tag with a trailing newline | Payload strings are matched whole, Tag with a trailing newline | no |
| The renamed repo's release reaches cli | A valid payload sets the cascade variables, The renamed repo's release reaches cli | no |

Requirement "Mode selection" (1079 characters, form a/b (MODIFIED, name kept)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Human commit survives | Mode selection, Human commit survives | no |
| Bot-only branch is rebuilt | Mode selection, Bot-only branch is rebuilt | no |

Requirement "Task run, commit and Notes" (1163 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| CRLF body is stable | Notes are kept byte for byte, CRLF body is stable | no |
| Body rewritten by a human | Notes are kept byte for byte, Body rewritten by a human | no |
| A branch that edits the task | Merge mode runs main's task, A branch that edits the task | no |

Requirement "Final title" (552 characters, form a/b (MODIFIED, name kept)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Human retitle kept | Final title, Human retitle kept | no |
| Marker pasted into the Notes | Final title, Marker pasted into the Notes | no |

Requirement "Labels" (1396 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Breaking release in the middle of the range | Planned labels are a union, Breaking release in the middle of the range | no |
| A plan that drops the labels | Publish derives the labels again, A plan that drops the labels | no |
| A live label is never removed | The bot only adds labels, A live label is never removed | no |

Requirement "Workflows guard" (995 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Main changed a workflow under a bot-only PR, shipped rule | The workflows guard rule ships as tree, Main changed a workflow under a bot-only PR, shipped rule | no |
| Main changed a workflow under a human commit, shipped rule | The workflows guard rule ships as tree, Main changed a workflow under a human commit, shipped rule | no |
| Main changed a workflow under a bot-only PR | The workflows guard limits what the bot pushes, Main changed a workflow under a bot-only PR | no |
| Main changed a workflow under a human commit | The workflows guard limits what the bot pushes, Main changed a workflow under a human commit | no |

Requirement "Publish verifies before it mints" (1147 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Hold added between compute and publish | A hold added after compute stops publish, Hold added between compute and publish | no |
| Human push between compute and publish | Publish treats the plan as untrusted, Human push between compute and publish | no |
| Forged plan | Publish treats the plan as untrusted, Forged plan | no |

Requirement "Gates-only runs never publish" (804 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Forged outputs on a gates-only run | A gates-only run never writes, Forged outputs on a gates-only run | no |
| Missing gates-only input | cascade-publish checks the gates-only input first, Missing gates-only input | no |
| Gates-only outputs come from the input | Receive outputs for a gates-only run, Gates-only outputs come from the input | no |

Requirement "Publish bounds the bot's increment" (2127 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| A bundle that edits the cascade task | The deny-list wins over the allow-list, A bundle that edits the cascade task | no |
| A bundle that edits the Taskfile | The deny-list wins over the allow-list, A bundle that edits the Taskfile | no |
| A symlink | Publish limits what a single-parent commit changes, A symlink | no |
| A commit the bot did not make | Publish bounds the increment's commits, A commit the bot did not make | no |
| A rebuild over a human commit | Publish refuses to drop a human commit, A rebuild over a human commit | no |
| A pin moved to a forged tag | Publish checks the tag of each moved pin, A pin moved to a forged tag | no |
| A recreate over a kept human commit | Publish refuses to drop a human commit, A recreate over a kept human commit | no |
| Merge mode with a human commit | Publish bounds the increment's commits, Merge mode with a human commit | no |
| cli's operator module pin file | Allow-lists live in .github, cli's operator module pin file | no |
| opm-operator's module | The deny-list wins over the allow-list, opm-operator's module | no |
| The renamed repo's module | The deny-list wins over the allow-list, The renamed repo's module | no |

Requirement "Publish renders the PR text" (778 characters, form a/b (MODIFIED, name kept)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Text planted above the Notes marker | Publish renders the PR text, Text planted above the Notes marker | no |
| Notes come from the live PR | Publish renders the PR text, Notes come from the live PR | no |

Requirement "Publish refuses a stale mirror" (1573 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| pins.sh changed on main | Publish refuses a plan from a stale mirror, pins.sh changed on main | no |
| classes removed from main | Publish refuses a plan from a stale mirror, classes removed from main | no |
| cascade.sh changed on main | Publish refuses a plan from a stale mirror, cascade.sh changed on main | no |
| A stale mirror does not hold a close | A stale mirror does not hold other actions, A stale mirror does not hold a close | no |
| An unrelated change on main | Publish refuses a plan from a stale mirror, An unrelated change on main | no |
| cli's module pin in the body | The cli mirror reports the controller pins, cli's module pin in the body | no |
| cli's pin file after its rename | The cli mirror reports the controller pins, cli's pin file after its rename | no |

### cascade-resolver

Requirement "One entry point with fixed exit codes" (570 characters, form a/b (MODIFIED, name kept)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Unknown subcommand | One entry point with fixed exit codes, Unknown subcommand | no |
| Malformed version argument | One entry point with fixed exit codes, Malformed version argument | no |
| Missing tool | One entry point with fixed exit codes, Missing tool | no |

Requirement "SemVer 2.0.0 precedence" (569 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Numeric identifiers compare by value | The resolver orders versions by SemVer 2.0.0 precedence, Numeric identifiers compare by value | no |
| Release above prerelease | The resolver orders versions by SemVer 2.0.0 precedence, Release above prerelease | no |
| Alphanumeric above numeric identifier | The resolver orders versions by SemVer 2.0.0 precedence, Alphanumeric above numeric identifier | no |
| Longer list above its prefix | The resolver orders versions by SemVer 2.0.0 precedence, Longer list above its prefix | no |
| Build metadata ignored | The resolver orders versions by SemVer 2.0.0 precedence, Build metadata ignored | no |
| Sort ascending | semver-cmp and semver-sort have fixed output, Sort ascending | no |

Requirement "Candidate rules for newest" (831 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Dev builds skipped | Newest considers only valid candidates, Dev builds skipped | no |
| Stable line ignores prereleases | Newest considers only valid candidates, Stable line ignores prereleases | no |
| Unpublished newest keeps the pin | Newest exits 3 when nothing newer is published, Unpublished newest keeps the pin | no |
| Skip to an older published candidate | Newest probes the ten newest candidates, Skip to an older published candidate | no |
| Ten unpublished candidates | Newest probes the ten newest candidates, Ten unpublished candidates | no |
| Never backwards | Newest exits 3 when nothing newer is published, Never backwards | no |

Requirement "Query kinds and what published means" (1626 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Draft release skipped | Release queries read git tags and release assets, Draft release skipped | no |
| Missing second asset | Release queries read git tags and release assets, Missing second asset | no |
| Go prerelease from the list | Go queries read the module proxy, Go prerelease from the list | no |
| Private package | Unknown or private GHCR packages, Private package | no |
| Caller's git credentials stay home | git ls-remote runs isolated from the caller's git config, Caller's git credentials stay home | no |
| No token leaves the process | The resolver sends no credentials, No token leaves the process | no |

Requirement "Requests, retries and the expect wait" (1551 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Transient error recovers | Transient failures are retried four times, Transient error recovers | no |
| Four transient errors | Transient failures are retried four times, Four transient errors | no |
| Expected version appears late | A confirmed expected version joins the candidates, Expected version appears late | no |
| Expected version never appears | Running out of expect wait time is not a failure, Expected version never appears | no |
| Expect above a hold is ignored | Expect applies only to a plausible version, Expect above a hold is ignored | no |

Requirement "Steering files" (1100 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Directory entry with trailing slash | frozen and is-frozen read the frozen file, Directory entry with trailing slash | no |
| Sibling directory not matched | frozen and is-frozen read the frozen file, Sibling directory not matched | no |
| Entry without a reason | A steering file violation is exit 1, Entry without a reason | no |
| Empty steering files | Steering files are read from the repo root, Empty steering files | no |
| Real frozen files | Frozen entries have fixed keys, Real frozen files | no |
| Expired hold | hold reads the hold file, Expired hold | no |

Requirement "Consistent-set helpers" (673 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Catalog's core pin | pin-of prints the pin a module version holds, Catalog's core pin | no |
| Dependency absent | pin-of prints the pin a module version holds, Dependency absent | no |
| Dependency followed by another | pin-of reads one dependency block, Dependency followed by another | no |
| Language version | language-of prints the module language version, Language version | no |
| Next patch | next-patch prints the next patch, Next patch | no |

Requirement "Warnings and JSON output" (558 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| JSON shape | newest --json prints one object, JSON shape | no |
| Release warning key | Warnings go to stderr and the warnings file, Release warning key | no |

Requirement "Proposed tags are on their repo's main" (1506 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| A forged tag | Newest answers only candidates whose tag is on main, A forged tag | no |
| Catalog tags carry their prefix | Catalog and module pins check a prefixed tag, Catalog tags carry their prefix | no |
| Operator module tags carry their prefix | Catalog and module pins check a prefixed tag, Operator module tags carry their prefix | no |
| One version checked on its own | tag-on-main answers the check for one version, One version checked on its own | no |
| Git failure | The tag check uses git only, Git failure | no |
| Controller module tags carry their prefix | Catalog and module pins check a prefixed tag, Controller module tags carry their prefix | no |

### cascade-resolver-checks

Requirement "Canonical stub" (608 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Checksum drift | The canonical stub has a fixed checksum, Checksum drift | no |
| Agreement on a beta line | The stub agrees with the real resolver, Agreement on a beta line | no |

Requirement "Offline test suite" (3839 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Runs without network | The offline suite runs without network, Runs without network | no |
| A real curl call is caught | The curl shim answers from fixtures, A real curl call is caught | no |
| Pagination limit | The offline suite covers the resolver, Pagination limit | no |

Requirement "Required CI check for .github" (1050 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Unrelated PR still reports | Resolver tests run on every change, Unrelated PR still reports | no |
| Failing test fails the check | Resolver tests run both offline suites, Failing test fails the check | no |
| Failing wiring case fails the check | Resolver tests run both offline suites, Failing wiring case fails the check | no |

Requirement "Live smoke workflow" (571 characters, form a/b (MODIFIED, name kept)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Live run on dispatch | Live smoke workflow, Live run on dispatch | no |

Requirement "Offline wiring test suite" (2250 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Wiring suite runs without network | The wiring suite runs offline with fakes, Wiring suite runs without network | no |
| Amended bot commit is a human commit | The wiring suite covers the cascade scripts, Amended bot commit is a human commit | no |

### tag-ledger

Requirement "Scanned repos" (1006 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| An opm tag is recorded | Every scanned repo gets the same treatment, An opm tag is recorded | no |
| A moved opm tag is drift | Every scanned repo gets the same treatment, A moved opm tag is drift | no |
| A missing opm tag ruleset is a finding | Every scanned repo gets the same treatment, A missing opm tag ruleset is a finding | no |
| The summary names every scanned repo | The summary and the reference name the scanned repos, The summary names every scanned repo | no |

### Batch .github-B1: clause tables

A clause that stays in a body, word for word, is not listed. Every rule keeps its keyword (SHALL stays SHALL). A clause listed as "moved" keeps its words; the new text only adds the subject that the old sentence took from the requirement it sat in. "Mode table", "Job limits" and "Guard table" hold a table that was in a body; the body names the scenario.

Form per requirement of B1 (the old length is in the ledger heading; the new lengths are in the report):

- Form b (MODIFIED parent plus ADDED splits, no scenario moves out of the parent): Receive interface and job split, Mode selection, Final title, Publish renders the PR text. Live smoke workflow of `cascade-resolver-checks` and One entry point with fixed exit codes of `cascade-resolver` are the same form.
- Form c2 (REMOVED plus ADDED, each old scenario reappears under its ledger name): every other requirement of the four specs.

#### cascade-receive

| Old requirement and clause | New place |
| --- | --- |
| Receive interface and job split: `setup-go`, `setup-cue`, `cue-version` inputs | ADDED "Receive setup inputs"; the parent body names it |
| Receive interface and job split: third job `publish` is the caller's own, its composite action and inputs | ADDED "The publish job is the caller's own" |
| Receive interface and job split: job table | scenario "Job limits" of ADDED "Receive jobs have fixed environment, permissions and timeouts" |
| Receive interface and job split: `compute` holds no secret; `publish` runs only `git`, `gh`, `jq` and `.github` scripts and fails off `refs/heads/main` | ADDED "Receive jobs have fixed environment, permissions and timeouts" |
| Receive interface and job split: Task installed, `yq` must be mikefarah | ADDED "Compute checks its tools" |
| Receive interface and job split: no auto-merge | ADDED "The bot never enables auto-merge" |
| Dry run fails closed: `publish` run conditions | "Publish runs only when every live condition holds" |
| Dry run fails closed: letter case of `CASCADE_DRY_RUN` | "The stop switch variable is case-insensitive" |
| Dry run fails closed: `dry-run` expression, exact `false`, `true` publishes nothing, other values fail, `effective_dry_run` refusal | "The publish action publishes only on a false dry-run input" |
| Dry run fails closed: other refs and gates-only are dry runs | "Compute treats other refs and gates-only runs as dry runs" |
| Dry run fails closed: summary lines, 200 KB cap, `diff.patch`, notify ignores dry run | "A dry run still writes the summary" |
| Payload is a validated hint: source in allowlist, 1 to 8 tags, unknown keys, drop whole, sweep, never a label | "Payload is a validated whole" |
| Payload is a validated hint: control characters, whole-tag match | "Payload strings are matched whole" |
| Payload is a validated hint: allowlists, "not a cascade receiver" | "The payload source allowlists" |
| Payload is a validated hint: `CASCADE_SOURCE`, `CASCADE_TAGS`, `CASCADE_EXPECT`, `CASCADE_EXTRA_SOURCES` | "A valid payload sets the cascade variables" |
| Payload is a validated hint: `publish` reads the event | "Publish reads the payload from the event" |
| Mode selection: mode table | scenario "Mode table" of the parent; the parent names it |
| Mode selection: `merge` checkout, derived-file conflicts, abort to `conflict` | ADDED "Merge mode merges main into the branch" |
| Task run, commit and Notes: dirty tree, task run, exit codes, bot commit, title before and after | "Compute runs the task and commits its result" |
| Task run, commit and Notes: merge mode puts `main`'s `.tasks/` and `Taskfile*` in the tree | "Merge mode runs main's task" |
| Task run, commit and Notes: scratch files | "Compute scratch files stay under the runner temp folder" |
| Task run, commit and Notes: Notes bytes, `CASCADE_NOTES_FILE` | "Notes are kept byte for byte" |
| Task run, commit and Notes: `warnings.tsv` | "Compute uploads the warnings file" |
| Final title: title-rise ranks and comment | ADDED "Title rise posts one comment" |
| Labels: planned label union | "Planned labels are a union" |
| Labels: range, payload, third-party pins, API error | "The breaking check covers the whole range" |
| Labels: `publish` derives labels again, keeps `deps-cascade:breaking` on a read failure | "Publish derives the labels again" |
| Labels: add only, remove `deps-cascade:conflict`, never remove two labels | "The bot only adds labels" |
| Labels: five labels, `labels-managed` | "Publish keeps the five bot labels" |
| Workflows guard: `D1`, `D2`, push rule, no update-branch API | "The workflows guard limits what the bot pushes" |
| Workflows guard: table | scenario "Guard table" of the same requirement |
| Workflows guard: `WF_GUARD_RULE` ships as `tree`, `strict` implemented | "The workflows guard rule ships as tree" |
| Publish verifies before it mints: untrusted plan, unknown action or label, PR mismatch, moved tip | "Publish treats the plan as untrusted" |
| Publish verifies before it mints: bundle, new tip, workflows guard, lint | "Publish verifies the bundle before it mints" |
| Publish verifies before it mints: bound the increment, render the text (the two requirement references) | "Publish bounds the increment and renders the text before it mints" |
| Publish verifies before it mints: comments from fixed texts, leases | "Publish builds comments from fixed texts and pushes under a lease" |
| Publish verifies before it mints: hold seen only by `publish` | "A hold added after compute stops publish" |
| Gates-only runs never publish: never mint or write, caller `if:` and input | "A gates-only run never writes" |
| Gates-only runs never publish: `cascade-publish` input check in `verify` and `act` | "cascade-publish checks the gates-only input first" |
| Gates-only runs never publish: outputs for a gates-only run | "Receive outputs for a gates-only run" |
| Publish bounds the bot's increment: increment definition, count, root, parents, emails | "Publish bounds the increment's commits" |
| Publish bounds the bot's increment: status, mode, allow-list and deny-list on a single-parent commit | "Publish limits what a single-parent commit changes" |
| Publish bounds the bot's increment: merge commits | "Publish checks merge commits" |
| Publish bounds the bot's increment: allow-lists in `.github` | "Allow-lists live in .github" |
| Publish bounds the bot's increment: deny-list contents, wins | "The deny-list wins over the allow-list" |
| Publish bounds the bot's increment: human commits on push, recreate, close | "Publish refuses to drop a human commit" |
| Publish bounds the bot's increment: `tag-on-main` per moved pin | "Publish checks the tag of each moved pin" |
| Publish renders the PR text: line filter | ADDED "Publish filters compute's warnings" |
| Publish renders the PR text: final title from its own title, notice | ADDED "Publish computes the final title itself" |
| Publish renders the PR text: 65000 bytes, empty diff | ADDED "Publish refuses an oversize body or an empty push diff" |
| Publish refuses a stale mirror: recorded files | "The mirror records the sha256 of receiver files" |
| Publish refuses a stale mirror: `opm-controller` records the same files | "The renamed repo records the same files" |
| Publish refuses a stale mirror: refusal before the token, message fields | "Publish refuses a plan from a stale mirror" |
| Publish refuses a stale mirror: `close`, `conflict`, `too_long` not refused | "A stale mirror does not hold other actions" |
| Publish refuses a stale mirror: mirrored `pins.sh` reports the same rows | "The mirrored pins report matches the receiver's" |
| Publish refuses a stale mirror: cli rows, before and after the rename | "The cli mirror reports the controller pins" |

The grammar of one old sentence is repaired in "Publish refuses a plan from a stale mirror" ("reads the bundle, runs the workflows guard or bounds the increment" was "before it reads the bundle, runs ... or bounds"); the list of times is the same.

#### cascade-resolver

| Old requirement and clause | New place |
| --- | --- |
| One entry point: work from any directory by absolute path | ADDED "The resolver runs from any directory" |
| SemVer 2.0.0 precedence: order rules, no `sort -V` trick | "The resolver orders versions by SemVer 2.0.0 precedence" |
| SemVer 2.0.0 precedence: `semver-cmp` and `semver-sort` output | "semver-cmp and semver-sort have fixed output" |
| Candidate rules for newest | three requirements as in guide section 5.2 (valid candidates; ten newest; exit 3) |
| Query kinds: lead sentence "support these kinds, with published defined per kind" | each kind states its own published rule, in the five kind requirements |
| Query kinds: `cue`, `go`, `release` plus `opm-cli`, `oci` | "Cue queries read the GHCR tag list", "Go queries read the module proxy", "Release queries read git tags and release assets", "OCI queries accept the manifest and index types" |
| Query kinds: no credentials, no `api.github.com` | "The resolver sends no credentials" |
| Query kinds: `git ls-remote` isolation | "git ls-remote runs isolated from the caller's git config" |
| Query kinds: unknown or private GHCR package | "Unknown or private GHCR packages" |
| Requests: curl shape | "Requests use one curl shape" |
| Requests: retries, sleeps, `git ls-remote` stall and retries | "Transient failures are retried four times" |
| Requests: 404 and 410, other statuses, no fallback | "A 404 means not published" |
| Requests: `--expect` conditions and poll | "Expect applies only to a plausible version" |
| Requests: elapsed time is the sum of requested sleeps | "The expect wait counts requested sleep" |
| Requests: confirmed `--expect` joins the candidates; never the answer unless newest | "A confirmed expected version joins the candidates" |
| Requests: running out of time warns | "Running out of expect wait time is not a failure" |
| Steering files: read from `--repo-root`, empty is valid | "Steering files are read from the repo root" |
| Steering files: frozen keys | "Frozen entries have fixed keys" |
| Steering files: hold keys, one per pin | "Hold entries have fixed keys" |
| Steering files: violation is exit 1, `check-files` | "A steering file violation is exit 1" |
| Steering files: `frozen`, `is-frozen` | "frozen and is-frozen read the frozen file" |
| Steering files: `hold` | "hold reads the hold file" |
| Consistent-set helpers: `pin-of` print and exit 3 | "pin-of prints the pin a module version holds" |
| Consistent-set helpers: first `v:`, duplicate key, no `cue` | "pin-of reads one dependency block" |
| Consistent-set helpers: `language-of` | "language-of prints the module language version" |
| Consistent-set helpers: `next-patch` | "next-patch prints the next patch" |
| Warnings and JSON output: warning format and file | "Warnings go to stderr and the warnings file" |
| Warnings and JSON output: `--json` object | "newest --json prints one object" |
| Proposed tags: tag reachable from `main`, skip warning, walk continues | "Newest answers only candidates whose tag is on main" |
| Proposed tags: `go`, `release`, `opm-cli`, core mapping | "Go, release and core pins check their own tag" |
| Proposed tags: catalog, operator and controller mapping with prefixes | "Catalog and module pins check a prefixed tag" |
| Proposed tags: git only, four attempts, exit 1 | "The tag check uses git only" |
| Proposed tags: other pins and `published` do not check | "Other pins and published do not check tags" |
| Proposed tags: `tag-on-main` | "tag-on-main answers the check for one version" |

#### cascade-resolver-checks

| Old requirement and clause | New place |
| --- | --- |
| Canonical stub: sha256 | "The canonical stub has a fixed checksum" |
| Canonical stub: agreement and exclusions | "The stub agrees with the real resolver" |
| Offline test suite: no network, PASS and FAIL, exit codes, missing case file | "The offline suite runs without network" |
| Offline test suite: `test/shim/` first, `CASCADE_FIXTURE_DIR`, no fixture path in the resolver, refusing `cue` | "The offline suite puts shims first on PATH" |
| Offline test suite: `curl` shim | "The curl shim answers from fixtures" |
| Offline test suite: `git` shim | "The git shim answers from fixtures" |
| Offline test suite: fixtures captured from real answers | "Fixtures are captured from real answers" |
| Offline test suite: git ignores caller config, fixed author | "Offline suite git ignores the caller's config" |
| Offline test suite: "SHALL cover at least" and its 14 list items | "The offline suite covers the resolver", eight scenarios (seven case lists and Pagination limit); the 14 items are kept in their order and words |
| Required CI check: triggers, permissions, job name, timeout | "Resolver tests run on every change" |
| Required CI check: checkout, `yq`, go-task | "Resolver tests set up pinned tools" |
| Required CI check: `shellcheck`, `actionlint` | "Resolver tests lint scripts and workflows" |
| Required CI check: both offline suites | "Resolver tests run both offline suites" |
| Required CI check: no new job, no other workflow changed | "Resolver tests add no job and change no other workflow" |
| Live smoke workflow: `opm-cli` assertions | ADDED "Live smoke workflow asserts the newest cli" |
| Offline wiring test suite: harness, PASS and FAIL, exit 0 | "The wiring suite runs offline with fakes" |
| Offline wiring test suite: real resolver for offline subcommands only | "The wiring suite uses the real resolver for offline subcommands only" |
| Offline wiring test suite: "SHALL cover at least" and its list | "The wiring suite covers the cascade scripts", four scenarios; the items are kept in their order and words |

#### tag-ledger

| Old requirement and clause | New place |
| --- | --- |
| Scanned repos: six repos, sandbox excluded, unreadable repo fails | "The tag-ledger scan covers exactly six repos" |
| Scanned repos: same treatment, four bullets | "Every scanned repo gets the same treatment" |
| Scanned repos: `Repos:` line, reference holds no second copy | "The summary and the reference name the scanned repos" |

New scenarios (not in the old specs) use only words of the clause they test; each is listed by the unit in its report so the reviewer can read them.


## Risks

- A rewrite changes a rule by accident. Mitigation: the guide checklist per unit and the `DIFF`/`LOST` script.
- Another repo copies spec text from this one (the `references/` files and five product repos' wiring copies cite requirement names). Mitigation: the grep of D2 before each rename; product repos hold no spec text.
- The CI step fails every PR if the pin is wrong. Mitigation: the implement unit runs the same commands locally before the commit; actionlint runs on the edited workflow.

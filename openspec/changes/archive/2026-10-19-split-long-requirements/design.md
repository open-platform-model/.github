## Context

The rule: the body of a requirement is the text between its header and the first line that starts with `#`, without blank, fenced and `**Key**:` lines; more than 500 UTF-16 units is a WARNING. The check runs on main specs and on ADDED blocks, not on MODIFIED blocks. A MODIFIED block that stays over 500 passes `validate <change> --strict` and then fails `validate --all --strict` after archive.

Measured on `origin/main` 48e9ead (OpenSpec 1.14.1): `validate --all --strict` prints 55 WARNING lines. Per spec (`validate <spec> --type spec --strict`): cascade-gates 4, cascade-notify 2, cascade-pr-text 4, cascade-receive 13, cascade-resolver 9, cascade-resolver-checks 5, cascade-wiring-check 8, cascade-workflows 9, tag-ledger 1, cite-lint-workflow 0. The inventory is 55 long requirements in 9 specs. Excess kinds in that inventory: almost all "several behaviors" plus format or list.

## Research & Decisions

### D1. Which form per requirement

Options: (a) shorten in place with MODIFIED and move detail into new scenarios; (b) MODIFIED parent plus ADDED splits; (c2) REMOVED plus ADDED under new names; (d) RENAMED plus MODIFIED. Status quo (leave the warnings and drop `--strict`) is rejected: the human ordered the gate.

Decision: read each requirement, then pick by the table of rewrite forms.

| The excess is | Form |
| --- | --- |
| Examples, lists, formats or rationale around one behavior | a |
| Several behaviors; the old scenarios fit the parent that stays | b |
| Several behaviors; the old scenarios belong to different behaviors | c2 |
| A name that must change with no change of rule | d, alone |

Most requirements of this repo hold several behaviors (the inventory marks 52 of 55 as "several behaviors"), so b and c2 are the common forms and a is the second. The inventory kind label is a heuristic: the author reads the text. Reversibility: high (hours). A wrong split is fixed by a new rewrite before archive.

Trade-off: c2 gives the cleanest one-behavior blocks but it is the only form that may lose a scenario without an error, so it carries the ledger (D2). Form a and b keep every scenario by name, which the repo rule requires for MODIFIED.

### D2. Scenario ledger

The repo rule (`openspec/config.yaml`, specs) says a MODIFIED requirement keeps every scenario of the main spec, and a rename that drops one uses REMOVED plus ADDED. OpenSpec checks this for MODIFIED but does not check scenarios under c2. So this design.md holds, for every rewritten requirement, a ledger block in this form, written by the unit that writes the delta:

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |

plus a second table for each clause that leaves the body: old clause, new place. Rules: a, b and d keep each old name byte for byte under the same requirement; c2 shows each old name in one new requirement; a moved scenario keeps its WHEN and THEN byte for byte ("Changed text?" is "no" except where a clause table names the change); keywords SHALL and MUST stay in every body; citations (`Source:` lines, `workspace RELEASING.md` sections, reasons with an enhancement id) stay in the body of the block that carries the rule, never in a header; no `**Key**:` line, no `#####` heading and no fenced block in a body (loopholes). A unit adds its ledger blocks to this file in the same commit as its delta. Before a rename or split the unit greps the repo (excluding `openspec/changes/archive`) for the old header text: `references/`, `README.md` and the workflow comments cite some requirement names.

New ADDED requirements follow the repo rule "scenarios that demonstrate requirements" and include the rejected case when the behavior has one (for example the exit code of a refusal), using only words of the old body.

### D3. Batches and order

Decision: two units in sequence on one branch: B1 (28), then B2 (27), then the CI step, then `AGENTS.md`, then the final gate. The inventory sets the batches (first-fit decreasing, cap 28, whole specs, no spec in two batches). Why B1 first: it is the larger one and holds `cascade-resolver-checks`, the spec that names the CI job, so the new CI requirement (D5) lands in a spec already open in this change. No collision exists: `openspec/changes/` holds no other open change, so no MODIFIED block of another author can go stale.

One caveat: the CI step must come after B2. With 27 warnings left, the step would fail its own PR. Inside one PR the group order is the commit order, and every group ends green under the repo gates, but `openspec validate --all --strict` is green only after the archive (task 5.3). Group 1 therefore ends green under gates 1 to 3 and under the gate of D4 (warnings fell by 28, no new ERROR).

### D4. The gate per unit

Run in a scratch copy of `openspec/`, never in the worktree, with the pinned 1.14.1 CLI. Paths for this repo: `WT` is the worktree of the branch, `CH` is `split-long-requirements`, `S` is a scratch folder. The gate block of the rewrite method runs unchanged:

- Baseline from `git -C $WT archive main openspec` (not from the worktree), copy of `$WT/openspec` for the change.
- It runs `validate $CH --strict`, `archive $CH --yes` in the copy, `validate --all --strict`, and fails on any line "Archive would refuse" and on any ERROR item (type, id, path) that main does not have.
- Unit B1: `N` = 28, so warnings must fall from 55 to 27. Unit B2: `N` = 55 and `LAST=1` (no unit follows in the rewrite, the CI step and `AGENTS.md` touch no spec text other than D5): after the archive `validate --specs --strict` must exit 0. Because this repo has no other open change, `validate --all --strict` is also expected to exit 0 and is reported.
- After each unit also run `openspec validate <spec> --type spec --strict --json` for the batch specs, and the scenario check of the review checklist (script `same:`, `new:`, `DIFF:`, `LOST:` lines) per rewritten requirement. A `DIFF` or `LOST` line stops the unit.
- `validate <change> --strict` alone is not enough: it skips long MODIFIED text.

### D5. The CI gate

Options: (1) a step in the existing `Resolver tests` job; (2) a new job in `cascade-resolver.yml`; (3) a new workflow; (4) a Taskfile with `openspec:check` (what cli does). The status quo is no gate.

Decision: option 1. Reasons: the owner ruled "CI workflow step only, no Taskfile" because the repo has none. The spec of that workflow says it adds no new job and no new check context, and `Resolver tests` is the required check that already reports on every PR with no path filter (Principle III). A new job or workflow would add a check context that no ruleset requires, so it would not gate merges, or it would need an owner ruleset edit that this change must not do.

Details of the step, for task group 3:

- Name: `OpenSpec`. Position: after `actionlint`, before the offline suites, so a spec error fails fast.
- Install: `npm install --prefix "$RUNNER_TEMP/openspec" --ignore-scripts @fission-ai/openspec@1.14.1`, then add `$RUNNER_TEMP/openspec/node_modules/.bin` to `GITHUB_PATH`. Node and npm come with the runner image, so no new third-party action and no `setup-node` pin. The exact version is the pin; `--ignore-scripts` follows the supply-chain rule on install scripts. The implement unit checked the installed 1.14.1 package and its dependency tree for install scripts and found none; the install itself runs for the first time in the CI run of the pull request.
- Run: `OPENSPEC_TELEMETRY=0 openspec validate --all --strict --no-interactive`. Telemetry off keeps the job free of calls to hosts it does not need (Principle I).
- No new permission: the job keeps `contents: read`. The 10-minute timeout stays.
- `openspec --version` is printed and compared to `1.14.1`; a different version fails the step, so the pin cannot drift silently.
- The workflow comment header gains one line that names the step. The step list is stated in the spec through one new requirement in `cascade-resolver-checks` (ADDED, one behavior, scenarios: a spec with a long requirement fails the job; the job reports on every pull request). The existing requirement for this workflow is rewritten in B1 only for length, and its meaning stays: the new step is a separate requirement, so no existing clause changes.
- Consequence (negative): a required check now also fails when a future PR adds an over-500 requirement or breaks a spec; authors of specs must keep requirements short. Operational: the OpenSpec pin is one more version to bump by hand; the owner is whoever bumps the skills. The same version string is in `.claude/skills/*/SKILL.md` (`generatedBy`), so a bump touches both.
- Revisit trigger: OpenSpec 1.15 or a repo Taskfile.

Reversibility: high (hours); the step is removed by one commit.

### D6. Security

Assets: none new. Trust boundary: the job installs one npm package at a pinned version, and npm resolves its whole transitive tree (about 70 packages, most by caret range) on a runner with `contents: read` and no secrets. Baseline: the repo's workflow principles (`openspec/config.yaml`, Principle I) and the supply-chain rules (pin, no install scripts). Residual risk: the npm registry serves a tampered 1.14.1, or a hijacked new release of any package in the floating transitive tree, and the job reports green (`--ignore-scripts` stops install scripts only; no integrity hash is checked as in the other steps); owner: the repo owner; accepted by the owner, who decided on no lockfile knowing there is no integrity hash, because the job holds no secret and a read-only token. Alternative to lower it later: a committed lockfile with integrity hashes and `npm ci --ignore-scripts`.

## Scenario ledger

Each unit appends its blocks here (form D2) in the commit of its delta.

### Batch .github-B1: scenario ledger

One table per rewritten requirement. "Changed text?" is "no" for every row: the scenario check prints `same:` for each of them. The group 1 delta holds 28 rewritten requirements.

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
| Publish verifies before it mints: bundle, new tip, workflows guard, body lint | "Publish verifies the bundle before it mints" |
| Publish verifies before it mints: bound the increment (requirement references) | "Publish bounds the increment before it mints" |
| Publish verifies before it mints: render the text (requirement reference) | "Publish renders the text before it mints" |
| Publish verifies before it mints: "with `GITHUB_TOKEN` and plain git only" | repeated in the bodies of the four requirements that carry a pre-mint step |
| Publish verifies before it mints: comments from fixed texts, lint of every comment for any action, leases | "Publish builds comments from fixed texts and pushes under a lease" |
| Publish verifies before it mints: hold seen only by `publish` | "A hold added after compute stops publish" |
| Gates-only runs never publish: never mint or write, caller `if:` and input | "A gates-only run never writes" |
| Gates-only runs never publish: `cascade-publish` input check in `verify` and `act` | "cascade-publish checks the gates-only input first" |
| Gates-only runs never publish: outputs for a gates-only run | "Receive outputs for a gates-only run" |
| Publish bounds the bot's increment: increment definition, count, root, parents, emails (scope "For `push` and `recreate`" copied from the old lead) | "Publish bounds the increment's commits" |
| Publish bounds the bot's increment: status, mode, allow-list and deny-list on a single-parent commit (scope "For `push` and `recreate`" copied) | "Publish limits what a single-parent commit changes" |
| Publish bounds the bot's increment: merge commits (scope "For `push` and `recreate`" copied) | "Publish checks merge commits" |
| Publish bounds the bot's increment: allow-lists in `.github` | "Allow-lists live in .github" |
| Publish bounds the bot's increment: deny-list contents, wins | "The deny-list wins over the allow-list" |
| Publish bounds the bot's increment: human commits on push, recreate, close | "Publish refuses to drop a human commit" |
| Publish bounds the bot's increment: `tag-on-main` per moved pin (scope "For `push` and `recreate`" copied) | "Publish checks the tag of each moved pin" |
| Publish renders the PR text: line filter | ADDED "Publish filters compute's warnings" |
| Publish renders the PR text: final title from its own title, notice | ADDED "Publish computes the final title itself" |
| Publish renders the PR text: 65000 bytes, empty diff | ADDED "Publish refuses an oversize body or an empty push diff" |
| Publish refuses a stale mirror: recorded files | "The mirror records the sha256 of receiver files" |
| Publish refuses a stale mirror: `opm-controller` records the same files | "The renamed repo records the same files" |
| Publish refuses a stale mirror: refusal before the token, message fields | "Publish refuses a plan from a stale mirror" |
| Publish refuses a stale mirror: `close`, `conflict`, `too_long` not refused | "A stale mirror does not hold other actions" |
| Publish refuses a stale mirror: mirrored `pins.sh` reports the same rows | "The mirrored pins report matches the receiver's" |
| Publish refuses a stale mirror: cli rows, before and after the rename | "The cli mirror reports the controller pins" |

The sentence of "Publish refuses a plan from a stale mirror" is kept word for word.

#### cascade-resolver

| Old requirement and clause | New place |
| --- | --- |
| One entry point: work from any directory by absolute path | ADDED "The resolver runs from any directory" |
| SemVer 2.0.0 precedence: order rules, no `sort -V` trick | "The resolver orders versions by SemVer 2.0.0 precedence" |
| SemVer 2.0.0 precedence: `semver-cmp` and `semver-sort` output | "semver-cmp and semver-sort have fixed output" |
| Candidate rules for newest | three requirements as in the rewrite method (valid candidates; ten newest; exit 3) |
| Query kinds: lead sentence "support these kinds, with published defined per kind" | each kind states its own published rule, in the five kind requirements |
| Query kinds: `cue`, `go`, `release` plus `opm-cli`, `oci` (for `oci`, the manifest `HEAD` decides published) | "Cue queries read the GHCR tag list", "Go queries read the module proxy", "Release queries read git tags and release assets", "OCI queries accept the manifest and index types" |
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
| Proposed tags: tag reachable from `main`, skip warning, walk continues; the lead "For a pin whose versions are tags of an `open-platform-model` repo" is kept word for word and closed by a reference to the two list requirements | "Newest answers only candidates whose tag is on main" |
| Proposed tags: `go`, `release`, `opm-cli`, core mapping | "Go, release and core pins check their own tag" |
| Proposed tags: catalog, operator and controller mapping with prefixes | "Catalog and module pins check a prefixed tag" |
| Proposed tags: git only, four attempts, exit 1 | "The tag check uses git only" |
| Proposed tags: "Other pins (fixtures, templates, `oci`) SHALL NOT be checked, and `published` SHALL NOT check." kept, with the words ", those not named in" and the two requirement names added after "Other pins"; "Other" is anchored by naming the two requirements that hold the closed list | "Other pins and published do not check tags" |
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

### Batch .github-B2: scenario ledger

One table per rewritten requirement. "Changed text?" is "no" for every row: the scenario check prints `same:` for each of them. The group 2 delta holds 27 rewritten requirements (five specs). The scenarios new to the spec are listed in the clause tables part.


#### cascade-workflows

Requirement "Hardened workflow shape" (1009 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Inline expression rejected | Run blocks take context values through env, Inline expression rejected | no |
| Caller passes no secrets | The App key is read only by the caller's own job, Caller passes no secrets | no |
| Reusable job does not see the Environment secret | Reusable cascade workflows hold no secret, Reusable job does not see the Environment secret | no |

Requirement "Scripts come from the pinned .github commit" (1054 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| A pinned action runs its own commit's code | The composite actions run their scripts from their own directory, A pinned action runs its own commit's code | no |
| The receive workflow checks its scripts out at its own SHA | The receive workflow checks the scripts out at its own commit, The receive workflow checks its scripts out at its own SHA | no |
| Unknown own commit | The receive workflow checks the scripts out at its own commit, Unknown own commit | no |

Requirement "App token minting" (1022 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Empty repository list | The mint uses a fixed owner and a non-empty repository list, Empty repository list | no |
| Branch run cannot reach the key | The App token is minted after every check that could stop the job, Branch run cannot reach the key | no |

Requirement "Repo code never holds a token" (1345 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Task sees no token | Repo code runs with no token variable, Task sees no token | no |
| Task cannot write the step's outputs or environment | Repo code runs with no runner command file path, Task cannot write the step's outputs or environment | no |
| No token after repo code | Compute reads with the token before repo code runs, No token after repo code | no |
| Breaking check without a token | Compute reads with the token before repo code runs, Breaking check without a token | no |

Requirement "No Actions cache from repo code reaches a publish job" (533 characters, form a/b (MODIFIED, name kept)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| compute's Go install | No Actions cache from repo code reaches a publish job, compute's Go install | no |

Requirement "Compute installs pinned, checksummed tools" (566 characters, form a/b (MODIFIED, name kept)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Unknown CUE version | Compute installs pinned, checksummed tools, Unknown CUE version | no |
| Tampered archive | Compute installs pinned, checksummed tools, Tampered archive | no |

Requirement "Daily mirror drift check" (656 characters, form a/b (MODIFIED, name kept)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| A receiver changed its classes | Daily mirror drift check, A receiver changed its classes | no |
| Every mirror current | Daily mirror drift check, Every mirror current | no |
| A file cannot be read | Daily mirror drift check, A file cannot be read | no |

Requirement "Rollout order for a new pin" (2017 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| All receivers dry, publish changed | A publish-only change while every receiver is dry, All receivers dry, publish changed | no |
| One receiver already live, publish changed | A publish-only change once a receiver is live, One receiver already live, publish changed | no |
| Resolver library changed | The pinning reference defines when a change touches an action, Resolver library changed | no |
| Notify changed | A notify-only change moves one upstream first, Notify changed | no |
| Both actions changed, one receiver live | A change that touches both actions follows both rules, Both actions changed, one receiver live | no |
| Change touches neither action | A change that touches neither action has no canary, Change touches neither action | no |

Requirement "The renamed controller repo answers to both names" (669 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| The renamed repo as a receiver | The renamed controller repo gets the same answers, The renamed repo as a receiver | no |
| A target list keeps the old name | A target list keeps the old repo name, A target list keeps the old name | no |
| Two names, one repo | same_repo treats the two names as one repo, Two names, one repo | no |


#### cascade-wiring-check

Requirement "Canonical wiring check" (2730 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| A variant spelling of the key | The App key is read only by the key-holding jobs, A variant spelling of the key | no |
| An aliased Environment and a computed secret name | The cascade Environment is declared only on the key-holding jobs, An aliased Environment and a computed secret name | no |
| A mixed-case call into .github | No call into .github passes secrets, A mixed-case call into .github | no |
| A publish workflow restores a cache | Publish workflows use no Actions cache, A publish workflow restores a cache | no |
| A gates-only publish | Key-holding jobs match the config, A gates-only publish | no |
| Current callers after the caller edit | The wiring check compares the callers with the documented shapes, Current callers after the caller edit | no |

Requirement "Per-repo wiring config" (1314 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Allow-list widened to a code-running variable | The wiring check allows only named env variables, Allow-list widened to a code-running variable | no |
| Allow-list widened to a proxy or a git hook directory | The wiring check allows only named env variables, Allow-list widened to a proxy or a git hook directory | no |
| An extra reference of an unknown kind | The wiring check refuses a bad extra-references item, An extra reference of an unknown kind | no |
| An extra reference beside a fixed one | The wiring check refuses a bad extra-references item, An extra reference beside a fixed one | no |

Requirement "Byte-identical copies" (1068 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Pin bump | Each product repo keeps a byte-identical copy of the wiring check, Pin bump | no |
| A copy that drifted | The check reports a copy that differs or cannot be fetched, A copy that drifted | no |
| Offline run | Without the flag the check does not compare the copy, Offline run | no |

Requirement "The release key needs the release Environment" (640 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Release job without the Environment | The wiring check finds the release-key readers and holds them to the release Environment, Release job without the Environment | no |
| The key in lower case | The wiring check finds the release-key readers and holds them to the release Environment, The key in lower case | no |
| The Environment on a job that does not read the key | The wiring check finds the release-key readers and holds them to the release Environment, The Environment on a job that does not read the key | no |
| Inherited secrets | The wiring check finds the release-key readers and holds them to the release Environment, Inherited secrets | no |

Requirement "Declared extra references" (613 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| opm-operator's module dependency bot | A declared extra reference adds one expected reference, opm-operator's module dependency bot | no |
| The extra reference at another SHA | A declared reference follows the fixed rules, The extra reference at another SHA | no |
| An undeclared second resolver | An undeclared or missing reference fails, An undeclared second resolver | no |

Requirement "Resolver checkouts pass no credentials" (616 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| A token on the resolver checkout | A resolver checkout uses fixed inputs, A token on the resolver checkout | no |
| A checkout through repository_owner | A step counts as a .github checkout by its repository input, A checkout through repository_owner | no |
| A clone in a run step | A step counts as a .github checkout by its repository input, A clone in a run step | no |

Requirement "Nothing reaches the CI wiring step" (523 characters, form a/b (MODIFIED, name kept)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| BASH_ENV in the CI job env | Nothing reaches the CI wiring step, BASH_ENV in the CI job env | no |
| A run step before the wiring step | Nothing reaches the CI wiring step, A run step before the wiring step | no |
| Pinned setup actions before the wiring step | Nothing reaches the CI wiring step, Pinned setup actions before the wiring step | no |

Requirement "Runbook for a failed API call" (739 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Unknown SHA | The runbook confirms the pinned SHA first, Unknown SHA | no |
| GitHub API outage | The runbook allows an admin bypass only for a PR outside .github and .tasks, GitHub API outage | no |


#### cascade-gates

Requirement "G2 freshness" (849 characters, form a/b (MODIFIED, name kept)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Shipped pin behind | G2 freshness, Shipped pin behind | no |
| Held pin | G2 freshness, Held pin | no |

Requirement "G3 settled" (1042 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Upstream cascade open | G3 is a problem when an upstream has an open cascade PR, Upstream cascade open | no |
| Forged settled result | G3 is evaluated by the gates job from API reads, Forged settled result | no |
| The renamed repo's upstreams | G3 is a problem when an upstream has an open cascade PR, The renamed repo's upstreams | no |

Requirement "Status mapping" (1281 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Forged gate entry | The gates job posts only on listed heads, Forged gate entry | no |
| Warn mode problem | Statuses are posted with GITHUB_TOKEN in two contexts, Warn mode problem | no |
| Long description | Statuses are posted with GITHUB_TOKEN in two contexts, Long description | no |
| Missing artifact | A listed head without a G2 result gets a warning or an error, Missing artifact | no |

Requirement "Per-PR gates workflow" (822 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Ordinary PR | A PR that is not a release PR gets n/a, Ordinary PR | no |
| Release PR head moves | A same-repo release PR starts a gates-only run, Release PR head moves | no |


#### cascade-pr-text

Requirement "Path classification" (817 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Unmatched path is shipped | classify prints the class of each path, Unmatched path is shipped | no |
| Basename glob at depth | Patterns match in five forms, Basename glob at depth | no |
| Directory segment at any depth | Patterns match in five forms, Directory segment at any depth | no |
| Root-level name only | Patterns match in five forms, Root-level name only | no |
| Pattern of no known form | classify exits 1 on a bad line, Pattern of no known form | no |

Requirement "Diff and moved pins" (561 characters, form a/b (MODIFIED, name kept)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Untracked file counts | Diff and moved pins, Untracked file counts | no |
| Pin missing at the base | Diff and moved pins, Pin missing at the base | no |

Requirement "Cascade PR title" (612 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Shipped wins over test | The title type follows the changed paths, Shipped wins over test | no |
| Release tool only | The title type follows the changed paths, Release tool only | no |
| Four pins | The title subject names the moved pins, Four pins | no |
| Empty diff | An empty diff gives no title, Empty diff | no |

Requirement "Cascade PR body" (2307 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Labels from moved pins | The body labels, Labels from moved pins | no |
| Same input, same bytes | The PR body is printed in a fixed layout, Same input, same bytes | no |
| No moved pin | The body table and the counts, No moved pin | no |
| Empty diff | The PR body is printed in a fixed layout, Empty diff | no |
| Hostile tag dropped | Triggering releases list one line per valid tag, Hostile tag dropped | no |
| Unknown source dropped | A source outside the allowlist is dropped, Unknown source dropped | no |
| Sandbox source accepted when listed | CASCADE_EXTRA_SOURCES widens the allowlist, Sandbox source accepted when listed | no |
| Sandbox source dropped when not listed | CASCADE_EXTRA_SOURCES widens the allowlist, Sandbox source dropped when not listed | no |
| The renamed repo as a source | A source outside the allowlist is dropped, The renamed repo as a source | no |


#### cascade-notify

Requirement "Notify interface" (522 characters, form a/b (MODIFIED, name kept)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Caller switch off | Notify interface, Caller switch off | no |

Requirement "Source and targets are fixed" (948 characters, form c2 (REMOVED plus ADDED)).

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| Unknown source | Targets come from a fixed map, Unknown source | no |
| Catalog tag shape | The tag input matches a fixed shape, Catalog tag shape | no |
| The renamed repo releases | Targets come from a fixed map, The renamed repo releases | no |

### Batch .github-B2: clause tables

Form per requirement of B2 (the old length is in the ledger heading; the new lengths are in the report):

- Form b (MODIFIED parent kept, no scenario moves out of it, rest split into ADDED): No Actions cache from repo code reaches a publish job, Compute installs pinned, checksummed tools, Daily mirror drift check, G2 freshness, Notify interface, Nothing reaches the CI wiring step, Diff and moved pins.
- Form c2 (REMOVED plus ADDED, each old scenario reappears under its ledger name): every other requirement of the five specs.

Each row reads: old clause, new requirement, and how the new sentence relates to the old one. "Verbatim" means the whole old sentence is copied unchanged. "Lead" means the new body starts with words copied from the same old requirement (a subject or a condition). "Clause split" means an old sentence was cut at a `;` or at a comma between list items and each piece keeps the words of the old sentence; a trailing `;` or `:` became a full stop and a leading `and` was dropped. A rule table that sat in a body is in a scenario THEN and the body names the scenario ("Status table", "Target map", "The config keys", "Body layout").

#### cascade-workflows

| Old requirement and clause | New requirement | New sentence |
| --- | --- | --- |
| Hardened workflow shape: `cascade-receive.yml` and `cascade-gates.yml` callable only through `workflow_call`; the two composite actions | Cascade workflows and actions have a fixed shape | verbatim |
| Hardened workflow shape: every job declares `permissions:`; third-party `uses:` pinned to a full SHA | Cascade workflows and actions have a fixed shape | verbatim (two sentences) |
| Hardened workflow shape: no `${{ }}` in a `run:` block, context through `env:` | Run blocks take context values through env | verbatim |
| Hardened workflow shape: no `secrets:` input, secret read or Environment in a reusable workflow, with the reason and (sandbox cycle E1) | Reusable cascade workflows hold no secret | verbatim |
| Hardened workflow shape: the App key read only as the `cascade` Environment secret by the caller's own job; no caller passes `secrets:` or `secrets: inherit` | The App key is read only by the caller's own job | verbatim |
| Scripts come from the pinned .github commit: callers reference by full 40-character SHA, never branch or tag, one SHA per repo (owner decision 24 and the supervisor extension) | Callers pin the cascade by full SHA | verbatim |
| Scripts: scripts run at the same commit; composite actions run them from `GITHUB_ACTION_PATH` and do not check out `.github` | The composite actions run their scripts from their own directory | clause split at the `:` and `;`; the first clause is the lead of the next row; trailing `;` is a full stop; one sentence points "that same commit" to "Callers pin the cascade by full SHA" |
| Scripts: each receive job checks out `.github` to `org-github` with `persist-credentials: false` after the `Own commit` checks | The receive workflow checks the scripts out at its own commit | lead "The scripts SHALL run at that same commit, with no input naming another `.github` ref;" then the old clause verbatim; one sentence points "that same commit" to "Callers pin the cascade by full SHA" |
| Scripts: the `Guard` derivation inline and before any script | The repo-name derivation runs inline before any script | verbatim |
| App token minting: minted only inside the two actions, by a job with `environment: cascade`, directly before first use and after every check | The App token is minted after every check that could stop the job | clause split before ", from the `client-id`"; trailing comma is a full stop |
| App token minting: from `client-id` and `private-key` with `owner` and a non-empty `repositories` list; the step before fails when the list is empty | The mint uses a fixed owner and a non-empty repository list | clause split; lead "The App token SHALL be minted"; the "fails when empty" sentence verbatim |
| App token minting: token scopes of notify and publish | The App token has a fixed scope | verbatim |
| App token minting: token not passed, written, put on a command line or kept; git receives it as the masked extraheader | The App token is neither passed nor persisted | verbatim |
| Repo code never holds a token: commands with repo code run with token variables unset | Repo code runs with no token variable | verbatim |
| Repo code: also run with the runner command-file variables and `ACTIONS_*` unset | Repo code runs with no runner command file path | "It" replaced by the subject "Every command that runs code from the calling repo" with its scope list "(its cascade tasks, its `pins.sh`, and the G2 task in a release-head worktree)" |
| Repo code: credentialed git read gets the header for one call only | A credentialed git read gets the header for one call | verbatim |
| Repo code: `compute` token reads before the first repo-code step; no token after | Compute reads with the token before repo code runs | verbatim |
| Repo code: steps are no boundary; later outputs untrusted | Compute output written after repo code is untrusted | verbatim, plus one sentence that points "that point" to the first step named in the previous row |
| No Actions cache: no step saves or restores a cache; `cache: false` | No Actions cache from repo code reaches a publish job (kept) | verbatim |
| No Actions cache: product repos' publish workflows restore no cache; the wiring check enforces it | Product repos restore no cache in their publish workflows | verbatim |
| Compute installs: Task and CUE with `install-tools.sh`, checksums, failures | Compute installs pinned, checksummed tools (kept) | verbatim |
| Compute installs: no version range installed | Compute installs no version range | verbatim, plus one sentence that points to the requirement that holds the install |
| Compute installs: `setup-go` stays SHA-pinned with `cache: false` | Compute keeps setup-go SHA-pinned without a cache | keyword added: "stays" became "SHALL stay" (strength table) |
| This repo's own workflows are least privilege | not rewritten (not over 500) | none |
| Daily mirror drift: runs daily with `contents: read`, no secret, no persisted credentials | Mirror drift runs daily with a read-only token | verbatim |
| Daily mirror drift: reads each recorded file, fails with annotations, checks every file; never required | Daily mirror drift check (kept) | lead: "It" replaced by "`cascade-mirror-drift.yml` (job `Mirror drift`)"; the rest verbatim |
| Rollout order: reference states the order (owner decision 37); one receiver takes a dry run | The pinning reference states the rollout order | verbatim (two sentences) |
| Rollout order: definition of "touches an action" | The pinning reference defines when a change touches an action | "That reference" replaced by "The pinning reference (`references/cascade-pinning.md`)" |
| Rollout order: neither action touched, no canary | A change that touches neither action has no canary | keyword added: "has" became "SHALL have" (strength table) |
| Rollout order: publish only, every receiver dry | A publish-only change while every receiver is dry | clause split at the `;`; trailing `;` is a full stop |
| Rollout order: publish only, once any receiver is live | A publish-only change once a receiver is live | clause split; lead "For a change that touches `cascade-publish` and not `cascade-notify`:"; one sentence that points "that run" to the requirement "A publish-only change while every receiver is dry" |
| Rollout order: notify only | A notify-only change moves one upstream first | verbatim |
| Rollout order: reference does not offer `CASCADE_NOTIFY` off | A notify-only change moves one upstream first | "That reference" replaced by "The pinning reference (`references/cascade-pinning.md`)" |
| Rollout order: both actions | A change that touches both actions follows both rules | verbatim, plus one sentence that names the three requirements that hold the notify rule and the publish rule |
| The renamed controller repo: fixed maps give both names the same answer | The renamed controller repo gets the same answers | verbatim |
| The renamed controller repo: values GitHub must find keep `opm-operator` | A target list keeps the old repo name | lead "While the repo `opm-operator` is renamed `opm-controller`," then the sentence with "A" as "a" |
| The renamed controller repo: `same_repo` | same_repo treats the two names as one repo | same lead, then the sentence verbatim |

#### cascade-wiring-check

| Old requirement and clause | New requirement | New sentence |
| --- | --- | --- |
| Canonical wiring check: the one check of the five repos; missing tool, config or bad config exits 2 | The canonical wiring check is one script | verbatim (two sentences) |
| Canonical: usage, compare with the documented shapes, mismatches on stderr, exit 1, ok line, exit 0 | The wiring check compares the callers with the documented shapes | verbatim |
| Canonical, bullet: no YAML anchor or alias | The wiring check refuses YAML anchors and aliases | "It SHALL check:" replaced by the subject `.github/scripts/cascade/wiring-check.sh` SHALL check:; bullet verbatim, `;` became a full stop |
| Canonical, bullet: key-holding jobs, exact shape | Key-holding jobs have a fixed shape | same lead; bullet cut at the `;` after "key expressions" |
| Canonical, bullet: key-holding jobs, notify and publish against the config | Key-holding jobs match the config | same lead; the job names of the bullet copied before the `:`; second half verbatim |
| Canonical, bullet: `release.yml` workflow `env` | The wiring check limits the workflow env of release.yml | same lead, verbatim |
| Canonical, bullet: receiver workflows | The wiring check holds a receiver's workflows to a fixed shape | same lead, verbatim |
| Canonical, bullet: App key read only by the key-holding jobs, with the reader definition | The App key is read only by the key-holding jobs | same lead; bullet cut at the first `;`; one sentence points "the key-holding jobs" to the requirement that names them |
| Canonical, bullet: cascade Environment only on those jobs | The cascade Environment is declared only on the key-holding jobs | same lead; one sentence points "those jobs" to the requirement "Key-holding jobs have a fixed shape" |
| Canonical, bullet: no call into `.github` passing `secrets:` | No call into .github passes secrets | same lead, verbatim |
| Canonical, bullet: publish workflows use no cache | Publish workflows use no Actions cache | same lead, verbatim |
| Canonical, bullet: every `.github` reference at one full SHA | Every .github reference is at one full SHA with the pin comment | same lead, verbatim |
| Canonical, bullet: the CI job runs exactly the wiring step | The CI job runs exactly the wiring step | same lead, verbatim |
| Per-repo wiring config: values live in `.tasks/cascade/wiring-check.yaml`, exactly these keys | The wiring config holds exactly the documented keys | the key list is in the THEN of scenario "The config keys", byte for byte; the body names the scenario |
| Per-repo config: refuse an unknown key, a wrong type, a `publish-workflows` list without `release.yml` | The wiring check refuses an unknown key, a wrong type or a publish-workflows list without release.yml | clause split of the list; lead "The check SHALL refuse, as a config error," |
| Per-repo config: refuse an `extra-references` item with another key, file name or kind; a `resolver` item on a non-receiver; the same file and kind twice; the four fixed files | The wiring check refuses a bad extra-references item | clause split of the list, same lead |
| Per-repo config: refuse an `env-allow` entry outside the four names, with the reason | The wiring check allows only named env variables | clause split of the list (leading "and" dropped), same lead; reason verbatim |
| Byte-identical copies: copy kept byte-identical; replaced in the PR that moves the pin | Each product repo keeps a byte-identical copy of the wiring check | verbatim |
| Byte-identical: reference gives the fetch and compare commands | The wiring-check reference gives the fetch and compare commands | verbatim |
| Byte-identical: with the flag, fetch the file and compare | The check compares the copy with the file at the pinned SHA | clause split at the `;` after "running" |
| Byte-identical: difference prints `differs from`, failed request prints `cannot fetch` | The check reports a copy that differs or cannot be fetched | clause split; lead "With `--pin-on-main`, after the pin was found on `.github` `main`," |
| Byte-identical: without the flag, print the not-compared line, no request | Without the flag the check does not compare the copy | "the flag" replaced by `--pin-on-main`, which the same requirement names |
| The release key: reader definition, `environment: release` for each reader and only readers | The wiring check finds the release-key readers and holds them to the release Environment | verbatim (two sentences) |
| The release key: mismatch messages, exit 1; needs no config key | A release key mismatch prints a message and exits 1 | verbatim (two sentences), plus one sentence that names the requirement above |
| Declared extra references: each item adds one expected reference; `resolver` and `cite-lint` definitions | A declared extra reference adds one expected reference | keyword added: "is" became "SHALL be" in the two definitions (strength table) |
| Declared extra references: held to the rules of the fixed references | A declared reference follows the fixed rules | verbatim |
| Declared extra references: neither fixed nor declared, or missing, fails | An undeclared or missing reference fails | verbatim |
| Resolver checkouts: fixed inputs; anything else fails with exit 1 | A resolver checkout uses fixed inputs | verbatim (two sentences) |
| Resolver checkouts: what counts as a `.github` checkout; expression and `run:` steps fail | A step counts as a .github checkout by its repository input | verbatim (two sentences) |
| Nothing reaches the CI wiring step: refusals in the CI workflow and job | Nothing reaches the CI wiring step (kept) | verbatim |
| Nothing reaches the CI wiring step: exit 1 before any request when `BASH_ENV` or `ENV` is set | The wiring check exits before any request when BASH_ENV or ENV is set | verbatim |
| Runbook: confirm the SHA first, `cannot compare` also for an unknown SHA | The runbook confirms the pinned SHA first | lead copied from the old first clause; clause split at the first `;` |
| Runbook: re-run; admin bypass only for a PR outside `.github/**` and `.tasks/**` | The runbook allows an admin bypass only for a PR outside .github and .tasks | same lead; clause split; one sentence points to the requirement that confirms the pinned SHA (an unknown SHA is not an outage) |
| Runbook: `--pin-on-main` never removed; failure never bypassed | The runbook keeps the flag and never bypasses a pin failure | same lead; two sentences verbatim |

#### cascade-gates

| Old requirement and clause | New requirement | New sentence |
| --- | --- | --- |
| G2 freshness: add worktree, run the head's task with the env unset | G2 runs the head's task in a detached worktree | clause split before "and rate the result"; trailing comma is a full stop |
| G2 freshness: rate the result by exit code | G2 freshness (kept) | clause "rate the result:" with its lead; the rest verbatim; one sentence points "the result" to the requirement that runs the task |
| G2 freshness: worktree removed on error | G2 runs the head's task in a detached worktree | verbatim |
| G2 freshness: runs before pin work, results uploaded | G2 runs before pin work and uploads its results | verbatim, plus one sentence that names the requirement that defines the evaluation |
| G3 settled: problem when the upstream's own cascade PR has a `fix(deps)` or `feat(deps)` title | G3 is a problem when an upstream has an open cascade PR | clause split; lead is the whole upstream map and "G3 SHALL be a problem when" |
| G3 settled: problem when an upstream release PR is pending with deps | G3 is a problem when an upstream release PR is pending with deps | clause split; same lead |
| G3 settled: otherwise `ok: upstreams settled`, API error, release-tool edges never count | G3 is otherwise settled | verbatim, plus one sentence that names the two requirements that define "otherwise" |
| G3 settled: evaluated by `gates` from API reads, once per run, posted on every head | G3 is evaluated by the gates job from API reads | verbatim |
| G3 settled: never read from `compute` | G3 is evaluated by the gates job from API reads | "It" replaced by "G3" |
| Status mapping: statuses posted with `GITHUB_TOKEN`, contexts, URL, 140 characters, then the table | Statuses are posted with GITHUB_TOKEN in two contexts | the table is in the THEN of scenario "Status table", byte for byte; the body names it |
| Status mapping: `gates` runs after `compute` | The gates job runs after compute | verbatim |
| Status mapping: list the heads, post only on them, fail when unreadable; take only G2 from `gates.json` | The gates job posts only on listed heads | the "It" of the list sentence replaced by "The `gates` job"; the other sentence verbatim |
| Status mapping: head without a G2 result | A listed head without a G2 result gets a warning or an error | verbatim |
| Per-PR gates workflow: inputs, one job, permissions, checks out nothing | The per-PR gates workflow has fixed inputs, job and permissions | clause split before ", and:"; subject copied |
| Per-PR gates workflow: not a release PR posts `success` | A PR that is not a release PR gets n/a | clause split of the `;`-list; subject copied |
| Per-PR gates workflow: same-repo release PR posts `pending`, starts `deps-cascade.yml` | A same-repo release PR starts a gates-only run | clause split; subject copied |
| Per-PR gates workflow: a failed start posts `error` or a warning, then fails | A failed start posts error or a warning | verbatim, plus one sentence that names the requirement that holds the start |
| Per-PR gates workflow: a gates-only run only posts | A gates-only receiver run only posts the gates | verbatim |

#### cascade-pr-text

| Old requirement and clause | New requirement | New sentence |
| --- | --- | --- |
| Path classification: `classify` reads paths and prints classes; the classes file format and first-match rule | classify prints the class of each path | verbatim (two sentences) |
| Path classification: the five pattern forms | Patterns match in five forms | verbatim |
| Path classification: exit 1 on an unknown class, a line without a pattern or a bad pattern | classify exits 1 on a bad line | verbatim, plus one sentence that names the requirement that holds "these five forms" |
| Diff and moved pins: `--classes`, `--pins`, base ref | title and body take the classes, the pins script and a base ref | verbatim |
| Diff and moved pins: merge-base, changed paths, moved pins, renamed file | Diff and moved pins (kept) | "They" replaced by "`title` and `body`"; the rest verbatim |
| Diff and moved pins: pins script that exits non-zero | A failing pins script fails title and body | verbatim |
| Cascade PR title: one line; the type rule; no `!`, no other type | The title type follows the changed paths | verbatim (three sentences, the first and the last from the ends of the old body) |
| Cascade PR title: subject rules; `<to>` v-prefixed | The title subject names the moved pins | verbatim (two sentences) |
| Cascade PR title: no changed path prints nothing, exit 3 | An empty diff gives no title | "it" replaced by "`title`" |
| Cascade PR body: exactly these lines, the fenced layout | The PR body is printed in a fixed layout | the fenced block is in the THEN of scenario "Body layout", byte for byte; the body names it, and names the five requirements that describe the parts |
| Cascade PR body: `<labels>` union; never `deps-cascade:breaking` | The body labels | the bullet dash dropped; the rest verbatim |
| Cascade PR body: table rows; counts | The body table and the counts | verbatim (two sentences) |
| Cascade PR body: triggering releases per valid tag; tag pattern; nothing valid | Triggering releases list one line per valid tag | verbatim (three sentences) |
| Cascade PR body: dropped value named with `?` | A dropped value is named only with safe characters | verbatim |
| Cascade PR body: source allowlist | A source outside the allowlist is dropped | verbatim |
| Cascade PR body: `CASCADE_EXTRA_SOURCES` | CASCADE_EXTRA_SOURCES widens the allowlist | verbatim, plus one sentence that points "those six names" to the requirement that lists them |
| Cascade PR body: warnings lines, `-` key, none | The body warnings | verbatim (three sentences) |
| Cascade PR body: notes byte for byte; never edited or linted | The body ends with the Notes | verbatim (two sentences) |

#### cascade-notify

| Old requirement and clause | New requirement | New sentence |
| --- | --- | --- |
| Notify interface: composite action, inputs; no dry-run mode | Notify interface (kept) | verbatim (two sentences) |
| Notify interface: the upstream runs it as the only step of `Notify downstream` | The upstream runs the notify action as its only step | keyword added: "runs" became "SHALL run" (strength table); one sentence names the requirement that defines "it" |
| Source and targets: source is the calling repo's name | The source is the calling repo's name | verbatim |
| Source and targets: targets from a fixed map; unknown source fails; the table | Targets come from a fixed map | the table is in the THEN of scenario "Target map", byte for byte; the body names it |
| Source and targets: `opm-controller` and the old name in target lists | A target list names only the old repo name | verbatim |
| Source and targets: `tag` shape | The tag input matches a fixed shape | verbatim |

#### Strength table (RFC 2119 words added by the whole change)

Batch B1 adds nine keywords, the first nine rows below (eight in cascade-receive, one in cascade-resolver-checks). The CI step requirement is new text, written with SHALL. Batch B2 adds four, listed after them:

| New requirement | Old sentence | New sentence |
| --- | --- | --- |
| Receive jobs have fixed environment, permissions and timeouts | "The jobs ... the table" (the job table stood in the body; the plain text had no keyword) | "The jobs `compute`, `gates` and `publish` SHALL have the environment, permissions and timeout of the table in the scenario "Job limits"." |
| Receive jobs have fixed environment, permissions and timeouts | "`compute` runs the repo's task and holds no secret." | "`compute` SHALL run the repo's task and hold no secret." |
| Receive jobs have fixed environment, permissions and timeouts | "`publish` runs only `git`, `gh`, `jq` and the `.github` scripts of the pinned action, never a repo task or repo code, and fails on any ref other than `refs/heads/main`." | "`publish` SHALL run only ... and SHALL fail on any ref other than `refs/heads/main`." |
| The publish job is the caller's own | "it needs the reusable job, declares `environment: cascade`, and runs the composite action ..." | "it SHALL need the reusable job, declare `environment: cascade`, and run the composite action ..." |
| The stop switch variable is case-insensitive | "`CASCADE_DRY_RUN` set to `false` in any letter case ... makes the receiver live, and every other value, unset included, keeps it dry." | "... SHALL make the receiver live, and every other value, unset included, SHALL keep it dry." |
| The payload source allowlists | "Allowlists: `catalog_opm` accepts `core`, `cli`; ..." | "The allowlists SHALL be: `catalog_opm` accepts `core`, `cli`; ..." |
| The workflows guard limits what the bot pushes | the push rule was the table of the old body ("Push allowed" columns) | "the push rule SHALL be that of the scenario "Guard table" for each mode and each rule value" |
| The workflows guard rule ships as tree | "the rule constant `WF_GUARD_RULE`, which ships as `tree` ...; `strict` stays implemented for the case GitHub tightens the rule" | "The rule constant `WF_GUARD_RULE` SHALL ship as `tree` (...); `strict` SHALL stay implemented for the case GitHub tightens the rule." |
| The wiring suite uses the real resolver for offline subcommands only (cascade-resolver-checks) | "(`title`, `body`, `classify`, `semver-cmp`; no case calls `newest`, `published` or `pin-of`)" | "(`title`, `body`, `classify`, `semver-cmp`); no case SHALL call `newest`, `published` or `pin-of`." |
| A change that touches neither action has no canary | "A change that touches neither `cascade-publish` nor `cascade-notify` has no canary: all five repos MAY move together, ..." | "... SHALL have no canary: ..." (the validator wants SHALL or MUST in every ADDED body; MAY alone fails) |
| Compute keeps setup-go SHA-pinned without a cache | "`setup-go` stays SHA-pinned with `cache: false`." | "`setup-go` SHALL stay SHA-pinned with `cache: false`." |
| A declared extra reference adds one expected reference | "A `resolver` reference is a step whose ..." and "A `cite-lint` reference is a job whose ..." | "SHALL be" in place of "is" in both |
| The upstream runs the notify action as its only step | "The upstream runs it as the only step of its own job ..." | "The upstream SHALL run it as the only step of its own job ..." |

#### New scenarios of B2

These scenarios are not in the old specs. Each restates the rule of its body in one WHEN and one THEN, using words of that body; a table or a fenced block that sat in a body is in the THEN of "Status table", "Target map", "The config keys" and "Body layout". Every kept or moved scenario is byte for byte as on `origin/main` (the scenario check prints `same:` for it).

- cascade-workflows (15): A workflow with no explicit permissions; Caller passes secrets: inherit; Reference by a branch; Guard before the scripts; Notify token scope; Publish token scope; Token handed to another job; Git receives the token as a header; Header for one git call only; Output written after repo code; Mirror drift permissions; Publish workflow restores a cache; Version range; setup-go reference; Dry run first.
- cascade-wiring-check (16): A missing config; A merge key; A key-holding job with another timeout; Env key outside the allow-list; A receiver trigger that differs; References at two SHAs; A path filter on the CI job; The config keys; An unknown config key; Commands in the reference; A matching copy; A failed fetch; Mismatch message; A declared reference that is missing; ENV set with the flag; A pin failure is never bypassed.
- cascade-gates (11): Worktree after an error; Upload after a failed step; Release PR pending with deps; Nothing pending; Status table; Gates job in a dry run; The list cannot be read; Gates workflow checkout; Dispatch fails in enforce mode; Dispatch fails in warn mode; Gates-only run.
- cascade-pr-text (11): Base ref fallback; Pins script exits non-zero; Unknown class; Paths changed, no pin moved; Body layout; Counts per class; Dropped value with a hostile character; Extra name that is not a repo name; Explicit warnings file missing; No warnings; Notes from the file.
- cascade-notify (4): Notify downstream job; A caller names another source; Target map; Target list with the new name.

Total 57.

### Repo extra: the CI step

One requirement is new and rewrites no old text, so it has no old scenario and no clause row. Its length is 324 characters.

| Old scenario name | New place (requirement, scenario name) | Changed text? |
| --- | --- | --- |
| (none, new requirement) | Resolver tests validate the OpenSpec specs, A spec with a long requirement fails the job | new |
| (none, new requirement) | Resolver tests validate the OpenSpec specs, A different CLI version fails the job | new |
| (none, new requirement) | Resolver tests validate the OpenSpec specs, The validation reports on every pull request | new |

Install check (task 3.1): the 1.14.1 package installed on the host and every package in that tree declare no `preinstall`, `install` or `postinstall` script. This is not proof for the tree that CI resolves at run time; the CI run of the pull request is the first real install.

## Risks

- A rewrite changes a rule by accident. Mitigation: the review checklist per unit and the `DIFF`/`LOST` script.
- Another repo copies spec text from this one (the `references/` files and five product repos' wiring copies cite requirement names). Mitigation: the grep of D2 before each rename; product repos hold no spec text.
- The CI step fails every PR if the pin is wrong. Mitigation: the implementing author runs the same commands locally before the commit; actionlint runs on the edited workflow.

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

Empty at the proposal step. Each unit appends its blocks here (form D2) in the commit of its delta.

## Risks

- A rewrite changes a rule by accident. Mitigation: the guide checklist per unit and the `DIFF`/`LOST` script.
- Another repo copies spec text from this one (the `references/` files and five product repos' wiring copies cite requirement names). Mitigation: the grep of D2 before each rename; product repos hold no spec text.
- The CI step fails every PR if the pin is wrong. Mitigation: the implement unit runs the same commands locally before the commit; actionlint runs on the edited workflow.

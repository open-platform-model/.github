Gates for every section (the repo's Validation Gates): `shellcheck` (pinned v0.11.0) on every
`*.sh` under `.github/scripts/` and on every test shim; `actionlint` (pinned v1.7.12) on
`.github/workflows/*.yml`; `bash .github/scripts/cascade/test/run.sh` and, from section 1 on,
`bash .github/scripts/cascade/wiring/test/run.sh`; `openspec validate --all --strict`. All run
offline. Interface source: the Phase 3 wiring contract, version 2, committed as `contract.md` and
cited as "contract §N". Depends on: `add-cascade-resolver` (merged) and the Phase 0 settings
(done); section 5 also needs the supervisor's sandbox preconditions (proposal, "Depends on").
Join changes (`join-release-cascade` in core, catalog_opm, library, opm-operator, cli) merge only
after this change.

## 1. Wiring library, sandbox sources and the test harness

- [ ] 1.1 Change `.github/scripts/cascade/lib/prtext.sh:11` to append `${CASCADE_EXTRA_SOURCES:-}` to `CASCADE_SOURCES`, ignoring with a warning any extra name that does not match `REPO_RE`; add the two `cascade-pr-text` scenarios ("Sandbox source accepted when listed", "Sandbox source dropped when not listed") as cases in `test/cases/prtext.sh` beside `:216-218`; resolver suite green
- [ ] 1.2 Add `.github/scripts/cascade/wiring/lib.sh` per design "Layout": the contract §3.1 to §3.7 maps, `WF_GUARD_RULE=strict`, repo-name derivation and the `org-github-ref` guard (contract §2.2, §2.4), payload validation (contract §6.2 step 4), `cascade_pr` (contract §6.2 step 6), Notes and title-marker extraction with CRLF handling (contract §6.2 step 9, §7.3), the type rank and final-title function (contract §7.3), the mention lint (pattern of `lib/prtext.sh:10`), the contract §7.5 comment texts, the workflows guard (contract §7.6), the action table (contract §6.2 step 12) and the status mapping with 140-character truncation (contract §8.1)
- [ ] 1.3 Add the wiring harness: `wiring/test/run.sh`, `wiring/test/lib.sh` (case runner, isolated git, temp dirs under a trap, bare `file://` origins, a toy `Taskfile.yml` whose `deps:cascade` edits a pinned file and whose title and body tasks call the real resolver offline), and `wiring/test/shim/gh` (answers from per-case fixtures, logs every call, fails on an unexpected call)
- [ ] 1.4 Add cases for every `lib.sh` function: the maps and a source or receiver outside them; payload validation (8 tags, 9 tags, a bad tag, an unknown source, extra keys, `@x`); the cascade-PR filter (fork PR, human PR, two matches); Notes with marker, without it and CRLF stable over two runs; title not retitled, retitled with `!` kept, title rise once, marker in the Notes, no marker; every workflows-guard row under `strict` and `tree`; every action-table row; status mapping and truncation; the repo-name and ref guards; the static check that no `run:` block in `.github/workflows/cascade-*.yml` contains `${{`; wiring suite green
- [ ] 1.5 In `.github/workflows/cascade-resolver.yml` add the step `Offline wiring tests` after `Offline resolver tests` and add `wiring/test/shim/gh` to the shellcheck list (`:66-69`); job name `Resolver tests` unchanged, timeout raised only if a green run needs it
- [ ] 1.6 Gates green, then commit `feat(cascade): add the cascade wiring library and sandbox sources`

## 2. Notify

- [ ] 2.1 Add `wiring/notify.sh` with `validate`, `wait-proxy` and `dispatch` per design "Script interfaces": targets from the contract §3.1 map, tag shapes from §3.3, the body built with `jq -n --arg`, 3 attempts per target (5, 15, 45 s via `CASCADE_SLEEP`), every target tried, one summary line each, exit 1 when any target failed
- [ ] 2.2 Add `.github/workflows/cascade-notify.yml` per contract §4.1 and design "Workflows": inputs `tag` and `org-github-ref`; job `Notify downstream`, `environment: cascade`, `permissions: {contents: read}`, 20 min; guard, `org-github` checkout, validate, the library-only proxy wait, the non-empty repository-list check, the mint (contract §2.3: targets, `permission-contents: write`), dispatch; actionlint clean
- [ ] 2.3 Add cases: the exact payload bytes for library `v1.0.0-beta.4` to `opm-operator` and `cli`; one target failing three times while the next succeeds (job exit 1, both summary lines); a catalog tag without `opm-`; an unknown source; the proxy wait timing out with a fake clock and still exiting 0; wiring suite green
- [ ] 2.4 Gates green, then commit `feat(cascade): add the reusable notify workflow`

## 3. Receiver: compute and publish

- [ ] 3.1 Add `wiring/receive-compute.sh` steps `guard`, `payload`, `state`, `prepare`, `notes`, `run`, `text`, `action`, `plan` and `summary` per contract §6.2 (steps 1 to 4 and 6 to 15), §7.1 to §7.4 and §7.6: forced dry run off `main`, the sandbox-only `CASCADE_EXTRA_SOURCES`, modes, derived-file merge rules (design "Branch strategy, title, labels, gates"), the bot identity, the task run and the title-before-equals-title-after check, body, final title, labels with the breaking check over the pin range, the action table, the workflows guard, `plan.json`, the bundle, the summary with "DRY RUN" and the 200 KB cap; scratch files only under `CASCADE_T`
- [ ] 3.2 Add `wiring/receive-publish.sh` `verify` and `act` per contract §6.4: every pre-mint refusal, the lease pushes and deletes with the masked `GIT_CONFIG_*` header, PR create and edit, `recreate` with carried labels and the "Continued in" comment, `close`, `conflict` without comment spam, `too_long` exiting 1, the title-rise comment, and label creation or the `labels-managed` check
- [ ] 3.3 Add `.github/workflows/cascade-receive.yml` jobs `compute` and `publish` per contract §6.1, §6.2 and §6.4 and design "Workflows" (inputs, toolchains, the yq check, artifacts, outputs, the publish `if:`, the mint scoped to the calling repo); actionlint clean
- [ ] 3.4 Add cases against bare-repo fixtures: each mode including a human-amended bot commit giving `merge`; a derived-file conflict resolved to `main`'s side and a hard conflict giving `conflict`; exit 3 with and without an open PR (`close`, `noop`); a dirty tree refused; the breaking check with a breaking release in the middle of the range and with an API error; a body over 65000 bytes; the publish refusals (PR-number mismatch, unknown label, unknown action, a title that does not recompute, a moved remote tip); `recreate` end to end against the bare origin; wiring suite green
- [ ] 3.5 Gates green, then commit `feat(cascade): add the reusable receive workflow`

## 4. Gates and docs

- [ ] 4.1 Add `wiring/gates-eval.sh` (contract §8.2: release-PR scope, G2 in a detached worktree under `CASCADE_T` with payload variables unset and removal on error, G3 over the contract §3.5 upstreams) and `wiring/gates-post.sh` (contract §8.1, §8.4); wire the `compute` step `gates` (contract §6.2 step 5, before any pin work, artifact upload `if: always()`, the `gates-only` stop) and the `gates` job (contract §6.3, including the missing-artifact rules)
- [ ] 4.2 Add `.github/workflows/cascade-gates.yml` per contract §8.3: job `Cascade gates`, `permissions: {statuses: write, actions: write}`, no checkout, inline guards, `n/a` on non-release and fork PRs, `pending` in `enforce` only, `gh workflow run deps-cascade.yml --ref main -f gates_only=true`, the dispatch-failure statuses; actionlint clean
- [ ] 4.3 Add cases: G2 exit 3, exit 0 with a shipped path (message `behind: …`), exit 0 with only test paths, other exit; G3 problem A, problem B, a fork `deps/cascade` PR ignored, an API error; every mode-by-result cell of the status mapping; a missing artifact in `warn` and `enforce`; wiring suite green
- [ ] 4.4 Extend the README `cascade` section with the workflows: the three reusable workflows and their jobs, the caller shapes of contract §4.3, §5 and §8.3, the repo variables `CASCADE_DRY_RUN` (live only at exactly `false`), `CASCADE_NOTIFY`, `CASCADE_G2_MODE` and `CASCADE_G3_MODE`, the stop switches of contract §9.2, and that callers use `@main` (owner decision 13)
- [ ] 4.5 Gates green, then commit `feat(cascade): add the cascade gates and document the workflows`

## 5. Sandbox cycle, verification and archive

- [ ] 5.1 Confirm the supervisor's preconditions with `gh api` (`cascade-sandbox-up` public, `main` rulesets on both sandboxes, `CASCADE_DRY_RUN=false` on down, this branch on `origin`) and stop and report if any is missing
- [ ] 5.2 Seed both sandbox repos as design "Sandbox cycle" lists, calling `@feat/add-release-cascade-workflows` with that `org-github-ref`; run E1 and E1b first and stop and report to the supervisor if E1 fails (contract §13.1) or E2 fails (contract §13.2)
- [ ] 5.3 Run E2, S3, S4, E3/E4 (a) to (c), E5, E7 and S5 to S11; record each run URL, PR URL and outcome in the "Sandbox cycle" table of `design.md`; set `WF_GUARD_RULE` from E4c (rerun (a) and (b) when it becomes `tree`); record E6 as pending until the supervisor toggles the setting after merge
- [ ] 5.4 Write the owner's pull-request-only bypass check (contract §11.4 last paragraph) into the PR notes, without performing it
- [ ] 5.5 Gates green and the OpenSpec verify step clean for `add-release-cascade-workflows`, then commit `docs(cascade): record the sandbox cycle`
- [ ] 5.6 After supervisor review, `openspec archive add-release-cascade-workflows --yes`, `openspec validate --all --strict` green, then commit `chore(openspec): archive add-release-cascade-workflows` (rides the implementing PR)

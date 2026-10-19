## 1. Batch .github-B1: cascade-receive, cascade-resolver, cascade-resolver-checks, tag-ledger (28 requirements)

- [ ] 1.1 For each long requirement of the four specs (cascade-receive 13, cascade-resolver 9, cascade-resolver-checks 5, tag-ledger 1), read the text, choose the form by design.md D1, and grep the repo outside `openspec/changes/archive` for the header text before any rename or split
- [ ] 1.2 Write the deltas in `specs/<spec>/spec.md` of this change; keep every old scenario byte for byte; keep RFC 2119 keywords and citations in bodies; no `**Key**:` line, no `#####` heading, no fenced block in a body
- [ ] 1.3 Append the scenario ledger and clause tables of the 28 requirements to design.md
- [ ] 1.4 Run the guide gate in a scratch copy (design.md D4): N = 28, warnings 55 to 27, no new ERROR item, no "Archive would refuse"; run `validate <spec> --type spec --strict` for the four specs and the scenario check per requirement (no `DIFF`, no `LOST`)
- [ ] 1.5 `shellcheck`, `actionlint` and every `test/run.sh` green, then commit docs(openspec): split the long requirements of batch B1

## 2. Batch .github-B2: cascade-workflows, cascade-wiring-check, cascade-gates, cascade-pr-text, cascade-notify (27 requirements)

- [ ] 2.1 For each long requirement of the five specs (cascade-workflows 9, cascade-wiring-check 8, cascade-gates 4, cascade-pr-text 4, cascade-notify 2), read the text, choose the form by design.md D1, and grep the repo outside `openspec/changes/archive` for the header text before any rename or split
- [ ] 2.2 Write the deltas, with the same rules as 1.2
- [ ] 2.3 Append the scenario ledger and clause tables of the 27 requirements to design.md
- [ ] 2.4 Run the guide gate (D4) with N = 55 and LAST=1: after the archive in the scratch copy `validate --specs --strict` exits 0, `validate <change> --strict` exits 0, no new ERROR item, no "Archive would refuse"; report whether `validate --all --strict` exits 0; run the per-spec check and the scenario check as in 1.4
- [ ] 2.5 `shellcheck`, `actionlint` and every `test/run.sh` green, then commit docs(openspec): split the long requirements of batch B2

## 3. Repo extra: OpenSpec gate in the Resolver tests job

- [ ] 3.1 Confirm in a scratch folder that `@fission-ai/openspec@1.14.1` installs with `--ignore-scripts` and runs `validate`; if it needs an install script, stop and ask
- [ ] 3.2 Add the pinned install step and the `openspec validate --all --strict --no-interactive` step to the job `Resolver tests` of `.github/workflows/cascade-resolver.yml` as in design.md D5; add no job, no permission and no action; update the header comment of the workflow
- [ ] 3.3 Write the delta for `cascade-resolver-checks`: one ADDED requirement for the step (a body of at most 500 characters, scenarios for pass and fail); add its ledger line to design.md
- [ ] 3.4 Run the new commands locally in the worktree (`openspec validate --all --strict --no-interactive` exits 0 after groups 1 and 2), `actionlint .github/workflows/*.yml`, shellcheck and every `test/run.sh`; rerun the guide gate
- [ ] 3.5 Commit ci(cascade): gate the specs with openspec validate in resolver tests

## 4. Repo extra: AGENTS.md

- [ ] 4.1 Change the sentence "CI runs the first three" in the Commands section of `AGENTS.md` to say that CI runs all four commands; the table row for `openspec validate --all --strict` stays as it is; check `openspec/config.yaml` gate 4 needs no edit
- [ ] 4.2 Commit docs(openspec): state that CI runs the openspec validate gate

## 5. Final gate

- [ ] 5.1 Run the guide gate with LAST=1 in a scratch copy and the review checklist of the guide (scope against the T1.3 inventory, rule meaning, scenario bytes, loopholes, lengths, forms, references, gate rerun): `validate split-long-requirements --strict` exits 0, `validate --specs --strict` exits 0 after archive, no "Archive would refuse", no new ERROR item
- [ ] 5.2 Fill the Deviations part of the report; confirm every scenario of every rewritten requirement is in the ledger
- [ ] 5.3 Archive the change on this branch (`openspec archive split-long-requirements --yes`), then run `openspec validate --all --strict --no-interactive` on the archived tree; it exits 0
- [ ] 5.4 Commit chore(openspec): archive split-long-requirements

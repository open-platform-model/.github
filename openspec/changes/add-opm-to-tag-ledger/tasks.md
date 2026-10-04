Gates for every section, the repo's Validation Gates:

- `shellcheck` on every `*.sh` under `.github/scripts/` and on `.github/scripts/cascade/test/shim/{curl,git}`
- `actionlint .github/workflows/*.yml`
- `bash .github/scripts/cascade/test/run.sh`
- `openspec validate --all --strict`

All of these run offline. Scratch files go only to the session scratchpad as `p3-gh-ledger-*`.
Never dispatch `tag-ledger.yml` from this branch (`design.md`, D4).

## 1. Scan the opm repo

- [x] 1.1 In `.github/workflows/tag-ledger.yml`, change `REPOS` to `core library catalog_opm cli opm-operator opm`. Change no other line in the workflow, `tag-ledger.sh` or `ledger-integrity.sh`, and confirm with `git diff --stat` that those three files show only this one line.
- [x] 1.2 In `README.md`, add `opm` to the tag-ledger "Scope:" list after `opm-operator`, wording per `design.md` D3.
- [x] 1.3 Write the PATH shims and recording wrappers of `design.md` D4 into the scratchpad: recording `git` and `curl` wrappers for V2, and replaying `git`, `curl` and `date` shims for V1 (`date` prints a fixed `2026-10-04T00:00:00Z`). Save `git show origin/tag-ledger:ledger.tsv` as the starting ledger.
- [x] 1.4 Run V2 once, recording: first require `rate.remaining` of at least 40 from `https://api.github.com/rate_limit`, then run the six repos with `GH_TOKEN` unset against a scratch copy of the ledger. It must exit 0 with empty FINDINGS, and its appended rows must include `opm` `v1.0.0-beta.1`. The recording is the V1 fixture tree for all six repos.
- [x] 1.5 Run V1 cases E-old, E-new, E-moved, E-deleted, E-revert and E-ruleset offline against the recorded fixtures with the worktree's `tag-ledger.sh`. Each case must hold as tabled in `design.md` D4. Record the outputs and a result table for the PR body in the scratchpad.
- [x] 1.6 Gates green, then commit `ci(tag-ledger): scan the opm repo for tag drift`.

## 2. Mention-guard Limits paragraph

- [x] 2.1 In `README.md`, extend the mention-guard "Limits" paragraph per `design.md` D3:
  - a ruleset-required run fires only on `opened`, `synchronize` and `reopened`, and ignores `edited`;
  - a re-run reads the title and body from the original event, while commit messages are listed fresh;
  - for a fresh scan, push a commit, or close and reopen the PR.
  The added lines must contain no bare `@word`, and `mention-guard.yml` must stay unchanged.
- [x] 2.2 Gates green, then commit `docs(mention-guard): say a ruleset run ignores edited`.
- [x] 2.3 Apply the review corrections of `design.md` D5: the spec, proposal and design say only `tags-immutable` is required; the README gains the step-4 sentence of `design.md` D3, scopes the mention-guard note to the other org repos, and keeps its wrap. Gates green, then commit.

## 3. Archive

- [ ] 3.1 After review, run `openspec archive add-opm-to-tag-ledger`, check `openspec validate --all --strict` is green, then commit `docs(openspec): archive add-opm-to-tag-ledger` on this branch, so the archive rides the implementing PR.

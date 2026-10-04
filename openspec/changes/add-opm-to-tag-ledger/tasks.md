Gates for every section, the repo's Validation Gates:

- `shellcheck` on every `*.sh` under `.github/scripts/` and on `.github/scripts/cascade/test/shim/{curl,git}`
- `actionlint .github/workflows/*.yml`
- `bash .github/scripts/cascade/test/run.sh`
- `openspec validate --all --strict`

All of these run offline. Scratch files go only to the session scratchpad as `p3-gh-ledger-*`.
Never dispatch `tag-ledger.yml` from this branch (`design.md`, D4).

## 1. Scan the opm repo

- [ ] 1.1 In `.github/workflows/tag-ledger.yml`, change `REPOS` to `core library catalog_opm cli opm-operator opm`. Change no other line in the workflow, `tag-ledger.sh` or `ledger-integrity.sh`, and confirm with `git diff --stat` that those three files show only this one line.
- [ ] 1.2 In `README.md`, add `opm` to the tag-ledger "Scope:" list after `opm-operator`, wording per `design.md` D3.
- [ ] 1.3 Capture the V1 fixtures into the scratchpad, read-only:
  - `git ls-remote --tags` for the six repos;
  - the anonymous tag and branch ruleset listings and the three ruleset bodies for `core` and `opm`;
  - `git show origin/tag-ledger:ledger.tsv`.
  Write the `git` and `curl` PATH shims described in `design.md` D4.
- [ ] 1.4 Run V1 cases E-old, E-new, E-moved, E-deleted, E-revert and E-ruleset with the worktree's `tag-ledger.sh`. Each case must hold as tabled in `design.md` D4. Record the outputs in the scratchpad.
- [ ] 1.5 Run V2 once: the six repos, `GH_TOKEN` unset, against a scratch copy of the live ledger. It must exit 0 with empty FINDINGS, and its appended rows must include `opm` `v1.0.0-beta.1`.
- [ ] 1.6 Gates green, then commit `ci(tag-ledger): scan the opm repo for tag drift`.

## 2. Mention-guard Limits paragraph

- [ ] 2.1 In `README.md`, extend the mention-guard "Limits" paragraph per `design.md` D3:
  - a ruleset-required run fires only on `opened`, `synchronize` and `reopened`, and ignores `edited`;
  - "Re-run jobs" rescans the original event's text;
  - for a fresh scan, push a commit, or close and reopen the PR.
  The added lines must contain no bare `@word`, and `mention-guard.yml` must stay unchanged.
- [ ] 2.2 Gates green, then commit `docs(mention-guard): say a ruleset run ignores edited`.

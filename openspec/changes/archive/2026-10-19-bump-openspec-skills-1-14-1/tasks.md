## 1. Regenerate skills

- [x] 1.1 Build pristine 1.12.0 and 1.14.1 skill output in a scratch directory, with no network.
- [x] 1.2 Confirm the repo skills equal pristine 1.12.0, then run `openspec update --force`.
- [x] 1.3 Confirm every generated skill is at `generatedBy: "1.14.1"`, equals pristine 1.14.1, and `openspec/config.yaml` is unchanged.
- [x] 1.4 Run `openspec validate --all --no-interactive` and a hidden-Unicode scan on the skills.
- [x] 1.5 Commit as `chore(openspec): regenerate the OpenSpec skills with 1.14.1`.

## Why

GitHub renames `opm-operator` to `opm-controller`. The daily `tag-ledger` run reads every repo in
`REPOS` twice: `git ls-remote` (which follows GitHub's redirect) and the REST ruleset listing
through `api_get` in `tag-ledger.sh`, whose `curl` does not follow redirects. After the rename the
listing for `opm-operator` answers HTTP 301, `check_ruleset` treats any status other than 200 or
404 as a failed scan (`exit 3`), and every run fails until `REPOS` names the new repo. Before the
rename the new name cannot be scanned at all (`git ls-remote` fails and aborts the run). So the
flip is its own one-line change, merged right after the rename.

Folding it into `retire-operator-repo-name` would leave the ledger red for the whole window
between the rename and that change's merge, which waits for the controller and cli rename PRs
and their releases.

## What Changes

- `tag-ledger.yml` `REPOS` scans `opm-controller` in place of `opm-operator`.
- The tag-ledger scope is the `REPOS` list. Main's README split removed the repo list from the README, so the README holds no copy to rename.
- The `tag-ledger` spec's scanned-repo list and summary line follow.

The ledger keeps its `opm-operator` rows (append-only) and records the renamed repo's tags again
under `opm-controller` on the first run after merge (the "Joining and leaving the scan" rule).

Not in this change: the cascade maps, `MIRROR_RECEIVERS` and the mirror hashes
(`retire-operator-repo-name`), the GitHub rename itself (owner step).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `tag-ledger`: the scanned set names `opm-controller` instead of `opm-operator`.

## Impact

- Workflow `tag-ledger.yml` (`REPOS`), `openspec/specs/tag-ledger`.
- Unpinned: `tag-ledger.yml` runs from this repo's default branch, so the change takes effect at
  merge. No receiver pins it and no pin round follows.

Depends on: the GitHub rename. Merge it right after the rename, before the next scheduled run
(04:17 UTC); it must not merge before the rename.

## Enhancement

None.

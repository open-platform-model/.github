## Context

`tag-ledger.yml` runs on schedule and dispatch from `.github` `main`. `REPOS` names the scanned
repos. `tag-ledger.sh` reads tags with `git ls-remote` (follows redirects) and asserts org
rulesets through `api_get` (`curl` without `-L`). `check_ruleset` exits 3 on any listing status
other than 200 or 404.

## Goals / Non-Goals

**Goals:** the ledger keeps scanning the renamed repo without a red run between the rename and the
cascade flip.

**Non-Goals:** following redirects in `api_get`, cascade maps, any receiver repo.

## Decisions

### D1: Flip on its own, right after the rename

The flip cannot land before the rename (`git ls-remote` of a missing repo fails the run) and
should not wait for `retire-operator-repo-name` (the old name answers 301 to the ruleset listing,
which fails every run). A separate unpinned PR merged right after the rename leaves at most the
minutes of the sitting in between. If a scheduled run (04:17 UTC) falls into that gap, it fails
with "the run did not complete" and comments on the drift issue; the first run after the merge is
clean, and the owner closes the issue.

### D2: Not `curl -L`

Following redirects in `api_get` would keep the old name scannable, but it would also hide a
rename of any scanned repo behind a redirect and leave the old name in `REPOS` until a later
cleanup. The rename is a one-off; one line in the right order is simpler.

### D3: The ledger records the renamed repo as a joining repo

The first run after the merge appends every `opm-controller` tag as a new row with a fresh
`first_seen` and does not compare them with the `opm-operator` rows. A tag moved inside the
rename window would therefore be baselined silently. The cutover closes that gap with a one-off
check on the `tag-ledger` branch (every `opm-operator` row has an `opm-controller` row with the
same tag, object and peeled SHA); it is not built into the script, so no old name stays in code.

## Risks / Trade-offs

- [Merged before the rename] -> `git ls-remote` fails and every run fails until the rename. The PR
  says so; the owner merges it after the rename.
- [A tag moved during the window] -> caught by the cutover check in D3, not by the run.

## Rollout

1. GitHub rename.
2. Merge this change; dispatch `tag-ledger.yml`; expect a clean run that appends the
   `opm-controller` rows.
3. Run the D3 check on the `tag-ledger` branch; it prints nothing.

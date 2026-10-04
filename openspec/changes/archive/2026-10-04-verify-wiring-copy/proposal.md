## Why

The wiring check is one canonical script kept byte-identical in five product repos at
`.tasks/cascade/wiring-check.sh`. Today nothing but review checks that a repo's copy is the file
at its pinned `.github` SHA: the README says "the script cannot verify its own provenance
offline, so this is the review's job". A copy that drifts (a local allow-list tweak, a stale copy
after a pin bump, a hand edit in a PR) keeps passing CI with rules the pinned commit never had.

Second, the check's list of `.github` references is fixed: the four `uses:` lines and the
`cascade-task.yml` resolver checkout. opm-operator `main` has a second resolver checkout, in
`.github/workflows/module-deps.yml` (the operator module's own dependency bot, job `compute`,
step "Clone the cascade resolver"), so the operator's wave-2 pin bump cannot pass the canonical
check without a way to declare it.

Third, the required CI step now calls the GitHub API (`compare`, and with this change a contents
read). An API outage or a rate limit fails the required job on every PR in the repo, and the
README has no runbook for that.

## What Changes

- **The copy verifies itself online.** With `--pin-on-main`, after every shape matched and the
  pin is on `.github` `main`, the check fetches
  `.github/scripts/cascade/wiring-check.sh` at the pinned SHA (`gh api` contents, raw) and
  compares it byte for byte with the running script; any difference, or a failed fetch, exits 1.
  Offline, the success output gains a second line saying the copy was not compared.
- **`extra-references` config key.** An optional list of `{file, kind}` maps declares more
  pinned `.github` references a repo carries. The only kind is `resolver` (an `actions/checkout`
  of `open-platform-model/.github`). Each declared reference must carry the one pinned SHA and
  the pin comment like the fixed ones. The key is validated strictly (exact item keys, a workflow
  file name, a known kind).
- **Every resolver checkout passes no credentials.** Each `.github` checkout, fixed or declared,
  must be `actions/checkout` at a full SHA with exactly `repository`, `ref`, `path` and
  `persist-credentials: false`, so no token or SSH key reaches it.
- **README.** The wiring-check section documents the copy comparison, `extra-references` (and
  opm-operator's value) and a runbook for a failed API call; "Keeping the copy in sync" and the
  pin-bump steps say what CI now checks.

Not in this change: moving any repo's pin, editing any repo's copy or config (the operator's
`extra-references` entry rides its pin-bump PR), rulesets or repo settings.

## Capabilities

### Modified Capabilities

- `cascade-wiring-check`: the canonical check, its config, the pin-on-main step and the
  byte-identical copy requirement.

## Impact

- Script: `.github/scripts/cascade/wiring-check.sh`; tests in
  `.github/scripts/cascade/wiring/test/cases/wiringcheck.sh` and a helper in
  `.github/scripts/cascade/wiring/test/lib.sh`; `README.md`.
- Callers: core, catalog_opm, library, opm-operator and cli run a copy. Nothing changes for them
  until each moves its pin; at that bump the copy is replaced (as today) and opm-operator adds
  `extra-references: [{file: module-deps.yml, kind: resolver}]` to its config.
- The required CI step makes one more API request per run (a contents read with the job's
  `GITHUB_TOKEN`, which `contents: read` on a public repo allows).
- Depends on: `bound-cascade-publish` (merged, 7b9ad1b). Later: the wave-2 pin bumps.

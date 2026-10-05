## Why

The README's rollout steps ("Pinning and bumps", step 2) put one receiver's dry-run checks before
every other pin bump, and kept the other repos on the old pin until one canary's first live run
whenever a change touched `cascade-publish` or `cascade-notify`. The `6938f8e` rollout moved all
five repos together and ran the dry-run checks afterwards (catalog_opm and library), opm-operator
last (opm-operator PR 241). Its range, `.github` PRs 14 and 15, changed the resolver's
`lib/common.sh` and `lib/release.sh`, which `cascade-publish` runs through `cascade-resolve.sh`,
and no file `cascade-notify` runs; every receiver is dry-run (`CASCADE_DRY_RUN` is not `false`
anywhere), so nothing published.
The owner accepted this and asked for it to be written down (security pass, owner decision 37).
The supervisor's ruling on decision 37 sets the rule. A change touches an action when it changes
any file that action runs: its `action.yml` and every script it calls or sources, directly or
through another script.

- A change that touches neither action has no canary: all five repos may move together, with
  the dry-run checks in one receiver after its merge.
- A change that touches `cascade-publish` but not `cascade-notify`: while every receiver is
  dry-run, all five may move together; the Phase 4 canary has the first live publish, and the
  other receivers stay dry until it succeeds. Once any receiver is live, one live receiver is the
  canary and every other receiver stays on the old pin until its first live publish on the new
  pin succeeds.
- A change that touches `cascade-notify` but not `cascade-publish`: a dry run does not help,
  because notify has no dry run, so the old rule holds unchanged: one upstream (core or a
  receiver) moves first, and the others stay on the old pin until its first live notify on the
  new pin succeeds. No `CASCADE_NOTIFY=off` steps.
- A change that touches both actions follows both rules: once any receiver is live, the canary
  is a live receiver, and the others wait for its first live publish and its first live notify.

Other README text went stale in the same pass:

- The wiring-check config table lists three `publish-workflows` for opm-operator; its config on
  `main` (from PR 241) lists seven and declares `extra-references` for `module-deps.yml`.
- The `mention-guard` section says the release repos switch to a `PR_TITLE` title and a `BLANK`
  body "once the owner applies" the settings. They are applied, and docs-kit, modules and
  opm-portal squash the same way (owner decision 35).
- "Keeping the copy in sync" leans on CODEOWNERS review and the `main` ruleset to stop a
  deliberate edit of the copy. During the beta the `main` rulesets require a pull request but no
  approval (owner decision 36), so nothing enforces that review.
- The residual-risk list says opm-operator's `module-deps.yml` gets none of the publish bounds.
  Since opm-operator PR 225 its publish job runs in the `release` Environment and accepts only
  plain files under `modules/opm_operator/`; the title, the body and the tools are still unbounded.
- "Pinning and bumps" cites opm-operator's `sha_pinning_required`; all nine releasing repos and
  this one now have it (owner decision 30).

## What Changes

- **README "Pinning and bumps".** Step 2 defines what touching an action means and states the
  rule above, one bullet per case, and step 4's ordering note points at it. The tag-ledger
  scope names the six scanned repos of nine.
- **README wiring-check config table.** opm-operator's row lists its seven `publish-workflows`.
- **README stale lines** listed under Why, and three entries added to "What stays open": no
  required review during the beta, one `opm-cascade` key shared by five repos (owner decision
  31), and the cli mirror left behind by cli PR 307 (issue 18).
- **Spec.** `cascade-workflows` gains a requirement for what the README's rollout order says.

Docs only: no script, workflow, test or setting changes. Depends on nothing. The workspace
`RELEASING.md` ("Moving the cascade pin") needs the same rule; that edit is a workspace PR,
not part of this change.

## Capabilities

### Modified Capabilities

- `cascade-workflows`: adds the documented rollout order for a new pin.

## Impact

- `README.md` only. No caller repo changes; no pin moves.

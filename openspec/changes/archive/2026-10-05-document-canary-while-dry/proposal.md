## Why

The README's rollout steps ("Pinning and bumps", step 2) say that when a `.github` change touches
`cascade-publish` or `cascade-notify`, the other receivers stay on the old pin until one canary's
first live publish has succeeded. The `6938f8e` rollout did not follow that: every receiver is
dry-run (`CASCADE_DRY_RUN` is not `false` anywhere), nothing publishes, so all five repos moved to
`6938f8e` together, opm-operator last (opm-operator PR 241). The owner accepted this and asked for
it to be written down (security pass, owner decision 37): while every receiver is dry-run, all
receivers may move to a new pin together, even when the change touches `cascade-publish` or
`cascade-notify`; the first live publish (or notify) after such a change happens in one repo only
(the Phase 4 canary), and the others stay dry until it succeeds.

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
- "Pinning and bumps" cites opm-operator's `sha_pinning_required`; all ten releasing repos and
  this one now have it (owner decision 30).

## What Changes

- **README "Pinning and bumps".** Step 2 states the rule of owner decision 37: a dry-run check in
  one receiver first; while every receiver is dry-run, all may then move together whatever the
  diff touches; the first live publish or notify after a `cascade-publish` or `cascade-notify`
  change happens in one repo (the Phase 4 canary) while the others stay dry until it succeeds.
  Step 4's ordering note follows.
- **README wiring-check config table.** opm-operator's row lists its seven `publish-workflows`.
- **README stale lines** listed under Why, and two accepted risks added to "What stays open":
  no required review during the beta, and one `opm-cascade` key shared by five repos (owner
  decision 31).
- **Spec.** `cascade-workflows` gains a requirement for what the README's rollout order says.

Docs only: no script, workflow, test or setting changes. Depends on nothing. The workspace
`RELEASING.md` ("Rolling out a .github change") needs the same rule; that edit is a workspace PR,
not part of this change.

## Capabilities

### Modified Capabilities

- `cascade-workflows`: adds the documented rollout order for a new pin.

## Impact

- `README.md` only. No caller repo changes; no pin moves.

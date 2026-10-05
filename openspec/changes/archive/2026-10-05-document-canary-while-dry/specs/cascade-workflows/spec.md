## ADDED Requirements

### Requirement: Rollout order for a new pin

The README's "Pinning and bumps" steps SHALL state the order in which the product repos move to a
new `.github` SHA (owner decision 37). One receiver SHALL take the new pin as a dry run and pass
the dry-run checks. A change that touches neither `cascade-publish` nor `cascade-notify` has no
canary: all five repos MAY move together, live or dry, with the dry-run checks in one receiver
after its pin PR has merged. For a change that touches `cascade-publish` and not `cascade-notify`:
while every receiver is dry-run (`CASCADE_DRY_RUN` is not `false`, in any letter case, in any
receiver), all five repos MAY move together, the canary is the first receiver set live (the
Phase 4 canary), and every other receiver SHALL stay dry until the canary's first live publish
run on the new pin has succeeded; once any receiver is live, the canary SHALL be one live
receiver, and every other receiver, live or dry, SHALL stay on the old pin until that run has
succeeded. For a change that touches `cascade-notify`, which has no dry run, one repo SHALL move
first as the canary and every other repo SHALL stay on the old pin until the canary's first live
notify run on the new pin has succeeded, whether every receiver is dry or not. The README SHALL
NOT offer turning notify off with `CASCADE_NOTIFY` as a rollout step.

#### Scenario: All receivers dry, publish changed

- **WHEN** a `.github` change touches `cascade-publish` but not `cascade-notify`, and every receiver has `CASCADE_DRY_RUN` unset or `true`
- **THEN** the README allows all five repos to move to the new pin together, with the dry-run checks in one receiver after its merge, and keeps every receiver but the Phase 4 canary dry until the canary's first live publish on the new pin has succeeded

#### Scenario: One receiver already live, publish changed

- **WHEN** a `.github` change touches `cascade-publish` but not `cascade-notify`, and one receiver has `CASCADE_DRY_RUN` set to `false`
- **THEN** the README makes one live receiver the canary and keeps every other receiver, live or dry, on its old pin until the canary's first live publish run on the new pin has succeeded

#### Scenario: Notify changed

- **WHEN** a `.github` change touches `cascade-notify`, whether every receiver is dry or not
- **THEN** the README moves one repo first as the canary and keeps every other repo on its old pin until the canary's first live notify run on the new pin has succeeded, and it does not ask any repo to set `CASCADE_NOTIFY` to `off`

#### Scenario: Change touches neither action

- **WHEN** a `.github` change touches only `.github/scripts/cascade/wiring-check.sh`, which neither action runs
- **THEN** the README lets all five repos move to the new pin together, live or dry, with the dry-run checks in one receiver after its merge

## ADDED Requirements

### Requirement: Rollout order for a new pin

The README's "Pinning and bumps" steps SHALL state the order in which the product repos move to a
new `.github` SHA (owner decision 37). One receiver SHALL take the new pin as a dry run and pass
the dry-run checks. The README SHALL define that a change touches an action when it changes any
file that action runs: its `action.yml` and every script it calls or sources, directly or through
another script, so a change to the resolver or its `lib/` touches `cascade-publish` and a change
to `wiring/lib.sh` touches both actions. A change that touches neither `cascade-publish` nor
`cascade-notify` has no canary: all five repos MAY move together, live or dry, with the dry-run
checks in one receiver after its pin PR has merged. For a change that touches `cascade-publish`
and not `cascade-notify`: while every receiver is dry-run (`CASCADE_DRY_RUN` is not `false`, in
any letter case, in any receiver), all five repos MAY move together, the canary is the Phase 4
canary (the first receiver whose `CASCADE_DRY_RUN` is set to `false`), and every other receiver
SHALL stay dry until the canary's first live publish run on the new pin has succeeded; once any
receiver is live, the canary SHALL be one live receiver, and every other receiver, live or dry,
SHALL stay on the old pin until that run has succeeded. For a change that touches
`cascade-notify` and not `cascade-publish`, which has no dry run, one upstream (core or a
receiver) SHALL move first as the canary and every other repo SHALL stay on the old pin until the
canary's first live notify run on the new pin has succeeded, whether every receiver is dry or
not. A change that touches both actions SHALL follow the notify rule and the publish rule
together: once any receiver is live, the canary SHALL be a live receiver, and no other repo SHALL
move until both its first live publish run and its first live notify run on the new pin have
succeeded. The README SHALL NOT offer turning notify off with `CASCADE_NOTIFY` as a rollout step.

#### Scenario: All receivers dry, publish changed

- **WHEN** a `.github` change touches `cascade-publish` but not `cascade-notify`, and every receiver has `CASCADE_DRY_RUN` unset or `true`
- **THEN** the README allows all five repos to move to the new pin together, with the dry-run checks in one receiver after its merge, and keeps every receiver but the Phase 4 canary dry until the canary's first live publish on the new pin has succeeded

#### Scenario: One receiver already live, publish changed

- **WHEN** a `.github` change touches `cascade-publish` but not `cascade-notify`, and one receiver has `CASCADE_DRY_RUN` set to `false`
- **THEN** the README makes one live receiver the canary and keeps every other receiver, live or dry, on its old pin until the canary's first live publish run on the new pin has succeeded

#### Scenario: Resolver library changed

- **WHEN** a `.github` change touches only `.github/scripts/cascade/lib/common.sh`, which `cascade-publish` runs through `cascade-resolve.sh`
- **THEN** the README counts it as touching `cascade-publish`, not as touching neither action

#### Scenario: Notify changed

- **WHEN** a `.github` change touches `cascade-notify` but not `cascade-publish`, whether every receiver is dry or not
- **THEN** the README moves one upstream (core or a receiver) first as the canary and keeps every other repo on its old pin until the canary's first live notify run on the new pin has succeeded, and it does not ask any repo to set `CASCADE_NOTIFY` to `off`

#### Scenario: Both actions changed, one receiver live

- **WHEN** a `.github` change touches both `cascade-publish` and `cascade-notify`, and one receiver has `CASCADE_DRY_RUN` set to `false`
- **THEN** the README makes a live receiver the canary and keeps every other repo on its old pin until both the canary's first live publish run and its first live notify run on the new pin have succeeded

#### Scenario: Change touches neither action

- **WHEN** a `.github` change touches only `.github/scripts/cascade/wiring-check.sh`, which neither action runs
- **THEN** the README lets all five repos move to the new pin together, live or dry, with the dry-run checks in one receiver after its merge

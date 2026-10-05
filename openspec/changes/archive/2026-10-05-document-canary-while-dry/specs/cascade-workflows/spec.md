## ADDED Requirements

### Requirement: Rollout order for a new pin

The README's "Pinning and bumps" steps SHALL state the order in which the product repos move to a
new `.github` SHA (owner decision 37). One receiver SHALL first take the new pin as a dry run and
pass the dry-run checks. Each rollout of a change that touches `cascade-publish` or
`cascade-notify` SHALL have one canary, the one repo where the first live run of the changed
action happens; a change that touches neither has none, and every repo MAY move after the dry-run
checks, live or dry. For `cascade-publish`: while every receiver is dry-run (`CASCADE_DRY_RUN` is
not `false`, in any letter case, in any receiver), the other repos MAY move to the new pin
together, the canary is the first receiver set live (Phase 4), and every other receiver SHALL stay
dry until the canary's first live publish run on the new pin has succeeded; once a receiver is
live, the canary SHALL be one live receiver, and every other receiver, live or dry, SHALL stay on
the old pin until that run has succeeded. For `cascade-notify`, which has no dry run, the README
SHALL name one upstream as the notify canary and require every other upstream to set
`CASCADE_NOTIFY` to `off` before its pin PR merges and until the canary's first notify on the new
pin has succeeded; it SHALL NOT offer holding back releases as the alternative.

#### Scenario: All receivers dry, publish changed

- **WHEN** a `.github` change touches `cascade-publish` and every receiver has `CASCADE_DRY_RUN` unset or `true`
- **THEN** the README allows all five repos to move to the new pin after one receiver's dry-run checks pass, and keeps every receiver but the Phase 4 canary dry until the canary's first live publish on it has succeeded

#### Scenario: One receiver already live

- **WHEN** a `.github` change touches `cascade-publish` and one receiver has `CASCADE_DRY_RUN` set to `false`
- **THEN** the README makes one live receiver the canary and keeps every other receiver, live or dry, on its old pin until the canary's first live publish run on the new pin has succeeded

#### Scenario: Notify changed

- **WHEN** a `.github` change touches `cascade-notify`
- **THEN** the README names one upstream as the notify canary and has every other upstream set `CASCADE_NOTIFY` to `off` before moving, until the canary's first notify on the new pin has succeeded

#### Scenario: Change touches neither action

- **WHEN** a `.github` change touches only the resolver and `cascade-receive.yml`
- **THEN** the README lets every repo move to the new pin after one receiver's dry-run checks pass, live or dry

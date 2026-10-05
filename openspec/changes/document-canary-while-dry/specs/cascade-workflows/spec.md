## ADDED Requirements

### Requirement: Rollout order for a new pin

The README's "Pinning and bumps" steps SHALL state the order in which the product repos move to a
new `.github` SHA (owner decision 37). One receiver SHALL first take the new pin as a dry run and
pass the dry-run checks. While every receiver is dry-run (`CASCADE_DRY_RUN` is not `false`, in any
letter case, in any receiver), the other repos MAY then move to the new pin together, whatever the
`.github` diff touches. When the diff touches `cascade-publish` or `cascade-notify`, the first live
publish (or notify) run on that pin SHALL happen in one repo only, the canary, and every other
repo SHALL stay dry until that run has succeeded. Notify has no dry run, so the README SHALL say
that for notify "dry" means an upstream makes no release, or has `CASCADE_NOTIFY=off`, until then.
A receiver that is already live when such a change arrives SHALL stay on the old pin until the
canary's first live run has succeeded.

#### Scenario: All receivers dry, publish changed

- **WHEN** a `.github` change touches `cascade-publish` and every receiver has `CASCADE_DRY_RUN` unset or `true`
- **THEN** the README allows all five repos to move to the new pin after one receiver's dry-run checks pass, and requires the first live publish on it to happen in one repo while the others stay dry

#### Scenario: One receiver already live

- **WHEN** a `.github` change touches `cascade-notify` and one receiver has `CASCADE_DRY_RUN` set to `false`
- **THEN** the README keeps that receiver on its old pin until the canary's first live notify run on the new pin has succeeded

#### Scenario: Change touches neither action

- **WHEN** a `.github` change touches only the resolver and `cascade-receive.yml`
- **THEN** the README lets every repo move to the new pin after one receiver's dry-run checks pass, live or dry

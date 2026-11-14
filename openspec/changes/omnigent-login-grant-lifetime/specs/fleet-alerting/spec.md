## ADDED Requirements

### Requirement: An Omnigent worker's expiring login reaches a person 14 days ahead

When the earliest login grant of an owner will expire in less than 14 days, a person SHALL be told by an alert naming that owner's alias, before any Omnigent worker of that owner stops for an expired login grant.
A login grant SHALL stay usable for 90 days after the owner signs in.

**Discharged by**: `fleet-alerting-interface` requirements `The Omnigent server runs with a 90-day login grant lifetime`, `The collector reads each owner's earliest login grant expiry as a column-limited role` and `OmnigentLoginGrantExpiring warns 14 days before an owner's earliest expiry`, resting on world assumptions `A105 — omnigent refuses a login grant's refresh once its age reaches a lifetime fixed at server start, and later purges it` and `A106 — A login grant is revocable only by presenting its own token`; `checks.x86_64-linux.fleet-alert`'s `promtoolRehearsal` with its mutant, and the series read after magnetite's deploy, discharge it.

#### Scenario: An owner's earliest grant enters its last 14 days

- **WHEN** an owner's earliest login grant has less than 14 days left for 15 minutes
- **THEN** one alert titled `[FIRING] OmnigentLoginGrantExpiring magnetite` naming that owner's alias is posted, which the build-time rule test confirms

#### Scenario: Grants with more than 14 days left

- **WHEN** every owner's earliest login grant has more than 14 days left
- **THEN** no alert is posted for this rule, which the build-time rule test confirms

#### Scenario: The expiry stops being reported

- **WHEN** the expiry signal returns no series for 30 minutes while magnetite reports its memory signal
- **THEN** one alert titled `[FIRING] RuleSignalMissing` naming `OmnigentLoginGrantExpiring` is posted, under `A missing signal is itself reported`

#### Scenario: An earlier login grant is still usable

- **WHEN** an owner signed in again and the owner's earlier login grant has not yet reached its 90 days
- **THEN** the alert follows the earlier login grant and resolves only once that grant is removed at its 90 days, so a person is told too early rather than too late

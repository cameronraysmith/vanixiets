## MODIFIED Requirements

### Requirement: The telemetry store's own failures reach a person

A failure of the telemetry store, of the unit that sets up its databases, of its hourly envelope regulator, or of any unit that applies or confirms a disk-share setting on magnetite SHALL produce a failure notice naming the failed unit and magnetite on the fleet's notification service.

**Discharged by**: `telemetry-store-interface` requirement `Failure notices are posted to one topic`, which posts with the notification service's credential, resting on world assumptions `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path` and `A37 — ntfy provisions users, access entries and tokens from its declaration, and refuses to start on an undeclared user`; the evaluation-time collector regulator's failure-wiring case with its mutants discharges that each of these units, and any unit of these kinds added later, hands its failure to the notifier, `checks.<system>.package-ntfy-send-test-token-transport` and the token-wiring clause of `checks.x86_64-linux.fleet-alert` with its mutant discharge that the notifier presents the credential, and the operator's deliberately failed envelope regulator after the access entries are in force discharges delivery.

#### Scenario: The hourly envelope regulator is made to fail at first activation

- **WHEN** at magnetite's first activation the hourly envelope regulator's memory threshold is set below the telemetry store's observed memory and the regulator runs
- **THEN** the regulator fails, a failure notice naming it and magnetite appears on the fleet's notification service, and the operator records that notice

#### Scenario: A unit fails after publishing to the fleet topics requires the credential

- **WHEN** once the notification service refuses anonymous publishing to the fleet topics, the hourly envelope regulator is made to fail on magnetite
- **THEN** a failure notice naming it and magnetite appears on the fleet's notification service, posted with the credential, and the operator records that notice

#### Scenario: The notification service is unreachable

- **WHEN** one of these units fails while the fleet's notification service is down or unreachable from magnetite
- **THEN** no failure notice reaches a person, which this requirement does not cover and world assumption `A33` records

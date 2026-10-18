## MODIFIED Requirements

### Requirement: A failed collection or store job notifies a person

A failure of the collector, of the telemetry store, of the unit that sets up its databases, of its hourly envelope regulator, or of any unit that applies or confirms a disk-share setting on magnetite SHALL produce, from magnetite, a failure notice on the fleet's notification service naming the failed unit and magnetite.

**Discharged by**: `telemetry-store-interface` requirement `Failure notices are posted to one topic`, which posts with the notification service's credential, resting on world assumptions `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path` and `A37 — ntfy provisions users, access entries and tokens from its declaration, and refuses to start on an undeclared user`; the evaluation-time collector regulator's failure-wiring case with its mutants discharges that every unit of the kinds named here, present or added later, hands its failure to the notifier, `checks.<system>.package-ntfy-send-test-token-transport` and the token-wiring clause of `checks.x86_64-linux.fleet-alert` with its mutant discharge that the notifier presents the credential, and the operator's deliberately failed envelope regulator after the access entries are in force discharges delivery from magnetite.

#### Scenario: A watched unit fails at first activation

- **WHEN** at magnetite's first activation the hourly envelope regulator is made to fail
- **THEN** a failure notice naming that unit and magnetite appears on the fleet's notification service, and the operator records it

#### Scenario: A named unit loses its failure handler

- **WHEN** magnetite's configuration is changed so that the collector, or any other unit this requirement names, no longer hands its failure to the notifier
- **THEN** the evaluation-time collector regulator fails before any activation, which its mutant shows, so a broken collection is reported rather than noticed as an absence of series

#### Scenario: A new disk-share unit is added

- **WHEN** magnetite's configuration gains a unit that applies or confirms a disk-share setting and does not list it for notification
- **THEN** the evaluation-time collector regulator fails before any activation, which its mutant shows

#### Scenario: A unit fails after publishing to the fleet topics requires the credential

- **WHEN** once the notification service refuses anonymous publishing to the fleet topics, a unit this requirement names fails on magnetite
- **THEN** a failure notice naming that unit and magnetite appears on the fleet's notification service, posted with the credential, and the operator records it

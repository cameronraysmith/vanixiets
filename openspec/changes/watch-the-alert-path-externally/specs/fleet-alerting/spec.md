## ADDED Requirements

### Requirement: An outage of the alert path reaches the operator by email from outside the fleet

When cinnabar, its notification service, the path by which the evaluator's heartbeat reaches that service, or the dead-man stops working, the operator SHALL receive an email from the watch service within 15 minutes of the dead-man's last ping, and a second email once the dead-man pings again.

**Discharged by**: `fleet-alerting-interface` requirements `The dead-man pings the watch service only after a passing run`, `The ping URL travels only as a credential read on stdin` and `The rule check runs promtool, fixture mutants and a property test`, resting on world assumptions `A53 — healthchecks.io counts a ping by its URL and emails when pings stop for longer than a check's period and grace`, `A54 — healthchecks.io runs outside the fleet, on Hetzner in Germany` and `A55 — The operator's mailbox is reached without the fleet`; regulator R9.6 and the operator's recorded stops of the notification service and of the evaluator at acceptance discharge it.

#### Scenario: The dead-man pings only when the path works

- **WHEN** the dead-man finishes a run
- **THEN** it pings the watch service only if it found the notification service refusing anonymous heartbeats, a heartbeat from the evaluator in the last 10 minutes, and every alert it raised posted

#### Scenario: The notification service is stopped

- **WHEN** at acceptance the operator stops the notification service on cinnabar and, after the first email arrives, starts it again
- **THEN** an email from the watch service reporting the pings late arrives within 15 minutes of the dead-man's last accepted ping, a second reporting them back arrives after the restart, and the operator records both times with the last ping's time

#### Scenario: The evaluator falls silent

- **WHEN** at acceptance the operator stops the evaluator on magnetite for 20 minutes, then starts it again
- **THEN** an alert titled `[FIRING] AlertEvaluatorSilent` arrives through the notification service and an email from the watch service arrives, and after the start an alert titled `[RESOLVED] AlertEvaluatorSilent` and the second email arrive, and the operator records all four

#### Scenario: The path works for a day

- **WHEN** the path works for the 24 hours after deployment
- **THEN** no email from the watch service arrives, and the operator records the pings the watch service lists for that period

#### Scenario: The watch service fails together with the fleet

- **WHEN** an outage takes down the watch service at the same time as cinnabar
- **THEN** no email arrives, which the operator accepted on 2026-11-01, and the weekly test alert's absence on a Monday remains the only report

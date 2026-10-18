## ADDED Requirements

### Requirement: Each known failure class on a host reaches a person as an alert

A person SHALL be told by an alert naming the alert rule and the host when, on a host whose series reach the telemetry store, memory pressure holds, the kernel kills a process for memory, a storage pool is not online, a unit restarts more than 5 times in 15 minutes, a unit the notifier does not report has failed, or a source the collector reads stops answering.
An alert for memory pressure or an out-of-memory kill SHALL name the three processes holding the most memory on that host.

**Discharged by**: `fleet-alerting-interface` requirements `The evaluator queries the fleet database as the regulators' store account`, `Alert rules are rendered from one Nix source to the evaluator and to promtool`, `Alerts are posted to fleet-alerts with a title and a severity priority` and `ntfy counts each mesh client as its own visitor`, resting on world assumptions `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path`, `A40 — ntfy rate-limits a client by its address masked to a prefix, taken from a trusted proxy's forwarding header` and `A41 — caddy reaches ntfy from ::1 and forwards the mesh client's address`; `checks.x86_64-linux.fleet-alert` with its fixture sequence and `promtool` pass, and the deploy-time watch of each rule's signal that `A missing signal is itself reported` states, discharge it.

#### Scenario: A storage pool degrades

- **WHEN** the telemetry store holds a series showing magnetite's `zroot` pool degraded on every pass of the evaluator for one minute
- **THEN** one alert titled `[FIRING] ZfsPoolUnhealthy magnetite` is posted, which the build-time alert regulator confirms by replaying that series

#### Scenario: A unit the notifier reports fails

- **WHEN** a unit the notifier reports, such as the telemetry store, fails on magnetite
- **THEN** the person receives the notifier's failure notice and no alert for the same failure, which the build-time alert regulator confirms by replaying a failed state for a unit the notifier reports

#### Scenario: Memory pressure is reported with the processes behind it

- **WHEN** memory pressure holds on magnetite for 5 minutes
- **THEN** the alert names magnetite's three processes holding the most memory, the memory its storage pool holds as cache and its compressed swap in use, which the build-time alert regulator confirms from replayed results

#### Scenario: The storage pool's cache is counted as available memory

- **WHEN** the rule for memory pressure is first deployed on magnetite
- **THEN** the operator confirms on magnetite that the kernel's available-memory figure excludes the storage pool's cache, and records the observation, because the rule counts that cache above its minimum as available

### Requirement: An alert instance reaches a person once when it fires and at most once when it resolves

An alert instance SHALL produce one alert when its condition has held for its alert rule's holding time, and at most one when its condition has then been absent for 5 minutes.
While it keeps firing, a critical instance SHALL be repeated once every 24 hours, and a warning instance SHALL NOT be repeated.
An info instance SHALL produce no alert on resolving.

**Discharged by**: `fleet-alerting-interface` requirements `Alert instance state is kept in one state file and posted once per transition` and `Alerts are posted to fleet-alerts with a title and a severity priority`; `checks.x86_64-linux.fleet-alert`'s fixture sequence, its no-state-write and zero-holding-time mutants, and its property test against the reference model's re-post cadence discharge it.

#### Scenario: A condition keeps holding

- **WHEN** a warning instance has fired and its condition still holds on the next pass of the evaluator and every pass after
- **THEN** no further alert is posted for it, which the build-time alert regulator's no-state-write mutant shows it can detect

#### Scenario: A condition holds for less than its holding time

- **WHEN** a condition with a 5-minute holding time holds on one pass of the evaluator and is absent on the next
- **THEN** no alert is posted, which the build-time alert regulator's zero-holding-time mutant shows it can detect

#### Scenario: A critical instance stays firing for a day

- **WHEN** a critical instance has been firing for 24 hours
- **THEN** it is posted once more, and not again until another 24 hours pass, which the build-time alert regulator confirms against its reference model

#### Scenario: A condition clears

- **WHEN** a firing warning or critical instance's condition has been absent for 5 minutes
- **THEN** one alert titled `[RESOLVED]` with that rule and host is posted, and none for an info instance

### Requirement: An unreachable telemetry store or a silent host freezes alerts

While the telemetry store does not answer the evaluator, no alert instance SHALL resolve or be repeated, and a person SHALL be told once the store has failed to answer for 3 minutes.
While a host reports no memory signal, no alert instance for that host SHALL resolve or be repeated, and each SHALL resume once the host reports again.

**Discharged by**: `fleet-alerting-interface` requirement `Store errors and silent hosts freeze instance state`; `checks.x86_64-linux.fleet-alert`'s store-error and silent-host fixture legs, its store-freeze and host-freeze mutants, and its property test against the reference model's store and host freezes discharge it.

#### Scenario: The telemetry store stops answering

- **WHEN** the telemetry store fails to answer the evaluator for 3 minutes while other alert instances are firing
- **THEN** one alert titled `[FIRING] StoreQueryFailing` is posted and no other instance resolves, which the build-time alert regulator's store-freeze mutant shows it can detect

#### Scenario: stibnite falls silent with an alert firing

- **WHEN** stibnite stops reporting its memory signal while one of its alert instances is firing, and later reports again with the condition still holding
- **THEN** no resolved alert and no second firing alert is posted for that instance, which the build-time alert regulator's host-freeze mutant shows it can detect

### Requirement: A missing signal is itself reported

When a signal an alert rule reads has had no series for 30 minutes while at least one host expected to emit it reports its memory signal, a person SHALL be told by an alert naming that rule.
The same gap while every expected host is silent SHALL raise nothing.

**Discharged by**: `fleet-alerting-interface` requirement `Each rule's presence selector is watched`; `checks.x86_64-linux.fleet-alert`'s signal-gap fixture legs, and the operator's observation within 30 minutes of the evaluator's first run on magnetite that no `RuleSignalMissing` alert has fired, discharge it.

#### Scenario: A signal is renamed

- **WHEN** a rule's signal returns no series for 30 minutes while magnetite reports its memory signal
- **THEN** one alert titled `[FIRING] RuleSignalMissing` naming that rule is posted, which the build-time alert regulator confirms

#### Scenario: Every expected host is silent

- **WHEN** a rule's signal returns no series for 30 minutes while no host expected to emit it reports its memory signal
- **THEN** no alert is posted for that rule, which the build-time alert regulator confirms

#### Scenario: The rules are first deployed

- **WHEN** 30 minutes have passed since the evaluator first ran on magnetite, and the operator has also run it once by hand with one rule's signal misspelt
- **THEN** the hand run reports the misspelt signal missing, no scheduled run reports any signal missing, and the operator records both, because the build-time alert regulator replays recorded results and cannot see the signal names the telemetry store actually holds

### Requirement: A silent evaluator is reported from another host

When no heartbeat has reached the notification service for 10 minutes, a person SHALL be told within the next 5 minutes by an alert raised on cinnabar, and told once more when heartbeats resume.

**Discharged by**: `fleet-alerting-interface` requirements `Each completed evaluator run posts a heartbeat` and `The dead-man on cinnabar polls the heartbeat topic after an anonymous-publish probe`, resting on world assumptions `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path` and `A42 — ntfy keeps a topic's messages for 12 hours and returns a recent window to a poll`; regulator R9.3's dead-man and its acceptance negative control discharge it.

#### Scenario: The evaluator is stopped

- **WHEN** at acceptance the operator stops the evaluator on magnetite
- **THEN** an alert titled `[FIRING] AlertEvaluatorSilent` arrives within 15 minutes, and after the evaluator is started again one titled `[RESOLVED] AlertEvaluatorSilent` arrives, and the operator records both

### Requirement: Only the alerting credential publishes alerts and heartbeats

The notification service SHALL accept an alert or a heartbeat only from a publisher presenting the fleet's alerting credential, and SHALL keep accepting anonymous publishing on every other topic.

**Discharged by**: `fleet-alerting-interface` requirements `ntfy grants the fleet topics to alerter through declarative provisioning` and `The alerter token travels only as a file`, resting on world assumptions `A37 — ntfy provisions users, access entries and tokens from its declaration, and refuses to start on an undeclared user` and `A38 — One ntfy access entry decides a request, a named user's before the anonymous one's`; `checks.x86_64-linux.ntfy-provisioning` and regulator R9.4's anonymous-publish probe, with its acceptance negative control, discharge it.

#### Scenario: An anonymous client posts a heartbeat

- **WHEN** a client without the credential publishes to the heartbeat topic
- **THEN** the notification service refuses it, and the dead-man's probe, which makes that publish every 5 minutes, fails and reports itself through the notifier if it is ever accepted

#### Scenario: The anonymous read-only entry is removed

- **WHEN** at acceptance the operator removes the entry that makes the fleet topics read-only for anonymous clients
- **THEN** the dead-man's probe fails on its next run and a failure notice for it reaches a person, and the operator records both

#### Scenario: A host's own topic stays open

- **WHEN** after the access entries are in force a client without the credential publishes to a topic named after a host
- **THEN** the notification service accepts it, and the operator records the accepted publish at acceptance

### Requirement: Alert volume stays within the alert budget

The alert budget SHALL be 10 firing alerts and failure notices across the fleet in any rolling 24 hours, of which at most 3 from stibnite and 3 from pyrite, info alerts excluded.
When the fleet exceeds it, a person SHALL be told once per 24 hours by an alert naming the alert rule and host that fired most, and no alert or failure notice SHALL be withheld because of it.

**Discharged by**: `fleet-alerting-interface` requirement `The alert budget is counted over the evaluator's state and the notifier's FAILED log`; regulator R9.1 and `checks.x86_64-linux.fleet-alert`'s two budget legs discharge it.

#### Scenario: Eleven instances fire in one day

- **WHEN** the build-time alert regulator fires 11 alert instances within 24 hours
- **THEN** exactly one `AlertBudgetExceeded` alert is posted and every one of the 11 firing alerts is posted

#### Scenario: Four instances fire on stibnite

- **WHEN** the build-time alert regulator fires 4 alert instances on stibnite within 24 hours
- **THEN** exactly one `AlertBudgetExceeded` alert is posted

### Requirement: The evaluator stays inside its envelope on magnetite

The evaluator SHALL draw at most 64 MiB of magnetite's memory, and each pass of the evaluator SHALL finish, or be stopped, within 50 seconds, so that no pass overlaps the next and the evaluator cannot add to a memory incident on magnetite.

**Discharged by**: `fleet-alerting-interface` requirement `The evaluator's memory ceiling and start timeout are asserted`, resting on world assumption `A31 — magnetite's memory is finite and shared with the build service's evaluation work`; regulator R9.5, the `fleet-alert` module's assertion with its mutant, discharges it.

#### Scenario: magnetite's configuration drops the evaluator's memory ceiling

- **WHEN** magnetite's configuration no longer gives the evaluator its memory ceiling or its 50-second limit
- **THEN** magnetite's evaluation fails before any activation, which the assertion's mutant shows

### Requirement: A weekly test alert proves the path to a person

Each Monday between 09:00 and 09:05 in the `America/New_York` time zone, a person SHALL be told by one info alert counting the hosts that report their memory signal, so that its absence on a Monday shows that the path from the telemetry store to the person is broken.

**Discharged by**: `fleet-alerting-interface` requirement `The weekly test rule is evaluated in one window each Monday`, resting on world assumption `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path`; regulator R9.3's weekly test, whose absence the operator observes as recorded human judgment, `checks.x86_64-linux.fleet-alert`'s window legs, and the operator's record of the first Monday's alert on a subscribed device discharge it.

#### Scenario: The first Monday after deployment

- **WHEN** the first Monday 09:00 to 09:05 in `America/New_York` after the evaluator is deployed passes
- **THEN** one alert titled `[FIRING] WeeklyPipelineTest` arrives on each device the operator subscribed, and the operator records it

#### Scenario: Any other time

- **WHEN** the evaluator runs outside that window
- **THEN** the weekly test rule raises nothing, which the build-time alert regulator confirms on either side of the window

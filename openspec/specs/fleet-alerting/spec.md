# fleet-alerting Specification

## Purpose

This capability (stratum: `behavioral`) states what the fleet requires of alerting: that each known failure class S1's series cover reaches a person as one FIRING and at most one RESOLVED per instance, with critical alerts repeated daily; that an unreachable store or a silent host freezes alerts rather than resolving or refiring them; that a renamed or missing signal is itself reported; that a silent evaluator is reported from another host; that only the alerting credential may publish to the alerting topics; that alert volume stays within a daily budget; that the evaluator stays inside a resource envelope; and that a weekly message proves the path.

## Requirements

### Requirement: Each known failure class on a host reaches a person as an alert

A person SHALL be told by an alert naming the alert rule and the host when, on a host that reports to the telemetry store, memory pressure holds, the kernel kills a process for memory, a storage pool is not online, a unit restarts more than 5 times in 15 minutes, a unit no notifier reports has failed, a source the collector reads stops answering, a file system is nearly full, or a laptop's disk is failing or worn.
Memory alerts SHALL name the three processes holding the most memory on that host.

**Discharged by**: `fleet-alerting-interface` requirements `The evaluator queries each rule's database as the regulators' store account`, `Alert rules are rendered from one Nix source to the evaluator and to promtool`, `Alerts are posted to fleet-alerts with a title and a severity priority` and `ntfy counts each mesh client as its own visitor`, resting on world assumptions `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path`, `A40 — ntfy rate-limits a client by its address masked to a prefix, taken from a trusted proxy's forwarding header`, `A41 — caddy reaches ntfy from ::1 and forwards the mesh client's address` and `A51 — pyrite's NVMe controller answers the SMART health log at the pinned smartmontools`; `checks.x86_64-linux.fleet-alert` with its fixture sequence and `promtool` pass, the replay of the new rules over stored history before they ship, and the deploy-time watch of each rule's signal that `A missing signal is itself reported` states, discharge it.

#### Scenario: A storage pool degrades

- **WHEN** the telemetry store holds a series showing magnetite's `zroot` pool degraded on every pass of the evaluator for one minute
- **THEN** one alert titled `[FIRING] ZfsPoolUnhealthy magnetite` is posted, which the operator's hand run of the deployed evaluator against magnetite's store, with the rule's matcher changed to select the online pool, confirms

#### Scenario: A unit the notifier reports fails

- **WHEN** a unit the notifier reports, such as the telemetry store, fails on magnetite
- **THEN** the person receives the notifier's failure notice and no alert for the same failure, which the build-time alert regulator confirms by replaying a failed state for a unit the notifier reports

#### Scenario: A unit another host's notifier reports fails

- **WHEN** a unit that only cinnabar's notifier reports, such as its dead-man, fails on cinnabar
- **THEN** the person receives cinnabar's failure notice and no alert for the same failure, which the build-time alert regulator confirms by replaying that failed state

#### Scenario: Memory pressure is reported with the processes behind it

- **WHEN** memory pressure holds on magnetite for 5 minutes
- **THEN** the alert names magnetite's three processes holding the most memory, the memory its storage pool holds as cache and its compressed swap in use, which the build-time alert regulator confirms from replayed results

#### Scenario: The storage pool's cache is counted as available memory

- **WHEN** the rule for memory pressure is first deployed on magnetite
- **THEN** the operator confirms on magnetite that the kernel's available-memory figure excludes the storage pool's cache, and records the observation, because the rule counts that cache above its minimum as available

#### Scenario: A file system fills

- **WHEN** a file system on cinnabar holds more than 85% of its space on every pass of the evaluator for 15 minutes, and later more than 95% for 5 minutes
- **THEN** one warning alert titled `[FIRING] FilesystemFillingWarn cinnabar` and then one critical alert titled `[FIRING] FilesystemFull cinnabar` are posted, which the build-time alert regulator confirms from replayed results

#### Scenario: A laptop's disk reports a critical warning

- **WHEN** pyrite's disk health reports a critical warning on one pass of the evaluator
- **THEN** one critical alert titled `[FIRING] NvmeCriticalWarning pyrite` is posted, which the build-time alert regulator confirms from replayed results

#### Scenario: The new rules meet the stored history

- **WHEN** before the file-system and disk-health rules ship, they are replayed over the telemetry store's stored history for magnetite, cinnabar and pyrite
- **THEN** the operator records each pass on which a rule would have held, with its cause, and a rule whose would-be alerts all share one known cause is decided on before deploy

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

While the telemetry store does not answer the evaluator's queries on one database, no alert instance read from that database SHALL resolve or be repeated, alert instances read from databases that answer SHALL keep being evaluated, and a person SHALL be told, naming the database, once queries on it have failed for 3 minutes.
While a host reports no memory signal, no alert instance for that host SHALL resolve or be repeated, and each SHALL resume once the host reports again.

**Discharged by**: `fleet-alerting-interface` requirement `Store errors and silent hosts freeze instance state`; `checks.x86_64-linux.fleet-alert`'s store-error, `devloop`-failure and silent-host fixture legs, its store-freeze, host-freeze and `allDatabasesFreeze` mutants, and its property test against the reference model's store and host freezes discharge it; the scenario "A freeze ends with the condition gone" is discharged by the same check's `storeThawLeg` and `hostThawLeg` fixture legs and its `test_resolve_follows_unfrozen_absence` property over `transition.jq` and the reference model.

#### Scenario: The telemetry store stops answering

- **WHEN** the telemetry store fails to answer the evaluator for 3 minutes while other alert instances are firing
- **THEN** one alert titled `[FIRING] StoreQueryFailing <database>`, naming the database that stopped answering, is posted and no other instance on that database resolves, which the build-time alert regulator's store-freeze mutant shows it can detect

#### Scenario: The dev-loop database stops answering

- **WHEN** queries on the dev-loop database fail for 4 minutes while a memory alert on magnetite is firing, and the memory condition goes during that time
- **THEN** one alert titled `[FIRING] StoreQueryFailing devloop` is posted, and the memory alert resolves 5 minutes after its condition goes, without waiting for the dev-loop database, which the build-time alert regulator's `devloop`-failure leg and its `allDatabasesFreeze` mutant show

#### Scenario: stibnite falls silent with an alert firing

- **WHEN** stibnite stops reporting its memory signal while one of its alert instances is firing, and later reports again with the condition still holding
- **THEN** no resolved alert and no second firing alert is posted for that instance, which the build-time alert regulator's host-freeze mutant shows it can detect

#### Scenario: A freeze ends with the condition gone

- **WHEN** a firing instance was last seen before the store stopped answering or its host fell silent, and the condition is absent once the freeze ends
- **THEN** after a freeze ends, an instance resolves only after the full absence interval observed unfrozen: no resolved alert is posted until 5 minutes after the first run that observes the store answering and the host reporting, because frozen time is not absence

### Requirement: A missing signal is itself reported

When a signal an alert rule reads has had no series for 30 minutes while at least one host expected to emit it reports its memory signal, a person SHALL be told by an alert naming that rule, but not while every expected host is silent.
When an always-on host, magnetite or cinnabar, has sent no memory signal for 15 minutes while the telemetry store answers, a person SHALL be told once, naming that host, within those 15 minutes, and again when it reports; a laptop's silence SHALL raise nothing.

**Discharged by**: `fleet-alerting-interface` requirements `Each rule's presence selector is watched` and `An always-on host's silence is reported`, and `fleet-ingress-interface` requirement `One host table declares the agent hosts and what each reports`, resting on world assumptions `A13 — Resuming this laptop from a suspended state is unreliable, and recovering a failed resume requires a person at the machine` and `A50 — electrum, galena and scheelite exist only while provisioned on demand`; `checks.x86_64-linux.fleet-alert`'s signal-gap, always-on-host and laptop-silence fixture legs, and the operator's observations at deploy and at acceptance, discharge it.

#### Scenario: A signal is renamed

- **WHEN** a rule's signal returns no series for 30 minutes while magnetite reports its memory signal
- **THEN** one alert titled `[FIRING] RuleSignalMissing` naming that rule is posted, which the build-time alert regulator confirms

#### Scenario: Every expected host is silent

- **WHEN** a rule's signal returns no series for 30 minutes while no host expected to emit it reports its memory signal
- **THEN** no alert is posted for that rule, which the build-time alert regulator confirms

#### Scenario: magnetite stops reporting while the store answers

- **WHEN** magnetite's collector stops exporting for 15 minutes while the telemetry store keeps answering
- **THEN** one alert titled `[FIRING] RuleSignalMissing magnetite` is posted, and one titled `[RESOLVED] RuleSignalMissing magnetite` after magnetite reports again, which the build-time alert regulator confirms

#### Scenario: The 15 minutes are counted

- **WHEN** an always-on host's last memory signal is stored and no later one follows while the telemetry store answers
- **THEN** a query still returns that signal for the telemetry store's 5-minute lookback, the evaluator then counts the 10 minutes once no query returns it, and the alert is posted by the end of those 15 minutes

#### Scenario: cinnabar falls silent while the notification service runs

- **WHEN** at acceptance the operator stops cinnabar's collector for 15 minutes while the notification service on cinnabar keeps running, then starts it again
- **THEN** one alert titled `[FIRING] RuleSignalMissing cinnabar` arrives within 15 minutes and one titled `[RESOLVED] RuleSignalMissing cinnabar` after it reports again, which the build-time alert regulator confirms first from replayed results, and the operator records both

#### Scenario: pyrite goes offline

- **WHEN** at acceptance, with the operator at pyrite, pyrite is taken off the network or powered off for 20 minutes while one of its alert instances is firing or none is
- **THEN** no alert naming pyrite is posted, neither its silence nor a resolution, which the build-time alert regulator confirms first from replayed results, and the operator records the 20 minutes without an alert

#### Scenario: pyrite reports memory but no disk health

- **WHEN** pyrite reports its memory signal for 30 minutes while its disk health returns no series
- **THEN** one alert titled `[FIRING] RuleSignalMissing` naming each disk-health rule is posted, which the build-time alert regulator confirms

#### Scenario: A cloud host that is provisioned on demand falls silent

- **WHEN** electrum, galena or scheelite stops reporting, whether destroyed or never provisioned
- **THEN** no alert naming that host is posted, because none of them is an always-on host

#### Scenario: The rules are first deployed

- **WHEN** 30 minutes have passed since the evaluator first ran on magnetite with the fleet's expected hosts, and the operator has also run it once by hand with one rule's signal misspelt
- **THEN** the hand run reports the misspelt signal missing, no scheduled run reports any signal missing, and the operator records both, because the build-time alert regulator replays recorded results and cannot see the signal names the telemetry store actually holds

### Requirement: A silent evaluator is reported from another host

When no heartbeat has reached the notification service for 10 minutes, a person SHALL be told within the next 5 minutes by an alert raised on cinnabar, and told once more when heartbeats resume.

**Discharged by**: `fleet-alerting-interface` requirements `Each completed evaluator run posts a heartbeat` and `The dead-man on cinnabar polls the heartbeat topic after an anonymous-publish probe`, resting on world assumptions `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path` and `A42 — ntfy keeps a topic's messages for a week and returns a recent window to a poll`; regulator R9.3's dead-man and its acceptance negative control discharge it.

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

### Requirement: Pull-request builds that wait too long to start reach a person as a warning

When, for one hour, at least 10 builds the build service ran for pull requests have finished within the trailing 24 hours and more than one in ten of them had a queue wait over 1 hour, a person SHALL be told by one warning alert naming no host, SHALL NOT be told again while that holds, and SHALL be told once more when it has not held for 5 minutes.
Builds the build service cancelled before they started SHALL NOT count, and a build the build service runs again SHALL count once, by its first run.

**Discharged by**: `fleet-alerting-interface` requirements `The pull-request queue-wait rule reads devloop through SQL`, `The evaluator queries each rule's database as the regulators' store account` and `Alert instance state is kept in one state file and posted once per transition`, and `devloop-collection` requirement `Every dev-loop event is recorded once and kept for a year`, resting on world assumption `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path`; `checks.x86_64-linux.fleet-alert`'s burn-rule timeline leg and two-database leg, and `vmTests.x86_64-linux.devloop-ingest`'s burn-rule case on the real store, discharge it.

#### Scenario: More than one in ten pull-request builds waited over an hour

- **WHEN** on every pass of the evaluator for one hour the trailing 24 hours hold 20 finished pull-request builds of which 3 had a queue wait over an hour, and then, after two slow builds age out, leaving 1 of 18, none of the passes over the next 5 minutes finds the share above one in ten
- **THEN** one alert titled `[FIRING] PullRequestQueueWaitBurn` is posted after the hour, none while it keeps holding, and one titled `[RESOLVED] PullRequestQueueWaitBurn` after the 5 minutes, which the build-time alert regulator's timeline leg confirms

#### Scenario: A quiet day with one slow build

- **WHEN** the trailing 24 hours hold 9 finished pull-request builds of which 2 waited over an hour, or 10 of which 1 did
- **THEN** no alert is posted, which the container test's burn-rule case confirms on the real store

#### Scenario: A build is run again

- **WHEN** a pull-request build that started ten minutes after it was requested is run again two hours later
- **THEN** it counts once, as a build that did not wait over an hour, which the container test's burn-rule case confirms on the real store

#### Scenario: The first week after deploy

- **WHEN** the rule's query is run by hand over each of the seven days before deploy
- **THEN** the operator records on which days it would have held, against the queue-wait history the build service kept

## MODIFIED Requirements

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

### Requirement: A missing signal is itself reported

When a signal an alert rule reads has had no series for 30 minutes while at least one host expected to emit it reports its memory signal, a person SHALL be told by an alert naming that rule, but not while every expected host is silent.
When an always-on host, magnetite or cinnabar, has reported no memory signal for 10 minutes while the telemetry store answers, a person SHALL be told once, naming that host, and again when it reports, and a laptop's silence SHALL raise nothing.

**Discharged by**: `fleet-alerting-interface` requirements `Each rule's presence selector is watched` and `An always-on host's silence is reported`, and `fleet-ingress-interface` requirement `One host table declares the agent hosts and what each reports`, resting on world assumptions `A13 — Resuming this laptop from a suspended state is unreliable, and recovering a failed resume requires a person at the machine` and `A50 — electrum, galena and scheelite exist only while provisioned on demand`; `checks.x86_64-linux.fleet-alert`'s signal-gap, always-on-host and laptop-silence fixture legs, and the operator's observations at deploy and at acceptance, discharge it.

#### Scenario: A signal is renamed

- **WHEN** a rule's signal returns no series for 30 minutes while magnetite reports its memory signal
- **THEN** one alert titled `[FIRING] RuleSignalMissing` naming that rule is posted, which the build-time alert regulator confirms

#### Scenario: Every expected host is silent

- **WHEN** a rule's signal returns no series for 30 minutes while no host expected to emit it reports its memory signal
- **THEN** no alert is posted for that rule, which the build-time alert regulator confirms

#### Scenario: magnetite stops reporting while the store answers

- **WHEN** magnetite's collector stops exporting for 10 minutes while the telemetry store keeps answering
- **THEN** one alert titled `[FIRING] RuleSignalMissing magnetite` is posted, and one titled `[RESOLVED] RuleSignalMissing magnetite` after magnetite reports again, which the build-time alert regulator confirms

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

## MODIFIED Requirements

### Requirement: Each known failure class on a host reaches a person as an alert

A person SHALL be told by an alert naming the alert rule and the host when, on a host that reports to the telemetry store, memory pressure holds, the kernel kills a process for memory, a storage pool is not online, a unit restarts more than 5 times in 15 minutes, a unit no notifier reports has failed, a source the collector reads stops answering, a file system is nearly full, or a laptop's disk is failing or worn.

**Discharged by**: `fleet-alerting-interface` requirements `The evaluator queries each rule's database as the regulators' store account`, `Alert rules are rendered from one Nix source to the evaluator and to promtool`, `Alerts are posted to fleet-alerts with a title and a severity priority` and `ntfy counts each mesh client as its own visitor`, and `fleet-ingress-interface` requirements `The darwin probe reports each allow-listed launchd job and the host's disk health in a textfile` and `A laptop's disk health is read on the host and served on loopback`, resting on world assumptions `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path`, `A40 — ntfy rate-limits a client by its address masked to a prefix, taken from a trusted proxy's forwarding header`, `A41 — caddy reaches ntfy from ::1 and forwards the mesh client's address`, `A51 — pyrite's NVMe controller answers the SMART health log at the pinned smartmontools`, `A62 — launchctl print reports a system job's state, runs and last exit code as unversioned text, and omits the exit code for some killed jobs` and `A63 — stibnite's internal SSD answers the SMART health read without privilege at the pinned smartmontools`; `checks.x86_64-linux.fleet-alert` with its fixture sequence, its darwin legs and `promtool` pass, the replay of the new rules over stored history before they ship, the deploy-time watch of each rule's signal that `A missing signal is itself reported` states, and the operator's recorded stop of a kept-alive job on stibnite at acceptance, discharge it.

#### Scenario: The failure classes of a darwin host

- **WHEN** a darwin host reports to the telemetry store
- **THEN** On a darwin host the same SHALL hold when a kept-alive job is not running, an allow-listed launchd job is not loaded, a launchd job no notifier reports has a non-zero last exit code, a launchd job starts more than 5 times in 15 minutes, or the probe's readings stop being refreshed or cannot be read.

#### Scenario: A memory alert names the processes behind it

- **WHEN** memory pressure holds, or the kernel kills a process for memory, on a host that reports to the telemetry store
- **THEN** Memory alerts SHALL name the three processes holding the most memory on that host.

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

#### Scenario: stibnite's disk reports a critical warning

- **WHEN** stibnite's disk health, read by its probe, reports a critical warning on one pass of the evaluator
- **THEN** one critical alert titled `[FIRING] NvmeCriticalWarning stibnite` is posted, under the same rule as pyrite's, which the build-time alert regulator confirms from replayed results

#### Scenario: The new rules meet the stored history

- **WHEN** before the file-system and disk-health rules ship, they are replayed over the telemetry store's stored history for magnetite, cinnabar and pyrite
- **THEN** the operator records each pass on which a rule would have held, with its cause, and a rule whose would-be alerts all share one known cause is decided on before deploy

#### Scenario: A kept-alive job is stopped on stibnite

- **WHEN** at acceptance, with no build sent to stibnite, the operator unloads stibnite's kept-alive job `org.nixos.nix-grpc-daemon` for 15 minutes and then loads it again
- **THEN** one alert titled `[FIRING] LaunchdJobNotRunning stibnite` and one titled `[RESOLVED] LaunchdJobNotRunning stibnite` arrive and nothing else, which the build-time alert regulator confirms first from replayed results, and the operator records both

#### Scenario: An allow-listed launchd job is not loaded

- **WHEN** stibnite's configuration declares an allow-listed launchd job, such as the envelope's, and the probe finds it not loaded on every pass of the evaluator for 10 minutes
- **THEN** one alert titled `[FIRING] LaunchdJobNotRunning stibnite` is posted, which the build-time alert regulator confirms from replayed results

#### Scenario: A launchd job no notifier reports fails

- **WHEN** stibnite's launchd job `org.nixos.harmonia-gc` has a non-zero last exit code on every pass of the evaluator for 5 minutes
- **THEN** one alert titled `[FIRING] LaunchdJobFailed stibnite` is posted, which the build-time alert regulator confirms from replayed results

#### Scenario: A launchd job the notifier reports fails

- **WHEN** stibnite's envelope fails and its last exit code stays non-zero
- **THEN** the person receives the notifier's failure notice for the envelope and no alert for the same failure, which the build-time alert regulator confirms by replaying that exit code

#### Scenario: A launchd job relaunches in a loop

- **WHEN** a launchd job on stibnite starts more than 5 times in 15 minutes
- **THEN** one alert titled `[FIRING] LaunchdJobRestartLoop stibnite` is posted on that pass, which the build-time alert regulator's `restartLoop` leg confirms from replayed results

#### Scenario: The probe stops refreshing its readings

- **WHEN** stibnite reports to the telemetry store while its probe's readings are more than 5 minutes old, or cannot be read, on every pass of the evaluator for 10 minutes
- **THEN** one alert titled `[FIRING] HostProbeStale stibnite` is posted, which the build-time alert regulator confirms from replayed results

#### Scenario: A failure class a darwin host cannot report

- **WHEN** stibnite reports to the telemetry store, which holds for it no available memory, no memory kill by the kernel, no storage pool state and no unit state other than its launchd jobs'
- **THEN** no alert of those failure classes names stibnite, and their absence on stibnite raises no alert that a signal is missing, which the build-time alert regulator confirms

#### Scenario: The darwin rules meet stibnite's stored history

- **WHEN** before the launchd, probe and stibnite's disk-health rules ship, they are replayed over at least 24 hours of stibnite's stored history at the evaluator's one-minute step
- **THEN** the operator records each pass on which a rule would have held, with its cause, and a replay that finds no series, or a series name that differs from the rules', stops the rules from shipping

### Requirement: An unreachable telemetry store or a silent host freezes alerts

While the telemetry store does not answer the evaluator's queries on one database, no alert instance read from that database SHALL resolve or be repeated, alert instances read from databases that answer SHALL keep being evaluated, and a person SHALL be told, naming the database, once queries on it have failed for 3 minutes.
While a host reports no memory signal, no alert instance for that host SHALL resolve or be repeated, and each SHALL resume once the host reports again.

**Discharged by**: `fleet-alerting-interface` requirement `Store errors and silent hosts freeze instance state`, resting on world assumptions `A61 — launchd misses a StartInterval firing during sleep and coalesces missed StartCalendarInterval firings into one run at wake` and `A64 — stibnite sleeps and wakes in the dark many times a day`; `checks.x86_64-linux.fleet-alert`'s store-error, `devloop`-failure, silent-host, `pendingAcrossFreeze` and `pendingAfterWake` fixture legs, its store-freeze, host-freeze and `allDatabasesFreeze` mutants, and its property test against the reference model's store and host freezes and its holding-time restart discharge it; the scenario "A freeze ends with the condition gone" is discharged by the same check's `storeThawLeg` and `hostThawLeg` fixture legs and its `test_resolve_follows_unfrozen_absence` property over `transition.jq` and the reference model; the operator's recorded suspend of stibnite and the logs of its next overnight sleep discharge the sleep scenarios at acceptance.

#### Scenario: A pending alert instance counts its holding time from its host's return

- **WHEN** an alert instance that has not yet fired was seen before its host stopped reporting, and the host reports again
- **THEN** An alert instance that has not yet fired SHALL count toward its holding time only passes after its host last resumed reporting, so a condition seen before a laptop's sleep SHALL fire only once it has held for its holding time while the laptop reports.

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

#### Scenario: A condition seen before sleep clears at wake

- **WHEN** stibnite reports, its probe's readings are first seen stale at its last report before sleep, stibnite is silent for 2 hours, and after it wakes the readings are seen stale on two passes of the evaluator and fresh after
- **THEN** no alert is posted, because the holding time counts only the passes after stibnite resumed reporting, which the build-time alert regulator's `pendingAcrossFreeze` leg confirms and showed failing before the change

#### Scenario: A condition that holds after wake

- **WHEN** stibnite wakes after the same sleep and its probe's readings stay stale for 11 minutes while it reports
- **THEN** one alert titled `[FIRING] HostProbeStale stibnite` is posted, 10 minutes after stibnite resumed reporting, which the build-time alert regulator's `pendingAfterWake` leg confirms

#### Scenario: stibnite sleeps with the lid closed

- **WHEN** at acceptance, after at least an hour of collection, the operator closes stibnite's lid for at least 30 minutes and opens it again
- **THEN** no alert and no failure notice naming stibnite is posted from the lid's closing until 30 minutes after wake, its probe and envelope each run again within one of their intervals of wake, and the operator records the sleep, the wake and every post in that window

#### Scenario: stibnite sleeps overnight with dark wakes

- **WHEN** stibnite sleeps through a night in ordinary use, waking in the dark many times
- **THEN** no alert and no failure notice naming stibnite is posted across the night, and the operator records the night's dark wakes with every post from its logs

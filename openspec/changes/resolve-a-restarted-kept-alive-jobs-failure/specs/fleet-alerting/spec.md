## MODIFIED Requirements

### Requirement: Each known failure class on a host reaches a person as an alert

A person SHALL be told by an alert naming the alert rule and the host when, on a host that reports to the telemetry store, memory pressure holds, the kernel kills a process for memory, a storage pool is not online, a unit restarts more than 5 times in 15 minutes, a unit no notifier reports has failed, a source the collector reads stops answering, a file system is nearly full, or a laptop's disk is failing or worn.

**Discharged by**: `fleet-alerting-interface` requirements `The evaluator queries each rule's database as the regulators' store account`, `Alert rules are rendered from one Nix source to the evaluator and to promtool`, `Alerts are posted to fleet-alerts with a title and a severity priority` and `ntfy counts each mesh client as its own visitor`, and `fleet-ingress-interface` requirements `The darwin probe reports each allow-listed launchd job and the host's disk health in a textfile` and `A laptop's disk health is read on the host and served on loopback`, resting on world assumptions `A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path`, `A40 — ntfy rate-limits a client by its address masked to a prefix, taken from a trusted proxy's forwarding header`, `A41 — caddy reaches ntfy from ::1 and forwards the mesh client's address`, `A51 — pyrite's NVMe controller answers the SMART health log at the pinned smartmontools`, `A62 — launchctl print reports a system job's state, runs and last exit code as unversioned text, and omits the exit code for some killed jobs` and `A63 — stibnite's internal SSD answers the SMART health read without privilege at the pinned smartmontools`; `checks.x86_64-linux.fleet-alert` with its fixture sequence, its darwin legs and `promtool` pass, the replay of the new rules over stored history before they ship, the deploy-time watch of each rule's signal that `A missing signal is itself reported` states, and the operator's recorded stop of a kept-alive job on stibnite at acceptance, discharge it.

#### Scenario: The failure classes of a darwin host

- **WHEN** a darwin host reports to the telemetry store
- **THEN** On a darwin host the same SHALL hold when a kept-alive job is not running, an allow-listed launchd job is not loaded, a launchd job no notifier reports has a non-zero last exit code, counted for a kept-alive job only within 30 minutes after launchd last started it, a launchd job starts more than 5 times in 15 minutes, or the probe's readings stop being refreshed or cannot be read.

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

#### Scenario: A kept-alive job runs again after an abnormal exit

- **WHEN** stibnite's kept-alive job `org.nixos.nix-daemon` ends without an exit code, launchd starts it again, and it keeps running with that end as its last exit
- **THEN** one alert titled `[FIRING] LaunchdJobFailed stibnite` is posted 5 minutes after the start and one titled `[RESOLVED] LaunchdJobFailed stibnite` about 35 minutes after it, with no action by the operator, which the build-time alert regulator's `keptAliveRestarted` leg confirms from replayed results and the replay over stibnite's stored history of 2026-11-08 confirms against the store

#### Scenario: A kept-alive job crashes

- **WHEN** stibnite's kept-alive job `org.nixos.otelcol-process` is killed and launchd starts it again
- **THEN** one alert titled `[FIRING] LaunchdJobFailed stibnite` is posted 5 minutes after the start, which the build-time alert regulator's `keptAliveCrashed` leg confirms from replayed results, and a job that launchd cannot keep running is reported as not running or as relaunching in a loop instead

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

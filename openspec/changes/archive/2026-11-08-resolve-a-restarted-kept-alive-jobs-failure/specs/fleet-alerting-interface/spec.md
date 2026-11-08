## MODIFIED Requirements

### Requirement: Alert rules are rendered from one Nix source to the evaluator and to promtool

The machine SHALL declare the alert rules once in `modules/nixos/fleet-alert/rules.nix`, each with `alert`, a `database` defaulting to `fleet`, a `language` of `promql` or `sql` defaulting to `promql`, an `expr` that carries its threshold, `for`, `labels.severity`, any presence selector with its expected hosts, and any annotation query, and SHALL render all of them to the evaluator's JSON and only the `promql` rules to a YAML rules file that only `promtool` reads.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s `promtool check rules` pass over the PromQL rules with its malformed-expression mutant, `vmTests.x86_64-linux.devloop-ingest`'s burn-rule case for the SQL rule, its fixture legs, which run the evaluator on the rendered rules, its notified-unit exclusion legs, its attribution legs and its darwin legs, whose series names and values are taken from stibnite's stored series; task 7.6's forced condition for each S3 rule on magnetite's store, the replay of the file-system and disk-health rules over stored history before they ship, the replay of the darwin rules over stibnite's stored history before they ship, the replay of `LaunchdJobFailed`'s two arms over stibnite's stored history before they ship, with the store's answer to `increase(launchd_job_runs_total[30m])` across a launch and a reset measured on magnetite, and the operator's recorded stop of `org.nixos.nix-grpc-daemon` on stibnite at acceptance.

#### Scenario: The rule set is rendered

- **WHEN** the rule table is rendered
- **THEN** it holds `HostMemoryPressure`, `HostOOMKill`, `FilesystemFillingWarn`, `FilesystemFull`, `ZfsPoolUnhealthy`, `NvmeCriticalWarning`, `NvmeWearHigh`, `SystemdUnitRestartLoop`, `SystemdUnitFailed`, `LocalExporterDown`, `LaunchdJobNotRunning`, `LaunchdJobFailed`, `LaunchdJobRestartLoop`, `HostProbeStale` and `WeeklyPipelineTest` on `fleet` in PromQL and `PullRequestQueueWaitBurn` on `devloop` in SQL, the YAML for `promtool` holds every rule but `PullRequestQueueWaitBurn`, and the evaluator adds `StoreQueryFailing` and `RuleSignalMissing` of its own

#### Scenario: The file-system and disk-health rules are rendered

- **WHEN** the rule table is rendered
- **THEN** `FilesystemFillingWarn` is `sum by (host_name, mountpoint) (system_filesystem_usage_bytes{state="used"}) / sum by (host_name, mountpoint) (system_filesystem_usage_bytes) > 0.85` for 15 min at `warning`, `FilesystemFull` the same above 0.95 for 5 min at `critical`, `NvmeCriticalWarning` `smartctl_device_critical_warning_total != 0` with no `for` at `critical`, and `NvmeWearHigh` `smartctl_device_percentage_used_total > 90` for 1 h at `warning`, under the `_total` names the store gives the exporter's counter-typed fields

#### Scenario: The darwin rules are rendered

- **WHEN** the rule table is rendered
- **THEN** `LaunchdJobNotRunning` is `launchd_job_state{launchd_state="running", launchd_label=~"<kept-alive labels>"} == 0 or launchd_job_state{launchd_state="unloaded", launchd_label!~"<kept-alive labels>"} == 1` for 10 min, `LaunchdJobFailed` `launchd_job_last_exit_code{launchd_label!~"<labels in notifiedUnits>|<kept-alive labels>"} != 0 or (launchd_job_last_exit_code{launchd_label=~"<kept-alive labels>", launchd_label!~"<labels in notifiedUnits>"} != 0 and on (host_name, launchd_label) increase(launchd_job_runs_total[30m]) > 0)` for 5 min, `LaunchdJobRestartLoop` `increase(launchd_job_runs_total[15m]) > 5` with no `for`, and `HostProbeStale` `time() - node_textfile_mtime_seconds > 300 or node_textfile_scrape_error == 1` for 10 min, each at `warning`
- **AND** `<kept-alive labels>` is rendered from `schema.nix`'s kept-alive list `launchdKeptAlive`, held equal by the darwin fragment's assertion to the labels of `schema.nix`'s launchd allow-list, which holds `org.nixos.otel-envelope`, whose evaluated `KeepAlive` is true on the darwin row, and `<labels in notifiedUnits>` from the `org.nixos.<unit>` label of each unit in the darwin rows' `notifiedUnits`, each with its literal dots written `[.]`

#### Scenario: An expression does not parse

- **WHEN** the check's mutant gives one rule a malformed expression
- **THEN** `promtool check rules` rejects the rendered YAML and the check fails

#### Scenario: A unit the notifier reports fails

- **WHEN** the fixture server replays `systemd_unit_state{systemd_unit_active_state="failed"} == 1` for each unit in the union of every host's `notifiedUnits` in `flake.lib.observabilityHosts`
- **THEN** the evaluator posts no `SystemdUnitFailed`, because that rule's exclusion is rendered from that union, with its literal dot written `[.]`, as GreptimeDB 1.2.1 rejects `\.` in both double-quoted and backtick strings

#### Scenario: A launchd job the notifier wrapper reports fails

- **WHEN** the fixture server replays `launchd_job_last_exit_code` of 1 on stibnite for 5 min, for `org.nixos.otel-envelope` in leg `envelopeFailedNotReported` and for `org.nixos.harmonia-gc` in leg `harmoniaFailedReported`
- **THEN** the evaluator posts no `LaunchdJobFailed` in the first leg and one `[FIRING] LaunchdJobFailed stibnite` in the second, because the envelope posts its own `FAILED` notice

#### Scenario: A kept-alive job's abnormal exit is counted only after its relaunch

- **WHEN** the fixture server answers, on stibnite once a minute, `LaunchdJobFailed`'s rendered expression as its two arms select one job whose launch count last rose at minute 0: `org.nixos.nix-daemon` with last exit -1 for 40 min in leg `keptAliveRestarted`, `org.nixos.otelcol-process` with last exit -1 for 10 min in leg `keptAliveCrashed`, and `org.nixos.harmonia-gc`, which is not kept alive, with last exit 1 for 40 min in leg `notKeptAliveHeld`
- **THEN** the evaluator posts `[FIRING] LaunchdJobFailed stibnite` at minute 5 in each leg and `[RESOLVED] LaunchdJobFailed stibnite` at minute 34 in `keptAliveRestarted` only, and the mutant `failedIgnoresLaunch`, the single-arm expression with the rendered notified exclusion, fails `keptAliveRestarted`

#### Scenario: A kept-alive job stops or an allow-listed job is unloaded

- **WHEN** the fixture server answers, for 15 min on stibnite, `LaunchdJobNotRunning`'s rendered expression over the probe's four `launchd_job_state` series for one label, as the expression's two arms select them: `org.nixos.nix-grpc-daemon` `not_running` in leg `keptAliveStopped`, `org.nixos.nix-grpc-daemon` `unloaded`, written `running` 0 and `unloaded` 1, in leg `keptAliveUnloaded`, and `org.nixos.otel-envelope` `unloaded` in leg `envelopeUnloaded`
- **THEN** the evaluator posts exactly one `[FIRING] LaunchdJobNotRunning stibnite` and one `[RESOLVED]` in each leg, and the mutant `notRunningBothArms`, the unloaded arm without its kept-alive exclusion, fails `keptAliveUnloaded`

#### Scenario: The probe's textfile goes stale

- **WHEN** the fixture server replays, in leg `probeStale`, `node_textfile_mtime_seconds` for stibnite's `launchd.prom` more than 300 s behind the run's time on every run for 10 min while stibnite reports `system_memory_usage_bytes`
- **THEN** the evaluator posts one `[FIRING] HostProbeStale stibnite`

#### Scenario: A launchd job relaunches in a loop

- **WHEN** the fixture server replays, in leg `restartLoop`, a `launchd_job_runs_total` on stibnite that increases by more than 5 within 15 min
- **THEN** the evaluator posts one `[FIRING] LaunchdJobRestartLoop stibnite` on that run

#### Scenario: A memory alert carries its attribution

- **WHEN** the fixture server replays a firing `HostMemoryPressure` or `HostOOMKill` instance on a host
- **THEN** the posted body carries that host's `topk(3, process_memory_usage_bytes)`, `node_zfs_arc_size` and summed `system_paging_usage_bytes{state="used"}`, and states that resident memory omits swapped-out pages

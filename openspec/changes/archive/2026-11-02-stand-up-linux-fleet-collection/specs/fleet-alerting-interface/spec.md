## MODIFIED Requirements

### Requirement: The evaluator queries each rule's database as the regulators' store account

The machine SHALL run on magnetite `fleet-alert.service`, a oneshot with `DynamicUser = true` and `StateDirectory = "fleet-alert"` that `fleet-alert.timer` starts every 60 s, issuing each rule's query on its database as `regulator` (password through `LoadCredential`), one at a time with a 10 s timeout each, as a scenario below states.
A failed or timed-out query SHALL end that run's querying of its rule's database, and queries on other databases SHALL continue inside the run's query deadline.

**Discharged by**: magnetite's credential-holder assertion (R8.2), which admits `fleet-alert`, `devloop-reconcile` and `otel-envelope` as `regulator-password` holders; `checks.x86_64-linux.fleet-alert`, whose fixture server refuses any other path, any database other than the rule's, or any other credential, records each request's path and database, and fails a leg if two queries are ever open at once, with its two-database leg and its mutant that sends every rule to `fleet`; and the operator's recorded first run on magnetite.

#### Scenario: A rule's query is sent by its language

- **WHEN** the evaluator issues a rule's query
- **THEN** a rule whose `language` is `promql` is sent as an instant query to `http://127.0.0.1:4000/v1/prometheus/api/v1/query` with `x-greptime-db-name: <database>`, and a rule whose `language` is `sql` as `POST http://127.0.0.1:4000/v1/sql?db=<database>`, accepting a 200 whose body holds exactly one `records` result, each of whose rows is one result with its `value` column as the value and its other columns as labels

#### Scenario: A second unit loads the regulators' password

- **WHEN** magnetite's configuration loads `regulator-password` into a unit other than `greptimedb-envelope`, `fleet-alert`, `devloop-reconcile` and `otel-envelope`
- **THEN** magnetite's evaluation fails on the credential-holder assertion (R8.2)

#### Scenario: The evaluator's queries are checked at the fixture server

- **WHEN** the evaluator runs against the check's fixture server
- **THEN** the server answers 404 to any path other than `/v1/prometheus/api/v1/query` and `/v1/sql`, 400 to a PromQL query whose `x-greptime-db-name` or a SQL query whose `db` is not the database the leg's rule declares, and 401 to any account but `regulator` with the fixture password, and the leg fails if two queries are ever open at once

#### Scenario: Two databases are queried in one run

- **WHEN** the two-database leg runs a PromQL rule declared on `fleet` and `PullRequestQueueWaitBurn` declared on `devloop`
- **THEN** the server records one PromQL request with `x-greptime-db-name: fleet` and one `/v1/sql` request with `db=devloop`, and the mutant evaluator that sends every rule to `fleet` fails the leg

#### Scenario: The evaluator's queries fit the store's query limit

- **WHEN** the evaluator runs its rule set's queries against magnetite's store, which accepts at most 8 concurrent queries, 23 in a run with no memory rule firing and outside `WeeklyPipelineTest`'s window (one per unique presence selector and one per expression not gated by a window: 22 PromQL on `fleet` and one SQL on `devloop`), plus the attribution queries of a firing memory rule
- **THEN** it holds one of those 8 at a time; the 19 PromQL queries of S3's rule set, run one after another on magnetite on 2026-10-18, took 0.62 to 0.68 s in total, and the operator records the time of a run's queries at the deploy that adds the file-system and disk-health rules

#### Scenario: The evaluator first runs on magnetite

- **WHEN** `fleet-alert.service` first runs on magnetite
- **THEN** it exits successfully having queried `fleet` and `devloop` as `regulator`, and the operator records the run

### Requirement: Alert rules are rendered from one Nix source to the evaluator and to promtool

The machine SHALL declare the alert rules once in `modules/nixos/fleet-alert/rules.nix`, each with `alert`, a `database` defaulting to `fleet`, a `language` of `promql` or `sql` defaulting to `promql`, an `expr` that carries its threshold, `for`, `labels.severity`, any presence selector with its expected hosts, and any annotation query, and SHALL render all of them to the evaluator's JSON and only the `promql` rules to a YAML rules file that only `promtool` reads.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s `promtool check rules` pass over the PromQL rules with its malformed-expression mutant, `vmTests.x86_64-linux.devloop-ingest`'s burn-rule case for the SQL rule, its fixture legs, which run the evaluator on the rendered rules, its notified-unit exclusion legs and its attribution legs; task 7.6's forced condition for each S3 rule on magnetite's store, and the replay of the file-system and disk-health rules over stored history before they ship.

#### Scenario: The rule set is rendered

- **WHEN** the rule table is rendered
- **THEN** it holds `HostMemoryPressure`, `HostOOMKill`, `FilesystemFillingWarn`, `FilesystemFull`, `ZfsPoolUnhealthy`, `NvmeCriticalWarning`, `NvmeWearHigh`, `SystemdUnitRestartLoop`, `SystemdUnitFailed`, `LocalExporterDown` and `WeeklyPipelineTest` on `fleet` in PromQL and `PullRequestQueueWaitBurn` on `devloop` in SQL, the YAML for `promtool` holds every rule but `PullRequestQueueWaitBurn`, and the evaluator adds `StoreQueryFailing` and `RuleSignalMissing` of its own

#### Scenario: The file-system and disk-health rules are rendered

- **WHEN** the rule table is rendered
- **THEN** `FilesystemFillingWarn` is `sum by (host_name, mountpoint) (system_filesystem_usage_bytes{state="used"}) / sum by (host_name, mountpoint) (system_filesystem_usage_bytes) > 0.85` for 15 min at `warning`, `FilesystemFull` the same above 0.95 for 5 min at `critical`, `NvmeCriticalWarning` `smartctl_device_critical_warning_total != 0` with no `for` at `critical`, and `NvmeWearHigh` `smartctl_device_percentage_used_total > 90` for 1 h at `warning`, under the `_total` names the store gives the exporter's counter-typed fields

#### Scenario: An expression does not parse

- **WHEN** the check's mutant gives one rule a malformed expression
- **THEN** `promtool check rules` rejects the rendered YAML and the check fails

#### Scenario: A unit the notifier reports fails

- **WHEN** the fixture server replays `systemd_unit_state{systemd_unit_active_state="failed"} == 1` for each unit in the union of every host's `notifiedUnits` in `flake.lib.observabilityHosts`
- **THEN** the evaluator posts no `SystemdUnitFailed`, because that rule's exclusion is rendered from that union, with its literal dot written `[.]`, as GreptimeDB 1.2.1 rejects `\.` in both double-quoted and backtick strings

#### Scenario: A memory alert carries its attribution

- **WHEN** the fixture server replays a firing `HostMemoryPressure` or `HostOOMKill` instance on a host
- **THEN** the posted body carries that host's `topk(3, process_memory_usage_bytes)`, `node_zfs_arc_size` and summed `system_paging_usage_bytes{state="used"}`, and states that resident memory omits swapped-out pages

### Requirement: Each rule's presence selector is watched

Each rule's presence selector SHALL be the bare metric name of its expression, except `up{job="node"}` for `LocalExporterDown`, its expected hosts SHALL be every host of `flake.lib.observabilityHosts` whose `collect` is true, or for the NVMe rules those of them with `smartDevices`, and the evaluator SHALL raise `RuleSignalMissing`, `warning`, for a rule whose selector has returned no series for 30 min while an expected host reports `system_memory_usage_bytes`.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s signal-gap fixture legs; the operator's recorded observation that no `RuleSignalMissing` fires within 30 min of the evaluator's first run with the fleet's expected hosts, with its negative control.

#### Scenario: A selector is empty while an expected host reports

- **WHEN** the fixture server returns no series for a rule's selector for 30 min while an expected host returns `system_memory_usage_bytes`
- **THEN** the evaluator posts one `[FIRING] RuleSignalMissing` naming that rule

#### Scenario: A selector is empty while every expected host is silent

- **WHEN** the fixture server returns no series for a rule's selector and no `system_memory_usage_bytes` for any of its expected hosts for 30 min
- **THEN** the evaluator posts nothing for that rule

#### Scenario: The NVMe selectors expect pyrite alone

- **WHEN** the fixture server returns `system_memory_usage_bytes` for magnetite and cinnabar only, and no `smartctl_device_critical_warning_total`, for 30 min
- **THEN** the evaluator posts nothing for `NvmeCriticalWarning`, and once pyrite also reports memory for 30 min without that series it posts one `[FIRING] RuleSignalMissing` naming the rule

#### Scenario: The deployed selectors are checked at acceptance

- **WHEN** at acceptance the operator runs the deployed evaluator by hand with one presence selector misspelt, its `for` at 0, scratch state and topic `fleet-acceptance`, and then waits 30 min after the evaluator's first scheduled run
- **THEN** the hand run posts `RuleSignalMissing` for the misspelt selector, the scheduled runs post none, and the operator records both

### Requirement: An always-on host's silence is reported

For each host whose `alwaysOn` and `collect` are true in `flake.lib.observabilityHosts`, magnetite and cinnabar, the evaluator SHALL raise `RuleSignalMissing` with `selector="system_memory_usage_bytes"` and that `host_name` once the store has answered but the host has been absent for 10 min since it last reported, or since the evaluator's first run, and SHALL resolve it when the host reports again; this SHALL be the only host-absence path.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s always-on-host and laptop-silence fixture legs, with the mutant that stops recording when each host last reported; `fleet-ingress-interface` requirement `otel-envelope regulates each agent from its own collector`, which carries no last-seen clause.

#### Scenario: An always-on host stops reporting while the store answers

- **WHEN** the fixture server answers every query but returns no series for magnetite for 40 min after it last reported, with `node_vmstat_oom_kill` empty, and then magnetite reports again
- **THEN** the evaluator posts one `[FIRING] RuleSignalMissing magnetite` 10 min after magnetite last reported, none for `node_vmstat_oom_kill`, and one `[RESOLVED] RuleSignalMissing magnetite` once magnetite reports again 5 min after the last run that found it silent

#### Scenario: cinnabar stops reporting while magnetite reports

- **WHEN** the fixture server returns no `system_memory_usage_bytes` for cinnabar for 40 min while magnetite reports, and then cinnabar reports again
- **THEN** the evaluator posts one `[FIRING] RuleSignalMissing cinnabar` 10 min after cinnabar last reported and one `[RESOLVED] RuleSignalMissing cinnabar` once it reports again

#### Scenario: A laptop or an on-demand host stops reporting

- **WHEN** the fixture server returns no `system_memory_usage_bytes` for pyrite, with one of its instances firing, or for electrum, for 40 min
- **THEN** the evaluator posts nothing about either host, and pyrite's firing instance neither resolves nor repeats

### Requirement: The dead-man on cinnabar polls the heartbeat topic after an anonymous-publish probe

On cinnabar, `fleet-deadman.timer` SHALL start `fleet-deadman.service` every 5 min, with `DynamicUser = true`, `StateDirectory = "fleet-deadman"` and `OnFailure=observability-notify@%n.service`, which SHALL first publish anonymously to `http://[::1]:2586/fleet-heartbeat` and fail if accepted, then poll `/fleet-heartbeat/json?poll=1&since=10m` there and, in its `state.json`, raise `AlertEvaluatorSilent`, `critical`, on an empty result and resolve it when a heartbeat returns.

**Discharged by**: regulator R9.3, shown able to fail at acceptance by stopping `fleet-alert.timer`, resting on world assumption `A42 — ntfy keeps a topic's messages for a week and returns a recent window to a poll`, whose `AlertEvaluatorSilent` reaches `fleet-alerts` only with the `alerter` credential once `*:fleet-*:ro` is in force; regulator R9.4, shown able to fail at acceptance by removing `*:fleet-*:ro`; and the assertions that hold R9.4's premise on cinnabar, `fleet-alert.nix`'s on ntfy's listener and access entries and cinnabar's on the dead-man's ordering, each shown able to fail by an `extendModules` override.

#### Scenario: The evaluator's timer is stopped

- **WHEN** at acceptance the operator stops `fleet-alert.timer` on magnetite, then starts it again
- **THEN** `AlertEvaluatorSilent` is posted to `fleet-alerts` within 15 min of the stop, and its `RESOLVED` after the start, and the operator records both

#### Scenario: The anonymous read-only entry is removed

- **WHEN** at acceptance the operator removes `*:fleet-*:ro` from cinnabar's `auth-access`
- **THEN** the probe's anonymous publish is accepted, `fleet-deadman.service` fails, a `FAILED` naming it and cinnabar appears on `fleet-alerts`, and the operator records both

#### Scenario: The probe is refused

- **WHEN** the access entries are in force and the dead-man runs
- **THEN** the probe's anonymous publish is refused with 403 and the unit goes on to poll

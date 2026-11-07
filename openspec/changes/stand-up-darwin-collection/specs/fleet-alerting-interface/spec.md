## MODIFIED Requirements

### Requirement: The evaluator queries each rule's database as the regulators' store account

The machine SHALL run on magnetite `fleet-alert.service`, a oneshot with `DynamicUser = true` and `StateDirectory = "fleet-alert"` that `fleet-alert.timer` starts every 60 s, issuing each rule's query on its database as `regulator` (password through `LoadCredential`), one at a time with a 10 s timeout each, as a scenario below states.
A failed or timed-out query SHALL end that run's querying of its rule's database, and queries on other databases SHALL continue inside the run's query deadline.

**Discharged by**: magnetite's credential-holder assertion (R8.2), which admits `fleet-alert`, `devloop-reconcile` and `otel-envelope` as `regulator-password` holders; `checks.x86_64-linux.fleet-alert`, whose fixture server refuses any other path, any database other than the rule's, or any other credential, records each request's path and database, and fails a leg if two queries are ever open at once, with its two-database leg and its mutant that sends every rule to `fleet`; and the operator's recorded first run on magnetite, and the query count and time recorded at the deploy that adds the darwin rules.

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

- **WHEN** the evaluator runs its rule set's queries against magnetite's store, which accepts at most 8 concurrent queries, 31 in a run with no memory rule firing and outside `WeeklyPipelineTest`'s window `[INFERENCE: 23 plus four selectors and four expressions]` (one per unique presence selector and one per expression not gated by a window: 30 PromQL on `fleet` and one SQL on `devloop`), plus the attribution queries of a firing memory rule
- **THEN** it holds one of those 8 at a time; the 19 PromQL queries of S3's rule set, run one after another on magnetite on 2026-10-18, took 0.62 to 0.68 s in total, and the operator records the number and the time of a run's queries at the deploy that adds the file-system and disk-health rules and again at the deploy that adds the darwin rules

#### Scenario: The evaluator first runs on magnetite

- **WHEN** `fleet-alert.service` first runs on magnetite
- **THEN** it exits successfully having queried `fleet` and `devloop` as `regulator`, and the operator records the run

### Requirement: Alert rules are rendered from one Nix source to the evaluator and to promtool

The machine SHALL declare the alert rules once in `modules/nixos/fleet-alert/rules.nix`, each with `alert`, a `database` defaulting to `fleet`, a `language` of `promql` or `sql` defaulting to `promql`, an `expr` that carries its threshold, `for`, `labels.severity`, any presence selector with its expected hosts, and any annotation query, and SHALL render all of them to the evaluator's JSON and only the `promql` rules to a YAML rules file that only `promtool` reads.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s `promtool check rules` pass over the PromQL rules with its malformed-expression mutant, `vmTests.x86_64-linux.devloop-ingest`'s burn-rule case for the SQL rule, its fixture legs, which run the evaluator on the rendered rules, its notified-unit exclusion legs, its attribution legs and its darwin legs, whose series names and values are taken from stibnite's stored series; task 7.6's forced condition for each S3 rule on magnetite's store, the replay of the file-system and disk-health rules over stored history before they ship, the replay of the darwin rules over stibnite's stored history before they ship, and the operator's recorded stop of `org.nixos.nix-grpc-daemon` on stibnite at acceptance.

#### Scenario: The rule set is rendered

- **WHEN** the rule table is rendered
- **THEN** it holds `HostMemoryPressure`, `HostOOMKill`, `FilesystemFillingWarn`, `FilesystemFull`, `ZfsPoolUnhealthy`, `NvmeCriticalWarning`, `NvmeWearHigh`, `SystemdUnitRestartLoop`, `SystemdUnitFailed`, `LocalExporterDown`, `LaunchdJobNotRunning`, `LaunchdJobFailed`, `LaunchdJobRestartLoop`, `HostProbeStale` and `WeeklyPipelineTest` on `fleet` in PromQL and `PullRequestQueueWaitBurn` on `devloop` in SQL, the YAML for `promtool` holds every rule but `PullRequestQueueWaitBurn`, and the evaluator adds `StoreQueryFailing` and `RuleSignalMissing` of its own

#### Scenario: The file-system and disk-health rules are rendered

- **WHEN** the rule table is rendered
- **THEN** `FilesystemFillingWarn` is `sum by (host_name, mountpoint) (system_filesystem_usage_bytes{state="used"}) / sum by (host_name, mountpoint) (system_filesystem_usage_bytes) > 0.85` for 15 min at `warning`, `FilesystemFull` the same above 0.95 for 5 min at `critical`, `NvmeCriticalWarning` `smartctl_device_critical_warning_total != 0` with no `for` at `critical`, and `NvmeWearHigh` `smartctl_device_percentage_used_total > 90` for 1 h at `warning`, under the `_total` names the store gives the exporter's counter-typed fields

#### Scenario: The darwin rules are rendered

- **WHEN** the rule table is rendered
- **THEN** `LaunchdJobNotRunning` is `launchd_job_state{launchd_state="running", launchd_label=~"<kept-alive labels>"} == 0 or launchd_job_state{launchd_state="unloaded", launchd_label!~"<kept-alive labels>"} == 1` for 10 min, `LaunchdJobFailed` `launchd_job_last_exit_code{launchd_label!~"<labels in notifiedUnits>"} != 0` for 5 min, `LaunchdJobRestartLoop` `increase(launchd_job_runs_total[15m]) > 5` with no `for`, and `HostProbeStale` `time() - node_textfile_mtime_seconds > 300 or node_textfile_scrape_error == 1` for 10 min, each at `warning`
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

### Requirement: Each rule's presence selector is watched

Each rule's presence selector SHALL be the bare metric name of its expression, except `up{job="node"}` for `LocalExporterDown`, and the evaluator SHALL raise `RuleSignalMissing`, `warning`, for a rule whose selector has returned no series for 30 min while an expected host reports `system_memory_usage_bytes`.
A rule's expected hosts SHALL be the hosts of `flake.lib.observabilityHosts` whose `collect` is true and that write its selector, as the scenarios below state: those whose `platform` is `nixos`, those with `smartDevices`, those whose `platform` is `darwin`, or all of them.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s signal-gap fixture legs, with its legs `linuxSelectorDarwinOnly`, `stibniteNotCollecting`, `darwinSignalMissing` and `nvmeExpectsStibnite`; `fleet-ingress-interface` requirement `One host table declares the agent hosts and what each reports`, whose assertion compares each row's `platform` with the inventory's `machineClass`; the operator's recorded observation that no `RuleSignalMissing` fires within 30 min of the evaluator's first run with the fleet's expected hosts, with its negative control, and within 30 min of the deploy that adds the darwin rules.

#### Scenario: Expected hosts follow each host's platform

- **WHEN** the rule table is rendered
- **THEN** `HostMemoryPressure`, `HostOOMKill`, `ZfsPoolUnhealthy`, `SystemdUnitRestartLoop` and `SystemdUnitFailed` expect the collecting hosts whose `platform` is `nixos`; `FilesystemFillingWarn`, `FilesystemFull`, `LocalExporterDown` and `WeeklyPipelineTest` every collecting host; `NvmeCriticalWarning` and `NvmeWearHigh` the collecting hosts with `smartDevices`, pyrite and stibnite; and `LaunchdJobNotRunning`, `LaunchdJobFailed`, `LaunchdJobRestartLoop` and `HostProbeStale` the collecting hosts whose `platform` is `darwin`, stibnite

#### Scenario: A selector is empty while an expected host reports

- **WHEN** the fixture server returns no series for a rule's selector for 30 min while an expected host returns `system_memory_usage_bytes`
- **THEN** the evaluator posts one `[FIRING] RuleSignalMissing` naming that rule

#### Scenario: A selector is empty while every expected host is silent

- **WHEN** the fixture server returns no series for a rule's selector and no `system_memory_usage_bytes` for any of its expected hosts for 30 min
- **THEN** the evaluator posts nothing for that rule

#### Scenario: The NVMe selectors expect pyrite alone

- **WHEN** pyrite is the only collecting host with `smartDevices`, as before stibnite collects, and the fixture server returns `system_memory_usage_bytes` for magnetite and cinnabar only, and no `smartctl_device_critical_warning_total`, for 30 min
- **THEN** the NVMe selectors expect pyrite alone: the evaluator posts nothing for `NvmeCriticalWarning`, and once pyrite also reports memory for 30 min without that series it posts one `[FIRING] RuleSignalMissing` naming the rule

#### Scenario: The NVMe selectors also expect stibnite

- **WHEN** in leg `nvmeExpectsStibnite` stibnite collects with `smartDevices` and the fixture server returns `system_memory_usage_bytes` for magnetite, cinnabar and stibnite, and no `smartctl_device_critical_warning_total`, for 30 min
- **THEN** the evaluator posts one `[FIRING] RuleSignalMissing` naming `NvmeCriticalWarning`, because stibnite is then an expected host of the NVMe rules beside pyrite

#### Scenario: A Linux-only selector is empty while only stibnite reports

- **WHEN** in leg `linuxSelectorDarwinOnly` the fixture server returns `system_memory_usage_bytes` and stibnite's other series for stibnite alone, and no series for the selectors of `HostMemoryPressure`, `HostOOMKill`, `ZfsPoolUnhealthy`, `SystemdUnitRestartLoop` or `SystemdUnitFailed`, for 30 min
- **THEN** the evaluator posts nothing for those rules, which the expected hosts of every collecting host failed before the platform split

#### Scenario: A launchd selector is empty while stibnite reports

- **WHEN** in leg `darwinSignalMissing` the fixture server returns `system_memory_usage_bytes` for stibnite and no `launchd_job_state` for 30 min
- **THEN** the evaluator posts one `[FIRING] RuleSignalMissing` naming `LaunchdJobNotRunning`

#### Scenario: A host that does not collect is expected nowhere

- **WHEN** in leg `stibniteNotCollecting` stibnite's row has `collect = false` and the fixture server returns no launchd or textfile series while magnetite reports for 30 min
- **THEN** stibnite is no rule's expected host and the evaluator posts nothing for the darwin rules

#### Scenario: The deployed selectors are checked at acceptance

- **WHEN** at acceptance the operator runs the deployed evaluator by hand with one presence selector misspelt, its `for` at 0, scratch state and topic `fleet-acceptance`, and then waits 30 min after the evaluator's first scheduled run
- **THEN** the hand run posts `RuleSignalMissing` for the misspelt selector, the scheduled runs post none, and the operator records both

#### Scenario: The darwin selectors are deployed

- **WHEN** 30 min have passed since magnetite's deploy that adds the darwin rules, with stibnite reporting
- **THEN** no `RuleSignalMissing` names a darwin rule, and the operator records every post since the deploy with its cause

### Requirement: Store errors and silent hosts freeze instance state

When a query fails or times out, the evaluator SHALL stop querying that database for the run, leave unchanged every instance whose rule reads it, keep evaluating rules on databases that answered, and raise `StoreQueryFailing`.
A database whose queries the run's query deadline did not reach SHALL count as failed for that run.
While a host returns no `system_memory_usage_bytes`, the evaluator SHALL leave every instance labelled with that host unchanged, as the scenarios below state.
A `pending` instance that was frozen on the previous run and is not frozen on this one SHALL have its `activeSince` set to this run, so its `for` counts only runs on which its database answers and its host reports.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s store-error, `devloop`-failure, silent-host, `pendingAcrossFreeze` and `pendingAfterWake` fixture legs, its store-freeze, host-freeze and `allDatabasesFreeze` mutants, and its property test against the reference model's per-database store freeze, host freeze and pending restart, whose two-database property was shown failing against the all-freeze transition before the change and whose `pendingAcrossFreeze` leg was shown failing against the transition that kept pending time across a freeze; the operator's recorded suspend of stibnite at acceptance.

#### Scenario: A database's queries fail

- **WHEN** the queries on one database fail or time out
- **THEN** the evaluator raises `StoreQueryFailing`, `critical`, with a `for` of 3 min, one instance per failing database, labelled with that `database` and naming it in its message

#### Scenario: A host falls silent

- **WHEN** a host returns no `system_memory_usage_bytes`
- **THEN** every instance labelled with that host is left unchanged, posting neither a `RESOLVED` nor a re-post, until the host reports again, except the `RuleSignalMissing` instance that reports that host's own absence

#### Scenario: The store freeze is dropped

- **WHEN** the check's mutant drops the store freeze and the fixture server answers a run with an error while an instance is firing
- **THEN** the mutant posts a `RESOLVED`, and the check fails

#### Scenario: The host freeze is dropped

- **WHEN** the check's mutant drops the host freeze and the fixture server stops returning `system_memory_usage_bytes` for a host with a firing instance
- **THEN** the mutant posts a `RESOLVED`, and the check fails

#### Scenario: One failed query bounds the run

- **WHEN** a query on one database times out after 10 s
- **THEN** the run issues no further query on that database, queries the other databases within its 30 s query deadline, and so ends well inside `TimeoutStartSec = 50s`

#### Scenario: Only the failing database is frozen

- **WHEN** the burn rule's SQL on `devloop` fails on every run for 4 min while `HostOOMKill` on `fleet` fires and its condition then goes
- **THEN** one `[FIRING] StoreQueryFailing devloop` is posted after 3 min, and `HostOOMKill` resolves 5 min after its condition goes, while `devloop` is still failing

#### Scenario: Every database is frozen by one failure

- **WHEN** the check's mutant `allDatabasesFreeze` freezes every instance whenever any database fails
- **THEN** the `devloop`-failure leg fails, and the check fails

#### Scenario: A pending instance crosses a host's silence

- **WHEN** in leg `pendingAcrossFreeze` stibnite returns `system_memory_usage_bytes`, `HostProbeStale`'s condition is first returned true at stibnite's last sample, stibnite returns no `system_memory_usage_bytes` for 2 h, and then it reports with the condition true on two runs and false after
- **THEN** the evaluator posts nothing, where the transition that kept pending time across the freeze posted `[FIRING] HostProbeStale stibnite` on the first run after the silence

#### Scenario: A pending instance holds after the silence

- **WHEN** in leg `pendingAfterWake` the same silence ends and the condition stays true for 11 min while stibnite reports
- **THEN** the evaluator posts exactly one `[FIRING] HostProbeStale stibnite`, 10 min after the first run that finds stibnite reporting

#### Scenario: The pending restart is compared with the reference model

- **WHEN** Hypothesis generates timelines in which a host or a database freezes while an instance is `pending` and then thaws with the condition held or absent
- **THEN** the jq transition function's posts and state equal the reference model's at every step, and both restart the instance's `activeSince` at the first unfrozen run

#### Scenario: stibnite is suspended at acceptance

- **WHEN** at acceptance, after at least an hour of collection, the operator closes stibnite's lid for at least 30 min and opens it again
- **THEN** the evaluator's journal holds no post naming stibnite from the lid's closing until 30 min after wake, and the operator records it with the sleep and wake times from `pmset -g log`

### Requirement: The alerter token travels only as a file

The `ntfy-alerter` generator, shared by magnetite, cinnabar, pyrite, electrum, galena, scheelite and stibnite, SHALL hold only the `alerter` token, as `token` with mode `0400`, owned on stibnite by `_otelcol`, and SHALL gain a reader only through `clan vars fix`, never by being generated again; the per-machine `ntfy-alerter-env` generator, declared on cinnabar only, SHALL derive `ntfy-env` from that token.
`ntfy-send` SHALL, when `NTFY_TOKEN_FILE` is set, send `Authorization: Bearer` with that file's token without placing it on curl's argument list, and every `fleet-*` publisher, stibnite's notifier wrapper among them, SHALL pass the token to it through `NTFY_TOKEN_FILE`.

**Discharged by**: `checks.<system>.package-ntfy-send-test-token-transport` with its argv mutant; the resolve-hook assertion in `observability-notify.nix`, shown able to fail by an `extendModules` override; `checks.x86_64-linux.otel-collector-darwin`'s notifier wrapper cases over a recording `ntfy-send`; the vars step's records of the decrypted token's sha256 before and after stibnite is added as a reader; the cutover order, resting on world assumption `A39 — ntfy refuses a request whose token it does not know, even where anonymous access is allowed`; the `alerter`-authenticated heartbeat requests recorded during the cutover; once `*:fleet-*:ro` is in force, the forced failure notice delivered with `alerter` and regulator R9.3's `AlertEvaluatorSilent`, both of which ntfy refuses without the token; and stibnite's refused anonymous post and accepted wrapper post at acceptance, resting on world assumption `A66 — ntfy refuses an anonymous post to a fleet topic from stibnite`.

#### Scenario: The sender is run with a recording curl

- **WHEN** `checks.<system>.package-ntfy-send-test-token-transport` runs `ntfy-send` with `NTFY_TOKEN_FILE` set and a recording curl stub
- **THEN** the token never appears in the stub's argument list and arrives as an `Authorization: Bearer` header read from stdin, and a mutant script passing the header on the argument list fails the test

#### Scenario: Each notified unit's resolve hooks carry the token

- **WHEN** magnetite's and cinnabar's configurations are evaluated
- **THEN** `observability-notify.nix`'s assertion holds that every notified unit's resolve hooks run under `env NTFY_TOKEN_FILE=<tokenFile>`, and an `extendModules` override replacing one unit's hooks makes evaluation fail

#### Scenario: stibnite is added as a reader

- **WHEN** the vars step runs `CLAN_NO_COMMIT=1 clan vars fix stibnite --generator ntfy-alerter`
- **THEN** the sha256 of the decrypted token, never printed, is the same before and after, `vars/shared/ntfy-alerter/token/machines/` lists seven readers, and the step stops otherwise

#### Scenario: stibnite's wrapper posts with the token file

- **WHEN** `checks.x86_64-linux.otel-collector-darwin` runs `observability-notify-run` over a recording `ntfy-send`, and stibnite's activation installs its copy of the token
- **THEN** the token reaches `ntfy-send` only through `NTFY_TOKEN_FILE`, and on stibnite the token's file is owned by `_otelcol` with mode `0400`, which the operator records after the activation

#### Scenario: stibnite posts without the token

- **WHEN** at acceptance an anonymous post to `fleet-acceptance` is sent from stibnite
- **THEN** ntfy refuses it with 403, while the wrapper's `FAILED otel-envelope on stibnite`, posted with the token, was accepted, and the operator records both

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that an alert reaches a person.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that the evaluator queries each rule's database as `regulator` on the path its language names, that the rules render from one source to the evaluator and to `promtool`, that instance state, freezes, presence watching, titles, priorities, heartbeats, the dead-man and its ping behave as the fixture check, its mutants, its property test and the recorded acceptance observations show, and that ntfy is configured with the stated access entries, provisioning and proxy settings

#### Scenario: A guarantee about ntfy's enforcement is sought

- **WHEN** someone asks whether these properties guarantee that ntfy refuses an anonymous `fleet-*` publish, rate-limits each client separately, or delivers a message to a subscribed device
- **THEN** the answer is no: ntfy enforces the access entries and rate limits and delivers to subscribed devices, and this machine only configures it, which R9.4's probe and the acceptance observations monitor

#### Scenario: A guarantee about the token's secrecy is sought

- **WHEN** someone asks whether only the evaluator, the dead-man, the notifier and stibnite's notifier wrapper can read the `alerter` token
- **THEN** the answer is no: any root process on a host holding a copy, magnetite, cinnabar, pyrite, electrum, galena, scheelite or stibnite, can read it, and on stibnite so can any process running as `_otelcol`, which also runs the agent collector

#### Scenario: A guarantee that a compromised laptop posts only its own notices is sought

- **WHEN** someone asks whether a compromised stibnite can post only its own failure notices
- **THEN** the answer is no: whoever reads stibnite's copy of the token can post to any `fleet-*` topic, alerts and heartbeats included, as whoever reads pyrite's copy can today, because ntfy grants the one `alerter` token every `fleet-*` topic and cannot tell which host posted; stibnite's copy also travels on a laptop that leaves the operator's premises, and it stays valid until the shared token is replaced

#### Scenario: A guarantee about an ntfy outage is sought

- **WHEN** someone asks whether an outage of cinnabar or its ntfy is reported
- **THEN** the answer is that the dead-man stops pinging healthchecks.io, which emails the operator once the check's period and grace pass; healthchecks.io evaluates the period and grace and sends the email, the operator's mail provider delivers it, and this machine only pings, so nothing reports the outage if healthchecks.io fails at the same time

#### Scenario: A guarantee about the watch's configuration is sought

- **WHEN** someone asks whether the check's period, grace and email integration are as the runbook states
- **THEN** the answer is no: they are set in healthchecks.io's web interface, not by this machine, and only the acceptance stops and later outages observe them

#### Scenario: A guarantee about the ping URL's secrecy is sought

- **WHEN** someone asks whether only the dead-man can send a ping that keeps the check up
- **THEN** the answer is no: the URL is a bearer credential, any root process on cinnabar can read it, and anyone holding it can keep the check up while the alert path is down

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that an alert reaches a person
- **THEN** the answer is no: each stage's configuration, the fixture check and the recorded acceptance observations behave as stated, and nothing here observes an alert or an email reaching a person's device

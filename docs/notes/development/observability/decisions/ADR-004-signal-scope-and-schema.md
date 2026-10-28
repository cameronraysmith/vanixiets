---
title: "ADR-004: Signal scope and schema"
---

## Status

Accepted (human gate, 2026-10-15)
Amended in place under charter v22 (2026-10-21), from slice S2's planning (`openspec/changes/stand-up-devloop-collection/`): the batch lifecycle admits the five exact gitea-mq messages rather than every line beginning `batch `, `devloop` rows restricted to the column allow-list are stored as OTLP log records with no message body, and the CI build timing row carries `pr_number` and `branch`.
Amended in place under charter v23 (2026-10-28), from slice S4's planning (`openspec/changes/stand-up-linux-fleet-collection/`): `observability-notify@` instances are excluded from the per-host cap of 40 `systemd_unit_name` values and bounded by the host's notified units, the `fleet` estimate counts S4's notifier instances, filesystem series and collector self-telemetry, 6,154 series against the unchanged 8,000, `systemd_unit_name`'s fleet-wide bound becomes 268, and R4.2 runs hourly in the ingress host's `otel-envelope`, with its journald-bytes and logs-table `ttl` clauses landing with S7.

## Context

Charter D4 asks which signals exist, how far they follow OpenTelemetry semantic conventions, and for an explicit cardinality and retention budget per consumer.
The development loop is the primary consumer and decides where the two consumers conflict (charter, Scope).
RK5 has fired: the schema must be an enumerated allow-list enforced at the collector, because every emitter-side content gate is an environment variable the collector cannot rely on (charter RK5; `research/telemetry-security-and-tenancy.md` F9).

Signals available without new emitter code:

- Fleet host metrics from the collector's `host_metrics` receiver: 17 metrics and 392 data points per scrape on stibnite (`research/otel-collector-topology.md` R10), estimated at 250 to 350 series per host (`research/otel-collector-topology.md` F41).
- Service metrics: gitea, niks3 and nixbot Prometheus endpoints, nginx `stub_status`, and zerotierone on every NixOS host (`research/fleet-emitter-inventory.md` C6 and updated emitter table).
- nixbot's series are status-labelled gauges only and never labelled by project (`research/dev-loop-signals.md` RF4).
- journald on NixOS, whose volume is unmeasured (`research/otel-collector-topology.md` Questions).
- gitea-mq batch lifecycle lines `batch formed`, `batch built`, `batch bisecting`, `batch landed` and `batch done` as `key=value` text in the journal (`research/dev-loop-signals.md` RF9).
- nixbot per-attribute rows in PostgreSQL, pruned after 90 days (`research/dev-loop-signals.md` RF2, RF3).
- omp OTLP metrics, spans and logs when an endpoint is set, with message content gated by `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT` and the log signal under no content gate (`research/dev-loop-signals.md` RF11).
- Omnigent OTLP, inert as packaged until the SDK and exporters are added (`research/dev-loop-signals.md` RF12, RC1).
- Host-level signals added on 2026-10-15, each tied to a failure this fleet has had (ADR-003 Context): per-process memory from the `host_metrics` `process` scraper, systemd unit state and restart counts from the contrib `systemd` receiver, ZFS pool state, ARC and the kernel `oom_kill` count from a loopback node_exporter, swap usage of the zram device from the `host_metrics` `paging` scraper, and NVMe health on pyrite from a loopback smartctl_exporter (ADR-003 items 16 to 19).
- No per-process or per-unit swap signal exists at the pinned collector: the `process` scraper's `process.memory.usage` is resident memory and the scraper defines no swap metric, and the `systemd` receiver defines only `systemd.service.cpu.time`, `systemd.service.restarts` and `systemd.unit.state` (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/hostmetricsreceiver/internal/scraper/processscraper/metadata.yaml:151-159`; `open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/systemdreceiver/metadata.yaml:43-78`).
- On magnetite, with `swappiness = 100`, resident memory was about 35 % of the evaluator's true footprint, and the zram pool is charged to no cgroup (`cameronraysmith/vanixiets@f55c27adb:docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:44-51`).
- Their darwin counterparts on stibnite, added the same day after the unnoticed exit 78 of `org.nixos.omnigent-host-cameron` there: bounded disk and APFS container metrics, per-process memory from a root `process` scraper, launchd job state and launch counts from a probe read through node_exporter's textfile collector, and NVMe health from the same probe (ADR-003 items 21 to 24).

omp's metric attributes are `gen_ai.operation.name`, `gen_ai.provider.name`, `gen_ai.request.model`, `gen_ai.response.service_tier`, `omp.gen_ai.agent.id` and `omp.gen_ai.agent.name` on every point, plus `gen_ai.token.type`, `gen_ai.response.finish_reason`, `gen_ai.tool.name`, `omp.tool.status` and `error.type` per instrument (`can1357/oh-my-pi@c2cb79e4c:packages/coding-agent/src/telemetry-export-otlp.ts:259-266`, `:296-315`).
Run-level points also carry five numeric `omp.agent.*.count` attributes that are spread into every tool-call and error point (`can1357/oh-my-pi@c2cb79e4c:packages/coding-agent/src/telemetry-export-otlp.ts:282-286`, `:300`).

All `gen_ai.*` conventions were moved out of `open-telemetry/semantic-conventions` into the separate `open-telemetry/semantic-conventions-genai` repository in v1.42.0 and are deprecated in the main repository (`open-telemetry/semantic-conventions@331541c40:CHANGELOG.md:114-122`).
The last main-repository definitions mark `gen_ai.input.messages` and `gen_ai.output.messages` as likely to contain sensitive information including PII, and `gen_ai.system_instructions`, `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result` and `gen_ai.retrieval.query.text` as possibly sensitive (`open-telemetry/semantic-conventions@331541c40:model/gen-ai/deprecated/registry-deprecated.yaml:805,830,1067,1098,1144,1212`).
Those content attributes and `gen_ai.tool.definitions` are `opt_in` on GenAI spans (`open-telemetry/semantic-conventions@331541c40:model/gen-ai/deprecated/spans-deprecated.yaml:126-133`).
omp emits exactly these names when content capture is on (`can1357/oh-my-pi@c2cb79e4c:packages/agent/CHANGELOG.md:1264`).

The cardinality hazard is unbounded label domains rather than volume: check names are closed at about 117 and machines at ten, whereas pull-request numbers, commit hashes, build ids and store paths grow without bound (`research/otel-collector-topology.md` F43).
GreptimeDB retention is a per-table `ttl` with a per-database default, and the metric engine's metadata region is pinned to `forever` (`research/greptimedb.md` F35, F36, R31).

## Decision

Collect a closed set of signals into three GreptimeDB databases, keep every attribute that is not on an enumerated allow-list out of the store, ban unbounded label domains from metrics, and retain dev-loop data longest.

Signal scope for the first deployment:

| Signal | Source | Consumer | Database |
|---|---|---|---|
| Host metrics, 60 s | `host_metrics` on every agent (ADR-003) | fleet | `fleet` |
| Service metrics, 60 s | gitea, niks3, nixbot, nginx, zerotierone (ADR-003) | fleet, dev-loop for nixbot aggregates | `fleet` |
| Unit logs | `journald` on NixOS, allow-listed units only | fleet | `fleet` |
| Per-process memory, 60 s | `process` scraper on NixOS agents and, through the root `otelcol-process`, on darwin agents, summed per executable, points below 64 MiB dropped (ADR-003) | fleet | `fleet` |
| systemd unit state and restarts, 60 s | `systemd` receiver on NixOS agents, allow-listed units only (ADR-003) | fleet | `fleet` |
| launchd job state, last exit code and launches, 60 s | `otel-host-probe` textfile through a loopback node_exporter on darwin agents, allow-listed jobs only (ADR-003) | fleet | `fleet` |
| ZFS pool state, ARC, OOM-kill count, 60 s | loopback node_exporter on NixOS agents (ADR-003) | fleet | `fleet` |
| Swap usage per swap device, 60 s | `host_metrics` `paging` scraper on NixOS agents (ADR-003 item 18) | fleet | `fleet` |
| NVMe health, 60 s | loopback smartctl_exporter on pyrite and `otel-host-probe` on stibnite (ADR-003) | fleet | `fleet` |
| Batch lifecycle | gitea-mq journal lines whose message is exactly `batch formed`, `batch built`, `batch landed`, `batch bisecting` or `batch done` (charter v22) | dev-loop | `devloop` |
| Per-attribute CI outcomes | nixbot rows read on magnetite (ADR-005) | dev-loop | `devloop` |
| Deploy records | `/var/log/deploy-record.jsonl` on every agent (ADR-005) | dev-loop | `devloop` |
| Agent-harness metrics | omp OTLP metrics `omp.agent.tool.calls` and `omp.agent.errors` | dev-loop | `agent` |

omp spans are admitted by this schema but are wired only when ADR-005 asks for them; omp OTLP logs are excluded (see ADR-008).
Omnigent telemetry is out of scope until its package carries the `tracing` extra; when added, it enters `agent` under the same allow-list.
Claude Code and hermes-agent are not emitters in this design.

Semantic-convention adherence:

1. Resource attributes follow the main OpenTelemetry semantic conventions: `service.name`, `service.version`, `host.name`, `host.arch` and `os.type`, with `host.name` stamped by the agent rather than trusted from the emitter.
2. Host metrics keep the `system.*` names the `host_metrics` receiver emits.
3. Prometheus-scraped metrics keep their native names; renaming them to conventions prevents no failure.
4. `gen_ai.*` names are accepted exactly as emitters send them and are allow-listed by exact key, with the `open-telemetry/semantic-conventions-genai` repository recorded as their reference; no attribute is renamed in the collector.
5. One non-convention resource attribute, `vanixiets.database`, is stamped by the agent to route to a database and removed by the ingress before export.
6. `process.*` and `systemd.*` metrics keep the names their receivers emit, node_exporter and smartctl_exporter metrics keep their native names, stibnite's probe writes SMART series under smartctl_exporter's names, and the first-party launchd metrics are named `launchd_job_*` in parallel with `systemd_unit_*`, because no convention or receiver names launchd state.
7. GreptimeDB's default translation stores OTLP names and keys with dots replaced by underscores and unit and `_total` suffixes appended, and the ingress promotes every allow-listed resource key to a label (ADR-003 item 15), so the names visible to PromQL are those listed below.

Attribute allow-list (single source of truth for the collector and for the regulator).
Key-level attribute redaction, `allow_all_keys: false`, applies only to the omp agent pipeline; Prometheus-scraped and `host_metrics` points keep their native label keys, bounded by the label bans and the per-label value cap below.

- Resource, every signal: `service.name`, `service.version`, `host.name`, `host.arch`, `os.type`; additionally `systemd.unit.name` on systemd receiver points and `process.executable.name` on process scraper points, including those `otelcol-process` forwards on darwin.
- omp metric names: exactly `omp.agent.tool.calls` and `omp.agent.errors`; every other omp metric, including token and cost metrics, is dropped (ADR-005 Q7).
- omp metric points: `gen_ai.operation.name`, `gen_ai.provider.name`, `gen_ai.request.model`, `gen_ai.response.service_tier`, `gen_ai.response.finish_reason`, `gen_ai.tool.name`, `omp.tool.status`, `omp.gen_ai.agent.name`, `error.type`.
- omp spans, when wired: the metric keys above plus `gen_ai.conversation.id`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens` and their cache variants.
- journald records: `MESSAGE` as the body, `_SYSTEMD_UNIT`, `PRIORITY` and `_HOSTNAME`; every other journal field is dropped.
- Prometheus-scraped and `host_metrics` points: their native label keys, not key-redacted, subject to the label bans below.
- Process scraper: metric `process.memory.usage` only, stored as `process_memory_usage_bytes{host_name, process_executable_name}`; the resource attributes `process.pid`, `process.parent_pid`, `process.command`, `process.command_line`, `process.executable.path` and `process.owner` are disabled at the source (ADR-003 item 16).
- systemd receiver: `systemd.unit.state` with point key `systemd.unit.active_state`, stored as `systemd_unit_state{host_name, systemd_unit_name, systemd_unit_active_state}`, and `systemd.service.restarts`, stored as `systemd_service_restarts_total{host_name, systemd_unit_name}`; `systemd.service.cpu.time` is disabled.
- node_exporter keep-list: `node_zfs_zpool_state` with labels `zpool` and `state`, `node_zfs_arc_size`, `node_zfs_arc_c`, `node_zfs_arc_c_min`, `node_zfs_arc_c_max`, `node_zfs_arc_hits`, `node_zfs_arc_misses`, `node_zfs_arc_memory_throttle_count` and `node_vmstat_oom_kill`; every other node_exporter series, including per-dataset `node_zfs_zpool_dataset_*`, is dropped.
- smartctl_exporter keep-list: `smartctl_device_smart_status`, `smartctl_device_critical_warning`, `smartctl_device_media_errors`, `smartctl_device_percentage_used`, `smartctl_device_available_spare`, `smartctl_device_available_spare_threshold`, `smartctl_device_num_err_log_entries` and `smartctl_device_temperature`, with labels `device` and `temperature_type`; `smartctl_device` and `smartctl_version` are dropped.
  stibnite's probe writes the same eight names from `smartctl -j -H -A disk0`, with `device="disk0"` and `temperature_type="current"`.
- launchd keep-list, darwin: `launchd_job_state{launchd_label, launchd_state}`, a gauge that is 1 for the job's current state and 0 for the others, with `launchd_state` one of `running`, `not_running`, `unloaded` and `other`; `launchd_job_last_exit_code{launchd_label}`, a gauge holding the last exit status, 0 when the job has never exited and -1 when the field is not an integer; and `launchd_job_runs_total{launchd_label}`, a counter of launches since the job was loaded; the PromQL-visible names are these.
- Textfile metadata, darwin: `node_textfile_mtime_seconds` with label `file` and `node_textfile_scrape_error`; every other node_exporter series on darwin is dropped.
- Prometheus scrape metadata: `up` is kept and `scrape_*` series are dropped for the node_exporter and smartctl_exporter targets on every host.
- Memory scraper: `system.linux.memory.available` is enabled on NixOS agents, stored as `system_linux_memory_available_bytes`.
- Paging scraper, NixOS agents: metric `system.paging.usage` only, stored as `system_paging_usage_bytes{host_name, device, state}`, with `state` one of `used` and `free` and `device` the `/proc/swaps` filename, `/dev/zram0` on every NixOS host; `system.paging.operations` and `system.paging.faults` are disabled (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/hostmetricsreceiver/internal/scraper/pagingscraper/metadata.yaml:38-68`; `open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/hostmetricsreceiver/internal/scraper/pagingscraper/pagefile_linux.go:17`, `:82`; `open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/hostmetricsreceiver/internal/scraper/pagingscraper/paging_scraper_others.go:90-98`).
- Darwin `disk` and `filesystem` scrapers: device `disk0` and mountpoint `/System/Volumes/Data` only, with `system.disk.io_time` and `system.disk.pending_operations` disabled (ADR-003 item 21).

`devloop` column allow-list, per signal, using ADR-005's field names; any other column is dropped:

| Signal (ADR-005) | Columns | Primary key | Time index |
|---|---|---|---|
| CI attribute outcome | `build_id`, `attr`, `system`, `status`, `cached`, `abandoned`, `drv_path`, `outputs.out`, `started_at`, `finished_at`, `eval_wall_ms`, `eval_alloc_bytes`, `commit_sha`, `branch`, `pr_number`, `project` | `(build_id, attr)` | `finished_at` |
| CI build timing | `build_id`, `created_at`, `started_at`, `finished_at`, `eval_duration_ms`, `status`, `pr_number`, `branch` (charter v22) | `(build_id)` | `finished_at` |
| Merge-queue batch event | `batch`, `msg` (the event name), `build`, `sha`, `failed_check`, `members`, `landed`, `ejected`, `builds`, `flaky` | `(batch, msg)` | journal timestamp |
| Deploy record | `host`, `closure`, `previous_closure`, `ts` | `(host)` | `ts` |

Explicitly never stored, whatever their source: `gen_ai.input.messages`, `gen_ai.output.messages`, `gen_ai.system_instructions`, `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result`, `gen_ai.tool.definitions`, `gen_ai.retrieval.query.text`, `gen_ai.prompt`, `gen_ai.completion`, `exception.message`, `exception.stacktrace`, span status messages, `user.email`, `user.id`, `user.account_uuid`, `user.account_id`, and any OTLP log record other than a `devloop` row (charter v22).
A `devloop` row is an OTLP log record restricted to the column allow-list above and carrying no message body, so the journald `MESSAGE` of a gitea-mq line is dropped once parsed and the nixbot queries select no `error` text (charter v22).
This list documents intent; enforcement is the allow-lists, so on the omp pipeline, in journald records and in `devloop` rows a key absent from its list is dropped.

journald unit allow-list: `gitea`, `gitea-mq`, `nixbot*`, `niks3*`, `nix-daemon`, `nix-grpc-daemon`, `harmonia-gc`, `postgresql`, `nginx`, `greptimedb`, `opentelemetry-collector`, `zerotierone`.
Never on the list: `omnigent*`, `omnigent-host-*`, `omnigraph`, `user@*`, and session scopes, because their output can carry agent or user content.
systemd unit allow-list, `.service` units only: the journald allow-list above, `omnigent-host-*`, `omnigraph`, `otel-envelope`, `devloop-reconcile`, `greptimedb-envelope`, `greptimedb-export`, `greptimedb-schema`, `prometheus-node-exporter`, `prometheus-smartctl-exporter`, `zfs-assert-*` and `zfs-set-*`.
Unit state carries no journal content, so `omnigent*` units are on this list while staying off the journald list; journald collection is unchanged by the host-level signals.
`zfs-assert-*` and `zfs-set-*` cover magnetite's six existing dataset-property oneshots and ADR-007's three `greptimedb` ones (`cameronraysmith/vanixiets@f55c27adb:modules/machines/nixos/magnetite/default.nix:193-263`; ADR-007), whose failure would otherwise leave a quota or reservation unenforced with nobody told; each also sets `OnFailure=observability-notify@%n.service` (ADR-003, ADR-007).
Each `omnigent-host-<owner>.service` name is rewritten to `omnigent-host-<alias>.service` from an explicit owner-to-alias attrset in `schema.nix`, so no owner's name becomes a label value and adding or removing an owner never renames another owner's series (ADR-003 Q12).
launchd job allow-list, darwin, by label: `org.nixos.nix-daemon`, `org.nixos.nix-grpc-daemon`, `org.nixos.harmonia-gc`, `org.nixos.nix-cleanup-gcroots`, `org.nixos.sops-install-secrets`, `org.nixos.dnscrypt-proxy`, `org.nixos.otelcol`, `org.nixos.otelcol-process`, `org.nixos.prometheus-node-exporter` and `org.nixos.omnigent-host-*`; each host's probe reads the labels on this list that its evaluated `launchd.daemons` defines.
The probe writes each `org.nixos.omnigent-host-<owner>` label as `org.nixos.omnigent-host-<alias>` from the same owner-to-alias attrset.
A job is expected to run continuously when its evaluated `serviceConfig.KeepAlive` is `true`, and `schema.nix` renders that set for ADR-009's not-running rule; jobs with conditional or no `KeepAlive` are judged by exit code and launches only.

Metric label bans: pull-request number, commit SHA, derivation or store path, build id, `gen_ai.conversation.id`, `session.id`, trace or span id, `omp.gen_ai.agent.id`, the five `omp.agent.*.count` attributes, any person identifier, `process.pid`, `process.parent_pid`, `process.command`, `process.command_line`, `process.executable.path`, `process.owner`, a launchd job's `pid`, smartctl's `serial_number`, zerotierone's per-peer `node_id`, and filesystem mountpoints under `/Volumes/` or `/private/var/folders/`.
Process command lines are banned because they can carry secrets passed as arguments and agent prompt content, and the other process keys are banned because a pid changes on every restart, so a restart-looping unit would mint one series per restart.
These may appear as span or log-row columns in `devloop` and `agent`, where they do not create series.

Budget per consumer:

| Consumer | Database | Cardinality envelope | Volume envelope | Retention |
|---|---|---|---|---|
| Fleet | `fleet` | at most 8,000 active series; at most 200 distinct values per label key per metric, except `process_executable_name`, bounded instead by 30 values per agent host (Q10), and `systemd_unit_name`, bounded instead by 40 values per NixOS agent host (Q12) plus that host's `observability-notify@` instances; per host at most 30 `process_executable_name` values, 40 `systemd_unit_name` values other than `observability-notify@` instances, at most one `observability-notify@` instance per unit in the host's `services.observability-notify.units`, and 30 `launchd_label` values (charter v23) | journald at most 100 MB per host per day, provisional | metrics 30 d; logs table 14 d |
| Dev-loop | `devloop` | no metric series; rows only | at most 100,000 rows per day | 365 d |
| Agent harness | `agent` | at most 2,000 active series; `gen_ai.tool.name` at most 200 values | at most 200,000 span rows per day when spans are wired | 90 d |

Retention beyond 365 d for dev-loop data is the Parquet export path of ADR-006, not in-store history.

## Rationale

The scope is what already emits or is already persisted, so the first deployment routes signals instead of authoring them (`research/dev-loop-signals.md` Bearing on D5; `research/fleet-emitter-inventory.md` Bearing on D4).
An allow-list rather than a deny-list is required because new content-bearing keys appear without notice, as the move of `gen_ai.*` to a separate repository shows, and a deny-list fails open on every key it does not name.
Keeping native names for scraped metrics avoids a rename layer whose only output would be different names.
Dev-loop data gets the longest retention because it is the primary consumer and its volume is small: under 60,000 check outcomes per day at the measured evaluation ceiling (`research/otel-collector-topology.md` F42), and nixbot prunes its own rows at 90 days, so the store is the only place longer CI history can live (`research/dev-loop-signals.md` RF3).
Fleet metrics at 30 d cover the incident-review windows recorded so far; fleet logs at 14 d bound the one signal whose volume is unmeasured.
Agent-harness data at 90 d covers planning-unit sizing over a quarter, while limiting how long a personal activity record persists (`research/telemetry-security-and-tenancy.md` Q6).
Banning unbounded domains from metric labels is the single rule that keeps the budget satisfiable in one store, so RK4 does not fire (`research/otel-collector-topology.md` Bearing on D4).
`omp.gen_ai.agent.id` and the `omp.agent.*.count` attributes are dropped because the first is per-instance and the second multiplies every tool series by run shape while feeding no decision in ADR-005.
The fleet envelope was 6,000 series: the measured 392 points per host at seven hosts plus service endpoints, with headroom.
The host-level signals add, per NixOS host, at most 30 process series, at most 40 units at nine series each (eight `systemd_unit_state` states plus one restart counter), 7 pool-state series for the single pool `zroot`, 7 ARC series, 1 `oom_kill` series, 1 `up` series, 1 memory-available series and 2 paging series for the one zram device, which is 30 + 360 + 7 + 7 + 1 + 1 + 1 + 2 = 409.
The unit cap is 40 rather than 30 because magnetite reaches 30 allow-listed units once these decisions land: 19 matched its evaluated configuration at `cameronraysmith/vanixiets@f55c27adb` (six of them `zfs-assert-*` and `zfs-set-*`), and ADR-003, ADR-005 and ADR-007 add `opentelemetry-collector`, `prometheus-node-exporter`, `otel-envelope`, `devloop-reconcile`, `greptimedb`, `greptimedb-schema`, `greptimedb-export`, `greptimedb-envelope` and three `greptimedb` dataset oneshots, so one further Omnigent owner would breach a cap of 30.
`observability-notify@` instances count outside the cap of 40 and are bounded instead by the host's notified units, because they pass the allow-list so that `SystemdUnitFailed` reports a failed post (charter v21), and magnetite stored 44 `systemd_unit_name` values on 2026-10-27, 16 of them notifier instances (charter v23).
pyrite adds 10 more for smartctl: 7 single-series metrics and `smartctl_device_temperature` with up to 2 `temperature_type` values on one controller, plus 1 `up`.
Six NixOS hosts therefore add 5 × 409 + 419 = 2,464 series, and the budget rises from 6,000 to 8,000.
stibnite's base host metrics are already inside the 392 points per host counted above, and item 21's device and mountpoint bounds only shrink them; darwin agents collect no paging series (ADR-003 item 25).
Its host-level signals add at most 30 process series, at most 30 jobs at six series each (four `launchd_job_state` states, one exit code and one launch counter), 8 SMART series for `disk0`, 2 `node_textfile_mtime_seconds` series for `launchd.prom` and `smartctl.prom`, 1 `node_textfile_scrape_error` series and 1 `up` series, which is 30 + 180 + 8 + 2 + 1 + 1 = 222.
The estimated base of 3,000 plus 2,464 plus 222 is 5,686 series before slice S4's additions.
S4 adds at most 9 series per `observability-notify@` instance for the 28 units notified fleet-wide, 252; 3 `system_filesystem_usage_bytes` series, `used`, `free` and `reserved`, per ZFS mountpoint, 7 mountpoints on magnetite and 3 on each other NixOS host, 66; and the collector self-telemetry keep-list, at most 50 series on magnetite and 20 on each other NixOS host, 150 `[INFERENCE: counted from the rendered exporters and receivers]` (charter v23).
The estimate is therefore 3,000 + 2,464 + 222 + 252 + 66 + 150 = 6,154 series, inside the 8,000 budget with 1,846 to spare; each further consenting darwin host would add at most 222 plus its own base of about 392.
The per-host cap of 30 keeps `launchd_label` at no more than 30 values on stibnite, inside the 200-value cap.
`systemd_unit_name` could reach 6 × 40 + 28 = 268 values, 40 per NixOS agent host plus the 28 units notified fleet-wide, if no unit name were shared between hosts, and `process_executable_name` 7 × 30 = 210, both above the 200-value cap, so their fleet-wide bounds are the per-host caps times the number of agent hosts, plus each NixOS host's notified units for `systemd_unit_name` (Q10, Q12; charter v23).
Swap is collected per host rather than per process because no pinned receiver attributes it lower: `system_paging_usage_bytes` with `state="used"` is the uncompressed size of the pages swapped out to zram, read from the `Used` column of `/proc/swaps`, and with `system_linux_memory_available_bytes` it is the memory-pressure input ADR-009 consumes.
The RAM that zram's compressed pool occupies is not exported by any pinned collector, because node_exporter at `prometheus/node_exporter@6044da783` has no zram collector (`collector/` contains only the `swap` collector's `/dev/zram0` fixture), and that RAM is already absent from available memory `[INFERENCE: zram's zsmalloc pages are not reclaimable, so the kernel's MemAvailable excludes them]`.

## Rejected alternatives

- Deny-list redaction: fails open on any content key not yet named.
- Renaming scraped metrics to semantic conventions: adds a transform layer that prevents no failure.
- Collecting every journald unit: omnigent worker units write agent output to the journal.
- One retention for all data: either discards dev-loop history at the fleet horizon or keeps unmeasured fleet logs for a year.
- Unlimited retention for dev-loop data in the store: unbounded growth on magnetite's local caches and R2, when ADR-006 already provides a Parquet path.
- Separate store for dev-loop telemetry: the budget is satisfiable in one store once metric labels are bounded (RK4 not confirmed).
- Collecting omp OTLP logs through a redaction stage: the log signal has no emitter-side content gate and string bodies defeat the redaction processor (see ADR-008).
- Person identifiers as attributes: no decision in ADR-005 needs them, and they make the store a personal-activity record.
- Admitting `process.command_line` or `process.pid` under a redaction stage: a command line is content that a redaction pattern cannot enumerate, and a pid mints a series per restart; disabling them at the source keeps them out of collector memory.
- Verbatim `omnigent-host-<owner>` unit names: each owner's name becomes a label value in `fleet` (ADR-003 Q12).
- Reusing `systemd_unit_state` and `systemd_service_restarts_total` for launchd jobs: launchd's states and launch counter differ in meaning from systemd's, so one name would put incomparable series under one rule.
- Lowering the per-host process cap to 28 so that seven hosts fit under 200 values: it shrinks every NixOS host's attribution to admit stibnite, and fails again when a further darwin host consents.

## Consequences

The collector configuration and the regulator read one allow-list file, so widening the schema is a reviewed change to that file.
Any new emitter attribute is dropped until added, which can hide a useful field until someone notices its absence.
Failure classes for omp come only from `error.type`, and Omnigent tool failure classes remain unavailable under its content-safe configuration (`research/dev-loop-signals.md` RF12).
Per-person cost attribution is not possible from the store; attribution is per host and per service.
The metric engine's metadata region and pipeline table never expire (`research/greptimedb.md` F36), so the store is not fully self-expiring.
The journald volume envelope is provisional until a week of measurement exists (Q4).
Process executable names are set by the running program, so a worker can choose them; the 64 MiB floor, the per-host cap of 30 values and R4.2 bound what that admits.
Per-process attribution is by resident memory only, so a process's swapped-out pages are missing from its `process_memory_usage_bytes` series, and a swap-heavy evaluator on magnetite can show about a third of its true footprint; swap pressure is visible only per host, through `system_paging_usage_bytes`, and per-unit memory waits on a pin at or past `v0.160.0` (ADR-003 Q11), whose cgroup figures would still omit the uncharged zram pool.

## Operating envelope and regulator

Envelope: the budget table above, plus the rule that every stored attribute key is on the allow-list.

Regulator R4.1, deterministic, build time: the flake check `checks.x86_64-linux.otel-redaction` defined in ADR-008 also feeds fixtures carrying a banned metric label, an unknown attribute key, an `omp.agent.*.count` attribute, a journald record from `omnigent-host-cameron`, a process resource carrying `process.command_line` and `process.pid`, a `systemd.unit.name` of `omnigent-host-cameron.service`, a `launchd_job_state` series labelled `org.nixos.omnigent-host-cameron`, a `filesystem` point with a `/Volumes/` mountpoint, and a `smartctl_device` series with `serial_number`, and asserts that the output contains only allow-listed keys and names, no record from a non-listed unit, and no owner name in any unit or job label.
It also fails evaluation when an enabled Omnigent worker has no entry in the owner-to-alias attrset.
It reads the same `schema.nix` file the collector configuration is generated from, so configuration and check cannot diverge.
It is shown able to fail at acceptance by deleting the label-ban stage from the generated configuration and observing the banned label in the output.

Regulator R4.2, runtime: the ingress host's instance of ADR-003's `otel-envelope`, which alone holds `regulator-password`, additionally queries each hour, per database, active series, the maximum distinct values of any label key per metric, per host the distinct values of `process_executable_name`, `systemd_unit_name` and `launchd_label` and the stored `observability-notify@` instances, and rows ingested in the last 24 h, and fails when any bound in the budget table is breached or a query returns an empty result or a missing table (charter v23).
The journald-bytes clause and the fleet logs table's `ttl` comparison have no input until S7 creates that table, and land with it (charter v23).
It is shown able to fail at acceptance by pushing one synthetic metric with 300 distinct values of one label into `fleet` and observing the unit fail.
A failed `otel-envelope` unit reaches a human through ADR-003's `OnFailure=observability-notify@%n.service` notifier; the systemd unit-state and launchd job series in `fleet` are a stored signal, and alerting over them belongs to ADR-009.
TTLs are asserted, not only set: ADR-007's `greptimedb-schema` oneshot enforces them, and R4.2 also compares each database's `ttl` option, and from S7 the fleet logs table's, against this table.

## Failure prevented

- Attribute allow-list: prompt, tool, or repository content reaches a store every admitted reader can query (RK5).
- journald unit allow-list: worker output written to the journal reaches the store through a path the attribute allow-list does not cover.
- Metric label bans: a series explosion consumes store memory on a host that has already been OOM-killed (RK3).
- Per-database retention: dev-loop history is lost at nixbot's 90-day prune, or fleet logs grow without bound.
- Single schema file: the regulator tests a different allow-list from the one deployed.
- R4.1: a configuration change that admits a banned label or a content key ships.
- R4.2: an emitter upgrade introduces an unbounded label, or a TTL drifts, with nobody told.
- Process attribute bans: a command line carrying a secret or prompt content reaches the store, or a restart-looping unit mints a new series on every restart.
- Per-host value caps: an unexpected set of large executables or a widened unit pattern pushes `fleet` past its series budget.
- Owner-to-alias attrset: a person's name enters `fleet` as a unit or launchd job label value.
- launchd job allow-list and names: a darwin job's failure is invisible to the store, or every launchd job on a host enters `fleet` and crowds out its budget.
- Mountpoint bans on darwin: a mounted application's name or a user's temporary-directory path becomes a label value.

## Implementation surface

- Add `modules/clan/services/otel-collector/schema.nix`: attribute allow-list, omp metric-name allow-list, per-signal `devloop` column allow-list with each table's primary key and time index, never-stored list, journald unit allow-list, systemd unit allow-list, launchd job allow-list, Omnigent owner-to-alias attrset, node_exporter, darwin textfile and smartctl_exporter metric keep-lists, the enabled `paging` and memory scraper metrics, metric label bans, signal-to-database map, and the budget numbers used by R4.2.
- Modify the collector configuration generated by `modules/clan/services/otel-collector/flake-module.nix` (ADR-003) to build `redaction`, `filter`, `transform` and `resource` stages from `schema.nix`.
- Modify `modules/checks/otel-redaction.nix` (ADR-008) to add the R4.1 fixtures.
- Add the R4.2 queries to the ingress host's instance of ADR-003's `otel-envelope`, run hourly, with the journald-bytes and logs-table `ttl` queries landing with S7 (charter v23).
- Consumed, not created here: the `greptimedb-schema` oneshot in `modules/nixos/greptimedb.nix` (ADR-007) creates `fleet`, `devloop` and `agent` with the database TTLs in the budget table and sets the fleet logs table TTL to 14 d, declared in `services.greptimedb.tableTtls` (charter v15).
- No flake input and no clan vars generator is added by this decision.

## Questions for the human gate

1. Q1: Is the dev-loop in-store retention 365 d? Recommended: yes; shorter loses year-over-year comparison, longer grows store caches without a named decision.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
2. Q2: Are person identifiers excluded from the store entirely? Recommended: yes; keeping them enables per-person cost attribution and makes the store a personal-activity record readable by every admitted reader.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
3. Q3: Are omp spans in scope for the first deployment? Recommended: no, metrics only, per ADR-005; enabling them adds `gen_ai.conversation.id` rows to `agent` under the same allow-list.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
4. Q4: Is the 100 MB per host per day journald envelope accepted as provisional pending one week of measurement? Recommended: yes; the alternative is deferring the log leg until measured.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
5. Q5: Should Omnigent's package gain its `tracing` extra so its metrics enter `agent`? Recommended: defer to ADR-008, under which no omnigent worker account receives an OTLP endpoint or credential in this slice; until ADR-008 is revised Omnigent contributes nothing.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
6. Q6: Is agent-harness retention 90 d? Recommended: yes; longer keeps a personal-activity record longer than any listed decision needs.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
7. Q7: Should the allow-list admit `omp.gen_ai.agent.name`? Recommended: yes, it is bounded by the agent roster; dropping it loses the per-subagent breakdown of tool calls and errors.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
8. Q8: Raise the `fleet` active-series budget from 6,000 to 8,000 for the host-level signals? Recommended: yes, per the per-host arithmetic in Rationale, which with stibnite's 222 series reaches about 5,686 and leaves 2,314 of headroom; the alternative keeps 6,000 and leaves about 314 series of headroom over the estimated 3,000 base plus 2,464 plus 222.
   Resolution: recommended answer accepted at the 2026-10-15 gate; under charter v23 S4's notifier instances, filesystem series and collector self-telemetry raise the estimate to 6,154 series, leaving 1,846 of headroom under the unchanged 8,000 (Rationale).
9. Q9: Admit `process.executable.name` as a label? Recommended: yes, bounded by the 64 MiB floor and a cap of 30 values per host; dropping it leaves a per-host total that cannot say which process grew.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
10. Q10: Bound `process_executable_name` fleet-wide by 30 values per agent host, 210 at seven hosts, instead of the general 200-value cap? Recommended: yes, because the key is already capped per host and its worst case grows only with consenting hosts; the alternative lowers every host's cap to 28 now and again at each new darwin host.
    Resolution: recommended answer accepted at the 2026-10-15 gate.
11. Q11: Name the darwin job metrics `launchd_job_state`, `launchd_job_last_exit_code` and `launchd_job_runs_total` with labels `launchd_label` and `launchd_state`? Recommended: yes, parallel to the systemd names without sharing them; the alternative reuses `systemd_*` names for series with different meanings.
    Resolution: recommended answer accepted at the 2026-10-15 gate.
12. Q12: Raise the per-host `systemd_unit_name` cap from 30 to 40 and bound the key fleet-wide by 40 values per NixOS agent host, 240 at six hosts, instead of the general 200-value cap? Recommended: yes, because magnetite reaches exactly 30 allow-listed units with the dataset oneshots and this design's own units, and each unit costs nine series; the alternative keeps 30 and drops the zfs oneshots from the allow-list, leaving their failures visible only through `OnFailure=`.
    Resolution: recommended answer accepted at the 2026-10-15 gate; under charter v23 the fleet-wide bound adds each NixOS host's notified units, 240 + 28 = 268 at S4, because `observability-notify@` instances count outside the per-host cap of 40 (Rationale).

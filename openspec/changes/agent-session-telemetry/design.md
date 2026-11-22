## Context

The fleet's telemetry store is GreptimeDB 1.2.1 on magnetite (`pkgs/by-name/greptimedb-bin/package.nix`), fed only by magnetite's collector, the ingress, which receives every other agent host's signals over mTLS (`modules/clan/services/otel-collector/README.md`).
It declares three databases, `fleet` (30 d), `devloop` (365 d) and `agent` (90 d) (`modules/clan/services/otel-collector/schema.nix:276-282`); nothing writes to `agent`.
No harness exports today: Claude Code is not an emitter (ADR-004:69), no NixOS agent has a loopback OTLP receiver, and ADR-008 refuses every OTLP log record from loopback and stores no content (ADR-008:61-70).

Agent sessions run on magnetite and pyrite as the human user `cameron` (herdr panes and terminals, `homeManager.ai`) and as the omnigent workers `omnigent-cameron` and `omnigent-janettesmith` (`homeManager.omnigent-worker`, `modules/nixos/omnigent-host.nix:335-350`; owners in `modules/clan/inventory/services/omnigent.nix:64-103`).

On 2026-11-22 the operator decided (brainstorm.md): record every such session, content included, readable by every store reader under an organisational model, with the group's consent; keep 30 days; Claude Code and omp first; no traces, no cloud sessions, no Langfuse, stibnite later.
The store cannot isolate a database from any read-only account (`GreptimeTeam/greptimedb@v1.2.1:src/auth/src/permission.rs:320-353`, `src/auth/src/user_provider/static_user_provider.rs:75-83`; world assumption A188), which is why the operator's choice is between shared content and no stored content, not a private database.

Stakeholders: the operator (decides, reads), Janette (her workers' sessions are recorded, consent stated by the operator, A189), every holder of a store reader (`perses`, `regulator`).

## Goals / Non-Goals

**Goals:**
- Every Claude Code and omp session on magnetite and pyrite, human or worker, reaches `agent`: Claude Code's metrics and events, omp's two admitted metrics.
- Prompts, responses and tool details are stored as event columns with word search; tool output, raw API bodies, account identifiers and record bodies never leave the host.
- What leaves the host is decided by one allow-list, enforced fail-closed at the collector and again by the store's pipeline.
- 30-day retention, a bounded series count, stated outage holds, and a VM test with a canary before any host deploys.

**Non-Goals:**
- Traces (1.2.1 lacks `greptime_trace_v2`, ADR-001:35; `modules/checks/otel-collector-config.nix:337-341` forbids `traces*` pipelines). omp's content lives only on spans, so it arrives with the traces follow-up.
- stibnite: its `127.0.0.1:4318` receiver already feeds `fleet` from `otelcol-process` (`modules/lib/otel-collector-darwin.nix:128-129,308`); moving it is a darwin change for the operator's console deploy.
- Claude's cloud sessions, claude-sandbox, the `claude-glm` and `claude-cerebras` wrappers, Langfuse, a public endpoint, omnigent's own telemetry (ADR-005 Q5).
- Per-reader isolation of content (impossible at 1.2.1, A188).

## Decisions

Each decision names the boundary it sits on where it touches vendored-versus-first-party (upstream Claude Code, omp, omnigent, GreptimeDB, the contrib collector) or source-versus-delivered (Nix source against the activated file or running config).

### D2: Emitter gates (operator content decision)
- **Choice**: Claude Code: `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_METRICS_EXPORTER=otlp`, `OTEL_LOGS_EXPORTER=otlp`, `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318`, `OTEL_LOG_USER_PROMPTS=1`, `OTEL_LOG_ASSISTANT_RESPONSES=1`, `OTEL_LOG_TOOL_DETAILS=1`, `OTEL_METRICS_INCLUDE_ACCOUNT_UUID=false`, `OTEL_RESOURCE_ATTRIBUTES=user.name=<person>`. Unset: `OTEL_LOG_TOOL_CONTENT`, `OTEL_LOG_RAW_API_BODIES`, `OTEL_TRACES_EXPORTER`, `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA`, `ENABLE_BETA_TRACING_DETAILED`, `BETA_TRACING_ENDPOINT`, `OTEL_RESOURCE_INCLUDE_HOST`. omp: `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://127.0.0.1:4318/v1/metrics` and no generic or traces endpoint, `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_LOGS_EXPORTER=none`, `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=full`, `OTEL_RESOURCE_ATTRIBUTES=user.name=<person>`.
- **Rationale**: the operator's gates (brainstorm.md). Claude's `tool.output` exists only on trace spans and raw bodies only as `api_request_body`/`api_response_body` events (`claude-code-docs/…/monitoring-usage.md:127-129,322-347,969-991`), so leaving their gates and traces off keeps them from being produced. `OTEL_METRICS_INCLUDE_ACCOUNT_UUID=false` removes the account ids at the source as well (`:156`); `user.email` and `organization.id` have no switch (`:631,:1851`) and are removed by the collector (D3). omp's `summary` level would carry truncated tool results (`oh-my-pi …/agent/src/telemetry.ts:807-831`), so `full` is set and, with no traces endpoint, nothing content-bearing is exported in phase 1; omp exports a signal only when that signal has an endpoint (`telemetry-export.ts:79-85`). `OTEL_RESOURCE_INCLUDE_HOST` would add `host.id`, the machine id (`:163-180`); the collector stamps `host.name` instead.
- **Delta temporality (D7 dropped)**: Claude's default `delta` is kept. Claude metrics carry no per-process identity but `session.id` (`:623-638`), which D3 removes; under `cumulative`, concurrent sessions would interleave different running totals in one series. Deltas summed across sessions are the right aggregate; query with `sum`/`sum_over_time`, not `rate`, since the store keeps deltas raw (`…@v1.2.1:src/servers/src/otlp/metrics.rs:566`).
- **Boundary**: vendored. These are upstream switches whose meaning is world assumptions A190 and A191; a renamed gate fails safe, because the collector's allow-list (D3) admits only listed keys.
- **Alternatives**: `summary` for omp (rejected: tool results); `cumulative` (rejected above); shell exports (rejected: herdr and omnigent environments differ, settings files reach every launch path).

### D3: Fail-closed enforcement at the collector, loopback path only
- **Choice**: a receiver `otlp/local` on `127.0.0.1:4318` feeds two pipelines, nothing else:
  - `metrics/agent-session`: `memory_limiter` → `filter/agent-session-service` (drop unless `resource.attributes["service.name"]` is `claude-code` or `oh-my-pi`) → `filter/agent-session-metrics` (drop any metric not named on the allow-list: the eight `claude_code.*` metrics, `omp.agent.tool.calls`, `omp.agent.errors`) → `transform/agent-session-metrics` (`keep_keys` on datapoint attributes to the metric key allow-list, which excludes `session.id`, `prompt.id`, `user.id`, `user.email`, `user.account_uuid`, `user.account_id`, `organization.id`, `terminal.type`; `keep_keys` on resource attributes to `service.name`, `service.version`, `host.arch`, `os.type`, `user.name`) → `resource/agent-session` (upsert `host.name`, set `vanixiets.database=agent`) → the agent export.
  - `logs/agent-session`: `memory_limiter` → `filter/agent-session-service` (`claude-code` only) → `filter/agent-session-events` (drop unless `attributes["event.name"]` is on the event allow-list) → `transform/agent-session-events` (per event, `keep_keys(log.attributes, <that event's keys>) where log.attributes["event.name"] == "<event>"`; set the body to the empty string; resource `keep_keys` as above) → `resource/agent-session-events` (upsert `host.name`, set `vanixiets.database=agent`, `vanixiets.table=session_event`) → `otlp_http/ingress-agent` (or `forward` on magnetite).
  - No `traces*` pipeline takes `otlp/local`, so the receiver answers trace exports with an error and stores nothing.
- **Event allow-list** (from `monitoring-usage.md:822-1470`): `user_prompt`, `assistant_response`, `tool_result`, `tool_decision`, `api_request`, `api_error`, `api_refusal`, `api_retries_exhausted`, `compaction`, `subagent_completed`, `skill_activated`. Every key kept is named per event: the correlation keys (`event.name`, `event.sequence`, `session.id`, `prompt.id`, `message.uuid`, `request_id`, `agent_id`, `parent_agent_id`), and per event its own keys, for example `user_prompt`: `prompt`, `prompt_length`, `command_name`, `command_source`; `assistant_response`: `response`, `response_length`, `model`, `query_source`; `tool_result`: `tool_name`, `tool_use_id`, `success`, `duration_ms`, `error_type`, `error`, `decision_type`, `decision_source`, `tool_input_size_bytes`, `tool_result_size_bytes`, `tool_parameters`, `tool_input`; `api_request`: `model`, `cost_usd_micros`, `duration_ms`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`, `query_source`, `speed`, `effort`. `prompt_text` (a duplicate of `prompt`, `:832`) is not kept. Dropped by not being listed: `api_request_body`, `api_response_body`, `system_prompt`, the hook, plugin, MCP-connection, auth and settings events, and every key a future release adds.
- **Rationale**: ADR-008 requires fail-closed key allow-lists at the collector (item 5, stage 2; `:61,:66`) and says emitter gates are not enforcement (`:72`); the human `settings.json` is a writable copy (`modules/home/ai/claude-code/default.nix:414-423`) and omp lets a shell export override its `.env`, so one edit could turn on tool content. The `redaction` processor does not protect string bodies (ADR-008:42), so the body is overwritten, not redacted. Only `claude-code` may send events because omp's log records are ungated (`omp.log`, ADR-008:40).
- **Boundary**: vendored (contrib 0.155.0's `filter` and `transform` processors and OTTL) configured from first-party source; the delivered configuration is what `otel-collector-config` evaluates and the VM test runs.
- **Alternatives**: a key deny-list (rejected: fails open on new keys); `redaction` with `allowed_keys` (kept for omp metrics per ADR-008 stage 2 where it already applies; it cannot express per-event key sets or bodies); the darwin-style shared receiver routed by `service.name` (rejected, D8).

### D4: Identity (operator decision, superseding aliases)
- **Choice**: the emitter stamps `user.name` with the person a session runs for: `config.home.username` for a human home (`cameron`), the worker's `owner` for a worker home (`cameron`, `janettesmith`), passed into the worker home beside `vcs.author` (`modules/nixos/omnigent-host.nix:343`). The collector stamps `host.name` and deletes every other identity key (D3).
- **Rationale**: the operator's identity rule; the collector cannot tell which local account posted to loopback (A194), so the person comes from the emitter's own configuration. The worker's Unix account (`omnigent-janettesmith`) is not used, because the decision names people.
- **Trade-off**: `user.name` is self-asserted; any local process can post as anyone (A194). Accepted under the organisational model; stated in the interface trust boundary.

### D5: Store: `agent`, 30 d, one events table through a version-2 VRL pipeline
- **Choice**: `schema.nix` `databases.agent = "30d"`; the schema job's existing `CREATE DATABASE IF NOT EXISTS` + `ALTER DATABASE … SET 'ttl'` applies it (`modules/nixos/greptimedb.nix:91-96`; the database option is `ttl`, `…@v1.2.1:src/common/meta/src/key/schema_name.rs:37,:85-97`). One table `agent.session_event`, declared in `schema.nix` as `agentSession.tables.session_event` and rendered, like devloop, by a renderer shared with `modules/nixos/devloop-collection.nix:30-153`:
  - DDL through `services.greptimedb.tables.agent`: every column double-quoted; time index `ts` from the record's `Timestamp` (`TIMESTAMP(6)`, the devloop `recordTimestamps` path); primary key `(host_name, session_id, event_sequence)`; `append_mode='false'`, `sst_format='flat'`, no table `ttl`; `prompt` and `response` as `STRING NULL FULLTEXT INDEX WITH (analyzer = 'English', case_sensitive = 'false', backend = 'bloom')`.
  - Columns: `ts`, `host_name`, `user_name`, `service_name`, `service_version`, `session_id`, `prompt_id`, `event_name`, `event_sequence`, `message_uuid`, `request_id`, `agent_id`, `parent_agent_id`, `model`, `query_source`, `prompt`, `prompt_length`, `command_name`, `command_source`, `response`, `response_length`, `tool_name`, `tool_use_id`, `success`, `duration_ms`, `error_type`, `error`, `decision`, `decision_type`, `decision_source`, `source`, `tool_input_size_bytes`, `tool_result_size_bytes`, `tool_parameters`, `tool_input`, `cost_usd_micros`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`, `status_code`, `attempt`. Types are the renderer's four (`int64`, `string`, `boolean`, `timestamp`); `cost_usd` (a float) is replaced by `cost_usd_micros`.
  - Pipeline `agent_session_event` through `services.greptimedb.pipelines.agent`, uploaded as admin to `/v1/pipelines/agent_session_event?db=agent` (`modules/nixos/greptimedb.nix:116-147`; route `…@v1.2.1:src/servers/src/http.rs:1281-1300`, multipart handler `src/servers/src/http/event.rs:293-325`): `version: 2`, one `vrl` processor that reads `a = object!(.LogAttributes)`, `r = object!(.ResourceAttributes)`, `t = int!(.Timestamp)`, returns `null` when `a."event.name"` is not on the event allow-list, then sets `. = {}` and assigns each column from its source key (`a."session.id"` to `session_id`, `r."host.name"` to `host_name`, …), and a `transform:` block typing every column, tagging the primary key and indexing `ts`.
  - Exporter headers: `x-greptime-db-name: agent`, `x-greptime-log-table-name: session_event`, `x-greptime-pipeline-name: agent_session_event`, `x-greptime-hints: auto_create_table=false` (header names `…@v1.2.1:src/servers/src/http/header.rs:45,55,58`).
- **Rationale**: GreptimeDB's own mechanisms, as the repo already uses them for devloop (README:140-151):
  - a pipeline whose processor returns `null` filters the record (`…@v1.2.1:src/pipeline/src/etl.rs:331-336`), so the store drops an unlisted event even if the collector passed it;
  - in a version-2 pipeline every field left after the processors becomes a column by auto-transform (`etl.rs:462-478`; `src/pipeline/src/etl/transform/transformer/greptime.rs:282-286`), so the processor must start from an empty object; the column set is closed at the store too;
  - `auto_create_table=false` refuses a write that races the schema job instead of creating an append table (`src/operator/src/insert.rs:495-513`);
  - full-text indexes are a column option of `CREATE TABLE` at 1.2.1 (`src/sql/src/parsers/create_parser.rs:895-936`; options `src/datatypes/src/schema/column_schema.rs:56-60,660-680,780-784`, default backend `bloom`), and the `bloom` backend prunes `matches_term` and term-bearing `LIKE` (`src/common/function/src/scalars/matches_term.rs:39-56`; https://docs.greptime.com/user-guide/manage-data/data-index). The table is created by the schema job rather than by the pipeline, so the index is declared in its DDL, the idiomatic place when `auto_create_table` is off.
  - Non-append with that key collapses an exporter's replay of a batch the store already took (same session, sequence and timestamp), as devloop's tables do; `event.sequence` restarts per process and can repeat within a resumed session (`monitoring-usage.md:803,810`), but not at the same timestamp.
  - The table carries no TTL of its own, so `agent`'s 30 days apply (`telemetry-store` requirement `Part of a database keeps the database's retention unless another is declared`); `greptimedb-envelope`'s table clause judges it automatically.
- **Boundary**: source-versus-delivered: the DDL and YAML are rendered at evaluation and applied by the schema job at activation; the delivered table is read back through `information_schema.tables.create_options` and `SHOW CREATE TABLE` in the VM test.
- **Alternatives**: `greptime_identity` (rejected: brainstorm.md); the default `opentelemetry_logs` table (rejected: one JSON column, no column allow-list); `append_mode='true'` (rejected: replays duplicate); `tantivy` (rejected: index near the data's size, and `matches_term` would scan).

### D6: Traces out of phase 1
- **Choice**: no `traces*` pipeline; `otel-collector-config`'s clause stays. Claude's `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA` and omp's traces endpoint stay unset.
- **Rationale**: ADR-001:35; a follow-up after the store moves to a release with `greptime_trace_v2`, which also needs ADR-004:112's never-stored list amended for omp's `gen_ai.*` content keys.

### D8: Emitter scope and its gates
- **Choice**: a host-table field `agentTelemetry` in `flake.lib.observabilityHosts` (default `false`; `true` for magnetite and pyrite), exposed on NixOS as `vanixiets.otelCollector.agentTelemetry`. The collector adds `otlp/local` and the two pipelines only where it is true. The emitter module (D9) is active only when `osConfig.vanixiets.otelCollector.agentTelemetry or false` is true, so an emitter exists only where its receiver does. All human homes and all worker homes on those hosts, Janette's included (A189). Not stibnite (darwin, no such option), not claude-sandbox (a standalone home that imports neither `ai` nor `omnigent-worker`, `modules/home/users/claude-sandbox/meta.nix:22-49`), not the wrappers (D9).
- **Rationale**: the operator's scope; a static, evaluation-cheap gate in the host table, the repo's place for per-host collection facts (`skill://preferences-nix-checks-architecture`, static data for attribute names).
- **Boundary**: first-party; a source fact (host table) delivered when each host deploys, so both magnetite and pyrite must deploy for the change to take effect on both.

### D9: Emitter configuration: one shared home module
- **Choice**: `flake.modules.homeManager.agent-telemetry` (new file under `modules/home/ai/`), imported by `homeManager.ai` and `homeManager.omnigent-worker`, gated per D8, with an option `agentTelemetry.person` (default `config.home.username`; the worker import sets it to `worker.owner`). It:
  - merges the Claude keys of D2 into `programs.claude-code.settings.env`; it exports the set of names it adds as `agentTelemetry.claudeCodeEnvNames`, and `modules/home/ai/claude-code/wrappers.nix` removes those names from `baseSettings.env` so the wrappers do not export;
  - writes `~/.omp/agent/.env` with D2's omp keys through `home.file`;
  - for workers, `modules/home/ai/omnigent/worker.nix` gains the same `managedConfigs.claude-code-settings` entry the human module has (`claude-code/default.nix:414-423`), so a worker's `settings.json` stays a writable managed copy instead of the read-only store symlink home-manager writes when `settings` is non-empty (`home-manager/modules/programs/claude-code/default.nix:358-365`).
- **Rationale**: Claude applies user-settings `env` to every session, overriding the shell, and refuses telemetry settings from project files (`settings-reference.md:2441-2491`; A190); omp reads `~/.omp/agent/.env` privately on every launch path, ACP included, which omnigent's ACP child environment would otherwise strip (A191, A195); the worker unit's environment must stay empty (`modules/lib/omnigent-fleet-obligations.nix:74`), which this keeps.
- **Boundary**: source-versus-delivered: verified on the activated files (`~/.claude/settings.json`, `~/.omp/agent/.env`) and by evaluation of each host's home configurations, not by reading the source.
- **Alternatives**: worker unit environment (forbidden by the fleet obligations, and would start omnigent's own exporter); a wrapper script (does not reach omnigent's native Claude or ACP omp).

### D10: Queues and holds
Rates are unmeasured estimates, recorded in `schema.nix` beside `fleetBytesPerMinute` and replaced by measurement after deploy (task 5):
- `agentMetricsBytesPerMinute` = 35,840 B/min per host: 8 concurrent sessions × about 35 series each (`TelemetrySemantics` estimate) × 128 B per point (the repo's own per-point figure, `schema.nix:248-254`) × one delta export a minute.
- `agentEventBytesPerMinute` = 133,000 B/min per host: 8 concurrent sessions × about 1.0 MB per session-hour (about 575 allow-listed events × 0.6 KB plus about 0.5 MB of prompts, responses and tool details; the review's content-free 0.5–1.1 MB less the dropped hook and startup events, plus content) ÷ 60.

Agent host with agent telemetry (pyrite; magnetite's own pipelines end in `forward`):

| Exporter | Now | Then | Hold at the assumed rates |
|---|---|---|---|
| `otlp_http/ingress` (metrics) | 400 MiB | 408 MiB | 24 h × (256,000 + 35,840) B/min = 420,249,600 B = 400.8 MiB needed; 408 MiB = 427,819,008 B holds 24.4 h |
| `otlp_http/ingress-logs` (deploy records) | 16 MiB | 16 MiB | unchanged |
| `otlp_http/ingress-agent` (agent events, logs only) | — | 64 MiB | 8 h × 133,000 B/min = 63,840,000 B = 60.9 MiB needed; 64 MiB = 67,108,864 B holds 8.4 h |
| Sum | 416 MiB | 488 MiB | < 512 MiB |

Hosts without agent telemetry keep 400 + 16 MiB.
The agent role's assertion (`modules/clan/services/otel-collector/flake-module.nix:591-622`) becomes: every exporter in the host's list queues in `file_storage` by bytes with unlimited retry; `otlp_http/ingress` ≥ 24 × 60 × (`fleetBytesPerMinute` + (if `agentTelemetry` then `agentMetricsBytesPerMinute` else 0)); where `agentTelemetry`, `otlp_http/ingress-agent` ≥ 8 × 60 × `agentEventBytesPerMinute`; sum < 512 MiB.
`otlp_http/ingress-agent` carries only logs: one exporter used for two signals keeps one persistent queue per signal (`exporter_otlp_http_<name>_<signal>`, README "Queue"), which a per-exporter sum would undercount.

Ingress on magnetite (store-side queues, which hold only while the store is down; `queueBytes`, `flake-module.nix:50-59`):

| Exporter | Now | Then | Hold for 2 agent-telemetry hosts |
|---|---|---|---|
| `otlp_http/fleet` | 400 | 400 | unchanged (24 h clause) |
| `otlp_http/agent` (metrics) | 48 | 16 | 16,777,216 B ÷ 71,680 B/min = 234 min = 3.9 h |
| `otlp_http/agent_session_event` | — | 32 | 33,554,432 B ÷ 266,000 B/min = 126 min = 2.1 h |
| `devloop` and its five tables | 52 | 52 | unchanged |
| Sum | 500 | 500 | < 512 MiB |

`otel-collector-config` gains: both agent exporters ≥ 2 × 60 × (number of `agentTelemetry` hosts) × their rate.
Stated holds: 24 h of agent metrics and 8 h of agent events per agent host while magnetite or the mesh is unreachable; 2 h of every host's agent output while the store is down.
- **Boundary**: first-party source; verified by evaluation (assertions and the check), and the rates by measurement on the delivered hosts.
- **Alternatives**: agent metrics through `otlp_http/ingress-agent` too (rejected: a second hidden per-signal queue); raising the fleet floor's queue on every host (rejected: needless deploys); 24 h for events (rejected: 24 × 60 × 133,000 B = 182.7 MiB does not fit beside the metrics floor).

### D11: ADR amendments (exact edits; applied by task 7.1)
The content and consent edits are decided by the operator (2026-11-22). The rest are pending the operator's ratification and are applied only after it.

**ADR-008** (`docs/notes/development/observability/decisions/ADR-008-access-control-and-tenancy.md`):
- `:61` (decided). From: "5. Content exclusion at that collector, fail-closed, as follows." To: "5. Content control at that collector, fail-closed, as follows: content is excluded everywhere except the Claude Code prompt, response and tool-detail keys on ADR-004's agent-session allow-list, which the operator admitted on 2026-11-22 and which every store reader may read (Q5)."
- `:65` (pending). From: "1. No logs pipeline consumes the local OTLP receiver, so OTLP log records from any emitter are refused regardless of emitter settings." To: "1. Only `logs/agent-session` consumes the local OTLP receiver, and only on hosts whose host-table row sets `agentTelemetry`; it admits records whose `service.name` is `claude-code` and whose `event.name` is on ADR-004's agent-session event allow-list, keeps only that event's allow-listed keys, replaces the body with an empty string and refuses everything else; elsewhere no logs pipeline consumes it."
- `:66` (pending). From: "2. On the agent (omp) pipeline only, `redaction` on traces and metrics with `allow_all_keys: false`, `allowed_keys` from ADR-004's agent key allow-list, and `summary: silent`, plus a `filter` that drops every omp metric whose name is not on ADR-004's metric-name allow-list (`omp.agent.tool.calls` and `omp.agent.errors`);" To: "2. On the agent-session metrics pipeline only, a `filter` admitting `service.name` `claude-code` and `oh-my-pi`, a `filter` that drops every metric whose name is not on ADR-004's metric-name allow-lists (the eight `claude_code.*` metrics, `omp.agent.tool.calls` and `omp.agent.errors`), and a `transform` keeping only ADR-004's agent metric point and resource keys;" (the rest of the line unchanged).
- `:74` (pending). From: "1. omp is configured with `OTEL_LOGS_EXPORTER=none` and without `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT`, pointing at the local agent (see ADR-005)." To: "1. omp is configured with `OTEL_LOGS_EXPORTER=none`, `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=full` and a metrics endpoint only, so its content-bearing spans are not exported until traces are wired; Claude Code with prompts, responses and tool details on and tool content, raw API bodies and traces off; both pointing at the local agent and stamping `user.name`."
- `:76` (decided). From: "3. In this slice no omnigent worker account receives an OTLP endpoint or credential, so worker sessions emit no telemetry to any collector; enabling worker telemetry requires revising this record (Q3; ADR-004 Q5 and ADR-005 Q5 defer here)." To: "3. Every omnigent worker account on a host whose host-table row sets `agentTelemetry` receives the loopback OTLP endpoint, and no credential, through its home configuration rather than its unit environment; its Claude Code and omp sessions emit under the same gates as a human's, Janette's included under the consent recorded for Q3 on 2026-11-22."
- `:93` (decided). From: "… the boundary that makes this acceptable is that the store holds no content and no person identifier (ADR-004)." To: "… the boundary that makes this acceptable is the operator's organisational model of 2026-11-22: every member of the group consented to their agent sessions, content included, being read by the group; the store holds no account identifier of a model provider, and `user.name` on `agent` data is its only person identifier (ADR-004)."
- After `:185` (decided), add: "   Revised 2026-11-22: the operator states that every member of the group was notified and consented to their agent sessions being recorded and readable by the group; Janette's workers emit."
- After `:189` (decided), add: "   Revised 2026-11-22: no; the operator admits Claude Code prompts, responses and tool details to `agent`, readable by every store reader (option C of `agent-session-telemetry`'s brainstorm)."

**ADR-004** (`ADR-004-signal-scope-and-schema.md`), all pending:
- After `:65`, add rows: "| Agent-harness metrics | Claude Code OTLP metrics, the eight `claude_code.*` names | agent sessions | `agent` |" and "| Agent session events | Claude Code OTLP events on the agent-session allow-list, with prompt, response and tool-detail text | agent sessions | `agent`, table `session_event` |".
- `:69`. From: "Claude Code and hermes-agent are not emitters in this design." To: "Claude Code is an emitter for every human user and every omnigent worker on hosts whose host-table row sets `agentTelemetry`, magnetite and pyrite; hermes-agent is not an emitter."
- `:82`. From: "… applies only to the omp agent pipeline; …" To: "… applies only to the agent-session pipelines (Claude Code and omp); …".
- `:84`. Append: "On the agent-session pipelines additionally `user.name`, the person a session runs for, which the emitter stamps."
- After `:86`, add: "- Claude Code metric names: exactly `claude_code.session.count`, `claude_code.lines_of_code.count`, `claude_code.pull_request.count`, `claude_code.commit.count`, `claude_code.cost.usage`, `claude_code.token.usage`, `claude_code.code_edit_tool.decision`, `claude_code.active_time.total`; metric point keys `model`, `type`, `query_source`, `speed`, `effort`, `agent.name`, `skill.name`, `plugin.name`, `marketplace.name`, `mcp_server.name`, `mcp_tool.name`, `tool_name`, `decision`, `source`, `language`, `start_type`, `user.name`." and "- Claude Code events: the event names and per-event keys of `schema.nix`'s `agentSession` allow-list; the record body is never kept."
- `:112`. From: "… `user.account_id`, and any OTLP log record other than a `devloop` row (charter v22)." To: "… `user.account_id`, `organization.id`, `workspace.host_paths`, `ccr.session.id`, Claude Code's `tool.output` span events and its `api_request_body` and `api_response_body` events, and any OTLP log record other than a `devloop` row or an `agent` session-event row (charter v22; operator 2026-11-22)."
- `:127`. From: "… any person identifier, …" To: "… any person identifier except `user.name` on `agent` series, …".
- `:137`. From: "| Agent harness | `agent` | at most 2,000 active series; `gen_ai.tool.name` at most 200 values | at most 200,000 span rows per day when spans are wired | 90 d |" To: "| Agent harness | `agent` | at most 2,000 active series, regulated hourly; `gen_ai.tool.name` at most 200 values | at most 200,000 span rows per day when spans are wired | 30 d |".

**ADR-003** (`ADR-003-collection-topology.md`), all pending:
- `:84`. From: "3. Each agent listens for local emitters on `127.0.0.1:4318` (OTLP/HTTP) only; that receiver is wired into the traces and metrics pipelines and into no logs pipeline, so OTLP log records are rejected (see ADR-008)." To: "3. Each agent listens for local emitters on `127.0.0.1:4318` (OTLP/HTTP) only. On NixOS hosts whose host-table row sets `agentTelemetry`, that receiver, `otlp/local`, feeds `metrics/agent-session` and `logs/agent-session`, the latter admitting only Claude Code events through ADR-008's stages into `agent`; no traces pipeline exists until the store carries `greptime_trace_v2` (ADR-001). Elsewhere it feeds no logs pipeline, so OTLP log records are rejected (see ADR-008)."
- `:235`. From: "Envelope, buffering: each agent's `file_storage` queue absorbs at least 24 h of that host's output and stays below 512 MiB on disk." To: "Envelope, buffering: each agent's `file_storage` queues stay below 512 MiB on disk in sum; its metrics queue absorbs at least 24 h of the host's fleet metrics plus, where it emits agent telemetry, its agent metrics, and its agent-events queue at least 8 h of its agent events, at the rates `schema.nix` assumes; the ingress's `agent` metrics and events queues absorb at least 2 h of every agent-telemetry host's agent output while the store is down."

### D12: Verification and rollout
- **VM test first** (pyrite, KVM): extend `vmTests.x86_64-linux.fleet-ingress`, the one test with both roles, against the real 1.2.1 store, with an agent container whose host-table row sets `agentTelemetry`. It posts recorded Claude-shaped OTLP requests (protobuf) to `otlp/local` and asserts through the `regulator` account:
  - admitted: a `user_prompt` with `prompt` `canary admitted prompt <nonce>` lands in `agent.session_event` and is found by `matches_term(prompt, '<nonce>')`; `SHOW CREATE TABLE` shows the full-text index; an `api_request` lands with its token counts; a `claude_code.token.usage` delta lands in `agent` without `session_id`;
  - the canary (dropped): an `api_request_body` event with body text `canary-raw-<nonce>`; a `tool_result` carrying an unlisted key `tool_output` = `canary-output-<nonce>`; an unlisted event name; a `user_prompt` whose resource carries `user.email`, `organization.id` and `user.account_uuid`; a record body string `canary-body-<nonce>`; an event from `service.name` `canary-other`; a metric named `canary.metric`. None of these strings or keys appears in any column of any table of any database, read by `SELECT` over `information_schema.columns`-listed string columns, and the collector's `otelcol_processor_*` drop counts rise;
  - `information_schema.schemata` shows `agent` with `ttl` 30 days, and the table has no `ttl` of its own.
  The port collisions move first: `fleet-ingress.nix:76,597,789`, `fleet-ingress/helpers.py:170`, `devloop-ingest.nix:1347` and `greptimedb-pipeline.nix:183-184` bind `127.0.0.1:4318`, which `otlp/local` now takes.
- **Then magnetite** (the ingress): deploy, then watch for 15 minutes the ingest of every database (rows and series per minute against the hour before), each exporter's `otelcol_exporter_queue_size` and `otelcol_exporter_send_failed_*`, the collector's memory against its 384 MiB limiter, and every `fleet-alerts` post since the deploy; any rise in failures, a queue that grows without draining, or a missing host rolls back with `clan machines update magnetite` from the previous revision.
- **Then pyrite**, the same observation for 15 minutes, plus its `otlp_http/ingress-agent` queue.
- **stibnite** waits for the operator.

## Risks / Trade-offs

- [Risk] Every store reader reads every session's prompts, responses and tool arguments, which can include secrets a person pasted. → The operator's decision (option C) accepts it under the organisational model; 30-day retention bounds it; tool output and raw bodies stay out. Recorded in the trust boundary.
- [Risk] magnetite's collector is the fleet's single ingress; a bad pipeline stops every host's ingest. → VM test first; agent hosts queue during a rollback; the 15-minute watch with a named rollback.
- [Risk] A forged sender: any local account can post to `otlp/local` with any `user.name` (A194). → Accepted; stated in the trust boundary; the allow-lists still bound what is stored.
- [Risk] Concurrent sessions' deltas on one host collide at the same millisecond and the metric engine keeps one (A192). Per pair of concurrently active sessions with identical labels, each exporting once a minute at an independent phase, the chance per minute is about 1/60,000; at 8 such sessions (28 pairs) about 4.7 × 10⁻⁴ per minute, about 0.7 lost one-minute deltas a day, an undercount near 0.01 %. → Accepted; events carry exact per-request token counts and cost for exact sums.
- [Risk] Upstream renames a gate or a key, or adds content under an existing key. → New keys and events are dropped (fail-closed). A content-bearing change to an already-listed key would pass; the close-out comparison of A190's and A191's versions catches it at the next change.
- [Risk] Row volume and the bloom index's size grow with use. → 30 days; `greptimedb-envelope`'s 50 GiB SST bound (`modules/nixos/greptimedb.nix:379`) and its disk clauses still regulate the store.
- [Trade-off] Holds are shorter for agent data (8 h, 2 h) than for fleet metrics (24 h). → The budget does not fit 24 h; a longer outage loses the oldest agent events, which the queue's drop counters show.
- [Trade-off] Tool details carry commands and file paths in `tool_parameters`/`tool_input`, which Claude caps at about 4 K characters (`monitoring-usage.md:887`). → Accepted as content under C.

## Migration Plan

1. Store side (`schema.nix`: `agent` 30 d, the `agentSession` allow-list, table and pipeline through the schema job). On magnetite this alone changes the TTL and creates an empty table; no writer exists yet.
2. Collector side and checks; VM test with the canary on pyrite.
3. Emitter module.
4. Deploy magnetite; watch 15 minutes; roll back on degradation.
5. Deploy pyrite; watch 15 minutes.
6. Measure the agent rates and record them beside the assumed ones; resize if a hold falls below its target.

The host table and `schema.nix` are shared data that magnetite's and pyrite's closures read, so each host's behaviour changes only when it deploys; both are listed above. Rollback: deploy the previous revision; the `agent` table and its rows remain and expire at 30 days, and `ALTER DATABASE agent SET 'ttl'='90d'` restores the old retention if wanted.

## Open Questions

- Ratification of the pending ADR-003, ADR-004 and ADR-008 edits above (operator).
- stibnite: move `otelcol-process` to another loopback port and enable `agentTelemetry` there (operator's console deploy).
- Whether to record which sessions are workers: phase 1 stamps only the person; a worker marker would be a further resource key and an ADR-004 amendment.

---
title: "ADR-004: Signal scope and schema"
---

## Status

Proposed

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
| Batch lifecycle | gitea-mq journal lines beginning `batch ` | dev-loop | `devloop` |
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

Attribute allow-list (single source of truth for the collector and for the regulator).
Key-level attribute redaction, `allow_all_keys: false`, applies only to the omp agent pipeline; Prometheus-scraped and `host_metrics` points keep their native label keys, bounded by the label bans and the per-label value cap below.

- Resource, every signal: `service.name`, `service.version`, `host.name`, `host.arch`, `os.type`.
- omp metric names: exactly `omp.agent.tool.calls` and `omp.agent.errors`; every other omp metric, including token and cost metrics, is dropped (ADR-005 Q7).
- omp metric points: `gen_ai.operation.name`, `gen_ai.provider.name`, `gen_ai.request.model`, `gen_ai.response.service_tier`, `gen_ai.response.finish_reason`, `gen_ai.tool.name`, `omp.tool.status`, `omp.gen_ai.agent.name`, `error.type`.
- omp spans, when wired: the metric keys above plus `gen_ai.conversation.id`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens` and their cache variants.
- journald records: `MESSAGE` as the body, `_SYSTEMD_UNIT`, `PRIORITY` and `_HOSTNAME`; every other journal field is dropped.
- Prometheus-scraped and `host_metrics` points: their native label keys, not key-redacted, subject to the label bans below.

`devloop` column allow-list, per signal, using ADR-005's field names; any other column is dropped:

| Signal (ADR-005) | Columns | Primary key | Time index |
|---|---|---|---|
| CI attribute outcome | `build_id`, `attr`, `system`, `status`, `cached`, `abandoned`, `drv_path`, `outputs.out`, `started_at`, `finished_at`, `eval_wall_ms`, `eval_alloc_bytes`, `commit_sha`, `branch`, `pr_number`, `project` | `(build_id, attr)` | `finished_at` |
| CI build timing | `build_id`, `created_at`, `started_at`, `finished_at`, `eval_duration_ms`, `status` | `(build_id)` | `finished_at` |
| Merge-queue batch event | `batch`, `msg` (the event name), `build`, `sha`, `failed_check`, `members`, `landed`, `ejected`, `builds`, `flaky` | `(batch, msg)` | journal timestamp |
| Deploy record | `host`, `closure`, `previous_closure`, `ts` | `(host)` | `ts` |

Explicitly never stored, whatever their source: `gen_ai.input.messages`, `gen_ai.output.messages`, `gen_ai.system_instructions`, `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result`, `gen_ai.tool.definitions`, `gen_ai.retrieval.query.text`, `gen_ai.prompt`, `gen_ai.completion`, `exception.message`, `exception.stacktrace`, span status messages, `user.email`, `user.id`, `user.account_uuid`, `user.account_id`, and any OTLP log record.
This list documents intent; enforcement is the allow-lists, so on the omp pipeline, in journald records and in `devloop` rows a key absent from its list is dropped.

journald unit allow-list: `gitea`, `gitea-mq`, `nixbot*`, `niks3*`, `nix-daemon`, `nix-grpc-daemon`, `harmonia-gc`, `postgresql`, `nginx`, `greptimedb`, `opentelemetry-collector`, `zerotierone`.
Never on the list: `omnigent*`, `omnigent-host-*`, `omnigraph`, `user@*`, and session scopes, because their output can carry agent or user content.

Metric label bans: pull-request number, commit SHA, derivation or store path, build id, `gen_ai.conversation.id`, `session.id`, trace or span id, `omp.gen_ai.agent.id`, the five `omp.agent.*.count` attributes, and any person identifier.
These may appear as span or log-row columns in `devloop` and `agent`, where they do not create series.

Budget per consumer:

| Consumer | Database | Cardinality envelope | Volume envelope | Retention |
|---|---|---|---|---|
| Fleet | `fleet` | at most 6,000 active series; at most 200 distinct values per label key per metric | journald at most 100 MB per host per day, provisional | metrics 30 d; logs table 14 d |
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
The fleet envelope is the measured 392 points per host at seven hosts plus service endpoints, with headroom.

## Rejected alternatives

- Deny-list redaction: fails open on any content key not yet named.
- Renaming scraped metrics to semantic conventions: adds a transform layer that prevents no failure.
- Collecting every journald unit: omnigent worker units write agent output to the journal.
- One retention for all data: either discards dev-loop history at the fleet horizon or keeps unmeasured fleet logs for a year.
- Unlimited retention for dev-loop data in the store: unbounded growth on magnetite's local caches and R2, when ADR-006 already provides a Parquet path.
- Separate store for dev-loop telemetry: the budget is satisfiable in one store once metric labels are bounded (RK4 not confirmed).
- Collecting omp OTLP logs through a redaction stage: the log signal has no emitter-side content gate and string bodies defeat the redaction processor (see ADR-008).
- Person identifiers as attributes: no decision in ADR-005 needs them, and they make the store a personal-activity record.

## Consequences

The collector configuration and the regulator read one allow-list file, so widening the schema is a reviewed change to that file.
Any new emitter attribute is dropped until added, which can hide a useful field until someone notices its absence.
Failure classes for omp come only from `error.type`, and Omnigent tool failure classes remain unavailable under its content-safe configuration (`research/dev-loop-signals.md` RF12).
Per-person cost attribution is not possible from the store; attribution is per host and per service.
The metric engine's metadata region and pipeline table never expire (`research/greptimedb.md` F36), so the store is not fully self-expiring.
The journald volume envelope is provisional until a week of measurement exists (Q4).

## Operating envelope and regulator

Envelope: the budget table above, plus the rule that every stored attribute key is on the allow-list.

Regulator R4.1, deterministic, build time: the flake check `checks.x86_64-linux.otel-redaction` defined in ADR-008 also feeds fixtures carrying a banned metric label, an unknown attribute key, an `omp.agent.*.count` attribute and a journald record from `omnigent-host-cameron`, and asserts that the output contains only allow-listed keys and no record from a non-listed unit.
It reads the same `schema.nix` file the collector configuration is generated from, so configuration and check cannot diverge.
It is shown able to fail at acceptance by deleting the label-ban stage from the generated configuration and observing the banned label in the output.

Regulator R4.2, runtime: the `otel-envelope` timer of ADR-003 additionally queries, per database, active series, the maximum distinct values of any label key per metric, rows ingested in the last 24 h, and journald bytes per host, and fails when any bound in the budget table is breached.
It is shown able to fail at acceptance by pushing one synthetic metric with 300 distinct values of one label into `fleet` and observing the unit fail.
A failed `otel-envelope` unit reaches a human through ADR-003's `OnFailure=observability-notify@%n.service` notifier; this decision defines no unit-state signal in the store.
TTLs are asserted, not only set: ADR-007's `greptimedb-schema` oneshot enforces them, and R4.2 also compares each database's and the fleet logs table's `ttl` option against this table.

## Failure prevented

- Attribute allow-list: prompt, tool, or repository content reaches a store every admitted reader can query (RK5).
- journald unit allow-list: worker output written to the journal reaches the store through a path the attribute allow-list does not cover.
- Metric label bans: a series explosion consumes store memory on a host that has already been OOM-killed (RK3).
- Per-database retention: dev-loop history is lost at nixbot's 90-day prune, or fleet logs grow without bound.
- Single schema file: the regulator tests a different allow-list from the one deployed.
- R4.1: a configuration change that admits a banned label or a content key ships.
- R4.2: an emitter upgrade introduces an unbounded label, or a TTL drifts, with nobody told.

## Implementation surface

- Add `modules/clan/services/otel-collector/schema.nix`: attribute allow-list, omp metric-name allow-list, per-signal `devloop` column allow-list with each table's primary key and time index, never-stored list, journald unit allow-list, metric label bans, signal-to-database map, and the budget numbers used by R4.2.
- Modify the collector configuration generated by `modules/clan/services/otel-collector/flake-module.nix` (ADR-003) to build `redaction`, `filter`, `transform` and `resource` stages from `schema.nix`.
- Modify `modules/checks/otel-redaction.nix` (ADR-008) to add the R4.1 fixtures.
- Add the R4.2 queries to the `otel-envelope` unit of ADR-003.
- Consumed, not created here: the `greptimedb-schema` oneshot in `modules/nixos/greptimedb.nix` (ADR-007) creates `fleet`, `devloop` and `agent` with the database TTLs in the budget table and sets the fleet logs table TTL to 14 d.
- No flake input and no clan vars generator is added by this decision.

## Questions for the human gate

1. Q1: Is the dev-loop in-store retention 365 d? Recommended: yes; shorter loses year-over-year comparison, longer grows store caches without a named decision.
2. Q2: Are person identifiers excluded from the store entirely? Recommended: yes; keeping them enables per-person cost attribution and makes the store a personal-activity record readable by every admitted reader.
3. Q3: Are omp spans in scope for the first deployment? Recommended: no, metrics only, per ADR-005; enabling them adds `gen_ai.conversation.id` rows to `agent` under the same allow-list.
4. Q4: Is the 100 MB per host per day journald envelope accepted as provisional pending one week of measurement? Recommended: yes; the alternative is deferring the log leg until measured.
5. Q5: Should Omnigent's package gain its `tracing` extra so its metrics enter `agent`? Recommended: defer to ADR-008, under which no omnigent worker account receives an OTLP endpoint or credential in this slice; until ADR-008 is revised Omnigent contributes nothing.
6. Q6: Is agent-harness retention 90 d? Recommended: yes; longer keeps a personal-activity record longer than any listed decision needs.
7. Q7: Should the allow-list admit `omp.gen_ai.agent.name`? Recommended: yes, it is bounded by the agent roster; dropping it loses the per-subagent breakdown of tool calls and errors.

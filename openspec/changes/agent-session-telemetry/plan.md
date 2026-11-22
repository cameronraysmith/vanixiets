# Agent session telemetry implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** every Claude Code and omp session on magnetite and pyrite exports its allow-listed metrics and Claude Code events through a loopback receiver, fail-closed filters and the ingress into `agent` (30 d), with `agent.session_event` searchable by word, proven by a canary in the `fleet-ingress` container test on GreptimeDB 1.2.1 before any host deploys (tasks.md groups 1–4).

**Architecture:** `schema.nix`'s `agentSession` is the one allow-list; a shared renderer (`flake.lib.greptimedbLogTable`) turns it and devloop's tables into DDL and version-2 VRL pipelines, which magnetite's schema job applies.
The agent role adds `otlp/local` and the two agent-session pipelines where the host-table flag `agentTelemetry` is set, rendered from the same allow-list; the ingress routes agent events to their own exporter.
A shared home module sets the Claude Code and omp emitter gates where the host's collector listens.

**Tech Stack:** flake-parts with import-tree; NixOS and home-manager modules; `otelcol-contrib` 0.155.0 (`filter`, `transform`, `resource` processors, OTTL); GreptimeDB 1.2.1 (`greptimedb-bin`) pipelines, VRL and full-text index; `pkgs.testers.runNixOSTest` with nspawn containers.

**Spec:** `openspec/changes/agent-session-telemetry/` — `design.md` (D2–D12), `specs/`, `tasks.md`, `brainstorm.md`, `proposal.md`; decisions taken during implementation are recorded under "Decisions during implementation" below.

## Global Constraints

- Four stacked commits, bottom to top, each evaluating, building and passing its checks alone: `vyprtvrk` (store side, task group 1), `rqwxkuup` (collector side and VM test, groups 2 and 4), `mzmrklxz` (emitters, group 3), `oqvywrql` (traces, group 9, design D6). Edits are made in `@` and routed with `jj squash --into <chain> --use-destination-message --keep-emptied <paths>`.
- No deploy, no `clan`, no switch; nothing touches the live `fleet` or `devloop` data; no listener off loopback or the existing mesh addresses; no local aarch64-darwin build.
- x86_64-linux builds on magnetite (`--eval-store auto --store ssh-ng://magnetite.zt`); container tests on pyrite (`--store ssh-ng://pyrite.vanixiets.internal`); logs under `logs/agent-session-telemetry-*`.
- Rates: `agentMetricsBytesPerMinute = 35840`, `agentEventBytesPerMinute = 133000`; queues: pyrite 408 + 16 + 64 MiB, magnetite `agent` 16 MiB and `agent_session_event` 32 MiB, sums below 512 MiB.
- Every regulator is seen failing on a mutant before it is trusted; each mutant runs only the clause or case it must fail.
- Unrelated hosts' toplevel drvPaths stay equal; the hosts whose closures change are named with the reason.

## Interface contract

| Kind | Name | Defined in |
|---|---|---|
| Schema | `flake.lib.otelCollectorSchema.agentSession.{events,metrics,tables}`; `events.{services,resourceKeys,correlationKeys,keys.<event>}`, `metrics.{services,resourceKeys,names,pointKeys,promotedResourceAttributes}`, `tables.session_event.{columns,primaryKey,timeIndex}`; a column is `{ name; type; nullable; source = { log = <key>; } | { resource = <key>; } | { record = "Timestamp"; }; fulltext ? false; }`; `databases.agent = "30d"`; `agentMetricsBytesPerMinute`, `agentEventBytesPerMinute`; `budget.agentActiveSeries = 2000` | Task 1 |
| Lib | `flake.lib.greptimedbLogTable { name; table; recordTimestamps ? [ ]; eventFilter ? null; }` → `{ ddl; pipeline; }`; `eventFilter = { key; values; }` renders the VRL `null` branch | Task 1 |
| Store | `services.greptimedb.tables.agent`, `services.greptimedb.pipelines.agent.agent_session_event` on the host importing `flake.modules.nixos.agent-session-store` (magnetite) | Task 1 |
| Option | `vanixiets.otelCollector.agentTelemetry : bool`, default `false`, set by the agent role from `flake.lib.observabilityHosts.<host>.agentTelemetry` | Task 2 |
| Collector | receiver `otlp/local` (`127.0.0.1:4318`, HTTP); processors `filter/agent-session-service`, `filter/agent-session-metrics`, `filter/agent-session-events`, `transform/agent-session-metrics`, `transform/agent-session-events`, `resource/agent-session`, `resource/agent-session-events`; pipelines `metrics/agent-session`, `logs/agent-session`; exporters `otlp_http/ingress-agent` (agent hosts), `otlp_http/agent_session_event` (ingress); pipeline `logs/agent-session_event-out` | Task 2 |
| Home | `flake.modules.homeManager.agent-telemetry`; options `agentTelemetry.person : str` (default `home.username`), `agentTelemetry.claudeCodeEnvNames : listOf str` (read-only) | Task 3 |

## Decisions during implementation (orchestrator, 2026-11-22)

- Per-event keys: the events design D3 does not spell out keep exactly their documented keys that map onto D5's columns; `speed` and `effort` become string columns so every kept key has a column. Each column's VRL coercion falls back to `null` on a value of the wrong type, so a stray type drops the value, never the record or a column.
- `otlp_http/agent` promotes `user.name` besides the shared resource attributes; every other exporter's promote header is unchanged.
- `otlp_http/ingress-agent` in no metrics pipeline is an agent-role assertion (placement ladder), not an `otel-collector-config` clause.
- The container test renders pyrite's evaluated agent-session receiver, processors and exporters as a third collector unit in the `store` container.

## Review Focus

- A Claude Code release sends a listed key with another type (a number where a string was): the record still lands, the value is null.
- A local process posts `vanixiets.database`/`vanixiets.table` or `host.name` on its resource: they are replaced, never routed by.
- The ingress runs before the schema job creates `session_event`: `auto_create_table=false` refuses rather than creating an append table.
- A trace export to `otlp/local`: refused, nothing stored.
- `agent` holds no metric table yet (a fresh store): the hourly budget clause notes it instead of failing.

---

## Task 1: Store side (chain `vyprtvrk`)

**Files:** Modify `modules/clan/services/otel-collector/schema.nix`, `modules/nixos/devloop-collection.nix`, `modules/machines/nixos/magnetite/default.nix`; Create `modules/lib/greptimedb-log-table.nix`, `modules/nixos/agent-session-store.nix`; Modify `modules/clan/services/otel-collector/README.md` (schema entries).

- [x] **Step 1:** Record `nix eval --json` of magnetite's `services.greptimedb.tables.devloop` and `pipelines.devloop` to `logs/agent-session-telemetry-devloop-before-*.json`.
- [x] **Step 2:** Move `quote`, `storeType`, `transformType`, `ddl`, `vrlAssignment`, `dateStep` and the pipeline renderer into `flake.lib.greptimedbLogTable`; devloop renders through it with `recordTimestamps.batch_event = [ "ts" ]`.
- [x] **Step 3:** Re-evaluate both and `diff` against Step 1: empty.
- [x] **Step 4:** Add `agentSession`, `databases.agent = "30d"`, the two rates with D10's derivation and `budget.agentActiveSeries`; `nix eval .#lib.otelCollectorSchema.agentSession --json | jq keys` → `["events","metrics","tables"]`.
- [x] **Step 5:** `flake.modules.nixos.agent-session-store` sets `services.greptimedb.tables.agent` and `pipelines.agent.agent_session_event` from the renderer, with an assertion that every event key of `agentSession.events` has a column and every column's log key is a kept key; magnetite imports it.
- [x] **Step 6:** `nix eval --raw` both on magnetite shows the `FULLTEXT INDEX WITH (analyzer = 'English', case_sensitive = 'false', backend = 'bloom')` clauses, `append_mode`/`sst_format`, and the `null` branch; `nix build .#checks.x86_64-linux.nixos-magnetite`, `greptimedb-envelope`, `devloop-queries`, `obs-query` pass.
- [x] **Step 7:** `vmTests.x86_64-linux.greptimedb-pipeline` creates the table from magnetite's declaration and reads back, as `regulator`, the full-text index on both columns, `append_mode`/`sst_format`, no table `ttl` in `create_options`, and the store's dry run of the pipeline (a listed event's listed keys kept, a wrong-typed value nulled, an unlisted event dropped, the column set equal to the table's); mutants `filterRemoved` (no event filter) and `pipelineWidened` (VRL starting from the record) each fail that subtest.

## Task 2: Collector side (chain `rqwxkuup`)

**Files:** Modify `modules/lib/observability-hosts.nix`, `modules/clan/services/otel-collector/flake-module.nix`, `modules/checks/otel-collector-config.nix`, `modules/lib/otel-envelope.nix`, `modules/checks/otel-envelope.nix`, `modules/checks/otel-envelope/stub.py`, `modules/clan/services/otel-collector/README.md`.

- [x] **Step 1:** Host flag `agentTelemetry` (magnetite, pyrite); option in the collector core, set by the agent role.
- [x] **Step 2:** Write the new `otel-collector-config` clauses and mutants (`localFeedsDevloop`, `localFeedsFleet`, `tracesPipeline`, `eventFilterDropped`, `bodyKept`, `sessionIdKept`, `agentEventsToDevloop`, `agentQueueShort`, and `toolOutputKept`, `fleetPromotesPerson`). Deviation: the clauses were written after Step 3's module code, so their failure on the pre-change configuration was not recorded; each mutant failing its named clause stands as their integrity evidence.
- [x] **Step 3:** Agent fragment: `otlp/local`, the processors rendered from `agentSession`, both pipelines, `otlp_http/ingress-agent` 64 MiB and `otlp_http/ingress` 408 MiB where the flag is set; ingress: queue split, `routing/logs` route, `logs/agent-session_event-out`, `otlp_http/agent_session_event`, `logs/ingress` when devloop or agent logs, `user.name` promoted on `otlp_http/agent` only.
- [x] **Step 4:** Queue assertion over the host's exporter list and the `ingress-agent` metrics-pipeline assertion; `extendModules` overrides of pyrite (`ingress-agent` 32 MiB, `ingress` 400 MiB, `ingress-agent` in `metrics/host`) each fail with the assertion's message.
- [x] **Step 5:** `otel-collector-config` passes; each mutant's failure list printed in its log.
- [x] **Step 6:** `otel-envelope` B1/B2 over `agent` (2,000 series, 200 values), with cases `budgetAgentAt2000`/`budgetAgentAt2001` and mutant `agentSeriesIgnored`.
- [x] **Step 7:** README: loopback path, routing, queue table, schema entries.

## Task 3: Emitters (chain `mzmrklxz`)

**Files:** Create `modules/home/ai/agent-telemetry.nix`, `modules/checks/agent-telemetry-emitters.nix`; Modify `modules/home/ai/claude-code/default.nix` (import), `modules/home/ai/omnigent/worker.nix`, `modules/home/ai/claude-code/wrappers.nix`.

- [x] **Step 1:** Module with D2's keys, gated on `osConfig.vanixiets.otelCollector.agentTelemetry or false`, asserting exactly those keys in `env` and the `.env` file.
- [x] **Step 2:** Import from `homeManager.ai` and `homeManager.omnigent-worker`; the worker's `agentTelemetry.person` is derived in `modules/home/ai/omnigent/worker.nix` from the `services.omnigent-host.workers` entry whose `user` is the home's (not set in `omnigent-host.nix`); worker `managedConfigs.claude-code-settings`; wrappers strip `claudeCodeEnvNames`.
- [x] **Step 3:** Evaluate cameron on pyrite (`user.name=cameron`), `omnigent-janettesmith` on magnetite (`user.name=janettesmith`), stibnite/cinnabar absent, worker units' `environment` empty, wrappers clean; build `omnigent-worker-capabilities`, `omnigent-acp-spawn-env`, `claude-sandbox-session-secrets`, `agent-telemetry-emitters`.

## Task 4: Container test with the canary (chain `rqwxkuup`)

**Files:** Modify `modules/vm-tests/fleet-ingress.nix`, `modules/vm-tests/fleet-ingress/helpers.py`, `modules/vm-tests/devloop-ingest.nix`, `modules/vm-tests/greptimedb-pipeline.nix`. The canary posts OTLP/JSON from the test driver (the receiver decodes JSON and protobuf alike, and the exporters send protobuf onward), so no protobuf sender file exists.

- [x] **Step 1:** Move `otlp/mesh` to `127.0.0.1:4319` and the other tests' 4318 binds off it; `rg -n '127\.0\.0\.1:4318' modules/vm-tests` finds only the agent-session unit's `otlp/local`.
- [x] **Step 2:** The store gets the `agent` table and pipeline; a third collector unit renders pyrite's evaluated agent-session receiver, processors, pipelines and exporters, pointed at `otlp/mesh`, with a file tap beside each pipeline's exporter.
- [x] **Step 3:** Case `agentSession`: admitted `user_prompt` (nonce in `prompt`), `assistant_response`, `api_request`, `claude_code.token.usage`; canary kinds; scan every string column of every table of every database as `regulator`; `matches_term`; `SHOW CREATE TABLE`; `information_schema.schemata`; drop counters.
- [x] **Step 4:** Run on pyrite; then mutants (transform removed, event filter removed, service filter removed, pipeline widened), each failing its assertion; then `devloop-ingest` and `greptimedb-pipeline` on pyrite.

## Task 5: Traces (chain `oqvywrql`, design D6)

**Files:** Modify `modules/clan/services/otel-collector/schema.nix` (`agentSession.spans`, `agentSpanBytesPerMinute`), `modules/nixos/agent-session-store.nix` (`spanDdl`), `modules/clan/services/otel-collector/flake-module.nix`, `modules/checks/otel-collector-config.nix`, `modules/clan/services/otel-collector/README.md`, `modules/home/ai/agent-telemetry.nix` (`ompTracesEnv`), `modules/checks/agent-telemetry-emitters.nix`, `modules/vm-tests/fleet-ingress.nix`, `modules/vm-tests/fleet-ingress/helpers.py`.

- [x] **Step 1:** Span allow-list and rate in the schema; the three v1 tables rendered from 1.2.1's own DDL with full-text indexes, applied by the schema job.
- [x] **Step 2:** `traces/agent-session` and `otlp_http/ingress-traces` (20 MiB) where the flag is set; `traces/ingress` and `otlp_http/agent_span` (8 MiB) on the ingress; the queue assertion's span term.
- [x] **Step 3:** `otel-collector-config`'s traces clause replacing the no-traces rule, with mutants `spanInputMessagesKept`, `spanEventsKept`, `promptAfterAllowList`, `spansToFleet`, `spanTableAutoCreated`.
- [x] **Step 4:** `ompTracesEnv` and the emitters check's expected lines, with the `OTEL_BSP_MAX_QUEUE_SIZE=2048` mutant.
- [x] **Step 5:** `fleet-ingress` case `agentSpans` on pyrite, and the span-events-filter override failing it.

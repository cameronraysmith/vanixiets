---
linear_story_id: CAM-120
linear_story_identifier: CAM-120
linear_story_title: "Record agent sessions in the telemetry store"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-120/record-agent-sessions-in-the-telemetry-store
linear_story_state: Todo
linear_team: CAM
linear_project: pi-agent-environment
last_synced_state: Todo
last_synced_at: "2026-11-22T08:54:11Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-22T08:54:11Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-120 created in Todo in project d7d743a19249 (Agent environment) with description seeded from proposal.md; related to CAM-119 (track main in Claude Code cloud sessions, whose transcript incident this change answers); state, project and relation confirmed by read-only view" }
---

## Why

Nobody can see what the fleet's agent sessions do. Claude Code and omp run in herdr panes, terminals and omnigent workers on magnetite and pyrite, and none of it reaches the telemetry store: the `agent` database is declared and empty. On 2026-11-22 the operator asked for every such session to export OpenTelemetry to its host's collector and on into the store. That day's incident, cloud transcripts published to a public repository, shows what this must avoid: a destination nobody asked about, and a content filter that only looks for credentials. The operator decided that session content is shared within the group, every store reader reads it, and the group has consented. This change records sessions' events, prompts, responses and tool details, enforces what may leave each host with an allow-list at the collector, and keeps it 30 days.

## What Changes

**Agent sessions reach the telemetry store**
- From: no harness exports; `agent` holds nothing.
- To: Claude Code and omp in every human session and every omnigent worker on magnetite and pyrite export to a loopback receiver of the host's collector; metrics go to `agent`, Claude Code events to one events table in `agent` whose prompt and response columns carry a full-text index.
- Impact: non-breaking; stibnite, claude-sandbox and the `claude-glm`/`claude-cerebras` wrappers are unchanged.

**What may leave a host is an allow-list at the collector**
- From: ADR-008 refuses every OTLP log record from loopback and stores no content.
- To: the collector admits only the two harnesses, only listed events with listed keys, deletes account identifiers, removes session and prompt identifiers from metrics, and drops tool output and raw API bodies, failing closed on anything unlisted.
- Reason: the operator's content decision (2026-11-22); emitter settings are not enforcement.

**`agent` retention 90 d → 30 d**
- Impact: no data loss; the database is empty.

**Queues**
- To: agent events get their own queue on each agent host, agent metrics are counted in the metrics queue's 24-hour assertion, and magnetite's agent bytes come from the `agent` route's 48 MiB; each hold is stated in hours.

**Removed**: the parked change `publish-claude-sandbox-transcripts-to-r2`, folded into brainstorm.md as a rejected alternative.

### Phase 1 scope (D8)
magnetite and pyrite; every human user's sessions and every omnigent worker there, Janette's included; Claude Code metrics and events; omp's two admitted metrics.

### Non-goals
Claude Code's traces (its events carry its content); stibnite (its loopback receiver needs the operator's console deploy); Claude's cloud sessions and claude-sandbox; Langfuse; a public ingest endpoint; tool output and raw API bodies; omp's log records; omp's earlier conversation history on each span, of which only the newest prompt is kept (design D6, which includes omp's spans through GreptimeDB 1.2.1's `greptime_trace_v1`).

### Operator decisions recorded, and what still needs ratification
- Content (decided 2026-11-22): option C, shared content under an organisational model; options B and D are recorded in brainstorm.md.
- Consent (stated 2026-11-22): everyone in the group was notified and consented; recorded as world assumption A189.
- ADR-008's content exclusion and its Q3 consent clause: amended by the operator's decision.
- The remaining ADR amendments (ADR-003 items 3 and the buffering envelope; ADR-004's emitters, resource keys, never-stored list, label bans and the `agent` budget row; ADR-008's loopback stage and worker posture) are written in design.md as exact edits pending ratification; a task applies them after it.

## Capabilities

### New Capabilities
- `agent-session-telemetry` (behavioral): which sessions are recorded, what of them is kept, who may read it, for how long, what never leaves a host, and how an outage is absorbed.
- `agent-session-telemetry-interface` (interface): the emitter settings, the loopback receiver and its fail-closed stages, the routing, exporters, queues, the events table and its pipeline, the regulators and the VM test with its canary. Trust boundary: the collector's stages govern what leaves a host; nothing here governs what a person or an agent does with session content once read, or what a process on the host sends while claiming another person's name.

### Modified Capabilities
- `world-assumptions` (world): A188–A195 (store authorization, group consent, the harnesses' emitter behaviour, metric deduplication and the pipeline engine at 1.2.1, the loopback receiver's openness) and the designation rows the new requirements use.
- `telemetry-store` (behavioral): `agent` keeps 30 days instead of 90.
- `telemetry-store-interface` (interface): logs may also enter `agent`'s events table; the schema job creates that table and uploads its pipeline; magnetite's queues split `agent`'s 48 MiB.
- `fleet-ingress-interface` (interface): an agent host with agent telemetry exports agent events through a third exporter, and its metrics queue holds 24 hours of fleet and agent metrics.

## Impact

- `modules/clan/services/otel-collector/` (`schema.nix`, `flake-module.nix`, README), `modules/lib/observability-hosts.nix`, `modules/nixos/greptimedb.nix`, `modules/nixos/devloop-collection.nix` (the renderer it shares), a new home module under `modules/home/ai/`, `modules/home/ai/omnigent/worker.nix`, `modules/checks/otel-collector-config.nix`, `modules/lib/otel-envelope.nix`, the VM tests `fleet-ingress`, `devloop-ingest` and `greptimedb-pipeline`, `modules/apps/obs-query.sh`.
- Deploys: magnetite, then pyrite. magnetite's collector is the fleet's ingress, so a fault there stops every host's ingest until rolled back.
- Readers: `perses` and `regulator` read session content from the first deploy.

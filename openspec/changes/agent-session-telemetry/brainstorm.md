# Brainstorm: agent session telemetry

Decision log, 2026-11-22.
Sources: the operator's direction and answers of that day; the orchestrator's decision record (D1–D12, with the operator's CONTENT decision superseding D1, D2's content part, D4 and part of D8, and the operator's answer dropping D7); the design review (verdict PROCEED WITH CHANGES) and the three research reports on the collector and store, the harnesses, and the upstream signal semantics; GreptimeDB's source at tag `v1.2.1` and its documentation; ADR-001, -003, -004, -005 and -008; `modules/clan/services/otel-collector/README.md`.
It folds in the parked change `publish-claude-sandbox-transcripts-to-r2` as a rejected alternative (operator Q3); that change's directory is deleted by this change, and what matters from it is quoted below.

## Driver

On 2026-11-22 the operator set a direction for agent observability: every Claude Code and omp session run on the fleet's hosts, through herdr, a terminal or omnigent, exports OpenTelemetry to the host's own collector and on into the telemetry store (GreptimeDB 1.2.1 on magnetite) over the mesh.
Claude's cloud sessions and Langfuse are non-goals; a public ingest endpoint is deferred.

The same day's incident is the reason the question came up then.
The parked change recorded it:

> The repository `cameronraysmith/vanixiets` is public.
> The hook ran in every Default session, not only in sessions the loop created, so it published every Default session's full transcript to a public branch.

> 1. The approval to put transcripts in git never stated that the repository is public. The destination was chosen because the session could already push there (its GitHub access is scoped to the attached repository), and the question "who can read that destination" was never asked.
> 2. The only content control was gitleaks, which finds credentials, not confidential content.

Lesson carried into this change: every destination is named with who can read it, and content control is an allow-list enforced before data leaves the host, not a credential scanner.

## Operator questions and answers (2026-11-22)

- Q1. What is recorded? Metrics, events and tool details on; prompt and response text on; tool output and raw API bodies off. Originally approved "in a separate database with its own read-only user and 30-day retention".
- Q2. Which harnesses first? Claude Code and omp.
- Q3. The R2 transcript proposal? Fold it in as a rejected alternative.
- Q4. Langfuse? Later, not in this change.

## The isolation finding (D1)

Q1's premise, a database whose content only its own read-only user can read, is false at GreptimeDB 1.2.1:

- `DefaultPermissionChecker::check_permission` compares only the user's global mode (`rw`/`ro`/`wo`) with whether the request reads or writes, and answers `Allow` otherwise; `uses_table_targets` is `false` (`GreptimeTeam/greptimedb@v1.2.1:src/auth/src/permission.rs:320-353`).
- `StaticUserProvider::authorize` ignores catalog and schema: "default allow all" (`…@v1.2.1:src/auth/src/user_provider/static_user_provider.rs:75-83`).
- ADR-008 already records it: per-person, per-database or per-table read partitioning is not enforceable with the open build (`ADR-008-access-control-and-tenancy.md:80`); the Enterprise provider is not available.

So any `ro` user, `regulator` (obs-query, the envelopes, fleet-alert) and `perses` (dashboards) included, reads every database.

Options put to the operator:

- B. A separate store instance for content, with its own users. The only real isolation the open build offers (ADR-008 Q5, `:188`), but `services.greptimedb` is single-instance (`modules/nixos/greptimedb.nix:192`), magnetite's store runs under a memory envelope, and ADR-008 already rejected a second instance on memory grounds.
- C. Store content in the shared store and accept that every store reader reads it.
- D. Leave content where it already lives (Claude's `~/.claude/projects`, kept 1100 days by `modules/home/ai/claude-code/default.nix:63`; omp's `~/.omp/agent/sessions`; worker homes are `0700`) and store only `session.id` and `prompt.id` as join keys, which ADR-004 allows as `agent` columns (`:129`).

The orchestrator recommended D now and B if cross-host content search was needed, and held content back (D1) pending the operator.

### Operator decision: C, under an organisational model

The operator chose C (2026-11-22): store session content for all users together in the shared store.
The fleet is one organisation working toward a common cause, not a set of mutually untrusted tenants, so every store reader may read every session.
This amends ADR-008's content exclusion and its Q3 consent clause by the operator's authority.

The operator also confirmed (2026-11-22) that everyone in the group has been notified and has consented to their agent sessions being recorded and readable by the group.
That statement is the evidence that discharges ADR-008 Q3's consent condition for Janette's workers (`:184-185`); it is recorded as a dated world assumption, not as an override, and the requirement that includes a person's sessions names it.

Consequences:
- Claude Code: `OTEL_LOG_USER_PROMPTS=1`, `OTEL_LOG_ASSISTANT_RESPONSES=1`, `OTEL_LOG_TOOL_DETAILS=1`; `OTEL_LOG_TOOL_CONTENT` and `OTEL_LOG_RAW_API_BODIES` unset, and the collector drops what they would add, fail-closed.
- omp: `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=full` (`summary` would include truncated tool results), the collector deleting tool-result keys, and `OTEL_LOGS_EXPORTER=none` (omp's `omp.log` string bodies are ungated; ADR-008 Q6).
- Identity: `user.name` (the person: `cameron`, `janettesmith`) and `host.name` are stamped; `user.email`, `user.id`, `user.account_uuid`, `user.account_id` and `organization.id` are deleted (Anthropic account identifiers, not needed).
- Emitters: every human user's Claude Code and omp, and all omnigent workers, Janette's included, on magnetite and pyrite. stibnite waits.
- Retention stays 30 days.

## Rejected alternative: transcripts to a private R2 bucket (operator Q3)

The parked change proposed, for Claude's cloud sessions only, a Stop hook that uploads each turn's transcript to a dedicated private R2 bucket with a write-only, prefix-scoped temporary credential, opt-in per session, 30-day lifecycle.
Its own constraints, quoted:

> The cloud's egress is limited to the environment's allowed hosts … R2's S3 endpoint for the account … would have to be added to each environment that publishes.

> long-lived R2 API tokens are scoped to buckets, not prefixes, … there is no write-only token;

> Any credential placed there is readable by the model and every process in the session.

Why it is rejected:
1. Scope. It covers only cloud sessions, which the operator's direction makes a non-goal; the sessions that matter run on the fleet's own hosts, where no credential has to enter a third party's sandbox.
2. Shape. It stores whole transcripts as objects to fetch and read, not events that can be queried, joined to metrics and dashboards, or searched across sessions; the telemetry store already gives the fleet those, with retention and regulators.
3. Risk. It needs a credential inside the session and an egress exception per environment, which the incident's lesson argues against; the OpenTelemetry path keeps every credential on the fleet (the emitters post to loopback, the collector holds the mTLS identity).
4. Its open questions (the lifetime of a locally signed R2 credential, curl's SigV4 with a session token) would need probes that buy nothing for fleet sessions.

What it leaves behind: the incident's two root causes, which this change answers with named readers and a collector allow-list.
The fate of the incident's kept refs (`refs/transcripts-keep/*`) stays with the operator and is outside this change.

## Decisions taken while the operator was away, as they stand

- D2 (gates): replaced by the operator's content gates above.
- D3 (enforcement): fail-closed at the collector on the loopback receiver path only: a `service.name` allow-list (`claude-code`, `oh-my-pi`); a Claude `event.name` allow-list, each event with a key allow-list, the record body dropped; `user.*` except `user.name`, `organization.id`, `workspace.host_paths` and `ccr.session.id` deleted; `session.id` and `prompt.id` removed from metrics; omp metrics limited to `omp.agent.tool.calls` and `omp.agent.errors`.
  Under C, the event key allow-lists include the prompt, response and tool-detail keys, and exclude every tool-output and raw-body key.
  A canary in the VM test proves a forbidden key, a forbidden event and an identity key are dropped and a prompt is stored and found.
- D4 (aliases instead of `user.name`): superseded; `user.name` is stamped.
- D5 (store): reuse the declared, empty `agent` database; 30 d retention instead of 90 d; one events table through a version-2 VRL pipeline, devloop pattern.
- D6 (traces): out; 1.2.1 has no `greptime_trace_v2` (ADR-001:35) and the collector check forbids traces pipelines.
- D7 (cumulative temporality): dropped by the operator.
  Claude metrics carry no per-process identity except `session.id`, so after D3 strips it, concurrent sessions on one host would write different cumulative counters into the same series.
  Claude's default delta temporality is kept; deltas summed across sessions are the right aggregate.
- D8 (scope): magnetite and pyrite; all humans and all workers (operator decision). Not stibnite, claude-sandbox, or the `claude-glm`/`claude-cerebras` wrappers.
- D9 (emitter config): a shared home module for humans and workers.
- D10 (queues): agent events get their own queue, agent metrics are counted in the metrics queue's assertion, magnetite's bytes come from the `agent` route's 48 MiB.
- D11 (ADR amendments): the content and consent amendments are decided by the operator; the rest are listed for ratification.
- D12 (rollout): VM test on pyrite first, then magnetite, then pyrite.

## Same-timestamp deltas (checked at the operator's request)

Two sessions on one host now write delta points into one series.
At 1.2.1, OTLP metrics go to the metric engine by default (`…@v1.2.1:src/frontend/src/server.rs:162` passes `prom_store.with_metric_engine`, default `true` per `config/standalone.example.toml:223`; `src/frontend/src/instance/otlp.rs:146-160`).
The metric engine's data region gets no `append_mode` (`src/metric-engine/src/engine/options.rs:63-90`), so mito's default applies: not append-only, merge mode `last_row` (`src/mito2/src/region/options.rs:97-108,165-171`), and rows with the same series key and timestamp are deduplicated.
Timestamps are stored in milliseconds (`src/servers/src/otlp/metrics.rs:448-454`).
GreptimeDB exposes no supported way to make OTLP's auto-created metric-engine tables append-only; pre-creating the physical table with `append_mode` is not a documented path and is not taken.
So a collision drops one session's delta for that minute; its likelihood and bound are recorded as an accepted risk in design.md.

## Directions considered and not taken

- A new `agents` database beside `agent`: rejected; `agent` is declared for exactly this and is empty.
- `greptime_identity` for events: rejected; it flattens every attribute into a column and Claude's `status_code` is a number on `api_error` and a string on `auth`, so the type clash fails requests; it would also admit any new key as a column, the opposite of fail-closed.
- The default `opentelemetry_logs` table: rejected; attributes land in one JSON column with no full-text index and every key is kept.
- Routing on the darwin receiver by `service.name`: deferred with stibnite; ADR-003 item 22 says nothing routes by `service.name`, and the clean fix is moving `otelcol-process` to another loopback port.

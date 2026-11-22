## ADDED Requirements

### Requirement: Claude Code's settings carry the emitter gates

Where agent telemetry is on, the user settings' `env` SHALL set telemetry, metrics, logs and traces on over `http/protobuf` to `http://127.0.0.1:4318`, prompts, responses, tool details and tool content on, a 64-span buffer (`OTEL_BSP_MAX_QUEUE_SIZE=64`), account UUIDs off and `OTEL_RESOURCE_ATTRIBUTES=user.name=<person>`, and no other `OTEL_*` or tracing key: never raw API bodies or detailed tracing.

**Discharged by**: evaluation of `checks.x86_64-linux.nixos-magnetite` and `nixos-pyrite` with an assertion of the agent-telemetry home module over the rendered `env`; `checks.x86_64-linux.agent-telemetry-emitters`, which writes the fourteen keys out itself and was seen failing on mutants adding `OTEL_LOG_RAW_API_BODIES` or `ENABLE_BETA_TRACING_DETAILED` and dropping `OTEL_LOG_TOOL_CONTENT`, `OTEL_TRACES_EXPORTER` or `OTEL_BSP_MAX_QUEUE_SIZE`; the activated `~/.claude/settings.json` read after each deploy; resting on world assumptions `A190 — Claude Code emits its telemetry as documented for its packaged version` and `A202 — Claude Code's traces carry its tool output in an event and read the span buffer bound from the environment`.

#### Scenario: The rendered settings are evaluated

- **WHEN** cameron's home and each worker's home on magnetite and pyrite are evaluated
- **THEN** `programs.claude-code.settings.env` holds exactly the keys above, `<person>` is `cameron` for cameron's home and for `omnigent-cameron`, and `janettesmith` for `omnigent-janettesmith`, and none of `OTEL_LOG_RAW_API_BODIES`, `ENABLE_BETA_TRACING_DETAILED`, `BETA_TRACING_ENDPOINT` or `OTEL_RESOURCE_INCLUDE_HOST` is present

#### Scenario: A worker's settings stay writable

- **WHEN** a worker home is activated
- **THEN** its `~/.claude/settings.json` is a managed writable copy, not a store symlink, as the human home's is

#### Scenario: The wrappers are evaluated

- **WHEN** the `claude-glm` and `claude-cerebras` wrapper settings are evaluated in cameron's home on pyrite
- **THEN** their `env` contains none of the names the agent-telemetry module adds

### Requirement: omp's environment file carries the emitter gates

Where agent telemetry is on, `~/.omp/agent/.env` SHALL set the metrics endpoint `http://127.0.0.1:4318/v1/metrics`, the traces endpoint `http://127.0.0.1:4318/v1/traces`, `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_LOGS_EXPORTER=none`, `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=full`, `OTEL_BSP_MAX_QUEUE_SIZE=64`, `OTEL_EXPORTER_OTLP_TIMEOUT=5000` and `OTEL_RESOURCE_ATTRIBUTES=user.name=<person>`, and no generic or logs endpoint.

**Discharged by**: the agent-telemetry home module's assertion over the rendered file; `checks.x86_64-linux.agent-telemetry-emitters`, which writes the eight lines out itself; the activated file read after each deploy; resting on world assumptions `A191 — omp reads its own environment file and puts content only on spans`, `A195 — omnigent runs a worker's harness with the worker's home` and `A196 — omp bounds its span buffer by its own batch settings`, and limited by `A197 — A project's environment file overrides omp's own`.

#### Scenario: The rendered file is evaluated

- **WHEN** each home on magnetite and pyrite is evaluated
- **THEN** `home.file.".omp/agent/.env"` holds exactly those eight lines with that home's person

#### Scenario: The buffer bound is changed

- **WHEN** the module's `OTEL_BSP_MAX_QUEUE_SIZE` is set to omp's default 2048
- **THEN** `checks.x86_64-linux.agent-telemetry-emitters` fails naming the three pyrite homes

### Requirement: The emitters exist only where the collector listens for them

`flake.lib.observabilityHosts` SHALL carry `agentTelemetry`, `true` only for magnetite and pyrite; the collector SHALL add `otlp/local` only there, and the agent-telemetry home module, imported by `homeManager.ai` and `homeManager.omnigent-worker`, SHALL act only when `osConfig.vanixiets.otelCollector.agentTelemetry` is true, never through a worker unit's environment.

**Discharged by**: evaluation of every NixOS and darwin machine check; the omnigent fleet obligation that `worker.environment == { }`; an `extendModules` override of cinnabar with the home module and no flag.

#### Scenario: A host without the flag is evaluated

- **WHEN** cinnabar, stibnite or claude-sandbox's home is evaluated
- **THEN** no `otlp/local` receiver exists and no home carries the module's settings

#### Scenario: The worker units are evaluated

- **WHEN** magnetite's omnigent worker units are evaluated
- **THEN** their environment is empty and no unit holds a store credential or an `OTEL_*` variable

### Requirement: The loopback receiver feeds only the agent-session pipelines

On an agent-telemetry host, `otlp/local` SHALL be an OTLP/HTTP receiver on `127.0.0.1:4318`, the only receiver of the agent-session collector, feeding exactly `metrics/agent-session`, `logs/agent-session` and `traces/agent-session`; the host's collector SHALL have no `otlp/local`, no receiver on its address and no agent-session pipeline, and its only traces pipeline SHALL be the ingress's `traces/ingress`.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s local, isolation, logs-receiver and traces clauses over magnetite's two collectors with mutants `localFeedsDevloop`, `localFeedsFleet`, `metricsBackInShared`, `spansBackInShared`, `localWildcard`, `localSecondReceiver` and `spansToFleet`; the `fleet-ingress` test's evaluation-time assertion over pyrite's agent-session collector; build-time `otelcol-contrib validate` of both configurations.

#### Scenario: A mutant wires the receiver elsewhere

- **WHEN** a mutant adds `otlp/local` or an agent-session pipeline back to the host's collector, adds a second receiver to the agent-session collector, sends `traces/ingress` to `otlp_http/fleet`, or binds `otlp/local` to `0.0.0.0:4318`
- **THEN** the check fails on its clause

### Requirement: The agent-session pipelines run in a collector unit of their own

On an agent-telemetry host, the agent-session pipelines SHALL run only in `otel-agent-session.service`, with `MemoryMax` 512M, a 384 MiB limiter first in every pipeline, `GOMEMLIMIT` 409 MiB between them, its own queue directory and telemetry port, the host collector's hardening and `OOMScoreAdjust` 700 on magnetite; the host's collector SHALL set no `GOMEMLIMIT` and no agent limiter.

**Discharged by**: the agent role's assertion over the unit and the notified units; magnetite's kill-order assertion; `checks.x86_64-linux.otel-collector-config`'s stages and agent limiter clauses with mutants `traceLimiterDropped`, `agentLimiterOverGoMemLimit`, `goMemLimitUnset` and `sharedGoMemLimit`; `vmTests.x86_64-linux.fleet-ingress` running pyrite's unit; the split load harness (design D14), resting on world assumptions `A199 — omp's chat spans carry the whole conversation at the measured sizes` and `A200 — The collector holds ten to fourteen times a span request while decoding it`.

#### Scenario: Eight sessions post maximum-size chat spans at once

- **WHEN** the split load harness posts eight 13.8 MiB chat spans every 5 s, or eight 64-span bursts, to `otlp/local` on pyrite's and magnetite's evaluated collectors
- **THEN** the host's collector refuses no fleet point and does not restart, and whatever the agent-session collector refuses or loses is agent telemetry

#### Scenario: magnetite's kill order omits the unit

- **WHEN** an override sets the unit's `OOMScoreAdjust` below perses's 600, or the unit is absent
- **THEN** magnetite's evaluation fails on its kill-order assertion

### Requirement: The agent-session stages admit only allow-listed events and keys

`logs/agent-session` SHALL run `memory_limiter`, a `service.name` filter admitting only `claude-code`, an `event.name` filter, a per-event `keep_keys`, an empty body and resource `keep_keys`, then stamp `host.name`, `vanixiets.database=agent`, `vanixiets.table=session_event`; `metrics/agent-session` SHALL admit `claude-code` and `oh-my-pi`, listed metric names and point keys only.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s stage-order clause with mutants `eventFilterDropped`, `bodyKept` and `sessionIdKept`; `vmTests.x86_64-linux.fleet-ingress`'s canary; resting on world assumption `A190 — Claude Code emits its telemetry as documented for its packaged version`.

#### Scenario: The stage order is checked

- **WHEN** the check reads magnetite's `logs/agent-session` and `metrics/agent-session`
- **THEN** each filter and transform precedes the resource stamping and every exporter, and every kept key is on `schema.nix`'s allow-list

#### Scenario: Metrics lose their session labels

- **WHEN** the VM test sends a `claude_code.token.usage` point carrying `session.id`, `prompt.id`, `user.email` and `organization.id`
- **THEN** the stored series carries none of those labels and carries `user_name` and `host_name`

### Requirement: Every kept span and event value is at most 64 KiB

After the allow-lists, the agent-session collector SHALL cut every span attribute, event attribute and span status message to 65,536 bytes; it SHALL delete an emitter's own `last_user_message` before any copy, and clear every span's links, dropping whole a span that still carries one.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s keys and stages clauses with mutants `spanTruncationRemoved`, `eventTruncationRemoved`, `statusMessageUncut`, `promptNotCleared`, `spanLinksNotCleared` and `spanLinksKept`; `vmTests.x86_64-linux.fleet-ingress`'s `agentSpans` case (a 70 KiB response, tool result and status message, a forged `last_user_message`, linked omp and Claude spans stored without their links), its uncommitted mutant `spanLinksNotCleared`; the split load harness's 14 MiB `gen_ai.output.messages` scenario (design D14); resting on world assumption `A203 — The collector's OTTL and queues behave as read at 0.155.0`.

#### Scenario: A response larger than 64 KiB is sent

- **WHEN** a chat span's `gen_ai.output.messages` holds 70 KiB, or 14 MiB under load, or a tool result or a status message holds 70 KiB
- **THEN** the stored value holds at most 65,536 bytes, its beginning intact

#### Scenario: A span carries a link or its own last user message

- **WHEN** an emitter sends a span with a link, or a span with a `last_user_message` attribute whose history ends in no user text
- **THEN** the linked span is stored without its link, whose attributes are nowhere, and the other span is stored without `last_user_message`

### Requirement: The span path keeps only the last user message and listed span keys

`traces/agent-session` SHALL admit `claude-code` and `oh-my-pi`, copy the newest user message where the gate below allows and Claude Code's `tool.output` onto its span as `gen_ai.tool.call.result`, then drop every span event and keep only `agentSession.spans` keys and resource keys, clearing scope attributes, before stamping; `traces/ingress` SHALL write only `agent`-stamped spans to `agent.agent_span` through `greptime_trace_v1` with `auto_create_table=false`.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s stage, statement and traces clauses with mutants `spanInputMessagesKept`, `spanEventsKept`, `toolOutputCopyRemoved`, `toolOutputCopyAfterEventsDropped`, `toolOutputAttributeDropped`, `promptAfterAllowList`, `spansToFleet` and `spanTableAutoCreated`; `vmTests.x86_64-linux.fleet-ingress`'s `agentSpans` case and its uncommitted mutant `toolOutputCopyRemoved`; resting on world assumptions `A198 — The telemetry store writes traces into pre-created v1 tables and refuses unknown columns`, `A202 — Claude Code's traces carry its tool output in an event and read the span buffer bound from the environment` and `A203 — The collector's OTTL and queues behave as read at 0.155.0`.

#### Scenario: A chat span carries the whole history

- **WHEN** the VM test posts an omp step-0 chat span with tools whose `gen_ai.input.messages` holds an older prompt, a tool result and the newest prompt, plus a system prompt, an unlisted key, an exception event, a status message and a scope attribute, and a tool span with its result
- **THEN** `agent.agent_span` holds the newest prompt in `span_attributes.last_user_message`, the response, the tool arguments, the tool result and the status message, and no column or value holds any of the rest

#### Scenario: Claude Code's spans are posted

- **WHEN** the VM test posts Claude Code's interaction, model-request, tool and tool-execution spans with its standard attributes, a `tool.output` event on each tool span, retry events and a link
- **THEN** the store holds the session id, the user prompt, tool name and id, the command or file path, duration, success, error, model and token counts, and each tool's output as `gen_ai.tool.call.result`, and no account identifier, event or link

#### Scenario: The span table is read back

- **WHEN** the VM test reads `SHOW CREATE TABLE agent.agent_span` and its `create_options` as `regulator`
- **THEN** `span_attributes.last_user_message`, `span_attributes.gen_ai.output.messages`, `span_attributes.gen_ai.tool.call.result` and `span_attributes.user_prompt` carry the full-text index, `span_attributes.success` is `BOOLEAN`, `table_data_model` is `greptime_trace_v1`, and the table has no `ttl` of its own

### Requirement: Credential shapes are masked in what the agent-session collector keeps

After the allow-lists and the 64 KiB cut, the agent-session collector SHALL replace every match of `agentSession.credentialPatterns` with `****` in every kept string attribute of events and spans and in the span status message. The masking is in addition to the key allow-lists, never instead of them, and catches token-shaped strings only, not every secret.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s stages and keys clauses with mutants `maskRemovedFromSpans`, `maskRemovedFromEvents`, `maskBeforeCut`, `maskShapeDropped` and `statusMessageUnmasked`; `vmTests.x86_64-linux.fleet-ingress`'s `agentSession` and `agentSpans` cases, with credentials assembled at run time from pieces so that `checks.x86_64-linux.gitleaks` stays clean, and the case's uncommitted mutant `maskRemoved`; resting on world assumption `A203 — The collector's OTTL and queues behave as read at 0.155.0`.

#### Scenario: Credentials are planted in tool output and errors

- **WHEN** the VM test sends a GitHub token and a private-key block in an omp tool result, an Anthropic key in a status message, a bearer token and a JWT in a Claude Bash output, a private-key block in a Claude Read output, a GitHub token in a Claude tool-execution status, and a bearer token in an event's tool parameters
- **THEN** each is stored as `****` around its unmasked context, and no part of any credential is in what left the host or in any column; with the masking stage removed the case fails

#### Scenario: A credential without a known shape is sent

- **WHEN** a session's tool output holds a password or an AWS secret access key
- **THEN** it is stored as sent; the allow-list and the shapes do not claim to catch it

### Requirement: The schema job brings an existing span table to the declared columns

On every run the schema job SHALL add each `agentSession.spans` key's column and each full-text index to an existing `agent.agent_span`, so a table an older generation created ends identical, up to column order, to a fresh one, and a second run changes nothing; on the store's host the agent-session collector SHALL start after the schema job.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s traces and unit clauses with mutants `spanColumnsNotAltered`, `spanIndexesNotAltered` and `agentBeforeSchema`; `vmTests.x86_64-linux.fleet-ingress`'s `agentSpans` case, which recreates the table as main created it before design D15 and runs the job twice, and its uncommitted mutant `spanAltersRemoved`; resting on world assumption `A204 — The telemetry store alters a table idempotently as read at 1.2.1`.

#### Scenario: The table predates the new keys

- **WHEN** `agent.agent_span` holds rows and lacks the columns and indexes design D15 adds, and the schema job runs
- **THEN** the job succeeds, the rows remain, and the table's definition equals a fresh store's up to column order; a second run leaves it unchanged

### Requirement: Only a top-level run's first request gets a last user message

The agent-session collector SHALL copy into `last_user_message` only on a span named `chat …` whose `omp.gen_ai.agent.step.number` is 0, which carries `omp.gen_ai.request.available_tools` and carries neither `gen_ai.agent.id` nor `omp.gen_ai.oneshot.kind`, so that no tool result, advisor update, subagent message or oneshot prompt is copied.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s keys clause with mutants `promptGateNoChat`, `promptGateNoStep`, `promptGateNoAgentId`, `promptGateNoOneshot` and `promptGateNoTools`; `vmTests.x86_64-linux.fleet-ingress`'s `agentSpans` case, seen failing with the gate removed; resting on world assumption `A201 — omp marks the spans whose newest user message can be other than a person's`.

#### Scenario: Spans the gate excludes

- **WHEN** the VM test posts chat spans whose history ends in user text at step 1, with `gen_ai.agent.id`, with `omp.gen_ai.oneshot.kind`, and without `omp.gen_ai.request.available_tools`
- **THEN** each is stored without `last_user_message`, and its user text is neither in what left the host nor in any column

#### Scenario: Injected user text at step 0 is stored (accepted)

- **WHEN** the newest user message of a top-level run's first request is `!cmd` output, a steering interjection, an IRC message, a skill body or an image-mention wrapper
- **THEN** it is stored as `last_user_message`, as the operator accepted on 2026-11-22 (design D15)

### Requirement: One allow-list decides what the collector keeps and the store stores

`flake.lib.otelCollectorSchema.agentSession` SHALL be the only declaration of the admitted event names, each event's keys, the metric names and point keys, and the `session_event` columns with their source keys, types, primary key, time index and full-text columns; the collector's stages, the table's DDL and its pipeline SHALL be rendered from it.

**Discharged by**: evaluation of magnetite; `checks.x86_64-linux.otel-collector-config`'s clause comparing the transform's key lists with the schema; the VM test's DDL read-back.

#### Scenario: A key is added to an event

- **WHEN** a change adds a key to one event in `agentSession`
- **THEN** the collector keeps it, the table gains its column and the pipeline fills it, with no second edit

### Requirement: The session-event table is created by the schema job with its pipeline

`greptimedb-schema` SHALL set `agent`'s `ttl` to `30d`, create `agent.session_event` non-append with `sst_format='flat'`, primary key `(host_name, session_id, event_sequence)`, time index `ts`, no `ttl` of its own and `FULLTEXT INDEX` (`bloom`, `English`, case-insensitive) on `prompt` and `response`, and upload the version-2 VRL pipeline `agent_session_event` that starts from an empty object and returns null for unlisted events.

**Discharged by**: `vmTests.x86_64-linux.fleet-ingress`'s DDL and options read-back through `SHOW CREATE TABLE` and `information_schema`; `greptimedb-envelope`'s table clause; resting on world assumption `A193 — The telemetry store's pipelines filter, close and index as documented`.

#### Scenario: The table is read back

- **WHEN** the VM test reads `SHOW CREATE TABLE agent.session_event` and `information_schema.schemata` as `regulator`
- **THEN** the table shows the full-text index on both columns, `append_mode` false and `sst_format` flat, and `agent`'s options show `ttl` 30 days

#### Scenario: A word is searched

- **WHEN** the VM test queries `SELECT … WHERE matches_term(prompt, '<nonce>')`
- **THEN** exactly the canary's admitted prompt is returned

### Requirement: Agent events are routed to their table

The ingress SHALL route logs with `vanixiets.database=agent` and `vanixiets.table=session_event` through `routing/logs` to `logs/agent-session_event-out` and `otlp_http/agent_session_event`, sending `x-greptime-db-name: agent`, `x-greptime-log-table-name: session_event`, `x-greptime-pipeline-name: agent_session_event` and `x-greptime-hints: auto_create_table=false`.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s logs-exporter clause with mutant `agentEventsToDevloop`; the VM test's admitted cases.

#### Scenario: A mutant routes agent events to devloop

- **WHEN** a mutant sends the agent route to a `devloop` exporter
- **THEN** the check fails

### Requirement: Agent queues are sized to their holds

The agent-session collector SHALL queue `otlp_http/ingress-metrics` 52 MiB (24 h of agent metrics), `otlp_http/ingress-agent` 64 MiB (8 h of events) and `otlp_http/ingress-traces` 44 MiB (3 h of spans), below 512 MiB; magnetite SHALL queue `otlp_http/agent` 16 MiB, `otlp_http/agent_session_event` 32 MiB (2 h) and `otlp_http/agent_span` 8 MiB (15 min, refusing when full) of every agent-telemetry host's rates, its sum below 512 MiB.

**Discharged by**: the agent role's assertion over the agent-session collector with an `extendModules` override of pyrite's `otlp_http/ingress-agent` to 32 MiB; `checks.x86_64-linux.otel-collector-config`'s queue clauses with their mutants, `agentSpanQueueShort` and `agentSpanQueueBlocks` among them; the rates measured after deploy; resting on world assumption `A203 — The collector's OTTL and queues behave as read at 0.155.0` for the refusal.

#### Scenario: pyrite's event queue is shrunk

- **WHEN** an override sizes pyrite's agent-session `otlp_http/ingress-agent` at 32 MiB
- **THEN** pyrite's evaluation fails on the agent role's assertion over the unit

### Requirement: Regulators cover the agent-session path

`otel-envelope` on the ingress host SHALL fail its hourly budget run when `agent` holds more than 2,000 active series or a label more than 200 values; `otel-agent-session-envelope` SHALL judge the agent-session collector's own telemetry, a span refused at `otlp/local` being loss; `otel-collector-config` SHALL fail on any agent-session pipeline in the host's collector, any transform statement list other than `agentSession` renders, and logs leaving for a database other than `devloop` or `agent`.

**Discharged by**: `checks.x86_64-linux.otel-envelope`'s case set with an `agent` fixture of 2,001 series, the cases `agentSessionHealthy`, `agentSessionLocalRefused` and `ingressLoopbackRefused` with mutant `loopbackRefusalIsLoss`; `checks.x86_64-linux.otel-collector-config` with its mutants.

#### Scenario: The agent series budget is exceeded in the fixture

- **WHEN** the envelope check runs its budget clause over a fixture where `agent` holds 2,001 active series
- **THEN** the clause fails, and passes at 2,000

#### Scenario: The agent-session collector refuses spans

- **WHEN** the agent-session collector's envelope reads 40 more spans refused at `otlp/local` than on its previous run
- **THEN** it fails `C4 loss`, while magnetite's envelope does not count refusals at `otlp/loopback` as loss

### Requirement: The VM test proves the allow-list with a canary

`vmTests.x86_64-linux.fleet-ingress`, run on pyrite against GreptimeDB 1.2.1, SHALL post the canary through `otlp/local` and find, as `regulator`, no canary word or forbidden key in any string column of any table, the admitted prompt by `matches_term`, the metric without session labels, and no VM-test listener on `127.0.0.1:4318` other than `otlp/local`.

**Discharged by**: `nix build .#vmTests.x86_64-linux.fleet-ingress` on pyrite, its log kept under `logs/`.

#### Scenario: The canary runs

- **WHEN** the test posts an `api_request_body` event, a `tool_result` with an unlisted `tool_output` key, an unlisted event, a `user_prompt` with `user.email`, `organization.id` and `user.account_uuid`, a string body, a `service.name` of `canary-other` and a metric `canary.metric`, each marked with a nonce
- **THEN** a scan of every string column in every database finds no nonce but the admitted prompt's, and no column named after a forbidden key exists

#### Scenario: The span canary runs

- **WHEN** the `agentSpans` case posts omp spans carrying an older prompt, a tool result in the history, a system prompt, an unlisted key, an exception event, a scope attribute, `user.email`, a `canary-other` service, a link, a forged `last_user_message` and four spans the copy's gate excludes, and Claude Code spans carrying account identifiers, retry events, a detailed-tracing attribute and a link, each marked with a nonce
- **THEN** what left the host and every string and JSON column in every database hold the nonce only in the admitted values: the step-0 chat span's newest prompt, the response, the tool arguments and results, the status messages, the linked span's own key, and Claude's session id, prompt, command, path and tool output

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described as an end-to-end guarantee about who reads session content or what a session sends.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** they establish that the emitters are configured as stated where the flag is on, that the collector admits only the allow-list on the loopback path and stamps the host, that the store closes and indexes the table as stated, and that queues and regulators are bounded, each as far as its own check, assertion or test reaches

#### Scenario: A guarantee about who sent a session event is sought

- **WHEN** someone asks whether a stored user name proves which person's session sent an event
- **THEN** the answer is no: any local process can post to the loopback receiver under any user name (world assumption `A194 — Any local process can send to a loopback receiver and name any person`)

#### Scenario: A guarantee about what is inside an admitted field is sought

- **WHEN** someone asks whether a stored prompt, response, tool detail or tool output is free of secrets
- **THEN** the answer is no: the allow-list chooses fields, not their contents, and a person or an agent can paste a secret into a prompt or a command; the masking replaces only token-shaped credentials of the listed issuers

#### Scenario: A guarantee about readers is sought

- **WHEN** someone asks whether these properties limit who reads session content
- **THEN** the answer is no: every holder of a read store account reads it (world assumption `A188 — The telemetry store authorizes reads by a global mode, not by database`), and nothing here governs what a reader does with it

#### Scenario: A guarantee that the emitter settings hold is sought

- **WHEN** someone asks whether omp's content level, traces endpoint or buffer bound are enforced
- **THEN** the answer is no: a project `.env` in a session's working directory overrides `~/.omp/agent/.env` (world assumption `A197 — A project's environment file overrides omp's own`); the collector's allow-lists still bound what leaves the host

### Requirement: Langfuse gets the store's spans after every stage, under its own names

Where a host's `flake.lib.observabilityHosts` row sets `langfuse`, and only there, the agent-session collector SHALL send to Langfuse Cloud the spans `traces/agent-session` exports, after its last stage, with input, output and token counts under Langfuse's keys, without `vanixiets.*` resource attributes or `claude_code.tool.blocked_on_user` spans; none of those renames SHALL reach the store.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s Langfuse path clause with mutants `langfuseBeforeMask`, `langfuseFromLocal`, `langfuseRoutingKept` and `langfuseWithoutFlag`; `vmTests.x86_64-linux.fleet-ingress`'s `agentSpans` case, whose stand-in sink receives the store's thirteen spans and its `langfuse` case, and the uncommitted mutant `langfuseBeforeMask`; resting on world assumptions `A205 — Langfuse Cloud ingests OTLP traces as read on 2026-11-22` and `A207 — The collector's fan-out returns every branch's error as read at 0.155.0`.

#### Scenario: The canary spans are sent

- **WHEN** the VM test posts omp and Claude Code spans carrying planted credentials, over-long values and a link
- **THEN** the sink receives exactly the spans the store stores, masked and cut alike, with the test key pair's Basic credential and `x-langfuse-ingestion-version: 4`, prompts, outputs and token counts under Langfuse's keys, and the store's tap holds no `langfuse.` key

#### Scenario: The fan-out is moved before the mask

- **WHEN** Langfuse's branch is fed before `transform/agent-session-mask`
- **THEN** the configuration check rejects it, and the VM test fails with a planted credential reaching the sink

### Requirement: Langfuse's branch cannot cost the store's spans

A slow, failing, rate-limited, blocked, oversized-refused or unreachable Langfuse SHALL NOT refuse, delay or duplicate a span on the store's path or return an error to an emitter: the branch SHALL have no limiter and no error-propagating stage, retry for 5 minutes and then drop, and drain at least ten times faster than the assumed span rate into a queue of twice a retry window.

**Discharged by**: the agent role's assertion on `otlp_http/langfuse`; `checks.x86_64-linux.otel-collector-config`'s Langfuse exporter clause with mutants `langfuseRetryForever`, `storeSpansRetryFinite`, `langfuseQueueShort`, `langfuseDrainSlow`, `langfuseBatchOverLimit`, `langfuseWithLimiter`, `langfuseTransformPropagates` and `agentQueuesOver512`; `vmTests.x86_64-linux.fleet-ingress`'s `langfuse` case; resting on world assumptions `A205 — Langfuse Cloud ingests OTLP traces as read on 2026-11-22` and `A207 — The collector's fan-out returns every branch's error as read at 0.155.0`.

#### Scenario: Langfuse is down, blocks, throttles or refuses the size

- **WHEN** the VM test's sink is stopped, then answers 403, 429 and 413, and a batch is posted in each state
- **THEN** each POST answers 200, the store holds each batch exactly once, `otlp/local` refuses nothing, Langfuse's queue never refuses and empties, and the exporter drops the batch at once for 403 and 413 and at the retry limit, after retrying, for the others

### Requirement: Langfuse's failed sends do not page, a refusing fan-out does

`otel-agent-session-envelope` SHALL leave only `otlp_http/langfuse`'s failed sends out of its loss clause; that exporter's enqueue failures, its queue at 90 % and `otlp/local`'s refusals SHALL still fail it.

**Discharged by**: `checks.x86_64-linux.otel-envelope`'s cases `langfuseSendFailed`, `langfuseEnqueueFailed` and `langfuseStoreSendFailed` with mutants `sendFailedExemptAnyExporter` and `sendFailedExemptAnySignal`.

#### Scenario: Langfuse's quota blocks ingestion

- **WHEN** Langfuse answers 403 to every request for a day
- **THEN** no envelope run fails and nothing is posted; the agent unit's `otelcol_exporter_send_failed_spans{exporter="otlp_http/langfuse"}` shows it

### Requirement: Langfuse's keys are a shared clan var loaded as credentials

The Langfuse project's public and secret keys SHALL be the shared clan var `langfuse`, entered at hidden persisted prompts, deployed only to hosts whose row sets `langfuse`, each of them a recipient, and read by `otel-agent-session.service` from its credentials directory; no key SHALL appear in the configuration, a command line or the repository in clear.

**Discharged by**: the agent role's generator and `LoadCredential`; `flake.lib.sharedVarsObligations` on the machine checks; `checks.x86_64-linux.otel-collector-config`'s Langfuse exporter clause with mutant `langfuseKeyInline`; `checks.x86_64-linux.gitleaks`.

#### Scenario: A host without the flag is evaluated

- **WHEN** cinnabar or electrum is evaluated
- **THEN** it declares no `langfuse` generator and loads no Langfuse credential

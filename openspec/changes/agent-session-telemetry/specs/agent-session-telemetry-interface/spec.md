## ADDED Requirements

### Requirement: Claude Code's settings carry the emitter gates

Where agent telemetry is on, the user settings' `env` SHALL set `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_METRICS_EXPORTER=otlp`, `OTEL_LOGS_EXPORTER=otlp`, `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318`, `OTEL_LOG_USER_PROMPTS=1`, `OTEL_LOG_ASSISTANT_RESPONSES=1`, `OTEL_LOG_TOOL_DETAILS=1`, `OTEL_METRICS_INCLUDE_ACCOUNT_UUID=false` and `OTEL_RESOURCE_ATTRIBUTES=user.name=<person>`, and no other `OTEL_*` or tracing key.

**Discharged by**: evaluation of `checks.x86_64-linux.nixos-magnetite` and `nixos-pyrite` with an assertion of the agent-telemetry home module over the rendered `env`; the activated `~/.claude/settings.json` read after each deploy; resting on world assumption `A190 — Claude Code emits its telemetry as documented for its packaged version`.

#### Scenario: The rendered settings are evaluated

- **WHEN** cameron's home and each worker's home on magnetite and pyrite are evaluated
- **THEN** `programs.claude-code.settings.env` holds exactly the keys above, `<person>` is `cameron` for cameron's home and for `omnigent-cameron`, and `janettesmith` for `omnigent-janettesmith`, and none of `OTEL_LOG_TOOL_CONTENT`, `OTEL_LOG_RAW_API_BODIES`, `OTEL_TRACES_EXPORTER`, `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA`, `ENABLE_BETA_TRACING_DETAILED`, `BETA_TRACING_ENDPOINT` or `OTEL_RESOURCE_INCLUDE_HOST` is present

#### Scenario: A worker's settings stay writable

- **WHEN** a worker home is activated
- **THEN** its `~/.claude/settings.json` is a managed writable copy, not a store symlink, as the human home's is

#### Scenario: The wrappers are evaluated

- **WHEN** the `claude-glm` and `claude-cerebras` wrapper settings are evaluated in cameron's home on pyrite
- **THEN** their `env` contains none of the names the agent-telemetry module adds

### Requirement: omp's environment file carries the emitter gates

Where agent telemetry is on, `~/.omp/agent/.env` SHALL set `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://127.0.0.1:4318/v1/metrics`, `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, `OTEL_LOGS_EXPORTER=none`, `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=full` and `OTEL_RESOURCE_ATTRIBUTES=user.name=<person>`, and no generic, traces or logs endpoint.

**Discharged by**: the agent-telemetry home module's assertion over the rendered file; the activated file read after each deploy; resting on world assumptions `A191 — omp reads its own environment file and puts content only on spans` and `A195 — omnigent runs a worker's harness with the worker's home`.

#### Scenario: The rendered file is evaluated

- **WHEN** each home on magnetite and pyrite is evaluated
- **THEN** `home.file.".omp/agent/.env"` holds exactly those five lines with that home's person

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

On an agent-telemetry host, `otlp/local` SHALL be an OTLP/HTTP receiver on `127.0.0.1:4318` feeding exactly `metrics/agent-session` and `logs/agent-session`; no `traces*` pipeline SHALL exist, and no other pipeline SHALL take `otlp/local`.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s clauses over magnetite's evaluated configuration with mutants `localFeedsDevloop`, `localFeedsFleet` and `tracesPipeline`; the agent role's assertion on pyrite; nixpkgs' build-time `otelcol-contrib validate`.

#### Scenario: A mutant wires the receiver elsewhere

- **WHEN** a mutant adds `otlp/local` to `metrics/host`, to a `logs/devloop-*` pipeline, or adds a `traces/agent-session` pipeline
- **THEN** the check fails on its clause

### Requirement: The agent-session stages admit only allow-listed events and keys

`logs/agent-session` SHALL run `memory_limiter`, a `service.name` filter admitting only `claude-code`, an `event.name` filter, a per-event `keep_keys`, an empty body and resource `keep_keys`, then stamp `host.name`, `vanixiets.database=agent`, `vanixiets.table=session_event`; `metrics/agent-session` SHALL admit `claude-code` and `oh-my-pi`, listed metric names and point keys only.

**Discharged by**: `checks.x86_64-linux.otel-collector-config`'s stage-order clause with mutants `eventFilterDropped`, `bodyKept` and `sessionIdKept`; `vmTests.x86_64-linux.fleet-ingress`'s canary; resting on world assumption `A190 — Claude Code emits its telemetry as documented for its packaged version`.

#### Scenario: The stage order is checked

- **WHEN** the check reads magnetite's `logs/agent-session` and `metrics/agent-session`
- **THEN** each filter and transform precedes the resource stamping and every exporter, and every kept key is on `schema.nix`'s allow-list

#### Scenario: Metrics lose their session labels

- **WHEN** the VM test sends a `claude_code.token.usage` point carrying `session.id`, `prompt.id`, `user.email` and `organization.id`
- **THEN** the stored series carries none of those labels and carries `user_name` and `host_name`

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

On an agent-telemetry host other than the ingress, `otlp_http/ingress` SHALL be 408 MiB and logs-only `otlp_http/ingress-agent` 64 MiB, asserted at 24 h of `fleetBytesPerMinute` plus `agentMetricsBytesPerMinute` and 8 h of `agentEventBytesPerMinute`; on magnetite `otlp_http/agent` 16 MiB and `otlp_http/agent_session_event` 32 MiB, checked at 2 h of every agent-telemetry host's rates; all sums below 512 MiB.

**Discharged by**: the agent role's queue assertion with an `extendModules` override of pyrite's `otlp_http/ingress-agent` to 32 MiB; `checks.x86_64-linux.otel-collector-config`'s queue clauses with their mutants; the rates measured after deploy.

#### Scenario: pyrite's event queue is shrunk

- **WHEN** an override sizes pyrite's `otlp_http/ingress-agent` at 32 MiB
- **THEN** pyrite's evaluation fails on the agent role's queue assertion

### Requirement: Regulators cover the agent-session path

`otel-envelope` on the ingress host SHALL fail its hourly budget run when `agent` holds more than 2,000 active series or a label more than 200 values, and `otel-collector-config` SHALL fail on any `traces*` pipeline, on `otlp/local` feeding any other pipeline, and on logs leaving for a database other than `devloop` or `agent`.

**Discharged by**: `checks.x86_64-linux.otel-envelope`'s case set with an `agent` fixture of 2,001 series; `checks.x86_64-linux.otel-collector-config` with its mutants.

#### Scenario: The agent series budget is exceeded in the fixture

- **WHEN** the envelope check runs its budget clause over a fixture where `agent` holds 2,001 active series
- **THEN** the clause fails, and passes at 2,000

### Requirement: The VM test proves the allow-list with a canary

`vmTests.x86_64-linux.fleet-ingress`, run on pyrite against GreptimeDB 1.2.1, SHALL post the canary through `otlp/local` and find, as `regulator`, no canary word or forbidden key in any string column of any table, the admitted prompt by `matches_term`, the metric without session labels, and no VM-test listener on `127.0.0.1:4318` other than `otlp/local`.

**Discharged by**: `nix build .#vmTests.x86_64-linux.fleet-ingress` on pyrite, its log kept under `logs/`.

#### Scenario: The canary runs

- **WHEN** the test posts an `api_request_body` event, a `tool_result` with an unlisted `tool_output` key, an unlisted event, a `user_prompt` with `user.email`, `organization.id` and `user.account_uuid`, a string body, a `service.name` of `canary-other` and a metric `canary.metric`, each marked with a nonce
- **THEN** a scan of every string column in every database finds no nonce but the admitted prompt's, and no column named after a forbidden key exists

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

- **WHEN** someone asks whether a stored prompt, response or tool detail is free of secrets
- **THEN** the answer is no: the allow-list chooses fields, not their contents, and a person or an agent can paste a secret into a prompt or a command

#### Scenario: A guarantee about readers is sought

- **WHEN** someone asks whether these properties limit who reads session content
- **THEN** the answer is no: every holder of a read store account reads it (world assumption `A188 — The telemetry store authorizes reads by a global mode, not by database`), and nothing here governs what a reader does with it

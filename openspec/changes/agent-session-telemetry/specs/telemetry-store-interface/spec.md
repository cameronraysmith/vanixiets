## MODIFIED Requirements

### Requirement: Ingest is OTLP over HTTP with a database header

The ingress SHALL write metrics to the telemetry store only through OTLP over HTTP at `http://127.0.0.1:4000/v1/otlp` as `collector`, one `otlp_http` exporter per database behind a `routing` connector, taking them from magnetite's agent through `forward` and from other agent hosts through `otlp/mesh`.
Logs SHALL enter the store only in `devloop`'s tables and `agent.session_event`, each limited to its allow-list, as scenarios below state; traces SHALL NOT enter it.

**Discharged by**: the evaluation-time collector check (R3.1) with its mutants, nixpkgs' build-time `otelcol-contrib validate`, and the container tests `greptimedb-pipeline`, `devloop-ingest` and `fleet-ingress`.

#### Scenario: Each database exporter carries its headers

- **WHEN** magnetite's collector configuration is evaluated
- **THEN** each `otlp_http/<db>` exporter sends `x-greptime-db-name: <db>` and `x-greptime-otlp-metric-promote-resource-attrs` built from the resource allow-list in `schema.nix`

#### Scenario: Logs are routed to their devloop table

- **WHEN** magnetite's collector configuration is evaluated
- **THEN** logs reach the telemetry store only through a `routing/logs` connector in the ingress role that routes on the resource attributes `vanixiets.database` and `vanixiets.table` to one `otlp_http/devloop_<table>` exporter per table of `flake.lib.otelCollectorSchema.devloop.tables`, each authenticating as `collector` and sending `x-greptime-db-name: devloop`, `x-greptime-log-table-name: <table>`, `x-greptime-pipeline-name: devloop_<table>` and `x-greptime-hints: auto_create_table=false`, and `resource/strip-database` deletes both attributes before every exporter

#### Scenario: Agent session events are routed to their table

- **WHEN** magnetite's collector configuration is evaluated
- **THEN** `routing/logs` also routes `vanixiets.database = agent` and `vanixiets.table = session_event` to `otlp_http/agent_session_event`, authenticating as `collector` and sending `x-greptime-db-name: agent`, `x-greptime-log-table-name: session_event`, `x-greptime-pipeline-name: agent_session_event` and `x-greptime-hints: auto_create_table=false`, and `logs/ingress` exists whenever `devloop` tables or agent events are routed

#### Scenario: Dev-loop rows are ingested in the container test

- **WHEN** `vmTests.x86_64-linux.devloop-ingest` runs the collector with its S2 receivers against the store
- **THEN** each source's rows pass from its `logs/devloop-<table>` pipeline through `forward` and `routing/logs` into the `devloop` table its exporter names, with zero failed log records and no `body` column

#### Scenario: Another host's series and deploy records cross the ingress

- **WHEN** `vmTests.x86_64-linux.fleet-ingress` runs an agent without the ingress role against the ingress and the store
- **THEN** its metrics pass through `otlp/mesh` and `metrics/ingress` into `fleet` with the agent's `host_name`, its deploy records pass through `otlp/mesh` and `logs/ingress` into `devloop.deploy_record`, and every exporter's failed-send count is zero after first start

#### Scenario: A metric is ingested in the container test

- **WHEN** the container test emits a metric to the collector's local receiver
- **THEN** the metric passes from the agent pipeline to the ingress pipeline through an in-process `forward` connector, arrives in the database the routing connector selects, and carries `host_name` as a promoted label

#### Scenario: The promoted attributes are read back

- **WHEN** the container test reads back the metric it emitted
- **THEN** the metric carries `host_name`, promoted through the `x-greptime-otlp-metric-promote-resource-attrs` header the ingress builds from the resource allow-list in `schema.nix`, and appears only in the database whose name the exporter's `x-greptime-db-name` header carries

#### Scenario: The histogram conversion is removed while the store is below 1.3.0

- **WHEN** magnetite's collector configuration drops the conversion of exponential histograms to explicit-bucket histograms while the telemetry store's version is below 1.3.0
- **THEN** the evaluation-time conversion check (R1.2) fails, which its mutant shows

#### Scenario: The collector configuration is validated at build time

- **WHEN** the collector's configuration is validated during the build, before `/run/credentials` exists
- **THEN** validation passes without a placeholder credential, because `basicauth` reads the `collector` password through `client_auth.password_file` and validation opens no TLS file; the one validation override removes the `authorization` of the zerotierone scrape job, whose credential file the prometheus receiver's validation stats, and the evaluation-time collector check (R3.1) fails when an override touches anything else

#### Scenario: A logs pipeline takes an OTLP receiver other than the ingress receiver

- **WHEN** a mutant of magnetite's collector configuration adds a local OTLP receiver to a `logs/*` pipeline other than `logs/agent-session`, or adds `otlp/local` to any pipeline but `logs/agent-session` and `metrics/agent-session`
- **THEN** the evaluation-time collector check (R3.1) fails, because only `otlp/mesh` and `otlp/mesh-tincr` may feed the ingress's logs pipelines and `otlp/local` only the agent-session pipelines

### Requirement: Databases and their retention are set at the telemetry store

The machine SHALL run a oneshot `greptimedb-schema.service` as `admin` that polls `GET /health` until the telemetry store answers, then sets each database's retention as the scenarios below state.
The machine SHALL then create exactly the tables of `services.greptimedb.tables`, the four `devloop` tables and `agent.session_event`, and upload their pipelines from `services.greptimedb.pipelines`, as the scenarios below state, and SHALL create no other table.

#### Scenario: Each database's retention is set

- **WHEN** the schema oneshot runs
- **THEN** for each of `fleet` (`30d`), `devloop` (`365d`) and `agent` (`30d`) it issues `CREATE DATABASE IF NOT EXISTS` followed by `ALTER DATABASE ... SET 'ttl'`, because the create statement leaves an existing database's retention unchanged

#### Scenario: The devloop tables are declared

- **WHEN** the schema oneshot creates the `devloop` tables
- **THEN** it creates, with `CREATE TABLE IF NOT EXISTS`, exactly `ci_attribute`, `ci_build`, `batch_event` and `deploy_record` from `services.greptimedb.tables`, each non-append with the flat SST format, its primary key, its time index and no `ttl` of its own

#### Scenario: The agent session-event table is declared

- **WHEN** the schema oneshot creates the `agent` table
- **THEN** it creates, with `CREATE TABLE IF NOT EXISTS`, exactly `session_event` from `services.greptimedb.tables.agent`, non-append with the flat SST format, primary key `(host_name, session_id, event_sequence)`, time index `ts`, a `bloom` full-text index on `prompt` and `response`, and no `ttl` of its own, and uploads `agent_session_event` to `/v1/pipelines/agent_session_event?db=agent`

#### Scenario: The schema oneshot runs against an empty store and against an existing database

- **WHEN** the container test runs the schema oneshot once against an empty telemetry store, and once after creating `fleet` with another `ttl`
- **THEN** each database carries its declared `ttl` after each run

#### Scenario: The devloop tables are created before the collector writes

- **WHEN** the container test `devloop-ingest` runs the schema oneshot and then the collector
- **THEN** the four `devloop` tables exist with `append_mode=false` and `sst_format=flat` in their create options and no `ttl` of their own, and the collector's first logs write to each succeeds

### Requirement: The collector's queue persists across a telemetry store restart

The machine SHALL back each exporter's sending queue in magnetite's collector with a `file_storage` extension using the `bytes` sizer, in one directory, sized as the first scenario below states, so that the queues sum to less than 512 MiB, the `fleet` queue holds at least 24 hours at an assumed 256,000 bytes per minute, a rate measured at first activation, and the two `agent` queues hold at least 2 hours of every agent-telemetry host's agent output at the rates `schema.nix` assumes.

#### Scenario: The queues are sized per database

- **WHEN** magnetite's collector configuration is evaluated
- **THEN** the queues are 400 MiB for `fleet`; 48 MiB for `agent`, split as 16 MiB for `otlp_http/agent` (metrics) and 32 MiB for `otlp_http/agent_session_event`; and 52 MiB for `devloop`, split as 4 MiB for its metrics exporter, 32 MiB for `otlp_http/devloop_ci_attribute` and 4 MiB each for `otlp_http/devloop_ci_build`, `otlp_http/devloop_batch_event`, `otlp_http/devloop_deploy_record` and `otlp_http/devloop_eval_run`

#### Scenario: The persistent queue is removed

- **WHEN** a mutant of magnetite's collector configuration drops the `file_storage` queue, sizes the `fleet` queue below 24 hours at the assumed rate, sizes an `agent` queue below 2 hours of the agent-telemetry hosts' assumed rates, gives a `devloop` or `agent` logs exporter no persistent queue, or brings the queues' sum to 512 MiB or more
- **THEN** the evaluation-time collector check (R3.1) fails on its queue clause

#### Scenario: The `fleet` queue rate is measured at first activation

- **WHEN** the operator stops `greptimedb.service` for ten minutes on magnetite and measures the bytes the `fleet` queue accumulates
- **THEN** the operator records the measured rate beside the assumed 256,000 bytes per minute, and a measured rate under which the 400 MiB queue holds less than 24 hours is a finding that resizes the queues

#### Scenario: The store restarts during collection

- **WHEN** the container test stops `greptimedb.service`, emits metrics, starts `greptimedb.service` again and queries the interval
- **THEN** the metrics emitted while the store was stopped are returned


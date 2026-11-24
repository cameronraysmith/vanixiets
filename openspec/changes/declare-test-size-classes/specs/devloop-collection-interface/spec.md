## MODIFIED Requirements

### Requirement: gitea-mq's five batch messages are parsed from its journal

magnetite's collector SHALL run `journald/gitea-mq` with `units: [gitea-mq.service]`, `grep: 'msg="batch (formed|built|landed|bisecting|done)"'`, `start_at: beginning`, `storage: file_storage` and a `journalctl_path` wrapper adding `--boot=all`, so it reads every retained boot, then a `key_value_parser` from `body.MESSAGE` into attributes, a `retain` of the allow-listed `batch_event` keys, and the removal of the body, keeping the record's journal timestamp.

**Discharged by**: `devloop-reconcile`'s comparison of batch events, resting on world assumption `A44 — gitea-mq announces each batch transition in one of five exact journal messages`; `vmTests.x86_64-linux.devloop-ingest-reconcile`'s stub `gitea-mq` with its mutant lacking `key_value_parser`.

#### Scenario: The parser is removed

- **WHEN** `devloop-ingest-reconcile` runs a collector configuration without `key_value_parser` against the stub's fixture lines
- **THEN** the rows do not reach `batch_event` and `devloop-reconcile` exits non-zero

#### Scenario: A further message begins with batch

- **WHEN** the stub prints `msg="batch reconcile build failed"`
- **THEN** no `batch_event` row is written for it

### Requirement: Each agent host's collector ships its own deploy records

Each agent host's collector SHALL read `/var/log/deploy-record.jsonl` through `file_log/deploy-record`, defined in the agent role for NixOS hosts and in `flake.lib.otelCollectorDarwin`'s agent configuration for darwin hosts, with `start_at: beginning`, `storage: file_storage` and `json_parser`, keeping `host`, `closure`, `previous_closure` and `ts`, under the receiver id and settings magnetite used before, so magnetite's stored offset carries over.

**Discharged by**: `devloop-reconcile`'s comparison of deploy records on magnetite; `vmTests.x86_64-linux.devloop-ingest`'s first-start case; `vmTests.x86_64-linux.fleet-ingress`'s delivery case; `checks.x86_64-linux.otel-collector-darwin`'s `otelcol-contrib validate` case over the rendered darwin agent configuration; the operator's line-count comparison at each agent host's first deploy or activation.

#### Scenario: The receiver reads another file

- **WHEN** `devloop-ingest-reconcile`'s mutant points `file_log/deploy-record` at another path
- **THEN** `devloop-reconcile` exits non-zero on the deploy-record count

#### Scenario: An agent host without the ingress role ships its records

- **WHEN** `fleet-ingress`'s agent writes three deploy-record lines
- **THEN** three `deploy_record` rows naming that agent's host arrive in `devloop` through `otlp_http/ingress-logs` and `otlp/mesh`

#### Scenario: magnetite's receiver moves into the agent role

- **WHEN** magnetite is first deployed with the receiver defined in the agent role
- **THEN** magnetite's `deploy_record` row count equals its file's line count, and no line is shipped a second time

#### Scenario: Each agent host is first deployed

- **WHEN** cinnabar and pyrite are first deployed with the agent role
- **THEN** the operator records, for each, the line count of its `/var/log/deploy-record.jsonl` and its `deploy_record` row count, and a difference is a finding

#### Scenario: The darwin agent configuration is rendered

- **WHEN** `flake.lib.otelCollectorDarwin`'s agent configuration is evaluated
- **THEN** its `logs/devloop-deploy_record` pipeline takes `file_log/deploy-record` through `resource/devloop-deploy_record` with the deploy-record keep-list rendered from the devloop allow-list and ends in `otlp_http/ingress-logs`, and `otel-collector-darwin` validates the configuration with the root pin's `otelcol-contrib`

#### Scenario: stibnite is first activated with the agent

- **WHEN** stibnite is first activated with its collector after its `collect` is set
- **THEN** the operator records the line count of stibnite's `/var/log/deploy-record.jsonl`, which `flake.modules.darwin.deploy-record` has appended to since before stibnite had a collector, and stibnite's `deploy_record` row count, and a difference is a finding

### Requirement: The devloop tables are pre-created with keys, a time index and deduplication

`greptimedb-schema.service` SHALL, after the databases, issue `CREATE TABLE IF NOT EXISTS` for `devloop.ci_attribute`, `devloop.ci_build`, `devloop.batch_event` and `devloop.deploy_record`, each `ENGINE=mito WITH ('append_mode' = 'false', 'sst_format' = 'flat')`, with every identifier quoted, its allow-listed primary key, a `TIMESTAMP(6) NOT NULL` time index and no `ttl`.

**Discharged by**: R3.1's ordering clause, which keeps the collector after `greptimedb-schema`, and `greptimedb-envelope`'s table clause, resting on world assumption `A46 — GreptimeDB 1.2.1 keeps one row per key and time in a pre-created non-append table`; `vmTests.x86_64-linux.devloop-ingest`'s first-start and writer-ordering cases; `devloop-reconcile`'s comparison of CI rows with its append-mode mutant.

#### Scenario: The tables exist before the collector's first write

- **WHEN** `devloop-ingest` starts the store, the schema job and the collector
- **THEN** every `otlp_http/devloop_<table>` exporter reports zero failed log records after its first send

#### Scenario: The schema job omits a table

- **WHEN** `devloop-ingest`'s mutant schema job creates no `ci_build`
- **THEN** `otlp_http/devloop_ci_build`'s first send is refused with HTTP 400 and its failed log-record count is non-zero, so the case fails

#### Scenario: A table is created in append mode

- **WHEN** `devloop-ingest-reconcile`'s mutant creates `ci_attribute` with `'append_mode' = 'true'` and the collector re-reads its overlap
- **THEN** duplicate keys are stored and `devloop-reconcile` exits non-zero

### Requirement: Each devloop table has an ingest pipeline that keeps only its allow-listed fields

`greptimedb-schema.service` SHALL post one pipeline per table to `/v1/pipelines/devloop_<table>?db=devloop`, failing on any answer but 200, whose `vrl` step resets the event with `. = {}` and then assigns exactly the table's allow-listed fields, each on its own line, with an empty string as null, whose `date` step parses `%Y-%m-%dT%H:%M:%S%.fZ` or `%Y-%m-%dT%H:%M:%SZ`, which declares the primary key as tags, and which takes `batch_event`'s `ts` from the record's timestamp.

**Discharged by**: `vmTests.x86_64-linux.devloop-ingest`'s table-shape case, which compares each table's `DESC TABLE` with the allow-list after ingest, and `vmTests.x86_64-linux.devloop-ingest-reconcile`'s pipeline mutant that drops `flaky`.

#### Scenario: The stored columns are read back

- **WHEN** `devloop-ingest` has ingested its fixtures
- **THEN** each table's `DESC TABLE` lists exactly its allow-listed columns, none of them `body`

### Requirement: devloop-reconcile compares CI rows with nixbot every day

Over its day, the reconcile SHALL exit non-zero when a nixbot `(build_id, attr, finished_at)` is missing from `ci_attribute`, or a stored key is absent from nixbot unless nixbot's current `finished_at` for that `(build_id, attr)` is null or later, or, when nixbot no longer has the attribute, its build's current `finished_at` is null or later, and likewise for `builds` and `ci_build`; each store query SHALL count before it reads keys.

**Discharged by**: `vmTests.x86_64-linux.devloop-ingest-reconcile`'s cached-row and null-`pr_number` mutants, each failing with as many missing keys as nixbot holds of its kind, its append-mode mutant, and its restarted-build leg.

#### Scenario: The collector omits cached outcomes

- **WHEN** `devloop-ingest-reconcile` runs the reconcile against a collector whose attribute query omits `cached = true` rows, and against a build query that omits rows with a null `pr_number`
- **THEN** the reconcile exits non-zero on each, and passes on the unmutated configuration

#### Scenario: A restarted attribute is accepted

- **WHEN** a fixture attribute finished in the window is restarted after it and finishes again
- **THEN** the reconcile accepts the stored earlier row and passes

#### Scenario: A restarted build drops a finished attribute

- **WHEN** a fixture build is restarted after the window and nixbot deletes one of its attributes that finished in the window, as nixbot does for a system it no longer builds
- **THEN** the reconcile accepts the stored row of that attribute and passes

### Requirement: devloop-reconcile compares batch events with the journal every day

Over the same day, the reconcile SHALL exit non-zero when the per-`msg` count of `gitea-mq.service` journal lines matching the five messages, filtered on `__REALTIME_TIMESTAMP`, differs from `batch_event`'s; when nixbot finished a build on a `gitea-mq/batch/` branch and `batch_event` holds no `batch built` row; or when a `batch done` row has a null `landed`, `ejected`, `builds` or `flaky`.

**Discharged by**: `vmTests.x86_64-linux.devloop-ingest-reconcile`'s parser, silent-stub and dropped-`flaky` mutants, resting on world assumption `A48 — magnetite's journal keeps gitea-mq's lines for longer than the reconcile's window`.

#### Scenario: The merge queue falls silent

- **WHEN** `devloop-ingest-reconcile`'s stub `gitea-mq` prints nothing while fixture batch-branch builds exist
- **THEN** the reconcile exits non-zero

#### Scenario: A batch done row loses a field

- **WHEN** `devloop-ingest-reconcile`'s mutant pipeline drops `flaky`
- **THEN** the reconcile exits non-zero

### Requirement: devloop-reconcile compares deploy records with the file and the current system

Over the same day, the reconcile SHALL exit non-zero when the count of `/var/log/deploy-record.jsonl` lines differs from magnetite's `deploy_record` rows, or when magnetite's latest stored `closure` differs from `readlink -f /run/current-system`.

**Discharged by**: `vmTests.x86_64-linux.devloop-ingest-reconcile`'s receiver-path and wrong-closure mutants.

#### Scenario: The snippet records the wrong closure

- **WHEN** `devloop-ingest-reconcile`'s mutant snippet writes the previous closure as `closure`
- **THEN** the reconcile exits non-zero

### Requirement: devloop-ingest shows the collection path and the reconcile able to fail

`vmTests.x86_64-linux.devloop-ingest` and `vmTests.x86_64-linux.devloop-ingest-reconcile` SHALL be systemd-nspawn container tests built from one container, requiring `uid-range`, run on demand on magnetite, running PostgreSQL with the nixbot input's migrations, GreptimeDB with the schema job, the collector with `devloop-collection`, a stub `gitea-mq.service` and the reconcile, and SHALL be run before the merge of any change to the S2 receivers, the pipelines or the reconcile.

**Discharged by**: the tests' own cases; the record of each run in the change that triggers it.

#### Scenario: The cases are run

- **WHEN** the tests run
- **THEN** `devloop-ingest` runs the first-start, writer-ordering, overlap, table-shape, configuration-switch, burn-rule-query and documented-query cases, and `devloop-ingest-reconcile` runs the first-start case and one mutant per reconcile comparison, and every mutant makes the reconcile exit non-zero

#### Scenario: The burn rule's query runs on the store

- **WHEN** the burn-rule case loads `ci_build` with 10 pull-request builds of which 2 waited over an hour, then 9 of which 2 did, then 10 of which 1 did with a rerun row of a fast build that waited over an hour, and runs the rule's SQL each time
- **THEN** only the first returns a row

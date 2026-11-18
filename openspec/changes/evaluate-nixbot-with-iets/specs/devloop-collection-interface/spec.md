## ADDED Requirements

### Requirement: nixbot's evaluation records are parsed from its journal

magnetite's collector SHALL run `journald/nixbot-eval` with `units: [nixbot.service]`, a `grep` matching nixbot's `"msg": "evaluation finished"` lines only, `start_at: beginning`, `storage: file_storage` and the `journalctl_path` wrapper adding `--boot=all`, then a `json_parser` from `body.MESSAGE` into attributes, a `retain` of the allow-listed `eval_run` keys, and the removal of the body, feeding `logs/devloop-eval_run`.

**Discharged by**: `devloop-reconcile`'s comparison of evaluation records, resting on world assumption `A146 — nixbot evaluates in a sandbox that sees neither the journal nor the cgroup tree, in a cgroup it removes after the run`; `vmTests.x86_64-linux.devloop-ingest`'s stub `nixbot.service` with its mutant lacking `json_parser`.

#### Scenario: The parser is removed

- **WHEN** `devloop-ingest` runs a collector configuration without the `json_parser` against the stub's fixture lines
- **THEN** the rows do not reach `eval_run` and `devloop-reconcile` exits non-zero

#### Scenario: nixbot logs another message

- **WHEN** the stub prints nixbot's `starting evaluation` line
- **THEN** no `eval_run` row is written for it

### Requirement: devloop-reconcile compares evaluation records with the journal every day

Over its day, the reconcile SHALL exit non-zero when a `nixbot.service` journal line with `msg` `evaluation finished` has no `eval_run` row with its `build_id` and `ts`, or an `eval_run` row of the day has no such line; it SHALL read the journal with `--boot=all` and count before it reads keys.

**Discharged by**: `vmTests.x86_64-linux.devloop-ingest`'s evaluation case and its dropped-row mutant, resting on world assumption `A146 — nixbot evaluates in a sandbox that sees neither the journal nor the cgroup tree, in a cgroup it removes after the run`.

#### Scenario: A record is lost between the journal and the store

- **WHEN** `devloop-ingest` deletes one `eval_run` row of the window before the reconcile runs
- **THEN** the reconcile exits non-zero naming one missing key, and passes on the unmutated run

## MODIFIED Requirements

### Requirement: The devloop tables are pre-created with keys, a time index and deduplication

`greptimedb-schema.service` SHALL, after the databases, issue `CREATE TABLE IF NOT EXISTS` for `devloop.ci_attribute`, `devloop.ci_build`, `devloop.batch_event`, `devloop.deploy_record` and `devloop.eval_run`, each `ENGINE=mito WITH ('append_mode' = 'false', 'sst_format' = 'flat')`, with every identifier quoted, its allow-listed primary key, a `TIMESTAMP(6) NOT NULL` time index and no `ttl`.

**Discharged by**: R3.1's ordering clause, which keeps the collector after `greptimedb-schema`, and `greptimedb-envelope`'s table clause, resting on world assumption `A46 — GreptimeDB 1.2.1 keeps one row per key and time in a pre-created non-append table`; `vmTests.x86_64-linux.devloop-ingest`'s first-start and writer-ordering cases; `devloop-reconcile`'s comparison of CI rows with its append-mode mutant.

#### Scenario: The tables exist before the collector's first write

- **WHEN** `devloop-ingest` starts the store, the schema job and the collector
- **THEN** every `otlp_http/devloop_<table>` exporter reports zero failed log records after its first send

#### Scenario: The schema job omits a table

- **WHEN** `devloop-ingest`'s mutant schema job creates no `ci_build`
- **THEN** `otlp_http/devloop_ci_build`'s first send is refused with HTTP 400 and its failed log-record count is non-zero, so the case fails

#### Scenario: A table is created in append mode

- **WHEN** `devloop-ingest`'s mutant creates `ci_attribute` with `'append_mode' = 'true'` and the collector re-reads its overlap
- **THEN** duplicate keys are stored and `devloop-reconcile` exits non-zero

### Requirement: One devloop allow-list decides every stored column

`flake.lib.otelCollectorSchema.devloop.tables` SHALL be the single declaration of the `devloop` tables' columns, types, primary keys and time indexes, and the table statements, the pipelines, the gitea-mq, deploy-record and nixbot-evaluation keep-lists and the nixbot queries' output columns SHALL be rendered from it.

**Discharged by**: `checks.x86_64-linux.devloop-queries`' comparison of returned columns with the list; `vmTests.x86_64-linux.devloop-ingest`'s comparison of `DESC TABLE` with the list.

#### Scenario: The allow-list is evaluated

- **WHEN** `flake.lib.otelCollectorSchema.devloop.tables` is evaluated
- **THEN** it declares `ci_attribute` (`build_id`, `attr`, `system`, `status`, `cached`, `abandoned`, `drv_path`, `outputs_out`, `started_at`, `finished_at`, `eval_wall_ms`, `eval_alloc_bytes`, `commit_sha`, `branch`, `pr_number`, `project`; key `build_id`, `attr`; time `finished_at`), `ci_build` (`build_id`, `created_at`, `started_at`, `finished_at`, `eval_duration_ms`, `status`, `pr_number`, `branch`; key `build_id`; time `finished_at`), `batch_event` (`batch`, `msg`, `build`, `sha`, `failed_check`, `members`, `landed`, `ejected`, `builds`, `flaky`, `ts`; key `batch`, `msg`; time `ts`), `deploy_record` (`host`, `closure`, `previous_closure`, `ts`; key `host`; time `ts`) and `eval_run` (`build_id`, `evaluator`, `evaluator_version`, `workers`, `max_memory_mib`, `memory_max_bytes`, `memory_peak_bytes`, `oom_kill`, `wall_ms`, `user_ms`, `system_ms`, `budget_kills`, `worker_kills`, `exit_status`, `ts`; key `build_id`; time `ts`)


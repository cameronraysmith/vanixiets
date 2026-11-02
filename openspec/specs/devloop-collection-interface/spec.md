# devloop-collection-interface Specification

## Purpose
This capability (stratum: `interface`) states the properties at the machine's interface that discharge the `devloop-collection` requirements: the two nixbot cursor queries with their overlap, page size, allow-listed text columns and abandonment marker; the readers' peer authentication and column grants; the gitea-mq journal parse; the deploy-record snippet on every machine, held by the five x86_64-linux NixOS machine checks, and magnetite's file receiver; the pre-created `devloop` tables, their ingest pipelines and the one allow-list behind both; the logs routing; `devloop-reconcile`'s daily comparisons; and the checks `devloop-queries` and `devloop-ingest`.
Trust boundary: nixbot and gitea-mq produce the source rows and lines and this machine only reads them, trusting their schema and messages at the pinned revisions; any root process on magnetite can read the `regulator` password and the deploy-record file, which is world-readable on every host; hosts other than magnetite write deploy records that no collector ships until S4 and S5; nothing here guarantees that a given event reaches the store, only that each stage's configuration, the gating checks, the container test and the daily reconcile behave as stated.

## Requirements

### Requirement: The collector reads nixbot's builds and attributes through two cursor queries

magnetite's collector SHALL run `sqlquery/ci_attribute`, over `build_attributes` joined to `builds` and `projects`, and `sqlquery/ci_build`, over `builds`, each with driver `postgres`, datasource `host=/run/postgresql dbname=nixbot user=opentelemetry-collector sslmode=disable`, `collection_interval: 60s`, `storage: file_storage`, `tracking_column: finished_at` and `tracking_start_value: "1970-01-01T00:00:00.000000Z"`.

**Discharged by**: `checks.x86_64-linux.devloop-queries`, resting on world assumptions `A43 — nixbot's migrations create the build and attribute columns the dev-loop copy reads, and finish times are transaction start times` and `A47 — The collector's sqlquery receiver resumes logs queries from the last row's tracking value`; `devloop-reconcile`'s comparison of CI rows; the operator's `EXPLAIN ANALYZE` of both queries at deploy.

#### Scenario: The queries are measured at deploy

- **WHEN** the collector has started on magnetite
- **THEN** the operator records `EXPLAIN ANALYZE` of each query run as `opentelemetry-collector` with the live cursor

#### Scenario: A column the query reads is renamed

- **WHEN** `checks.x86_64-linux.devloop-queries`' fixture migration renames `build_attributes.cached`
- **THEN** the attribute query fails and the check fails

### Requirement: Each nixbot query re-reads a five-minute overlap in pages of 10,000 rows

Each nixbot query SHALL select rows with `finished_at >= least($1::timestamptz, now() - interval '5 minutes')`, ordered by `finished_at`, with `LIMIT 10000`.

**Discharged by**: `checks.x86_64-linux.devloop-queries`' overlap fixtures; `vmTests.x86_64-linux.devloop-ingest`'s overlap case; the operator's measurement of the widest `finished_at` tie at deploy.

#### Scenario: Recent, tied and old rows

- **WHEN** the check runs a query with a cursor 10 minutes old, and again with a cursor 1 minute old
- **THEN** the first returns a row 4 minutes old and every row tied with the cursor, and the second does not return a row 7 minutes old

#### Scenario: The widest tie is measured

- **WHEN** the collector has started on magnetite
- **THEN** the operator records the largest number of attribute rows sharing one `finished_at`, which must be below 10,000

### Requirement: Each nixbot query returns only allow-listed columns as text

Each nixbot query SHALL select exactly its table's allow-listed columns in allow-list order, each as text with a null as the empty string and each timestamp as `to_char(<column> AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`, plus a constant empty `body` as its body column, with `outputs_out` taken from `outputs ->> 'out'` and `project` as `owner || '/' || name`, and SHALL select no `error` column.

**Discharged by**: `checks.x86_64-linux.devloop-queries`, whose error-cell clause finds none of the fixtures' error texts in any cell the attribute query returns, with its selected-error and error-under-alias mutants; the query's aliases and the expected columns are both rendered from the allow-list, so the check does not compare them (S2 review F4).

#### Scenario: A query gains the error column

- **WHEN** the check's mutant adds `a.error` to the attribute query's SELECT list
- **THEN** a returned cell holds a fixture's error text and the check fails

### Requirement: The attribute query derives abandoned from the shared marker

The attribute query SHALL compute `abandoned` as `status = 'ignored_failure' AND error IS NOT DISTINCT FROM <abandonMarker>`, where `<abandonMarker>` is `flake.lib.devloopCollection.abandonMarker`, rendered as a literal.

**Discharged by**: `checks.x86_64-linux.devloop-queries`' fixtures and its marker clause.

#### Scenario: Three kinds of ignored failure

- **WHEN** the check's fixtures hold an `ignored_failure` row with the marker, one with other error text and one with a null `error`
- **THEN** only the first returns `abandoned` as `true`

### Requirement: The nixbot readers authenticate by peer and hold column grants only

magnetite SHALL declare the PostgreSQL roles `opentelemetry-collector` and `devloop-reconcile` through `services.postgresql.ensureUsers` with no password, SHALL grant each only column-level `SELECT` on the columns its queries use, and SHALL create no index, view, function or trigger in nixbot's database.

**Discharged by**: `checks.x86_64-linux.devloop-queries`, which applies the rendered grants and runs each reader's queries as its role, with its reduced-grant mutant, resting on world assumption `A45 — PostgreSQL on magnetite admits a local role named after the connecting system user without a password`.

#### Scenario: The grants are rendered

- **WHEN** the grant statements are rendered
- **THEN** `opentelemetry-collector` holds `builds (id, project_id, commit_sha, branch, pr_number, status, created_at, started_at, finished_at, eval_duration_ms)`, `build_attributes (build_id, attr, system, status, cached, error, drv_path, outputs, started_at, finished_at, eval_wall_ms, eval_alloc_bytes)` and `projects (id, owner, name)`, and `devloop-reconcile` holds `builds (id, branch, finished_at)` and `build_attributes (build_id, attr, finished_at)`

#### Scenario: A grant lacks a column a query refers to

- **WHEN** the check's mutant renders the collector's grant without `build_attributes.error`
- **THEN** the attribute query is refused with a permission error and the check fails

### Requirement: Column grants are applied once nixbot's columns exist

magnetite SHALL run `devloop-pg-grants.service`, a oneshot as `postgres` with `RemainAfterExit`, ordered after `postgresql.service`, `postgresql-setup.service` and `nixbot.service` and wanted by `multi-user.target`, which, once per boot and at an activation only when the unit changes, waits up to 300 s for every granted column, then grants, failing if one is absent.
It SHALL NOT be described as re-applying a grant that a later nixbot migration removes; such a loss is detected, not repaired.

**Discharged by**: the unit's failure notice through `services.observability-notify.units`; the operator's observation at deploy that both roles can run their queries; for a grant lost later, the collector's query errors and `devloop-reconcile`'s comparisons of CI rows, whose container mutants show them failing on missing rows.

#### Scenario: A granted column does not appear

- **WHEN** a granted column is absent from nixbot's database 300 s after the unit starts
- **THEN** `devloop-pg-grants.service` fails and a failure notice names it and magnetite

#### Scenario: A later migration drops and re-adds a granted column

- **WHEN** a nixbot migration drops and re-creates a column one of the readers is granted, after the unit has run
- **THEN** that reader's query fails with a permission error, its rows stop arriving, and the next morning's reconcile fails on its CI comparisons or exits 2

### Requirement: gitea-mq's five batch messages are parsed from its journal

magnetite's collector SHALL run `journald/gitea-mq` with `units: [gitea-mq.service]`, `grep: 'msg="batch (formed|built|landed|bisecting|done)"'`, `start_at: beginning`, `storage: file_storage` and a `journalctl_path` wrapper adding `--boot=all`, so it reads every retained boot, then a `key_value_parser` from `body.MESSAGE` into attributes, a `retain` of the allow-listed `batch_event` keys, and the removal of the body, keeping the record's journal timestamp.

**Discharged by**: `devloop-reconcile`'s comparison of batch events, resting on world assumption `A44 — gitea-mq announces each batch transition in one of five exact journal messages`; `vmTests.x86_64-linux.devloop-ingest`'s stub `gitea-mq` with its mutant lacking `key_value_parser`.

#### Scenario: The parser is removed

- **WHEN** `devloop-ingest` runs a collector configuration without `key_value_parser` against the stub's fixture lines
- **THEN** the rows do not reach `batch_event` and `devloop-reconcile` exits non-zero

#### Scenario: A further message begins with batch

- **WHEN** the stub prints `msg="batch reconcile build failed"`
- **THEN** no `batch_event` row is written for it

### Requirement: The collector's journal read is asserted

`devloop-collection.nix` SHALL assert that magnetite's `opentelemetry-collector.service` carries `systemd-journal` in `SupplementaryGroups`.

**Discharged by**: the assertion, with its `extendModules` mutant.

#### Scenario: The collector loses journal read

- **WHEN** an `extendModules` override clears the collector's `SupplementaryGroups`
- **THEN** magnetite's evaluation fails on the assertion

### Requirement: Each activation appends one deploy record

`flake.modules.nixos.deploy-record`, as `system.activationScripts.deploy-record` without dry-activation support, and `flake.modules.darwin.deploy-record`, added to `system.activationScripts.postActivation`, SHALL append to `/var/log/deploy-record.jsonl`, mode `0644`, one JSON line with `host` the evaluated `networking.hostName`, `closure` the activated `$systemConfig`, `previous_closure` the target of `/run/current-system` when it exists, else absent, and `ts` from `date -u +%Y-%m-%dT%H:%M:%SZ`.

**Discharged by**: `devloop-reconcile`'s comparison of deploy records, resting on world assumption `A49 — NixOS and nix-darwin run activation snippets before the current system is relinked`; `vmTests.x86_64-linux.devloop-ingest`'s switch case; the operator's recorded deploy and boot lines at deploy.

#### Scenario: A node switches to a second system

- **WHEN** `devloop-ingest` switches its node from one system to another, the second its configuration extended by `extendModules`
- **THEN** exactly one line is appended, naming the second as `closure` and the first as `previous_closure`

#### Scenario: The configuration switch cannot run in a container

- **WHEN** the switch case finds no `switch-to-configuration` in the container's second system, as nixpkgs' nspawn container module builds it
- **THEN** the case runs that system's activation script, which sets `$systemConfig`, instead, and the limitation is recorded with the run

### Requirement: Each agent host's collector ships its own deploy records

Each agent host's collector SHALL read `/var/log/deploy-record.jsonl` through `file_log/deploy-record`, defined in the agent role, with `start_at: beginning`, `storage: file_storage` and `json_parser`, keeping `host`, `closure`, `previous_closure` and `ts`, under the receiver id and settings magnetite used before, so magnetite's stored offset carries over.

**Discharged by**: `devloop-reconcile`'s comparison of deploy records on magnetite; `vmTests.x86_64-linux.devloop-ingest`'s first-start case; `vmTests.x86_64-linux.fleet-ingress`'s delivery case; the operator's line-count comparison at each agent host's first deploy.

#### Scenario: The receiver reads another file

- **WHEN** `devloop-ingest`'s mutant points `file_log/deploy-record` at another path
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

- **WHEN** `devloop-ingest`'s mutant creates `ci_attribute` with `'append_mode' = 'true'` and the collector re-reads its overlap
- **THEN** duplicate keys are stored and `devloop-reconcile` exits non-zero

### Requirement: Each devloop table has an ingest pipeline that keeps only its allow-listed fields

`greptimedb-schema.service` SHALL post one pipeline per table to `/v1/pipelines/devloop_<table>?db=devloop`, failing on any answer but 200, whose `vrl` step resets the event with `. = {}` and then assigns exactly the table's allow-listed fields, each on its own line, with an empty string as null, whose `date` step parses `%Y-%m-%dT%H:%M:%S%.fZ` or `%Y-%m-%dT%H:%M:%SZ`, which declares the primary key as tags, and which takes `batch_event`'s `ts` from the record's timestamp.

**Discharged by**: `vmTests.x86_64-linux.devloop-ingest`'s table-shape case, which compares each table's `DESC TABLE` with the allow-list after ingest, and its pipeline mutant that drops `flaky`.

#### Scenario: The stored columns are read back

- **WHEN** `devloop-ingest` has ingested its fixtures
- **THEN** each table's `DESC TABLE` lists exactly its allow-listed columns, none of them `body`

### Requirement: One devloop allow-list decides every stored column

`flake.lib.otelCollectorSchema.devloop.tables` SHALL be the single declaration of the `devloop` tables' columns, types, primary keys and time indexes, and the table statements, the pipelines, the gitea-mq and deploy-record keep-lists and the nixbot queries' output columns SHALL be rendered from it.

**Discharged by**: `checks.x86_64-linux.devloop-queries`' comparison of returned columns with the list; `vmTests.x86_64-linux.devloop-ingest`'s comparison of `DESC TABLE` with the list.

#### Scenario: The allow-list is evaluated

- **WHEN** `flake.lib.otelCollectorSchema.devloop.tables` is evaluated
- **THEN** it declares `ci_attribute` (`build_id`, `attr`, `system`, `status`, `cached`, `abandoned`, `drv_path`, `outputs_out`, `started_at`, `finished_at`, `eval_wall_ms`, `eval_alloc_bytes`, `commit_sha`, `branch`, `pr_number`, `project`; key `build_id`, `attr`; time `finished_at`), `ci_build` (`build_id`, `created_at`, `started_at`, `finished_at`, `eval_duration_ms`, `status`, `pr_number`, `branch`; key `build_id`; time `finished_at`), `batch_event` (`batch`, `msg`, `build`, `sha`, `failed_check`, `members`, `landed`, `ejected`, `builds`, `flaky`, `ts`; key `batch`, `msg`; time `ts`) and `deploy_record` (`host`, `closure`, `previous_closure`, `ts`; key `host`; time `ts`)

### Requirement: Dev-loop sources are stamped and routed to their table

Each dev-loop receiver SHALL feed its own `logs/devloop-<table>` pipeline through `memory_limiter` and a `resource/devloop-<table>` processor that sets `vanixiets.database` to `devloop`, `vanixiets.table` to its table and `host.name`, ending in `forward` on the ingress host and in `otlp_http/ingress-logs` elsewhere, and no `logs/*` pipeline SHALL take an OTLP receiver other than `otlp/mesh`.

**Discharged by**: the R3.1 collector check's clause that no logs pipeline takes an OTLP receiver other than `otlp/mesh`, with its mutant; `vmTests.x86_64-linux.devloop-ingest`'s first-start case and `vmTests.x86_64-linux.fleet-ingress`'s delivery case, in which each table receives its rows.

#### Scenario: The local receiver is added to a logs pipeline

- **WHEN** a mutant of magnetite's collector configuration adds a local OTLP receiver to `logs/devloop-ci_build`
- **THEN** the evaluation-time collector check (R3.1) fails

#### Scenario: Another host's deploy records reach the logs route

- **WHEN** an agent host without the ingress role is evaluated
- **THEN** its `logs/devloop-deploy_record` pipeline ends in `otlp_http/ingress-logs`, and on magnetite `logs/ingress` receives from both `forward` and `otlp/mesh` into the unchanged `routing/logs`

### Requirement: devloop-reconcile runs daily as its own reader

magnetite SHALL run `devloop-reconcile.service`, a oneshot with `DynamicUser`, `SupplementaryGroups = [ "systemd-journal" ]`, `LoadCredential=regulator-password`, `MemoryMax = "128M"` and `TimeoutStartSec = "10min"`, ordered after `postgresql.service`, `greptimedb.service`, `greptimedb-schema.service` and `devloop-pg-grants.service` with no `wants`, from `devloop-reconcile.timer` at `*-*-* 02:15:00 UTC` with `Persistent = true`.

**Discharged by**: magnetite's credential-holder assertion (R8.2) with its `extendModules` mutant; R3.1's failure-wiring clause; the operator's recorded memory peak of the first scheduled run.

#### Scenario: The day and database are overridden

- **WHEN** the unit runs with `DEVLOOP_RECONCILE_DAY` or `DEVLOOP_RECONCILE_DATABASE` set
- **THEN** it compares that UTC day, or reads that store database, instead of yesterday and `devloop`

#### Scenario: The reconcile fails on magnetite

- **WHEN** at deploy the operator starts the reconcile under a drop-in setting `DEVLOOP_RECONCILE_DATABASE=devloop_absent`
- **THEN** the unit fails, `FAILED devloop-reconcile.service on magnetite` reaches `fleet-alerts`, a start without the drop-in posts its `RESOLVED`, and the operator records both

### Requirement: devloop-reconcile compares CI rows with nixbot every day

Over its day, the reconcile SHALL exit non-zero when a nixbot `(build_id, attr, finished_at)` is missing from `ci_attribute`, or a stored key is absent from nixbot unless nixbot's current `finished_at` for that `(build_id, attr)` is null or later, or, when nixbot no longer has the attribute, its build's current `finished_at` is null or later, and likewise for `builds` and `ci_build`; each store query SHALL count before it reads keys.

**Discharged by**: `vmTests.x86_64-linux.devloop-ingest`'s cached-row and null-`pr_number` mutants, each failing with as many missing keys as nixbot holds of its kind, its append-mode mutant, and its restarted-build leg.

#### Scenario: The collector omits cached outcomes

- **WHEN** `devloop-ingest` runs the reconcile against a collector whose attribute query omits `cached = true` rows, and against a build query that omits rows with a null `pr_number`
- **THEN** the reconcile exits non-zero on each, and passes on the unmutated configuration

#### Scenario: A restarted attribute is accepted

- **WHEN** a fixture attribute finished in the window is restarted after it and finishes again
- **THEN** the reconcile accepts the stored earlier row and passes

#### Scenario: A restarted build drops a finished attribute

- **WHEN** a fixture build is restarted after the window and nixbot deletes one of its attributes that finished in the window, as nixbot does for a system it no longer builds
- **THEN** the reconcile accepts the stored row of that attribute and passes

### Requirement: devloop-reconcile compares batch events with the journal every day

Over the same day, the reconcile SHALL exit non-zero when the per-`msg` count of `gitea-mq.service` journal lines matching the five messages, filtered on `__REALTIME_TIMESTAMP`, differs from `batch_event`'s; when nixbot finished a build on a `gitea-mq/batch/` branch and `batch_event` holds no `batch built` row; or when a `batch done` row has a null `landed`, `ejected`, `builds` or `flaky`.

**Discharged by**: `vmTests.x86_64-linux.devloop-ingest`'s parser, silent-stub and dropped-`flaky` mutants, resting on world assumption `A48 — magnetite's journal keeps gitea-mq's lines for longer than the reconcile's window`.

#### Scenario: The merge queue falls silent

- **WHEN** `devloop-ingest`'s stub `gitea-mq` prints nothing while fixture batch-branch builds exist
- **THEN** the reconcile exits non-zero

#### Scenario: A batch done row loses a field

- **WHEN** `devloop-ingest`'s mutant pipeline drops `flaky`
- **THEN** the reconcile exits non-zero

### Requirement: devloop-reconcile compares deploy records with the file and the current system

Over the same day, the reconcile SHALL exit non-zero when the count of `/var/log/deploy-record.jsonl` lines differs from magnetite's `deploy_record` rows, or when magnetite's latest stored `closure` differs from `readlink -f /run/current-system`.

**Discharged by**: `vmTests.x86_64-linux.devloop-ingest`'s receiver-path and wrong-closure mutants.

#### Scenario: The snippet records the wrong closure

- **WHEN** `devloop-ingest`'s mutant snippet writes the previous closure as `closure`
- **THEN** the reconcile exits non-zero

### Requirement: devloop-queries binds the export queries to nixbot's migrations

`checks.x86_64-linux.devloop-queries` SHALL start PostgreSQL of the major version `flake.lib.devloopCollection.postgresqlMajor` through `postgresqlTestHook`, apply the nixbot input's migrations in lexical order, each with `psql -v ON_ERROR_STOP=1 --single-transaction`, create both roles with the rendered grants, load fixtures, run the export queries and the reconcile's PostgreSQL queries as their roles, and fail on each of its mutants, within an evaluation budget of 0.5 GiB.

**Discharged by**: the check's renamed-column, selected-error and reduced-grant mutants; magnetite's module assertion that its PostgreSQL major version equals `flake.lib.devloopCollection.postgresqlMajor`, with its `extendModules` mutant; the plan-time comparison of its `pg_dump --schema-only` of `builds`, `build_attributes` and `projects` with magnetite's; the measurement of its evaluation cost with `NIX_SHOW_STATS`.

#### Scenario: The check's evaluation cost is measured

- **WHEN** `NIX_SHOW_STATS=1 nix eval --raw .#.checks.x86_64-linux.devloop-queries.drvPath` is run
- **THEN** its evaluation stays within the 0.5 GiB budget, and the figure and method are recorded

#### Scenario: magnetite's PostgreSQL major version changes

- **WHEN** magnetite's configuration is evaluated with a PostgreSQL package whose major version differs from `flake.lib.devloopCollection.postgresqlMajor`
- **THEN** magnetite's evaluation fails on the module assertion, which an `extendModules` override shows

#### Scenario: Lexical application differs from nixbot's schema

- **WHEN** the check's schema dump differs from magnetite's for the three tables
- **THEN** the check applies the migrations with nixbot's own migrator from the input instead, and the difference is recorded

### Requirement: devloop-queries binds the abandonment marker to the patch's production code

`checks.x86_64-linux.devloop-queries` SHALL fail unless `modules/nixos/nixbot-abandon-optional-attributes.patch` contains `flake.lib.devloopCollection.abandonMarker`, enclosed in double quotes, on the added line between `return AttributeStatus.ignored_failure, (` and `if outcome == BuildOutcome.abandoned`.

**Discharged by**: the check's marker clause, which compares `abandonMarker` with the patch text; the measurement of the check's evaluation cost with `NIX_SHOW_STATS`.

#### Scenario: The marker drifts from the patch

- **WHEN** the marker differs from the patch's production literal by one character
- **THEN** the check fails

#### Scenario: Only the patch's tests carry the marker

- **WHEN** the production literal changes while the patch's test assertions keep the old text
- **THEN** the check fails, because only the production context satisfies it

### Requirement: The x86_64-linux NixOS machine checks carry the deploy-record snippet

`modules/checks/machines.nix` SHALL, for every machine check it builds, fail unless the machine's activation script as the platform assembles it contains the script `deploy-record.nix` renders, read from `system.activationScripts.script` on NixOS and `system.activationScripts.script.text` on darwin, so the obligation fails however the entry is dropped.

**Discharged by**: the obligation's negative control over a configuration whose activation entry an `extendModules` override drops.

#### Scenario: A machine drops the snippet

- **WHEN** the negative control evaluates the obligation over magnetite's configuration without the `deploy-record` activation entry
- **THEN** the obligation returns a non-empty failure list

#### Scenario: The obligation's coverage is reported

- **WHEN** someone asks which machines CI holds to the obligation
- **THEN** the answer is the five x86_64-linux NixOS machine checks; the four darwin machines' checks run best-effort, so their failure blocks no merge, and `scheelite`'s is deferred, so those five machines are shown carrying the snippet once by evaluation when it is introduced and are not described as held by CI

### Requirement: devloop-ingest shows the collection path and the reconcile able to fail

`vmTests.x86_64-linux.devloop-ingest` SHALL be a systemd-nspawn container test requiring `uid-range`, run on demand on magnetite, running PostgreSQL with the nixbot input's migrations, GreptimeDB with the schema job, the collector with `devloop-collection`, a stub `gitea-mq.service` and the reconcile, and SHALL be run before the merge of any change to the S2 receivers, the pipelines or the reconcile.

**Discharged by**: the test's own cases; the record of each run in the change that triggers it.

#### Scenario: The cases are run

- **WHEN** the test runs
- **THEN** it runs the first-start, writer-ordering, overlap, table-shape, configuration-switch, burn-rule-query and documented-query cases and one mutant per reconcile comparison, and every mutant makes the reconcile exit non-zero

#### Scenario: The burn rule's query runs on the store

- **WHEN** the burn-rule case loads `ci_build` with 10 pull-request builds of which 2 waited over an hour, then 9 of which 2 did, then 10 of which 1 did with a rerun row of a fast build that waited over an hour, and runs the rule's SQL each time
- **THEN** only the first returns a row

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a dev-loop event reaches the store.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that the queries, the journal parse and the deploy snippet select, parse and write the stated fields; that the tables, pipelines and routes carry them into `devloop` keyed as stated; that the readers authenticate by peer under column grants; and that the reconcile compares each signal with its source daily, each as far as its check, container test or recorded observation reaches

#### Scenario: A guarantee about the sources is sought

- **WHEN** someone asks whether an event nixbot or gitea-mq never records is detected
- **THEN** the answer is no: nixbot and gitea-mq produce the source rows and lines, this machine only reads them, and their schema and messages are trusted at the pinned revisions

#### Scenario: A guarantee about secrecy is sought

- **WHEN** someone asks whether only the reconcile can read the `regulator` password or the deploy-record file
- **THEN** the answer is no: any root process on magnetite can read both, and the deploy-record file is world-readable on every host

#### Scenario: A guarantee about other hosts is sought

- **WHEN** someone asks whether deploys on hosts other than magnetite reach `devloop` and are reconciled
- **THEN** the answer is no for reconciliation: every NixOS agent host ships its records through the ingress, but `devloop-reconcile` compares magnetite's alone, the darwin machines ship none until they run collectors of their own, and the snippets are held by the build-time check only on the five x86_64-linux NixOS machines

#### Scenario: A guarantee about a record's host is sought

- **WHEN** someone asks whether a `deploy_record` row's `host` proves which host sent it
- **THEN** the answer is no: any holder of an `otel-ca` certificate can send a row naming any host

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that a given event reaches the store
- **THEN** the answer is no: each stage's configuration, the gating checks, the container tests and the daily reconcile behave as stated, and nothing here observes every event's whole path

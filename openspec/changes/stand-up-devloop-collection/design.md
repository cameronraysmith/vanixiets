## Context

This change is slice S2 of the fleet observability implementation (RA:252-254; Linear CAM-69).
It realizes ADR-005 except the omp emitter, which S7 realizes, and its component `devloop-exporters`, and it lands the dev-loop SLO burn rule that S3 deferred (S3 D8; CH:332) with S3's review finding F10 (CH:356).
`brainstorm.md` records the grounding evidence, the contradictions C1 to C8 and the decision chain D1 to D17, which the operator accepted on 2026-10-21; this document develops that direction into the technical design and fixes the items the brainstorm left for design.
The decision records were amended in place under charter v22 (CH:357-370), so the amended texts are cited as they stand.

Citation keys:
A4, A5 and A9 are ADR-004, ADR-005 and ADR-009 under `docs/notes/development/observability/decisions/`, CH is `docs/notes/development/observability/charter.md`, RA is `architecture/reference-architecture.md` and DX is `components/devloop-exporters.md` under the same directory.
GR is `logs/s2/grounding.md`, SP is `logs/s2/spike-dedup.md`, BP is `logs/s2/brainstorm-prep.md` and BS is this change's `brainstorm.md`.
S1 and S3 are the archived changes `openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/` and `openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/`; S1-R6 and S3-R6 are their `retrospective.md` §6.
FM is `modules/clan/services/otel-collector/flake-module.nix`, SC is `modules/clan/services/otel-collector/schema.nix`, GN is `modules/nixos/greptimedb.nix`, FA is `modules/nixos/fleet-alert.nix`, MG is `modules/machines/nixos/magnetite/default.nix` and MC is `modules/checks/machines.nix`.

The current state:

- magnetite runs S1's store and collector and S3's evaluator; `devloop` exists with a 365-day TTL and holds no table, and no ingest pipeline has ever been created (GR §3).
- The collector is `otelcol-contrib` 0.155.0 with `metrics/*` pipelines only; the ingress `routing` connector routes on the resource attribute `vanixiets.database` to one `otlp_http/<db>` exporter per database, each with a `file_storage` queue and infinite retry (FM:375-432; GR §4.1).
- The collector already runs with `SupplementaryGroups=systemd-journal`, set by nixpkgs' module (GR §4.2), and its build names the file receiver `file_log` and rates `sqlquery`'s logs signal at Development (GR §4.2).
- nixbot runs against PostgreSQL 16.15 over the Unix socket, and every local connection is peer-authenticated (GR §1.1).
- gitea-mq writes its batch lines through slog's text handler to the journal under `_SYSTEMD_UNIT=gitea-mq.service` with `SYSLOG_IDENTIFIER=gitea-mq-start` (GR §2.1).
- The evaluator sends every rule as PromQL to `fleet` (FA:90, :110-134, :529), and its fixture server answers 400 to any other database (`modules/checks/fleet-alert/fixture_server.py:107-108`).

Pins:

- gitea-mq is pinned at `02264515b` in the working copy and on `origin/main`, and its five batch messages are at `internal/batch/batch.go:143`, `:228`, `:328`, `:391` and `:568` (GR §2.2).
- nixbot was pinned at `b1f699803` when GR was taken, and magnetite's deployed migrations `0001` to `0037` are byte-identical to that revision's (GR §1.3).
- PR #3536, merged 2026-10-21 17:31 UTC, moved the `nixbot` input on `main` to `d020013fa` (`flake.lock` read through `gh api` at `main` and in the working copy), which magnetite runs after its next deploy.
- Between the two revisions nixbot has three commits, which touch only the CLI, the control API's schedule route and their tests (`git diff --stat b1f699803 d020013fa` in the reference copy): no migration is added or changed, the newest is still `0037_effect_when_changed.sql`, and none of `builds`, `build_attributes`, `projects` or `nixbot/nixbot/migrations.py` changes.
- The local abandonment patch touches `build_run.py`, `build_scheduler.py`, `repo_config.py` and two tests, none of which the bump changes.
- This design is stated against `d020013fa`, and every schema fact GR read at `b1f699803` holds there unchanged.

Constraints that shape every decision below:

- Every S2 signal is a row, not a series (A4:131), and the store must keep no CI error text and no journal message body (A4:108-109; BS D3).
- A pre-created non-append table deduplicates on its primary key and time index under the flat SST format, on the OTLP-with-pipeline path, keeping the last row written; a table the write creates is append-mode and keeps every duplicate; a pipeline that emits an undeclared field adds that column; `auto_create_table=false` turns a write to a missing table into HTTP 400, which the exporter drops as permanent (SP Verdict).
- PostgreSQL's `now()` is the transaction's start time, and nixbot sets `finished_at = now()` (`Mic92/nixbot@d020013fa:nixbot/nixbot/db_gen/builds.py:257`, `:303`, `:352`, `:417`, `:436`), so a row can commit after the cursor has passed its `finished_at` (A5:129).
- nixbot keeps `UNIQUE (build_id, attr)`, so restarting an attribute overwrites its `finished_at` in place (GR §1.2, §1.6; `Mic92/nixbot@d020013fa:nixbot/nixbot/db_gen/events.py:97`).
- Each check states a 0.5 GiB evaluation budget, measured with `NIX_SHOW_STATS=1 nix eval --raw .#.checks.x86_64-linux.<check>.drvPath`; attribute names come from static data only; relations within one host are module assertions (S1-R6; S3-R6).
- Each new clause names its two independently defined value sources before its mutant is written, each reconcile clause names the container-test case that makes it fail, and each new writer names the unit that creates its target and carries an ordering clause with a mutant (S1-R6; S3-R6).

Stakeholders are the operator, who reads `devloop` through D5-R1 to D5-R8 and receives the burn rule's warning, and slices S4 to S8, which reuse the logs path, the tables and the evaluator's SQL path (Later slices).

## Goals / Non-Goals

**Goals:**

- Copy every finished nixbot attribute and build, every gitea-mq batch event and every magnetite activation into `devloop`, within minutes, once each, with no CI error text and no journal message body (E5.1, E5.4, E5.5).
- Prove the copy complete every day with `devloop-reconcile`, and show each of its clauses able to fail in `devloop-ingest` (E5.6).
- Bind the export queries to the schema nixbot's migrations create, and the abandonment marker to the patch text, at check time (E5.2, E5.3).
- Install the deploy-record snippet on all ten machines, held by CI as a machine-check obligation on the five x86_64-linux NixOS machines and shown once by evaluation on the other five (E5.5; BS D12).
- Make batch formation-to-land, the CI queue wait of pull-request builds and per-build CI outcome excluding flaky and abandoned attributes answerable for the past week (BS D7, D8).
- Raise one `warning` when more than 10% of the pull-request builds of the trailing 24 h waited more than 1 h to start, and let every rule declare its database and query language (BS D1, D2; A9 item 15).

**Non-Goals:**

- Shipping deploy records from hosts other than magnetite (S4, S5); every host writes them from this change on (BS D12).
- Dashboards over `devloop` (S6), the omp emitter and `fleet` journald logs (S7), and the Parquet export of `devloop` (S8).
- Any index, view, trigger or other object in nixbot's database (BS D15), and any change to nixbot, gitea-mq or their patches (A5:199).
- Content stages, R8.1 and R8.3; S2's allow-list is enforced by its own query, keep-list and pipelines (BS D3).
- A gating container test; `devloop-ingest` stays on demand (A5:162-166).
- Attributing a `dependency_failed` row to the attribute that failed under it (D8).

## Decisions

### Layout

New files:

| Path | Content |
|---|---|
| `modules/nixos/devloop-collection.nix` | `flake.modules.nixos.devloop-collection`: the two `sqlquery` receivers, the gitea-mq `journald` receiver and the deploy-record `file_log` receiver with their per-table `logs/*` source pipelines; the PostgreSQL roles `opentelemetry-collector` and `devloop-reconcile` through `services.postgresql.ensureUsers`; `devloop-pg-grants.service`; `devloop-reconcile.{service,timer}`; the assertions of D11, D13 and D14; `flake.lib.devloopCollection` with `abandonMarker`, the per-table `select` expressions, the rendered queries, grants, pipelines and DDL, and `flake.lib.devloopReconcile pkgs { … }` as a `writeShellApplication` |
| `modules/system/deploy-record.nix` | `flake.modules.nixos.deploy-record` (a `system.activationScripts.deploy-record` entry) and `flake.modules.darwin.deploy-record` (a `system.activationScripts.postActivation` addition), both from one rendered script, following `modules/system/zt-dns.nix` |
| `modules/checks/devloop-queries.nix` | `checks.x86_64-linux.devloop-queries` (D14) |
| `modules/vm-tests/devloop-ingest.nix` | `perSystem.vmTests.devloop-ingest`, an nspawn container test on magnetite following `modules/vm-tests/greptimedb-pipeline.nix` (D16) |

Changed files:

| Path | Change |
|---|---|
| `modules/clan/services/otel-collector/schema.nix` | `devloop.tables`, the single `devloop` allow-list (D3) |
| `modules/clan/services/otel-collector/flake-module.nix` | the ingress role's `routing/logs` connector, `logs/ingress` and `logs/devloop-<table>` pipelines, one `otlp_http/devloop_<table>` exporter per table, `resource/strip-database` also deleting `vanixiets.table`, and the split of `devloop`'s 48 MiB queue (D4) |
| `modules/nixos/greptimedb.nix` | options `services.greptimedb.tables` and `services.greptimedb.pipelines`, applied by `greptimedb-schema` after the databases (D5) |
| `modules/nixos/fleet-alert.nix`, `modules/nixos/fleet-alert/rules.nix` | per-rule `database` and `language`, `/v1/sql`, the burn rule (D1, D2) |
| `modules/checks/fleet-alert.nix`, `modules/checks/fleet-alert/fixture_server.py` | `/v1/sql`, per-request database recording, the two-database leg, the burn-rule timeline leg and the ignored-database mutant (D2, D17) |
| `modules/checks/machines.nix` | the deploy-record obligation beside `omnigentFleetObligations` (D12) |
| `modules/checks/otel-collector-config.nix` | the failure-wiring clause matches `devloop-*` too; the queue clause reads the split; a new clause that no `logs/*` pipeline takes the OTLP receiver (D4, D11) |
| `modules/machines/nixos/magnetite/default.nix` | imports `devloop-collection`; `regulator-password` holders gain `devloop-reconcile`; `services.observability-notify.units` gains `devloop-reconcile` and `devloop-pg-grants`; the kill-order assertion gains `devloop-reconcile` (D11) |
| the NixOS and darwin machine aggregates | import `deploy-record` on all ten machines (D12) |
| ADR-004, ADR-005, `devloop-exporters`, the operator page | the build-timing columns (CH:369, done); the operator page on querying `devloop` (Migration Plan PR 6) |

Units added on magnetite:

| Unit | User | Role |
|---|---|---|
| `opentelemetry-collector.service` | existing `DynamicUser`, `SupplementaryGroups=systemd-journal` from nixpkgs | gains the three S2 receivers and the logs routes |
| `devloop-pg-grants.service` | `postgres`, oneshot, `RemainAfterExit` | creates the column grants of D10 once nixbot's columns exist |
| `devloop-reconcile.timer`, `devloop-reconcile.service` | `DynamicUser`, `SupplementaryGroups=systemd-journal`, `LoadCredential=regulator-password` | the daily E5.1, E5.4 and E5.5 regulator (D11) |

### Data flow

```
nixbot PostgreSQL (peer, role opentelemetry-collector)
  sqlquery/ci_attribute ─┐  every 60 s, cursor in file_storage
  sqlquery/ci_build ─────┤
journald gitea-mq.service┤  grep the five msg values, key_value_parser, keep-list, body dropped
file_log deploy-record ──┘  /var/log/deploy-record.jsonl, json_parser
        │ logs/devloop-<table>: memory_limiter, resource/devloop-<table>
        │   (vanixiets.database=devloop, vanixiets.table=<table>, host.name)
        ▼
     forward ─▶ logs/ingress: memory_limiter ─▶ routing/logs
        ▼ (database, table)
     logs/devloop-<table>-out: resource/strip-database ─▶ otlp_http/devloop_<table>
        │ POST 127.0.0.1:4000/v1/otlp/v1/logs, basicauth collector,
        │ x-greptime-db-name: devloop, x-greptime-log-table-name: <table>,
        │ x-greptime-pipeline-name: devloop_<table>, x-greptime-hints: auto_create_table=false
        ▼
GreptimeDB pipeline devloop_<table> (vrl keeps exactly the allow-listed fields)
        ▼
devloop.<table>, pre-created by greptimedb-schema, append_mode=false, sst_format=flat

devloop-reconcile.timer (02:15 UTC) ─▶ devloop-reconcile.service
   psql (peer, role devloop-reconcile) · journalctl -u gitea-mq.service -o json
   · /var/log/deploy-record.jsonl · /run/current-system · greptimedb-sql as regulator
   ─▶ exit non-zero on any difference ─▶ OnFailure=observability-notify@%n.service

fleet-alert.service ─▶ PromQL rules: /v1/prometheus/api/v1/query, x-greptime-db-name: fleet
                   └▶ SQL rule:     /v1/sql?db=devloop
```

### D1: The burn rule's minimum count, holding time and query

- **Choice**: `PullRequestQueueWaitBurn`, severity `warning`, `database = "devloop"`, `language = "sql"`, `for = "1h"`, no presence selector, and the query:

```sql
SELECT CAST(sum(CASE WHEN c.started_at > c.created_at + INTERVAL '1 hour' THEN 1 ELSE 0 END) AS DOUBLE) / count(*) AS value
FROM ci_build c
JOIN (SELECT build_id, min(finished_at) AS first_finished FROM ci_build GROUP BY build_id) f
  ON c.build_id = f.build_id AND c.finished_at = f.first_finished
WHERE c.pr_number IS NOT NULL
  AND c.started_at IS NOT NULL
  AND c.finished_at >= now() - INTERVAL '24 hours'
HAVING count(*) >= 10
   AND sum(CASE WHEN c.started_at > c.created_at + INTERVAL '1 hour' THEN 1 ELSE 0 END) * 10 > count(*)
```

- **Rationale**:
  - A pull-request build is a `ci_build` row with `pr_number` set; the build-timing row carries `pr_number` and `branch` since CH:369, because `gitea-mq/batch/<n>` builds have a null `pr_number` and `main` builds are neither (GR §1.6).
  - A build that never started has no queue wait to measure; the 117 such pull-request builds were all `cancelled` (GR §1.5).
  - Only each build's first attempt counts, the row with the smallest `finished_at` for its `build_id`: nixbot's restart clears a build's `started_at` and `finished_at` and keeps its `created_at` (`Mic92/nixbot@d020013fa:nixbot/nixbot/db_gen/maintenance.py:96-123`), so a rerun arrives as a second `ci_build` row whose wait runs from the original request and would count as slow (plan review F1).
    The join reads the whole table, which holds at most a year of builds; that GreptimeDB 1.2.1 runs it is `[INFERENCE]`, confirmed by the `devloop-ingest` burn-rule case.
    Reruns are rare: on 2026-10-21, 1 of the 615 pull-request builds finished in the previous 30 days had a `status_generation` of 2, which nixbot bumps once per settle (`db_gen/builds.py:413-420`; that a second settle marks a rerun is `[INFERENCE]`), and none of the 14 days' slow builds was such a build, so the per-day shares below are unchanged (`logs/s2/burn-rule-reruns-20261021T193007Z.log`).
  - The window is over `finished_at`, the time index, because the store learns a build's wait only when its row arrives at finish, so this is the earliest the store can count it.
  - The minimum of 10 makes one slow build unable to fire the rule: below 10 builds a single slow build exceeds 10%, while from 10 to 19 builds two are needed and from 20 three.
    The 30-day data gives 2 to 43 pull-request builds a day (GR §1.6), so the rule stays silent on quiet days such as 2026-10-07, -09, -11, -16, -18 and -20, and over 14 days it would have fired on the four days whose share of slow builds exceeded 10%, 2026-10-10, -14, -17 and -21, each of which breached D5-R4's bound (GR §1.6).
  - `for = "1h"` means the share must stay above 10% over 61 consecutive passes; the share changes only when a build row arrives or ages out of the window, so an hour damps a firing and resolving pair caused by one build crossing the window edge, and costs an hour on a condition that a 24 h window already makes slow.
  - The query returns a row only when the condition holds, with the single column `value`, so the instance carries no label, is host-less, and its identity does not change as the counts move; a `warning` is never re-posted (A9:94-95).
  - The timestamp comparison `started_at > created_at + INTERVAL '1 hour'` avoids interval arithmetic between two timestamps, and `HAVING` without `GROUP BY` is DataFusion SQL; both are confirmed against GreptimeDB 1.2.1 by the `devloop-ingest` burn-rule case (D16) before merge, because the fixture server cannot check SQL as `promtool` checks PromQL.
- **Regulation**: the burn-rule timeline leg of `checks.fleet-alert` replays the spec scenario `More than one in ten pull-request builds waited over an hour` (D17); the `devloop-ingest` burn-rule case runs the query on the real store with 10 builds of which 2 are slow (one row), 9 of which 2 are slow (none) and 10 of which 1 is slow plus a slow rerun row of a fast build (none).
- **Alternatives considered**: a minimum of 20, rejected because it would silence the rule on most days that breach D5-R4; windows over `created_at` or `started_at`, rejected because rows are absent until finish either way and the time index gives the window directly; `for = "0s"`, rejected for flapping at the window edge; a presence selector over `ci_build`, rejected because a day without pull requests is not a missing signal, and `devloop-reconcile` already fails within a day when rows stop arriving.

### D2: Each rule declares its database and query language

- **Choice**: every rule in `rules.nix` carries `database` (default `fleet`) and `language` (`promql` or `sql`, default `promql`); the evaluator's `query` takes both and sends PromQL to `/v1/prometheus/api/v1/query` with `x-greptime-db-name: <database>`, as today, and SQL as `POST /v1/sql?db=<database>` with `sql=<expr>`, accepting a 200 whose body holds exactly one `records` result; each SQL row becomes one result with `value` from its `value` column and labels from its other columns; the YAML for `promtool` renders only `promql` rules; the evaluator's configuration drops its top-level `database`.
- **Rationale**: PromQL cannot take `started_at - created_at` over rows (BS D2), and one evaluator with one credential keeps one failure path; `?db=` is the form SP used on 1.2.1 for `/v1/sql`.
  A failed or timed-out query, SQL or PromQL, is a store failure of its rule's database only (operator decision on plan review F7): the evaluator stops querying that database for the run and keeps querying the others inside the unchanged 30 s query deadline, and a database whose queries the deadline did not reach counts as failed.
  The observations carry `storeErrors`, the sorted list of databases that failed in the run, replacing the boolean `storeError` with no alias; `transition.jq` freezes an instance only when its rule's database is in `storeErrors`, and raises one `StoreQueryFailing`, `critical`, `for` 3 min, per failing database, labelled `database`, titled `[FIRING] StoreQueryFailing <database>` without a host (S3 review F12 omits only the host), so two databases' instances are told apart on a phone, with the database named in its body too.
  `reporting` and `state.hosts` come from `fleet`'s `system_memory_usage_bytes`, so a `fleet` failure still freezes every `fleet` instance and leaves `state.hosts` unchanged, while a `devloop` failure, such as a missing `ci_build`, leaves every host alert evaluating and posts its own `StoreQueryFailing`.
  The reference model `model.py` and the Hypothesis property test change with it, and the change lands regulator first: the two-database generator and its property are shown failing against the all-freeze `transition.jq` before `transition.jq` changes (S3 retrospective §6), with the mutant `allDatabasesFreeze` rejected after.
- **Boundary**: first-party; the fixture server is the only reader of the SQL path before deploy.
- **Alternatives considered**: a GreptimeDB Flow materialising a metric-shaped table, rejected as a new store feature; a `sqlquery` metrics gauge, rejected at alpha stability with a second path (BS D2).

### D3: One `devloop` allow-list and where it lives

- **Choice**: `flake.lib.otelCollectorSchema.devloop.tables` in SC, an attrset from table name to `{ columns, primaryKey, timeIndex }`, each column `{ name; type; nullable; }` with `type` one of `int64`, `string`, `boolean` and `timestamp`, in the order of A4:101-106 (CH:369):

| Table | Columns | Primary key | Time index |
|---|---|---|---|
| `ci_attribute` | `build_id`, `attr`, `system`, `status`, `cached`, `abandoned`, `drv_path`, `outputs_out`, `started_at`, `finished_at`, `eval_wall_ms`, `eval_alloc_bytes`, `commit_sha`, `branch`, `pr_number`, `project` | `build_id`, `attr` | `finished_at` |
| `ci_build` | `build_id`, `created_at`, `started_at`, `finished_at`, `eval_duration_ms`, `status`, `pr_number`, `branch` | `build_id` | `finished_at` |
| `batch_event` | `batch`, `msg`, `build`, `sha`, `failed_check`, `members`, `landed`, `ejected`, `builds`, `flaky`, `ts` | `batch`, `msg` | `ts` |
| `deploy_record` | `host`, `closure`, `previous_closure`, `ts` | `host` | `ts` |

  From it are rendered: the `CREATE TABLE` statements and the GreptimeDB pipelines (D5), the gitea-mq keep-list (D7) and the deploy-record parser's keep-list; the nixbot queries' output aliases and order come from it too, while the SQL expression behind each alias is written per column in `devloop-collection.nix` (D6).
- **Rationale**: `outputs.out` is stored as `outputs_out`, because a dot in a column name would need quoting in every reader's SQL; every identifier is quoted in the rendered DDL and queries, because `status` is a reserved word in GreptimeDB's parser (SP DDL) and quoting all removes the class.
  The two independently defined values that `devloop-queries` compares are the column names PostgreSQL returns when it executes the rendered query against the migrated schema, and the allow-list; the pipelines' `vrl` step builds the event from the allow-list alone, so an extra field is never emitted, which SP showed the pre-created schema would not prevent.
- **Boundary**: first-party data rendered into vendored formats; the store, not the allow-list, decides the stored types, so `devloop-ingest` compares `DESC TABLE` with the allow-list on the real store.
- **Alternatives considered**: the allow-list in `devloop-collection.nix`, rejected because the store module and S4's agents also read it; a separate list per renderer, rejected as the drift D3 forbids.

### D4: The logs ingress shape and the queue split

- **Choice**: the ingress role gains a second instance of the routing connector, `routing/logs`, whose table has one route per `devloop` table on `attributes["vanixiets.database"] == "devloop" and attributes["vanixiets.table"] == "<table>"`, each to `logs/devloop-<table>-out`; `logs/ingress` runs `forward → memory_limiter → routing/logs`; each `-out` pipeline runs `resource/strip-database`, which now also deletes `vanixiets.table`, into `otlp_http/devloop_<table>` with the headers of the data flow above, `basicauth/store`, infinite retry and a `file_storage` queue.
  `devloop`'s 48 MiB is split as 4 MiB for `otlp_http/devloop` (metrics), 32 MiB for `ci_attribute` and 4 MiB each for `ci_build`, `batch_event` and `deploy_record`, so the queues still sum to 496 MiB.
  The source pipelines live in the `agent` role through `devloop-collection.nix` and end in the existing `forward` connector, so on a host without the ingress role they would end in the agent's OTLP exporter instead (S4).
  The local OTLP receiver feeds no logs pipeline (ADR-003:81).
- **Rationale**: one routing instance cannot carry both signals here, because its logs router resolves every route's pipelines as logs pipelines and fails with "pipeline not found" on `metrics/<db>`, and a second item with the same condition is ignored (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:connector/routingconnector/router.go:161-190`, `:205-260`), so a sibling instance in the same role is D4's ingress route.
  One exporter carries one table header and one pipeline header (GR §4.1), hence one per table.
  The busiest day sends about 64,800 attribute rows including re-reads (GR §1.4), about 32 MiB at roughly 0.5 KiB a row `[INFERENCE]`, so 32 MiB holds about a day of store outage for the largest table, and the other three tables send under 1 MiB a day.
  A full queue loses rows only from the store's copy; nixbot keeps 90 days and the journal and deploy file persist, so `devloop-reconcile` reports the gap and a cursor reset replays it (Risks).
- **Regulation**: the R3.1 collector check's queue clause reads the split and its sum, with a mutant that gives a logs exporter no persistent queue; a new R3.1 clause fails when any `logs/*` pipeline takes the OTLP receiver, with a mutant that adds it; the existing ordering clause keeps the collector after `greptimedb-schema`.
- **Alternatives considered**: a devloop-only path to the exporters, rejected by BS D4; one logs exporter with GreptimeDB's pipeline dispatcher choosing the table, rejected because SP did not exercise it; no persistent queue on the logs exporters, rejected because recovery would then need a manual cursor reset after every store restart.

### D5: Tables, pipelines and the unit that creates them

- **Choice**: GN gains `services.greptimedb.tables`, a list of statements per database, and `services.greptimedb.pipelines`, an attrset from `<database>.<name>` to pipeline YAML; `greptimedb-schema` applies them after the databases, issuing each `CREATE TABLE IF NOT EXISTS` and posting each pipeline to `/v1/pipelines/<name>?db=<database>` as `admin`, failing on any non-200.
  `devloop-collection.nix` sets both from D3, each table rendered as SP's DDL: `ENGINE=mito WITH ('append_mode' = 'false', 'sst_format' = 'flat')`, the primary key as `PRIMARY KEY`, the time index `TIMESTAMP(6) NOT NULL` under `TIME INDEX`, every other column nullable, and no `ttl`, so each table inherits `devloop`'s 365 days and `tableTtls` stays empty.
  Each pipeline is SP's shape: a `vrl` step that resets the event with `. = {}` and then assigns each allow-listed field on its own line, coercing each from its string attribute and mapping `""` to null, because VRL rejects an `if` as a value inside an object literal (the plan's rehearsal with VRL 0.36; that GreptimeDB 1.2.1's bundled VRL 0.33.1 compiles the same form is `[INFERENCE]`, confirmed by `devloop-ingest`'s first-start case), a `date` step over the timestamp fields with the formats `%Y-%m-%dT%H:%M:%S%.fZ` and `%Y-%m-%dT%H:%M:%SZ`, and a `transform` declaring the primary-key columns as tags and the time index; `batch_event`'s `ts` is taken from the record's `Timestamp`, the journal's `__REALTIME_TIMESTAMP`.
  Every exporter sends `x-greptime-hints: auto_create_table=false`.
- **Rationale**: SP showed deduplication holds under both formats the envelope accepts on the OTLP-with-pipeline path, and that a pipeline-created table is append-mode whatever the hints, so the operator's fallback of per-table pipelines alone would not deduplicate; the decision is pre-created tables with no fallback.
  `'sst_format' = 'flat'` is explicit, so the tables do not depend on the engine default, which the envelope's R6.3 and the store spec's flat-format requirement both read.
  With `auto_create_table=false` a write that races the schema job is rejected instead of creating an append-mode table that would keep every duplicate for 365 days.
  `CREATE TABLE IF NOT EXISTS` leaves an existing table unchanged; a column a later allow-list adds is added by the pipeline's first write of it (SP Verdict), and a changed type needs an explicit migration in that slice.
  Each pipeline upload creates a new version on every schema run, which costs one row in `greptime_private.pipelines` per run `[INFERENCE]`.
- **Boundary**: source versus delivered; the tables exist only once `greptimedb-schema` has run on the host, so their delivered form is observed in `devloop-ingest` and at deploy, not at evaluation.
- **Regulation**: the collector stays ordered after `greptimedb-schema` (FM:448-451), a oneshot that exits only after its last statement, which R3.1's ordering clause and its mutant already hold; S1-R6's writer rule is met at runtime by the `devloop-ingest` first-start case, which requires each `otlp_http/devloop_<table>` exporter's `otelcol_exporter_send_failed_log_records` to be zero after first start and fails on the mutant whose schema job omits `ci_build`, where the exporter's first write is rejected with 400.
- **Alternatives considered**: a pipeline per table creating its table, rejected by SP; tables created by the collector's `ExecStartPre`, rejected because only `admin` may create and the collector holds `collector` (`wo`).

### D6: The nixbot queries, cursor, overlap and poll

- **Choice**: two receivers, `sqlquery/ci_attribute` and `sqlquery/ci_build`, driver `postgres`, datasource `host=/run/postgresql dbname=nixbot user=opentelemetry-collector sslmode=disable`, `collection_interval: 60s`, `storage: file_storage`, `tracking_column: finished_at`, `tracking_start_value: "1970-01-01T00:00:00.000000Z"`, and `body_column: body` over a constant empty `body`; every selected value is text, `coalesce(<expr>::text, '')`, and every timestamp is `to_char(<col> AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`.
  The attribute query is:

```sql
SELECT '' AS body,
       b.id::text AS build_id, a.attr AS attr, coalesce(a.system, '') AS system, a.status AS status,
       a.cached::text AS cached,
       (a.status = 'ignored_failure' AND a.error IS NOT DISTINCT FROM $marker)::text AS abandoned,
       coalesce(a.drv_path, '') AS drv_path, coalesce(a.outputs ->> 'out', '') AS outputs_out,
       coalesce(<ts a.started_at>, '') AS started_at, <ts a.finished_at> AS finished_at,
       coalesce(a.eval_wall_ms::text, '') AS eval_wall_ms, coalesce(a.eval_alloc_bytes::text, '') AS eval_alloc_bytes,
       b.commit_sha AS commit_sha, b.branch AS branch, coalesce(b.pr_number::text, '') AS pr_number,
       p.owner || '/' || p.name AS project
FROM build_attributes a JOIN builds b ON b.id = a.build_id JOIN projects p ON p.id = b.project_id
WHERE a.finished_at >= least($1::timestamptz, now() - interval '5 minutes')
ORDER BY a.finished_at
LIMIT 10000
```

  The build query selects `build_id`, `created_at`, `started_at`, `finished_at`, `eval_duration_ms`, `status`, `pr_number` and `branch` from `builds` under the same predicate, order and limit; `$marker` is `abandonMarker`, rendered as a literal.
- **Rationale**:
  - The receiver stores the last row's tracking value and binds it to `$1` on the next run (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/sqlqueryreceiver/README.md:166-173`); rendering timestamps and values as text in the query fixes the cursor's format and the pipeline's input, so neither depends on how the driver stringifies `timestamptz`, `bigint`, `boolean` or `NULL`, which SP left unobserved.
  - The lower bound `least($1, now() - 5 min)` re-reads every row that finished in the last five minutes of wall time and every row tied with the cursor, so a row whose transaction commits up to about four minutes after its `finished_at` is still read on the next poll (A5:129), and `>=` keeps tied rows, of which nine values exist (GR §1.6).
    An overlap anchored on the cursor alone, `$1 - 5 min`, would re-read the cursor's last five minutes of rows on every poll for as long as CI is idle, for example 1,440 times overnight, which could exceed A4:131's 100,000 rows a day after one burst; under `least` an idle poll re-reads only the rows tied with the cursor.
    Each row is sent about five times while it is younger than five minutes, so the busiest day sends about 64,800 attribute rows (GR §1.4), and the store keeps each once (SP).
  - `LIMIT 10000` bounds the first run, which backfills nixbot's whole retained history, about 200,000 attribute rows (GR §1.4), in about 20 polls; it exceeds A4:131's daily row budget once, on the deploy day (Risks).
    A tie wider than the limit would stall the cursor; the widest tie is measured at deploy with one `GROUP BY finished_at` query.
  - `abandoned` is equality on the marker and the status, never a pattern match, because `ignored_failure` covers 1,120 rows of which 117 carry the marker (GR §1.5; A5:75).
  - `error` is referenced but never selected, so no CI error text leaves PostgreSQL; the column grant must still include `error`, because PostgreSQL requires column privilege for a column referenced anywhere in a query (D10).
  - `project` joins `projects` as A5:57 states, as `owner/name`.
  - No index is added (BS D15); the planner already answers the window with `build_attributes_build_finished_idx` (GR §1.6), and `EXPLAIN ANALYZE` at deploy is the measurement.
- **Boundary**: vendored versus first-party; the schema is nixbot's at `d020013fa`, and the queries are ours, bound to it by `devloop-queries` (D14).
- **Alternatives considered**: the cursor-anchored overlap of A5:129, rejected for the idle re-read above; no limit, rejected because the first poll would hold about 200,000 rows in a collector capped at 512 MiB; the receiver's default stringification, rejected as unobserved.

### D7: The gitea-mq journal receiver

- **Choice**: `journald/gitea-mq` with `units: [gitea-mq.service]`, `grep: 'msg="batch (formed|built|landed|bisecting|done)"'`, `start_at: beginning`, `storage: file_storage` and `journalctl_path` a wrapper that runs the system `journalctl` with `--boot=all`; operators `key_value_parser` from `body.MESSAGE` into attributes, then a `retain` of the keep-list `batch`, `msg`, `build`, `sha`, `failed_check`, `members`, `landed`, `ejected`, `builds` and `flaky`, then removal of the body; the record keeps its journal timestamp as `ts`.
- **Rationale**: the receiver must filter on the unit, because the identifier is the wrapper `gitea-mq-start` (GR §2.1); the closing quote in the pattern makes each match exact, so the five further `batch …` messages at the pin cannot match (CH:363 lists them) (A4:59; CH:363); `time`, `level`, `branch`, `current`, `pending`, `left`, `right` and `prs` are dropped, because no D5 rule reads them (A4:105; GR §2.2).
  `start_at: beginning` with a stored cursor copies the retained journal from 2026-09-16 once, 173 batches (GR §2.2), and then follows it.
  The receiver always runs `journalctl --follow` and has no boot option (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:pkg/stanza/operator/input/journald/config_linux.go`, `buildArgs`), and magnetite's systemd 261 `journalctl` reads only the current boot under `--follow` unless a `--boot` is given, also after `--after-cursor`; the wrapper's `--boot=all` reads every retained boot (on 2026-10-22 the receiver's argv selected 282 of 772 lines without it and 772 with it).
  The journal's `__REALTIME_TIMESTAMP` is the time index, because it is the time `devloop-reconcile` filters the journal by, and repeated `batch built`, `batch landed` and `batch bisecting` lines of one bisected batch stay distinct rows because their timestamps differ (GR §2.3).
- **Boundary**: vendored message text; only `devloop-reconcile`'s liveness clause guards an upstream rename (A5:127).
- **Alternatives considered**: a prefix match, rejected by BS D10; slog's `time=` as time index, rejected because the reconcile reads journal time and the two agree to the millisecond in the sample (GR §2.1) without a guarantee that they always will.

### D8: The questions `devloop` answers, and flaky and abandoned attributes

- **Choice**: three documented queries, each run for the past week at acceptance and in the `devloop-ingest` query case against fixture rows:
  - Formation-to-land is `done.ts - formed.ts` per batch, joining `batch_event` rows on `batch` with `msg = 'batch formed'` and `msg = 'batch done'`; `batch done` occurs once per batch and is the endpoint, while a bisected batch's repeated `batch landed` rows stay stored and are not the endpoint (GR §2.3).
  - CI queue wait is `started_at - created_at` over `ci_build` rows with `pr_number` set and `started_at` set, each build's first attempt only as in D1, reported as the 50th, 90th and 99th percentiles.
  - Per-build CI outcome is computed over `ci_attribute` rows in the window: pass rows are `succeeded` and `skipped_local`; own-fail rows are `failed`, `failed_eval` and `ignored_failure` with `abandoned = false`; `dependency_failed` is a fail row of the build but not the derivation's own outcome; `cancelled`, `building`, `pending` and abandoned rows are no outcome.
    A `drv_path` is flaky in the window when it has both a pass row and an own-fail row there, and a build fails when any of its rows that is neither abandoned nor of a flaky `drv_path` is an own-fail or `dependency_failed` row, and passes otherwise.
    A build with no outcome row, only `cancelled`, `pending`, `building` or abandoned rows, has no result and is left out of the answer by a `HAVING` clause, rather than counted as passed (plan review F21).
- **Rationale**: `dependency_failed` does not count toward flakiness, because a flaky dependency would otherwise mark every dependent flaky.
  The store cannot attribute a `dependency_failed` row to the derivation that failed under it: nixbot names that derivation only in `error` text, which S2 never stores, and no dependency edge is collected, so a build whose only failures are `dependency_failed` rows below a flaky derivation still counts as failed; this limitation is recorded with the query.
  Flakiness and abandonment are computed at query time with no stored column (BS D8), so a change to their definition reinterprets history.
- **Alternatives considered**: `count(distinct status) > 1` as GR §1.6 measured, rejected because it counts a cached pass against a built pass; the first `batch landed` as the endpoint, rejected by the operator.

### D9: The deploy record

- **Choice**: one shell script, rendered once with the host's `networking.hostName` as a literal, appends to `/var/log/deploy-record.jsonl`, created with mode `0644`, one line `{"host":…,"closure":…,"previous_closure":…,"ts":…}` with `closure` the activated `$systemConfig`, `previous_closure` the target of `/run/current-system` when it exists and absent otherwise, and `ts` from `date -u +%Y-%m-%dT%H:%M:%SZ`; NixOS runs it as `system.activationScripts.deploy-record` without `supportsDryActivation`, and darwin appends it to `system.activationScripts.postActivation`.
  On magnetite `file_log/deploy-record` reads the file with `start_at: beginning`, `storage: file_storage` and `json_parser`, keeping `host`, `closure`, `previous_closure` and `ts`.
- **Rationale**: both activation scripts run before `/run/current-system` is relinked (A5:39), so the previous closure is readable; store paths need no JSON escaping, so `printf` writes the line without `jq` on every machine; whole seconds suffice because two activations of one host never fall in one second, and darwin's `date` has no sub-second format.
  The host name is taken at evaluation, so a renamed hostname at runtime cannot misattribute a record.
  `start_at: beginning` ships a host's whole file the first time its collector reads it, which is how S4 and S5 pick up history (BS D12).
  Commit attribution is the join of D8's style: `closure` equals `outputs_out` of a pass row whose `attr` is `checks.<system>.nixos-<host>` or `checks.<system>.darwin-<host>` (A5:71).
- **Boundary**: source versus delivered; the obligation checks the evaluated activation, and only `devloop-ingest` and the deploy observe the delivered line.
- **Alternatives considered**: recording commit and outcome, rejected by BS D9; `jq` in activation, rejected as a runtime dependency on every machine for one line.

### D10: PostgreSQL roles and column grants

- **Choice**: `services.postgresql.ensureUsers` creates the login roles `opentelemetry-collector` and `devloop-reconcile`, admitted by the default local peer rule because each is named after its unit's `DynamicUser` (GR §1.1); `devloop-pg-grants.service`, a oneshot as `postgres` with `RemainAfterExit`, ordered after `postgresql.service`, `postgresql-setup.service` (where `ensureUsers` creates the roles) and `nixbot.service` and wanted by `multi-user.target`, once per boot or activation waits up to 300 s for every granted column to exist in `information_schema.columns`, then grants:

| Role | `builds` | `build_attributes` | `projects` |
|---|---|---|---|
| `opentelemetry-collector` | `id`, `project_id`, `commit_sha`, `branch`, `pr_number`, `status`, `created_at`, `started_at`, `finished_at`, `eval_duration_ms` | `build_id`, `attr`, `system`, `status`, `cached`, `error`, `drv_path`, `outputs`, `started_at`, `finished_at`, `eval_wall_ms`, `eval_alloc_bytes` | `id`, `owner`, `name` |
| `devloop-reconcile` | `id`, `branch`, `finished_at` | `build_id`, `attr`, `finished_at` | none |

- **Rationale**: column grants keep every other column, including `builds.error` and `eval_warnings`, out of both roles' reach; `build_attributes.error` must be granted to the collector because the `abandoned` comparison references it, so the SELECT list, regulated by `devloop-queries`, is what keeps error text out of the store.
  A view or function computing `abandoned` would remove that grant, but an object in nixbot's database that depends on its columns makes PostgreSQL refuse a later nixbot migration that drops or alters them, which would stop nixbot at startup; BS D15 keeps nixbot's database unchanged for the same reason.
  nixbot's unit is not a notify unit, so `After=nixbot.service` does not wait for its migrations, hence the wait for the columns.
  The grants are not re-applied when nixbot restarts: the wait would see the old columns before nixbot's migrator runs (`Mic92/nixbot@d020013fa:nixbot/nixbot/migrations.py:94-165`), so a migration that drops and re-adds a granted column, as `0014_streamed_eval_warnings.sql:3-4` did, loses the grant either way (plan review F6).
  Such a loss is detected rather than repaired: the reader's query fails with a permission error in the collector's journal, its rows stop arriving, and `devloop-reconcile`'s C1 or C2 fails the next morning, or the run exits 2 when its own grant is gone; the next activation or boot grants again.
  A grant oneshot that times out fails visibly through the notifier, which is also an early sign of schema drift.
- **Boundary**: vendored versus first-party; the roles and grants are ours, the tables nixbot's.
- **Alternatives considered**: one shared role for both readers, rejected because the reconcile needs only counts and keys; granting whole tables, rejected because `error` columns would then be readable by the reconcile too.

### D11: `devloop-reconcile`

- **Choice**:
  - `devloop-reconcile.service`, a oneshot from `flake.lib.devloopReconcile`, `DynamicUser`, `SupplementaryGroups = [ "systemd-journal" ]`, `LoadCredential=regulator-password`, `MemoryMax = "128M"`, `TimeoutStartSec = "10min"`, `OOMScoreAdjust = 600`, `after = [ "postgresql.service" "greptimedb.service" "greptimedb-schema.service" "devloop-pg-grants.service" ]` with no `wants`, and `OnFailure=observability-notify@%n.service` through `services.observability-notify.units`.
  - `devloop-reconcile.timer`, `OnCalendar = "*-*-* 02:15:00 UTC"`, `Persistent = true`.
  - The window is the previous UTC day, `[D-1 00:00, D 00:00)`, which closes 2 h 15 min before the run and so satisfies E5.1's window ending at least an hour ago (A5:148).
  - Each store query first counts, which always returns one row, and reads keys only when a count is non-zero, so `greptimedbSql`'s empty-result failure still applies to every key query it issues (S1 review F3).
  - The window's day and the store database come from `DEVLOOP_RECONCILE_DAY` (default yesterday) and `DEVLOOP_RECONCILE_DATABASE` (default `devloop`), so a runtime drop-in can force a failure, as `greptimedb-envelope`'s thresholds do (S1 tasks.md 8.6); the comparisons' own fallibility is shown by `devloop-ingest`, not at deploy (A5:153).
- **Comparisons**, each failing the run and naming its clause, with the `devloop-ingest` case that makes it fail:

| Clause | nixbot or host side | Store side | Fails when | Case |
|---|---|---|---|---|
| C1 attributes | `(build_id, attr, finished_at)` in the window | `ci_attribute` keys in the window | a nixbot triple is missing, or a stored triple is not in nixbot and nixbot's current `finished_at` for that `(build_id, attr)` is neither null nor later | the collector mutant whose query omits `cached = true` rows; the append-mode table mutant, whose overlap re-reads leave duplicates |
| C2 builds | `(id, finished_at)` in the window | `ci_build` keys in the window | as C1 for builds | the mutant build query that drops `pr_number IS NULL` rows |
| C3 batch lines | journal lines of `gitea-mq.service` matching D7's pattern, counted per `msg`, filtered on `__REALTIME_TIMESTAMP` | `batch_event` rows per `msg` in the window | any count differs | the collector mutant without `key_value_parser` |
| C4 batch liveness | builds on a `gitea-mq/batch/` branch finished in the window | `batch built` rows in the window | nixbot has one and the store has none | the stub `gitea-mq` that prints nothing while fixture batch builds exist |
| C5 batch fields | — | `batch done` rows with a null `landed`, `ejected`, `builds` or `flaky` | any exists | the pipeline mutant that drops `flaky` |
| C6 deploys | lines of `/var/log/deploy-record.jsonl` with `ts` in the window | `deploy_record` rows for the host in the window | counts differ | the `file_log` mutant reading another path |
| C7 current system | `readlink -f /run/current-system` | the latest `deploy_record` row for the host | they differ | the snippet mutant writing the previous closure as `closure` |

- **Rationale**: a restarted attribute keeps its `(build_id, attr)` and gets a new `finished_at`, so the store legitimately keeps the earlier row while nixbot no longer has it; C1 explains such extra rows instead of failing on them, and fails on any other extra row, which is how an overlap re-read that adds a row shows itself (CAM-69 acceptance).
  Comparing per-key sets subsumes CAM-69's per-build row counts.
  C4's window is one day, because `batch bisecting` occurred in none of the last 7 days (GR §2.2, G3), so no clause requires it.
  A day's queries touch at most about 13,000 attribute keys (GR §1.4), so 128M and ten minutes leave a wide margin `[INFERENCE]`, which the first deploy's logged memory peak checks.
  An `OOMScoreAdjust` of 600 puts the reconcile after nixbot's evaluator (900) and before the store (500), the collector (300) and the evaluator of alerts (0), because a killed reconcile fails visibly and runs again tomorrow, while the store's death loses ingest.
- **Credential**: `devloop-reconcile` becomes the third `regulator-password` holder under MG's R8.2 assertion; the collector's reader holds no store credential (BS D6).
- **Regulation**: MG's kill-order assertion gains `devloop-reconcile` between the nixbot evaluator and the store, with an `extendModules` mutant that sets it to 0, as S3 D12 asks of any slice adding a memory-bounded unit; R3.1's failure-wiring clause extends its pattern to `devloop-*` with a mutant that drops the unit from `services.observability-notify.units`.
  The collector's journal read is already in force (GR §4.2), so `devloop-collection.nix` asserts that the collector's `SupplementaryGroups` contains `systemd-journal`, with an `extendModules` mutant that clears it; this is the whole of D11's collector clause.
- **Alternatives considered**: a rolling 24 h window ending one hour before each run, rejected because consecutive runs would not tile the timeline; failing on any extra stored row, rejected because restarts would fail it.

### D12: Deploy-record presence as a machine obligation

- **Choice**: `deploy-record.nix` sets the read-only option `vanixiets.deployRecord.script`; MC's `withFleetObligations` gains a second obligation set, `self.lib.deployRecordObligations`, whose `failures name config` is non-empty unless the activation script the platform assembles contains that script, read from `system.activationScripts.script` on NixOS and `system.activationScripts.script.text` on darwin, so the obligation fails however the entry is dropped, by removal, an empty override or a replaced script.
- **Rationale**: CI already evaluates each x86_64-linux NixOS machine's toplevel, so the obligation costs nothing beyond a string search, while a check over all ten configurations would force ten module fixpoints, magnetite's alone about 2.61 GiB (CH:319), against a 0.5 GiB budget (BS D12).
  The two values compared are the script the module renders and the activation text the platform assembles, which the platform's own activation module builds.
  CI holds the obligation on five of the ten machines, the x86_64-linux NixOS machine checks of cinnabar, electrum, galena, magnetite and pyrite: nixbot gates merges only on `checks.x86_64-linux`, while the four darwin machine checks under `checks.aarch64-darwin` are best-effort, so a failure there is recorded as an ignored failure and blocks nothing (`nixbot.toml`; `modules/checks/nixbot-best-effort-darwin.nix`), and `scheelite`'s check is deferred (MC:6); their activation is shown carrying the snippet once by evaluation when the snippet lands, and no darwin gate is added, because evaluating four darwin configurations per pull request costs more than the dropped snippet it would catch (plan review F9).
- **Regulation**: a negative control evaluates the obligation over a configuration built with `extendModules` that drops the module's activation entry and requires a non-empty failure list.

### D13: Pins and the abandonment marker

- **Choice**: `flake.lib.devloopCollection.abandonMarker = "not finished when the required attributes had settled"`, the one value the attribute query and `devloop-queries`' marker clause read.
- **Rationale**: the marker is a Python string literal in the patch (`modules/nixos/nixbot-abandon-optional-attributes.patch:146`, `:379`, `:451`), so the check matches it with its quotes, `"<marker>"`, which a prefix or suffix of the message would not satisfy; it occurs once in production code, the added line between `return AttributeStatus.ignored_failure, (` and `if outcome == BuildOutcome.abandoned` (`:145-147`), and twice in the patch's tests, so the check matches the production context (plan review F11).

### D14: `devloop-queries` reproduces nixbot's schema

- **Choice**: `checks.x86_64-linux.devloop-queries` is a derivation using `postgresqlTestHook` with `pkgs."postgresql_${postgresqlMajor}"`, where `flake.lib.devloopCollection.postgresqlMajor = "16"` is the major version magnetite runs (16.15, `nix eval --raw .#nixosConfigurations.magnetite.config.services.postgresql.package.version`, 2026-10-21), and `flake.modules.nixos.devloop-collection` asserts that the host's `services.postgresql.package` has that major version, shown failing by an `extendModules` override that sets another major; the two values are the host's package version and the lib constant, so the check evaluates no NixOS configuration; it applies `${inputs.nixbot}/nixbot/nixbot/migrations/*.sql` in lexical order, each with `psql -v ON_ERROR_STOP=1 --single-transaction`, creates both roles, applies the grant SQL of D10, loads fixture projects, builds and attributes, and runs both export queries as `opentelemetry-collector` and the reconcile's PostgreSQL queries as `devloop-reconcile`, with `$1` bound through `PREPARE … EXECUTE`.
  It asserts the result column names and order equal D3's allow-list per table; `abandoned` is true only for the marker row and false for a non-marker `ignored_failure` and a null-`error` one; `outputs_out` is empty for a null `outputs`; a row 4 min old with an old cursor is returned and a row 6 min older than a recent cursor is not; and tied rows at the cursor are returned.
  Mutants, each of which must fail the check: a fixture migration renaming `cached`; a query mutant adding `a.error` to the SELECT list; a grant mutant without `build_attributes.error`.
- **Rationale**: lexical order equals the migrator's numeric order, because every file name has a four-digit version, and the migrator runs each file in its own transaction (GR §1.3), which `--single-transaction` per file mirrors; the plan's first task compares the check's `pg_dump --schema-only` of the three tables with magnetite's live one, read-only, and falls back to nixbot's migrator from the input only if they differ (BS D14).
- **Evaluation cost**: the check reads `flake.lib` values and the nixbot input's path and builds no NixOS configuration; `checks.x86_64-linux.package-ntfy-send-test-token-transport`, a check of that class, evaluates at 127,019,504 B (0.118 GiB, measured 2026-10-21 with the method above), so `devloop-queries` is estimated at 0.12 to 0.2 GiB `[INFERENCE]`, measured when the task lands.

### D15: The marker clause lives in `devloop-queries`

- **Choice**: `checks.x86_64-linux.devloop-queries` asserts that the patch text contains the three added lines `return AttributeStatus.ignored_failure, (`, `"` + `abandonMarker` + `"` and `if outcome == BuildOutcome.abandoned` in sequence, and carries two embedded negative controls that evaluate the same assertion with the marker's last character changed, and over the patch's test lines alone, and require each false, following `modules/checks/omnigent-environment.nix`; no `devloop-signals` check is created in S2.
- **Rationale**: `devloop-queries` already reads the marker for the attribute query, so the clause adds a file read and a string search to an evaluation already paid for, instead of a second per-system package-set evaluation (plan review F11); the two values compared are `abandonMarker` and the patch text.
- **Later slices**: S7 creates `checks.x86_64-linux.devloop-signals` for the omp clause, measured when it lands.

### D16: `devloop-ingest`

- **Choice**: `vmTests.x86_64-linux.devloop-ingest`, an nspawn container test on magnetite following `greptimedb-pipeline`, running PostgreSQL with nixbot's migrations, GreptimeDB with the schema job, the collector with both roles and `devloop-collection`, a stub `gitea-mq.service` printing fixture slog lines to stdout, and the reconcile with its fixture window.
  Cases:
  - First start: each `otlp_http/devloop_<table>` exporter's `send_failed` log-record count is zero, every table's `DESC TABLE` equals the allow-list, and no table has a `body` column (S1-R6).
  - Writer ordering: the schema job without `ci_build` makes that exporter's `send_failed` non-zero.
  - Overlap: fixture rows re-read on three polls leave one row per key, and the reconcile passes.
  - Reconcile mutants: each row of D11's table.
  - Configuration switch: a node switching to a second system, its own configuration extended by `extendModules` because nixpkgs' nspawn container module forbids `specialisation`, appends exactly one line naming both closures (A5:152); the container's systems carry no `switch-to-configuration`, so the case appends by running the second system's activation script, which sets `$systemConfig`, and the gap is recorded (BS D13).
  - Burn rule: D1's three fixtures on the real store.
  - Queries: each D8 query returns its fixture answer.
- **Rationale**: the gitea-mq parser and the reconcile's fallibility have no gating regulator, so this test runs on magnetite before the merge of any change to either (A5:166).

### D17: The evaluator's check

- **Choice**: the fixture server answers `/v1/sql` beside `/v1/prometheus/api/v1/query`, records each request's path and database (`x-greptime-db-name` for PromQL, `db` for SQL), answers 400 to a request whose database is not the one the leg's rule declares, and replays SQL bodies in GreptimeDB's `output[0].records` shape; a new leg runs one PromQL rule against `fleet` and the burn rule against `devloop` and asserts both databases were queried on their paths; the timeline leg replays the burn rule's spec scenario, a row for 61 passes then none for 5 minutes, and expects one `[FIRING] PullRequestQueueWaitBurn` after the hour, no re-post, and one `[RESOLVED]`; a mutant evaluator that sends every query to `fleet` must fail the two-database leg.
  D2's per-database freeze changes `transition.jq`, `model.py` and `test_transition.py`: the property test gains a generator with rules on `fleet` and `devloop` and per-run `storeErrors`, and a property that a `devloop` failure leaves the posts of `fleet` instances unchanged, shown failing against the all-freeze `transition.jq` first; the fixture part gains `devloopFailureLeg`, in which `HostOOMKill` fires and resolves on `fleet` while the burn rule's SQL fails and `StoreQueryFailing` names `devloop`; and the mutant `allDatabasesFreeze` must fail both.
- **Evaluation cost**: `checks.fleet-alert` evaluates at 328,149,136 B (0.306 GiB, measured 2026-10-21); the new legs add fixture files and one more rendered configuration, estimated under 0.02 GiB more `[INFERENCE]`.

### Spec deltas beyond the proposal's list

The specs touch these requirements beyond the proposal's list, each a consequence of a decision above:

- `telemetry-store-interface` `The collector's queue persists across a telemetry store restart` states D4's split of `devloop`'s 48 MiB.
- `fleet-alerting-interface` `The evaluator queries the fleet database as the regulators' store account` is renamed to `The evaluator queries each rule's database as the regulators' store account` (D2), so `fleet-alerting`'s `Each known failure class on a host reaches a person as an alert` is modified only to cite the new name.
- `fleet-alerting-interface` `Alerts are posted to fleet-alerts with a title and a severity priority` adds `PullRequestQueueWaitBurn` to the host-less titles (D1), and its trust-boundary requirement says each rule's database instead of `fleet`.
- `fleet-alerting-interface` gains `The pull-request queue-wait rule reads devloop through SQL` for D1's rule.
- `fleet-alerting-interface` `Store errors and silent hosts freeze instance state` and `fleet-alerting` `An unreachable telemetry store or a silent host freezes alerts` are modified for D2's per-database freeze, and the query requirement's sentence on a failed SQL query says it ends only its database's queries.

The `world-assumptions` delta adds A43 to A49, the next free numbers after A42, and copies main's designation table whole, adding the rows of S3 `verify.md` §8a and the dev-loop terms; S1 `verify.md` §8a's rows are already in main.

### Later slices

| Slice | Touches | Rule it must keep |
|---|---|---|
| S4 | ships deploy records from every agent host to the ingress (CH:310) | the agent stamps `vanixiets.database = devloop` and `vanixiets.table = deploy_record`; the ingress's `routing/logs` route is unchanged; `devloop-reconcile` still samples magnetite alone unless S4 extends C6 and C7 |
| S4 | adds notified units on other hosts | `SystemdUnitFailed`'s exclusion becomes the union (S3 D10) |
| S6 | dashboards read `devloop` | they read D3's column names and D8's definitions, as `perses` (`ro`) |
| S7 | `fleet` journald logs on the same logs path; the omp emitter | new logs routes are new `routing/logs` items with their own table attribute; content stages precede any content-bearing pipeline; an edit of an export query or its allow-list columns re-backfills its whole source once, about 200,000 rows, because the cursor key embeds the query text (Risks); S7 creates `devloop-signals` for the omp clause, and the marker clause stays in `devloop-queries` |
| S8 | exports `devloop` | the export reads the four tables and keeps `outputs_out` and the quoted identifiers |

## Risks / Trade-offs

- [Risk] Both CI and journal readers advance their position before the rows are delivered, so a `memory_limiter` refusal loses journal lines and CI rows older than the overlap, and the `sqlquery` cursor's storage key embeds the query text, so any later edit of an export query restarts it from `tracking_start_value` and re-backfills about 200,000 rows, over A4:131's budget that day (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/sqlqueryreceiver/logs_receiver.go:123`, `:206`, `:276`, `:337-346`; `pkg/stanza/operator/input/journald/input.go:186-189`; plan review F16). → Mitigation: `journald/gitea-mq` sets `retry_on_failure` with no time limit; C1, C3 and C6 report a loss and a cursor reset replays it; a later slice that edits a query accepts one re-backfill day (Later slices).
- [Risk] `sqlquery`'s logs signal is at Development stability in 0.155.0 (GR §4.2), so a collector bump can change the tracking or body behaviour. → Mitigation: world assumption A47 records the behaviour S2 relies on; `devloop-ingest` exercises it, and `devloop-reconcile` fails within a day if rows stop arriving; a collector bump runs `devloop-ingest` before merge.
- [Risk] A transaction commits more than about four minutes after its `finished_at`, and its row is never read. → Mitigation: C1 fails on the missing triple the next morning, and nixbot keeps the row for 90 days, so a cursor reset replays it.
- [Risk] A `finished_at` tie wider than 10,000 rows stalls the cursor. → Mitigation: the widest tie is measured at deploy; a stall stops all rows and C1 fails within a day.
- [Risk] `journalctl --follow` reads only the current boot on systemd 261, so `journald/gitea-mq` would copy only the lines since magnetite's last boot, and after a reboot skip the lines between its cursor and the boot; found by 7.4 after D3, when `batch_event` held 282 of 772 retained lines. → Mitigation: the receiver's `journalctl_path` wrapper adds `--boot=all`; `devloop-ingest`'s table-shape case asserts the running `journalctl` carries it; one reset of the receiver's cursor after the fix's deploy re-reads the journal, deduplicated by `batch_event`'s key and time; C3 compares each day without `--follow`, so it reads every boot.
- [Risk] A nixbot input bump renames or drops a column S2 reads. → Mitigation: `devloop-queries` fails at merge; `devloop-pg-grants` fails visibly if a granted column disappears at runtime.
- [Risk] gitea-mq renames a batch message. → Mitigation: C4's liveness clause, the only guard (A5:127).
- [Risk] A missing or broken `devloop` table makes the burn rule unevaluable. → Mitigation: the failure freezes only `devloop`'s rule and posts `StoreQueryFailing` naming `devloop`, while every `fleet` rule keeps evaluating (D2), and the table is created before the evaluator starts (FA orders after `greptimedb-schema`).
- [Risk] The `logs/*` queues fill during a store outage longer than about a day on the busiest day, and rows are dropped. → Mitigation: C1 to C6 report the gap; the sources keep the rows, so a cursor reset replays them.
- [Risk] One record a pipeline cannot process fails its whole OTLP request with HTTP 400, which the exporter drops as permanent, and the `sqlquery` receiver has already advanced its cursor, so up to 10,000 rows older than the overlap can be lost (`GreptimeTeam/greptimedb@v1.2.1:src/servers/src/pipeline.rs:106`, `:158`, `:186`; `open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/sqlqueryreceiver/logs_receiver.go:206`, `:337-346`). → Mitigation: C1, C3 and C6 fail the next morning on the missing rows, and a cursor reset replays them from the source; `skip_error` is not set, because it would make per-row loss silent (plan review F4).
- [Risk] The collector role can read `build_attributes.error`, so a query edit could ship error text. → Mitigation: `devloop-queries` compares the result columns with the allow-list and its `a.error` mutant shows the comparison can fail; the pipelines emit allow-listed fields only.
- [Trade-off] The first deploy sends about 200,000 attribute rows, above A4:131's 100,000 a day. → Accepted once: it is nixbot's retained history, which the copy exists to keep.
- [Trade-off] A `dependency_failed` row cannot be attributed to the flaky derivation under it (D8). → Accepted and recorded with the query; storing error text or dependency edges would be needed to do better.
- [Trade-off] The reconcile samples one host of ten for deploy records (A5:159). → Accepted until S4 and S5.
- [Trade-off] Each schema run uploads a new pipeline version. → Accepted: one small row per boot or activation.

## Migration Plan

The change lands as six pull requests, merged in order; the deploys are magnetite's unless stated:

| Pull request | Contains | Deploy |
|---|---|---|
| 1 | `deploy-record.nix` imported on all ten machines, the machine obligation held by CI on the five x86_64-linux NixOS machines | magnetite, then the others at their routine updates |
| 2 | SC's `devloop.tables`; GN's `tables` and `pipelines`; `abandonMarker` and `devloop-queries` with its marker clause; before the pull request is enqueued, the four tables and pipelines compiled and written once on a throwaway store on magnetite | magnetite: the four tables and pipelines exist, empty |
| 3 | `devloop-collection.nix` receivers, roles, grants and assertions; `devloop-pg-grants` in magnetite's notified units; FM's `routing/logs`, exporters and queue split; `devloop-ingest`, run on magnetite before merge | magnetite: backfill and live copy |
| 4 | `devloop-reconcile` and its timer; the holder entry, `devloop-reconcile`'s notified-unit entry and the kill-order entry; R3.1's failure-wiring pattern | magnetite |
| 5 | per-rule `database` and `language`, `/v1/sql`, the burn rule, the fixture server and legs | magnetite |
| 6 | the operator page on querying `devloop`, the component README and the skill lines | none |

1. After PR 1's deploy, `/var/log/deploy-record.jsonl` on magnetite holds one line naming the new and previous closures, and a reboot adds a line without `previous_closure`.
2. After PR 2's deploy, `SHOW TABLES FROM devloop` lists the four tables, `SHOW CREATE TABLE` shows `append_mode = 'false'` and `sst_format = 'flat'`, the next `greptimedb-envelope` run passes, and `SELECT name FROM greptime_private.pipelines` lists the four pipelines.
3. After PR 3's deploy, every exporter's `send_failed` log-record count is zero; `ci_attribute` reaches nixbot's row count within about 20 polls; `EXPLAIN ANALYZE` of each query, run as `opentelemetry-collector` with the live cursor, is recorded (BS D15); the widest `finished_at` tie is recorded; and the operator records the day's sent and stored row counts against A4:131.
4. After PR 4's deploy, a hand start of `devloop-reconcile.service` passes for the previous day; a hand start under a runtime drop-in setting `DEVLOOP_RECONCILE_DATABASE=devloop_absent` fails and posts one `FAILED devloop-reconcile.service on magnetite`, and removing the drop-in and starting it again posts its `RESOLVED`; the timer's first scheduled run passes, and its memory peak is recorded against 128M.
5. After PR 5's deploy, the evaluator's first run queries both databases; the burn rule's query is run by hand for the past week, and the operator records which days it would have fired.
6. CAM-69's acceptance is recorded: the reconcile passes, the past week's formation-to-land, queue wait and per-build outcome queries answer, and one magnetite deploy yields exactly one new record.

Rollback reverses the order: PR 5's revert restores PromQL-only evaluation; PR 4's stops the reconcile; PR 3's revert stops collection and leaves the tables and their rows in place, which the next deploy of PR 3 resumes from the stored cursors; the tables are dropped only by hand, as `admin`.

## Open Questions

None.

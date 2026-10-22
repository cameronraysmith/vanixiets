### Task 3: Collection on magnetite and `devloop-ingest` (deploy D3)

Implements `tasks.md` 3.1–3.11 (design D4, D6, D7, D8, D9, D10, D11, D16; DCI `The nixbot readers authenticate by peer and hold column grants only`, `Column grants are applied once nixbot's columns exist`, `The collector reads nixbot's builds and attributes through two cursor queries`, `gitea-mq's five batch messages are parsed from its journal`, `magnetite's collector ships its own deploy records`, `Dev-loop sources are stamped and routed to their table`, `The collector's journal read is asserted`, `devloop-ingest shows the collection path and the reconcile able to fail`; TSI `Ingest is OTLP over HTTP with a database header`, `The collector's queue persists across a telemetry store restart`; HMC `magnetite contributes its own signals to the telemetry store`; DC `The past week of the dev loop can be asked about`, `Every dev-loop event is recorded once and kept for a year`, `No error text, message body or other free text enters the dev-loop history`; WA A46, A47, A49).
The order is RED before GREEN at every layer.
First each evaluated value this task adds is shown absent from magnetite, and the container test is written whole and shown failing at evaluation because the `questions` and `batchEventKeys` it reads do not exist yet.
Then `devloop-collection.nix` and the ingress role are written and each `tasks.md` 3.1–3.5 value is read back by `nix eval`.
The journal assertion is shown absent by an `extendModules` override before it is written and failing under the same override after.
R3.1 is shown failing on the new logs pipelines with its old content clause, then its four new mutants are added and shown accepted, then the clauses that reject them are added and the check passes with every mutant rejected.
Last, `devloop-ingest` runs on magnetite from the change's commit, with the `noAutoCreate` mutant rejected, before the pull request merges.

**Files:**
- Modify: `modules/nixos/devloop-collection.nix` (whole file; 309 lines as Task 2 leaves it, `flake.lib.devloopCollection` at lines 280-291 and `flake.modules.nixos.devloop-collection` at lines 293-308)
- Modify: `modules/machines/nixos/magnetite/default.nix` (`services.observability-notify.units`, lines 329-343 on `main@origin` before Tasks 1 and 2, whose import lines move it down)
- Modify: `modules/clan/services/otel-collector/flake-module.nix:1-10` (header comment), `:33-42` (`mib` and `queueBytes`), `:332-453` (the whole `flake.modules.nixos.otel-collector-ingress` definition)
- Modify: `modules/checks/otel-collector-config.nix:1-14` (header comment), `:211-212` (`dbs`, `exporterNames`), `:297-300` (the content clause), `:300` (new clause after it), `:434` (four mutants after `queueOver512MiB`)
- Create: `modules/vm-tests/devloop-ingest.nix` (`vmTests.x86_64-linux.devloop-ingest`)
- Create: `modules/vm-tests/devloop-ingest/helpers.py`, `modules/vm-tests/devloop-ingest/nixbot-schema.sh`, `modules/vm-tests/devloop-ingest/gitea-mq-lines.txt`
- Modify: `openspec/changes/stand-up-devloop-collection/tasks.md:35-43` (ticks 3.1–3.9)
- Evidence (git-ignored): `logs/s2-evidence/3.*-*.log`

**Interfaces:**
- Consumes (Task 1): `flake.modules.nixos.deploy-record`, whose activation entry runs `flake.lib.deployRecordScript` with `"$systemConfig"` and appends one line `{"host","closure","previous_closure","ts"}` to `/var/log/deploy-record.jsonl`.
- Consumes (Task 2): `flake.lib.otelCollectorSchema.devloop.tables`; `modules/nixos/devloop-collection.nix` with `flake.lib.devloopCollection.abandonMarker` (Task 2 creates the file, plan review F11); in `devloop-collection.nix` the `let` bindings `tables`, `abandonMarker`, `postgresqlMajor`, `quote`, `sqlLiteral`, `storeType`, `transformType`, `recordTimestamps`, `ddl`, `vrlAssignment`, `dateStep`, `pipelines`, `sources`, `asText`, `queries`, `grants`, `grantSql` and the attrset `flake.lib.devloopCollection = { abandonMarker; postgresqlMajor; ddl; pipelines; queries; grants; grantSql; selects; }`; the module function `flake.modules.nixos.devloop-collection = { config, ... }:` with the PostgreSQL-major assertion (message prefix `devloop-collection: services.postgresql.package is PostgreSQL`); `services.greptimedb.tables` and `services.greptimedb.pipelines` applied by `greptimedb-schema.service`; `grants.devloop-reconcile` is `builds = [ "id" "branch" "finished_at" ]`, `build_attributes = [ "build_id" "attr" "finished_at" ]` and has no `projects` key; the `ci_*` and `deploy_record` pipelines read each column from the string attribute of the same name, `""` or absent as null, and `batch_event`'s `ts` from the record's `Timestamp`; `devloop-queries` applies `${inputs.nixbot}/nixbot/nixbot/migrations/*.sql` lexically with `psql -X -q -v ON_ERROR_STOP=1 --single-transaction`, unless Task 2's schema diff chose nixbot's migrator (plan review F17).
- Consumes (S1): magnetite's `clan.core.vars.generators.greptimedb-users` (its `finalScript` writes `admin-password`, `collector-password`, `perses-password`, `regulator-password` and `users`), the store on `127.0.0.1:4000`, the collector's `forward` connector, `memory_limiter`, `file_storage` and `basicauth/store`, and its order after `greptimedb-schema.service` (`flake-module.nix:446-451`).
- Produces in `flake.lib.devloopCollection`: `questions.formationToLand`, `questions.queueWait`, `questions.buildOutcome` (GreptimeDB SQL over `devloop`, past 7 days, every identifier double-quoted) and `batchEventKeys` (`batch_event`'s columns minus its time index, in allow-list order).
- Produces in `flake.modules.nixos.devloop-collection` (the function becomes `{ config, pkgs, ... }:`, a plain attrset, no `mkIf` or `mkMerge`): a second assertion, after Task 2's, with message prefix `devloop-collection: journald/gitea-mq reads`; `services.postgresql.ensureUsers` entries `{ name = "devloop-reconcile"; }` and `{ name = "opentelemetry-collector"; }`; `systemd.services.devloop-pg-grants`; receivers `sqlquery/ci_attribute`, `sqlquery/ci_build`, `journald/gitea-mq` (operators `parse-message`, `keep-list`, `drop-body`), `file_log/deploy-record` (operators `parse-line`, `keep-list`, `drop-body`); processors `resource/devloop-<table>`; pipelines `logs/devloop-<table>` ending in `forward`.
  Task 4 appends `systemd.services.devloop-reconcile` and `systemd.timers.devloop-reconcile` directly after the `systemd.services.devloop-pg-grants` block.
- Produces in magnetite: `services.observability-notify.units` gains `"devloop-pg-grants"`, first in the sorted list; Task 4 adds `"devloop-reconcile"` after it and extends R3.1's policy to `devloop-`.
- Produces in the ingress role: `connectors."routing/logs"`, pipelines `logs/ingress` and `logs/devloop-<table>-out`, exporters `otlp_http/devloop_<table>`, all present only when `services.greptimedb.pipelines.devloop` is non-empty; `resource/strip-database` deletes `vanixiets.database` and `vanixiets.table`; `queueBytes` with `devloop = mib 4` and `devloop_<table>` entries.
- Produces in R3.1: mutants `logsQueueNotPersistent`, `logsToFleet`, `logsToMetricsExporter`, `otlpInLogsPipeline`; clause messages `R3.1: a traces pipeline, or a logs pipeline exporting outside devloop` and `R3.1: a logs pipeline takes the local OTLP receiver` (contract name `logsTakeLocalReceiver`).
- Produces `vmTests.x86_64-linux.devloop-ingest`: outer `let` bindings `vars = "/run/devloop-ingest-vars"`, `credentialConsumers`, `baselineFixtures`, `giteaMqStub`, `unitMutants = { }` (entries `{ unit = "<unit without .service>"; module = …; }`), the case strings `firstStart`, `noAutoCreate`, `overlap`, `tableShape`, `switch`, `documentedQueries`, and `cases = [ firstStart noAutoCreate overlap tableShape switch documentedQueries ]`; `testScript = builtins.readFile ./devloop-ingest/helpers.py + lib.concatStringsSep "\n" cases`.
  Inside the container: `/etc/devloop-ingest/config.json` (keys `vars`, `psql`, `tables`, `questions`, `abandonMarker`, `batchEventKeys`), `/etc/devloop-ingest/mutants/<name>.conf` and `<name>.unit` per `unitMutants` entry, `/etc/devloop-ingest/gitea-mq-lines.txt`, `/etc/devloop-ingest/gitea-mq-empty.txt`, the runtime symlink `/run/devloop-ingest/gitea-mq-lines` that the stub reads, the specialisation `devloop-switch`.
  Helpers of the contract, plus the private `_sql`, `_count(table)`, `_sent(table)` and `_otel_metric(name, label, value)`; every Task 3 case leaves the collector running with no mutant drop-in.
  Baseline nixbot rows at boot: project 1; builds 9001 (pull request 9001) and 9002 (branch `gitea-mq/batch/1`, null `pr_number`); attributes `checks.x86_64-linux.pass`, `.abandoned`, `.broken` of 9001 (tied `finished_at`) and `checks.x86_64-linux.cached` of 9002; build ids from 9100 are free for later cases.

- [ ] **Step 1: Confirm the base**

Run from `$REPO`:

```bash
mkdir -p logs/s2-evidence
{
  pwd
  jj git fetch
  jj log --no-graph -r 'main@origin' -T 'commit_id.shortest(12) ++ " " ++ description.first_line() ++ "\n"'
  nix eval --json .#.lib.devloopCollection --apply builtins.attrNames
  nix eval --json .#nixosConfigurations.magnetite.config.services.greptimedb.pipelines --apply 'p: builtins.attrNames (p.devloop or { })'
  jj file show -r main@origin modules/nixos/devloop-collection.nix | wc -l
  ls logs/s2-evidence/2.6-schema-diff-*.log
  ls logs/s2-evidence/7.1-*.log
} 2>&1 | tee logs/s2-evidence/3.0-base-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: the path, then a `main@origin` that contains Tasks 1 and 2's merges; `["abandonMarker","ddl","grantSql","grants","pipelines","postgresqlMajor","queries","selects"]`; `["devloop_batch_event","devloop_ci_attribute","devloop_ci_build","devloop_deploy_record"]`; `309`; Task 2's schema-diff log; at least one 7.1 log.
If `devloop-collection.nix` is not 309 lines, re-read it and re-anchor Step 9's file against it before writing; if Task 2's schema diff chose nixbot's migrator (plan review F17), Step 5's `nixbot-schema.sh` replaces its migration loop with the exact command Task 2's `devloop-queries` uses for the migrator.

- [ ] **Step 2: Confirm the collector's components on magnetite (read-only)**

Run:

```bash
ssh magnetite.zt 'p=$(systemctl show -P ExecStart opentelemetry-collector.service | grep -o "/nix/store/[^ ]*/bin/otelcol-contrib" | head -n 1); "$p" --version; "$p" components | grep -E "^ *(- )?name: (sqlquery|journald|file_log|routing|forward)$"; systemctl show -P SupplementaryGroups opentelemetry-collector.service' 2>&1 | tee logs/s2-evidence/3.0-components-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `otelcol-contrib version 0.155.0`, five `name:` lines for `sqlquery`, `journald`, `file_log`, `routing` and `forward`, then `systemd-journal` (as `logs/s2/grounding.md` §4.2 recorded on 2026-10-21).
The keys this task writes were read at the pins:
- `sqlquery`: `driver`, `datasource`, `collection_interval`, `storage` (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:internal/sqlquery/config.go:15-27`); per query `sql`, `logs`, `tracking_column`, `tracking_start_value` (`:85-91`); per logs entry `body_column` and `attribute_columns` (`:116-118`), so each column becomes an attribute only when listed in that entry's `attribute_columns` (`receiver/sqlqueryreceiver/logs_receiver.go:364-382`); the last row's tracking value is stored under the receiver's storage and bound as `$1` (`logs_receiver.go:299-311`, `:319-321`, `:350-361`); the README places `attribute_columns` at query level (`README.md:85`), which the code contradicts, and the code is followed.
- `journald`: `units`, `grep`, `start_at`, `storage`, `operators` (`receiver/journaldreceiver/README.md:40-58`); `start_at: beginning` passes `--no-tail` and `grep` passes `--grep` (`pkg/stanza/operator/input/journald/config_linux.go:97-114`); the record's timestamp is `__REALTIME_TIMESTAMP`, removed from the body (`pkg/stanza/operator/input/journald/input.go:209-256`); `--priority info` is the default and gitea-mq's lines are `PRIORITY=6`.
- Operators: `key_value_parser` with `parse_from`, default `parse_to: attributes`, `=` and whitespace delimiters (`pkg/stanza/operator/parser/keyvalue/config.go:30-65`), splitting on whitespace outside quotes and stripping the outer quotes, so `msg="batch done"` yields `msg = batch done` (`internal/coreinternal/parseutils/parser.go:17-81`); `retain` keeps only the listed attributes and leaves the body untouched when no body field is listed (`pkg/stanza/operator/transformer/retain/transformer.go:33-60`); `remove` with `field: body` sets the body to null (`pkg/stanza/entry/body_field.go:126-131`); `json_parser` defaults to `parse_from: body`, `parse_to: attributes` (`pkg/stanza/docs/operators/json_parser.md:7-17`).
- `file_log`: `include`, `start_at`, `storage`, `operators` (`receiver/filelogreceiver/README.md:24-55`); its type is `file_log`, with `filelog` the deprecated alias (`receiver/filelogreceiver/internal/metadata/generated_status.go:12-13`); `include_file_name` defaults to true, adding `log.file.name`, which the keep-list removes.
- `routing`: a `table` of items with `context`, `condition`, `pipelines` (`connector/routingconnector/config.go:120-144`), `context: resource` evaluating the condition on the resource attributes (`connector/routingconnector/logs.go:79-104`), and a logs router resolving every route's pipelines as logs pipelines (`router.go:161-260`), which is why `routing/logs` is a second instance.
- `forward` carries logs to logs (`open-telemetry/opentelemetry-collector@v0.155.0:connector/forwardconnector/forward.go:24`); a connector used as a receiver in a logs pipeline must be an exporter in some logs pipeline, or the configuration is rejected (`service/internal/graph/graph.go:171-184`).
- Configuration strings without `${` are not expanded and `$$` becomes `$`, so the queries' single `$1` reaches the driver unchanged (`open-telemetry/opentelemetry-collector@v0.155.0:confmap/expand.go:73-76`, `confmap/resolver.go:198`, `:226-243`).
- Internal telemetry: with no `service.telemetry` in our configuration (no module sets it), the collector serves Prometheus on `localhost:8888` with `without_units` and `without_type_suffix` (`service/telemetry/otelconftelemetry/factory.go:50-59`), so the counters are named `otelcol_exporter_send_failed_log_records` and `otelcol_exporter_sent_log_records` (`exporter/exporterhelper/metadata.yaml:137-144`, `:173-176`), labelled `exporter="<component id>"` (`exporter/exporterhelper/internal/obs_report_sender.go:35`, `:71`).
- nixpkgs: `CREATE USER "<name>"`, a login role with no password, for each `ensureUsers` entry, run by `postgresql-setup.service` (`NixOS/nixpkgs@ac1faec44836:nixos/modules/services/databases/postgresql.nix:113`, `:870-921`); `ensureDBOwnership` defaults to false and `ensureClauses` to `{ }` (`:447-450`, `:457-476`); local connections are `peer` (`:693`); the collector unit is `DynamicUser` with `SupplementaryGroups = [ "systemd-journal" ]` (`nixos/modules/services/monitoring/opentelemetry-collector.nix:109-127`); nixbot's unit is ordered after and requires `postgresql.target` when `database.createLocally` (`Mic92/nixbot@d020013fa:nixosModules/nixbot.nix:1072-1084`).

- [ ] **Step 3: Show the task's values absent (RED, evaluation)**

Run:

```bash
{
  nix eval --json .#nixosConfigurations.magnetite.config.services.postgresql.ensureUsers --apply 'us: builtins.filter (n: n == "opentelemetry-collector" || n == "devloop-reconcile") (map (u: u.name) us)'
  nix eval --json .#nixosConfigurations.magnetite.config.systemd.services --apply 's: s ? devloop-pg-grants'
  nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings --apply 's: { receivers = builtins.filter (n: builtins.elem n [ "sqlquery/ci_attribute" "sqlquery/ci_build" "journald/gitea-mq" "file_log/deploy-record" ]) (builtins.attrNames s.receivers); logs = builtins.filter (n: builtins.substring 0 5 n == "logs/") (builtins.attrNames s.service.pipelines); routingLogs = s.connectors ? "routing/logs"; }'
  nix eval --json .#.lib.devloopCollection --apply 'd: { questions = d ? questions; batchEventKeys = d ? batchEventKeys; }'
  nix eval --json .#nixosConfigurations.magnetite.config.services.observability-notify.units --apply 'us: builtins.elem "devloop-pg-grants" us'
} 2>&1 | tee logs/s2-evidence/3.0-absent-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `[]`, `false`, `{"logs":[],"receivers":[],"routingLogs":false}`, `{"batchEventKeys":false,"questions":false}`, `false`.

- [ ] **Step 4: Show the journal assertion absent (RED, evaluation)**

The two values the assertion relates are the receiver this module declares, which reads `gitea-mq.service`'s journal, and the unit's `SupplementaryGroups`, which nixpkgs' collector module sets; both belong to magnetite, so the relation is an assertion, not a check clause.
Run:

```bash
nix eval --impure --json --expr '
let
  flake = builtins.getFlake (toString ./.);
  lib = flake.inputs.nixpkgs.lib;
  host = flake.nixosConfigurations.magnetite;
  failing = m: map (a: a.message) (lib.filter (a: !a.assertion) (host.extendModules { modules = [ m ]; }).config.assertions);
in lib.mapAttrs (_: failing) {
  control = { };
  journalGroupCleared = { systemd.services.opentelemetry-collector.serviceConfig.SupplementaryGroups = lib.mkForce [ ]; };
}' 2>&1 | jq -r 'to_entries[] | "=== \(.key)", .value[]' | tee logs/s2-evidence/3.7-journal-assertion-red-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `=== control` and `=== journalGroupCleared`, each followed by nothing: clearing the group is not yet caught.

- [ ] **Step 5: Write the container test's data files**

Create `modules/vm-tests/devloop-ingest/nixbot-schema.sh` with exactly:

```bash
#!/usr/bin/env bash
# Stand-in for nixbot's start in vmTests.x86_64-linux.devloop-ingest: applies
# the nixbot input's migrations to the nixbot database in lexical order, one
# transaction per file, as checks.x86_64-linux.devloop-queries does (design
# D14; Task 2's schema diff), then the test's baseline fixture rows.
# Usage: nixbot-schema.sh MIGRATIONS_DIR FIXTURES_SQL
set -euo pipefail
migrations=$1
fixtures=$2
for migration in "$migrations"/*.sql; do
  psql -X -q -v ON_ERROR_STOP=1 --single-transaction -d nixbot -f "$migration"
done
psql -X -q -v ON_ERROR_STOP=1 --single-transaction -d nixbot -f "$fixtures"
```

Create `modules/vm-tests/devloop-ingest/gitea-mq-lines.txt` with exactly these 13 lines, slog text lines of the shapes `logs/s2/grounding.md` §2.2 records at `Mic92/gitea-mq@02264515b:internal/batch/batch.go:143`, `:228`, `:328`, `:391`, `:568`, plus one non-batch line, one batch line outside the five messages and one `batch formed` line with an extra key:

```text
time=2026-10-21T10:00:00.000Z level=INFO msg="batch formed" batch=1 branch=gitea-mq/batch/1 members=2
time=2026-10-21T10:00:01.000Z level=INFO msg="batch built" batch=1 build=11 sha=1111111111111111111111111111111111111111 current=1 pending=0
time=2026-10-21T10:00:02.000Z level=INFO msg="batch landed" batch=1 sha=1111111111111111111111111111111111111111 prs=2
time=2026-10-21T10:00:03.000Z level=INFO msg="batch done" batch=1 landed=2 ejected=0 builds=1 flaky=false
time=2026-10-21T10:01:00.000Z level=INFO msg="batch formed" batch=2 branch=gitea-mq/batch/2 members=3
time=2026-10-21T10:01:01.000Z level=INFO msg="batch built" batch=2 build=12 sha=2222222222222222222222222222222222222222 current=1 pending=0
time=2026-10-21T10:01:02.000Z level=INFO msg="batch bisecting" batch=2 build=12 failed_check=nixbot/nix-build left=1 right=2
time=2026-10-21T10:01:03.000Z level=INFO msg="batch built" batch=2 build=13 sha=3333333333333333333333333333333333333333 current=1 pending=1
time=2026-10-21T10:01:04.000Z level=INFO msg="batch landed" batch=2 sha=3333333333333333333333333333333333333333 prs=1
time=2026-10-21T10:01:05.000Z level=INFO msg="batch done" batch=2 landed=1 ejected=2 builds=2 flaky=true
time=2026-10-21T10:01:06.000Z level=INFO msg="batch reconcile build failed" batch=2 build=14 err="exit status 1"
time=2026-10-21T10:02:00.000Z level=INFO msg="batch formed" batch=3 branch=gitea-mq/batch/3 members=1 extra_key=dropped
time=2026-10-21T10:02:01.000Z level=INFO msg="discovery: reconciled" repos=1
```

Eleven lines match design D7's pattern: `batch formed` 3, `batch built` 3, `batch landed` 2, `batch bisecting` 1, `batch done` 2.

- [ ] **Step 6: Write the test helpers**

Create `modules/vm-tests/devloop-ingest/helpers.py` with exactly:

```python
# Helpers for vmTests.x86_64-linux.devloop-ingest (design D16). The test
# driver runs this file and then each case string of the `cases` list in
# modules/vm-tests/devloop-ingest.nix, in order. Every case prints
# `=== case <name>` first and `ok: <name>` last, prints
# `mutant <name> rejected: <reason>` for each mutant it shows rejected, and
# leaves the collector running with no mutant drop-in.
import datetime as dt
import json
import re
import shlex

COLLECTOR = "opentelemetry-collector"
DEPLOY_RECORD = "/var/log/deploy-record.jsonl"
_CONFIG = None


def config():
    """/etc/devloop-ingest/config.json, rendered by the container module."""
    global _CONFIG
    if _CONFIG is None:
        _CONFIG = json.loads(store.succeed("cat /etc/devloop-ingest/config.json"))
    return _CONFIG


def _sql(user, query, db):
    cmd = [
        "curl", "-sS", "-o", "/tmp/devloop-sql-response", "-w", "%{http_code}",
        "--netrc-file", f"{config()['vars']}/{user}.netrc",
        "--data-urlencode", f"sql={query}",
        f"http://127.0.0.1:4000/v1/sql?db={db}",
    ]
    status = int(store.succeed(shlex.join(cmd)))
    return status, store.succeed("cat /tmp/devloop-sql-response")


def _output(user, query, db):
    status, body = _sql(user, query, db)
    assert status == 200, (user, query, status, body)
    # A statement without rows answers {"affectedrows": n} instead of
    # {"records": ...} (GreptimeTeam/greptimedb@v1.2.1:src/servers/src/http.rs:395-400).
    output = json.loads(body)["output"][0]
    return output["records"]["rows"] if "records" in output else output["affectedrows"]


def gsql(query, db="devloop"):
    """A read as the store's `regulator` account; returns records.rows."""
    return _output("regulator", query, db)


def admin_sql(query, db="devloop"):
    """A statement as the store's `admin` account."""
    return _output("admin", query, db)


def psql(query, role="postgres"):
    """psql -XAt on nixbot as `postgres`, under SET ROLE for another role."""
    role_statement = [] if role == "postgres" else ["-c", f'SET ROLE "{role}"']
    cmd = [
        "runuser", "-u", "postgres", "--", config()["psql"],
        "-XAtq", "-v", "ON_ERROR_STOP=1", "-d", "nixbot", *role_statement, "-c", query,
    ]
    return store.succeed(shlex.join(cmd))


def nixbot_rows(sql):
    """Fixture inserts into nixbot's database as `postgres`."""
    return psql(sql)


def collector_restart(mutant=None):
    """Remove every mutant drop-in, install `mutant`'s when given, reload,
    restart each unit that had or gets a drop-in, then the collector."""
    units = store.succeed(
        'for f in /run/systemd/system/*.service.d/zz-mutant.conf; do '
        '[ -e "$f" ] && basename "$(dirname "$f")" .service.d; done; true'
    ).split()
    store.succeed("rm -f /run/systemd/system/*.service.d/zz-mutant.conf")
    if mutant is not None:
        unit = store.succeed(f"cat /etc/devloop-ingest/mutants/{mutant}.unit").strip()
        store.succeed(
            f"install -D -m 0444 /etc/devloop-ingest/mutants/{mutant}.conf "
            f"/run/systemd/system/{unit}.service.d/zz-mutant.conf"
        )
        units.append(unit)
    store.succeed("systemctl daemon-reload")
    for unit in sorted(set(units) - {COLLECTOR}):
        store.succeed(f"systemctl restart {unit}.service")
    store.succeed(f"systemctl restart {COLLECTOR}.service")
    store.wait_for_unit(f"{COLLECTOR}.service")


def reset_devloop():
    """Stop the collector, delete its file_storage directory (cursors and
    queues), drop the four tables as admin, rerun the schema job and empty
    the deploy-record file. The journald receiver then re-reads the stub's
    journal from its beginning. The collector stays stopped."""
    store.succeed(
        f"systemctl stop {COLLECTOR}.service",
        "rm -rf /var/lib/opentelemetry-collector/queue",
    )
    for table in config()["tables"]:
        admin_sql(f'DROP TABLE IF EXISTS "{table}"')
    store.succeed(
        "systemctl restart greptimedb-schema.service",
        f": > {DEPLOY_RECORD}",
    )


def _otel_metric(name, label, value):
    """The sum of a counter over the series whose `label` equals `value`
    in the collector's internal telemetry; 0 when no series exists."""
    text = store.succeed("curl -sS http://localhost:8888/metrics")
    pattern = re.compile("^" + re.escape(name) + r"\{([^}]*)\} (\S+)$")
    total = 0.0
    for line in text.splitlines():
        match = pattern.match(line)
        if match and f'{label}="{value}"' in match.group(1):
            total += float(match.group(2))
    return int(total)


def send_failed(table):
    return _otel_metric(
        "otelcol_exporter_send_failed_log_records", "exporter", f"otlp_http/devloop_{table}"
    )


def _sent(table):
    return _otel_metric(
        "otelcol_exporter_sent_log_records", "exporter", f"otlp_http/devloop_{table}"
    )


def _count(table):
    status, body = _sql("regulator", f'SELECT count(*) FROM "{table}"', "devloop")
    if status != 200:
        return 0
    return json.loads(body)["output"][0]["records"]["rows"][0][0]


def wait_rows(table, n, timeout=240):
    """Wait until the table holds at least n rows; return its count."""
    retry(lambda _last: _count(table) >= n, timeout=dt.timedelta(seconds=timeout))
    return _count(table)


def key_counts(table):
    """(rows, distinct keys), a key being the primary key and the time index,
    the identity under which a non-append table keeps one row."""
    spec = config()["tables"][table]
    key = ", ".join(f'"{c}"' for c in spec["primaryKey"] + [spec["timeIndex"]])
    rows = gsql(f'SELECT count(*) FROM "{table}"')[0][0]
    distinct = gsql(f'SELECT count(*) FROM (SELECT DISTINCT {key} FROM "{table}") AS k')[0][0]
    return rows, distinct


def utc_today():
    """The container's UTC date. Within 10 minutes of 00:00 UTC it first
    waits until 5 s after midnight, so a case's fixture rows and any window
    a later case derives from this date fall in one UTC day."""
    now = int(store.succeed("date -u +%s").strip())
    into_day = now % 86400
    if into_day >= 86400 - 600:
        wait = 86400 - into_day + 5
        print(f"utc_today: {wait} s before 00:00 UTC; waiting for the next day")
        store.succeed(f"sleep {wait}")
    return store.succeed("date -u +%F").strip()
```

`retry`, `store` and `start_all` are the NixOS test driver's globals, as `modules/vm-tests/greptimedb-pipeline.nix:276-397` uses them.

- [ ] **Step 7: Write `modules/vm-tests/devloop-ingest.nix` (the test file, before the code it judges)**

Create `modules/vm-tests/devloop-ingest.nix` with exactly:

````nix
# On-demand runtime test of S2's collection path
# (openspec/changes/stand-up-devloop-collection, design D16; tasks.md 3.9,
# 4.6, 5.6).
#
# One systemd-nspawn container on a builder advertising uid-range
# (magnetite) runs PostgreSQL with the nixbot input's migrations, applied by
# a stand-in nixbot.service that devloop-pg-grants orders after; GreptimeDB
# with magnetite's databases, the devloop tables and pipelines and the
# credentials of magnetite's greptimedb-users generator; the collector with
# both roles and devloop-collection; a stub gitea-mq.service printing the
# lines of /run/devloop-ingest/gitea-mq-lines; and the deploy-record
# activation snippet. testScript is helpers.py followed by `cases`, in order.
#
# What it establishes: each devloop exporter's first send succeeds when the
# store, its schema job and the collector start together, and fails when the
# schema job has not created its table (auto_create_table=false); each stored
# table equals the allow-list; overlap re-reads leave one row per key; lines
# outside the five batch messages are not stored; one activation appends one
# deploy record naming both closures and reaches the store; the documented
# queries answer on GreptimeDB 1.2.1.
#
# What it does not establish: the collector's keep-list (`retain`) and body
# removal, which are defence in depth with no test here, because the
# pre-created DDL and each pipeline's VRL reset (`. = {}` and one assignment
# per allow-listed field) decide the stored columns whatever the record
# carries; the collector's order after the schema job, which R3.1's
# schemaOrderDropped mutant judges; nixbot itself (the stand-in only migrates),
# magnetite's journal retention, deployed credentials or storage, the OOM
# order, or a specialisation switch the container cannot perform: the
# switch case prints a `limitation:` line when it falls back to running the
# activation script. A configuration mutant is installed at runtime as a
# drop-in, because an nspawn node cannot switch to a specialisation.
{ self, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        devloop-ingest =
          let
            # perSystem `pkgs` lacks the flake overlay that carries
            # greptimedb-bin.
            nodePkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
              overlays = [ self.overlays.default ];
            };
            reference = self.nixosConfigurations.magnetite.config;
            inherit (reference.services.greptimedb) databases;
            usersGenerator = reference.clan.core.vars.generators.greptimedb-users;
            schema = self.lib.otelCollectorSchema;
            devloop = self.lib.devloopCollection;
            vars = "/run/devloop-ingest-vars";
            credentialConsumers = [
              "greptimedb.service"
              "greptimedb-schema.service"
              "opentelemetry-collector.service"
            ];

            # nixbot's rows at boot: build 9001 is a pull-request build whose
            # three attributes finish in one transaction (a finished_at tie),
            # one abandoned by the marker and one an ignored_failure with
            # error text; build 9002 is a merge-queue build with no
            # pull-request number and one cached attribute.
            baselineFixtures = pkgs.writeText "devloop-ingest-baseline.sql" ''
              INSERT INTO projects (id, forge, forge_repo_id, owner, name, default_branch, url)
              OVERRIDING SYSTEM VALUE
              VALUES (1, 'gitea', '1', 'crs58', 'vanixiets', 'main', 'https://gitea.zt/crs58/vanixiets');
              INSERT INTO builds (id, project_id, number, commit_sha, branch, pr_number, status, created_at, started_at, finished_at, eval_duration_ms, eval_completed)
              OVERRIDING SYSTEM VALUE
              VALUES
                (9001, 1, 1, 'a000000000000000000000000000000000009001', 'pr/9001', 9001, 'failed', now() - interval '30 minutes', now() - interval '25 minutes', now() - interval '10 minutes', 4200, true),
                (9002, 1, 2, 'b000000000000000000000000000000000009002', 'gitea-mq/batch/1', NULL, 'succeeded', now() - interval '29 minutes', now() - interval '28 minutes', now() - interval '11 minutes', 3100, true);
              INSERT INTO build_attributes (build_id, attr, system, drv_path, outputs, status, cached, error, started_at, finished_at, eval_wall_ms, eval_alloc_bytes)
              VALUES
                (9001, 'checks.x86_64-linux.pass', 'x86_64-linux', '/nix/store/00000000000000000000000000000001-pass.drv', '{"out": "/nix/store/00000000000000000000000000000001-pass"}', 'succeeded', false, NULL, now() - interval '20 minutes', now() - interval '12 minutes', 900, 1048576),
                (9001, 'checks.x86_64-linux.abandoned', 'x86_64-linux', '/nix/store/00000000000000000000000000000002-abandoned.drv', NULL, 'ignored_failure', false, '${devloop.abandonMarker}', NULL, now() - interval '12 minutes', NULL, NULL),
                (9001, 'checks.x86_64-linux.broken', 'x86_64-linux', '/nix/store/00000000000000000000000000000003-broken.drv', NULL, 'ignored_failure', false, 'error: builder for broken failed with exit code 1', now() - interval '19 minutes', now() - interval '12 minutes', 700, 524288),
                (9002, 'checks.x86_64-linux.cached', 'x86_64-linux', '/nix/store/00000000000000000000000000000004-cached.drv', '{"out": "/nix/store/00000000000000000000000000000004-cached"}', 'skipped_local', true, NULL, NULL, now() - interval '13 minutes', 50, 65536);
            '';

            # Prints one line at a time, so the journal gives each line its
            # own __REALTIME_TIMESTAMP.
            giteaMqStub = pkgs.writeShellScript "gitea-mq-stub" ''
              while IFS= read -r line; do
                printf '%s\n' "$line"
                sleep 0.05
              done < /run/devloop-ingest/gitea-mq-lines
            '';

            # Configuration mutants: name -> { unit (without .service);
            # module }. Each is rendered as a drop-in of the unit's ExecStart
            # under the container's extendModules (Task 4 adds entries).
            unitMutants = { };

            firstStart = ''
              print("=== case firstStart")
              start_all()
              store.wait_for_unit("multi-user.target")
              for table in config()["tables"]:
                  retry(
                      lambda _last, t=table: _count(t) > 0 and _sent(t) > 0,
                      timeout=dt.timedelta(minutes=5),
                  )
                  failed = send_failed(table)
                  assert failed == 0, (table, failed)
                  print(f"ok: firstStart: otlp_http/devloop_{table} sent {_sent(table)}, send_failed 0")
              type_names = {
                  "int64": "Int64",
                  "string": "String",
                  "boolean": "Boolean",
                  "timestamp": "TimestampMicrosecond",
              }
              for table, spec in config()["tables"].items():
                  desc = gsql(f'DESC TABLE "{table}"')
                  got = [(row[0], row[1], row[5]) for row in desc]
                  want = [
                      (
                          column["name"],
                          type_names[column["type"]],
                          "TIMESTAMP" if column["name"] == spec["timeIndex"]
                          else "TAG" if column["name"] in spec["primaryKey"]
                          else "FIELD",
                      )
                      for column in spec["columns"]
                  ]
                  assert got == want, (table, got, want)
                  assert "body" not in [row[0] for row in desc], (table, desc)
                  print(f"ok: firstStart: DESC TABLE {table} equals the allow-list")
              print("ok: firstStart")
            '';

            noAutoCreate = ''
              print("=== case noAutoCreate")
              reset_devloop()
              admin_sql('DROP TABLE "ci_build"')
              collector_restart()
              retry(lambda _last: send_failed("ci_build") > 0, timeout=dt.timedelta(minutes=5))
              tables = [row[0] for row in gsql("SHOW TABLES")]
              assert "ci_build" not in tables, tables
              for table in ("ci_attribute", "batch_event"):
                  retry(lambda _last, t=table: _sent(t) > 0, timeout=dt.timedelta(minutes=5))
                  assert send_failed(table) == 0, (table, send_failed(table))
              print(
                  "mutant noAutoCreate rejected: otlp_http/devloop_ci_build send_failed "
                  f"{send_failed('ci_build')} when the schema job's tables lack ci_build, and no table was created"
              )
              reset_devloop()
              collector_restart()
              retry(lambda _last: _sent("ci_build") > 0, timeout=dt.timedelta(minutes=5))
              assert send_failed("ci_build") == 0, send_failed("ci_build")
              print("ok: noAutoCreate")
            '';

            overlap = ''
              print("=== case overlap")
              utc_today()
              reset_devloop()
              collector_restart()
              wait_rows("ci_attribute", int(psql("SELECT count(*) FROM build_attributes").strip()))
              nixbot_rows(
                  "INSERT INTO builds (id, project_id, number, commit_sha, branch, pr_number, status, created_at, started_at, finished_at, eval_completed) "
                  "OVERRIDING SYSTEM VALUE VALUES (9101, 1, 9101, 'c000000000000000000000000000000000009101', 'pr/9101', 9101, 'succeeded', now() - interval '3 minutes', now() - interval '2 minutes', now(), true); "
                  "INSERT INTO build_attributes (build_id, attr, system, status, cached, started_at, finished_at) VALUES "
                  "(9101, 'checks.x86_64-linux.overlap-a', 'x86_64-linux', 'succeeded', false, now() - interval '1 minute', now()), "
                  "(9101, 'checks.x86_64-linux.overlap-b', 'x86_64-linux', 'succeeded', false, now() - interval '1 minute', now()), "
                  "(9101, 'checks.x86_64-linux.overlap-c', 'x86_64-linux', 'skipped_local', true, NULL, now())"
              )
              # The counters are read once the new rows are stored, so idle
              # re-reads of the cursor's tie before the insert cannot meet the
              # bound; every later poll re-reads the three attribute rows and
              # the build row while they are under 5 min old (design D6), so
              # two more polls send at least 6 and 2 more records.
              retry(
                  lambda _last: gsql('SELECT count(*) FROM "ci_attribute" WHERE "build_id" = 9101') == [[3]]
                  and gsql('SELECT count(*) FROM "ci_build" WHERE "build_id" = 9101') == [[1]],
                  timeout=dt.timedelta(minutes=3),
              )
              attributes_before = _sent("ci_attribute")
              builds_before = _sent("ci_build")
              retry(
                  lambda _last: _sent("ci_attribute") >= attributes_before + 6
                  and _sent("ci_build") >= builds_before + 2,
                  timeout=dt.timedelta(minutes=4),
              )
              for table in ("ci_attribute", "ci_build"):
                  rows, distinct = key_counts(table)
                  assert rows == distinct, (table, rows, distinct)
              assert gsql('SELECT count(*) FROM "ci_attribute" WHERE "build_id" = 9101') == [[3]]
              assert gsql('SELECT count(*) FROM "ci_build" WHERE "build_id" = 9101') == [[1]]
              print(
                  f"ok: overlap: ci_attribute sent {_sent('ci_attribute') - attributes_before} and ci_build "
                  f"{_sent('ci_build') - builds_before} records after the rows were stored; one row per key"
              )
              print("ok: overlap")
            '';

            tableShape = ''
              print("=== case tableShape")
              pattern = re.compile(r'msg="(batch (formed|built|landed|bisecting|done))"')
              want = {}
              for line in store.succeed("cat /etc/devloop-ingest/gitea-mq-lines.txt").splitlines():
                  match = pattern.search(line)
                  if match:
                      want[match.group(1)] = want.get(match.group(1), 0) + 1
              printed = int(store.succeed(
                  "journalctl -u gitea-mq.service -o cat | grep -cE 'msg=\"batch (formed|built|landed|bisecting|done)\"'"
              ).strip())
              assert printed == sum(want.values()), (printed, want)
              wait_rows("batch_event", sum(want.values()))
              got = {row[0]: row[1] for row in gsql('SELECT "msg", count(*) FROM "batch_event" GROUP BY "msg"')}
              assert got == want, (got, want)
              assert gsql("SELECT count(*) FROM \"batch_event\" WHERE \"msg\" = 'batch reconcile build failed'") == [[0]]
              columns = [row[0] for row in gsql('DESC TABLE "batch_event"')]
              for key in ("extra_key", "branch", "time", "level", "current", "pending", "prs", "left", "right", "err", "repos"):
                  assert key not in columns, (key, columns)
              assert gsql("SELECT \"members\" FROM \"batch_event\" WHERE \"batch\" = 3 AND \"msg\" = 'batch formed'") == [[1]]
              assert gsql("SELECT \"flaky\", \"ejected\" FROM \"batch_event\" WHERE \"batch\" = 2 AND \"msg\" = 'batch done'") == [[True, 2]]
              print(f"ok: tableShape: batch_event per msg {got}; the reconcile line is not stored")

              # The CI rows as stored against nixbot's source rows, read by
              # psql; abandoned against the fixture's intent.
              retry(
                  lambda _last: gsql('SELECT count(*) FROM "ci_attribute" WHERE "build_id" IN (9001, 9002)') == [[4]],
                  timeout=dt.timedelta(minutes=4),
              )
              source = []
              for line in psql(
                  "SELECT a.build_id, a.attr, a.status, a.cached, coalesce(a.outputs ->> 'out', '''), "
                  "(extract(epoch FROM a.finished_at) * 1000000)::bigint, coalesce(b.pr_number::text, ''') "
                  "FROM build_attributes a JOIN builds b ON b.id = a.build_id "
                  "WHERE a.build_id IN (9001, 9002) ORDER BY a.build_id, a.attr"
              ).splitlines():
                  build, attr, status, cached, out, finished, pr = line.split("|")
                  source.append([int(build), attr, status, cached == "t", out or None, int(finished), int(pr) if pr else None])
              stored = gsql(
                  'SELECT "build_id", "attr", "status", "cached", "outputs_out", "finished_at", "pr_number", "abandoned" '
                  'FROM "ci_attribute" WHERE "build_id" IN (9001, 9002) ORDER BY "build_id", "attr"'
              )
              assert [row[:7] for row in stored] == source, (stored, source)
              abandoned = {row[1]: row[7] for row in stored}
              assert abandoned == {
                  "checks.x86_64-linux.abandoned": True,
                  "checks.x86_64-linux.broken": False,
                  "checks.x86_64-linux.pass": False,
                  "checks.x86_64-linux.cached": False,
              }, abandoned
              broken = gsql("SELECT * FROM \"ci_attribute\" WHERE \"attr\" = 'checks.x86_64-linux.broken'")
              assert not any("builder for broken failed" in str(value) for value in broken[0]), broken
              print("ok: tableShape: ci_attribute equals nixbot's rows, abandoned only for the marker, no error text")
              print("ok: tableShape")
            '';

            switch = ''
              print("=== case switch")

              def record_lines():
                  text = store.succeed(f"cat {DEPLOY_RECORD} 2>/dev/null || true")
                  return [json.loads(line) for line in text.splitlines() if line.strip()]

              original = store.succeed("readlink -f /run/current-system").strip()
              variant = store.succeed("readlink -f /run/current-system/specialisation/devloop-switch").strip()
              before = record_lines()
              code, output = store.execute(f"{variant}/bin/switch-to-configuration test 2>&1")
              added = record_lines()[len(before):]
              switched = code == 0
              if code != 0 and not added:
                  print(
                      f"limitation: switch-to-configuration test exited {code} in the nspawn container "
                      f"before activation ({output.strip().splitlines()[-1] if output.strip() else 'no output'}); "
                      f"running {variant}/activate, which sets systemConfig={variant} (design D16)"
                  )
                  store.succeed(f"{variant}/activate")
                  added = record_lines()[len(before):]
              elif code != 0:
                  print(f"limitation: switch-to-configuration test exited {code} after activation appended its line")
              assert len(added) == 1, added
              line = added[0]
              assert set(line) == {"host", "closure", "previous_closure", "ts"}, line
              assert line["host"] == "store", line
              assert line["closure"] == variant, (line, variant)
              assert line["previous_closure"] == original, (line, original)
              assert re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", line["ts"]), line
              print(f"ok: switch: one line, closure {variant}, previous_closure {original}")

              # Back to the original system, one second later so the second
              # record has its own (host, ts) key.
              store.succeed("sleep 1.1")
              if switched:
                  store.succeed(f"{original}/bin/switch-to-configuration test")
              else:
                  store.succeed(f"{original}/activate")
              lines = record_lines()
              assert lines[-1]["closure"] == original and lines[-1]["previous_closure"] == variant, lines[-1]
              wait_rows("deploy_record", len(lines))
              stored = gsql('SELECT "closure", "previous_closure" FROM "deploy_record" WHERE "host" = \'store\' ORDER BY "ts"')
              assert stored[-2:] == [[variant, original], [original, variant]], stored
              print("ok: switch: both records reached deploy_record")
              print("ok: switch")
            '';

            documentedQueries = ''
              print("=== case documentedQueries")
              reset_devloop()
              t0 = dt.datetime.fromtimestamp(int(store.succeed("date -u +%s").strip()) - 7200, dt.timezone.utc)

              def at(seconds):
                  return (t0 + dt.timedelta(seconds=seconds)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")

              admin_sql(
                  'INSERT INTO "batch_event" ("batch", "msg", "members", "landed", "ejected", "builds", "flaky", "ts") VALUES '
                  f"(9001, 'batch formed', 2, NULL, NULL, NULL, NULL, '{at(0)}'), "
                  f"(9001, 'batch done', NULL, 2, 0, 1, false, '{at(600)}'), "
                  f"(9002, 'batch formed', 3, NULL, NULL, NULL, NULL, '{at(60)}'), "
                  f"(9002, 'batch landed', NULL, NULL, NULL, NULL, NULL, '{at(600)}'), "
                  f"(9002, 'batch done', NULL, 1, 2, 2, true, '{at(1860)}'), "
                  f"(9003, 'batch formed', 1, NULL, NULL, NULL, NULL, '{at(120)}')"
              )
              builds = [
                  f"({601 + k}, '{at(0)}', '{at(60 * k)}', '{at(60 * k + 60)}', 'succeeded', 7, 'pr/7')"
                  for k in range(11)
              ]
              builds.append(f"(612, '{at(0)}', '{at(9999)}', '{at(10059)}', 'succeeded', NULL, 'main')")
              builds.append(f"(613, '{at(0)}', NULL, '{at(30)}', 'cancelled', 7, 'pr/7')")
              # Build 605 restarted: nixbot keeps created_at and resets the
              # start, so the rerun row waits 5000 s and must not count.
              builds.append(f"(605, '{at(0)}', '{at(5000)}', '{at(5060)}', 'succeeded', 7, 'pr/7')")
              admin_sql(
                  'INSERT INTO "ci_build" ("build_id", "created_at", "started_at", "finished_at", "status", "pr_number", "branch") VALUES '
                  + ", ".join(builds)
              )
              attributes = [
                  (501, "a", "succeeded", False, False, "A"),
                  (501, "b", "skipped_local", True, False, "B"),
                  (502, "a", "failed", False, False, "C"),
                  (503, "a", "failed", False, False, "D"),
                  (504, "a", "succeeded", False, False, "D"),
                  (505, "a", "ignored_failure", False, True, "E"),
                  (505, "b", "succeeded", False, False, "F"),
                  (506, "a", "dependency_failed", False, False, "G"),
                  (507, "a", "ignored_failure", False, False, "H"),
                  (509, "a", "failed_eval", False, False, None),
              ]
              admin_sql(
                  'INSERT INTO "ci_attribute" ("build_id", "attr", "status", "cached", "abandoned", "drv_path", "finished_at") VALUES '
                  + ", ".join(
                      f"({build}, 'checks.x86_64-linux.{attr}', '{status}', {str(cached).lower()}, {str(abandoned).lower()}, "
                      + (f"'/nix/store/0000000000000000000000000000000{drv}-{drv}.drv'" if drv else "NULL")
                      + f", '{at(3000 + build)}')"
                      for build, attr, status, cached, abandoned, drv in attributes
                  )
              )

              def close(a, b):
                  return abs(a - b) < 1e-6

              questions = config()["questions"]
              formation = gsql(questions["formationToLand"])
              print(f"formationToLand: {formation}")
              assert [row[0] for row in formation] == [9001, 9002], formation
              assert close(formation[0][1], 600.0) and close(formation[1][1], 1800.0), formation
              wait = gsql(questions["queueWait"])
              print(f"queueWait: {wait}")
              assert gsql('SELECT count(*) FROM "ci_build" WHERE "build_id" = 605') == [[2]]
              assert len(wait) == 1 and wait[0][3] == 11, wait
              assert close(wait[0][0], 300.0) and close(wait[0][1], 540.0) and close(wait[0][2], 594.0), wait
              print("ok: documentedQueries: queueWait counts build 605's first attempt only, not its 5000 s rerun")
              outcome = gsql(questions["buildOutcome"])
              print(f"buildOutcome: {outcome}")
              assert outcome == [
                  [501, "passed"], [502, "failed"], [503, "passed"], [504, "passed"], [505, "passed"],
                  [506, "failed"], [507, "failed"], [509, "failed"],
              ], outcome
              print("ok: documentedQueries: each of the three questions returns its fixture answer")
              reset_devloop()
              collector_restart()
              print("ok: documentedQueries")
            '';

            cases = [
              firstStart
              noAutoCreate
              overlap
              tableShape
              switch
              documentedQueries
            ];
          in
          pkgs.testers.runNixOSTest {
            name = "devloop-ingest";
            requiredFeatures = {
              nixos-test = true;
              uid-range = true;
            };
            node.pkgs = lib.mkForce nodePkgs;
            containers.store =
              {
                config,
                extendModules,
                pkgs,
                ...
              }:
              {
                imports = [
                  self.modules.nixos.greptimedb
                  self.modules.nixos.otel-collector-agent
                  self.modules.nixos.otel-collector-ingress
                  self.modules.nixos.devloop-collection
                  self.modules.nixos.deploy-record
                ];
                system.stateVersion = lib.trivial.release;
                environment.systemPackages = [ pkgs.curl ];

                services.greptimedb = {
                  enable = true;
                  inherit databases;
                };

                # magnetite's PostgreSQL; the stand-in nixbot.service applies
                # the nixbot input's migrations, as nixbot's own start does,
                # and devloop-pg-grants orders after it.
                services.postgresql = {
                  enable = true;
                  inherit (reference.services.postgresql) package;
                  ensureDatabases = [ "nixbot" ];
                };
                systemd.services.nixbot = {
                  description = "Stand-in for nixbot: the input's migrations and the baseline rows";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "postgresql.target" ];
                  requires = [ "postgresql.target" ];
                  path = [
                    config.services.postgresql.package
                    pkgs.bash
                  ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    User = "postgres";
                    Group = "postgres";
                  };
                  script = "bash ${./devloop-ingest/nixbot-schema.sh} ${inputs.nixbot}/nixbot/nixbot/migrations ${baselineFixtures}";
                };

                # gitea-mq writes slog text to stdout under its own unit
                # (logs/s2/grounding.md §2.1); the stub does the same with
                # the lines its runtime symlink names, which a case may point
                # at gitea-mq-empty.txt.
                systemd.services.gitea-mq = {
                  description = "Stand-in for gitea-mq: prints fixture slog lines";
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    ExecStart = "${giteaMqStub}";
                  };
                };
                systemd.tmpfiles.rules = [
                  "d /run/devloop-ingest 0755 root root -"
                  "L+ /run/devloop-ingest/gitea-mq-lines - - - - /etc/devloop-ingest/gitea-mq-lines.txt"
                ];

                # Credentials from magnetite's own generator script, run at
                # boot, so no credential value exists in the repository; the
                # netrc files keep passwords out of the driver's log.
                systemd.services.devloop-ingest-vars = {
                  description = "Test credentials from magnetite's greptimedb-users generator";
                  requiredBy = credentialConsumers;
                  before = credentialConsumers;
                  path = [
                    pkgs.bash
                    pkgs.coreutils
                  ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  script = ''
                    install -d -m 0700 ${vars}
                    out=${vars} bash ${usersGenerator.finalScript}
                    for user in admin collector perses regulator; do
                      printf 'machine 127.0.0.1 login %s password %s\n' \
                        "$user" "$(cat "${vars}/$user-password")" > "${vars}/$user.netrc"
                    done
                  '';
                };
                systemd.services.greptimedb.serviceConfig.LoadCredential = [ "users:${vars}/users" ];
                systemd.services.greptimedb-schema.serviceConfig.LoadCredential = [
                  "admin-password:${vars}/admin-password"
                ];
                systemd.services.opentelemetry-collector.serviceConfig.LoadCredential = [
                  "collector-password:${vars}/collector-password"
                ];

                # The switch case's second system.
                specialisation.devloop-switch.configuration = {
                  environment.etc."devloop-ingest/variant".text = "devloop-switch";
                };

                environment.etc = {
                  "devloop-ingest/gitea-mq-lines.txt".source = ./devloop-ingest/gitea-mq-lines.txt;
                  "devloop-ingest/gitea-mq-empty.txt".text = "";
                  "devloop-ingest/config.json".text = builtins.toJSON {
                    inherit vars;
                    psql = "${config.services.postgresql.package}/bin/psql";
                    inherit (schema.devloop) tables;
                    inherit (devloop) questions abandonMarker batchEventKeys;
                  };
                }
                // lib.concatMapAttrs (name: mutant: {
                  "devloop-ingest/mutants/${name}.unit".text = mutant.unit;
                  "devloop-ingest/mutants/${name}.conf".text = ''
                    [Service]
                    ExecStart=
                    ${lib.concatMapStringsSep "\n" (command: "ExecStart=${command}") (
                      lib.toList
                        (extendModules { modules = [ mutant.module ]; })
                        .config.systemd.services.${mutant.unit}.serviceConfig.ExecStart
                    )}
                  '';
                }) unitMutants;
              };
            testScript = builtins.readFile ./devloop-ingest/helpers.py + lib.concatStringsSep "\n" cases;
          };
      };
    };
}
````

Each case string is top-level Python run after `helpers.py`, so it uses `config()`, `dt`, `json`, `re` and the helpers directly.
The vars unit writes the generator's files with the generator's own script, exactly as `modules/vm-tests/greptimedb-pipeline.nix:131-159` does, under a separate path.
Unverified until the case runs, each confirmed by the named case's first run on magnetite in Step 25:
- `[INFERENCE]` `DESC TABLE` answers the columns `Column, Type, Key, Null, Default, Semantic Type` with the type names `Int64`, `String`, `Boolean` and `TimestampMicrosecond` (`firstStart`).
- `[INFERENCE]` PostgreSQL 16 starts in the nspawn container and the `DynamicUser` collector reaches `/run/postgresql` by peer as `opentelemetry-collector` (`firstStart`, the `ci_*` tables filling).
- `[INFERENCE]` journald attributes each stub line to `gitea-mq.service` and gives it its own timestamp (`tableShape`, whose per-`msg` counts would differ otherwise).
- `[INFERENCE]` a timestamp column reads back over HTTP as integer microseconds, as `logs/s2/spike-dedup.md` showed for `finished_at` (`tableShape`).
- `[INFERENCE]` a specialisation's `activate` runs inside the container and relinks `/run/current-system` (`switch`, which prints its `limitation:` line on that path).

- [ ] **Step 8: Show the test failing at evaluation (RED)**

Run:

```bash
jj st --no-pager >/dev/null
nix eval --raw .#vmTests.x86_64-linux.devloop-ingest.drvPath 2>&1 | tee logs/s2-evidence/3.9-ingest-red-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E "error:.*(questions|batchEventKeys)"
```

Expected: an `error:` line naming the missing attribute `questions` (the container's `config.json` reads `devloop.questions` first).

- [ ] **Step 9: Write `modules/nixos/devloop-collection.nix`**

Replace the whole file with exactly the following.
Lines 1-11 and 16-281 are Task 2's 309-line file, unchanged (its lines 1-11 and 12-277); this task inserts four header lines after line 11, the bindings from `batchEventKeys` to `grantColumns` after `grantSql`, the names `questions` and `batchEventKeys` in `flake.lib.devloopCollection`, and in the NixOS module the arguments `pkgs`, the `let`, a second assertion after Task 2's PostgreSQL-major assertion, and everything after Task 2's two `services.greptimedb` lines.

```nix
# Dev-loop collection on magnetite (S2). One allow-list,
# flake.lib.otelCollectorSchema.devloop.tables (schema.nix, design D3),
# decides every stored column; this module renders from it the store's
# table statements and ingest pipelines (D5) and nixbot's export queries
# and column grants (D6, D10), and flake.modules.nixos.devloop-collection
# hands the statements and pipelines to greptimedb-schema
# (modules/nixos/greptimedb.nix). abandonMarker is the error nixbot's local
# patch writes for an abandoned attribute (D13); the attribute query derives
# `abandoned` from it. checks.x86_64-linux.devloop-queries binds the marker
# to the patch's production code and runs the queries and grants against
# the nixbot input's migrations (D14, D15 as amended by plan review F11).
# The NixOS module also creates the two readers' roles and their column
# grants, and the collector's four source receivers, each stamping its rows
# for the ingress role's `routing/logs` (D4, D6, D7, D9, D10);
# vmTests.x86_64-linux.devloop-ingest runs them against a real store (D16).
{ config, lib, ... }:
let
  inherit (config.flake.lib.otelCollectorSchema.devloop) tables;

  abandonMarker = "not finished when the required attributes had settled";

  # The PostgreSQL major nixbot runs on magnetite (16.15, read 2026-10-21 by
  # `nix eval --raw .#nixosConfigurations.magnetite.config.services.postgresql.package.version`).
  # checks.x86_64-linux.devloop-queries runs nixpkgs' postgresql_<major>, so it
  # reads no NixOS configuration, and the assertion below binds the constant
  # to the package of every host importing this module.
  postgresqlMajor = "16";

  # Every identifier is double-quoted: `status` is a reserved word in
  # GreptimeDB 1.2.1's parser (logs/s2/spike-dedup.md, DDL), and quoting all
  # of them removes the class.
  quote = name: ''"${name}"'';
  sqlLiteral = text: "'${lib.replaceStrings [ "'" ] [ "''" ] text}'";

  storeType = {
    int64 = "BIGINT";
    string = "STRING";
    boolean = "BOOLEAN";
    timestamp = "TIMESTAMP(6)";
  };

  # Pipeline transform types
  # (GreptimeTeam/greptimedb@v1.2.1:src/pipeline/src/etl/value.rs:58-100).
  transformType = {
    int64 = "int64";
    string = "string";
    boolean = "boolean";
    timestamp = "time, us";
  };

  # Columns taken from the OTLP record's Timestamp, nanoseconds since the
  # epoch (src/servers/src/otlp/logs.rs:153-156), rather than from a string
  # attribute: the journal's __REALTIME_TIMESTAMP (design D7).
  recordTimestamps = {
    batch_event = [ "ts" ];
  };

  ddl = lib.mapAttrs (
    name: table:
    lib.concatStringsSep "\n" (
      [ "CREATE TABLE IF NOT EXISTS ${quote name} (" ]
      ++ map (
        column:
        let
          notNull = lib.optionalString (!column.nullable) " NOT NULL";
        in
        "  ${quote column.name} ${storeType.${column.type}}${notNull},"
      ) table.columns
      ++ [
        "  TIME INDEX (${quote table.timeIndex}),"
        "  PRIMARY KEY (${lib.concatMapStringsSep ", " quote table.primaryKey})"
        ") ENGINE=mito WITH ('append_mode' = 'false', 'sst_format' = 'flat')"
      ]
    )
  ) tables;

  # One VRL assignment per allow-listed column, after the event is replaced
  # by an empty object: "" and an absent attribute become null before any
  # coercion, because to_int and to_bool turn null into 0 and false
  # (vectordotdev/vrl@v0.33.1:src/stdlib/to_int.rs:12,
  # src/stdlib/to_bool.rs:11). VRL takes no `if` as an object-literal
  # value, so the fields are assigned one by one.
  vrlAssignment =
    table: column:
    let
      attribute = "a.${column.name}";
      coerced =
        {
          int64 = "to_int!(${attribute})";
          boolean = "to_bool!(${attribute})";
          string = "string!(${attribute})";
          timestamp = "string!(${attribute})";
        }
        .${column.type};
    in
    if lib.elem column.name (recordTimestamps.${table} or [ ]) then
      ''.${column.name} = if t == 0 { null } else { from_unix_timestamp!(t, unit: "nanoseconds") }''
    else
      ''.${column.name} = if ${attribute} == null || ${attribute} == "" { null } else { ${coerced} }'';

  dateStep =
    fields: ignoreMissing:
    [
      "  - date:"
      "      fields:"
    ]
    ++ map (field: "        - ${field}") fields
    ++ [
      "      formats:"
      "        - \"%Y-%m-%dT%H:%M:%S%.fZ\""
      "        - \"%Y-%m-%dT%H:%M:%SZ\""
      "      timezone: UTC"
    ]
    ++ lib.optional ignoreMissing "      ignore_missing: true";

  pipelines = lib.mapAttrs (
    name: table:
    let
      fromAttributes = lib.filter (
        column: column.type == "timestamp" && !(lib.elem column.name (recordTimestamps.${name} or [ ]))
      ) table.columns;
      required = map (column: column.name) (lib.filter (column: !column.nullable) fromAttributes);
      optional = map (column: column.name) (lib.filter (column: column.nullable) fromAttributes);
      transformEntry =
        column:
        [
          "  - fields:"
          "      - ${column.name}"
          "    type: ${transformType.${column.type}}"
        ]
        ++ lib.optional (lib.elem column.name table.primaryKey) "    tag: true"
        ++ lib.optional (column.name == table.timeIndex) "    index: timestamp";
    in
    lib.concatStringsSep "\n" (
      [
        "version: 2"
        "processors:"
        "  - vrl:"
        "      source: |"
        "        a = object!(.LogAttributes)"
      ]
      # The record's Timestamp is read before the event is replaced.
      ++ lib.optional (recordTimestamps ? ${name}) "        t = int!(.Timestamp)"
      ++ [ "        . = {}" ]
      ++ map (column: "        ${vrlAssignment name column}") table.columns
      ++ [ "        ." ]
      ++ lib.optionals (required != [ ]) (dateStep required false)
      ++ lib.optionals (optional != [ ]) (dateStep optional true)
      ++ [ "transform:" ]
      ++ lib.concatMap transformEntry table.columns
    )
    + "\n"
  ) tables;

  # The nixbot side (design D6): the SQL expression behind each alias of the
  # two CI tables, over nixbot's schema at the pinned input.
  sources = {
    ci_attribute = {
      from = "build_attributes a JOIN builds b ON b.id = a.build_id JOIN projects p ON p.id = b.project_id";
      selects = {
        build_id = "b.id";
        attr = "a.attr";
        system = "a.system";
        status = "a.status";
        cached = "a.cached";
        abandoned = "(a.status = 'ignored_failure' AND a.error IS NOT DISTINCT FROM ${sqlLiteral abandonMarker})";
        drv_path = "a.drv_path";
        outputs_out = "a.outputs ->> 'out'";
        started_at = "a.started_at";
        finished_at = "a.finished_at";
        eval_wall_ms = "a.eval_wall_ms";
        eval_alloc_bytes = "a.eval_alloc_bytes";
        commit_sha = "b.commit_sha";
        branch = "b.branch";
        pr_number = "b.pr_number";
        project = "p.owner || '/' || p.name";
      };
    };
    ci_build = {
      from = "builds b";
      selects = {
        build_id = "b.id";
        created_at = "b.created_at";
        started_at = "b.started_at";
        finished_at = "b.finished_at";
        eval_duration_ms = "b.eval_duration_ms";
        status = "b.status";
        pr_number = "b.pr_number";
        branch = "b.branch";
      };
    };
  };

  # Every value is text with a null as '', and every timestamp the cursor's
  # text form, so neither the cursor nor the pipeline's input depends on how
  # the receiver's driver stringifies a column type.
  asText =
    column: expression:
    if column.type == "timestamp" then
      "coalesce(to_char(${expression} AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"'), '')"
    else
      "coalesce((${expression})::text, '')";

  queries = lib.mapAttrs (
    name: source:
    lib.concatStringsSep "\n" [
      "SELECT '' AS ${quote "body"},"
      (lib.concatMapStringsSep ",\n" (
        column: "  ${asText column source.selects.${column.name}} AS ${quote column.name}"
      ) tables.${name}.columns)
      "FROM ${source.from}"
      "WHERE ${source.selects.finished_at} >= least($1::timestamptz, now() - interval '5 minutes')"
      "ORDER BY ${source.selects.finished_at}"
      "LIMIT 10000"
    ]
  ) sources;

  # Column grants (design D10). build_attributes.error is granted to the
  # collector because `abandoned` reads it; the SELECT list, regulated by
  # devloop-queries, keeps it out of the store.
  grants = {
    opentelemetry-collector = {
      builds = [
        "id"
        "project_id"
        "commit_sha"
        "branch"
        "pr_number"
        "status"
        "created_at"
        "started_at"
        "finished_at"
        "eval_duration_ms"
      ];
      build_attributes = [
        "build_id"
        "attr"
        "system"
        "status"
        "cached"
        "error"
        "drv_path"
        "outputs"
        "started_at"
        "finished_at"
        "eval_wall_ms"
        "eval_alloc_bytes"
      ];
      projects = [
        "id"
        "owner"
        "name"
      ];
    };
    devloop-reconcile = {
      builds = [
        "id"
        "branch"
        "finished_at"
      ];
      build_attributes = [
        "build_id"
        "attr"
        "finished_at"
      ];
    };
  };

  grantSql =
    lib.concatStringsSep "\n" (
      lib.concatLists (
        lib.mapAttrsToList (
          role:
          lib.mapAttrsToList (
            table: columns:
            "GRANT SELECT (${lib.concatMapStringsSep ", " quote columns}) ON ${quote table} TO ${quote role};"
          )
        ) grants
      )
    )
    + "\n";

  # The keys gitea-mq's batch lines keep (design D7): batch_event's columns
  # other than its time index, which is the journal's timestamp.
  batchEventKeys = lib.filter (name: name != tables.batch_event.timeIndex) (
    map (column: column.name) tables.batch_event.columns
  );

  # The three questions devloop answers for the past week (design D8), run in
  # devloop-ingest's documentedQueries case and at acceptance. GreptimeDB
  # 1.2.1 plans SQL with DataFusion 53.1.0 (GreptimeTeam/greptimedb@v1.2.1:
  # Cargo.toml:131, patched at :349 to GreptimeTeam/datafusion@bb531e75);
  # percentile_cont is the exact, interpolating percentile
  # (datafusion/functions-aggregate/src/percentile_cont.rs:92-116 there).
  # A timestamp cast to BIGINT is its microseconds.
  questions = {
    # Seconds from `batch formed` to `batch done` per batch; a bisected
    # batch's repeated `batch landed` rows are not the endpoint.
    formationToLand = ''
      SELECT f."batch" AS "batch",
             CAST(CAST(d."ts" AS BIGINT) - CAST(f."ts" AS BIGINT) AS DOUBLE) / 1000000.0 AS "formation_to_land_s"
      FROM "batch_event" AS f
      JOIN "batch_event" AS d ON d."batch" = f."batch"
      WHERE f."msg" = 'batch formed'
        AND d."msg" = 'batch done'
        AND d."ts" >= now() - INTERVAL '7 days'
      ORDER BY f."batch"
    '';
    # The CI queue wait of pull-request builds, in seconds, over each
    # build's first attempt: nixbot's restart resets started_at and
    # finished_at and keeps created_at (Mic92/nixbot@d020013fa:
    # nixbot/nixbot/db_gen/maintenance.py:96-123), so a rerun is a second row
    # of the build, the one with the later finished_at, whose wait is inflated.
    queueWait = ''
      SELECT percentile_cont(CAST(CAST(c."started_at" AS BIGINT) - CAST(c."created_at" AS BIGINT) AS DOUBLE) / 1000000.0, 0.5) AS "p50_s",
             percentile_cont(CAST(CAST(c."started_at" AS BIGINT) - CAST(c."created_at" AS BIGINT) AS DOUBLE) / 1000000.0, 0.9) AS "p90_s",
             percentile_cont(CAST(CAST(c."started_at" AS BIGINT) - CAST(c."created_at" AS BIGINT) AS DOUBLE) / 1000000.0, 0.99) AS "p99_s",
             count(*) AS "builds"
      FROM "ci_build" AS c
      JOIN (SELECT "build_id", min("finished_at") AS "first_finished" FROM "ci_build" GROUP BY "build_id") AS f
        ON c."build_id" = f."build_id" AND c."finished_at" = f."first_finished"
      WHERE c."pr_number" IS NOT NULL
        AND c."started_at" IS NOT NULL
        AND c."created_at" IS NOT NULL
        AND c."finished_at" >= now() - INTERVAL '7 days'
    '';

    # Per build, `failed` when any row that is neither abandoned nor of a
    # flaky drv_path is an own failure or dependency_failed; a drv_path is
    # flaky when it has a pass row and an own-fail row in the window.
    # A build with no outcome row (only cancelled, pending, building or
    # abandoned rows) is left out (plan review F21).
    # Limitation: a dependency_failed row cannot be attributed to the flaky
    # derivation under it, because nixbot names it only in error text.
    buildOutcome = ''
      WITH "attempt" AS (
        SELECT "build_id", "drv_path", "status",
               "status" IN ('succeeded', 'skipped_local') AS "pass",
               ("status" IN ('failed', 'failed_eval') OR ("status" = 'ignored_failure' AND "abandoned" = false)) AS "own_fail"
        FROM "ci_attribute"
        WHERE "finished_at" >= now() - INTERVAL '7 days'
      ),
      "flaky_drv" AS (
        SELECT "drv_path"
        FROM "attempt"
        WHERE "drv_path" IS NOT NULL
        GROUP BY "drv_path"
        HAVING max(CASE WHEN "pass" THEN 1 ELSE 0 END) = 1
           AND max(CASE WHEN "own_fail" THEN 1 ELSE 0 END) = 1
      )
      SELECT a."build_id" AS "build_id",
             CASE WHEN max(CASE WHEN (a."own_fail" OR a."status" = 'dependency_failed') AND f."drv_path" IS NULL THEN 1 ELSE 0 END) = 1
                  THEN 'failed' ELSE 'passed' END AS "outcome"
      FROM "attempt" AS a
      LEFT JOIN "flaky_drv" AS f ON f."drv_path" = a."drv_path"
      GROUP BY a."build_id"
      HAVING max(CASE WHEN a."pass" OR a."own_fail" OR a."status" = 'dependency_failed' THEN 1 ELSE 0 END) = 1
      ORDER BY a."build_id"
    '';
  };

  # The receiver that feeds each table (design D6, D7, D9).
  sourceReceivers = {
    ci_attribute = "sqlquery/ci_attribute";
    ci_build = "sqlquery/ci_build";
    batch_event = "journald/gitea-mq";
    deploy_record = "file_log/deploy-record";
  };

  # The file flake.modules.nixos.deploy-record appends to (design D9).
  deployRecordFile = "/var/log/deploy-record.jsonl";

  # The keep-list and the body removal are defence in depth: the
  # pre-created tables and each pipeline's VRL reset decide the stored
  # columns, and no test can see either operator fail (plan review F15).
  keepAttributes = names: {
    type = "retain";
    id = "keep-list";
    fields = map (name: "attributes.${name}") names;
  };
  dropBody = {
    type = "remove";
    id = "drop-body";
    field = "body";
  };

  # Each column becomes an attribute only through attribute_columns
  # (open-telemetry/opentelemetry-collector-contrib@aaf5045a2:
  # receiver/sqlqueryreceiver/logs_receiver.go:364-382); the body is the
  # constant '' the query selects. The receiver stores the last row's
  # finished_at as its cursor while it builds the batch, before the batch is
  # consumed (logs_receiver.go:200-211, :337-346), so rows the pipeline
  # refuses are lost unless the five-minute overlap re-reads them; C1 and C2
  # report the gap and a cursor reset replays it. The cursor's storage key
  # embeds the SQL text (logs_receiver.go:123, :276), so any later edit of a
  # query restarts it from tracking_start_value and re-reads nixbot's
  # retained history, about 200,000 attribute rows, once.
  sqlqueryReceiver = table: {
    driver = "postgres";
    datasource = "host=/run/postgresql dbname=nixbot user=opentelemetry-collector sslmode=disable";
    collection_interval = "60s";
    storage = "file_storage";
    queries = [
      {
        sql = queries.${table};
        tracking_column = "finished_at";
        tracking_start_value = "1970-01-01T00:00:00.000000Z";
        logs = [
          {
            body_column = "body";
            attribute_columns = map (column: column.name) tables.${table}.columns;
          }
        ];
      }
    ];
  };

  # `<table>.<column>` for every granted column of both roles, sorted bytewise.
  grantColumns = lib.sort lib.lessThan (
    lib.unique (
      lib.concatMap (
        roleGrants:
        lib.concatLists (lib.mapAttrsToList (table: map (column: "${table}.${column}")) roleGrants)
      ) (lib.attrValues grants)
    )
  );
in
{
  flake.lib.devloopCollection = {
    inherit
      abandonMarker
      postgresqlMajor
      ddl
      pipelines
      queries
      grants
      grantSql
      ;
    selects = lib.mapAttrs (_: source: source.selects) sources;
    inherit questions batchEventKeys;
  };

  flake.modules.nixos.devloop-collection =
    { config, pkgs, ... }:
    let
      hostName = config.networking.hostName;
      collectorGroups = lib.toList (
        config.systemd.services.opentelemetry-collector.serviceConfig.SupplementaryGroups or [ ]
      );
    in
    {
      assertions = [
        {
          assertion =
            !config.services.postgresql.enable
            || lib.versions.major config.services.postgresql.package.version == postgresqlMajor;
          message = "devloop-collection: services.postgresql.package is PostgreSQL ${config.services.postgresql.package.version}, but flake.lib.devloopCollection.postgresqlMajor is ${postgresqlMajor}, the major checks.x86_64-linux.devloop-queries runs nixbot's migrations and the export queries on (design D14).";
        }
        # journald/gitea-mq runs journalctl as the collector's DynamicUser, which
        # reads the system journal only through this group, set by nixpkgs'
        # collector module (design D11; logs/s2/grounding.md §4.2).
        {
          assertion = lib.elem "systemd-journal" collectorGroups;
          message = "devloop-collection: journald/gitea-mq reads gitea-mq.service's journal, so opentelemetry-collector.service must keep SupplementaryGroups systemd-journal, which nixpkgs' collector module sets (design D11); it has ${builtins.toJSON collectorGroups}.";
        }
      ];
      services.greptimedb.tables.devloop = lib.attrValues ddl;
      services.greptimedb.pipelines.devloop = lib.mapAttrs' (
        name: pipeline: lib.nameValuePair "devloop_${name}" pipeline
      ) pipelines;

      # Login roles without a password, admitted by the local peer rule
      # because each is named after its reader's DynamicUser (design D10).
      services.postgresql.ensureUsers = map (name: { inherit name; }) (lib.attrNames grants);

      # nixbot.service is not a notify unit, so its migrations may still be
      # running when it counts as started: wait up to 300 s for every granted
      # column, then grant, once per boot or activation. A grant that a later
      # nixbot migration drops with its column is not repaired here; the
      # collector's query errors and devloop-reconcile's C1 and C2 report it.
      # Nothing is created in nixbot's database but the grants (design D10).
      systemd.services.devloop-pg-grants = {
        description = "Column grants on nixbot's tables for the dev-loop readers";
        after = [
          "postgresql.service"
          "postgresql-setup.service"
          "nixbot.service"
        ];
        wantedBy = [ "multi-user.target" ];
        path = [ config.services.postgresql.package ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "postgres";
          Group = "postgres";
        };
        script = ''
          expected=${lib.escapeShellArg (lib.concatStringsSep "\n" grantColumns)}
          deadline=$((SECONDS + 300))
          while :; do
            present=$(psql -XAtq -d nixbot -c "SELECT table_name || '.' || column_name FROM information_schema.columns WHERE table_schema = 'public'" 2>/dev/null | LC_ALL=C sort -u || true)
            missing=$(LC_ALL=C comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$present"))
            if [ -z "$missing" ]; then
              break
            fi
            if [ "$SECONDS" -ge "$deadline" ]; then
              echo "devloop-pg-grants: after 300 s nixbot still lacks:" $missing >&2
              exit 1
            fi
            sleep 5
          done
          psql -XAtq -d nixbot -v ON_ERROR_STOP=1 -f ${pkgs.writeText "devloop-pg-grants.sql" grantSql}
        '';
      };

      services.opentelemetry-collector.settings = {
        receivers = {
          "sqlquery/ci_attribute" = sqlqueryReceiver "ci_attribute";
          "sqlquery/ci_build" = sqlqueryReceiver "ci_build";
          # The unit, not the identifier, which is the wrapper gitea-mq-start
          # (logs/s2/grounding.md §2.1); the closing quote makes each of the
          # five messages an exact match (design D7). The receiver stores its
          # journal cursor before it hands a line on
          # (open-telemetry/opentelemetry-collector-contrib@aaf5045a2:
          # pkg/stanza/operator/input/journald/input.go:181-191), so a line
          # the pipeline refuses would be lost; retry_on_failure with no
          # elapsed limit holds the reader until memory_limiter accepts it
          # (receiver/journaldreceiver/README.md:52-55).
          "journald/gitea-mq" = {
            units = [ "gitea-mq.service" ];
            grep = ''msg="batch (formed|built|landed|bisecting|done)"'';
            start_at = "beginning";
            storage = "file_storage";
            retry_on_failure = {
              enabled = true;
              max_elapsed_time = "0s";
            };
            operators = [
              {
                type = "key_value_parser";
                id = "parse-message";
                parse_from = "body.MESSAGE";
              }
              (keepAttributes batchEventKeys)
              dropBody
            ];
          };
          "file_log/deploy-record" = {
            include = [ deployRecordFile ];
            start_at = "beginning";
            storage = "file_storage";
            operators = [
              {
                type = "json_parser";
                id = "parse-line";
              }
              (keepAttributes (map (column: column.name) tables.deploy_record.columns))
              dropBody
            ];
          };
        };

        # Stamps for the ingress role's routing/logs (design D4).
        processors = lib.mapAttrs' (
          table: _:
          lib.nameValuePair "resource/devloop-${table}" {
            attributes = [
              {
                key = "vanixiets.database";
                value = "devloop";
                action = "upsert";
              }
              {
                key = "vanixiets.table";
                value = table;
                action = "upsert";
              }
              {
                key = "host.name";
                value = hostName;
                action = "upsert";
              }
            ];
          }
        ) sourceReceivers;

        # Each source ends in the agent role's forward connector, which
        # logs/ingress receives from on a host holding both roles.
        service.pipelines = lib.mapAttrs' (
          table: receiver:
          lib.nameValuePair "logs/devloop-${table}" {
            receivers = [ receiver ];
            processors = [
              "memory_limiter"
              "resource/devloop-${table}"
            ];
            exporters = [ "forward" ];
          }
        ) sourceReceivers;
      };
    };
}
```

The queries' `$1` is written once: confmap expands only `${…}` and turns `$$` into `$` (Step 2), so the driver receives `$1`.
`grantColumns` and the script's `present` are both sorted bytewise (`lib.lessThan` and `LC_ALL=C sort`), which `comm` requires.
`devloop-pg-grants` is ordered after `postgresql-setup.service`, which creates the two roles (`postgresql.nix:870-921`); on magnetite nixbot is ordered after `postgresql.target`, which requires that unit, so the extra entry changes no order there and makes the roles' existence explicit.
`[INFERENCE]` The three questions parse and plan on GreptimeDB 1.2.1, in particular `CAST(<timestamp> AS BIGINT)`, the two-argument `percentile_cont` and `queueWait`'s join of `ci_build` with its first-attempt subquery; Step 25's `documentedQueries` case confirms both against fixture answers.

- [ ] **Step 10: Add the logs routes to the ingress role**

In `modules/clan/services/otel-collector/flake-module.nix`, replace lines 1-10 (the header comment's first paragraph) with exactly:

```nix
# Fleet metrics collection as one clan service (ADR-003; design D8 to D10),
# and the logs path of S2's dev-loop tables (S2 design D4).
#
# Both roles' NixOS fragments merge into one services.opentelemetry-collector,
# because the NixOS module runs one collector per host. On magnetite, which
# holds both roles, the agent pipelines export to an in-process `forward`
# connector that the ingress pipelines receive from. The ingress converts
# exponential histograms while the store is below 1.3.0 (ADR-001 R1.2), routes
# metrics on the `vanixiets.database` resource attribute and logs on it and
# `vanixiets.table`, and writes each database, and each devloop table, through
# its own otlp_http exporter with a persistent queue, authenticating as the
# store's write-only `collector` user.
```

Replace lines 33-42 (`mib` and `queueBytes`) with exactly:

```nix
  mib = n: n * 1024 * 1024;

  # Persistent queue per exporter: at least 24 h of fleet and under 512 MiB
  # in total (ADR-003 envelope), asserted by
  # checks.x86_64-linux.otel-collector-config. devloop's 48 MiB is split
  # between its metrics and its four tables, ci_attribute holding about a
  # day of store outage on the busiest day (S2 design D4).
  queueBytes = {
    fleet = mib 400;
    devloop = mib 4;
    agent = mib 48;
    devloop_ci_attribute = mib 32;
    devloop_ci_build = mib 4;
    devloop_batch_event = mib 4;
    devloop_deploy_record = mib 4;
  };
```

Replace lines 332-453 (the whole `flake.modules.nixos.otel-collector-ingress` definition) with exactly:

```nix
  flake.modules.nixos.otel-collector-ingress =
    { config, lib, ... }:
    let
      databaseNames = lib.attrNames schema.databases;
      storeDatabaseNames = lib.attrNames config.services.greptimedb.databases;
      devloopTables = lib.attrNames schema.devloop.tables;
      # The logs routes write through the store's devloop_<table> pipelines,
      # so they exist where the store declares those pipelines
      # (flake.modules.nixos.devloop-collection); without a logs pipeline
      # exporting to `forward`, `logs/ingress` would fail validation.
      devloopLogs = (config.services.greptimedb.pipelines.devloop or { }) != { };
      storeExporter = headers: queueSize: {
        endpoint = "http://127.0.0.1:4000/v1/otlp";
        inherit headers;
        auth.authenticator = "basicauth/store";
        sending_queue = {
          storage = "file_storage";
          sizer = "bytes";
          queue_size = queueSize;
        };
        # A persistent queue drops an item whose retries run out, so
        # retries never stop while the store is down.
        retry_on_failure = {
          enabled = true;
          max_interval = "60s";
          max_elapsed_time = "0s";
        };
      };
    in
    {
      imports = [ collectorCore ];

      # The exporters write only to schema.nix's databases, and the store
      # answers 400 for any database its schema job did not create.
      assertions = lib.optional (config.services.greptimedb.enable or false) {
        assertion = storeDatabaseNames == databaseNames;
        message = "otel-collector ingress: services.greptimedb.databases creates ${builtins.toJSON storeDatabaseNames}, but flake.lib.otelCollectorSchema.databases routes to ${builtins.toJSON databaseNames}";
      };

      services.opentelemetry-collector = lib.mkMerge [
        {
          settings = {
            extensions = {
              file_storage = {
                directory = "${stateDir}/queue";
                create_directory = true;
              };
              "basicauth/store".client_auth = {
                username = "collector";
                password_file = "${credentialsDir}/collector-password";
              };
            };

            processors = {
              # The store accepts explicit-bucket histograms only below 1.3.0
              # (ADR-001 R1.2); the bounds are Prometheus' default buckets.
              "transform/exphist".metric_statements = [
                "convert_exponential_histogram_to_histogram(\"upper\", [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]) where metric.type == METRIC_DATA_TYPE_EXPONENTIAL_HISTOGRAM"
              ];
              "resource/strip-database".attributes = [
                {
                  key = "vanixiets.database";
                  action = "delete";
                }
                {
                  key = "vanixiets.table";
                  action = "delete";
                }
              ];
            };

            connectors.routing.table = map (db: {
              context = "resource";
              condition = ''attributes["vanixiets.database"] == "${db}"'';
              pipelines = [ "metrics/${db}" ];
            }) databaseNames;

            exporters = lib.listToAttrs (
              map (
                db:
                lib.nameValuePair "otlp_http/${db}" (
                  storeExporter {
                    "x-greptime-db-name" = db;
                    "x-greptime-otlp-metric-promote-resource-attrs" =
                      lib.concatStringsSep ";" schema.promotedResourceAttributes;
                  } queueBytes.${db}
                )
              ) databaseNames
            );

            service = {
              extensions = [
                "file_storage"
                "basicauth/store"
              ];
              pipelines = {
                "metrics/ingress" = {
                  receivers = [ "forward" ];
                  processors = [
                    "memory_limiter"
                    "transform/exphist"
                  ];
                  exporters = [ "routing" ];
                };
              }
              // lib.listToAttrs (
                map (
                  db:
                  lib.nameValuePair "metrics/${db}" {
                    receivers = [ "routing" ];
                    processors = [ "resource/strip-database" ];
                    exporters = [ "otlp_http/${db}" ];
                  }
                ) databaseNames
              );
            };
          };
        }

        # A second routing instance carries logs: one instance's logs router
        # resolves every route as a logs pipeline
        # (open-telemetry/opentelemetry-collector-contrib@aaf5045a2:
        # connector/routingconnector/router.go:161-260). One exporter per
        # table, because an exporter carries one table and one pipeline
        # header; auto_create_table=false turns a write that races the schema
        # job into a 400 instead of an append-mode table (S2 design D4, D5).
        (lib.mkIf devloopLogs {
          settings = {
            connectors."routing/logs".table = map (table: {
              context = "resource";
              condition = ''attributes["vanixiets.database"] == "devloop" and attributes["vanixiets.table"] == "${table}"'';
              pipelines = [ "logs/devloop-${table}-out" ];
            }) devloopTables;

            exporters = lib.listToAttrs (
              map (
                table:
                lib.nameValuePair "otlp_http/devloop_${table}" (
                  storeExporter {
                    "x-greptime-db-name" = "devloop";
                    "x-greptime-log-table-name" = table;
                    "x-greptime-pipeline-name" = "devloop_${table}";
                    "x-greptime-hints" = "auto_create_table=false";
                  } queueBytes."devloop_${table}"
                )
              ) devloopTables
            );

            service.pipelines = {
              "logs/ingress" = {
                receivers = [ "forward" ];
                processors = [ "memory_limiter" ];
                exporters = [ "routing/logs" ];
              };
            }
            // lib.listToAttrs (
              map (
                table:
                lib.nameValuePair "logs/devloop-${table}-out" {
                  receivers = [ "routing/logs" ];
                  processors = [ "resource/strip-database" ];
                  exporters = [ "otlp_http/devloop_${table}" ];
                }
              ) devloopTables
            );
          };
        })
      ];

      systemd.services.opentelemetry-collector = lib.mkMerge [
        {
          # Killed after the evaluator (900) and the store (500), so it survives
          # the store's death and queues (A7:100,127).
          serviceConfig = {
            MemoryMax = "512M";
            OOMScoreAdjust = 300;
          };
        }
        # The store answers 400 for a missing database or table and the
        # exporter drops 400s as permanent, so export waits for the schema job.
        (lib.mkIf (config.services.greptimedb.enable or false) {
          after = [ "greptimedb-schema.service" ];
          wants = [ "greptimedb-schema.service" ];
        })
      ];
    };
```

`queueBytes."devloop_${table}"` fails evaluation for a table added to the allow-list without a queue size, so a new table cannot ship unsized.
The metrics exporters render exactly as before; `storeExporter` only shares their fields with the logs exporters.

In `modules/machines/nixos/magnetite/default.nix`, in the list `services.observability-notify.units` (lines 329-343 on `main@origin` before this slice; Tasks 1 and 2 each add one import line above it, so it starts at line 331), insert one line before `"fleet-alert"`, keeping the list sorted:

```nix
        "devloop-pg-grants"
```

so that the list begins exactly:

```nix
      services.observability-notify.units = [
        "devloop-pg-grants"
        "fleet-alert"
        "greptimedb"
```

A grant oneshot that times out then posts `FAILED devloop-pg-grants.service on magnetite`, the early sign of schema drift design D10 relies on.
R3.1's existing wiring clauses (`modules/checks/otel-collector-config.nix:340-346`: every listed name is a unit with an `ExecStart`, wired to the notifier, with the start-time `RESOLVED` hook) judge the new entry from this task on; the policy clause that requires every `devloop-*` unit to be listed (`notifiedByPolicy`, `:35-40`, `:335-337`) covers it only once Task 4 extends the policy to `devloop-`, so until then removing the entry fails no check.

- [ ] **Step 11: Read back the roles and the grants unit (GREEN, evaluation; tasks.md 3.1)**

Run:

```bash
jj st --no-pager >/dev/null
{
  nix eval --json .#nixosConfigurations.magnetite.config.services.postgresql.ensureUsers --apply 'us: map (u: { inherit (u) name ensureDBOwnership ensureClauses; }) (builtins.filter (u: u.name == "opentelemetry-collector" || u.name == "devloop-reconcile") us)'
  nix eval --json .#nixosConfigurations.magnetite.config.systemd.services.devloop-pg-grants --apply 's: { inherit (s) after partOf wantedBy; serviceConfig = { inherit (s.serviceConfig) Type RemainAfterExit User; }; }'
  nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.devloop-pg-grants.script | grep -cE 'information_schema.columns|SECONDS \+ 300|ON_ERROR_STOP=1 -f /nix/store/[a-z0-9]{32}-devloop-pg-grants.sql'
  nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.devloop-pg-grants.script | grep -ciE 'create (unique )?(index|view|function|trigger|table)' || true
  nix eval --raw .#.lib.devloopCollection.grantSql
  nix eval --json .#nixosConfigurations.magnetite.config.services.observability-notify.units --apply 'us: builtins.elem "devloop-pg-grants" us'
  nix eval --json .#nixosConfigurations.magnetite.config.systemd.services.devloop-pg-grants.unitConfig.OnFailure
  nix eval --json .#nixosConfigurations.magnetite.config.systemd.services.devloop-pg-grants.serviceConfig.ExecStartPost | grep -c 'observability-notify-resolved start %n'
} 2>&1 | tee logs/s2-evidence/3.1-roles-grants-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected:
- `[{"ensureClauses":{},"ensureDBOwnership":false,"name":"devloop-reconcile"},{"ensureClauses":{},"ensureDBOwnership":false,"name":"opentelemetry-collector"}]`;
- `{"after":["postgresql.service","postgresql-setup.service","nixbot.service"],"partOf":[],"serviceConfig":{"RemainAfterExit":true,"Type":"oneshot","User":"postgres"},"wantedBy":["multi-user.target"]}`;
- `3`, then `0`;
- the five `GRANT SELECT (…) ON "<table>" TO "<role>";` lines of `grantSql`, the collector's on `"build_attributes"`, `"builds"` and `"projects"`, and `devloop-reconcile`'s `GRANT SELECT ("build_id", "attr", "finished_at") ON "build_attributes" TO "devloop-reconcile";` and `GRANT SELECT ("id", "branch", "finished_at") ON "builds" TO "devloop-reconcile";`, which the script applies from the `devloop-pg-grants.sql` store file the third command counted;
- `true`, then `["observability-notify@%n.service"]`, then `1`: `devloop-pg-grants` is a notified unit, and the agent role's wiring gave it `OnFailure` and the notifier's start hook.
The delivered unit on magnetite is observed by 7.4 after D3.

- [ ] **Step 12: Read back the nixbot receivers (GREEN, evaluation; tasks.md 3.2)**

Run:

```bash
{
  nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.receivers --apply 'r: builtins.mapAttrs (n: v: v // { queries = map (q: removeAttrs q [ "sql" ]) v.queries; }) { inherit (r) "sqlquery/ci_attribute" "sqlquery/ci_build"; }' | jq .
  for t in ci_attribute ci_build; do
    diff <(nix eval --raw .#.lib.devloopCollection.queries.$t) <(nix eval --raw .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.receivers --apply "r: (builtins.head r.\"sqlquery/$t\".queries).sql") && echo "$t-query-equal"
  done
} 2>&1 | tee logs/s2-evidence/3.2-sqlquery-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: each receiver shows `driver: "postgres"`, `datasource: "host=/run/postgresql dbname=nixbot user=opentelemetry-collector sslmode=disable"`, `collection_interval: "60s"`, `storage: "file_storage"`, and one query with `tracking_column: "finished_at"`, `tracking_start_value: "1970-01-01T00:00:00.000000Z"` and `logs: [{ body_column: "body", attribute_columns: [<the table's allow-list columns in order>] }]`; then `ci_attribute-query-equal` and `ci_build-query-equal`.

- [ ] **Step 13: Read back the gitea-mq receiver (GREEN, evaluation; tasks.md 3.3)**

Run:

```bash
{
  nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.receivers --apply 'r: r."journald/gitea-mq"' | jq .
  diff <(nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.receivers --apply 'r: map (f: builtins.substring 11 99 f) (builtins.elemAt r."journald/gitea-mq".operators 1).fields' | jq -c .) \
       <(nix eval --json .#.lib.otelCollectorSchema.devloop.tables.batch_event --apply 't: builtins.filter (n: n != t.timeIndex) (map (c: c.name) t.columns)' | jq -c .) && echo keep-list-equal
} 2>&1 | tee logs/s2-evidence/3.3-journald-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `units: ["gitea-mq.service"]`, `grep: "msg=\"batch (formed|built|landed|bisecting|done)\""`, `start_at: "beginning"`, `storage: "file_storage"`, `retry_on_failure: { enabled: true, max_elapsed_time: "0s" }`, operators in order `{ type: "key_value_parser", id: "parse-message", parse_from: "body.MESSAGE" }`, `{ type: "retain", id: "keep-list", fields: ["attributes.batch", …, "attributes.flaky"] }`, `{ type: "remove", id: "drop-body", field: "body" }`; then `keep-list-equal` (the receiver's keep-list against the allow-list read directly from `schema.nix`, the second value).

- [ ] **Step 14: Read back the deploy-record receiver (GREEN, evaluation; tasks.md 3.4)**

Run:

```bash
nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.receivers --apply 'r: r."file_log/deploy-record"' 2>&1 | jq . | tee logs/s2-evidence/3.4-file-log-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `include: ["/var/log/deploy-record.jsonl"]`, `start_at: "beginning"`, `storage: "file_storage"`, operators `json_parser` (`id: "parse-line"`), `retain` (`id: "keep-list"`, `fields: ["attributes.host", "attributes.closure", "attributes.previous_closure", "attributes.ts"]`) and `remove` (`id: "drop-body"`, `field: "body"`).

- [ ] **Step 15: Read back the routes, pipelines, exporters and queues (GREEN, evaluation; tasks.md 3.5)**

Run:

```bash
{
  nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings --apply 's: { routes = s.connectors."routing/logs".table; strip = s.processors."resource/strip-database".attributes; stamps = builtins.listToAttrs (map (n: { name = n; value = s.processors.${n}.attributes; }) (builtins.filter (n: builtins.substring 0 17 n == "resource/devloop-") (builtins.attrNames s.processors))); pipelines = builtins.listToAttrs (map (n: { name = n; value = s.service.pipelines.${n}; }) (builtins.filter (n: builtins.substring 0 5 n == "logs/") (builtins.attrNames s.service.pipelines))); exporters = builtins.mapAttrs (n: e: { inherit (e) endpoint headers; queue = e.sending_queue; retry = e.retry_on_failure.max_elapsed_time; }) s.exporters; }' > /tmp/3.5-collector.json
  jq . /tmp/3.5-collector.json
  jq '[.exporters[].queue.queue_size] | add' /tmp/3.5-collector.json
} 2>&1 | tee logs/s2-evidence/3.5-routes-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected:
- `routes`: four items, `context: "resource"`, `condition: "attributes[\"vanixiets.database\"] == \"devloop\" and attributes[\"vanixiets.table\"] == \"<table>\""`, `pipelines: ["logs/devloop-<table>-out"]` for `batch_event`, `ci_attribute`, `ci_build`, `deploy_record`;
- `strip`: deletes of `vanixiets.database` and `vanixiets.table`;
- `stamps`: four `resource/devloop-<table>` processors upserting `vanixiets.database = devloop`, `vanixiets.table = <table>` and `host.name = magnetite`;
- `pipelines`: `logs/devloop-<table>` (receiver → `memory_limiter`, `resource/devloop-<table>` → `forward`), `logs/ingress` (`forward` → `memory_limiter` → `routing/logs`) and `logs/devloop-<table>-out` (`routing/logs` → `resource/strip-database` → `otlp_http/devloop_<table>`), nine in all;
- `exporters`: `otlp_http/devloop_<table>` with `endpoint: "http://127.0.0.1:4000/v1/otlp"`, headers `x-greptime-db-name: devloop`, `x-greptime-log-table-name: <table>`, `x-greptime-pipeline-name: devloop_<table>`, `x-greptime-hints: auto_create_table=false`, queue `file_storage`, `bytes`, sizes 33554432 for `ci_attribute` and 4194304 for the other three, `retry: "0s"`; `otlp_http/devloop` at 4194304, `otlp_http/fleet` at 419430400, `otlp_http/agent` at 50331648;
- the sum `520093696` (496 MiB).
Step 21's `nixos-magnetite` build runs `otelcol-contrib validate` over the rendered file.

- [ ] **Step 16: Show the journal assertion failing under the override (GREEN, evaluation; tasks.md 3.7)**

Run Step 4's command again, logging to `logs/s2-evidence/3.7-journal-assertion-$(date -u +%Y%m%dT%H%M%SZ).log`.
Expected: `=== control` followed by nothing; `=== journalGroupCleared` followed by exactly `devloop-collection: journald/gitea-mq reads gitea-mq.service's journal, so opentelemetry-collector.service must keep SupplementaryGroups systemd-journal, which nixpkgs' collector module sets (design D11); it has [].`
If `extendModules` is missing on the clan-built configuration, stop and report, as S3 Task 4 Step 21 does.

- [ ] **Step 17: Show R3.1's content clause failing on the logs pipelines (RED, build)**

Run:

```bash
nix build --no-link .#checks.x86_64-linux.otel-collector-config 2>&1 | tee logs/s2-evidence/3.6-r31-red-content-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E 'otel-collector-config (failures|accepted)'
```

Expected: `otel-collector-config failures: ["R3.1: a logs or traces pipeline"]`: the S1 clause at `modules/checks/otel-collector-config.nix:297-300` requires every pipeline to start with `metrics/`.

- [ ] **Step 18: Add the four mutants with a traces-only content clause (RED, build)**

Each new clause names its two independently defined values before its mutant:
- Queue clause: the exporter names derived from `schema.nix`'s databases and `devloop.tables`, against the evaluated exporters' `sending_queue`, which `flake-module.nix` renders from `queueBytes`; mutant `logsQueueNotPersistent`, `otlp_http/devloop_ci_build` without `storage`.
- Content clause: the evaluated pipelines' exporter lists against the exporter names derived from `schema.nix`'s `devloop.tables` and the evaluated exporters' `x-greptime-db-name` headers; mutants `logsToFleet`, `logs/devloop-ci_build-out` exporting to `otlp_http/fleet`, and `logsToMetricsExporter`, the same pipeline exporting to the metrics exporter `otlp_http/devloop`, whose database header is `devloop` but which carries no table or pipeline header.
- `logsTakeLocalReceiver`: the evaluated `logs/*` pipelines' receiver lists against the OTLP receiver's component type `otlp`, which the vendor registers (`open-telemetry/opentelemetry-collector@v0.155.0:receiver/otlpreceiver/internal/metadata/generated_status.go:12`) and no line of ours sets; mutant `otlpInLogsPipeline`, an `otlp` receiver on loopback added to `logs/devloop-ci_build`.

In `modules/checks/otel-collector-config.nix`, replace lines 297-300 with exactly:

```nix
          # Content: no traces pipeline (S7 adds journald logs behind
          # ADR-008's stages).
          (check "R3.1: a traces pipeline, or a logs pipeline exporting outside devloop" (
            lib.all (name: !(lib.hasPrefix "traces" name)) (builtins.attrNames pipelines)
          ))
```

After line 434 (`queueOver512MiB = …;`), insert exactly:

```nix
        # S2 design D4: a logs exporter without the persistent queue.
        logsQueueNotPersistent =
          i:
          i
          // {
            settings = i.settings // {
              exporters = i.settings.exporters // {
                "otlp_http/devloop_ci_build" = i.settings.exporters."otlp_http/devloop_ci_build" // {
                  sending_queue =
                    builtins.removeAttrs i.settings.exporters."otlp_http/devloop_ci_build".sending_queue
                      [ "storage" ];
                };
              };
            };
          };
        # A devloop logs route writing into fleet.
        logsToFleet = onSettings {
          service.pipelines."logs/devloop-ci_build-out".exporters = [ "otlp_http/fleet" ];
        };
        # A devloop logs route bypassing the table's pipeline through the
        # metrics exporter, whose only header is the database (plan review F3).
        logsToMetricsExporter = onSettings {
          service.pipelines."logs/devloop-ci_build-out".exporters = [ "otlp_http/devloop" ];
        };
        # ADR-003:81: the local OTLP receiver feeding a logs pipeline.
        otlpInLogsPipeline =
          i:
          onSettings {
            receivers.otlp.protocols.http.endpoint = "127.0.0.1:4318";
            service.pipelines."logs/devloop-ci_build".receivers =
              i.settings.service.pipelines."logs/devloop-ci_build".receivers ++ [ "otlp" ];
          } i;
```

Run:

```bash
nix build --no-link .#checks.x86_64-linux.otel-collector-config 2>&1 | tee logs/s2-evidence/3.6-r31-red-mutants-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E 'otel-collector-config (failures|accepted)'
```

Expected: `otel-collector-config accepted a mutant: ["logsQueueNotPersistent","logsToFleet","logsToMetricsExporter","otlpInLogsPipeline"]`: the queue clause still reads only the three database exporters, the content clause reads no exporter, and no clause reads a logs pipeline's receivers.

- [ ] **Step 19: Add the clauses that reject them (GREEN, build; tasks.md 3.6)**

Replace lines 211-212 (`dbs` and `exporterNames`) with exactly:

```nix
          dbs = lib.attrNames i.schema.databases;
          devloopTables = lib.attrNames i.schema.devloop.tables;
          exporterNames =
            map (db: "otlp_http/${db}") dbs ++ map (table: "otlp_http/devloop_${table}") devloopTables;
          logsPipelineNames = builtins.filter (lib.hasPrefix "logs/") (builtins.attrNames pipelines);
          # A logs pipeline writes only into devloop: through the forward and
          # routing connectors, or a devloop table's exporter whose database
          # header is devloop.
          # Not the metrics exporter otlp_http/devloop, which carries no table
          # or pipeline header, so logs sent there would skip the allow-list
          # pipeline.
          exportsToDevloop =
            name:
            name == "forward"
            || name == "routing/logs"
            || (
              builtins.elem name (map (table: "otlp_http/devloop_${table}") devloopTables)
              && (e.${name}.headers."x-greptime-db-name" or null) == "devloop"
            );
          # The OTLP receiver's component type is `otlp`
          # (open-telemetry/opentelemetry-collector@v0.155.0:
          # receiver/otlpreceiver/internal/metadata/generated_status.go:12);
          # an instance is `otlp` or `otlp/<name>`.
          isOtlpReceiver = name: name == "otlp" || lib.hasPrefix "otlp/" name;
```

Replace the content clause written in Step 18 with exactly:

```nix
          # Content: no traces pipeline, and the logs pipelines write only
          # into devloop (S2 design D4; S7 adds journald logs behind ADR-008's
          # stages).
          (check "R3.1: a traces pipeline, or a logs pipeline exporting outside devloop" (
            lib.all (name: !(lib.hasPrefix "traces" name)) (builtins.attrNames pipelines)
            && lib.all (name: lib.all exportsToDevloop pipelines.${name}.exporters) logsPipelineNames
          ))
          # logsTakeLocalReceiver: the local OTLP receiver feeds no logs
          # pipeline (ADR-003:81; S2 design D4).
          (check "R3.1: a logs pipeline takes the local OTLP receiver" (
            lib.all (name: !(lib.any isOtlpReceiver pipelines.${name}.receivers)) logsPipelineNames
          ))
```

In the header comment, replace lines 9-10 (the two lines from `# literals, and the process identity attributes` to `requires the exponential-histogram conversion`) with exactly:

```nix
# literals, and the process identity attributes and node_exporter's firewall
# are module assertions. Since S2 it also judges the devloop logs routes: each
# devloop table's exporter queue, no logs pipeline exporting outside devloop
# and none taking the local OTLP receiver. R1.2 requires the exponential-histogram conversion
```

Run:

```bash
nix build --no-link -L .#checks.x86_64-linux.otel-collector-config 2>&1 | tee logs/s2-evidence/3.6-r31-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E 'otel-collector-config (failures|accepted)|error:' || echo r31-green
```

Expected: `r31-green`: the real configuration has no failure, and every mutant, the four new ones and S1's `schemaOrderDropped` among them, gives a non-empty failure list, so the ordering clause still keeps the collector after `greptimedb-schema`.
To record each new mutant's rejecting clause, run:

```bash
nix eval --impure --json --expr '
let
  flake = builtins.getFlake (toString ./.);
  lib = flake.inputs.nixpkgs.lib;
  m = flake.nixosConfigurations.magnetite.config;
  check = flake.checks.x86_64-linux.otel-collector-config;
  input = {
    settings = m.services.opentelemetry-collector.settings;
    overrides = m.services.opentelemetry-collector.validateConfigOverrides;
    collectorService = m.systemd.services.opentelemetry-collector.serviceConfig;
    node = m.services.prometheus.exporters.node;
    services = m.systemd.services;
    notifyUnits = m.services.observability-notify.units;
    schema = flake.lib.otelCollectorSchema;
    storeVersion = m.services.greptimedb.package.version;
    notifierInterval = m.systemd.services."observability-notify@".environment.OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC or null;
  };
  onSettings = update: i: i // { settings = lib.recursiveUpdate i.settings update; };
  e = input.settings.exporters;
in {
  logsQueueNotPersistent = check.failures (input // { settings = input.settings // { exporters = e // { "otlp_http/devloop_ci_build" = e."otlp_http/devloop_ci_build" // { sending_queue = removeAttrs e."otlp_http/devloop_ci_build".sending_queue [ "storage" ]; }; }; }; });
  logsToFleet = check.failures (onSettings { service.pipelines."logs/devloop-ci_build-out".exporters = [ "otlp_http/fleet" ]; } input);
  logsToMetricsExporter = check.failures (onSettings { service.pipelines."logs/devloop-ci_build-out".exporters = [ "otlp_http/devloop" ]; } input);
  otlpInLogsPipeline = check.failures (onSettings { receivers.otlp.protocols.http.endpoint = "127.0.0.1:4318"; service.pipelines."logs/devloop-ci_build".receivers = input.settings.service.pipelines."logs/devloop-ci_build".receivers ++ [ "otlp" ]; } input);
}' 2>&1 | jq -r 'to_entries[] | "mutant \(.key) rejected: \(.value | join("; "))"' | tee -a logs/s2-evidence/3.6-r31-2*.log
```

Expected: `mutant logsQueueNotPersistent rejected: R3.1: queue not in file_storage`, `mutant logsToFleet rejected: R3.1: a traces pipeline, or a logs pipeline exporting outside devloop`, `mutant logsToMetricsExporter rejected: R3.1: a traces pipeline, or a logs pipeline exporting outside devloop`, `mutant otlpInLogsPipeline rejected: R3.1: a logs pipeline takes the local OTLP receiver`.
The `input` above is the check's own (`modules/checks/otel-collector-config.nix:77-89`), rebuilt outside it because the check exposes only `failures` through `passthru`.

- [ ] **Step 20: Record R3.1's evaluation cost**

Run:

```bash
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/otel-collector-config-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.otel-collector-config.drvPath; echo
jq '{gcTotalBytes: .gc.totalBytes, cpuTime}' /tmp/otel-collector-config-stats.json 2>&1 | tee logs/s2-evidence/3.6-r31-cost-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: a `/nix/store/…-otel-collector-config.drv` path and `gcTotalBytes` below `536870912` (0.5 GiB), recorded with this command as its method.
Before this task the same command measured 483139008 B (0.450 GiB, cpuTime 1.54 s) on 2026-10-21 against the working copy at `main@origin` `5f94a946ba`; the new clauses read values the check already forces, so the figure should move by under 0.01 GiB `[INFERENCE]`, confirmed by this step.
If it is at or above the budget, stop and report the two figures to the orchestrator; the margin was already 0.05 GiB.

- [ ] **Step 21: Build magnetite and the neighbouring checks (build)**

Run:

```bash
{
  nix build --no-link .#checks.x86_64-linux.nixos-magnetite .#checks.x86_64-linux.devloop-queries .#checks.x86_64-linux.greptimedb-envelope && echo built
  nix eval --raw .#vmTests.x86_64-linux.greptimedb-pipeline.drvPath && echo
  nix eval --raw .#vmTests.x86_64-linux.devloop-ingest.drvPath && echo
} 2>&1 | tee logs/s2-evidence/3.5-build-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '^built$|\.drv$|error:'
```

Expected: `built` (magnetite's toplevel runs `otelcol-contrib validate` over the rendered configuration, `NixOS/nixpkgs@ac1faec44836:nixos/modules/services/monitoring/opentelemetry-collector.nix:30-38`), then the two test `.drv` paths (GREEN for Step 8), and no `error:` line.
`greptimedb-pipeline` imports the ingress role without `devloop-collection`, so its collector has no logs pipeline, which `devloopLogs` keeps valid.
If the build cannot be scheduled from stibnite, nixbot builds it on the pull request, and its log is fetched as this evidence instead.

- [ ] **Step 22: Format**

Run:

```bash
{
  nix fmt -- modules/nixos/devloop-collection.nix modules/machines/nixos/magnetite/default.nix modules/clan/services/otel-collector/flake-module.nix modules/checks/otel-collector-config.nix modules/vm-tests/devloop-ingest.nix modules/vm-tests/devloop-ingest/helpers.py modules/vm-tests/devloop-ingest/nixbot-schema.sh modules/vm-tests/devloop-ingest/gitea-mq-lines.txt
  nix fmt -- --fail-on-change && echo fmt-clean
} 2>&1 | tee logs/s2-evidence/3.10-fmt-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: the last line is `fmt-clean`.
If the first command reformatted a file, rerun Steps 19 and 21 and expect the same lines.

- [ ] **Step 23: Tick 3.1–3.8**

In `openspec/changes/stand-up-devloop-collection/tasks.md`, change the leading `- [ ]` of the lines beginning `- [ ] 3.1 `, `- [ ] 3.2 `, `- [ ] 3.3 `, `- [ ] 3.4 `, `- [ ] 3.5 `, `- [ ] 3.6 `, `- [ ] 3.7 ` and `- [ ] 3.8 ` (lines 35-42) to `- [x]` with the edit tool, and nothing else; 3.9 is ticked in Step 26 after its run, 3.10 by the orchestrator when nixbot reports the pull request green, and 3.11 after the deploy.
Run: `rg -n '^- \[x\] 3\.[1-8] ' openspec/changes/stand-up-devloop-collection/tasks.md | wc -l`
Expected: `8`.

- [ ] **Step 24: Commit**

Run:

```bash
jj new --no-edit -r main@origin -m 'feat(devloop): collect nixbot, gitea-mq and deploy records into devloop'
change="$(jj log --no-graph -r 'children(main@origin) & empty() & description(substring:"feat(devloop): collect nixbot, gitea-mq and deploy records")' -T 'change_id.shortest(8)')"
jj squash --from @ --into "$change" --keep-emptied --use-destination-message -- \
  modules/nixos/devloop-collection.nix \
  modules/machines/nixos/magnetite/default.nix \
  modules/clan/services/otel-collector/flake-module.nix \
  modules/checks/otel-collector-config.nix \
  modules/vm-tests/devloop-ingest.nix \
  modules/vm-tests/devloop-ingest \
  openspec/changes/stand-up-devloop-collection/tasks.md
jj diff --no-pager --summary -r "$change"
```

Expected: `M modules/nixos/devloop-collection.nix`, `M modules/machines/nixos/magnetite/default.nix`, `M modules/clan/services/otel-collector/flake-module.nix`, `M modules/checks/otel-collector-config.nix`, `A modules/vm-tests/devloop-ingest.nix`, `A modules/vm-tests/devloop-ingest/gitea-mq-lines.txt`, `A modules/vm-tests/devloop-ingest/helpers.py`, `A modules/vm-tests/devloop-ingest/nixbot-schema.sh`, `M openspec/changes/stand-up-devloop-collection/tasks.md`, and nothing else.
If `tasks.md` carried hunks other than this task's ticks before the squash, squash that file with `--interactive` and select only the eight ticks.

- [ ] **Step 25: Run `devloop-ingest` on magnetite from the change's commit (tasks.md 3.9)**

The test runs from a checkout of exactly the commit the pull request carries, on magnetite, the only builder advertising `uid-range` (`modules/README.md:56-62`); from stibnite the build is routed there.
Run:

```bash
commit="$(jj log --no-graph -r 'children(main@origin) & description(substring:"feat(devloop): collect nixbot, gitea-mq and deploy records")' -T 'commit_id')"
git worktree add -q --detach /tmp/wt-s2-ingest "$commit"
( cd /tmp/wt-s2-ingest && nix build --no-link -L .#vmTests.x86_64-linux.devloop-ingest ) 2>&1 | tee logs/s2-evidence/3.9-devloop-ingest-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '^(.*: )?(=== case|ok: |mutant .* rejected|limitation:)|Traceback|AssertionError|error:'
git worktree remove /tmp/wt-s2-ingest
echo "commit $commit" | tee -a logs/s2-evidence/3.9-devloop-ingest-*.log
```

Expected, in order: `=== case firstStart`, four `ok: firstStart: otlp_http/devloop_<table> sent <n>, send_failed 0` lines, four `ok: firstStart: DESC TABLE <table> equals the allow-list` lines, `ok: firstStart`; `=== case noAutoCreate`, `mutant noAutoCreate rejected: otlp_http/devloop_ci_build send_failed <n> when the schema job's tables lack ci_build, and no table was created`, `ok: noAutoCreate`; `=== case overlap`, `ok: overlap: ci_attribute sent <≥6> and ci_build <≥2> records after the rows were stored; one row per key`, `ok: overlap`; `=== case tableShape`, `ok: tableShape: batch_event per msg {'batch formed': 3, 'batch built': 3, 'batch landed': 2, 'batch bisecting': 1, 'batch done': 2}; …`, `ok: tableShape: ci_attribute equals nixbot's rows, abandoned only for the marker, no error text`, `ok: tableShape`; `=== case switch`, at most one `limitation:` line, `ok: switch: one line, closure /nix/store/…, previous_closure /nix/store/…`, `ok: switch: both records reached deploy_record`, `ok: switch`; `=== case documentedQueries`, `ok: documentedQueries: queueWait counts build 605's first attempt only, not its 5000 s rerun`, `ok: documentedQueries: each of the three questions returns its fixture answer`, `ok: documentedQueries`; no `Traceback`, `AssertionError` or `error:`; the build succeeds.
The `limitation:` line, if printed, is design D16's recorded gap: Task 8's `verify.md` cites it for WA `A49`, and the line says which path wrote the record.
If any case fails, fix the code it judges in the working copy, rerun Steps 21-22, squash the fix into `$change` with the same `jj squash` paths, and rerun this step; never weaken an assertion to pass.

- [ ] **Step 26: Tick 3.9 and fold it into the change**

Change the leading `- [ ]` of the line beginning `- [ ] 3.9 ` (line 43) to `- [x]` with the edit tool, then run:

```bash
change="$(jj log --no-graph -r 'children(main@origin) & description(substring:"feat(devloop): collect nixbot, gitea-mq and deploy records")' -T 'change_id.shortest(8)')"
jj squash --from @ --into "$change" -- openspec/changes/stand-up-devloop-collection/tasks.md
jj diff --no-pager --git -r "$change" -- openspec/changes/stand-up-devloop-collection/tasks.md | grep -c '^+- \[x\] 3\.'
jj diff --no-pager --summary --from "$(sed -n 's/^commit //p' logs/s2-evidence/3.9-devloop-ingest-*.log | tail -n 1)" --to "$change"
```

Expected: `9`, then only `M openspec/changes/stand-up-devloop-collection/tasks.md`: the pull request's tree differs from the tested one by the tick alone.

- [ ] **Step 27: Pull request merged (tasks.md 3.10)**

The orchestrator rebases the development join onto the change, pushes it, opens pull request 3 with `logs/s2-evidence/3.9-devloop-ingest-<ts>.log` (the file name and its `commit` line) named in the description, and enqueues it after pull request 2 has landed; nixbot reports `otel-collector-config`, `devloop-queries` and `nixos-magnetite` green, and the orchestrator ticks 3.10.
Verify: `jj git fetch && jj log --no-graph -r 'main@origin & description(substring:"feat(devloop): collect nixbot, gitea-mq and deploy records")' -T 'commit_id.shortest(12)'` prints one commit.

- [ ] **Step 28: Gate before deploy D3**

Task 7's 7.3 has passed after D2: the four tables and pipelines exist on magnetite and are empty, so the first rows have their tables (design D5).
Run: `ls logs/s2-evidence/7.3-*.log && grep -c 'append_mode' logs/s2-evidence/7.3-*.log`
Expected: the 7.3 logs exist and the count is at least 4; if not, stop: deploying before the tables exist turns the first writes into dropped 400s.
Also confirm D2's window was closed by its deploy: `grep -E '^D2_(START|END)=' logs/s2-evidence/window.env` prints two lines.

- [ ] **Step 29: Deploy D3 (tasks.md 3.11)**

Run: `$REPO/logs/s2-evidence/s2-deploy.sh magnetite D3`
Expected: `clan exit=0` and `D3_START`, `D3_END` appended to `logs/s2-evidence/window.env`; the script deploys from a fresh worktree of `origin/main` only when `nixbot-logs queue` prints `Queue is empty` (Task 7 Step 0).
The first polls backfill nixbot's retained history, about 200,000 attribute rows in about 20 polls of 10,000, above ADR-004's 100,000 rows a day once, on this deploy day only, as design Risks accepts; 7.4 records the day's sent and stored counts against that budget, so nothing here is a failure.
Tick 3.11 with the edit tool in the next task's change, or in Task 8's, after 7.4 passes; 7.4 must pass before group 4's deploy.
If the collector fails to start, `sudo journalctl -u opentelemetry-collector` names the component; roll back by redeploying magnetite from the previous `main@origin` commit through the same script, which stops collection and leaves the tables and their rows in place (design Migration Plan).

#### Questions and contract notes for Task 3

1. R3.1's `logsTakeLocalReceiver`: the contract and `tasks.md` 3.6 compare the pipelines with "the receiver the agent role declares for local senders", but no role declares an OTLP receiver today (only `greptimedb-pipeline`'s test node adds one, `modules/vm-tests/greptimedb-pipeline.nix:164-167`).
   The clause compares the evaluated logs pipelines' receivers with the vendor's component type `otlp` instead, which no line of ours sets; the name and mutant are kept.
2. The content clause at `otel-collector-config.nix:297-300` had to change for any logs pipeline to exist.
   Following the orchestrator's instruction it now forbids traces pipelines and any logs export outside `devloop`, with the added mutants `logsToFleet` and `logsToMetricsExporter` (plan review F3), names the contract does not list.
3. `logs/ingress` and the per-table routes are built only when `services.greptimedb.pipelines.devloop` is non-empty: a `forward` receiver in a logs pipeline with no logs pipeline exporting to `forward` fails validation (`open-telemetry/opentelemetry-collector@v0.155.0:service/internal/graph/graph.go:171-184`), which would break `greptimedb-pipeline` and any ingress host without `devloop-collection`.
4. `devloop-pg-grants` is also ordered after `postgresql-setup.service`, which creates the roles; the contract lists only `postgresql.service` and `nixbot.service`.
5. The contract writes the drop-in path as `/run/systemd/system/<unit>.d/`; `unitMutants.<name>.unit` is the unit name without `.service` (so `systemd.services.${unit}` resolves), and the path is `/run/systemd/system/<unit>.service.d/zz-mutant.conf`, agreed with S2PlanT4.
6. The container's `config.json` carries the Nix-rendered constants (`vars`, `psql`, `tables`, `questions`, `abandonMarker`, `batchEventKeys`), so `testScript` stays exactly `helpers.py` plus `cases`; helpers.py adds the private `_sql`, `_output`, `_count`, `_sent` and `_otel_metric` beside the contract's helpers.
7. `key_counts` counts distinct `(primary key, time index)`, the identity a non-append table deduplicates on; `deploy_record`'s key `host` alone would make every second record a "duplicate".
8. The sqlquery README places `attribute_columns` at query level (`README.md:85`), but the receiver reads it per `logs` entry (`internal/sqlquery/config.go:116-118`); the code is followed, and without it no column would become an attribute.
9. `documentedQueries` inserts its fixture rows as `admin` directly into the tables, so the three answers are exact; ingestion of each column is judged by `tableShape` and `firstStart`, not by this case.
10. The vm test runs from the commit before 3.9's tick is folded in, so the merged tree differs from the tested tree by that one line, which Step 26 shows.
11. `devloop-pg-grants` joins `services.observability-notify.units` in this task (Main's decision), but R3.1's policy clause requires it to be listed only after Task 4 extends `notifiedByPolicy` to `devloop-`; until then only the wiring clauses judge the entry, and removing it fails no check.
12. Plan review F15: `writerOrdering` is renamed `noAutoCreate`, because it shows `auto_create_table=false` refusing a write to a missing table, while the collector's order after the schema job is judged by R3.1's `schemaOrderDropped`; `tasks.md` 3.9's "writer ordering" wording names the same case.
    `overlap` snapshots the sent counters only after the 9101 rows are stored; the collector's `retain` and body `remove` are defence in depth with no test.
13. Plan review F16: both journal and SQL readers advance their cursor before delivery, so a refused batch loses journal lines and CI rows older than the overlap; `journald/gitea-mq` retries without limit, and the `sqlquery` receivers rely on the overlap, C1 to C3 and a cursor reset.
    Any later edit of an export query re-backfills about 200,000 attribute rows once, over ADR-004's row budget that day, because the cursor's storage key embeds the SQL text.
14. Plan review F21: `buildOutcome` leaves out a build with no outcome row, so the fixture build 508 (one `cancelled` row) and its expectation are gone.

---


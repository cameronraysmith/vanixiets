### Task 2: The `devloop` allow-list, tables, pipelines and `devloop-queries` (deploy D2)

Implements `tasks.md` 2.1–2.9 (design D3, D5, D6, D10, D13, D14; DCI `One devloop allow-list decides every stored column`, `The devloop tables are pre-created with keys, a time index and deduplication`, `Each devloop table has an ingest pipeline that keeps only its allow-listed fields`, `Each nixbot query re-reads a five-minute overlap in pages of 10,000 rows`, `Each nixbot query returns only allow-listed columns as text`, `The attribute query derives abandoned from the shared marker`, `The nixbot readers authenticate by peer and hold column grants only`, `The collector reads nixbot's builds and attributes through two cursor queries`, `devloop-queries binds the export queries to nixbot's migrations`, `devloop-queries binds the abandonment marker to the patch's production code`; TSI `Databases and their retention are set at the telemetry store`; DC `No error text, message body or other free text enters the dev-loop history`, `The build service's records are read without being changed and without a stored credential`; WA `A43`).
Each piece is shown absent or failing before it is written: the allow-list and the renderers are first evaluated as missing, the two store options first fail as undeclared options, and `checks.x86_64-linux.devloop-queries` is written complete and seen failing at evaluation while `flake.lib.devloopCollection` still lacks the nixbot side (2.5), which is then added and the check built green with its marker clause's two negative controls and its four mutants rejected.
This task creates `modules/nixos/devloop-collection.nix`, `abandonMarker` included, which Task 1 no longer creates (plan review F11).
The store options are proved inert when empty by comparing magnetite's `greptimedb-schema` `ExecStart` before and after the edit, before magnetite imports `devloop-collection`.
This task establishes the statements and pipelines by evaluation, by `yq` and by a planning-time rehearsal of the VRL programs, and then, before its pull request is enqueued, by the pre-D2 compile check (`tasks.md` 2.7, plan review F5): a throwaway GreptimeDB 1.2.1 on magnetite runs the four statements, takes the four pipelines and stores one OTLP record per table written as `collector`, and D2 gates on its log.
Task 3's `devloop-ingest` first-start case exercises them again with the real receivers.

**Files:**
- Modify: `modules/clan/services/otel-collector/schema.nix` (87 lines today; insert `devloop.tables` after the `databases` map, `:81-85`, before the closing `};` of `flake.lib.otelCollectorSchema` at `:86`)
- Create: `modules/nixos/devloop-collection.nix` (177 lines in Step 6, extended in Step 18; 309 lines after this task)
- Modify: `modules/nixos/greptimedb.nix` (345 lines today: header comment `:6-7`, new `let` bindings after `:95`, the script's last line `:125`, two options after `tableTtls` at `:146-153`)
- Modify: `modules/machines/nixos/magnetite/default.nix` (the `with flakeModules` list, `:52-77` today, `:52-78` after Task 1's `deploy-record` line; one line after `greptimedb`)
- Create: `modules/checks/devloop-queries.nix` (`checks.x86_64-linux.devloop-queries`)
- Create: `modules/checks/devloop-queries/fixtures.sql`, `modules/checks/devloop-queries/mutant-rename-cached.sql` (`.sql`, so import-tree does not load them)
- Modify: `openspec/changes/stand-up-devloop-collection/tasks.md` (tick 2.1–2.6)
- Evidence (git-ignored): `logs/s2-evidence/2.7-precheck.sh` (Step 25), `logs/s2-evidence/2.*-*.log`, `logs/s2-evidence/2.6-schema-check.sql`, `logs/s2-evidence/2.6-schema-check.norm.sql`

**Interfaces:**
- Consumes (Task 1): `logs/s2-evidence/1.2-normalise.sh` (stdin to stdout) and `logs/s2-evidence/1.2-schema-magnetite.norm.sql` from Task 1 Step 2.
- Consumes (S1): `services.greptimedb.databases` with `devloop = "365d"` on magnetite from `flake.lib.otelCollectorSchema.databases` (`schema.nix:81-85`), the schema job's `admin-password` credential and `sql` function (`greptimedb.nix:118-123`).
- Produces: `flake.lib.otelCollectorSchema.devloop.tables.<table> = { columns = [ { name; type; nullable; } … ]; primaryKey = [ … ]; timeIndex = "<column>"; }` with `type` in `int64`, `string`, `boolean`, `timestamp`, the four tables of the plan head's allow-list, every column `nullable = true` except the time index (`nullable = false`).
- Produces: `flake.lib.devloopCollection` = `{ abandonMarker; postgresqlMajor; ddl; pipelines; selects; queries; grants; grantSql; }`:
  - `abandonMarker = "not finished when the required attributes had settled"` (design D13), the Python string literal of `modules/nixos/nixbot-abandon-optional-attributes.patch:146`.
  - `postgresqlMajor = "16"`: the PostgreSQL major magnetite runs (16.15, read 2026-10-21 by `nix eval --raw .#nixosConfigurations.magnetite.config.services.postgresql.package.version`), the major `devloop-queries` runs.
  - `ddl.<table>`: one `CREATE TABLE IF NOT EXISTS "<table>" (…) ENGINE=mito WITH ('append_mode' = 'false', 'sst_format' = 'flat')` string, every identifier double-quoted, one column per line in allow-list order (`  "<name>" <BIGINT|STRING|BOOLEAN|TIMESTAMP(6)>[ NOT NULL],`), then `  TIME INDEX ("<timeIndex>"),` and `  PRIMARY KEY ("<k>", …)`; `'append_mode' = 'false'` occurs exactly once.
  - `pipelines.<table>`: the YAML of pipeline `devloop_<table>`, `version: 2`; a `vrl` step `a = object!(.LogAttributes)`, for `batch_event` only `t = int!(.Timestamp)`, then `. = {}` and one line per column in allow-list order, `        .<column> = if a.<column> == null || a.<column> == "" { null } else { <to_int!|to_bool!|string!>(a.<column>) }` (8-space indent), for `batch_event.ts` `        .ts = if t == 0 { null } else { from_unix_timestamp!(t, unit: "nanoseconds") }`, then `.`; a `date` step over the non-nullable string timestamps (the time index) and one with `ignore_missing: true` over the nullable ones; a `transform` entry per column (`int64`, `string`, `boolean`, `time, us`), `tag: true` on key columns, `index: timestamp` on the time index.
  - `selects.<ci_attribute|ci_build>.<column>`: the SQL expression behind each alias before wrapping (`b.id`, `a.cached`, `a.outputs ->> 'out'`, `p.owner || '/' || p.name`, `(a.status = 'ignored_failure' AND a.error IS NOT DISTINCT FROM 'not finished when the required attributes had settled')`, …).
  - `queries.<ci_attribute|ci_build>`: `SELECT '' AS "body",` then one line per allow-listed column, `  coalesce((<expr>)::text, '') AS "<column>"` or for a timestamp `  coalesce(to_char(<expr> AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), '') AS "<column>"`, then `FROM …`, `WHERE <finished_at expr> >= least($1::timestamptz, now() - interval '5 minutes')`, `ORDER BY <finished_at expr>`, `LIMIT 10000`, no trailing semicolon.
  - `grants.opentelemetry-collector.{builds,build_attributes,projects}` and `grants.devloop-reconcile.{builds,build_attributes}` (lists of column names, design D10 with the reconcile narrowed to least privilege: `builds` `[ "id" "branch" "finished_at" ]`, `build_attributes` `[ "build_id" "attr" "finished_at" ]`, no `projects` key).
  - `grantSql`: five lines, `GRANT SELECT ("<col>", …) ON "<table>" TO "<role>";`, roles and tables in attribute-name order (`devloop-reconcile` first), newline-terminated; the collector's `build_attributes` line contains `"cached", "error", "drv_path"` exactly once.
- Produces: options `services.greptimedb.tables` (`attrsOf (listOf str)`, default `{ }`) and `services.greptimedb.pipelines` (`attrsOf (attrsOf str)`, default `{ }`); with either non-empty, `greptimedb-schema` gains the shell functions `expect_200`, `database_sql DATABASE STATEMENT` (`POST /v1/sql?db=DATABASE`, form `sql`) and `upload_pipeline DATABASE NAME FILE` (`POST /v1/pipelines/NAME?db=DATABASE`, `--form file=@FILE`), each as `admin` through `curl --config -`, exiting 1 with `greptimedb-schema: <what> answered HTTP <code>` on any status but 200; tables first, then pipelines, both after the databases; with both empty the script is byte-identical to today's.
- Produces: `flake.modules.nixos.devloop-collection`, a module function `{ config, ... }:` setting `services.greptimedb.tables.devloop = lib.attrValues ddl` and `services.greptimedb.pipelines.devloop.devloop_<table>`, with one assertion: when `config.services.postgresql.enable`, `lib.versions.major config.services.postgresql.package.version == postgresqlMajor`, message starting `devloop-collection: services.postgresql.package is PostgreSQL`; magnetite imports it directly after `greptimedb`; Task 3 and Task 4 add to the same function.
- Produces: `checks.x86_64-linux.devloop-queries`, a `stdenvNoCC.mkDerivation` whose `checkPhase` runs under `postgresqlTestHook` with `pkgs."postgresql_${flake.lib.devloopCollection.postgresqlMajor}"`, reading no NixOS configuration; before PostgreSQL starts it prints its evaluated marker clause and the clause's two negative controls (`markerClauses`, over `patchText`, `productionContext`, `lastCharacterChanged` and `testLiterals`); output `$out/schema.sql`; prints `ok: <label>` per assertion and `mutant <name> rejected: <first FAIL or ERROR line>` per mutant.
  The extension point for Task 4, all `perSystem` `let` bindings in `modules/checks/devloop-queries.nix`:
  - `clockVars`: attrset from psql variable name to an SQL timestamp expression over `t0` (`fixture_clock.t0`); each is rendered as `to_char((<expr>) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')` and passed to every query as `-v <name>=<value>`; Task 2 defines `cursor_old` and `cursor_recent`, Task 4 adds its window bounds.
  - `fixtureFiles`: the list of SQL files loaded as `postgres` after the grants, in order; Task 4 appends its own file.
  - `roleQueries = queries: [ { name; role; types; sql; executions = { <label> = [ <EXECUTE argument SQL> … ]; }; } … ]`: each entry is rendered per execution into `PREPARE <name>(<types>) AS <sql>; EXECUTE <name>(<arguments>);` and run with `psql -X -q -A -F <TAB> -P footer=off -v ON_ERROR_STOP=1 -U <role>`, its result in `$(result <name> <label>)`, a header line then TAB-separated rows; adding a query run as another role is one list entry, with arguments such as `":'window_start'"`.
  - `assertions = [ { label; script; } … ]`: bash run with `$db` set, using `result NAME LABEL`, `value NAME LABEL KEYCOLUMN KEY COLUMN` (exit 1 when no row matches); the runner prints `ok: <label>` or `FAIL: <label>`.
  - `real = { queries; grantSql; afterFixtures; }`, `mutants.<name> = real // { … }` and `replaceOnce name from to text` (an evaluation error when the replacement changes nothing); every run, real and mutant, executes every `roleQueries` entry and every assertion in its own database (`nixbot`, `nixbot_<mutant>`).

- [ ] **Step 1: Confirm the base and record the schema job's script**

Run from `$REPO`:

```bash
mkdir -p logs/s2-evidence
{
  jj git fetch
  jj log --no-graph -r main@origin -T 'description.first_line() ++ "\n"'
  jj file list -r main@origin modules/nixos/devloop-collection.nix modules/checks/devloop-signals.nix | wc -l
  ls logs/s2-evidence/1.2-normalise.sh logs/s2-evidence/1.2-schema-magnetite.norm.sql
  nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.greptimedb-schema.serviceConfig.ExecStart; echo
  nix eval --json .#nixosConfigurations.magnetite.config.services.greptimedb --apply 's: { inherit (s) databases tableTtls; hasTables = s ? tables; }'
  nix eval --raw .#nixosConfigurations.magnetite.config.services.postgresql.package.name; echo
} 2>&1 | tee logs/s2-evidence/2.0-base-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `main@origin` contains Task 1's merge; `0` (Task 1 created neither file); both files exist; a path `/nix/store/…-greptimedb-schema/bin/greptimedb-schema` (call it `P0`); `{"databases":{"agent":"90d","devloop":"365d","fleet":"30d"},"hasTables":false,"tableTtls":{}}`; `postgresql-16.15`.
If either file is missing, Task 1 Step 2 has not run; stop.
Step 10 compares the script path with `P0`.

- [ ] **Step 2: Show the allow-list absent (RED, evaluation)**

Run: `nix eval --json .#.lib.otelCollectorSchema --apply 's: s ? devloop' 2>&1 | tee logs/s2-evidence/2.1-allow-list-absent-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: `false`.

- [ ] **Step 3: Add the allow-list to `schema.nix` (tasks.md 2.1)**

In `modules/clan/services/otel-collector/schema.nix`, insert after line 85 (the `};` closing `databases`) and before line 86 (the `};` closing `flake.lib.otelCollectorSchema`), with a blank line before it:

```nix
    # The devloop allow-list (design D3; ADR-004 as amended by charter v22):
    # the only declaration of the dev-loop tables' columns, in stored order,
    # their types, primary keys and time indexes. devloop-collection.nix
    # renders from it the table statements, the ingest pipelines and the
    # nixbot queries' output columns; S4's agents read it too. Every column
    # but the time index is nullable.
    devloop.tables =
      let
        column = name: type: {
          inherit name type;
          nullable = true;
        };
        timeIndex = name: {
          inherit name;
          type = "timestamp";
          nullable = false;
        };
      in
      {
        ci_attribute = {
          columns = [
            (column "build_id" "int64")
            (column "attr" "string")
            (column "system" "string")
            (column "status" "string")
            (column "cached" "boolean")
            (column "abandoned" "boolean")
            (column "drv_path" "string")
            (column "outputs_out" "string")
            (column "started_at" "timestamp")
            (timeIndex "finished_at")
            (column "eval_wall_ms" "int64")
            (column "eval_alloc_bytes" "int64")
            (column "commit_sha" "string")
            (column "branch" "string")
            (column "pr_number" "int64")
            (column "project" "string")
          ];
          primaryKey = [
            "build_id"
            "attr"
          ];
          timeIndex = "finished_at";
        };
        ci_build = {
          columns = [
            (column "build_id" "int64")
            (column "created_at" "timestamp")
            (column "started_at" "timestamp")
            (timeIndex "finished_at")
            (column "eval_duration_ms" "int64")
            (column "status" "string")
            (column "pr_number" "int64")
            (column "branch" "string")
          ];
          primaryKey = [ "build_id" ];
          timeIndex = "finished_at";
        };
        batch_event = {
          columns = [
            (column "batch" "int64")
            (column "msg" "string")
            (column "build" "int64")
            (column "sha" "string")
            (column "failed_check" "string")
            (column "members" "int64")
            (column "landed" "int64")
            (column "ejected" "int64")
            (column "builds" "int64")
            (column "flaky" "boolean")
            (timeIndex "ts")
          ];
          primaryKey = [
            "batch"
            "msg"
          ];
          timeIndex = "ts";
        };
        deploy_record = {
          columns = [
            (column "host" "string")
            (column "closure" "string")
            (column "previous_closure" "string")
            (timeIndex "ts")
          ];
          primaryKey = [ "host" ];
          timeIndex = "ts";
        };
      };
```

The two local helpers make the one non-nullable column of each table, the time index, visible at its place in the list, and every other column nullable (plan head; design D3).

- [ ] **Step 4: Evaluate the allow-list (GREEN, evaluation; tasks.md 2.1 verify)**

Run:

```bash
{
  nix eval --json .#.lib.otelCollectorSchema.devloop.tables --apply 't: builtins.mapAttrs (_: v: { columns = map (c: c.name) v.columns; inherit (v) primaryKey timeIndex; }) t' | jq -cS . > /tmp/2.1-tables.json
  cat /tmp/2.1-tables.json
  jq -cnS '{
    ci_attribute: {columns: ["build_id","attr","system","status","cached","abandoned","drv_path","outputs_out","started_at","finished_at","eval_wall_ms","eval_alloc_bytes","commit_sha","branch","pr_number","project"], primaryKey: ["build_id","attr"], timeIndex: "finished_at"},
    ci_build: {columns: ["build_id","created_at","started_at","finished_at","eval_duration_ms","status","pr_number","branch"], primaryKey: ["build_id"], timeIndex: "finished_at"},
    batch_event: {columns: ["batch","msg","build","sha","failed_check","members","landed","ejected","builds","flaky","ts"], primaryKey: ["batch","msg"], timeIndex: "ts"},
    deploy_record: {columns: ["host","closure","previous_closure","ts"], primaryKey: ["host"], timeIndex: "ts"}
  }' > /tmp/2.1-scenario.json
  diff /tmp/2.1-scenario.json /tmp/2.1-tables.json && echo "allow-list equals the spec scenario"
  nix eval --json .#.lib.otelCollectorSchema.devloop.tables --apply 't: builtins.mapAttrs (_: v: map (c: "${c.name}:${c.type}:${if c.nullable then "null" else "notnull"}") v.columns) t' | jq -c .
} 2>&1 | tee logs/s2-evidence/2.1-allow-list-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: the line `allow-list equals the spec scenario` (the jq literal is DCI `The allow-list is evaluated` transcribed from `specs/devloop-collection-interface/spec.md:179`), then every column `…:null` except `ci_attribute`'s and `ci_build`'s `finished_at:timestamp:notnull` and `batch_event`'s and `deploy_record`'s `ts:timestamp:notnull`, with the types of the plan head's allow-list.

- [ ] **Step 5: Show the renderers absent (RED, evaluation)**

Run: `nix eval --json .#.lib --apply 'l: l ? devloopCollection' 2>&1 | tee logs/s2-evidence/2.2-renderers-absent-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: `false`.

- [ ] **Step 6: Write the table statements and pipelines (tasks.md 2.2)**

Create `modules/nixos/devloop-collection.nix` with exactly:

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
in
{
  flake.lib.devloopCollection = {
    inherit
      abandonMarker
      postgresqlMajor
      ddl
      pipelines
      ;
  };

  flake.modules.nixos.devloop-collection =
    { config, ... }:
    {
      assertions = [
        {
          assertion =
            !config.services.postgresql.enable
            || lib.versions.major config.services.postgresql.package.version == postgresqlMajor;
          message = "devloop-collection: services.postgresql.package is PostgreSQL ${config.services.postgresql.package.version}, but flake.lib.devloopCollection.postgresqlMajor is ${postgresqlMajor}, the major checks.x86_64-linux.devloop-queries runs nixbot's migrations and the export queries on (design D14).";
        }
      ];
      services.greptimedb.tables.devloop = lib.attrValues ddl;
      services.greptimedb.pipelines.devloop = lib.mapAttrs' (
        name: pipeline: lib.nameValuePair "devloop_${name}" pipeline
      ) pipelines;
    };
}
```

The `vrl` step resets the event with `. = {}` and assigns each allow-listed field on its own line, coerced from its string attribute with `""` and an absent attribute as null.
The module's assertion relates two independently defined values, the host's evaluated `services.postgresql.package.version` and the constant `postgresqlMajor`; Step 14 shows it able to fail.

Vendor behaviour this file relies on, read at `GreptimeTeam/greptimedb@v1.2.1` (commit `179ff8e5`):
- On the OTLP-with-pipeline path the event a pipeline sees is an object with `Timestamp` and `ObservedTimestamp` as integer nanoseconds, `LogAttributes` as an object of the record's attributes, and `Body`, `TraceId`, `SpanId`, `SeverityText`, `ResourceAttributes`, `Scope*` beside them (`src/servers/src/otlp/logs.rs:142-197`, built for every record at `:986-1010` and handed to the pipeline at `:92-108`).
- The `vrl` processor compiles the source with the whole VRL standard library and replaces the event with the program's result, which must be able to be an object (`src/pipeline/src/etl/processor/vrl_processor.rs:48-96`); the bundled VRL is `vrl` 0.33.1 (`Cargo.lock`).
- The `date` processor turns a string field into a timestamp with the first format that parses, under `timezone`, and fails on a null or missing field unless `ignore_missing: true` (`src/pipeline/src/etl/processor/date.rs:93-145`, `:196-228`), hence one strict step over the time index and one lenient step over the nullable timestamps.
- A transform's `type: time, us` is `TimestampMicrosecond` (`src/pipeline/src/etl/value.rs:58-100`), `tag: true` makes the column a tag, that is a primary-key column, and `index: timestamp` the time index (`src/pipeline/src/etl/transform/transformer/greptime/coerce.rs:73-85`, `src/pipeline/src/etl/transform/index.rs:57-69`); a null value is written as null and a missing field as null, except the time index, which is the error `TimeIndexMustBeNonNull` (`coerce.rs:173-209`, `src/pipeline/src/etl/transform/transformer/greptime.rs:233-290`); a VRL timestamp is coerced to the transform's resolution (`coerce.rs:184-203`), which is how `batch_event.ts` reaches `TIMESTAMP(6)` without a `date` step.
- `version: 2` passes every field the transform does not name to auto-transform, which would add a column (`src/pipeline/src/etl.rs:146-160`; spike-dedup.md `extra field`), so the `vrl` step's `. = {}` and the per-column assignments are what keep the event to the allow-list.
- The journald receiver sets the record's timestamp from `__REALTIME_TIMESTAMP` in microseconds (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:pkg/stanza/operator/input/journald/input.go:209-256`) and the stanza converter copies it to the OTLP record when non-zero (`pkg/stanza/adapter/converter.go:58-62`), so `batch_event.ts` is the journal time and a zero `Timestamp` is null, which fails the request instead of storing 1970.
- Any processor or transform error fails the whole OTLP request, because the pipeline runner returns it unless `skip_error` is set (`src/servers/src/pipeline.rs:106`, `:158`, `:186`; `src/pipeline/src/lib.rs:42-54`), and GreptimeDB answers it with HTTP 400 (`src/pipeline/src/error.rs:912-984`, `InvalidArguments`), which the exporter drops as permanent (`logs/s2/spike-dedup.md:185-188`).
- In VRL 0.33.1, `to_int(null)` is `0` and `to_bool(null)` is `false` (`vectordotdev/vrl@v0.33.1:src/stdlib/to_int.rs:12`, `src/stdlib/to_bool.rs:11`), so `""` and an absent attribute are mapped to null before coercion; `from_unix_timestamp` takes `unit: "nanoseconds"` (`src/stdlib/from_unix_timestamp.rs:34-51`, `:166-173`).

During planning the four rendered programs were run with `vector vrl` from `vector` 0.59.0 at the root pin, which bundles VRL 0.36.0, over sample events: a first form that put `if` expressions inside an object literal was rejected with `E203 syntax error … unexpected syntax token: "If"`, and the per-field form above produced `{ "abandoned": false, "build_id": 101, "cached": true, "drv_path": null, … }` for `ci_attribute`, `"ts": t'2026-10-21T10:00:00.123456789Z'` for `batch_event` and `"build": null` for an empty attribute.
That VRL 0.33.1 compiles the same programs is `[INFERENCE]`, confirmed by Step 26's pre-D2 compile check and again by Task 3's `devloop-ingest` first-start case, where each pipeline is uploaded and written through.
One bad record therefore loses its whole request (plan review F4): for `sqlquery` the receiver stores the batch's tracking value while it builds the batch (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/sqlqueryreceiver/logs_receiver.go:337-346`), before it sends it (`:206`), so up to 10,000 rows older than the overlap are not read again until the operator resets the receiver's cursor.
`devloop-reconcile`'s C1, C3 and C6 report such a gap the next day, and the replay is a cursor reset; no exporter sets `skip_error`, so a malformed record never silently drops out of a request that otherwise succeeds.

Then snapshot: `jj st --no-pager >/dev/null`.

- [ ] **Step 7: Evaluate the statements and pipelines (evaluation; tasks.md 2.2 verify)**

Run:

```bash
{
  for t in ci_attribute ci_build batch_event deploy_record; do
    echo "=== ddl.$t"; nix eval --raw ".#.lib.devloopCollection.ddl.$t"; echo
    nix eval --raw ".#.lib.devloopCollection.pipelines.$t" > "/tmp/2.2-$t.yaml"
    echo "=== pipelines.$t"; cat "/tmp/2.2-$t.yaml"
    echo "=== yq $t"
    yq -c '{version, steps: [.processors[] | keys[0]], dateFields: [.processors[] | select(has("date")) | {fields: .date.fields, ignore_missing: (.date.ignore_missing // false)}], columns: [.transform[].fields[0]], tags: [.transform[] | select(.tag == true) | .fields[0]], index: [.transform[] | select(.index == "timestamp") | .fields[0]]}' "/tmp/2.2-$t.yaml"
    nix eval --json .#.lib.otelCollectorSchema.devloop.tables --apply "t: { columns = map (c: c.name) t.$t.columns; tags = t.$t.primaryKey; index = [ t.$t.timeIndex ]; }"
  done
  for t in ci_attribute ci_build batch_event deploy_record; do nix eval --raw ".#.lib.devloopCollection.ddl.$t"; done | grep -ci ttl || true
} 2>&1 | tee logs/s2-evidence/2.2-render-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected for each table: the DDL as Step 6 renders it, for `ci_attribute`:

```sql
CREATE TABLE IF NOT EXISTS "ci_attribute" (
  "build_id" BIGINT,
  "attr" STRING,
  "system" STRING,
  "status" STRING,
  "cached" BOOLEAN,
  "abandoned" BOOLEAN,
  "drv_path" STRING,
  "outputs_out" STRING,
  "started_at" TIMESTAMP(6),
  "finished_at" TIMESTAMP(6) NOT NULL,
  "eval_wall_ms" BIGINT,
  "eval_alloc_bytes" BIGINT,
  "commit_sha" STRING,
  "branch" STRING,
  "pr_number" BIGINT,
  "project" STRING,
  TIME INDEX ("finished_at"),
  PRIMARY KEY ("build_id", "attr")
) ENGINE=mito WITH ('append_mode' = 'false', 'sst_format' = 'flat')
```

and the `yq` line's `columns`, `tags` and `index` equal the allow-list line printed after it; `version` is `2`; `steps` is `["vrl","date","date"]` for `ci_attribute` and `ci_build`, `["vrl"]` for `batch_event` and `["vrl","date"]` for `deploy_record`; `dateFields` is `[{"fields":["finished_at"],"ignore_missing":false},{"fields":["started_at"],"ignore_missing":true}]` for `ci_attribute`, `[{"fields":["finished_at"],"ignore_missing":false},{"fields":["created_at","started_at"],"ignore_missing":true}]` for `ci_build`, `[]` for `batch_event` and `[{"fields":["ts"],"ignore_missing":false}]` for `deploy_record`; the last line is `0` (no `ttl` in any statement).
`yq` here is the jq-syntax YAML wrapper on stibnite's path (`/etc/profiles/per-user/crs58/bin/yq`); its exiting non-zero on a pipeline is a parse failure, so stop.
`batch_event`'s pipeline as rendered:

```yaml
version: 2
processors:
  - vrl:
      source: |
        a = object!(.LogAttributes)
        t = int!(.Timestamp)
        . = {}
        .batch = if a.batch == null || a.batch == "" { null } else { to_int!(a.batch) }
        .msg = if a.msg == null || a.msg == "" { null } else { string!(a.msg) }
        .build = if a.build == null || a.build == "" { null } else { to_int!(a.build) }
        .sha = if a.sha == null || a.sha == "" { null } else { string!(a.sha) }
        .failed_check = if a.failed_check == null || a.failed_check == "" { null } else { string!(a.failed_check) }
        .members = if a.members == null || a.members == "" { null } else { to_int!(a.members) }
        .landed = if a.landed == null || a.landed == "" { null } else { to_int!(a.landed) }
        .ejected = if a.ejected == null || a.ejected == "" { null } else { to_int!(a.ejected) }
        .builds = if a.builds == null || a.builds == "" { null } else { to_int!(a.builds) }
        .flaky = if a.flaky == null || a.flaky == "" { null } else { to_bool!(a.flaky) }
        .ts = if t == 0 { null } else { from_unix_timestamp!(t, unit: "nanoseconds") }
        .
transform:
  - fields:
      - batch
    type: int64
    tag: true
  - fields:
      - msg
    type: string
    tag: true
  - fields:
      - build
    type: int64
  - fields:
      - sha
    type: string
  - fields:
      - failed_check
    type: string
  - fields:
      - members
    type: int64
  - fields:
      - landed
    type: int64
  - fields:
      - ejected
    type: int64
  - fields:
      - builds
    type: int64
  - fields:
      - flaky
    type: boolean
  - fields:
      - ts
    type: time, us
    index: timestamp
```

- [ ] **Step 8: Show the store options undeclared (RED, evaluation)**

Run:

```bash
nix eval --impure --json --expr 'let f = builtins.getFlake (toString ./.); in (f.nixosConfigurations.magnetite.extendModules { modules = [ { services.greptimedb.tables.probe = [ "CREATE TABLE IF NOT EXISTS \"probe\" (\"ts\" TIMESTAMP(6) NOT NULL, TIME INDEX (\"ts\"))" ]; } ]; }).config.systemd.services.greptimedb-schema.serviceConfig.ExecStart' 2>&1 | tee logs/s2-evidence/2.3-options-absent-$(date -u +%Y%m%dT%H%M%SZ).log | rg -o "The option .services\.greptimedb\.tables' does not exist"
```

Expected: ``The option `services.greptimedb.tables' does not exist``.

- [ ] **Step 9: Add the two options and their application to `greptimedb.nix` (tasks.md 2.3)**

Make four edits in `modules/nixos/greptimedb.nix`, line numbers as of today.

Replace lines 6–7:

```nix
# [storage] object-store stanza, `databases` and any `tableTtls`; without a
# stanza the store uses GreptimeDB's local `File` storage under data_home.
```

with:

```nix
# [storage] object-store stanza, `databases`, any `tableTtls` and any
# `tables` and `pipelines`; without a stanza the store uses GreptimeDB's
# local `File` storage under data_home.
```

Insert after line 95 (the blank line after `schemaStatements`, `:91-94`) these lines followed by one blank line:

```nix
      # Tables and ingest pipelines (design D5), applied after the databases
      # as admin. With both options empty the script gains nothing, so a host
      # that sets neither runs the script it ran before.
      tableStatements = lib.concatLists (
        lib.mapAttrsToList (
          database: statements: map (statement: { inherit database statement; }) statements
        ) cfg.tables
      );
      pipelineUploads = lib.concatLists (
        lib.mapAttrsToList (
          database: pipelines:
          lib.mapAttrsToList (name: yaml: {
            inherit database name;
            file = pkgs.writeText "greptimedb-pipeline-${database}-${name}.yaml" yaml;
          }) pipelines
        ) cfg.pipelines
      );
      # /v1/sql answers 200 only on success
      # (GreptimeTeam/greptimedb@v1.2.1:src/servers/src/error.rs:933-935), and
      # the pipeline API takes the first multipart field as the pipeline's
      # YAML (src/servers/src/http/event.rs:137-175, :293-325). The answer
      # goes to a file under PrivateTmp, so its status is judged on its own.
      objectsScript = lib.optionalString (tableStatements != [ ] || pipelineUploads != [ ]) (
        "\n"
        + ''
          answer="$(mktemp)"
          expect_200() {
            cat "$answer"
            echo
            if [ "$1" != 200 ]; then
              echo "greptimedb-schema: $2 answered HTTP $1" >&2
              exit 1
            fi
          }
          database_sql() {
            local status
            status="$(printf 'user = "admin:%s"\n' "$password" |
              curl --silent --show-error --config - --output "$answer" --write-out '%{http_code}' \
                --data-urlencode "sql=$2" "${httpUrl}/v1/sql?db=$1")"
            expect_200 "$status" "the statement on $1"
          }
          upload_pipeline() {
            local status
            status="$(printf 'user = "admin:%s"\n' "$password" |
              curl --silent --show-error --config - --output "$answer" --write-out '%{http_code}' \
                --form "file=@$3" "${httpUrl}/v1/pipelines/$2?db=$1")"
            expect_200 "$status" "pipeline $2 on $1"
          }

          ${lib.concatMapStringsSep "\n" (
            table: "database_sql ${lib.escapeShellArg table.database} ${lib.escapeShellArg table.statement}"
          ) tableStatements}
          ${lib.concatMapStringsSep "\n" (
            pipeline:
            "upload_pipeline ${lib.escapeShellArg pipeline.database} ${lib.escapeShellArg pipeline.name} ${pipeline.file}"
          ) pipelineUploads}
        ''
      );
```

Replace line 125:

```nix
          ${lib.concatMapStringsSep "\n" (statement: "sql ${lib.escapeShellArg statement}") schemaStatements}
```

with (nixfmt's layout of the same interpolation followed by `${objectsScript}`; the whitespace inside `${ }` is not part of the string):

```nix
          ${
            lib.concatMapStringsSep "\n" (statement: "sql ${lib.escapeShellArg statement}") schemaStatements
          }${objectsScript}
```

Insert after line 153 (the `};` closing `tableTtls`), before line 154 (the `};` closing `options.services.greptimedb`):

```nix
        tables = lib.mkOption {
          type = lib.types.attrsOf (lib.types.listOf lib.types.str);
          default = { };
          description = "Statements, per database, that the schema job issues through /v1/sql?db=<database> as admin after the databases, in order; any answer but 200 fails the job.";
        };
        pipelines = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
          default = { };
          description = "Ingest pipelines, as `<database>.<name>` mapped to the pipeline's YAML, that the schema job uploads to /v1/pipelines/<name>?db=<database> as admin after the tables; any answer but 200 fails the job, and each upload stores a new version.";
        };
```

`objectsScript` is the empty string when both options are empty, and it is appended to the existing last line rather than placed on a line of its own, so the empty case adds not even a newline (Step 10).
The status is read with `--write-out '%{http_code}'` and the body kept in a file under the unit's `PrivateTmp`, so a 2xx other than 200, which `--fail-with-body` would accept, also fails the job; GreptimeDB answers a failed statement with a non-200 status (`GreptimeTeam/greptimedb@v1.2.1:src/servers/src/http/result/error_result.rs:78-96`, `src/servers/src/error.rs:933-957`) and accepts a pipeline as `multipart/form-data` whose first field is the YAML (`src/servers/src/http/event.rs:137-175`), refusing names starting `greptime_` (`:293-325`).
The password still reaches curl only on stdin, as in the existing `sql` function.
During planning the same `objectsScript` was built into a `writeShellApplication` at the root pin, which runs `shellcheck`, and run against a loopback stub: with every answer 200 it issued `POST /v1/sql?db=devloop` as `application/x-www-form-urlencoded` and `POST /v1/pipelines/devloop_t?db=devloop` as `multipart/form-data`, both with an `Authorization` header, and exited 0; with the pipeline answered 400 it printed `greptimedb-schema: pipeline devloop_t on devloop answered HTTP 400` and exited 1.

- [ ] **Step 10: Show the script unchanged with both options empty (evaluation; tasks.md 2.3 verify, second half)**

Magnetite does not import `devloop-collection` yet, so both options are empty there.
Run:

```bash
{
  nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.greptimedb-schema.serviceConfig.ExecStart; echo
  nix eval --json .#nixosConfigurations.magnetite.config.services.greptimedb --apply 's: { inherit (s) tables pipelines; }'
  jj file show -r main@origin modules/nixos/greptimedb.nix | sha256sum
} 2>&1 | tee logs/s2-evidence/2.3-script-unchanged-$(date -u +%Y%m%dT%H%M%SZ).log
for log in logs/s2-evidence/2.0-base-*.log logs/s2-evidence/2.3-script-unchanged-*.log; do grep -c '^/nix/store/.*greptimedb-schema$' "$log"; done
grep -h '^/nix/store/.*greptimedb-schema$' logs/s2-evidence/2.0-base-*.log logs/s2-evidence/2.3-script-unchanged-*.log | sort -u | wc -l
```

Expected: the same path `P0` as Step 1, `{"pipelines":{},"tables":{}}`, then a count of at least `1` for every log the loop names, so neither log is empty, and `1` from the last command (one distinct script path in both logs).
Equal store paths mean equal derivations, so the script `origin/main` builds is the script this tree builds when neither option is set.

- [ ] **Step 11: Build the script of a configuration with one table and one pipeline (build; tasks.md 2.3 verify, first half)**

Run:

```bash
out=$(nix build --no-link --print-out-paths --impure --expr '
let
  f = builtins.getFlake (toString ./.);
  m = f.nixosConfigurations.magnetite.extendModules {
    modules = [ {
      services.greptimedb.tables.probe = [ "CREATE TABLE IF NOT EXISTS \"probe\" (\"ts\" TIMESTAMP(6) NOT NULL, TIME INDEX (\"ts\"))" ];
      services.greptimedb.pipelines.probe.probe_pipeline = "version: 2\n";
    } ];
  };
in m.pkgs.runCommand "greptimedb-schema-probe" { } "cp ${m.config.systemd.services.greptimedb-schema.serviceConfig.ExecStart} $out"' 2>&1 | tail -n 1)
{
  echo "$out"
  rg -n -F 'database_sql probe '\''CREATE TABLE IF NOT EXISTS "probe" ("ts" TIMESTAMP(6) NOT NULL, TIME INDEX ("ts"))'\''' "$out"
  rg -n 'upload_pipeline probe probe_pipeline /nix/store/[a-z0-9]{32}-greptimedb-pipeline-probe-probe_pipeline\.yaml$' "$out"
  rg -n -F 'if [ "$1" != 200 ]; then' "$out"
  rg -n -F '"${httpUrl}' "$out" || echo "no unexpanded interpolation"
  rg -n -F 'http://127.0.0.1:4000/v1/sql?db=$1' "$out"
  rg -n -F 'http://127.0.0.1:4000/v1/pipelines/$2?db=$1' "$out"
  rg -n "^sql 'ALTER DATABASE devloop" "$out"
} 2>&1 | tee logs/s2-evidence/2.3-script-probe-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: the store path, then one match each for the statement, the upload, the non-200 test, `no unexpanded interpolation`, the two URLs, and the `ALTER DATABASE devloop` line, whose line number is smaller than those of the `database_sql` and `upload_pipeline` lines, because tables and pipelines follow the databases.
The build runs `writeShellApplication`'s `shellcheck` over the extended script on an x86_64-linux builder.

- [ ] **Step 12: Import `devloop-collection` on magnetite (tasks.md 2.4)**

In `modules/machines/nixos/magnetite/default.nix`, in the `with flakeModules` list, insert directly after the line `        greptimedb` (line 72 today, line 73 after Task 1 inserted `deploy-record` after `base`):

```nix
        devloop-collection
```

- [ ] **Step 13: Evaluate magnetite's tables and pipelines (evaluation; tasks.md 2.4 verify)**

Run:

```bash
{
  nix eval --json .#nixosConfigurations.magnetite.config.services.greptimedb --apply 's: { tables = builtins.mapAttrs (_: l: map (x: builtins.head (builtins.match "CREATE TABLE IF NOT EXISTS \"([a-z_]+)\".*" (builtins.replaceStrings [ "\n" ] [ " " ] x))) l) s.tables; pipelines = builtins.mapAttrs (_: builtins.attrNames) s.pipelines; inherit (s) tableTtls; }'
  nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.greptimedb-schema.serviceConfig.ExecStart; echo
} 2>&1 | tee logs/s2-evidence/2.4-magnetite-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `{"pipelines":{"devloop":["devloop_batch_event","devloop_ci_attribute","devloop_ci_build","devloop_deploy_record"]},"tableTtls":{},"tables":{"devloop":["batch_event","ci_attribute","ci_build","deploy_record"]}}`, then a script path that differs from `P0`.

- [ ] **Step 14: Show the PostgreSQL-major assertion able to fail (evaluation, negative control)**

The two values the assertion relates are magnetite's evaluated `services.postgresql.package.version` and `flake.lib.devloopCollection.postgresqlMajor`; `postgresql_17` at the root pin is 17.11 (`nix eval` of the pin's `postgresql_17.version`, 2026-10-21).
Run:

```bash
{
  nix eval --impure --raw --expr 'let f = builtins.getFlake (toString ./.); m = f.nixosConfigurations.magnetite.extendModules { modules = [ ({ lib, pkgs, ... }: { services.postgresql.package = lib.mkForce pkgs.postgresql_17; }) ]; }; in builtins.concatStringsSep "\n" (map (a: a.message) (builtins.filter (a: !a.assertion) m.config.assertions))'; echo
  nix eval --impure --raw --expr 'let f = builtins.getFlake (toString ./.); m = f.nixosConfigurations.magnetite; in "failed assertions: " + builtins.concatStringsSep "\n" (map (a: a.message) (builtins.filter (a: !a.assertion) m.config.assertions))'; echo
  nix eval --raw .#nixosConfigurations.magnetite.config.services.postgresql.package.version; echo
  nix eval --raw .#.lib.devloopCollection.postgresqlMajor; echo
} 2>&1 | tee logs/s2-evidence/2.4-postgresql-major-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: the first command's output contains the line `devloop-collection: services.postgresql.package is PostgreSQL 17.11, but flake.lib.devloopCollection.postgresqlMajor is 16, the major checks.x86_64-linux.devloop-queries runs nixbot's migrations and the export queries on (design D14).`; the second prints `failed assertions: ` and nothing after it; then `16.15` and `16`.
If `extendModules` is missing on the clan-built configuration, stop and report; the fallback is a temporary branch commit with the `mkForce` line, evaluated and discarded.

- [ ] **Step 15: Write the fixtures and the renamed-column mutant (tasks.md 2.6)**

Create `modules/checks/devloop-queries/fixtures.sql` with exactly:

```sql
-- Fixture rows for checks.x86_64-linux.devloop-queries (design D14), loaded as
-- postgres after the nixbot input's migrations and the rendered grants. Every
-- time is relative to fixture_clock.t0, the load time truncated to the
-- second, so the export queries' `now() - interval '5 minutes'` sees the rows
-- at the ages the assertions name. fixture_clock is not one of the three
-- dumped tables and no reader is granted it.
CREATE TABLE fixture_clock AS SELECT date_trunc('second', now()) AS t0;

INSERT INTO projects (id, forge, forge_repo_id, owner, name, default_branch, url)
OVERRIDING SYSTEM VALUE
VALUES (1, 'gitea', '1', 'sciexp', 'vanixiets', 'main', 'https://gitea.example/sciexp/vanixiets');

INSERT INTO builds (id, project_id, number, commit_sha, branch, pr_number, status, created_at, started_at, finished_at, eval_duration_ms)
OVERRIDING SYSTEM VALUE
SELECT v.id, 1, v.number, v.commit_sha, v.branch, v.pr_number, v.status,
       c.t0 - v.created_ago, c.t0 - v.started_ago, c.t0 - v.finished_ago, v.eval_duration_ms
FROM fixture_clock c,
     (VALUES
       -- finished exactly at the old cursor: a row tied with the cursor
       (101, 1, '1111111111111111111111111111111111111111', 'pr-42', 42::bigint, 'succeeded',
        interval '30 minutes', interval '29 minutes', interval '10 minutes', 1234::bigint),
       -- finished 4 minutes ago, never started, no pull request
       (102, 2, '2222222222222222222222222222222222222222', 'gitea-mq/batch/7', NULL, 'failed',
        interval '20 minutes', NULL, interval '4 minutes', NULL),
       -- finished 7 minutes ago
       (103, 3, '3333333333333333333333333333333333333333', 'main', NULL, 'succeeded',
        interval '15 minutes', interval '14 minutes', interval '7 minutes', 10),
       -- not finished
       (104, 4, '4444444444444444444444444444444444444444', 'main', NULL, 'building',
        interval '2 minutes', interval '1 minute', NULL, NULL)
     ) AS v (id, number, commit_sha, branch, pr_number, status, created_ago, started_ago, finished_ago, eval_duration_ms);

INSERT INTO build_attributes (build_id, attr, system, drv_path, outputs, status, cached, error, started_at, finished_at, eval_wall_ms, eval_alloc_bytes)
SELECT v.build_id, v.attr, 'x86_64-linux', v.drv_path, v.outputs::jsonb, v.status, v.cached, v.error,
       c.t0 - v.started_ago, c.t0 - v.finished_ago, v.eval_wall_ms, v.eval_alloc_bytes
FROM fixture_clock c,
     (VALUES
       -- the abandonment marker, as modules/nixos/nixbot-abandon-optional-attributes.patch writes it
       (101, 'checks.x86_64-linux.marker', '/nix/store/aaaa-marker.drv', '{"out": "/nix/store/aaaa-marker"}',
        'ignored_failure', false, 'not finished when the required attributes had settled',
        interval '11 minutes', interval '10 minutes', 5, 1048576::bigint),
       -- other error text, no outputs
       (101, 'checks.x86_64-linux.other-ignored', '/nix/store/bbbb-other.drv', NULL,
        'ignored_failure', false, 'error: builder for /nix/store/bbbb-other.drv failed with exit code 1',
        interval '11 minutes', interval '10 minutes', NULL, NULL),
       -- a null error, finished 4 minutes ago
       (101, 'checks.x86_64-linux.null-error', '/nix/store/cccc-null.drv', '{"out": "/nix/store/cccc-null"}',
        'ignored_failure', true, NULL,
        NULL, interval '4 minutes', NULL, NULL),
       -- the marker inside longer text: abandoned only under a pattern match
       (101, 'checks.x86_64-linux.marker-in-text', '/nix/store/gggg-in-text.drv', NULL,
        'ignored_failure', false, 'abandoned: not finished when the required attributes had settled (retry 2)',
        interval '11 minutes', interval '10 minutes', NULL, NULL),
       -- the exact marker on a failed row: abandoned only without the status condition
       (101, 'checks.x86_64-linux.failed-marker', '/nix/store/hhhh-failed.drv', NULL,
        'failed', false, 'not finished when the required attributes had settled',
        interval '11 minutes', interval '10 minutes', NULL, NULL),
       (102, 'checks.x86_64-linux.recent', '/nix/store/dddd-recent.drv', '{"out": "/nix/store/dddd-recent"}',
        'succeeded', true, NULL,
        interval '5 minutes', interval '4 minutes', 7, 2097152),
       (103, 'checks.x86_64-linux.old', '/nix/store/eeee-old.drv', '{"out": "/nix/store/eeee-old"}',
        'failed', false, 'boom',
        interval '8 minutes', interval '7 minutes', 9, 4194304),
       (104, 'checks.x86_64-linux.unfinished', '/nix/store/ffff-unfinished.drv', NULL,
        'building', false, NULL,
        interval '1 minute', NULL, NULL, NULL)
     ) AS v (build_id, attr, drv_path, outputs, status, cached, error, started_ago, finished_ago, eval_wall_ms, eval_alloc_bytes);
```

Create `modules/checks/devloop-queries/mutant-rename-cached.sql` with exactly:

```sql
-- Mutant renameCached for checks.x86_64-linux.devloop-queries (design D14):
-- a later nixbot migration renaming a column the attribute query reads,
-- applied after the fixtures, so the attribute query must fail.
ALTER TABLE build_attributes RENAME COLUMN cached TO cached_renamed;
```

The fixtures write the columns nixbot's migrations declare `NOT NULL` without a default (`projects.forge`, `forge_repo_id`, `owner`, `name`, `default_branch`, `url`; `builds.number`, `commit_sha`, `branch`; `build_attributes.attr`; `Mic92/nixbot@d020013fa:nixbot/nixbot/migrations/0001_initial.sql:4-74`), use `OVERRIDING SYSTEM VALUE` because the ids are `GENERATED ALWAYS AS IDENTITY` (`0001_initial.sql:5`, `:26`), and include `eval_duration_ms`, `eval_wall_ms` and `eval_alloc_bytes`, which `0027_eval_stats.sql:1-6` adds.
The marker row's error text is written here as a literal, independently of `flake.lib.devloopCollection.abandonMarker`, so the `abandoned` clause relates the rendered query to the patch's text, which the check's marker clause binds to the constant.
Two rows must read `false` although they carry the marker (plan review F12): `marker-in-text` holds it inside longer text, which a pattern match would accept, and `failed-marker` holds it exactly on a `failed` row, which an expression without the status condition would accept.
The distinct error texts the fixtures store are read back as `postgres` by the check's `fixture_errors` query, the second value source of the error-cell clause (plan review F10).
The mutant migration is applied after the fixtures, as a later nixbot migration would be applied to a populated database, so its failure is the attribute query's, as DCI `A column the query reads is renamed` states.

- [ ] **Step 16: Write `devloop-queries` (tasks.md 2.6)**

Create `modules/checks/devloop-queries.nix` with exactly:

```nix
# checks.x86_64-linux.devloop-queries (design D14): binds the export queries
# and column grants of flake.lib.devloopCollection to the schema the nixbot
# input's migrations create, in a PostgreSQL started by nixpkgs'
# postgresqlTestHook with nixpkgs' postgresql_<postgresqlMajor>, the major
# devloop-collection's assertion binds to magnetite's package.
#
# Each run builds a fresh database: the input's migrations applied in
# lexical order, each with `psql -v ON_ERROR_STOP=1 --single-transaction`
# (the migrator's numeric order, one transaction per file, GR §1.3), the
# rendered grantSql, the fixture files, any mutant migration, then every
# entry of `roleQueries` as its role with its parameters bound through
# PREPARE … EXECUTE, and every entry of `assertions` over the results.
# Roles are LOGIN roles without a password, as on magnetite; the hook's
# initdb leaves local authentication at `trust`
# (postgres/postgres@REL_16_15:src/bin/initdb/initdb.c:2524-2532), so
# `psql -U <role>` opens a session as that role, and every privilege check
# runs against the role exactly as under magnetite's peer authentication.
#
# The clauses, each relating two independently defined values:
#   - marker: abandonMarker and the patch's production code (below);
#   - columns: the column names PostgreSQL returns for each rendered query
#     against the migrated schema, and the allow-list in schema.nix;
#   - abandoned: the query's value over fixture rows whose error text is
#     the patch's marker, the marker inside other text, other text and null,
#     and a failed row carrying the marker, and the fixture's expectation;
#   - error cells: every cell the attribute query returns, and the error
#     texts the fixtures stored, read back from the database;
#   - outputs_out: the query's value over a row whose outputs is null and
#     one whose outputs.out is a path, and the fixture's outputs;
#   - overlap: the rows returned for the fixture cursors, and the fixture
#     rows' ages relative to the cursors.
# Mutants, each of which must fail the run (D14): renameCached (a later
# migration renaming build_attributes.cached), selectError (a.error added to
# the attribute query's SELECT list), grantWithoutError (the collector's
# grant without build_attributes.error) and errorUnderAlias (a.error under
# the drv_path alias); the marker clause has two negative controls,
# markerLastCharacter and testLiteralsOnly. The real run's
# `pg_dump --schema-only` of the three tables is $out/schema.sql, compared
# at plan time with magnetite's dump.
#
# Task 4 extends `clockVars`, `fixtureFiles`, `roleQueries`, `assertions`
# and `mutants` with the reconcile's queries run as devloop-reconcile.
{
  self,
  inputs,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    let
      dc = self.lib.devloopCollection;
      inherit (self.lib.otelCollectorSchema.devloop) tables;
      postgresql = pkgs."postgresql_${dc.postgresqlMajor}";
      migrations = "${inputs.nixbot}/nixbot/nixbot/migrations";

      # psql variables set from fixture_clock before any query, each an SQL
      # timestamp expression over t0 rendered in the receiver's cursor form.
      clockVars = {
        cursor_old = "t0 - interval '10 minutes'";
        cursor_recent = "t0 - interval '1 minute'";
      };
      clockSql = pkgs.writeText "devloop-queries-clock.sql" (
        lib.concatStringsSep "\nUNION ALL\n" (
          lib.mapAttrsToList (
            name: expression:
            "SELECT '${name}=' || to_char((${expression}) AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"') FROM fixture_clock"
          ) clockVars
        )
        + ";\n"
      );

      # Loaded as postgres after the grants, in order.
      fixtureFiles = [ ./devloop-queries/fixtures.sql ];

      # Each entry is one prepared statement run as one role, once per
      # execution; its result is $work/$db/<name>.<execution>.tsv.
      roleQueries = queries: [
        {
          name = "ci_attribute";
          role = "opentelemetry-collector";
          types = [ "text" ];
          sql = queries.ci_attribute;
          executions = {
            old = [ ":'cursor_old'" ];
            recent = [ ":'cursor_recent'" ];
          };
        }
        {
          name = "ci_build";
          role = "opentelemetry-collector";
          types = [ "text" ];
          sql = queries.ci_build;
          executions = {
            old = [ ":'cursor_old'" ];
            recent = [ ":'cursor_recent'" ];
          };
        }
        # The error texts the fixtures stored, read back as postgres: the
        # second value source of the error-cell clause.
        {
          name = "fixture_errors";
          role = "postgres";
          types = [ ];
          sql = "SELECT DISTINCT error FROM build_attributes WHERE error IS NOT NULL ORDER BY 1";
          executions.all = [ ];
        }
      ];

      queryFile =
        query: execution: arguments:
        let
          list = items: lib.optionalString (items != [ ]) "(${lib.concatStringsSep ", " items})";
        in
        pkgs.writeText "devloop-queries-${query.name}-${execution}.sql" ''
          PREPARE ${query.name}${list query.types} AS
          ${query.sql};
          EXECUTE ${query.name}${list arguments};
        '';

      header =
        table: lib.concatStringsSep "\t" ([ "body" ] ++ map (column: column.name) tables.${table}.columns);

      # Each script runs with $db set and returns non-zero on failure.
      assertions = [
        {
          label = "ci_attribute returns body and the allow-listed columns in order";
          script = ''[ "$(head -n 1 "$(result ci_attribute old)")" = ${lib.escapeShellArg (header "ci_attribute")} ]'';
        }
        {
          label = "ci_build returns body and the allow-listed columns in order";
          script = ''[ "$(head -n 1 "$(result ci_build old)")" = ${lib.escapeShellArg (header "ci_build")} ]'';
        }
        {
          label = "abandoned is true only for the ignored_failure row whose error is exactly the marker";
          script = ''
            [ "$(value ci_attribute old attr checks.x86_64-linux.marker abandoned)" = true ] &&
              [ "$(value ci_attribute old attr checks.x86_64-linux.other-ignored abandoned)" = false ] &&
              [ "$(value ci_attribute old attr checks.x86_64-linux.null-error abandoned)" = false ] &&
              [ "$(value ci_attribute old attr checks.x86_64-linux.marker-in-text abandoned)" = false ] &&
              [ "$(value ci_attribute old attr checks.x86_64-linux.failed-marker abandoned)" = false ]
          '';
        }
        {
          label = "no ci_attribute cell holds any error text the fixtures stored";
          script = ''
            errors=$(result fixture_errors all)
            [ "$(tail -n +2 "$errors" | wc -l)" -ge 4 ] &&
              ! tail -q -n +2 "$(result ci_attribute old)" "$(result ci_attribute recent)" |
              grep -qF -f <(tail -n +2 "$errors")
          '';
        }
        {
          label = "outputs_out is empty for a null outputs";
          script = ''
            [ "$(value ci_attribute old attr checks.x86_64-linux.other-ignored outputs_out)" = "" ] &&
              [ "$(value ci_attribute old attr checks.x86_64-linux.recent outputs_out)" = /nix/store/dddd-recent ]
          '';
        }
        {
          label = "with a cursor 10 min old, the rows tied with the cursor and the rows 4 min old are returned";
          script = ''
            value ci_attribute old attr checks.x86_64-linux.marker attr >/dev/null &&
              value ci_attribute old attr checks.x86_64-linux.other-ignored attr >/dev/null &&
              value ci_attribute old attr checks.x86_64-linux.null-error attr >/dev/null &&
              value ci_attribute old attr checks.x86_64-linux.recent attr >/dev/null &&
              value ci_build old build_id 101 build_id >/dev/null &&
              value ci_build old build_id 102 build_id >/dev/null
          '';
        }
        {
          label = "with a cursor 1 min old, the rows 4 min old are returned and the rows 7 min old are not";
          script = ''
            value ci_attribute recent attr checks.x86_64-linux.recent attr >/dev/null &&
              value ci_build recent build_id 102 build_id >/dev/null &&
              ! value ci_attribute recent attr checks.x86_64-linux.old attr >/dev/null &&
              ! value ci_build recent build_id 103 build_id >/dev/null
          '';
        }
      ];

      replaceOnce =
        name: from: to: text:
        let
          replaced = builtins.replaceStrings [ from ] [ to ] text;
        in
        assert lib.assertMsg (replaced != text) "devloop-queries: mutant ${name} matched nothing";
        replaced;

      real = {
        inherit (dc) queries grantSql;
        afterFixtures = [ ];
      };
      mutants = {
        renameCached = real // {
          afterFixtures = [ ./devloop-queries/mutant-rename-cached.sql ];
        };
        selectError = real // {
          queries = dc.queries // {
            ci_attribute =
              replaceOnce "selectError" "SELECT '' AS \"body\",\n" "SELECT '' AS \"body\",\n  a.error,\n"
                dc.queries.ci_attribute;
          };
        };
        grantWithoutError = real // {
          grantSql =
            replaceOnce "grantWithoutError" ''"cached", "error", "drv_path"'' ''"cached", "drv_path"''
              dc.grantSql;
        };
        errorUnderAlias = real // {
          queries = dc.queries // {
            ci_attribute =
              replaceOnce "errorUnderAlias" ''coalesce((a.drv_path)::text, ''') AS "drv_path"''
                ''coalesce((a.error)::text, ''') AS "drv_path"''
                dc.queries.ci_attribute;
          };
        };
      };

      # The marker clause (design D13, D15; plan review F11): the two values
      # are flake.lib.devloopCollection.abandonMarker and the text of the
      # nixbot patch magnetite applies. The marker must appear in the
      # patch's production code, the three added lines of outcome_status
      # (modules/nixos/nixbot-abandon-optional-attributes.patch:145-147), not
      # merely somewhere in the patch, where its test literals (:379, :451)
      # would satisfy a bare search.
      patchText = builtins.readFile ../nixos/nixbot-abandon-optional-attributes.patch;
      patchLines = lib.splitString "\n" patchText;
      productionContext =
        marker:
        lib.concatStringsSep "\n" [
          "+        return AttributeStatus.ignored_failure, ("
          "+            \"${marker}\""
          "+            if outcome == BuildOutcome.abandoned"
        ];
      markerHolds = text: marker: lib.hasInfix (productionContext marker) text;
      lastCharacterChanged =
        let
          stem = lib.substring 0 (lib.stringLength dc.abandonMarker - 1) dc.abandonMarker;
        in
        stem + (if lib.hasSuffix "x" dc.abandonMarker then "y" else "x");
      testLiterals = map (number: lib.elemAt patchLines (number - 1)) [
        379
        451
      ];
      markerClauses =
        assert lib.assertMsg (lib.all (line: lib.hasInfix "\"${dc.abandonMarker}\"" line) testLiterals)
          "devloop-queries: lines 379 and 451 of the abandonment patch no longer hold the marker's test literals; update testLiterals";
        [
          {
            label = "ok: the patch's production code returns abandonMarker as an abandoned attribute's error";
            holds = markerHolds patchText dc.abandonMarker;
          }
          {
            label = "mutant markerLastCharacter rejected: the production context with the marker's last character changed is not in the patch";
            holds = !markerHolds patchText lastCharacterChanged;
          }
          {
            label = "mutant testLiteralsOnly rejected: the patch's test literals (:379, :451) alone do not hold the production context";
            holds = !markerHolds (lib.concatStringsSep "\n" testLiterals) dc.abandonMarker;
          }
        ];

      # run_<name>: builds database <db>, runs every query and assertion;
      # returns 1 at the first failure.
      runFunction = name: db: run: ''
        run_${name}() {
          local db=${db}
          createdb -U postgres "$db" || return 1
          mkdir -p "$work/$db"
          for migration in ${migrations}/*.sql; do
            psql -X -q -v ON_ERROR_STOP=1 --single-transaction -U postgres -d "$db" -f "$migration" || return 1
          done
          sql_as postgres "$db" ${pkgs.writeText "devloop-queries-grants.sql" run.grantSql} || return 1
          ${lib.concatMapStrings (file: ''
            sql_as postgres "$db" ${file} || return 1
          '') (fixtureFiles ++ run.afterFixtures)}
          psql -X -q -A -t -v ON_ERROR_STOP=1 -U postgres -d "$db" -f ${clockSql} > "$work/$db/clock" || return 1
          clock_args=()
          while IFS= read -r line; do clock_args+=(-v "$line"); done < "$work/$db/clock"
          ${lib.concatMapStrings (
            query:
            lib.concatStrings (
              lib.mapAttrsToList (execution: arguments: ''
                psql -X -q -A -F "$tab" -P footer=off -v ON_ERROR_STOP=1 "''${clock_args[@]}" \
                  -U ${lib.escapeShellArg query.role} -d "$db" -f ${queryFile query execution arguments} \
                  > "$(result ${query.name} ${execution})" || return 1
              '') query.executions
            )
          ) (roleQueries run.queries)}
          ${lib.concatMapStrings (assertion: ''
            if ! { ${assertion.script}
            }; then
              echo ${lib.escapeShellArg "FAIL: ${assertion.label}"}
              return 1
            fi
            echo ${lib.escapeShellArg "ok: ${assertion.label}"}
          '') assertions}
        }
      '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        devloop-queries = pkgs.stdenvNoCC.mkDerivation {
          name = "devloop-queries";
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;
          dontInstall = true;
          doCheck = true;
          nativeCheckInputs = [
            postgresql
            pkgs.postgresqlTestHook
          ];
          checkPhase = ''
            runHook preCheck
            work=$(mktemp -d)
            tab=$'\t'

            sql_as() { psql -X -q -v ON_ERROR_STOP=1 -U "$1" -d "$2" -f "$3"; }
            # result NAME EXECUTION: the result file of one execution in $db.
            result() { echo "$work/$db/$1.$2.tsv"; }
            # value NAME EXECUTION KEYCOLUMN KEY COLUMN: COLUMN of the first
            # row whose KEYCOLUMN is KEY; exit 1 when there is none.
            value() {
              awk -F "$tab" -v k="$3" -v key="$4" -v c="$5" '
                NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; if (!(k in col) || !(c in col)) exit 2; next }
                $col[k] == key { print $col[c]; found = 1; exit }
                END { if (!found) exit 1 }
              ' "$(result "$1" "$2")"
            }

            ${lib.concatMapStrings (clause: ''
              if [ ${lib.boolToString clause.holds} != true ]; then
                echo ${lib.escapeShellArg "FAIL: ${clause.label}"}
                exit 1
              fi
              echo ${lib.escapeShellArg clause.label}
            '') markerClauses}

            psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL'
            CREATE ROLE "opentelemetry-collector" LOGIN;
            CREATE ROLE "devloop-reconcile" LOGIN;
            SQL

            ${runFunction "real" "nixbot" real}
            ${lib.concatStrings (lib.mapAttrsToList (name: run: runFunction name "nixbot_${name}" run) mutants)}

            run_real
            mkdir -p "$out"
            pg_dump -U postgres --schema-only -t builds -t build_attributes -t projects nixbot > "$out/schema.sql"

            ${lib.concatMapStrings (name: ''
              if output=$(run_${name} 2>&1); then
                echo "$output"
                echo "FAIL: mutant ${name} was accepted"
                exit 1
              fi
              echo "mutant ${name} rejected: $(grep -m 1 -E 'FAIL: |ERROR: ' <<< "$output")"
            '') (lib.attrNames mutants)}

            runHook postCheck
          '';
        };
      };
    };
}
```

The check applies the migrations lexically, each file with `psql -v ON_ERROR_STOP=1 --single-transaction`, as the migrator does in version order with one transaction per file (`Mic92/nixbot@d020013fa:nixbot/nixbot/migrations.py:46-70`, `:125-155`).
Step 22 decides whether that stands: only if its diff with magnetite's dump is non-empty, make these two changes, and nothing else, then rerun Steps 17 to 22.
Add after the `migrations = …;` binding:

```nix
      # nixbot's own migrator (Step 22's diff chose it): one transaction per
      # file in version order, recorded in schema_migrations
      # (Mic92/nixbot@d020013fa:nixbot/nixbot/migrations.py:97-165).
      nixbotPython = pkgs.python3.withPackages (_: [ inputs.nixbot.packages.${system}.nixbot ]);
```

and replace the three lines of the migration loop:

```nix
          for migration in ${migrations}/*.sql; do
            psql -X -q -v ON_ERROR_STOP=1 --single-transaction -U postgres -d "$db" -f "$migration" || return 1
          done
```

with:

```nix
          ${nixbotPython}/bin/python3 -c 'import asyncio, sys; from nixbot.migrations import apply_migrations; asyncio.run(apply_migrations(sys.argv[1]))' \
            "postgresql://postgres@/$db?host=$PGHOST" || return 1
```

`nixbot` at the pin is a `buildPythonPackage` depending on `asyncpg` (`Mic92/nixbot@d020013fa:packages/nixbot.nix:1-40`), so `python3.withPackages` can import `nixbot.migrations` `[INFERENCE]`, confirmed by Step 20's build, whose log then shows no `psql:` migration lines.
With an empty diff in Step 22 the file stays as written above.

The marker clause (design D13, D15 as amended by plan review F11) relates two independently defined values, `flake.lib.devloopCollection.abandonMarker` and the text of `modules/nixos/nixbot-abandon-optional-attributes.patch`, which magnetite's nixbot applies.
It requires the patch's production code, the three added lines of `outcome_status` at `:145-147`, joined by newlines with the marker in the middle one, not the bare literal, which the patch's tests also carry at `:379` and `:451`.
Its two negative controls run the same test with the marker's last character changed, which must not hold, and over the two test lines alone, which must not hold either; an evaluation assertion first requires those two lines to hold the quoted marker, so the second control cannot pass on lines that have drifted.
The clause and its controls are evaluated when the check's derivation is instantiated, so a failure stops evaluation in CI with the clause's label, and a pass prints the three lines at the start of the build.

How the check authenticates: `postgresqlTestHook` at the root pin runs `initdb --encoding=UTF8 -U postgres` with no `--auth` (`NixOS/nixpkgs@ac1faec44836:pkgs/by-name/po/postgresqlTestHook/postgresql-test-hook.sh:57`, read in its store copy `/nix/store/l9sdkpnv33hmdr49q2nhahph8bpjmc9s-source`, magnetite's `pkgs.path`), and `initdb` then sets local and host authentication to `trust` (`postgres/postgres@REL_16_15:src/bin/initdb/initdb.c:2524-2532`); the socket lives under `$NIX_BUILD_TOP/run/postgresql` with TCP disabled (`postgresql-test-hook.sh:20-24`, `:61-68`), so only the build's own processes reach it.
Peer authentication is not available in the sandbox, because the build runs as one build user; `psql -U opentelemetry-collector` therefore opens a session whose `session_user` and `current_user` are that `LOGIN` role, and every column-privilege check is made against it exactly as it is under magnetite's peer rule, which only decides which role a connection becomes.
The peer admission itself is world assumption A45, observed at D3 (`tasks.md` 7.4), not here.
`$1` is bound by `PREPARE <name>(text) AS …; EXECUTE <name>(:'cursor_old');`, the cursor arriving as text as the receiver stores and binds it, and the query casting it with `$1::timestamptz`.
The cursors are `fixture_clock.t0` minus 10 min and minus 1 min, rendered in the receiver's cursor format; the rows tied with the old cursor finished exactly at `t0 - 10 min`.
With the recent cursor the bound is `now() - 5 min` at query time, a few seconds after `t0`, so the rows finished at `t0 - 4 min` are inside it and those at `t0 - 7 min` outside; the build would have to take more than a minute between loading the fixtures and running the queries for the 4-minute rows to fall out, which would fail the check rather than pass it.

- [ ] **Step 17: Show the check failing at evaluation before 2.5 (RED, evaluation)**

Run:

```bash
jj st --no-pager >/dev/null
nix eval --raw '.#.checks.x86_64-linux.devloop-queries.drvPath' 2>&1 | tee logs/s2-evidence/2.6-check-red-$(date -u +%Y%m%dT%H%M%SZ).log | rg -o "attribute '(grantSql|queries)' missing"
```

Expected: `attribute 'grantSql' missing` (the planning rehearsal's first missing attribute; `attribute 'queries' missing` is the same failure), because `flake.lib.devloopCollection` holds only `abandonMarker`, `ddl` and `pipelines`.

- [ ] **Step 18: Render the nixbot side (tasks.md 2.5)**

In `modules/nixos/devloop-collection.nix` as Step 6 wrote it, insert after line 149 (`  ) tables;`, the end of `pipelines`) these lines, the first of them blank:

```nix

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
```

and replace the lines

```nix
  flake.lib.devloopCollection = {
    inherit
      abandonMarker
      postgresqlMajor
      ddl
      pipelines
      ;
  };
```

with:

```nix
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
  };
```

The whole file after this task is exactly:

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
  };

  flake.modules.nixos.devloop-collection =
    { config, ... }:
    {
      assertions = [
        {
          assertion =
            !config.services.postgresql.enable
            || lib.versions.major config.services.postgresql.package.version == postgresqlMajor;
          message = "devloop-collection: services.postgresql.package is PostgreSQL ${config.services.postgresql.package.version}, but flake.lib.devloopCollection.postgresqlMajor is ${postgresqlMajor}, the major checks.x86_64-linux.devloop-queries runs nixbot's migrations and the export queries on (design D14).";
        }
      ];
      services.greptimedb.tables.devloop = lib.attrValues ddl;
      services.greptimedb.pipelines.devloop = lib.mapAttrs' (
        name: pipeline: lib.nameValuePair "devloop_${name}" pipeline
      ) pipelines;
    };
}
```

`abandoned` is equality on the status and the marker, never a pattern (design D6); `error` is read only inside that comparison, so it is granted to the collector but never selected (design D10); `outputs_out` is `outputs ->> 'out'`, `project` `owner || '/' || name` (design D6; A5:57).

- [ ] **Step 19: Read the rendered queries and grants (evaluation)**

Run:

```bash
{
  nix eval --raw .#.lib.devloopCollection.queries.ci_attribute; echo
  nix eval --raw .#.lib.devloopCollection.queries.ci_build; echo
  nix eval --raw .#.lib.devloopCollection.grantSql
  nix eval --json .#.lib.devloopCollection.selects --apply 's: builtins.mapAttrs (_: builtins.attrNames) s'
} 2>&1 | tee logs/s2-evidence/2.5-queries-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected, the attribute query:

```sql
SELECT '' AS "body",
  coalesce((b.id)::text, '') AS "build_id",
  coalesce((a.attr)::text, '') AS "attr",
  coalesce((a.system)::text, '') AS "system",
  coalesce((a.status)::text, '') AS "status",
  coalesce((a.cached)::text, '') AS "cached",
  coalesce(((a.status = 'ignored_failure' AND a.error IS NOT DISTINCT FROM 'not finished when the required attributes had settled'))::text, '') AS "abandoned",
  coalesce((a.drv_path)::text, '') AS "drv_path",
  coalesce((a.outputs ->> 'out')::text, '') AS "outputs_out",
  coalesce(to_char(a.started_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), '') AS "started_at",
  coalesce(to_char(a.finished_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), '') AS "finished_at",
  coalesce((a.eval_wall_ms)::text, '') AS "eval_wall_ms",
  coalesce((a.eval_alloc_bytes)::text, '') AS "eval_alloc_bytes",
  coalesce((b.commit_sha)::text, '') AS "commit_sha",
  coalesce((b.branch)::text, '') AS "branch",
  coalesce((b.pr_number)::text, '') AS "pr_number",
  coalesce((p.owner || '/' || p.name)::text, '') AS "project"
FROM build_attributes a JOIN builds b ON b.id = a.build_id JOIN projects p ON p.id = b.project_id
WHERE a.finished_at >= least($1::timestamptz, now() - interval '5 minutes')
ORDER BY a.finished_at
LIMIT 10000
```

the build query:

```sql
SELECT '' AS "body",
  coalesce((b.id)::text, '') AS "build_id",
  coalesce(to_char(b.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), '') AS "created_at",
  coalesce(to_char(b.started_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), '') AS "started_at",
  coalesce(to_char(b.finished_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), '') AS "finished_at",
  coalesce((b.eval_duration_ms)::text, '') AS "eval_duration_ms",
  coalesce((b.status)::text, '') AS "status",
  coalesce((b.pr_number)::text, '') AS "pr_number",
  coalesce((b.branch)::text, '') AS "branch"
FROM builds b
WHERE b.finished_at >= least($1::timestamptz, now() - interval '5 minutes')
ORDER BY b.finished_at
LIMIT 10000
```

the grants:

```sql
GRANT SELECT ("build_id", "attr", "finished_at") ON "build_attributes" TO "devloop-reconcile";
GRANT SELECT ("id", "branch", "finished_at") ON "builds" TO "devloop-reconcile";
GRANT SELECT ("build_id", "attr", "system", "status", "cached", "error", "drv_path", "outputs", "started_at", "finished_at", "eval_wall_ms", "eval_alloc_bytes") ON "build_attributes" TO "opentelemetry-collector";
GRANT SELECT ("id", "project_id", "commit_sha", "branch", "pr_number", "status", "created_at", "started_at", "finished_at", "eval_duration_ms") ON "builds" TO "opentelemetry-collector";
GRANT SELECT ("id", "owner", "name") ON "projects" TO "opentelemetry-collector";
```

and the `selects` key lists, which are the allow-list's columns of each table in attribute-name order.
Whether the queries run against nixbot's schema and return the allow-list is judged by Step 20, not here (tasks.md 2.5 verify: by 2.6).

- [ ] **Step 20: Build `devloop-queries` (GREEN, build; tasks.md 2.6 verify)**

Run:

```bash
jj st --no-pager >/dev/null
nix build --no-link --print-out-paths -L '.#.checks.x86_64-linux.devloop-queries' 2>&1 | tee logs/s2-evidence/2.6-devloop-queries-$(date -u +%Y%m%dT%H%M%SZ).log | rg '^devloop-queries> (ok:|FAIL|mutant)|^/nix/store/|error:'
```

Expected, in this order:

```
devloop-queries> ok: the patch's production code returns abandonMarker as an abandoned attribute's error
devloop-queries> mutant markerLastCharacter rejected: the production context with the marker's last character changed is not in the patch
devloop-queries> mutant testLiteralsOnly rejected: the patch's test literals (:379, :451) alone do not hold the production context
devloop-queries> ok: ci_attribute returns body and the allow-listed columns in order
devloop-queries> ok: ci_build returns body and the allow-listed columns in order
devloop-queries> ok: abandoned is true only for the ignored_failure row whose error is exactly the marker
devloop-queries> ok: no ci_attribute cell holds any error text the fixtures stored
devloop-queries> ok: outputs_out is empty for a null outputs
devloop-queries> ok: with a cursor 10 min old, the rows tied with the cursor and the rows 4 min old are returned
devloop-queries> ok: with a cursor 1 min old, the rows 4 min old are returned and the rows 7 min old are not
devloop-queries> mutant errorUnderAlias rejected: FAIL: no ci_attribute cell holds any error text the fixtures stored
devloop-queries> mutant grantWithoutError rejected: psql:/nix/store/…-devloop-queries-ci_attribute-old.sql:23: ERROR:  permission denied for table build_attributes
devloop-queries> mutant renameCached rejected: psql:/nix/store/…-devloop-queries-ci_attribute-old.sql:22: ERROR:  column a.cached does not exist
devloop-queries> mutant selectError rejected: FAIL: ci_attribute returns body and the allow-listed columns in order
/nix/store/…-devloop-queries
```

and no `error:` line.
Each clause's two value sources, named before its mutant:
- The column clause relates the column names PostgreSQL returns when it executes the rendered query against the migrated schema with the allow-list in `schema.nix`; `selectError` adds `a.error` to the SELECT list and is rejected by it.
- The marker clause relates `abandonMarker` with the patch's production code; `markerLastCharacter` and `testLiteralsOnly` are its negative controls, rejected at evaluation.
- The `abandoned` clause relates the query's value over five fixture rows with the fixture's marker literal, transcribed from the patch, and the other error texts; during planning a query matching the marker with `LIKE '%…%'` and one without the status condition were each run against the fixtures and each failed this clause, through the `marker-in-text` and `failed-marker` rows.
- The error-cell clause relates every cell the attribute query returns under both cursors with the error texts the fixtures stored, read back as `postgres` (at least four distinct texts, so the clause is not vacuous); `errorUnderAlias` puts `a.error` under the `drv_path` alias, which passes the column clause, and is rejected by it.
- The `outputs_out` clause relates the query's value with the fixture's `outputs` of a null row and a path row.
- The overlap clauses relate the rows returned for the two cursors with the fixture rows' ages; the second also requires the 4-minute rows under the recent cursor, which is the five-minute overlap itself and fails for a predicate anchored on `$1` alone.
- `renameCached` relates the attribute query's column references with the migrated schema after a later migration, and `grantWithoutError` the query's referenced columns with the rendered grants; each is rejected at the query by PostgreSQL itself.

During planning the check was rehearsed on aarch64-darwin with the files of Steps 15, 16 and 18, nixpkgs' `postgresql_16` 16.15 at the root pin, the hook, and the 37 migrations of `Mic92/nixbot@d020013fa` fetched with `gh api`; it printed exactly the fourteen lines above, with these store-path line numbers, in 15 s.
`nix log` of the output shows the hook's `initializing postgresql` and `setting up postgresql` before them.

- [ ] **Step 21: Record the evaluation cost (evaluation)**

Run:

```bash
{
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/devloop-queries-stats.json nix eval --option eval-cache false --raw '.#.checks.x86_64-linux.devloop-queries.drvPath'; echo
  jq '{bytes: .gc.totalBytes, cpu: .cpuTime}' /tmp/devloop-queries-stats.json
  echo 'method: NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/devloop-queries-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.devloop-queries.drvPath, .gc.totalBytes against 536870912 B'
} 2>&1 | tee logs/s2-evidence/2.6-devloop-queries-cost-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: a `/nix/store/…-devloop-queries.drv` path, then `bytes` below `536870912`.
The check reads `flake.lib` values, the nixbot input's path and nixpkgs' `postgresql_16`, and builds no NixOS configuration, so design D14's estimate of 0.12 to 0.2 GiB applies `[INFERENCE]`, measured here on landing.
If `bytes` exceeds 536870912, stop and report the figure; the check is not committed over budget.

- [ ] **Step 22: Compare the check's schema with magnetite's (command; tasks.md 2.6 verify)**

Run:

```bash
out=$(nix build --no-link --print-out-paths '.#.checks.x86_64-linux.devloop-queries')
cp "$out/schema.sql" logs/s2-evidence/2.6-schema-check.sql
logs/s2-evidence/1.2-normalise.sh < logs/s2-evidence/2.6-schema-check.sql > logs/s2-evidence/2.6-schema-check.norm.sql
{
  sha256sum logs/s2-evidence/2.6-schema-check.sql logs/s2-evidence/2.6-schema-check.norm.sql logs/s2-evidence/1.2-schema-magnetite.norm.sql
  diff logs/s2-evidence/1.2-schema-magnetite.norm.sql logs/s2-evidence/2.6-schema-check.norm.sql && echo "schema equals magnetite's"
} 2>&1 | tee logs/s2-evidence/2.6-schema-diff-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `schema equals magnetite's`, which keeps lexical application.
The normaliser is Task 1 Step 2's, which drops comments, blank lines, `SET` and `set_config` lines, `\restrict`/`\unrestrict` lines (whose keys differ per dump from pg_dump 16.10 on), ownership, `GRANT`/`REVOKE` and `COMMENT ON` lines, so the check's grants to its two roles do not count as a difference.
Magnetite's dump, `1.2-schema-magnetite.sql`, holds `pg_dump`'s stdout only, because magnetite's `psql` and `pg_dump` print a collation-version warning on stderr, and the check's `$out/schema.sql` is likewise `pg_dump`'s stdout alone, so neither side carries a warning line.
On a non-empty diff, apply Step 16's migrator alternative, rerun Steps 17 to 21, and run this step again: an empty diff then keeps the migrator, recorded with the first diff in this step's two logs, and a second non-empty diff means neither application reproduces magnetite's schema, so stop and report both diffs.

- [ ] **Step 23: Build the neighbouring checks and magnetite (build; tasks.md 2.4 verify)**

Run: `nix build --no-link '.#.checks.x86_64-linux.nixos-magnetite' '.#.checks.x86_64-linux.greptimedb-envelope' 2>&1 | tee logs/s2-evidence/2.4-builds-$(date -u +%Y%m%dT%H%M%SZ).log | tail -n 3`
Expected: both build, with no `error:` line.
`nixos-magnetite` builds magnetite's toplevel, including the extended `greptimedb-schema` script through `shellcheck`, and evaluates every magnetite assertion, the PostgreSQL-major assertion among them; `greptimedb-envelope` still passes, because the tables add no `ttl` and `tableTtls` stays empty.

- [ ] **Step 24: Format**

Run:

```bash
{
  nix fmt -- modules/clan/services/otel-collector/schema.nix modules/nixos/devloop-collection.nix modules/nixos/greptimedb.nix modules/machines/nixos/magnetite/default.nix modules/checks/devloop-queries.nix
  nix fmt -- --fail-on-change && echo fmt-clean
} 2>&1 | tee logs/s2-evidence/2.8-fmt-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: the last line is `fmt-clean`.
Every Nix text above was run through the root pin's `nixfmt` during planning and is stable under it; if the first command changed a file anyway, rerun Steps 13 and 20 and expect the same output.

- [ ] **Step 25: Write the pre-D2 compile check (tasks.md 2.7)**

Create `logs/s2-evidence/2.7-precheck.sh` (git-ignored) with exactly this content, then `chmod +x logs/s2-evidence/2.7-precheck.sh`:

```bash
#!/usr/bin/env bash
# tasks.md 2.7 (plan review F5): compile the rendered devloop tables and
# pipelines on a throwaway GreptimeDB 1.2.1 on magnetite before D2, and write
# one OTLP log record per table through otelcol-contrib 0.155.0 with the
# production headers as the `collector` (wo) account. Run as the operator
# user on magnetite, as logs/s2/spike-dedup.md §Environment ran the spike:
# user units, loopback ports 24000/24001 and 24318-24321, local File storage
# under /tmp. Usage: 2.7-precheck.sh GREPTIMEDB_BIN_PATH OTELCOL_CONTRIB_PATH
# with the rendered inputs in /tmp/s2-precheck-inputs.
set -euo pipefail
greptime="$1/bin/greptime"
otelcol="$2/bin/otelcol-contrib"
in=/tmp/s2-precheck-inputs
w=/tmp/s2-precheck
tables=(ci_attribute ci_build batch_event deploy_record)

cleanup() {
  systemctl --user stop s2-precheck-otelcol s2-precheck-greptimedb 2>/dev/null || true
  rm -rf "$w"
}
trap cleanup EXIT

rm -rf "$w"
mkdir -m 0700 "$w"
umask 077
"$greptime" --version
"$otelcol" --version

# Throwaway accounts; the values stay in files and never reach an argv.
head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$w/admin-password"
head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$w/collector-password"
printf 'admin:rw=%s\ncollector:wo=%s\n' "$(< "$w/admin-password")" "$(< "$w/collector-password")" > "$w/users"

cat > "$w/greptimedb.toml" <<EOF
enable_telemetry = false
user_provider = "static_user_provider:file:$w/users"

[http]
addr = "127.0.0.1:24000"

[grpc]
bind_addr = "127.0.0.1:24001"

[mysql]
enable = false

[postgres]
enable = false

[influxdb]
enable = false

[opentsdb]
enable = false

[jaeger]
enable = false

[prom_store]
enable = false

[logging]
dir = "$w/logs"

[storage]
type = "File"
data_home = "$w/data"
EOF

systemd-run --user --unit=s2-precheck-greptimedb --collect "$greptime" standalone start --config-file "$w/greptimedb.toml"
attempt=0
until curl --silent --fail --output /dev/null http://127.0.0.1:24000/health; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 60 ]; then
    echo "FAIL: the throwaway store did not answer /health within 120 s"
    exit 1
  fi
  sleep 2
done

# admin ARGS...: curl as admin, the password on stdin; prints the status.
admin() {
  printf 'user = "admin:%s"\n' "$(< "$w/admin-password")" |
    curl --silent --show-error --config - --output "$w/answer" --write-out '%{http_code}' "$@"
}
# expect_200 STATUS WHAT
expect_200() {
  cat "$w/answer"
  echo
  if [ "$1" != 200 ]; then
    echo "FAIL: $2 answered HTTP $1"
    exit 1
  fi
  echo "ok: $2 answered 200"
}

status=$(admin --data-urlencode "sql=CREATE DATABASE IF NOT EXISTS devloop WITH (ttl = '365d')" http://127.0.0.1:24000/v1/sql)
expect_200 "$status" "CREATE DATABASE devloop"
for t in "${tables[@]}"; do
  status=$(admin --data-urlencode "sql@$in/ddl-$t.sql" "http://127.0.0.1:24000/v1/sql?db=devloop")
  expect_200 "$status" "ddl.$t"
done
for t in "${tables[@]}"; do
  status=$(admin --form "file=@$in/pipeline-$t.yaml" "http://127.0.0.1:24000/v1/pipelines/devloop_$t?db=devloop")
  expect_200 "$status" "pipeline devloop_$t"
done

# One receiver per table, one exporter per table with the production
# headers (design D4, D5), no retry and no queue, so a refused write is
# answered to the sender instead of being retried.
{
  echo 'extensions:'
  echo '  basicauth/store:'
  echo '    client_auth:'
  echo '      username: collector'
  echo "      password_file: $w/collector-password"
  echo 'receivers:'
  port=24318
  for t in "${tables[@]}"; do
    echo "  otlp/$t:"
    echo '    protocols:'
    echo '      http:'
    echo "        endpoint: 127.0.0.1:$port"
    port=$((port + 1))
  done
  echo 'exporters:'
  for t in "${tables[@]}"; do
    echo "  otlp_http/devloop_$t:"
    echo '    endpoint: http://127.0.0.1:24000/v1/otlp'
    echo '    auth:'
    echo '      authenticator: basicauth/store'
    echo '    retry_on_failure:'
    echo '      enabled: false'
    echo '    sending_queue:'
    echo '      enabled: false'
    echo '    headers:'
    echo '      x-greptime-db-name: devloop'
    echo "      x-greptime-log-table-name: $t"
    echo "      x-greptime-pipeline-name: devloop_$t"
    echo '      x-greptime-hints: auto_create_table=false'
  done
  echo 'service:'
  echo '  extensions: [basicauth/store]'
  echo '  telemetry:'
  echo '    metrics:'
  echo '      level: none'
  echo '  pipelines:'
  for t in "${tables[@]}"; do
    echo "    logs/$t:"
    echo "      receivers: [otlp/$t]"
    echo "      exporters: [otlp_http/devloop_$t]"
  done
} > "$w/otelcol.yaml"
systemd-run --user --unit=s2-precheck-otelcol --collect "$otelcol" "--config=file:$w/otelcol.yaml"
sleep 5

# One record per table, every value a string attribute as the S2 receivers
# emit, an empty string standing for a null; batch_event's time is the
# record's timeUnixNano, as the journald receiver sets it.
attrs() {
  local sep=""
  printf '['
  while [ "$#" -gt 0 ]; do
    printf '%s{"key": "%s", "value": {"stringValue": "%s"}}' "$sep" "$1" "$2"
    sep=", "
    shift 2
  done
  printf ']'
}
record() {
  printf '{"resourceLogs": [{"resource": {"attributes": []}, "scopeLogs": [{"scope": {"name": "s2-precheck"}, "logRecords": [{%s"observedTimeUnixNano": "1792600000000000000", "attributes": %s}]}]}]}' "$1" "$2"
}
record '' "$(attrs build_id 101 attr checks.x86_64-linux.precheck system x86_64-linux status succeeded cached false abandoned false drv_path /nix/store/aaaa-precheck.drv outputs_out "" started_at "" finished_at 2026-10-21T10:00:00.123456Z eval_wall_ms 5 eval_alloc_bytes "" commit_sha 1111111111111111111111111111111111111111 branch pr-42 pr_number 42 project sciexp/vanixiets)" > "$w/ci_attribute.json"
record '' "$(attrs build_id 101 created_at 2026-10-21T09:00:00.000001Z started_at "" finished_at 2026-10-21T10:00:00Z eval_duration_ms "" status failed pr_number "" branch gitea-mq/batch/7)" > "$w/ci_build.json"
record '"timeUnixNano": "1792576800123456000", ' "$(attrs batch 180 msg "batch done" build "" sha "" failed_check "" members 2 landed 2 ejected 0 builds 1 flaky false)" > "$w/batch_event.json"
record '' "$(attrs host magnetite closure /nix/store/bbbb-nixos-system previous_closure "" ts 2026-10-21T10:00:00Z)" > "$w/deploy_record.json"

port=24318
for t in "${tables[@]}"; do
  status=$(curl --silent --show-error --output "$w/answer" --write-out '%{http_code}' \
    -H 'Content-Type: application/json' --data-binary "@$w/$t.json" "http://127.0.0.1:$port/v1/logs")
  expect_200 "$status" "the OTLP write to $t through otlp_http/devloop_$t"
  port=$((port + 1))
done

for t in "${tables[@]}"; do
  status=$(admin --data-urlencode "sql=SELECT count(*) FROM \"$t\"" "http://127.0.0.1:24000/v1/sql?db=devloop")
  expect_200 "$status" "count of $t"
  [ "$(jq -c '.output[0].records.rows' "$w/answer")" = '[[1]]' ] || { echo "FAIL: $t does not hold exactly one row"; exit 1; }
  echo "ok: $t holds one row"
done
status=$(admin --data-urlencode 'sql=SELECT "batch", "msg", "flaky", "build", "ts" FROM "batch_event"' "http://127.0.0.1:24000/v1/sql?db=devloop")
expect_200 "$status" "read of batch_event"
[ "$(jq -c '.output[0].records.rows' "$w/answer")" = '[[180,"batch done",false,null,1792576800123456]]' ] || { echo "FAIL: batch_event's row is not (180, batch done, false, null, record time)"; exit 1; }
echo "ok: batch_event's ts is the record time and an empty attribute is null"
failed=$(journalctl --user -u s2-precheck-otelcol --no-pager -o cat | grep -c 'Exporting failed' || true)
[ "$failed" = 0 ] || { echo "FAIL: the collector logged $failed failed exports"; exit 1; }
echo "ok: the collector logged no failed export"
echo "precheck passed"
```

It follows `logs/s2/spike-dedup.md` §Environment: user units started with `systemd-run --user`, HTTP on `127.0.0.1:24000`, gRPC on `127.0.0.1:24001`, every other protocol disabled, local `File` storage under `/tmp`, and cleanup by stopping the units and removing the directory, here on every exit through the trap.
Unlike the spike it runs a static user provider with the production accounts' permissions, `admin` (`rw`) and `collector` (`wo`), in the users-file format magnetite's generator writes (`modules/machines/nixos/magnetite/default.nix:555`), so the four pipelines are uploaded as `admin` and written through as `collector`, as in production.
The exporters carry the production headers of design D4 and D5 and authenticate with `basicauth/store` as the collector role does (`modules/clan/services/otel-collector/flake-module.nix:355-357`, `:387-391`), with retry and queue disabled so a refused write is answered to the sender.
The throwaway passwords are random, kept in mode-0600 files under the mode-0700 directory, and reach `curl` and the collector only on stdin or by file, never on an argv.
The records carry every value as a string attribute with `""` for null, as the S2 receivers emit them, and `batch_event`'s time as `timeUnixNano`, as the journald receiver sets it.
That the OTLP receiver answers non-200 when its synchronous exporter's write is refused is `[INFERENCE]`; the per-table row counts and the collector's `Exporting failed` count decide the step either way.
The exact JSON of the `batch_event` read, `[[180,"batch done",false,null,1792576800123456]]` with the time index in microseconds, is `[INFERENCE]` from the spike's `finished_at` read (`logs/s2/spike-dedup.md:175-180`), confirmed by this step; on a mismatch on that line alone, the printed answer shows the stored row.
During planning the script passed `bash -n` and `shellcheck` at the root pin, its four generated payloads parsed with `jq`, and `jq` and a running user manager were confirmed on magnetite (`/etc/profiles/per-user/cameron/bin/jq`, `systemctl --user is-system-running` printing `running`).

- [ ] **Step 26: Run the pre-D2 compile check on magnetite (runtime, magnetite; tasks.md 2.7 verify)**

Run from `$REPO`, with this task's tree, before the commit:

```bash
in=/tmp/s2-precheck-inputs
rm -rf "$in" && mkdir -p "$in"
for t in ci_attribute ci_build batch_event deploy_record; do
  nix eval --raw ".#.lib.devloopCollection.ddl.$t" > "$in/ddl-$t.sql"
  nix eval --raw ".#.lib.devloopCollection.pipelines.$t" > "$in/pipeline-$t.yaml"
done
greptimedb=$(nix eval --raw .#nixosConfigurations.magnetite.config.services.greptimedb.package)
otelcol=$(nix eval --raw .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.package)
ssh magnetite.zt "rm -rf $in /tmp/2.7-precheck.sh && test -x $greptimedb/bin/greptime && test -x $otelcol/bin/otelcol-contrib" && echo "store paths present on magnetite"
scp -rq "$in" logs/s2-evidence/2.7-precheck.sh magnetite.zt:/tmp/
ssh magnetite.zt "bash /tmp/2.7-precheck.sh $greptimedb $otelcol; status=\$?; rm -rf $in /tmp/2.7-precheck.sh; exit \$status" 2>&1 | tee logs/s2-evidence/2.7-precheck-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `store paths present on magnetite`; the two version lines naming GreptimeDB 1.2.1 and `otelcol-contrib version 0.155.0`; then, in order, `ok: CREATE DATABASE devloop answered 200`, `ok: ddl.<table> answered 200` and `ok: pipeline devloop_<table> answered 200` for each of the four tables, `ok: the OTLP write to <table> through otlp_http/devloop_<table> answered 200` for each, `ok: count of <table> answered 200` and `ok: <table> holds one row` for each, `ok: read of batch_event answered 200`, `ok: batch_event's ts is the record time and an empty attribute is null`, `ok: the collector logged no failed export`, and the last line `precheck passed`.
The store and collector are the paths magnetite's configuration evaluates, the versions running there since S1; if `test -x` fails because this tree's paths are not yet on magnetite, run `nix copy --to ssh-ng://magnetite.zt "$greptimedb" "$otelcol"` after `nix build --no-link "$greptimedb" "$otelcol"`, which stibnite routes to magnetite, and repeat.
Any `FAIL:` line stops the task before the commit: a statement, pipeline or write that the real store refuses is fixed in Steps 6 to 9 and this step is run again.
The step changes nothing on magnetite but the operator's user units and `/tmp` directories, which the trap and the last command remove; `ssh magnetite.zt 'systemctl --user list-units --all "s2-precheck*"; ls -d /tmp/s2-precheck /tmp/s2-precheck-inputs'` afterwards prints `0 loaded units listed.` and two `No such file or directory` lines.

- [ ] **Step 27: Tick 2.1–2.7**

In `openspec/changes/stand-up-devloop-collection/tasks.md`, with the edit tool, change only the leading `- [ ]` of the lines beginning `- [ ] 2.1` to `- [ ] 2.7` to `- [x]`; 2.8 is ticked by the orchestrator when nixbot reports the pull request green, and 2.9 after Step 31.
Run: `rg -n '^- \[x\] 2\.[1-7] ' openspec/changes/stand-up-devloop-collection/tasks.md | wc -l`
Expected: `7`.

- [ ] **Step 28: Commit**

Run:

```bash
jj new --no-edit -r main@origin -m 'feat(devloop): the devloop allow-list, tables, pipelines and devloop-queries'
change="$(jj log --no-graph -r 'children(main@origin) & empty() & description(substring:"feat(devloop): the devloop allow-list, tables, pipelines and devloop-queries")' -T 'change_id.shortest(8)')"
jj squash --from @ --into "$change" --keep-emptied --use-destination-message -- \
  modules/clan/services/otel-collector/schema.nix \
  modules/nixos/devloop-collection.nix \
  modules/nixos/greptimedb.nix \
  modules/machines/nixos/magnetite/default.nix \
  modules/checks/devloop-queries.nix \
  modules/checks/devloop-queries \
  openspec/changes/stand-up-devloop-collection/tasks.md
jj diff --no-pager --summary -r "$change"
```

Expected: `M modules/clan/services/otel-collector/schema.nix`, `A modules/nixos/devloop-collection.nix`, `M modules/nixos/greptimedb.nix`, `M modules/machines/nixos/magnetite/default.nix`, `A modules/checks/devloop-queries.nix`, `A modules/checks/devloop-queries/fixtures.sql`, `A modules/checks/devloop-queries/mutant-rename-cached.sql`, `M openspec/changes/stand-up-devloop-collection/tasks.md`, and nothing else.
If `tasks.md` carried hunks other than the seven ticks before the squash, squash that file with `--interactive` and select only the ticks.
The orchestrator rebases the development join onto this change, pushes it, opens pull request 2 and enqueues it after pull request 1 has landed.

- [ ] **Step 29: Pull request merged (tasks.md 2.8)**

The orchestrator's pull request shows nixbot green, including `checks.x86_64-linux.devloop-queries`, `greptimedb-envelope` and `nixos-magnetite`, and merges through the queue; the orchestrator ticks 2.8.
Verify: `jj git fetch && jj log --no-graph -r 'main@origin & description(substring:"feat(devloop): the devloop allow-list, tables, pipelines and devloop-queries")' -T 'commit_id.shortest(12)'` prints one commit.
Record `devloop-queries`' build time from the nixbot log in `logs/s2-evidence/2.8-nixbot-<ts>.log`, for the retrospective.
If any file of Step 28 changed between Step 26 and the merge, run Step 26 again from the merged tree before Step 30.

- [ ] **Step 30: Gate before deploy D2**

`tasks.md` 7.1 has passed after D1 (1.7), and the pre-D2 compile check (2.7) passed on this task's statements and pipelines.
Run:

```bash
ls logs/s2-evidence/7.1-*.log && rg -n '^- \[x\] 7\.1 ' openspec/changes/stand-up-devloop-collection/tasks.md
rg -l '^precheck passed$' logs/s2-evidence/2.7-precheck-*.log
```

Expected: the 7.1 evidence files exist and 7.1 is ticked, and at least one `2.7-precheck-<ts>.log` ends with `precheck passed`; if either is missing, stop, because D2 must not run before 7.1 and 2.7 (tasks.md 2.9).

- [ ] **Step 31: Deploy D2 (tasks.md 2.9)**

Run Task 7 Step 0's procedure: `logs/s2-evidence/s2-deploy.sh magnetite D2 2>&1 | tee logs/s2-evidence/2.9-deploy-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: the script finds `Queue is empty`, runs `clan machines update magnetite` from a fresh worktree of `origin/main` containing Step 29's commit, and appends `D2_START` and `D2_END` to `logs/s2-evidence/window.env`; then `ssh magnetite.zt 'systemctl show greptimedb-schema -p ActiveState -p Result; journalctl -u greptimedb-schema -b --since "-15min" -o cat | grep -c "answered HTTP"'` prints `ActiveState=active`, `Result=success` and `0`.
Verify: Task 7's 7.3 passes after D2 (2.9) (`SHOW TABLES FROM devloop`, `SHOW CREATE TABLE`, `greptime_private.pipelines`, empty tables and the next `greptimedb-envelope` run, read as `regulator`); group 3's deploy waits for it, and the orchestrator ticks 2.9.
If `greptimedb-schema` failed, `journalctl -u greptimedb-schema` names the statement or pipeline and its HTTP status; roll back by redeploying magnetite from the previous `main@origin` commit through the same script, which leaves any created table in place, empty and unread until Task 3.

---


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

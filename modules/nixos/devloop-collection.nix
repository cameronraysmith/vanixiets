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

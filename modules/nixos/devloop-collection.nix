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

  # The reconcile's nixbot side (design D11), run by devloop-reconcile as
  # the role devloop-reconcile under its column grants (design D10), each
  # prepared over the window [$1, $2) as timestamptz. currentFinish also
  # takes $3, a jsonb array of { build_id, attr (null for a build),
  # finished_at_us }: the stored keys nixbot's window lacks; it returns
  # those nixbot does not explain, a key being explained when nixbot has
  # it with a null or later finished_at (a restart). Times are epoch
  # microseconds, the form the store returns for TIMESTAMP(6).
  # checks.x86_64-linux.devloop-queries runs all four as devloop-reconcile.
  reconcileQueries =
    let
      us = expression: "((extract(epoch FROM ${expression}) * 1000000)::bigint)";
    in
    {
      attributes = lib.concatStringsSep "\n" [
        "SELECT a.build_id::text AS build_id, a.attr AS attr, ${us "a.finished_at"}::text AS finished_at_us"
        "FROM build_attributes a"
        "WHERE a.finished_at >= $1 AND a.finished_at < $2"
        "ORDER BY a.build_id, a.attr"
      ];
      builds = lib.concatStringsSep "\n" [
        "SELECT b.id::text AS build_id, ${us "b.finished_at"}::text AS finished_at_us"
        "FROM builds b"
        "WHERE b.finished_at >= $1 AND b.finished_at < $2"
        "ORDER BY b.id"
      ];
      batchBuilds = lib.concatStringsSep "\n" [
        "SELECT count(*)::text AS batch_builds"
        "FROM builds b"
        "WHERE starts_with(b.branch, 'gitea-mq/batch/') AND b.finished_at >= $1 AND b.finished_at < $2"
      ];
      currentFinish = lib.concatStringsSep "\n" [
        "WITH k AS ("
        "  SELECT r.build_id, r.attr, r.finished_at_us"
        "  FROM jsonb_to_recordset($3) AS r(build_id bigint, attr text, finished_at_us bigint)"
        "  WHERE r.finished_at_us >= ${us "$1"} AND r.finished_at_us < ${us "$2"}"
        "), c AS ("
        "  SELECT k.build_id, k.attr, k.finished_at_us,"
        "    coalesce(a.build_id, b.id) IS NOT NULL AS present,"
        "    ${us "coalesce(a.finished_at, b.finished_at)"} AS current_us"
        "  FROM k"
        "  LEFT JOIN build_attributes a ON k.attr IS NOT NULL AND a.build_id = k.build_id AND a.attr = k.attr"
        "  LEFT JOIN builds b ON k.attr IS NULL AND b.id = k.build_id"
        ")"
        "SELECT coalesce(c.build_id::text, 'NULL') AS build_id, coalesce(c.attr, '') AS attr,"
        "  c.finished_at_us::text AS stored_us,"
        "  CASE WHEN NOT c.present THEN 'absent' ELSE coalesce(c.current_us::text, 'null') END AS current_us"
        "FROM c"
        "WHERE NOT c.present OR (c.current_us IS NOT NULL AND c.current_us <= c.finished_at_us)"
        "ORDER BY 1, 2, 3"
      ];
    };

  # flake.lib.devloopReconcile (design D11): devloop-reconcile.service's
  # ExecStart. Over one UTC day, [DEVLOOP_RECONCILE_DAY 00:00, +1 day)
  # (default yesterday), it compares each table of DEVLOOP_RECONCILE_DATABASE
  # (default devloop) with its source and prints one line per clause,
  # `devloop-reconcile: C<n> <name>: ok` or `... FAIL <detail>`:
  #   C1 attributes, C2 builds: nixbot's keys in the window against the
  #     table's, compared as multisets, so a duplicated row is an extra key;
  #     an extra key is explained only when nixbot's current finished_at for
  #     it is null or later (a restart), and any other fails, as does a
  #     missing key;
  #   C3 batch-lines: per-msg counts of the gitea-mq.service journal lines
  #     matching design D7's pattern, by __REALTIME_TIMESTAMP, against
  #     batch_event's rows;
  #   C4 batch-liveness: a gitea-mq/batch/ build finished in the window and
  #     no batch built row;
  #   C5 batch-fields: a batch done row with a null landed, ejected, builds
  #     or flaky;
  #   C6 deploys: the deploy record's lines with ts in the window against
  #     the host's deploy_record rows;
  #   C7 current-system: the current system against the host's latest
  #     stored closure; when the deploy record's last line names the
  #     current system and the store's latest row does not, the store is
  #     read again every 10 s for up to 120 s first, because that line may
  #     not be shipped yet (a deploy just before the run, or the timer's
  #     Persistent catch-up at boot).
  # nixbot is read by peer as devloop-reconcile through
  # devloopCollection.reconcileQueries; the store as `regulator` through
  # greptimedbSql (modules/lib/greptimedb-envelope.nix), which reads
  # $CREDENTIALS_DIRECTORY/regulator-password into `curl --config -` and
  # fails on an empty answer, so every store query here counts first and
  # reads keys only after a non-zero count (S1 review F3). Exit 1 when a
  # clause fails; exit 2, naming the source on stderr, when nixbot, the
  # journal, the deploy record, the current system or the store cannot be
  # read, or an environment value is malformed.
  devloopReconcile =
    pkgs:
    {
      psql,
      journalctl ? "journalctl",
      storeUrl ? "http://127.0.0.1:4000",
      hostName,
      deployRecord ? "/var/log/deploy-record.jsonl",
      currentSystem ? "/run/current-system",
    }:
    let
      queries = reconcileQueries;
      sqlFile = name: pkgs.writeText "devloop-reconcile-${name}.sql" queries.${name};
      attributesSql = sqlFile "attributes";
      buildsSql = sqlFile "builds";
      batchBuildsSql = sqlFile "batchBuilds";
      currentFinishSql = sqlFile "currentFinish";
      storeSql = config.flake.lib.greptimedbSql pkgs {
        url = storeUrl;
        user = "regulator";
      };
      # The extra stored keys, one `build_id<TAB>attr<TAB>finished_at` (C1)
      # or `build_id<TAB>finished_at` (C2) line each, as currentFinish's $3;
      # a NULL or non-numeric field reads as null, which nixbot never has.
      extraKeysJq = pkgs.writeText "devloop-reconcile-extra-keys.jq" ''
        split("\n")
        | map(select(length > 0) | split("\t"))
        | map(
            if length == 3 then
              { build_id: (.[0] | tonumber? // null), attr: .[1], finished_at_us: (.[2] | tonumber? // null) }
            else
              { build_id: (.[0] | tonumber? // null), attr: null, finished_at_us: (.[1] | tonumber? // null) }
            end
          )
      '';
      # The slurped journal entries in [$from, $to) microseconds of
      # __REALTIME_TIMESTAMP whose MESSAGE carries one of design D7's five
      # messages, the closing quote making each match exact, counted per
      # message as `<msg><TAB><count>` lines.
      batchLinesJq = pkgs.writeText "devloop-reconcile-batch-lines.jq" ''
        [ .[]
          | select(.MESSAGE | type == "string")
          | select((.__REALTIME_TIMESTAMP | tonumber) as $t | $t >= $from and $t < $to)
          | .MESSAGE
          | capture("msg=\"(?<msg>batch (?:formed|built|landed|bisecting|done))\"")
          | .msg ]
        | group_by(.)
        | .[]
        | "\(.[0])\t\(length)"
      '';
      # The deploy record's lines whose ts lies in [$from, $to).
      deployLinesJq = pkgs.writeText "devloop-reconcile-deploy-lines.jq" ''
        select(.ts >= $from and .ts < $to) | .ts
      '';
    in
    pkgs.writeShellApplication {
      name = "devloop-reconcile";
      # diffutils for C3's cmp: a unit's PATH has no cmp.
      runtimeInputs = [
        pkgs.coreutils
        pkgs.diffutils
        pkgs.jq
      ];
      text = ''
        tab=$'\t'
        failed=0
        host=${lib.escapeShellArg hostName}
        unreadable() {
          printf 'devloop-reconcile: cannot read %s\n' "$1" >&2
          exit 2
        }
        ok() {
          printf 'devloop-reconcile: %s: ok\n' "$1"
        }
        fail() {
          printf 'devloop-reconcile: %s: FAIL %s\n' "$1" "$2"
          failed=1
        }
        # sample FILE: FILE's line count and its first three lines, tabs as "/".
        sample() {
          printf '%s (first: %s)' "$(wc -l < "$1")" "$(head -n 3 "$1" | tr '\t' '/' | paste -s -d ',' -)"
        }

        day=''${DEVLOOP_RECONCILE_DAY:-$(date -u -d yesterday +%F)}
        db=''${DEVLOOP_RECONCILE_DATABASE:-devloop}
        [[ $day =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || unreadable "DEVLOOP_RECONCILE_DAY=$day: not YYYY-MM-DD"
        [[ $db =~ ^[a-z_][a-z0-9_]*$ ]] || unreadable "DEVLOOP_RECONCILE_DATABASE=$db: not a database name"
        from_s=$(date -u -d "$day" +%s 2>/dev/null) || unreadable "DEVLOOP_RECONCILE_DAY=$day: not a date"
        to_s=$((from_s + 86400))
        from_iso=$(date -u -d "@$from_s" +%Y-%m-%dT%H:%M:%SZ)
        to_iso=$(date -u -d "@$to_s" +%Y-%m-%dT%H:%M:%SZ)
        [ "$from_iso" = "''${day}T00:00:00Z" ] || unreadable "DEVLOOP_RECONCILE_DAY=$day: not a calendar day"
        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT

        # pg QUERY [KEYS_FILE]: one reconcileQueries text as devloop-reconcile,
        # prepared over the window as $1 and $2 and, with KEYS_FILE, its JSON as
        # $3; psql reads that file itself (\set with a backquoted cat), so no key
        # list is on an argument list. Prints the rows, tab-separated, no header.
        pg() {
          local keys="" types="timestamptz, timestamptz" args=":'from', :'to'"
          if [ "$#" -eq 2 ]; then
            keys="\\set keys \`cat $2\`"
            types="$types, jsonb"
            args="$args, :'keys'"
          fi
          printf '%s\nPREPARE q(%s) AS %s;\nEXECUTE q(%s);\n' "$keys" "$types" "$1" "$args" |
            ${psql} -X -q -A -t -v ON_ERROR_STOP=1 -F "$tab" -v from="$from_iso" -v to="$to_iso" \
              "host=/run/postgresql dbname=nixbot user=devloop-reconcile"
        }
        # storeq SQL: one statement as `regulator`; greptimedbSql fails on an
        # empty answer, so callers count first and read keys only after a
        # non-zero count.
        storeq() {
          ${lib.getExe storeSql} "$1"
        }
        # win COLUMN: the window predicate over a store column.
        win() {
          printf '%s' "\"$1\" >= '$from_iso' AND \"$1\" < '$to_iso'"
        }
        # tbl TABLE: the table in the reconciled database.
        tbl() {
          printf '%s' "\"$db\".\"$1\""
        }

        # keyed CLAUSE TABLE COLUMNS QUERY: C1 and C2. Keys are compared as
        # multisets (sorted, not made unique), so a duplicated stored row is an
        # extra key; an extra key is explained only when nixbot's current
        # finished_at for it is null or later than the stored one (a restart).
        keyed() {
          local clause=$1 table=$2 columns=$3 query=$4 n detail=""
          pg "$(< "$query")" > "$work/source.raw" || unreadable "nixbot's $table keys as devloop-reconcile"
          n=$(storeq "SELECT count(*) FROM $(tbl "$table") WHERE $(win finished_at)") || unreadable "$db.$table in the store"
          if [ "$n" -gt 0 ]; then
            storeq "SELECT $columns FROM $(tbl "$table") WHERE $(win finished_at)" > "$work/store.raw" ||
              unreadable "$db.$table keys in the store"
          else
            : > "$work/store.raw"
          fi
          LC_ALL=C sort "$work/source.raw" > "$work/source"
          LC_ALL=C sort "$work/store.raw" > "$work/store"
          LC_ALL=C comm -23 "$work/source" "$work/store" > "$work/missing"
          LC_ALL=C comm -13 "$work/source" "$work/store" > "$work/extra"
          : > "$work/unexplained"
          if [ -s "$work/extra" ]; then
            jq -R -s -f ${extraKeysJq} "$work/extra" > "$work/extra.json" || unreadable "the stored $table keys"
            pg "$(< ${currentFinishSql})" "$work/extra.json" > "$work/unexplained" ||
              unreadable "nixbot's current finished_at as devloop-reconcile"
          fi
          if [ -s "$work/missing" ]; then
            detail="missing from $db.$table: $(sample "$work/missing")"
          fi
          if [ -s "$work/unexplained" ]; then
            detail="''${detail:+$detail; }unexplained in $db.$table: $(sample "$work/unexplained")"
          fi
          if [ -n "$detail" ]; then
            fail "$clause" "$detail"
          else
            ok "$clause"
          fi
        }

        keyed "C1 attributes" ci_attribute '"build_id", "attr", "finished_at"' ${attributesSql}
        keyed "C2 builds" ci_build '"build_id", "finished_at"' ${buildsSql}

        # C3: the journal is readable only if PID 1's entries are visible, so an
        # empty gitea-mq answer below means a quiet day, not a missing group.
        seen=$(${journalctl} --quiet --no-pager --lines=1 --output=cat _PID=1) || unreadable "the journal"
        [ -n "$seen" ] || unreadable "the journal: no entry of PID 1 is visible to this user"
        ${journalctl} --quiet --no-pager --output=json --unit=gitea-mq.service --since="@$from_s" --until="@$to_s" \
          > "$work/journal.json" || unreadable "the gitea-mq.service journal"
        jq -r -s --argjson from "$((from_s * 1000000))" --argjson to "$((to_s * 1000000))" -f ${batchLinesJq} \
          "$work/journal.json" > "$work/journal.raw" || unreadable "the gitea-mq.service journal entries"
        n=$(storeq "SELECT count(*) FROM $(tbl batch_event) WHERE $(win ts)") || unreadable "$db.batch_event in the store"
        if [ "$n" -gt 0 ]; then
          storeq "SELECT \"msg\", count(*) FROM $(tbl batch_event) WHERE $(win ts) GROUP BY \"msg\"" > "$work/batch.raw" ||
            unreadable "$db.batch_event counts in the store"
        else
          : > "$work/batch.raw"
        fi
        LC_ALL=C sort "$work/journal.raw" > "$work/journal.counts"
        LC_ALL=C sort "$work/batch.raw" > "$work/batch.counts"
        if cmp -s "$work/journal.counts" "$work/batch.counts"; then
          ok "C3 batch-lines"
        else
          fail "C3 batch-lines" "journal {$(tr '\t' '=' < "$work/journal.counts" | paste -s -d ',' -)} store {$(tr '\t' '=' < "$work/batch.counts" | paste -s -d ',' -)}"
        fi

        batch_builds=$(pg "$(< ${batchBuildsSql})") || unreadable "nixbot's gitea-mq/batch/ builds as devloop-reconcile"
        built=$(storeq "SELECT count(*) FROM $(tbl batch_event) WHERE \"msg\" = 'batch built' AND $(win ts)") ||
          unreadable "$db.batch_event in the store"
        if [ "$batch_builds" -gt 0 ] && [ "$built" -eq 0 ]; then
          fail "C4 batch-liveness" "nixbot finished $batch_builds gitea-mq/batch/ builds and $db.batch_event has no batch built row"
        else
          ok "C4 batch-liveness"
        fi

        nulls=$(storeq "SELECT count(*) FROM $(tbl batch_event) WHERE \"msg\" = 'batch done' AND $(win ts) AND (\"landed\" IS NULL OR \"ejected\" IS NULL OR \"builds\" IS NULL OR \"flaky\" IS NULL)") ||
          unreadable "$db.batch_event in the store"
        if [ "$nulls" -eq 0 ]; then
          ok "C5 batch-fields"
        else
          fail "C5 batch-fields" "$nulls batch done rows have a null landed, ejected, builds or flaky"
        fi

        # C7 reads the store first, because its wait also lets C6 count the rows
        # the collector ships meanwhile. When the deploy record's last line names
        # the current system and the store's latest row does not, that line may
        # not be shipped yet (a deploy just before the run, or the timer's
        # Persistent catch-up at boot), so the store is read again every 10 s for
        # up to 120 s before C7 judges.
        current=$(readlink -f ${lib.escapeShellArg currentSystem}) || unreadable ${lib.escapeShellArg currentSystem}
        last=$(tail -n 1 ${lib.escapeShellArg deployRecord} | jq -r '.closure // ""') || unreadable ${lib.escapeShellArg deployRecord}
        # latest_closure: the host's latest stored closure, or nothing without a row.
        latest_closure() {
          local stored
          stored=$(storeq "SELECT count(*) FROM $(tbl deploy_record) WHERE \"host\" = '$host'") ||
            unreadable "$db.deploy_record in the store"
          if [ "$stored" -gt 0 ]; then
            storeq "SELECT \"closure\" FROM $(tbl deploy_record) WHERE \"host\" = '$host' ORDER BY \"ts\" DESC LIMIT 1" ||
              unreadable "$db.deploy_record in the store"
          fi
        }
        latest=$(latest_closure) || exit 2
        waited=0
        if [ "$last" = "$current" ]; then
          while [ "$latest" != "$current" ] && [ "$waited" -lt 120 ]; do
            printf 'devloop-reconcile: C7 current-system: waiting for %s in the store (%s s)\n' "$current" "$waited" >&2
            sleep 10
            waited=$((waited + 10))
            latest=$(latest_closure) || exit 2
          done
        fi

        lines=$(jq -r --arg from "$from_iso" --arg to "$to_iso" -f ${deployLinesJq} ${lib.escapeShellArg deployRecord} | wc -l) ||
          unreadable ${lib.escapeShellArg deployRecord}
        rows=$(storeq "SELECT count(*) FROM $(tbl deploy_record) WHERE \"host\" = '$host' AND $(win ts)") ||
          unreadable "$db.deploy_record in the store"
        if [ "$lines" -eq "$rows" ]; then
          ok "C6 deploys"
        else
          fail "C6 deploys" "${deployRecord} has $lines lines in the window and $db.deploy_record $rows rows for $host"
        fi

        after=""
        if [ "$waited" -gt 0 ]; then
          after=" after waiting $waited s"
        fi
        if [ -z "$latest" ]; then
          fail "C7 current-system" "$db.deploy_record has no row for $host$after; the current system is $current"
        elif [ "$latest" = "$current" ]; then
          ok "C7 current-system"
        else
          fail "C7 current-system" "the latest stored closure is $latest$after and the current system is $current"
        fi

        exit "$failed"
      '';
    };
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
    inherit questions batchEventKeys reconcileQueries;
  };

  flake.lib.devloopReconcile = devloopReconcile;

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

      # devloop-reconcile (design D11): once a day, 2 h 15 min after the
      # previous UTC day closed, every devloop table is compared with its
      # source over that day. The host sets LoadCredential=regulator-password,
      # so this module stays free of clan vars, as greptimedb.nix's
      # greptimedb-envelope does, and lists the unit in
      # services.observability-notify.units for OnFailure. No `wants`: a run
      # whose sources are down exits 2 and is notified instead of starting
      # them. OOMScoreAdjust 600 puts it after nixbot's evaluator (900) and
      # before the store (500); magnetite asserts the order. Persistent=true
      # catches up one missed run at boot, which reconciles only the previous
      # day; days missed while magnetite was down are rerun by hand with
      # DEVLOOP_RECONCILE_DAY (design D11; plan review F13).
      systemd.services.devloop-reconcile = {
        description = "Daily reconcile of the devloop tables with nixbot, the journal and the deploy record";
        after = [
          "postgresql.service"
          "greptimedb.service"
          "greptimedb-schema.service"
          "devloop-pg-grants.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe (
            devloopReconcile pkgs {
              psql = lib.getExe' config.services.postgresql.package "psql";
              journalctl = lib.getExe' config.systemd.package "journalctl";
              hostName = config.networking.hostName;
            }
          );
          DynamicUser = true;
          SupplementaryGroups = [ "systemd-journal" ];
          MemoryMax = "128M";
          TimeoutStartSec = "10min";
          OOMScoreAdjust = 600;
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
        };
      };

      systemd.timers.devloop-reconcile = {
        description = "Daily devloop reconcile";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 02:15:00 UTC";
          Persistent = true;
        };
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
          # The receiver always runs `journalctl --follow`
          # (pkg/stanza/operator/input/journald/config_linux.go buildArgs)
          # and has no boot option, and systemd 261's journalctl reads only
          # the current boot under --follow unless a --boot is given: on
          # magnetite the receiver's argv selected 282 of the 772 retained
          # lines, those since the last reboot, and 772 with --boot=all
          # (logs/s2-evidence/7.4-batch-lines-*.log). The wrapper reads every
          # retained boot, including the lines written after the cursor
          # before a reboot.
          "journald/gitea-mq" = {
            journalctl_path = "${pkgs.writeShellScript "journalctl-all-boots" ''
              exec ${config.systemd.package}/bin/journalctl --boot=all "$@"
            ''}";
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

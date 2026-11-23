# One log table of the telemetry store, rendered from a column allow-list:
# its CREATE TABLE statement and its version-2 ingest pipeline (S2 design D5;
# agent-session-telemetry design D5). devloop's tables
# (flake.lib.devloopCollection) and agent.session_event
# (flake.lib.agentSessionStore) are rendered here, so the two follow one
# convention.
#
# flake.lib.greptimedbLogTable { name; table; recordTimestamps ? [ ];
# eventFilter ? null; } → { ddl; alters; pipeline; }. `table` is { columns;
# primaryKey; timeIndex; }, each column { name; type; nullable; } of the
# four types below, and optionally:
#   - `source`: { log = <key>; } or { resource = <key>; }, the OTLP log
#     attribute or resource attribute the column is read from. A column with
#     a source is coerced leniently: a value of another type becomes null
#     rather than failing the record, so an emitter's type change loses a
#     value, never a row and never adds a column. Without a source the
#     column is the log attribute of its own name, coerced strictly, as the
#     devloop receivers guarantee their types.
#   - `fulltext = true`: a string column with a bloom full-text index, which
#     `matches_term` and term-bearing `LIKE` use
#     (GreptimeTeam/greptimedb@v1.2.1:src/sql/src/parsers/create_parser.rs:895-936).
# `recordTimestamps` names the columns taken from the OTLP record's
# Timestamp. `eventFilter` = { key; values; } makes the pipeline return null,
# which drops the record (src/pipeline/src/etl.rs:331-336), unless the log
# attribute `key` is one of `values`.
{ lib, ... }:
let
  # Every identifier is double-quoted: `status` is a reserved word in
  # GreptimeDB 1.2.1's parser (logs/s2/spike-dedup.md, DDL), and quoting all
  # of them removes the class.
  quote = name: ''"${name}"'';

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

  fulltextIndex = "FULLTEXT INDEX WITH (analyzer = 'English', case_sensitive = 'false', backend = 'bloom')";

  # A VRL path segment: bare when it is an identifier, quoted otherwise
  # (`a."session.id"`).
  segment = key: if builtins.match "[A-Za-z_][A-Za-z0-9_]*" key != null then key else ''"${key}"'';

  vrlString = value: ''"${lib.replaceStrings [ ''\'' ''"'' ] [ ''\\'' ''\"'' ] value}"'';
in
{
  flake.lib.greptimedbLogTable =
    {
      name,
      table,
      recordTimestamps ? [ ],
      eventFilter ? null,
    }:
    let
      ddl = lib.concatStringsSep "\n" (
        [ "CREATE TABLE IF NOT EXISTS ${quote name} (" ]
        ++ map (
          column:
          let
            notNull = lib.optionalString (!column.nullable) " NOT NULL";
            fulltext = lib.optionalString (column.fulltext or false) " ${fulltextIndex}";
          in
          "  ${quote column.name} ${storeType.${column.type}}${notNull}${fulltext},"
        ) table.columns
        ++ [
          "  TIME INDEX (${quote table.timeIndex}),"
          "  PRIMARY KEY (${lib.concatMapStringsSep ", " quote table.primaryKey})"
          ") ENGINE=mito WITH ('append_mode' = 'false', 'sst_format' = 'flat')"
        ]
      );

      # CREATE TABLE IF NOT EXISTS changes nothing once the table exists, and
      # with auto_create_table=false 1.2.1 refuses a pipeline's write of a
      # column the table lacks ("unknown columns", the whole request), so
      # each nullable column outside the primary key is also added to an
      # existing table, with its full-text index, every run: ADD COLUMN IF
      # NOT EXISTS does nothing to a column that is there, and 1.2.1 takes no
      # index inside ADD COLUMN (src/sql/src/parsers/alter_parser.rs:697-724).
      alters = lib.concatMap (
        column:
        [
          "ALTER TABLE ${quote name} ADD COLUMN IF NOT EXISTS ${quote column.name} ${storeType.${column.type}} NULL"
        ]
        ++ lib.optional (column.fulltext or false
        ) "ALTER TABLE ${quote name} MODIFY COLUMN ${quote column.name} SET ${fulltextIndex}"
      ) (lib.filter (column: column.nullable && !(lib.elem column.name table.primaryKey)) table.columns);

      fromResource = lib.any (column: column ? source.resource) table.columns;

      # One VRL assignment per allow-listed column, after the event is
      # replaced by an empty object: "" and an absent attribute become null
      # before any coercion, because to_int and to_bool turn null into 0 and
      # false (vectordotdev/vrl@v0.33.1:src/stdlib/to_int.rs:12,
      # src/stdlib/to_bool.rs:11). VRL takes no `if` as an object-literal
      # value, so the fields are assigned one by one.
      vrlAssignment =
        column:
        let
          attribute =
            if column ? source.log then
              "a.${segment column.source.log}"
            else if column ? source.resource then
              "r.${segment column.source.resource}"
            else
              "a.${column.name}";
          coerced =
            if column ? source then
              {
                int64 = "to_int(${attribute}) ?? null";
                boolean = "to_bool(${attribute}) ?? null";
                string = "string(${attribute}) ?? null";
              }
              .${column.type}
            else
              {
                int64 = "to_int!(${attribute})";
                boolean = "to_bool!(${attribute})";
                string = "string!(${attribute})";
                timestamp = "string!(${attribute})";
              }
              .${column.type};
        in
        if lib.elem column.name recordTimestamps then
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

      fromAttributes = lib.filter (
        column: column.type == "timestamp" && !(lib.elem column.name recordTimestamps)
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

      # Without a filter the body is the event; with one it sits in the
      # `else` branch, two spaces deeper.
      indent = if eventFilter == null then "        " else "          ";
      body = [
        "${indent}. = {}"
      ]
      ++ map (column: "${indent}${vrlAssignment column}") table.columns
      ++ [
        "${indent}."
      ];
    in
    {
      inherit ddl alters;
      pipeline =
        lib.concatStringsSep "\n" (
          [
            "version: 2"
            "processors:"
            "  - vrl:"
            "      source: |"
            "        a = object!(.LogAttributes)"
          ]
          ++ lib.optional fromResource "        r = object(.ResourceAttributes) ?? {}"
          # The record's Timestamp is read before the event is replaced.
          ++ lib.optional (recordTimestamps != [ ]) "        t = int!(.Timestamp)"
          ++ (
            if eventFilter == null then
              body
            else
              [
                "        if !includes([${
                          lib.concatMapStringsSep ", " vrlString eventFilter.values
                        }], a.${segment eventFilter.key}) {"
                "          null"
                "        } else {"
              ]
              ++ body
              ++ [ "        }" ]
          )
          ++ lib.optionals (required != [ ]) (dateStep required false)
          ++ lib.optionals (optional != [ ]) (dateStep optional true)
          ++ [ "transform:" ]
          ++ lib.concatMap transformEntry table.columns
        )
        + "\n";
    };
}

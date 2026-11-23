# agent.session_event at the telemetry store (agent-session-telemetry design
# D5): its CREATE TABLE statement and its version-2 ingest pipeline
# `agent_session_event`, rendered by flake.lib.greptimedbLogTable from
# flake.lib.otelCollectorSchema.agentSession and handed to greptimedb-schema
# (modules/nixos/greptimedb.nix), which creates the table before the
# collector writes and uploads the pipeline to
# /v1/pipelines/agent_session_event?db=agent. The pipeline starts from an
# empty object and returns null for an event off the allow-list, so the
# store keeps the column set closed behind the collector's filters. The
# ingress role routes the agent events to this table where the pipeline is
# declared.
{ config, lib, ... }:
let
  inherit (config.flake.lib.otelCollectorSchema) agentSession;
  table = agentSession.tables.session_event;
  rendered = config.flake.lib.greptimedbLogTable {
    name = "session_event";
    inherit table;
    recordTimestamps = map (column: column.name) (
      lib.filter (column: column ? source.record) table.columns
    );
    eventFilter = {
      key = "event.name";
      values = lib.attrNames agentSession.events.keys;
    };
  };

  # Every kept key reaches a column and every column reads a kept key, so
  # the collector's allow-list and the table cannot drift apart.
  keptLogKeys = lib.unique (
    agentSession.events.correlationKeys ++ lib.concatLists (lib.attrValues agentSession.events.keys)
  );
  columnLogKeys = map (column: column.source.log) (
    lib.filter (column: column ? source.log) table.columns
  );
  columnResourceKeys = map (column: column.source.resource) (
    lib.filter (column: column ? source.resource) table.columns
  );
  unmapped = lib.subtractLists columnLogKeys keptLogKeys;
  unkept = lib.subtractLists keptLogKeys columnLogKeys;
  unkeptResource = lib.subtractLists (
    [ "host.name" ] ++ agentSession.events.resourceKeys
  ) columnResourceKeys;

  # agent.agent_span and its two lookup tables (design D13): GreptimeDB
  # 1.2.1's own greptime_trace_v1 schema, as the store writes it when it
  # creates the tables on insert (GreptimeTeam/greptimedb@v1.2.1:
  # src/servers/src/otlp/trace/v1.rs:48-95, :551; src/operator/src/insert.rs:686-790),
  # with one column per allow-listed key and full-text indexes on the
  # content columns. The ingress writes with auto_create_table=false, so a
  # key off the list is refused rather than added as a column; there is no
  # PARTITION ON (one region, standalone) and no ttl (agent's 30 d applies).
  spans = agentSession.spans;
  skipping = "SKIPPING INDEX WITH(false_positive_rate = '0.01', granularity = '10240', type = 'BLOOM')";
  fulltextIndex = "FULLTEXT INDEX WITH(analyzer = 'English', case_sensitive = 'false', backend = 'bloom')";
  storeType = {
    string = "STRING";
    int64 = "BIGINT";
    boolean = "BOOLEAN";
  };
  spanColumn = keys: key: ''"span_attributes.${key}" ${storeType.${keys.${key}}} NULL'';
  # service.name becomes service_name; host.name is stamped by the collector.
  resourceColumns =
    resourceKeys:
    map (key: ''"resource_attributes.${key}" STRING NULL'') (
      lib.remove "service.name" resourceKeys ++ [ "host.name" ]
    );
  createTable = name: columns: options: ''
    CREATE TABLE IF NOT EXISTS "${name}" (
      ${lib.concatStringsSep ",\n  " columns}
    ) ENGINE=mito WITH(${lib.concatStringsSep ", " options})'';
  # The span table's CREATE for a key set; the VM test renders the tables
  # of earlier generations from it.
  spanTableFor =
    {
      keys,
      fulltext,
      resourceKeys ? spans.resourceKeys,
    }:
    createTable spans.table
      (
        [
          ''"timestamp" TIMESTAMP(9) NOT NULL''
          ''"timestamp_end" TIMESTAMP(9) NULL''
          ''"duration_nano" BIGINT UNSIGNED NULL''
          ''"parent_span_id" STRING NULL ${skipping}''
          ''"trace_id" STRING NULL ${skipping}''
          ''"span_id" STRING NULL''
          ''"span_kind" STRING NULL''
          ''"span_name" STRING NULL''
          ''"span_status_code" STRING NULL''
          ''"span_status_message" STRING NULL''
          ''"trace_state" STRING NULL''
          ''"scope_name" STRING NULL''
          ''"scope_version" STRING NULL''
          ''"service_name" STRING NULL ${skipping}''
        ]
        ++ map (key: spanColumn keys key + lib.optionalString (lib.elem key fulltext) " ${fulltextIndex}") (
          lib.attrNames keys
        )
        ++ resourceColumns resourceKeys
        ++ [
          ''"span_events" JSON NULL''
          ''"span_links" JSON NULL''
          ''TIME INDEX ("timestamp")''
          ''PRIMARY KEY ("service_name")''
        ]
      )
      [
        "append_mode = 'true'"
        "'greptime.semantic.pipeline' = 'greptime_trace_v1'"
        "'greptime.semantic.signal_type' = 'trace'"
        "'greptime.semantic.source' = 'opentelemetry'"
        "'greptime.semantic.trace.conventions' = 'unknown'"
        "table_data_model = 'greptime_trace_v1'"
      ];
  # CREATE TABLE IF NOT EXISTS changes nothing once the table exists, so
  # each span key's and resource key's column is also added to an existing
  # table, and each content column's index set, every run (design D15;
  # darwin-agent-session-telemetry design D15): ADD COLUMN IF NOT EXISTS
  # does nothing to a column that is there, and SET FULLTEXT INDEX rewrites
  # the same options. 1.2.1 takes no index inside ADD COLUMN
  # (src/sql/src/parsers/alter_parser.rs:697-724 parses a plain column
  # definition), hence the second statement. A table created by an older
  # generation thus ends with the columns and indexes a new one has.
  spanAlters =
    map (column: ''ALTER TABLE "${spans.table}" ADD COLUMN IF NOT EXISTS ${column}'') (
      map (spanColumn spans.keys) (lib.attrNames spans.keys) ++ resourceColumns spans.resourceKeys
    )
    ++ map (
      key: ''ALTER TABLE "${spans.table}" MODIFY COLUMN "span_attributes.${key}" SET ${fulltextIndex}''
    ) spans.fulltext;
  spanDdl = [
    (spanTableFor { inherit (spans) keys fulltext; })
  ]
  ++ spanAlters
  ++ [
    (createTable "${spans.table}_services"
      [
        ''"timestamp" TIMESTAMP(9) NOT NULL''
        ''"service_name" STRING NULL''
        ''TIME INDEX ("timestamp")''
        ''PRIMARY KEY ("service_name")''
      ]
      [ "append_mode = 'false'" ]
    )
    (createTable "${spans.table}_operations"
      [
        ''"timestamp" TIMESTAMP(9) NOT NULL''
        ''"service_name" STRING NULL''
        ''"span_name" STRING NULL''
        ''"span_kind" STRING NULL''
        ''TIME INDEX ("timestamp")''
        ''PRIMARY KEY ("service_name", "span_name", "span_kind")''
      ]
      [ "append_mode = 'false'" ]
    )
  ];
in
{
  flake.lib.agentSessionStore = {
    inherit spanDdl spanTableFor;
    inherit (rendered) ddl pipeline;
    pipelineName = "agent_session_event";
  };

  flake.modules.nixos.agent-session-store = {
    assertions = [
      {
        assertion = unmapped == [ ] && unkept == [ ] && unkeptResource == [ ];
        message = "agent-session-store: agentSession's kept keys and session_event's sources disagree: keys without a column ${builtins.toJSON unmapped}, columns reading an unkept key ${
          builtins.toJSON (unkept ++ unkeptResource)
        }.";
      }
    ];
    services.greptimedb.tables.agent = [ rendered.ddl ] ++ rendered.alters ++ spanDdl;
    services.greptimedb.pipelines.agent.agent_session_event = rendered.pipeline;
  };
}

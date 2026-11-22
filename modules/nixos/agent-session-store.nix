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
in
{
  flake.lib.agentSessionStore = {
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
    services.greptimedb.tables.agent = [ rendered.ddl ];
    services.greptimedb.pipelines.agent.agent_session_event = rendered.pipeline;
  };
}

# The ingress fragment, flake.modules.nixos.otel-collector-ingress, which the
# clan ingress role imports on magnetite (see service.nix).
{ config, ... }:
let
  inherit (import ./_shared.nix { inherit config; })
    flakeLib
    schema
    credentialsDir
    loopbackHandoff
    queueBytes
    collectorCore
    ;
in
{
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
      # Agent session events write through the store's agent_session_event
      # pipeline (flake.modules.nixos.agent-session-store), so their route
      # exists where the store declares it (agent-session-telemetry design D5).
      agentSession = schema.agentSession;
      agentLogs = (config.services.greptimedb.pipelines.agent or { }) ? agent_session_event;
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

      vanixiets.otelCollector.ingress = true;

      # The exporters write only to schema.nix's databases, and the store
      # answers 400 for any database its schema job did not create.
      assertions = lib.optional (config.services ? greptimedb) {
        assertion = storeDatabaseNames == databaseNames;
        message = "otel-collector ingress: services.greptimedb.databases creates ${builtins.toJSON storeDatabaseNames}, but flake.lib.otelCollectorSchema.databases routes to ${builtins.toJSON databaseNames}";
      };

      services.opentelemetry-collector = lib.mkMerge [
        {
          settings = {
            extensions = {
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

            # The agents' mTLS exports, one receiver per overlay on magnetite's
            # address there: otlp/mesh on ZeroTier, removed at ZeroTier's
            # retirement, and otlp/mesh-tincr on the tincr mesh, with the same
            # TLS. A client without an otel-ca certificate fails the handshake
            # (design D3). HTTP only, no gRPC.
            receivers."otlp/mesh".protocols.http = {
              endpoint = "[${flakeLib.hosts.magnetite.zerotier.address}]:4318";
              tls = {
                cert_file = "${credentialsDir}/otel-cert";
                key_file = "${credentialsDir}/otel-key";
                client_ca_file = config.vanixiets.otelCollector.caFile;
                min_version = "1.3";
              };
            };
            receivers."otlp/mesh-tincr".protocols.http = {
              endpoint = "[${flakeLib.hosts.magnetite.address}]:4318";
              tls = {
                cert_file = "${credentialsDir}/otel-cert";
                key_file = "${credentialsDir}/otel-key";
                client_ca_file = config.vanixiets.otelCollector.caFile;
                min_version = "1.3";
              };
            };

            # The agent's pipelines on this host end in the in-process
            # `forward` connector, which metrics/ingress and logs/ingress
            # receive from.
            connectors.forward = { };

            connectors.routing.table = map (db: {
              context = "resource";
              condition = ''attributes["vanixiets.database"] == "${db}"'';
              pipelines = [ "metrics/${db}" ];
            }) databaseNames;

            # `agent` also promotes the person an agent session ran for
            # (agent-session-telemetry design D4), which its emitters stamp on
            # the resource; every other database's header is unchanged.
            exporters = lib.listToAttrs (
              map (
                db:
                lib.nameValuePair "otlp_http/${db}" (
                  storeExporter {
                    "x-greptime-db-name" = db;
                    "x-greptime-otlp-metric-promote-resource-attrs" = lib.concatStringsSep ";" (
                      schema.promotedResourceAttributes
                      ++ lib.optionals (db == "agent") agentSession.metrics.promotedResourceAttributes
                    );
                  } queueBytes.${db}
                )
              ) databaseNames
            );

            service = {
              extensions = [ "basicauth/store" ];
              pipelines = {
                "metrics/ingress" = {
                  receivers = [
                    "forward"
                    "otlp/mesh"
                    "otlp/mesh-tincr"
                  ];
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

            service.pipelines = lib.listToAttrs (
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

        # Agent session events into agent.session_event through its own
        # exporter, as a devloop table's (agent-session-telemetry design D5).
        (lib.mkIf agentLogs {
          settings = {
            connectors."routing/logs".table = [
              {
                context = "resource";
                condition = ''attributes["vanixiets.database"] == "agent" and attributes["vanixiets.table"] == "session_event"'';
                pipelines = [ "logs/agent-session_event-out" ];
              }
            ];
            exporters."otlp_http/agent_session_event" = storeExporter {
              "x-greptime-db-name" = "agent";
              "x-greptime-log-table-name" = "session_event";
              "x-greptime-pipeline-name" = flakeLib.agentSessionStore.pipelineName;
              "x-greptime-hints" = "auto_create_table=false";
            } queueBytes.agent_session_event;
            service.pipelines."logs/agent-session_event-out" = {
              receivers = [ "routing/logs" ];
              processors = [ "resource/strip-database" ];
              exporters = [ "otlp_http/agent_session_event" ];
            };
          };
        })

        # omp's spans into agent.agent_span through the store's built-in
        # greptime_trace_v1 model (design D13), where the store declares
        # the span tables beside the events table. The schema job creates
        # all three, so auto_create_table=false refuses a key off the list
        # instead of adding a column. Only data the agents stamped `agent`
        # passes; on the ingress host its own spans arrive through
        # otlp/loopback.
        (lib.mkIf agentLogs {
          settings = {
            processors."filter/agent-spans-only" = {
              error_mode = "propagate";
              trace_conditions = [ ''not (resource.attributes["vanixiets.database"] == "agent")'' ];
            };
            exporters."otlp_http/agent_span" = storeExporter {
              "x-greptime-db-name" = "agent";
              "x-greptime-trace-table-name" = schema.agentSession.spans.table;
              "x-greptime-pipeline-name" = "greptime_trace_v1";
              "x-greptime-hints" = "auto_create_table=false";
            } queueBytes.agent_span;
            service.pipelines."traces/ingress" = {
              receivers = [
                "otlp/mesh"
                "otlp/mesh-tincr"
              ];
              processors = [
                "memory_limiter"
                "filter/agent-spans-only"
                "resource/strip-database"
              ];
              exporters = [ "otlp_http/agent_span" ];
            };
          };
        })

        # The logs entry, wherever a logs route exists. `forward` only where
        # a local logs pipeline exports to it, the deploy record's, which
        # needs the devloop route: since the agent-session pipelines left
        # this collector (agent-session-telemetry design D14), an ingress
        # with the agent route alone has none, and the collector refuses a
        # connector no pipeline exports to.
        (lib.mkIf (devloopLogs || agentLogs) {
          settings.service.pipelines."logs/ingress" = {
            receivers = lib.optional devloopLogs "forward" ++ [
              "otlp/mesh"
              "otlp/mesh-tincr"
            ];
            processors = [ "memory_limiter" ];
            exporters = [ "routing/logs" ];
          };
        })

        # The ingress host's own agent-session collector, a unit of its own,
        # hands its metrics, events and spans to this collector on loopback
        # (agent-session-telemetry design D14). The receiver requires the
        # otel-ca client certificate as otlp/mesh does, so no local account
        # can write into the store past otlp/local's allow-lists.
        (lib.mkIf config.vanixiets.otelCollector.agentTelemetry {
          settings = {
            receivers."otlp/loopback".protocols.http = {
              endpoint = loopbackHandoff;
              tls = {
                cert_file = "${credentialsDir}/otel-cert";
                key_file = "${credentialsDir}/otel-key";
                client_ca_file = config.vanixiets.otelCollector.caFile;
                min_version = "1.3";
              };
            };
            service.pipelines = {
              "metrics/ingress".receivers = [ "otlp/loopback" ];
              "logs/ingress".receivers = [ "otlp/loopback" ];
              "traces/ingress".receivers = [ "otlp/loopback" ];
            };
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
        (lib.mkIf (config.services ? greptimedb) {
          after = [ "greptimedb-schema.service" ];
          wants = [ "greptimedb-schema.service" ];
        })
      ];
    };
}

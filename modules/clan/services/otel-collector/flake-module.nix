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
#
# The fragments are plain NixOS modules, flake.modules.nixos.otel-collector-
# agent and -ingress, so the container test imports them without clan; only
# the clan ingress role reads the collector password from clan vars.
#
# The agent imports the failure notifier, flake.modules.nixos.observability-
# notify (modules/nixos/observability-notify.nix), and lists its own unit in
# services.observability-notify.units.
#
# Build-time validation (nixpkgs' `otelcol-contrib validate`) runs before
# /run/credentials exists. basicauth's password_file is not opened by
# validation; the prometheus receiver does stat its credentials_file, so the
# one validateConfigOverrides entry replaces the zerotierone job with itself
# minus `authorization`, for validation only.
{ config, ... }:
let
  nixosModules = config.flake.modules.nixos;
  schema = config.flake.lib.otelCollectorSchema;

  stateDir = "/var/lib/opentelemetry-collector";
  credentialsDir = "/run/credentials/opentelemetry-collector.service";

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

  # Imported by both roles. `package` accepts a single definition, and the
  # shared key makes the module system load this module once on a machine
  # holding both roles. The agent pipelines and `metrics/ingress` start with
  # this limiter; the per-database pipelines behind the routing connector only
  # strip the routing attribute (ADR-003 item 8; envelope 384 MiB under
  # MemoryMax 512M).
  collectorCore = {
    key = "vanixiets#otel-collector-core";
    imports = [
      (
        { pkgs, ... }:
        {
          services.opentelemetry-collector = {
            enable = true;
            package = pkgs.opentelemetry-collector-contrib;
            settings.processors.memory_limiter = {
              check_interval = "1s";
              limit_mib = 384;
            };
          };
          # nixpkgs restarts the collector after 100 ms, so five quick start
          # failures would hit systemd's default start limit and leave it
          # failed for good.
          systemd.services.opentelemetry-collector = {
            startLimitIntervalSec = 0;
            serviceConfig.RestartSec = "5s";
          };
        }
      )
    ];
  };
in
{
  flake.modules.nixos.otel-collector-agent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostName = config.networking.hostName;

      scrape =
        job: target: extra:
        {
          job_name = job;
          scrape_interval = "60s";
          static_configs = [ { targets = [ target ]; } ];
        }
        // extra;

      zerotierScrape = scrape "zerotierone" "127.0.0.1:9993" {
        authorization = {
          type = "Bearer";
          credentials_file = "${credentialsDir}/zerotier-metricstoken";
        };
        # Per-peer series carry node ids (ADR-003 item 20).
        metric_relabel_configs = [
          {
            source_labels = [ "__name__" ];
            regex = "zt_peer_.*";
            action = "drop";
          }
        ];
      };

      # ADR-003 item 16: a process identifier or command line could carry a
      # secret or prompt content into collector memory and the store.
      processAttributes =
        config.services.opentelemetry-collector.settings.receivers."host_metrics/process".scrapers.process.resource_attributes;
      enabledProcessAttributes = builtins.filter (a: (processAttributes.${a}.enabled or true) != false) [
        "process.pid"
        "process.parent_pid"
        "process.command"
        "process.command_line"
        "process.executable.path"
        "process.owner"
      ];
    in
    {
      imports = [
        collectorCore
        nixosModules.observability-notify
      ];

      config = lib.mkMerge [
        {
          assertions = [
            {
              assertion = enabledProcessAttributes == [ ];
              message = "otel-collector agent: the process scraper must disable ${lib.concatStringsSep ", " enabledProcessAttributes} at source (ADR-003 item 16).";
            }
            {
              assertion = !config.services.prometheus.exporters.node.openFirewall;
              message = "otel-collector agent: node_exporter must not open the firewall; it is scraped on loopback (ADR-003 item 18).";
            }
          ];

          services.opentelemetry-collector = {
            settings = {
              processors = {
                "transform/omnigent-alias".metric_statements = lib.mapAttrsToList (
                  owner: alias:
                  ''set(resource.attributes["systemd.unit.name"], "omnigent-host-${alias}.service") where resource.attributes["systemd.unit.name"] == "omnigent-host-${owner}.service"''
                ) schema.ownerAliases;
                "resource/agent".attributes = [
                  {
                    key = "host.name";
                    value = hostName;
                    action = "upsert";
                  }
                  {
                    key = "vanixiets.database";
                    value = "fleet";
                    action = "upsert";
                  }
                ];
                # Compaction (empty keys) merges same-named processes before
                # the sum (ADR-003 item 16).
                "groupbyattrs/compact".keys = [ ];
                "metrics_transform/process".transforms = [
                  {
                    include = "process.memory.usage";
                    match_type = "strict";
                    action = "update";
                    operations = [
                      {
                        action = "aggregate_labels";
                        label_set = [ ];
                        aggregation_type = "sum";
                      }
                    ];
                  }
                ];
                "filter/process-min" = {
                  error_mode = "ignore";
                  metric_conditions = [
                    ''metric.name == "process.memory.usage" and datapoint.value_int < ${toString schema.process.minBytes}''
                  ];
                };
              };

              receivers = {
                "host_metrics/memory" = {
                  collection_interval = "60s";
                  scrapers = {
                    memory.metrics."system.linux.memory.available".enabled = true;
                    paging.metrics = {
                      "system.paging.usage".enabled = true;
                      "system.paging.operations".enabled = false;
                      "system.paging.faults".enabled = false;
                      "system.paging.utilization".enabled = false;
                    };
                  };
                };
                "host_metrics/process" = {
                  collection_interval = "60s";
                  scrapers.process = {
                    # DynamicUser cannot read other users' exe links or io.
                    mute_process_all_errors = true;
                    resource_attributes = {
                      "process.pid".enabled = false;
                      "process.parent_pid".enabled = false;
                      "process.command".enabled = false;
                      "process.command_line".enabled = false;
                      "process.executable.path".enabled = false;
                      "process.owner".enabled = false;
                    };
                    metrics = {
                      "process.memory.usage".enabled = true;
                      "process.cpu.time".enabled = false;
                      "process.disk.io".enabled = false;
                      "process.memory.virtual".enabled = false;
                    };
                  };
                };
                systemd = {
                  collection_interval = "60s";
                  scope = "system";
                  units = schema.systemdUnits;
                  metrics = {
                    "systemd.service.restarts".enabled = true;
                    "systemd.service.cpu.time".enabled = false;
                  };
                };
                prometheus.config.scrape_configs = [
                  (scrape "node" "127.0.0.1:9100" {
                    metric_relabel_configs = [
                      {
                        source_labels = [ "__name__" ];
                        regex = lib.concatStringsSep "|" schema.nodeExporterKeep;
                        action = "keep";
                      }
                    ];
                  })
                  (scrape "gitea" "127.0.0.1:3002" { })
                  (scrape "niks3" "127.0.0.1:5752" { })
                  (scrape "nixbot" "127.0.0.1:9180" { })
                  (scrape "greptimedb" "127.0.0.1:4000" { })
                ];
              };

              connectors.forward = { };

              service.pipelines = {
                "metrics/host" = {
                  receivers = [
                    "host_metrics/memory"
                    "systemd"
                    "prometheus"
                  ];
                  processors = [
                    "memory_limiter"
                    "transform/omnigent-alias"
                    "resource/agent"
                  ];
                  exporters = [ "forward" ];
                };
                "metrics/process" = {
                  receivers = [ "host_metrics/process" ];
                  processors = [
                    "memory_limiter"
                    "groupbyattrs/compact"
                    "metrics_transform/process"
                    "filter/process-min"
                    "resource/agent"
                  ];
                  exporters = [ "forward" ];
                };
              };
            };
          };

          services.prometheus.exporters.node = {
            enable = true;
            listenAddress = "127.0.0.1";
            openFirewall = false;
            extraFlags = [
              "--collector.disable-defaults"
              "--collector.zfs"
              "--collector.vmstat"
              "--collector.vmstat.fields=^oom_kill$"
            ];
          };

          services.observability-notify.units = [ "opentelemetry-collector" ];

          systemd.services.prometheus-node-exporter.serviceConfig.MemoryMax = "64M";
        }

        (lib.mkIf (config.services.nginx.enable && config.services.nginx.statusPage) {
          services.opentelemetry-collector.settings = {
            receivers.nginx = {
              endpoint = "http://127.0.0.1:80/nginx_status";
              collection_interval = "60s";
            };
            service.pipelines."metrics/host".receivers = [ "nginx" ];
          };
        })

        (lib.mkIf config.services.zerotierone.enable {
          # Explicit, so an upgrade past 1.16.0 (default off) keeps the
          # mesh-health signal (ADR-003 item 5).
          services.zerotierone.localConf.settings.enableMetrics = true;

          systemd.services.opentelemetry-collector = {
            after = [ "zerotierone.service" ];
            serviceConfig.LoadCredential = [
              "zerotier-metricstoken:/var/lib/zerotier-one/metricstoken.secret"
            ];
          };

          services.opentelemetry-collector = {
            settings = {
              receivers."prometheus/zerotier".config.scrape_configs = [ zerotierScrape ];
              service.pipelines."metrics/host".receivers = [ "prometheus/zerotier" ];
            };
            validateConfigOverrides = [
              "receivers::prometheus/zerotier::config::scrape_configs=${
                builtins.toJSON [ (builtins.removeAttrs zerotierScrape [ "authorization" ]) ]
              }"
            ];
          };
        })
      ];
    };

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

  clan.modules.otel-collector =
    { ... }:
    {
      _class = "clan.service";
      manifest = {
        name = "otel-collector";
        description = "Fleet metrics collection into the telemetry store";
        categories = [ "System" ];
        readme = ''
          OpenTelemetry collector for the fleet. `agent` collects the
          machine's host, process, unit and service metrics, runs
          node_exporter on loopback, and imports the observability-notify@
          failure notifier. `ingress` converts, routes and writes metrics
          into GreptimeDB on 127.0.0.1:4000, one otlp_http exporter per
          database with a persistent queue. On a machine holding both
          roles they share one collector, joined by a `forward` connector.
        '';
      };

      roles.agent = {
        description = "Collects the machine's own metrics and posts unit failures to ntfy";
        interface = { };
        perInstance =
          { ... }:
          {
            nixosModule.imports = [ nixosModules.otel-collector-agent ];
          };
      };

      roles.ingress = {
        description = "Writes collected metrics into the telemetry store";
        interface = { };
        perInstance =
          { ... }:
          {
            nixosModule =
              { config, ... }:
              {
                imports = [ nixosModules.otel-collector-ingress ];
                systemd.services.opentelemetry-collector.serviceConfig.LoadCredential = [
                  "collector-password:${config.clan.core.vars.generators.greptimedb-users.files.collector-password.path}"
                ];
              };
          };
      };
    };
}

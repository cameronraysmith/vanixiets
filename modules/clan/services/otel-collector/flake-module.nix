# Fleet metrics collection as one clan service (ADR-003; design D8 to D10),
# and the logs path of S2's dev-loop tables (S2 design D4).
#
# Both roles' NixOS fragments merge into one services.opentelemetry-collector,
# because the NixOS module runs one collector per host. On magnetite, which
# holds both roles, the agent pipelines export to an in-process `forward`
# connector that the ingress pipelines receive from; every other agent host
# exports over mutual TLS to the ingress's otlp/mesh receiver on magnetite's
# ZeroTier address (S4 design D2, D3). The ingress converts
# exponential histograms while the store is below 1.3.0 (ADR-001 R1.2), routes
# metrics on the `vanixiets.database` resource attribute and logs on it and
# `vanixiets.table`, and writes each database, and each devloop table, through
# its own otlp_http exporter with a persistent queue, authenticating as the
# store's write-only `collector` user.
#
# The fragments are plain NixOS modules, flake.modules.nixos.otel-collector-
# agent and -ingress, so the container test imports them without clan; only
# the clan roles read clan vars: the agent role's otel-ca and otel-cert
# generators and the ntfy-alerter token on every host of
# flake.lib.observabilityHosts, and the ingress role's collector password.
#
# The agent imports the failure notifier, flake.modules.nixos.observability-
# notify (modules/nixos/observability-notify.nix); the agent role lists the
# host's notified units from flake.lib.observabilityHosts, and imports the
# agent fragment only where the host's `collect` is true (S4 design D6).
#
# Build-time validation (nixpkgs' `otelcol-contrib validate`) runs before
# /run/credentials exists. basicauth's password_file is not opened by
# validation; the prometheus receiver does stat its credentials_file, so the
# one validateConfigOverrides entry replaces the zerotierone job with itself
# minus `authorization`, for validation only.
{ config, ... }:
let
  nixosModules = config.flake.modules.nixos;
  darwinModules = config.flake.modules.darwin;
  flakeLib = config.flake.lib;
  schema = config.flake.lib.otelCollectorSchema;

  stateDir = "/var/lib/opentelemetry-collector";
  credentialsDir = "/run/credentials/opentelemetry-collector.service";

  mib = n: n * 1024 * 1024;

  # Persistent queue per exporter: at least 24 h of fleet and under 512 MiB
  # in total (ADR-003 envelope), asserted by
  # checks.x86_64-linux.otel-collector-config. devloop's 52 MiB is split
  # between its metrics and its five tables, ci_attribute holding about a
  # day of store outage on the busiest day (S2 design D4); eval_run's 4 MiB
  # holds months of nixbot's roughly 100 evaluation lines a day. agent's 48
  # MiB is split between its metrics and its session events, each holding
  # about 2 h of every agent-telemetry host's assumed output while the store
  # is down (agent-session-telemetry design D10).
  queueBytes = {
    fleet = mib 400;
    devloop = mib 4;
    agent = mib 16;
    agent_session_event = mib 32;
    # omp spans (design D13): 8,388,608 B holds about 42 min of two
    # agent-telemetry hosts at agentSpanBytesPerMinute while the store is
    # down, the hold the design accepts within the 512 MiB sum.
    agent_span = mib 8;
    devloop_ci_attribute = mib 32;
    devloop_ci_build = mib 4;
    devloop_batch_event = mib 4;
    devloop_deploy_record = mib 4;
    devloop_eval_run = mib 4;
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
        { lib, pkgs, ... }:
        {
          options.vanixiets.otelCollector = {
            ingress = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Whether this host runs the ingress, set by
                flake.modules.nixos.otel-collector-ingress: the agent's
                pipelines then end in the in-process `forward` connector
                instead of the mTLS exporters to magnetite's ZeroTier receiver.
              '';
            };
            caFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = ''
                The otel-ca certificate as a store path, which the agent's
                exporters and the ingress receiver trust; a new CA changes the
                configuration and so restarts the collector.
              '';
            };
            smartDevices = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = ''
                NVMe devices read by a loopback smartctl exporter that the
                agent scrapes; none when empty.
              '';
            };
            agentTelemetry = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Whether this host's agent listens for its agent sessions'
                telemetry: the loopback receiver `otlp/local` on
                127.0.0.1:4318 and the pipelines `metrics/agent-session` and
                `logs/agent-session` (agent-session-telemetry design D3, D8).
                Set by the clan agent role from the host's
                flake.lib.observabilityHosts row; the agent-telemetry home
                module configures the emitters only where it is true.
              '';
            };
            envelopeBudget = lib.mkOption {
              type = lib.types.nullOr lib.types.attrs;
              default = null;
              description = ''
                flake.lib.otelEnvelope's `budget`, { storeUrl; notifiedUnits;
                databases; }, set by the clan ingress role: otel-envelope then
                also judges the store's series and row budget hourly as the
                store's `regulator`, whose password it loads as the
                regulator-password credential (design D8).
              '';
            };
          };

          config = {
            services.opentelemetry-collector = {
              enable = true;
              package = pkgs.opentelemetry-collector-contrib;
              settings.processors.memory_limiter = {
                check_interval = "1s";
                limit_mib = 384;
              };
              # Every exporter's persistent queue, and the file and journal
              # receivers' offsets.
              settings.extensions.file_storage = {
                directory = "${stateDir}/queue";
                create_directory = true;
              };
              settings.service.extensions = [ "file_storage" ];
            };
            # nixpkgs restarts the collector after 100 ms, so five quick start
            # failures would hit systemd's default start limit and leave it
            # failed for good.
            systemd.services.opentelemetry-collector = {
              startLimitIntervalSec = 0;
              serviceConfig.RestartSec = "5s";
            };
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

      # The filesystem scraper's mountpoints, read in this one place from the
      # host's own fileSystems (design D4).
      zfsMounts = lib.sort lib.lessThan (
        map (fs: fs.mountPoint) (
          builtins.filter (fs: fs.fsType == "zfs") (builtins.attrValues config.fileSystems)
        )
      );

      # Where the agent's pipelines end: the in-process `forward` connector on
      # the ingress host, the mTLS exporters to otlp/mesh elsewhere.
      ingress = config.vanixiets.otelCollector.ingress;
      agentTelemetry = config.vanixiets.otelCollector.agentTelemetry;
      agentExport =
        if ingress then
          {
            metrics = [ "forward" ];
            logs = [ "forward" ];
            agentEvents = [ "forward" ];
            agentSpans = [ "forward" ];
          }
        else
          {
            metrics = [ "otlp_http/ingress" ];
            logs = [ "otlp_http/ingress-logs" ];
            # Agent events take their own logs-only exporter and queue, so
            # neither they nor the deploy records crowd the other out, and an
            # exporter carries one signal, whose queue the assertion below
            # sizes (agent-session-telemetry design D10).
            agentEvents = [ "otlp_http/ingress-agent" ];
            # And omp's spans theirs, traces only (design D13).
            agentSpans = [ "otlp_http/ingress-traces" ];
          };
      # The queues of a host that is not the ingress (design D10): the
      # metrics queue holds 24 h of fleet and, with agent telemetry, agent
      # metrics, and the agent events queue 8 h of agent events, all below
      # 512 MiB; the assertion below judges them against schema.nix's rates.
      agentQueueBytes = {
        "otlp_http/ingress" = mib (if agentTelemetry then 408 else 400);
        "otlp_http/ingress-logs" = mib 16;
        "otlp_http/ingress-agent" = mib 64;
        # 20,971,520 B at agentSpanBytesPerMinute holds 3.5 h (design D13).
        "otlp_http/ingress-traces" = mib 20;
      };
      ingressExporter = queueSize: {
        endpoint = "https://[${flakeLib.hosts.magnetite.zerotier.address}]:4318";
        tls = {
          ca_file = config.vanixiets.otelCollector.caFile;
          cert_file = "${credentialsDir}/otel-cert";
          key_file = "${credentialsDir}/otel-key";
          min_version = "1.3";
        };
        sending_queue = {
          storage = "file_storage";
          sizer = "bytes";
          queue_size = queueSize;
        };
        # A persistent queue drops an item whose retries run out, so
        # retries never stop while the ingress is unreachable.
        retry_on_failure = {
          enabled = true;
          max_interval = "60s";
          max_elapsed_time = "0s";
        };
      };

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

      # Design D6: relations within one host, judged on every agent host.
      services = config.systemd.services;
      notified = config.services.observability-notify.units;
      unitRegex = p: builtins.replaceStrings [ "." "*" ] [ "\\." ".*" ] p;
      # ADR-004's cap counts allow-listed services except notifier instances,
      # which the host's notified units bound.
      capped = builtins.filter (
        n:
        builtins.match (unitRegex schema.systemdUnitsNotifierPattern) "${n}.service" == null
        && lib.any (p: builtins.match (unitRegex p) "${n}.service" != null) schema.systemdUnits
      ) (builtins.attrNames services);
      owners = lib.concatMap (
        n:
        let
          m = builtins.match "omnigent-host-(.+)" n;
        in
        lib.optional (m != null) (builtins.head m)
      ) (builtins.attrNames services);
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
              assertion =
                !(
                  config.services.prometheus.exporters.node.openFirewall
                  || config.services.prometheus.exporters.smartctl.openFirewall
                );
              message = "otel-collector agent: node_exporter and the smartctl exporter must not open the firewall; they are scraped on loopback (ADR-003 items 18-20).";
            }
            {
              assertion =
                lib.all (u: (services.${u}.serviceConfig or { }) ? ExecStart) notified
                && builtins.elem "opentelemetry-collector" notified
                && builtins.elem "otel-envelope" notified;
              message = "otel-collector agent: ${hostName}'s notified units ${builtins.toJSON notified} must be services with an ExecStart and include opentelemetry-collector and otel-envelope (design D6, D7).";
            }
            {
              assertion = builtins.length capped <= schema.budget.units;
              message = "otel-collector agent: ${toString (builtins.length capped)} of ${hostName}'s services match the unit allow-list, above ADR-004's ${toString schema.budget.units}: ${builtins.toJSON capped}";
            }
            {
              assertion =
                lib.all (o: schema.ownerAliases ? ${o}) owners
                && lib.all (a: lib.all (o: !(lib.hasInfix o a)) owners) (builtins.attrValues schema.ownerAliases);
              message = "otel-collector agent: every omnigent-host-<owner> service on ${hostName} needs an alias in ownerAliases that does not contain an owner's name; owners ${builtins.toJSON owners}";
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
                # A process whose comm fills the kernel's 15 bytes is named by
                # the base of its argv[0] (gopsutil@v4.26.5:process/process_linux.go:847-860),
                # which a process that rewrites its title, as Chromium does,
                # fills with its whole command line. Cut the name at its first
                # space, so that no command line reaches the store (ADR-004's
                # label bans) or mints a series per launch.
                "transform/process-name".metric_statements = [
                  ''replace_pattern(resource.attributes["process.executable.name"], "^([^ ]{15,}) .*$", "$$1")''
                ];
                # Compaction (empty keys) and aggregate_labels are meant to sum
                # same-named processes, but aggregate_labels keys points by the
                # full nanosecond timestamp, which the scraper stamps per
                # process, so each process keeps its own point (ADR-003 item 16).
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
                    ''metric.name == "process.memory.usage" and datapoint.value_int < ${toString schema.process.minBytes.linux}''
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
                  }
                  # Only the host's ZFS mountpoints, by strict match, so
                  # container runtime mounts under /var/lib/docker stay out
                  # (design D4; ADR-003 item 26). An empty strict list is no
                  # filter in otelcol, so a host without ZFS gets no scraper.
                  // lib.optionalAttrs (zfsMounts != [ ]) {
                    filesystem = {
                      # /proc/filesystems lists zfs as nodev, and the scraper
                      # drops virtual filesystems unless told otherwise
                      # (filesystem_scraper.go:75 at otelcol 0.155.0), which
                      # would discard every ZFS mount; the strict list below
                      # still limits it to the ZFS datasets.
                      include_virtual_filesystems = true;
                      include_mount_points = {
                        match_type = "strict";
                        mount_points = zfsMounts;
                      };
                      metrics = {
                        "system.filesystem.usage".enabled = true;
                        "system.filesystem.inodes.usage".enabled = false;
                        "system.filesystem.utilization".enabled = false;
                      };
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
                # A service's scrape only where it runs: a target that is
                # never up would be a permanently down target (design D4).
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
                ]
                ++ lib.optional config.services.gitea.enable (scrape "gitea" "127.0.0.1:3002" { })
                ++ lib.optional (config.services.niks3.enable or false) (scrape "niks3" "127.0.0.1:5752" { })
                ++ lib.optional (config.services.nixbot.enable or false) (scrape "nixbot" "127.0.0.1:9180" { })
                ++ lib.optional (config.services.greptimedb.enable or false) (
                  scrape "greptimedb" "127.0.0.1:4000" { }
                )
                ++ [
                  # The collector's own queue, failure and refusal counters
                  # (design D4; ADR-003 item 26).
                  (scrape "otelcol" "127.0.0.1:8888" {
                    metric_relabel_configs = [
                      {
                        source_labels = [ "__name__" ];
                        regex = lib.concatStringsSep "|" schema.otelcolKeep;
                        action = "keep";
                      }
                      # A new identifier at every collector start (ADR-004's process-identifier ban).
                      {
                        regex = "service_instance_id";
                        action = "labeldrop";
                      }
                    ];
                  })
                ];
              };

              # The ingress receives the agent's pipelines in-process.
              connectors = lib.mkIf ingress { forward = { }; };

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
                  exporters = agentExport.metrics;
                };
                "metrics/process" = {
                  receivers = [ "host_metrics/process" ];
                  processors = [
                    "memory_limiter"
                    "transform/process-name"
                    "groupbyattrs/compact"
                    "metrics_transform/process"
                    "filter/process-min"
                    "resource/agent"
                  ];
                  exporters = agentExport.metrics;
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

          systemd.services.prometheus-node-exporter.serviceConfig.MemoryMax = "64M";

          # R3.2 from the host's own collector (design D7): its telemetry,
          # queues and loss counters, and the targets it scrapes and the
          # exporters it runs, both read from its settings so the two cannot
          # drift. A target's bearer credential is read from
          # this unit's credentials under the same name. On the ingress host
          # it also judges the store's budget hourly (design D8).
          systemd.services.otel-envelope = {
            description = "Collector delivery envelope (ADR-003 R3.2)";
            after = [ "opentelemetry-collector.service" ];
            serviceConfig = {
              Type = "oneshot";
              DynamicUser = true;
              StateDirectory = "otel-envelope";
              MemoryMax = "64M";
              TimeoutStartSec = "4min";
              ExecStart = lib.getExe (
                flakeLib.otelEnvelope pkgs {
                  inherit hostName ingress;
                  targets = flakeLib.otelEnvelopeTargets config.services.opentelemetry-collector.settings.receivers;
                  exporters = builtins.attrNames config.services.opentelemetry-collector.settings.exporters;
                  budget = config.vanixiets.otelCollector.envelopeBudget;
                }
              );
            };
          };
          systemd.timers.otel-envelope = {
            wantedBy = [ "timers.target" ];
            # UTC: in a daylight-saving zone such as pyrite's, systemd
            # computes a local calendar's next elapse across the autumn
            # change as an hour later, so the timer would skip an hour.
            timerConfig.OnCalendar = "*:0/5 UTC";
          };
        }

        # Every agent host's deploy records into devloop.deploy_record, with the
        # receiver id and settings magnetite has used since S2, so its stored
        # offset carries over (S4 design D5). On an ingress host the records
        # reach the store only through `logs/ingress`, which exists where the
        # store declares the devloop pipelines; without it, `forward` would be
        # an exporter with no receiving pipeline and fail validation.
        (lib.mkIf (!ingress || (config.services.greptimedb.pipelines.devloop or { }) != { }) {
          services.opentelemetry-collector.settings =
            let
              inherit (flakeLib.devloopCollection) keepAttributes dropBody deployRecordFile;
            in
            {
              receivers."file_log/deploy-record" = {
                include = [ deployRecordFile ];
                start_at = "beginning";
                storage = "file_storage";
                operators = [
                  {
                    type = "json_parser";
                    id = "parse-line";
                  }
                  (keepAttributes (map (column: column.name) schema.devloop.tables.deploy_record.columns))
                  dropBody
                ];
              };
              processors."resource/devloop-deploy_record".attributes = [
                {
                  key = "vanixiets.database";
                  value = "devloop";
                  action = "upsert";
                }
                {
                  key = "vanixiets.table";
                  value = "deploy_record";
                  action = "upsert";
                }
                {
                  key = "host.name";
                  value = hostName;
                  action = "upsert";
                }
              ];
              service.pipelines."logs/devloop-deploy_record" = {
                receivers = [ "file_log/deploy-record" ];
                processors = [
                  "memory_limiter"
                  "resource/devloop-deploy_record"
                ];
                exporters = agentExport.logs;
              };
            };
        })

        # The agent's envelope where it exports to the ingress (ADR-003
        # envelope; design D2; agent-session-telemetry design D10): every
        # exporter of the host against schema.nix's rate assumptions, and the
        # limiter against the unit's ceiling.
        (lib.mkIf (!config.vanixiets.otelCollector.ingress) {
          assertions =
            let
              settings = config.services.opentelemetry-collector.settings;
              e = settings.exporters or { };
              exporterNames = builtins.attrNames e;
              q = n: e.${n}.sending_queue or { };
              size = n: (q n).queue_size or 0;
              memMax = builtins.match "([0-9]+)M" (
                config.systemd.services.opentelemetry-collector.serviceConfig.MemoryMax or ""
              );
              limit = settings.processors.memory_limiter.limit_mib or 0;
              metricsPerMinute =
                schema.fleetBytesPerMinute + (if agentTelemetry then schema.agentMetricsBytesPerMinute else 0);
              metricsPipelinesWith =
                exporter:
                builtins.filter (
                  name:
                  lib.hasPrefix "metrics" name && builtins.elem exporter settings.service.pipelines.${name}.exporters
                ) (builtins.attrNames settings.service.pipelines);
            in
            [
              {
                assertion =
                  lib.all (
                    n:
                    (q n).storage or null == "file_storage"
                    && (q n).sizer or null == "bytes"
                    && (e.${n}.retry_on_failure.max_elapsed_time or null) == "0s"
                  ) exporterNames
                  && size "otlp_http/ingress" >= 24 * 60 * metricsPerMinute
                  && (!agentTelemetry || size "otlp_http/ingress-agent" >= 8 * 60 * schema.agentEventBytesPerMinute)
                  && (!agentTelemetry || size "otlp_http/ingress-traces" >= 3 * 60 * schema.agentSpanBytesPerMinute)
                  && lib.foldl' (s: n: s + size n) 0 exporterNames < mib 512
                  && memMax != null
                  && limit < lib.toInt (builtins.head memMax);
                message = "otel-collector agent on ${hostName}: every exporter must queue in file_storage by bytes with unlimited retry, otlp_http/ingress must hold 24 h at fleetBytesPerMinute${lib.optionalString agentTelemetry " plus agentMetricsBytesPerMinute, otlp_http/ingress-agent 8 h at agentEventBytesPerMinute, otlp_http/ingress-traces 3 h at agentSpanBytesPerMinute"}, the queues must sum below 512 MiB, and the limiter must be below MemoryMax (ADR-003 envelope; design D2); queues ${builtins.toJSON (lib.genAttrs exporterNames size)}.";
              }
              # An exporter keeps one persistent queue per signal
              # (exporter_otlp_http_<name>_<signal>), so a metrics pipeline
              # on the agent events exporter would hold a second queue the
              # sum above does not see (design D10).
              {
                assertion = metricsPipelinesWith "otlp_http/ingress-agent" == [ ];
                message = "otel-collector agent on ${hostName}: otlp_http/ingress-agent carries agent events only, but the metrics pipelines ${builtins.toJSON (metricsPipelinesWith "otlp_http/ingress-agent")} export to it (agent-session-telemetry design D10).";
              }
            ];
        })

        # Every host but the ingress exports over mTLS to otlp/mesh on
        # magnetite's ZeroTier address, under its own envelope (design D2).
        (lib.mkIf (!ingress) {
          services.opentelemetry-collector.settings = {
            processors.memory_limiter = {
              limit_mib = lib.mkForce 150;
              spike_limit_mib = 30;
            };
            exporters."otlp_http/ingress" = ingressExporter agentQueueBytes."otlp_http/ingress";
            exporters."otlp_http/ingress-logs" = ingressExporter agentQueueBytes."otlp_http/ingress-logs";
          };
          systemd.services.opentelemetry-collector.serviceConfig.MemoryMax = "256M";
        })

        # Agent sessions' telemetry, where the host table sets agentTelemetry
        # (agent-session-telemetry design D3, D8): `otlp/local` on loopback
        # feeds exactly the three agent-session pipelines, each of which drops
        # every service, metric, event, span key and key off schema.nix's
        # agentSession allow-list before it stamps the host and the routing
        # attributes. Every filter and transform but the prompt copy
        # propagates its errors, so a statement that cannot run refuses the
        # batch rather than passing it on; the prompt copy ignores its own,
        # since the span allow-list after it drops what it would have read.
        (lib.mkIf agentTelemetry (
          let
            session = schema.agentSession;
            eventNames = builtins.attrNames session.events.keys;
            list = keys: "[${lib.concatMapStringsSep ", " (key: ''"${key}"'') keys}]";
            oneOf = path: values: lib.concatMapStringsSep " or " (value: ''${path} == "${value}"'') values;
            serviceName = ''resource.attributes["service.name"]'';
            eventName = ''log.attributes["event.name"]'';
            stamp =
              extra:
              [
                {
                  key = "host.name";
                  value = hostName;
                  action = "upsert";
                }
                {
                  key = "vanixiets.database";
                  value = "agent";
                  action = "upsert";
                }
              ]
              ++ extra;
          in
          {
            assertions = [
              {
                assertion = !ingress || (config.services.greptimedb.pipelines.agent or { }) ? agent_session_event;
                message = "otel-collector agent on ${hostName}: agent telemetry on the ingress host needs the store's agent_session_event pipeline (flake.modules.nixos.agent-session-store), which the ingress routes agent events through (agent-session-telemetry design D5).";
              }
            ];

            # omp's chat spans arrive several MiB at a time, each request
            # decoded on the heap the fleet pipelines share. The Go runtime
            # collects before the cgroup's ceiling rather than letting garbage
            # reach it, and the span pipeline has its own limiter whose soft
            # limit sits a third below the shared limiter's, so agent spans
            # are refused before a fleet scrape is (design D13).
            systemd.services.opentelemetry-collector.serviceConfig.Environment =
              let
                memoryMax = lib.toInt (
                  lib.removeSuffix "M" config.systemd.services.opentelemetry-collector.serviceConfig.MemoryMax
                );
              in
              [ "GOMEMLIMIT=${toString (memoryMax * 4 / 5)}MiB" ];

            services.opentelemetry-collector.settings = {
              receivers."otlp/local".protocols.http.endpoint = "127.0.0.1:4318";

              processors = {
                "memory_limiter/agent-session" =
                  let
                    shared = config.services.opentelemetry-collector.settings.processors.memory_limiter;
                    sharedSoft = shared.limit_mib - (shared.spike_limit_mib or (shared.limit_mib / 5));
                  in
                  {
                    check_interval = "1s";
                    limit_mib = sharedSoft;
                    spike_limit_mib = sharedSoft / 3;
                  };
                "filter/agent-session-service" = {
                  error_mode = "propagate";
                  metric_conditions = [ "not (${oneOf serviceName session.metrics.services})" ];
                  log_conditions = [ "not (${oneOf serviceName session.events.services})" ];
                  trace_conditions = [ "not (${oneOf serviceName session.spans.services})" ];
                };
                "filter/agent-session-metrics" = {
                  error_mode = "propagate";
                  metric_conditions = [ "not (${oneOf "metric.name" session.metrics.names})" ];
                };
                "filter/agent-session-events" = {
                  error_mode = "propagate";
                  log_conditions = [ "not (${oneOf eventName eventNames})" ];
                };
                "transform/agent-session-metrics" = {
                  error_mode = "propagate";
                  metric_statements = [
                    "keep_keys(datapoint.attributes, ${list session.metrics.pointKeys})"
                    "keep_keys(resource.attributes, ${list session.metrics.resourceKeys})"
                    "keep_keys(scope.attributes, [])"
                  ];
                };
                # Per event, its own keys and the correlation keys; the body,
                # which ADR-008:42's redaction cannot protect, is replaced.
                "transform/agent-session-events" = {
                  error_mode = "propagate";
                  log_statements =
                    map (
                      event:
                      ''keep_keys(log.attributes, ${
                        list (session.events.correlationKeys ++ session.events.keys.${event})
                      }) where ${eventName} == "${event}"''
                    ) eventNames
                    ++ [
                      ''set(log.body, "")''
                      "keep_keys(resource.attributes, ${list session.events.resourceKeys})"
                      "keep_keys(scope.attributes, [])"
                    ];
                };
                "resource/agent-session".attributes = stamp [ ];
                "resource/agent-session-events".attributes = stamp [
                  {
                    key = "vanixiets.table";
                    value = "session_event";
                    action = "upsert";
                  }
                ];
                # omp's gen_ai.input.messages holds the whole conversation,
                # earlier tool results included (design D13): the text of its
                # newest message, when that is a user text message, becomes
                # `prompt`, and the allow-list below drops the attribute itself.
                # Only the attribute's last 64 KiB is searched and only the
                # matched text is parsed: parsing the whole history, often
                # several MiB, held about ten times its size on the heap the
                # fleet pipelines share. A newest message longer than that
                # yields no prompt.
                "transform/agent-session-prompt" =
                  let
                    source = ''span.attributes["${session.spans.promptSource}"]'';
                  in
                  {
                    error_mode = "ignore";
                    trace_statements = [
                      ''set(span.cache["t"], ${source}) where ${source} != nil and Len(${source}) <= 65536''
                      ''set(span.cache["t"], Substring(${source}, Len(${source}) - 65536, 65536)) where ${source} != nil and Len(${source}) > 65536''
                      ''set(span.cache["x"], ExtractPatterns(span.cache["t"], "\\{\\s*\"role\"\\s*:\\s*\"user\"\\s*,\\s*\"parts\"\\s*:\\s*\\[\\s*\\{\\s*\"type\"\\s*:\\s*\"text\"\\s*,\\s*\"content\"\\s*:\\s*\"(?P<c>(?:[^\"\\\\]|\\\\.)*)\"\\s*\\}(?:\\s*,\\s*\\{[^\\[\\]]*\\})*\\s*\\]\\s*\\}\\s*\\]\\s*$")) where span.cache["t"] != nil''
                      ''set(span.cache["p"], ParseJSON(Concat(["[\"", span.cache["x"]["c"], "\"]"], ""))) where span.cache["x"]["c"] != nil''
                      ''set(span.attributes["prompt"], span.cache["p"][0]) where span.cache["p"] != nil''
                    ];
                  };
                # Every span event, exceptions included, whatever its name.
                "filter/agent-session-span-events" = {
                  error_mode = "propagate";
                  trace_conditions = [ ''spanevent.name != "" or spanevent.name == ""'' ];
                };
                "transform/agent-session-spans" = {
                  error_mode = "propagate";
                  trace_statements = [
                    "keep_keys(span.attributes, ${list (builtins.attrNames session.spans.keys)})"
                    ''set(span.status.message, "")''
                    "keep_keys(resource.attributes, ${list session.spans.resourceKeys})"
                    "keep_keys(scope.attributes, [])"
                  ];
                };
              };

              exporters = lib.mkIf (!ingress) {
                "otlp_http/ingress-agent" = ingressExporter agentQueueBytes."otlp_http/ingress-agent";
                "otlp_http/ingress-traces" = ingressExporter agentQueueBytes."otlp_http/ingress-traces";
              };

              service.pipelines = {
                "metrics/agent-session" = {
                  receivers = [ "otlp/local" ];
                  processors = [
                    "memory_limiter"
                    "filter/agent-session-service"
                    "filter/agent-session-metrics"
                    "transform/agent-session-metrics"
                    "resource/agent-session"
                  ];
                  exporters = agentExport.metrics;
                };
                "logs/agent-session" = {
                  receivers = [ "otlp/local" ];
                  processors = [
                    "memory_limiter"
                    "filter/agent-session-service"
                    "filter/agent-session-events"
                    "transform/agent-session-events"
                    "resource/agent-session-events"
                  ];
                  exporters = agentExport.agentEvents;
                };
                "traces/agent-session" = {
                  receivers = [ "otlp/local" ];
                  processors = [
                    "memory_limiter/agent-session"
                    "filter/agent-session-service"
                    "transform/agent-session-prompt"
                    "filter/agent-session-span-events"
                    "transform/agent-session-spans"
                    "resource/agent-session"
                  ];
                  exporters = agentExport.agentSpans;
                };
              };
            };
          }
        ))

        # NVMe health where the host table lists devices (ADR-003 item 19;
        # design D4).
        (lib.mkIf (config.vanixiets.otelCollector.smartDevices != [ ]) {
          services.prometheus.exporters.smartctl = {
            enable = true;
            listenAddress = "127.0.0.1";
            port = 9633;
            devices = config.vanixiets.otelCollector.smartDevices;
            openFirewall = false;
            # smartctl_exporter 0.15.0 hard-codes `--log=error` and drops a device
            # whenever smartctl reports any error message; pyrite's APPLE SSD
            # rejects the Error Information log page (0x01) with Invalid Log Page,
            # so the exporter would never publish its health. No kept series reads
            # that log (the error count comes from the health log), and a failed
            # health-log read still errors and drops the device, so only the
            # unread error-log flag is removed, as the darwin probe's `-H -A` does.
            extraFlags = [
              "--smartctl.path=${pkgs.writeShellScript "smartctl-without-error-log" ''
                args=()
                for a in "$@"; do
                  [ "$a" = --log=error ] || args+=("$a")
                done
                exec ${lib.getExe pkgs.smartmontools} "''${args[@]}"
              ''}"
            ];
          };
          systemd.services.prometheus-smartctl-exporter.serviceConfig = {
            MemoryMax = "64M";
            # The module's udev rule grants this ACL only on an `add` event, which a
            # switch does not replay (GR §5; design D4); `+` runs it privileged.
            ExecStartPre = map (
              d: "+${pkgs.acl}/bin/setfacl -m g:smartctl-exporter-access:rw ${d}"
            ) config.vanixiets.otelCollector.smartDevices;
          };
          services.opentelemetry-collector.settings.receivers.prometheus.config.scrape_configs = [
            (scrape "smartctl" "127.0.0.1:9633" {
              metric_relabel_configs = [
                {
                  source_labels = [ "__name__" ];
                  regex = lib.concatStringsSep "|" schema.smartctlKeep;
                  action = "keep";
                }
              ];
            })
          ];
        })

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
          # The envelope probes the zerotierone target with the same token.
          systemd.services.otel-envelope.serviceConfig.LoadCredential = [
            "zerotier-metricstoken:/var/lib/zerotier-one/metricstoken.secret"
          ];

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

        # PostgreSQL collation drift (F61, Q68a): the sqlquery receiver of
        # flake.lib.postgresqlCollation reads pg_database every 60 s as the
        # collector's own role, peer-authenticated on the local socket, into
        # metrics/host, which stamps host.name and the fleet database.
        (lib.mkIf config.services.postgresql.enable {
          # Duplicates devloop-collection's entry on magnetite; remove it only with the next intentional ensureUsers change, as any setup change restarts PostgreSQL (see README).
          services.postgresql.ensureUsers = [ { name = "opentelemetry-collector"; } ];
          services.opentelemetry-collector.settings = {
            receivers."sqlquery/postgresql-collation" = flakeLib.postgresqlCollation.receiver {
              datasource = "host=/run/postgresql dbname=postgres user=opentelemetry-collector sslmode=disable";
              parked = config.vanixiets.postgresqlCollation.parkedDatabases;
            };
            service.pipelines."metrics/host".receivers = [ "sqlquery/postgresql-collation" ];
          };
        })

        # F78: on 2026-11-19 at 03:09:10Z a deploy stopped the collector and
        # PostgreSQL in one transaction with no ordering between them;
        # PostgreSQL's fast shutdown closed the sqlquery receivers'
        # connections at 03:09:11.10, and their shutdown then wrote to the
        # closed sockets, so the collector exited 1 ("failed to shutdown
        # pipelines: write unix @->/run/postgresql/.s.PGSQL.5432: write:
        # broken pipe", twice) and posted a FAILED notice. After= makes
        # systemd stop the collector before PostgreSQL, and start it after.
        {
          assertions = [
            {
              assertion =
                !lib.any (r: lib.hasInfix "host=/run/postgresql" (r.datasource or "")) (
                  lib.attrValues (config.services.opentelemetry-collector.settings.receivers or { })
                )
                || lib.elem "postgresql.service" config.systemd.services.opentelemetry-collector.after;
              message = "otel-collector agent on ${hostName}: a receiver reads the local PostgreSQL, so opentelemetry-collector.service must be After=postgresql.service, or a deploy restarting both stops PostgreSQL first and the collector exits 1 on its broken connections (F78).";
            }
          ];
          systemd.services.opentelemetry-collector.after = lib.mkIf config.services.postgresql.enable [
            "postgresql.service"
          ];
        }
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
      assertions = lib.optional (config.services.greptimedb.enable or false) {
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
        # passes; on the ingress host its own spans arrive through forward.
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
              receivers = lib.optional config.vanixiets.otelCollector.agentTelemetry "forward" ++ [
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

        # The logs entry, wherever a logs route exists.
        (lib.mkIf (devloopLogs || agentLogs) {
          settings.service.pipelines."logs/ingress" = {
            receivers = [
              "forward"
              "otlp/mesh"
              "otlp/mesh-tincr"
            ];
            processors = [ "memory_limiter" ];
            exporters = [ "routing/logs" ];
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

  flake.clan.modules.otel-collector =
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
          { roles, machine, ... }:
          let
            # One definition of the CA and the certificate for both module
            # classes; clan compares a shared generator's files, prompts,
            # dependencies and validation across machines and ignores owner,
            # group and mode (clan_lib/vars/generator.py:106-116).
            otelGenerators =
              { lib, pkgs }:
              let
                isIngress = roles.ingress.machines ? ${machine.name};
                host = flakeLib.hosts.${machine.name};
                # The ingress is named on both transports while ZeroTier runs.
                sans = lib.optionalString isIngress (
                  lib.concatStringsSep "," [
                    "IP:${host.zerotier.address}"
                    "DNS:${machine.name}.zt"
                    "IP:${host.address}"
                    "DNS:${host.fqdn}"
                  ]
                );
                usage = if isIngress then "serverAuth,clientAuth" else "clientAuth";
              in
              {
                # Shared: every agent trusts one CA; its key signs at generation time
                # only and is never deployed (ADR-003 Q2; design D1).
                otel-ca = {
                  share = true;
                  files."ca.key".deploy = false;
                  files."ca.crt".secret = false;
                  runtimeInputs = [ pkgs.openssl ];
                  script = ''
                    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$out"/ca.key
                    openssl req -x509 -new -key "$out"/ca.key -sha256 -days 3650 -subj "/CN=otel-ca" \
                      -addext "basicConstraints=critical,CA:TRUE" \
                      -addext "keyUsage=critical,keyCertSign,cRLSign" \
                      -addext "subjectKeyIdentifier=hash" -out "$out"/ca.crt
                  '';
                };
                # The SANs and the usage enter validation, so moving a host into the
                # ingress role regenerates its certificate (design D1).
                otel-cert = {
                  dependencies = [ "otel-ca" ];
                  files."cert.pem".secret = false;
                  validation = {
                    subjectAltNames = sans;
                    extendedKeyUsage = usage;
                  };
                  runtimeInputs = [ pkgs.openssl ];
                  script = ''
                    openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$out"/key.pem
                    openssl req -new -key "$out"/key.pem -subj "/CN=${machine.name}" -out cert.csr
                    {
                      echo "basicConstraints=critical,CA:FALSE"
                      echo "keyUsage=critical,digitalSignature"
                      echo "extendedKeyUsage=${usage}"
                      ${lib.optionalString isIngress ''echo "subjectAltName=${sans}"''}
                    } > cert.ext
                    openssl x509 -req -in cert.csr -CA "$in"/otel-ca/ca.crt -CAkey "$in"/otel-ca/ca.key \
                      -set_serial "0x$(openssl rand -hex 16)" -sha256 -days 3650 -extfile cert.ext -out "$out"/cert.pem
                  '';
                };
              };
          in
          {
            nixosModule =
              {
                config,
                lib,
                pkgs,
                ...
              }:
              let
                # Static data, so it can select imports without evaluating the host (design D6).
                collect = flakeLib.observabilityHosts.${machine.name}.collect;
                restart = lib.optional collect "opentelemetry-collector.service";
                gens = config.clan.core.vars.generators;
              in
              {
                # Declared on every agent host, so one vars step covers all six; on a host
                # that does not collect yet they are uploaded files no unit reads.
                imports = [
                  nixosModules.ntfy-alerter
                ]
                ++ lib.optional collect nixosModules.otel-collector-agent;

                config = lib.mkMerge [
                  {
                    # restartUnits only here: clan throws on it on darwin
                    # (clan-core generic-generator.nix:193-208; design D5).
                    clan.core.vars.generators = lib.mkMerge [
                      (otelGenerators { inherit lib pkgs; })
                      {
                        otel-cert.files."key.pem".restartUnits = restart;
                        otel-cert.files."cert.pem".restartUnits = restart;
                      }
                    ];
                  }
                  # ca.crt reaches the collector as a store path, so a new CA changes
                  # the configuration and restarts it (design D1). The credentials
                  # load on the ingress host too, where otlp/mesh presents them.
                  # optionalAttrs, not mkIf: where collect is false these options
                  # are not declared, and collect is static data.
                  (lib.optionalAttrs collect {
                    vanixiets.otelCollector.caFile = pkgs.writeText "otel-ca.crt" gens.otel-ca.files."ca.crt".value;
                    vanixiets.otelCollector.smartDevices = flakeLib.observabilityHosts.${machine.name}.smartDevices;
                    vanixiets.otelCollector.agentTelemetry = flakeLib.observabilityHosts.${machine.name}.agentTelemetry;
                    services.observability-notify = {
                      units = flakeLib.observabilityHosts.${machine.name}.notifiedUnits;
                      tokenFile = gens.ntfy-alerter.files.token.path;
                    };
                    systemd.services.opentelemetry-collector.serviceConfig.LoadCredential = [
                      "otel-cert:${gens.otel-cert.files."cert.pem".path}"
                      "otel-key:${gens.otel-cert.files."key.pem".path}"
                    ];
                  })
                ];
              };

            # Every darwin row, whatever its collect: the collector's account
            # and its three secrets, so the files have their owner before any
            # collector runs; the fragment only where collect is true (design
            # D1, D2, D5). nix-darwin has no tmpfiles and no restartUnits:
            # the fragment's OTEL_CERT_SHA256 reloads the agent on a reissue.
            darwinModule =
              {
                lib,
                pkgs,
                ...
              }:
              let
                # Static data, so it can select imports without evaluating the host (design D6).
                collect = flakeLib.observabilityHosts.${machine.name}.collect;
                otelcol = {
                  owner = "_otelcol";
                  group = "_otelcol";
                  mode = "0400";
                };
              in
              {
                imports = [
                  darwinModules.ntfy-alerter
                ]
                ++ lib.optional collect darwinModules.otel-collector-agent;

                # As nix-grpc-store's darwin module declares nix-grpc-daemon.
                users.knownGroups = [ "_otelcol" ];
                users.knownUsers = [ "_otelcol" ];
                users.groups._otelcol.gid = 536;
                users.users._otelcol = {
                  uid = 536;
                  gid = 536;
                  home = "/var/empty";
                  shell = "/usr/bin/false";
                  isHidden = true;
                  description = "OpenTelemetry collector agent";
                };

                clan.core.vars.generators = lib.mkMerge [
                  (otelGenerators { inherit lib pkgs; })
                  {
                    otel-cert.files."key.pem" = otelcol // {
                      neededFor = "services";
                    };
                    ntfy-alerter.files.token = {
                      inherit (otelcol) owner mode;
                    };
                  }
                ];
              };
          };
      };

      roles.ingress = {
        description = "Writes collected metrics into the telemetry store";
        interface = { };
        perInstance =
          { ... }:
          {
            nixosModule =
              { config, lib, ... }:
              {
                imports = [ nixosModules.otel-collector-ingress ];
                systemd.services.opentelemetry-collector.serviceConfig.LoadCredential = [
                  "collector-password:${config.clan.core.vars.generators.greptimedb-users.files.collector-password.path}"
                ];
                # The hourly budget over the store, read as `regulator`
                # (design D8); the envelope reads every host's notified units.
                vanixiets.otelCollector.envelopeBudget = {
                  storeUrl = "http://127.0.0.1:4000";
                  notifiedUnits = lib.mapAttrs (_: h: h.notifiedUnits) flakeLib.observabilityHosts;
                  databases = schema.databases;
                };
                systemd.services.otel-envelope = {
                  after = [ "greptimedb.service" ];
                  serviceConfig.LoadCredential = [
                    "regulator-password:${config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path}"
                  ];
                };
                # otlp/mesh, on the mesh interfaces only. magnetite's
                # net.ipv6.ip_nonlocal_bind = 1 lets the receiver bind its
                # address before the mesh daemon holds it.
                networking.firewall.interfaces = lib.genAttrs (flakeLib.meshInterfaces config) (_: {
                  allowedTCPPorts = [ 4318 ];
                });
              };
          };
      };
    };
}

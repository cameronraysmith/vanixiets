# The agent fragment, flake.modules.nixos.otel-collector-agent, which the
# clan agent role imports on each collecting host (see service.nix).
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
  inherit (import ./_shared.nix { inherit config; })
    nixosModules
    flakeLib
    schema
    credentialsDir
    agentSessionUnit
    agentSessionStateDir
    agentSessionCredentials
    agentSessionTelemetryPort
    mib
    collectorCore
    ;
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
          }
        else
          {
            metrics = [ "otlp_http/ingress" ];
            logs = [ "otlp_http/ingress-logs" ];
          };
      ingressEndpoint = "https://[${flakeLib.hosts.magnetite.zerotier.address}]:4318";
      ingressExporter = flakeLib.otelMtlsExporter {
        endpoint = ingressEndpoint;
        caFile = config.vanixiets.otelCollector.caFile;
        certFile = "${credentialsDir}/otel-cert";
        keyFile = "${credentialsDir}/otel-key";
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
                && builtins.elem "otel-envelope" notified
                && (
                  !agentTelemetry
                  || builtins.elem agentSessionUnit notified && builtins.elem "${agentSessionUnit}-envelope" notified
                );
              message = "otel-collector agent: ${hostName}'s notified units ${builtins.toJSON notified} must be services with an ExecStart and include opentelemetry-collector and otel-envelope${lib.optionalString agentTelemetry ", and with agent telemetry ${agentSessionUnit} and ${agentSessionUnit}-envelope"} (design D6, D7; agent-session-telemetry design D14).";
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
                ++ lib.optional (config.services ? greptimedb) (scrape "greptimedb" "127.0.0.1:4000" { })
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
                ]
                # The agent-session collector's Langfuse sent and failed
                # span counters, for LangfuseSendFailing: two series, and
                # nothing else of that collector reaches fleet
                # (darwin-agent-session-telemetry design D9).
                ++ lib.optional config.vanixiets.otelCollector.langfuse (
                  scrape "otelcol-agent-session" "127.0.0.1:${toString agentSessionTelemetryPort}" {
                    metric_relabel_configs = [
                      {
                        source_labels = [ "__name__" ];
                        regex = lib.concatStringsSep "|" schema.otelcolAgentSessionKeep;
                        action = "keep";
                      }
                      {
                        source_labels = [ "exporter" ];
                        regex = "otlp_http/langfuse";
                        action = "keep";
                      }
                      {
                        regex = "service_instance_id";
                        action = "labeldrop";
                      }
                    ];
                  }
                );
              };

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

        # Every agent host's record files into their devloop tables: the
        # deploy record into devloop.deploy_record, with the receiver id and
        # settings magnetite has used since S2, so its stored offset carries
        # over (S4 design D5), and whatever a host adds to devloopRecordFiles,
        # as pyrite adds the weekly runtime-test results
        # (declare-test-size-classes design D11). On an ingress host the
        # records reach the store only through `logs/ingress`, which exists
        # where the store declares the devloop pipelines; without it,
        # `forward` would be an exporter with no receiving pipeline and fail
        # validation.
        (lib.mkIf (!ingress || (config.services.greptimedb.pipelines.devloop or { }) != { }) {
          vanixiets.otelCollector.devloopRecordFiles.deploy-record = {
            file = flakeLib.devloopCollection.deployRecordFile;
            table = "deploy_record";
          };
          services.opentelemetry-collector.settings =
            let
              inherit (flakeLib.devloopCollection) keepAttributes dropBody;
              recordFile = name: entry: {
                receivers."file_log/${name}" = {
                  include = [ entry.file ];
                  start_at = "beginning";
                  storage = "file_storage";
                  operators = [
                    {
                      type = "json_parser";
                      id = "parse-line";
                    }
                    (keepAttributes (map (column: column.name) schema.devloop.tables.${entry.table}.columns))
                    dropBody
                  ];
                };
                processors."resource/devloop-${entry.table}".attributes = [
                  {
                    key = "vanixiets.database";
                    value = "devloop";
                    action = "upsert";
                  }
                  {
                    key = "vanixiets.table";
                    value = entry.table;
                    action = "upsert";
                  }
                  {
                    key = "host.name";
                    value = hostName;
                    action = "upsert";
                  }
                ];
                service.pipelines."logs/devloop-${entry.table}" = {
                  receivers = [ "file_log/${name}" ];
                  processors = [
                    "memory_limiter"
                    "resource/devloop-${entry.table}"
                  ];
                  exporters = agentExport.logs;
                };
              };
            in
            lib.mkMerge (lib.mapAttrsToList recordFile config.vanixiets.otelCollector.devloopRecordFiles);
        })

        # The agent's envelope where it exports to the ingress (ADR-003
        # envelope; design D2): the queue literals below against SC's rate
        # assumption, and the limiter against the unit's ceiling.
        (lib.mkIf (!config.vanixiets.otelCollector.ingress) {
          assertions =
            let
              e = config.services.opentelemetry-collector.settings.exporters or { };
              agentExporters = [
                "otlp_http/ingress"
                "otlp_http/ingress-logs"
              ];
              q = n: e.${n}.sending_queue or { };
              memMax = builtins.match "([0-9]+)M" (
                config.systemd.services.opentelemetry-collector.serviceConfig.MemoryMax or ""
              );
              limit = config.services.opentelemetry-collector.settings.processors.memory_limiter.limit_mib or 0;
            in
            [
              {
                assertion =
                  lib.all (
                    n:
                    (q n).storage or null == "file_storage"
                    && (q n).sizer or null == "bytes"
                    && (e.${n}.retry_on_failure.max_elapsed_time or null) == "0s"
                  ) agentExporters
                  && ((q "otlp_http/ingress").queue_size or 0) >= 24 * 60 * schema.fleetBytesPerMinute
                  && lib.foldl' (s: n: s + ((q n).queue_size or 0)) 0 agentExporters < mib 512
                  && memMax != null
                  && limit < lib.toInt (builtins.head memMax);
                message = "otel-collector agent on ${hostName}: both ingress exporters must queue in file_storage by bytes with unlimited retry, the metrics queue must hold 24 h at fleetBytesPerMinute, the queues must sum below 512 MiB, and the limiter must be below MemoryMax (ADR-003 envelope; design D2).";
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
            exporters."otlp_http/ingress" = ingressExporter (mib 400);
            exporters."otlp_http/ingress-logs" = ingressExporter (mib 16);
          };
          systemd.services.opentelemetry-collector.serviceConfig.MemoryMax = "256M";
        })

        # Agent sessions' telemetry, where the host table sets agentTelemetry
        # (agent-session-telemetry design D3, D8, D14, D15), in a collector
        # unit of its own, otel-agent-session.service, so that agent traffic
        # can cost only agent telemetry: `otlp/local` on loopback feeds
        # exactly the three agent-session pipelines, each of which drops
        # every service, metric, event, span key and key off schema.nix's
        # agentSession allow-list (events and spans then cut every kept value
        # to 64 KiB and mask credential shapes in it) before it stamps the
        # host and the routing attributes. Its settings are
        # flake.lib.agentSessionCollector's (modules/lib/
        # agent-session-collector.nix) for this host, with the credentials
        # the unit loads; it exports over mTLS with the host's otel-cert:
        # elsewhere to otlp/mesh like the host's collector, on the ingress
        # host to its loopback receiver otlp/loopback.
        (lib.mkIf agentTelemetry (
          let
            langfuse = config.vanixiets.otelCollector.langfuse;
            langfuseExporter = "otlp_http/langfuse";
            collector = flakeLib.agentSessionCollector {
              inherit hostName ingress;
              inherit (config.vanixiets.otelCollector) caFile;
              certFile = "${agentSessionCredentials}/otel-cert";
              keyFile = "${agentSessionCredentials}/otel-key";
              queueDirectory = "${agentSessionStateDir}/queue";
              telemetryPort = agentSessionTelemetryPort;
              # The project's keys, loaded by the unit as credentials.
              langfuse =
                if langfuse then
                  {
                    publicKeyFile = "${agentSessionCredentials}/langfuse-public-key";
                    secretKeyFile = "${agentSessionCredentials}/langfuse-secret-key";
                  }
                else
                  null;
            };

            settings = config.vanixiets.otelCollector.agentSessionSettings;
            unit = config.systemd.services.${agentSessionUnit}.serviceConfig;
            package = config.services.opentelemetry-collector.package;
            memMax = builtins.match "([0-9]+)M" (unit.MemoryMax or "");
            goMemLimit = builtins.match "GOMEMLIMIT=([0-9]+)MiB" (
              lib.findFirst (lib.hasPrefix "GOMEMLIMIT=") "" (lib.toList (unit.Environment or [ ]))
            );
            configFile =
              pkgs.runCommandLocal "${agentSessionUnit}.yaml"
                { generated = (pkgs.formats.yaml { }).generate "${agentSessionUnit}.yaml" settings; }
                ''
                  cp "$generated" "$out"
                  ${lib.getExe package} validate --config=file:"$out"
                '';
          in
          {
            assertions = [
              {
                assertion = !ingress || (config.services.greptimedb.pipelines.agent or { }) ? agent_session_event;
                message = "otel-collector agent on ${hostName}: agent telemetry on the ingress host needs the store's agent_session_event pipeline (flake.modules.nixos.agent-session-store), which the ingress routes agent events through (agent-session-telemetry design D5).";
              }
              # The unit's ceiling and GOMEMLIMIT, which
              # flake.lib.agentSessionAssertions judges against the limiter.
              {
                assertion = memMax != null && goMemLimit != null;
                message = "otel-collector agent on ${hostName}: ${agentSessionUnit} must set MemoryMax in M and GOMEMLIMIT in MiB (ADR-003 envelope; agent-session-telemetry design D14); ${
                  builtins.toJSON (unit.Environment or null)
                }, MemoryMax ${builtins.toJSON (unit.MemoryMax or null)}.";
              }
              # checks.x86_64-linux.otel-collector-darwin compares stibnite's
              # daemon with this call over placeholder host facts, which stands
              # for this host only while its settings are the call over the
              # facts that check's normaliser replaces, read back from the
              # settings (darwin-agent-session-telemetry design D12).
              {
                assertion =
                  let
                    tls = settings.exporters."otlp_http/ingress-metrics".tls;
                    auth = settings.extensions."basicauth/langfuse".client_auth;
                  in
                  settings == (flakeLib.agentSessionCollector {
                    inherit hostName ingress;
                    caFile = tls.ca_file;
                    certFile = tls.cert_file;
                    keyFile = tls.key_file;
                    queueDirectory = settings.extensions.file_storage.directory;
                    telemetryPort =
                      (builtins.head settings.service.telemetry.metrics.readers).pull.exporter.prometheus.port;
                    langfuse =
                      if langfuse then
                        {
                          publicKeyFile = auth.username_file;
                          secretKeyFile = auth.password_file;
                        }
                      else
                        null;
                  }).settings;
                message = "otel-collector agent on ${hostName}: agentSessionSettings must be flake.lib.agentSessionCollector's over the host's facts alone (host name, TLS files, queue directory, telemetry port, Langfuse key files), as checks.otel-collector-darwin's agentSessionEqualsPyrite assumes (darwin-agent-session-telemetry design D12).";
              }
            ]
            ++ flakeLib.agentSessionAssertions {
              inherit hostName settings langfuse;
              goMemLimitMib = if goMemLimit == null then null else lib.toInt (builtins.head goMemLimit);
              ceilingMib = if memMax == null then null else lib.toInt (builtins.head memMax);
            };

            # The hardening of nixpkgs' collector unit, without the journal
            # group it does not need. After the host's collector: at the
            # cutover that collector releases 127.0.0.1:4318, and on the
            # ingress host it runs otlp/loopback. Where the store runs, also
            # after its schema job, so a switch that adds span keys adds their
            # columns before this unit sends them (design D15). After= orders
            # only jobs in one transaction, and a switch starts each unit in
            # a transaction of its own, so this unit also wants the job: its
            # start then pulls the job's start in and waits for it to end.
            # Wants, not Requires: a failed job leaves this unit starting
            # anyway, sending keys the store may refuse until the job is
            # rerun, rather than down until someone starts it.
            systemd.services.${agentSessionUnit} = {
              description = "OpenTelemetry collector for agent sessions' telemetry";
              wantedBy = [ "multi-user.target" ];
              after = [
                "opentelemetry-collector.service"
              ]
              ++ lib.optional (config.services ? greptimedb) "greptimedb-schema.service";
              wants = lib.optional (config.services ? greptimedb) "greptimedb-schema.service";
              startLimitIntervalSec = 0;
              serviceConfig = {
                ExecStart = "${lib.getExe package} --config=file:${configFile}";
                DynamicUser = true;
                Restart = "always";
                RestartSec = "5s";
                ProtectSystem = "full";
                DevicePolicy = "closed";
                NoNewPrivileges = true;
                WorkingDirectory = "%S/${agentSessionUnit}";
                StateDirectory = agentSessionUnit;
                MemoryMax = "${toString collector.ceilingMib}M";
                # Killed at its ceiling rather than spilling into the
                # host's swap, as greptimedb and perses are.
                MemorySwapMax = 0;
                Environment = [ "GOMEMLIMIT=${toString collector.goMemLimitMib}MiB" ];
              }
              # On the ingress host the kernel kills it after the evaluator
              # and before the dashboard, the store and the ingress
              # (magnetite's kill-order assertion).
              // lib.optionalAttrs ingress { OOMScoreAdjust = 700; };
            };

            # R3.2 over the unit's own telemetry, as otel-envelope does for
            # the host's collector (design D7, D14).
            systemd.services."${agentSessionUnit}-envelope" = {
              description = "Agent-session collector delivery envelope (ADR-003 R3.2)";
              after = [ "${agentSessionUnit}.service" ];
              serviceConfig = {
                inherit (config.systemd.services.otel-envelope.serviceConfig)
                  Type
                  DynamicUser
                  MemoryMax
                  TimeoutStartSec
                  ;
                StateDirectory = "${agentSessionUnit}-envelope";
                ExecStart = lib.getExe (
                  flakeLib.otelEnvelope pkgs {
                    inherit hostName;
                    telemetryUrl = "http://127.0.0.1:${toString agentSessionTelemetryPort}/metrics";
                    targets = flakeLib.otelEnvelopeTargets settings.receivers;
                    exporters = builtins.attrNames settings.exporters;
                    # Langfuse's failed sends are expected whenever it is
                    # down or its quota blocks ingestion, and page no one; its
                    # enqueue failures and otlp/local's refusals, which would
                    # mean the fan-out refused, are still loss (design D16).
                    sendFailedExempt = lib.optional langfuse langfuseExporter;
                  }
                );
              };
            };
            systemd.timers."${agentSessionUnit}-envelope" = {
              wantedBy = [ "timers.target" ];
              timerConfig.OnCalendar = "*:0/5 UTC";
            };

            vanixiets.otelCollector.agentSessionSettings = collector.settings;
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
}

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
  flakeLib = config.flake.lib;
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
      ingressExporter = queueSize: {
        endpoint = "https://[${flakeLib.hosts.magnetite.zt}]:4318";
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
              assertion = builtins.length capped <= 40;
              message = "otel-collector agent: ${toString (builtins.length capped)} of ${hostName}'s services match the unit allow-list, above ADR-004's 40: ${builtins.toJSON capped}";
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
          # queues and loss counters, and the targets it scrapes itself, so
          # the two cannot drift. A target's bearer credential is read from
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

            # The agents' mTLS exports, on magnetite's ZeroTier address only;
            # a client without an otel-ca certificate fails the handshake
            # (design D3). HTTP only, no gRPC.
            receivers."otlp/mesh".protocols.http = {
              endpoint = "[${flakeLib.hosts.magnetite.zt}]:4318";
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
              extensions = [ "basicauth/store" ];
              pipelines = {
                "metrics/ingress" = {
                  receivers = [
                    "forward"
                    "otlp/mesh"
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

            service.pipelines = {
              "logs/ingress" = {
                receivers = [
                  "forward"
                  "otlp/mesh"
                ];
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
          { roles, machine, ... }:
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
                isIngress = roles.ingress.machines ? ${machine.name};
                sans = lib.optionalString isIngress "IP:${flakeLib.hosts.magnetite.zt},DNS:magnetite.zt";
                usage = if isIngress then "serverAuth,clientAuth" else "clientAuth";
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
                    clan.core.vars.generators = {
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
                        files."key.pem".restartUnits = restart;
                        files."cert.pem" = {
                          secret = false;
                          restartUnits = restart;
                        };
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
                  }
                  # ca.crt reaches the collector as a store path, so a new CA changes
                  # the configuration and restarts it (design D1). The credentials
                  # load on the ingress host too, where otlp/mesh presents them.
                  # optionalAttrs, not mkIf: where collect is false these options
                  # are not declared, and collect is static data.
                  (lib.optionalAttrs collect {
                    vanixiets.otelCollector.caFile = pkgs.writeText "otel-ca.crt" gens.otel-ca.files."ca.crt".value;
                    vanixiets.otelCollector.smartDevices = flakeLib.observabilityHosts.${machine.name}.smartDevices;
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
                # otlp/mesh, on ZeroTier only. magnetite's
                # net.ipv6.ip_nonlocal_bind = 1 lets the receiver bind its
                # address before zerotierone holds it.
                networking.firewall.interfaces."zt+".allowedTCPPorts = [ 4318 ];
              };
          };
      };
    };
}

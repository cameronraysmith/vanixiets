# flake.lib.otelCollectorDarwin { hostName; certFile; keyFile; caFile;
# fleetExecutables; }: the darwin agent's and otelcol-process's
# configurations as plain attrsets, from flake.lib data and the arguments
# only, so checks.x86_64-linux.otel-collector-darwin judges
# them without evaluating a darwin host (design D2, D3, D13). `targets` and
# `exporters` are what the darwin otel-envelope probes and reads; `node` is
# the loopback node_exporter's settings. The Linux-only parts of the NixOS
# agent are absent: the systemd receiver errors at start off Linux, and the
# darwin memory scraper's available-memory and paging series are empty or
# zero (design "Requirement applicability").
{ config, lib, ... }:
let
  flakeLib = config.flake.lib;
  schema = flakeLib.otelCollectorSchema;
  mib = n: n * 1024 * 1024;
  scrape =
    job: target: extra:
    {
      job_name = job;
      scrape_interval = "60s";
      static_configs = [ { targets = [ target ]; } ];
    }
    // extra;
  keep = names: {
    source_labels = [ "__name__" ];
    regex = lib.concatStringsSep "|" names;
    action = "keep";
  };
in
{
  # The probe's labels: the allow-listed glob patterns of SC's launchdLabels
  # matched against a host's evaluated daemon labels, each dot literal
  # (ADR-004:121; design D4). checks.x86_64-linux.otel-collector-darwin
  # judges it over a fixture list with a decoy label.
  flake.lib.otelHostProbeLabels =
    { launchdLabels, daemonLabels }:
    let
      toRegex =
        builtins.replaceStrings
          [ "." "*" ]
          # mutant: labelDotUnescaped
          [ "[.]" ".*" ];
    in
    builtins.filter (l: lib.any (p: builtins.match (toRegex p) l != null) launchdLabels) daemonLabels;

  flake.lib.otelCollectorDarwin =
    {
      hostName,
      certFile,
      keyFile,
      caFile,
      # The executable names otelcol-process keeps below the darwin floor:
      # the host's fleet daemons', from SC's darwinFleetExecutables.
      fleetExecutables,
    }:
    let
      # The process filter's clause sparing one fleet executable.
      spared = n: ''resource.attributes["process.executable.name"] != ${builtins.toJSON n}'';
      # As the NixOS agent's exporters (modules/clan/services/otel-collector/
      # flake-module.nix ingressExporter), with the sops paths of otel-cert.
      ingressExporter = queueSize: {
        endpoint = "https://[${flakeLib.hosts.magnetite.zt}]:4318";
        tls = {
          ca_file = caFile;
          cert_file = certFile;
          key_file = keyFile;
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
      node = {
        listenAddress = "127.0.0.1";
        port = 9100;
        extraFlags = [
          "--collector.disable-defaults"
          "--collector.textfile"
          "--collector.textfile.directory=/var/lib/prometheus-node-exporter/textfile"
        ];
      };
      agent = {
        extensions.file_storage = {
          directory = "/var/lib/opentelemetry-collector/queue";
          create_directory = true;
        };
        receivers = {
          "host_metrics/memory" = {
            collection_interval = "60s";
            scrapers = {
              memory = { };
              disk = {
                include = {
                  devices = [ "disk0" ];
                  match_type = "strict";
                };
                # pending_operations is always 0 on darwin
                # (gopsutil@v4.26.5:disk/disk_darwin.go:318-325).
                metrics = {
                  "system.disk.io_time".enabled = false;
                  "system.disk.pending_operations".enabled = false;
                };
              };
              # darwin ignores include_virtual_filesystems, so the strict
              # list is the only bound (gopsutil@v4.26.5:disk/disk_darwin.go:21-30).
              filesystem = {
                include_mount_points = {
                  mount_points = [ "/System/Volumes/Data" ];
                  match_type = "strict";
                };
                metrics = {
                  "system.filesystem.usage".enabled = true;
                  "system.filesystem.inodes.usage".enabled = false;
                  "system.filesystem.utilization".enabled = false;
                };
              };
            };
          };
          # otelcol-process's points; no logs pipeline reads it (ADR-003:81).
          otlp.protocols.http.endpoint = "127.0.0.1:4318";
          prometheus.config.scrape_configs = [
            (scrape "node" "${node.listenAddress}:${toString node.port}" {
              metric_relabel_configs = [ (keep (schema.darwinNodeExporterKeep ++ schema.smartctlKeep)) ];
            })
            # A new identifier at every collector start (ADR-004's process-identifier ban).
            (scrape "otelcol" "127.0.0.1:8888" {
              metric_relabel_configs = [
                (keep schema.otelcolKeep)
                {
                  regex = "service_instance_id";
                  action = "labeldrop";
                }
              ];
            })
          ];
          # As every NixOS agent host's, with the same receiver id and
          # settings, so the stored rows have the same shape (design D11).
          "file_log/deploy-record" = {
            include = [ flakeLib.devloopCollection.deployRecordFile ];
            start_at = "beginning";
            storage = "file_storage";
            operators = [
              {
                type = "json_parser";
                id = "parse-line";
              }
              (flakeLib.devloopCollection.keepAttributes (
                map (column: column.name) schema.devloop.tables.deploy_record.columns
              ))
              flakeLib.devloopCollection.dropBody
            ];
          };
        };
        processors = {
          memory_limiter = {
            check_interval = "1s";
            limit_mib = 150;
            spike_limit_mib = 30;
          };
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
          "resource/devloop-deploy_record".attributes = [
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
        };
        exporters = {
          "otlp_http/ingress" = ingressExporter (mib 400);
          "otlp_http/ingress-logs" = ingressExporter (mib 16);
        };
        service = {
          extensions = [ "file_storage" ];
          # Explicit, so the loopback clause and assertion judge the listener.
          telemetry.metrics.readers = [
            {
              pull.exporter.prometheus = {
                host = "127.0.0.1";
                port = 8888;
              };
            }
          ];
          pipelines."metrics/host" = {
            receivers = [
              "host_metrics/memory"
              "otlp"
              "prometheus"
            ];
            processors = [
              "memory_limiter"
              "resource/agent"
            ];
            exporters = [ "otlp_http/ingress" ];
          };
          pipelines."logs/devloop-deploy_record" = {
            receivers = [ "file_log/deploy-record" ];
            processors = [
              "memory_limiter"
              "resource/devloop-deploy_record"
            ];
            exporters = [ "otlp_http/ingress-logs" ];
          };
        };
      };
    in
    {
      inherit node agent;
      # Root, for proc_pidinfo over other users' processes, with no listener
      # and no credential (design D3; ADR-008 item 4). It sets no
      # service.name: nothing reads one for process series, and the store
      # would add a service_name column only stibnite's rows fill.
      process = {
        receivers."host_metrics/process" = {
          collection_interval = "60s";
          scrapers.process = {
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
        # As the NixOS agent's process processors, which live in a NixOS
        # module the darwin side cannot import (ADR-003 item 16).
        processors = {
          memory_limiter = {
            check_interval = "1s";
            limit_mib = 64;
            spike_limit_mib = 16;
          };
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
          # Below the darwin floor only the fleet's own executables pass
          # (SC's process.minBytes.darwin and darwinFleetExecutables; A77).
          "filter/process-min" = {
            error_mode = "ignore";
            metric_conditions = [
              (lib.concatStringsSep " and " (
                [
                  ''metric.name == "process.memory.usage"''
                  "datapoint.value_int < ${toString schema.process.minBytes.darwin}"
                ]
                # mutant: keepListIgnored
                ++ map spared fleetExecutables
              ))
            ];
          };
        };
        exporters."otlp_http/agent" = {
          endpoint = "http://127.0.0.1:4318";
          sending_queue.enabled = true;
        };
        # No listener and no reader: level none builds no meter reader
        # (go.opentelemetry.io/collector/service@v0.155.0
        # service/telemetry/otelconftelemetry/metrics.go:28-30).
        service.telemetry.metrics.level = "none";
        service.pipelines."metrics/process" = {
          receivers = [ "host_metrics/process" ];
          processors = [
            "memory_limiter"
            "groupbyattrs/compact"
            "metrics_transform/process"
            "filter/process-min"
          ];
          exporters = [ "otlp_http/agent" ];
        };
      };
      targets = [
        {
          job = "node";
          url = "http://${node.listenAddress}:${toString node.port}/metrics";
        }
        {
          job = "otelcol";
          url = "http://127.0.0.1:8888/metrics";
        }
      ];
      exporters = builtins.attrNames agent.exporters;
    };
}

# Single source of the collector's allow-lists and bounds (ADR-004
# "Implementation surface"; design D8, D9). The otel-collector clan service
# builds its receivers, transforms and exporter headers from it, its agent
# assertions read the unit allow-list, owner aliases, rate assumption and
# unit cap, otel-envelope's hourly clauses read the budget, and
# checks.x86_64-linux.otel-collector-config reads its databases. import-tree loads every .nix file under
# modules/, so this is a flake-parts module exposing the data as
# flake.lib.otelCollectorSchema; nothing imports it by path. S1 carries the
# keys S1 deploys; later slices add theirs here.
{ ... }:
{
  flake.lib.otelCollectorSchema = {
    # ADR-004's systemd unit allow-list, `.service` units only, as systemd
    # unit patterns. At most budget.units of them may match on one host
    # (ADR-004 Q12).
    systemdUnits = [
      "gitea.service"
      "gitea-mq.service"
      "nixbot*.service"
      "niks3*.service"
      "nix-daemon.service"
      "nix-grpc-daemon.service"
      "harmonia-gc.service"
      "postgresql.service"
      "nginx.service"
      "greptimedb.service"
      "opentelemetry-collector.service"
      "zerotierone.service"
      "omnigent-host-*.service"
      "omnigraph.service"
      "otel-envelope.service"
      "devloop-reconcile.service"
      "greptimedb-envelope.service"
      "greptimedb-export.service"
      "greptimedb-schema.service"
      "prometheus-node-exporter.service"
      "prometheus-smartctl-exporter.service"
      "zfs-assert-*.service"
      "zfs-set-*.service"
      # A failed notifier post becomes a SystemdUnitFailed instance, which
      # the evaluator retries until ntfy accepts it (S3 review F2).
      "observability-notify@*.service"
    ];

    # omnigent-host-<owner>.service is stored as omnigent-host-<alias>.service
    # (ADR-003 item 17), so no owner's name becomes a label value. Opaque and
    # stable: a new owner takes the next number and no alias is renumbered.
    ownerAliases = {
      cameron = "owner-1";
      janettesmith = "owner-2";
    };

    # Resource attributes the store promotes to labels (ADR-003 item 15).
    promotedResourceAttributes = [
      "host.name"
      "systemd.unit.name"
      "process.executable.name"
    ];

    # node_exporter series kept; every other is dropped (ADR-004).
    nodeExporterKeep = [
      "node_zfs_zpool_state"
      "node_zfs_arc_size"
      "node_zfs_arc_c"
      "node_zfs_arc_c_min"
      "node_zfs_arc_c_max"
      "node_zfs_arc_hits"
      "node_zfs_arc_misses"
      "node_zfs_arc_memory_throttle_count"
      "node_vmstat_oom_kill"
    ];

    # The collector's own telemetry kept from 127.0.0.1:8888 (design D4;
    # ADR-003 item 26): queue size and capacity, send and enqueue failures,
    # receiver refusals. At contrib 0.155.0 the counters carry no `_total`
    # suffix (read live on magnetite on 2026-10-29).
    otelcolKeep = [
      "otelcol_exporter_queue_size"
      "otelcol_exporter_queue_capacity"
      "otelcol_exporter_send_failed_metric_points"
      "otelcol_exporter_send_failed_log_records"
      "otelcol_exporter_enqueue_failed_metric_points"
      "otelcol_exporter_enqueue_failed_log_records"
      "otelcol_receiver_refused_metric_points"
      "otelcol_receiver_refused_log_records"
    ];

    # smartctl_exporter series kept; `smartctl_device` and
    # `smartctl_version` are dropped (ADR-004).
    smartctlKeep = [
      "smartctl_device_smart_status"
      "smartctl_device_critical_warning"
      "smartctl_device_media_errors"
      "smartctl_device_percentage_used"
      "smartctl_device_available_spare"
      "smartctl_device_available_spare_threshold"
      "smartctl_device_num_err_log_entries"
      "smartctl_device_temperature"
    ];

    # Darwin node_exporter series kept besides smartctlKeep, which the
    # probe's textfile writes under the same names (ADR-004:93, :95-96).
    darwinNodeExporterKeep = [
      "launchd_job_state"
      "launchd_job_last_exit_code"
      "launchd_job_runs_total"
      "node_textfile_mtime_seconds"
      "node_textfile_scrape_error"
    ];

    # ADR-004:121's launchd allow-list, by label, as glob patterns; each
    # darwin host's probe reads the labels on it that its evaluated
    # launchd.daemons defines. org.nixos.otel-envelope is listed so a
    # stopped or unloaded envelope is visible through the store (design D9).
    launchdLabels = [
      "org.nixos.nix-daemon"
      "org.nixos.nix-grpc-daemon"
      "org.nixos.harmonia-gc"
      "org.nixos.nix-cleanup-gcroots"
      "org.nixos.sops-install-secrets"
      "org.nixos.dnscrypt-proxy"
      "org.nixos.otelcol"
      "org.nixos.otelcol-process"
      "org.nixos.otel-envelope"
      "org.nixos.prometheus-node-exporter"
      "org.nixos.omnigent-host-*"
    ];

    # The allow-listed labels whose evaluated KeepAlive is true (ADR-004:123),
    # which LaunchdJobNotRunning expects running; the darwin fragment asserts
    # this list against its host's evaluated launchd.daemons. A job whose
    # KeepAlive is a condition set, as omnigent-host-<owner>'s
    # { SuccessfulExit = false; }, may exit 0 and stay down legitimately, so
    # it is outside the list (design D9).
    launchdKeptAlive = [
      "org.nixos.dnscrypt-proxy"
      "org.nixos.nix-daemon"
      "org.nixos.nix-grpc-daemon"
      "org.nixos.otelcol"
      "org.nixos.otelcol-process"
      "org.nixos.prometheus-node-exporter"
    ];

    # process.memory.usage is stored only for processes holding at least
    # minBytes.<platform>; each point is one process, so an executable is
    # stored when any one of its processes reaches the floor (ADR-003 item 16).
    # ADR-004's per-host bound of 30 distinct names has no collector stage
    # at contrib 0.155.0; S1 records the observed count at deployment and
    # S4's otel-envelope adds its regulator. The scraper reports RSS on both
    # platforms (process_scraper.go:321-326), and on darwin RSS counts each
    # process's mapped share of the dyld shared cache and frameworks, so
    # ordinary daemons hold 65-300 MiB; darwin's floor is the smallest of
    # 128, 192, 256, 384 and 512 MiB that kept stibnite's hourly distinct
    # names at or below 20 from 2026-11-06T05:17Z to 21:14Z (A77).
    process.minBytes = {
      linux = 67108864;
      darwin = 402653184;
    };

    # The darwin executables kept whatever their size, so that a leak in a
    # service the fleet runs shows as a trend: per launchd label glob (dots
    # literal, as launchdLabels), the name the scraper reports, the kernel's
    # p_comm, which follows symlinks and names an interpreter, not a script
    # (gopsutil@v4.26.5:process/process_darwin.go:65-87; `ps -o comm=` on
    # stibnite on 2026-11-06). The darwin fragment asserts that the globs
    # cover the host's long-running org.nixos.* daemons and that omnigent's
    # name is its package's interpreter. `nix` and `python3.x` also name the
    # operator's own processes; each is one series because the store's series
    # key is the name, and same-named points stored in the same millisecond
    # become one row (design D3).
    process.darwinFleetExecutables = {
      "org.nixos.dnscrypt-proxy" = "dnscrypt-proxy";
      "org.nixos.nix-daemon" = "nix";
      "org.nixos.nix-grpc-daemon" = "nix-grpc-daemon";
      "org.nixos.omnigent-host-*" = "python3.14";
      "org.nixos.otelcol" = "otelcol-contrib";
      "org.nixos.otelcol-process" = "otelcol-contrib";
      "org.nixos.prometheus-node-exporter" = "node_exporter";
    };

    # Unmeasured estimate of magnetite's `fleet` export rate: about 2000
    # series (ADR-004's ~800 host-level series per NixOS host plus the
    # scraped service endpoints) at 128 bytes per OTLP number point with its
    # resource and attribute overhead, one point per minute. The deployment
    # measurement (logs/s1-evidence/8.5-queue-rate.log) replaces it. The
    # agents' queue assertion and checks.x86_64-linux.otel-collector-config
    # read it.
    fleetBytesPerMinute = 256000;

    # observability-notify@ instances pass the unit allow-list, so that
    # SystemdUnitFailed reports a failed post, but are bounded by the host's
    # notified units, not by budget.units (ADR-004 as amended under charter
    # v23).
    systemdUnitsNotifierPattern = "observability-notify@*.service";

    # ADR-004's budget: otel-envelope's hourly clauses B1, B2, B3 and B5
    # judge the store against it on the ingress host, and the agent role
    # asserts `units` against each host's allow-listed services, so the two
    # cannot disagree on the cap.
    budget = {
      activeSeries = 8000;
      labelValues = 200;
      processNames = 30;
      units = 40;
      launchdLabels = 30;
      devloopRows = 100000;
    };

    # Store databases and their retention, one otlp_http exporter each
    # (design D8). magnetite's services.greptimedb.databases reads this map,
    # and the ingress role asserts the store creates exactly these names.
    databases = {
      fleet = "30d";
      devloop = "365d";
      agent = "90d";
    };

    # The devloop allow-list (design D3; ADR-004 as amended by charter v22):
    # the only declaration of the dev-loop tables' columns, in stored order,
    # their types, primary keys and time indexes. devloop-collection.nix
    # renders from it the table statements, the ingest pipelines and the
    # nixbot queries' output columns; S4's agents read it too. Every column
    # but the time index is nullable.
    devloop.tables =
      let
        column = name: type: {
          inherit name type;
          nullable = true;
        };
        timeIndex = name: {
          inherit name;
          type = "timestamp";
          nullable = false;
        };
      in
      {
        ci_attribute = {
          columns = [
            (column "build_id" "int64")
            (column "attr" "string")
            (column "system" "string")
            (column "status" "string")
            (column "cached" "boolean")
            (column "abandoned" "boolean")
            (column "drv_path" "string")
            (column "outputs_out" "string")
            (column "started_at" "timestamp")
            (timeIndex "finished_at")
            (column "eval_wall_ms" "int64")
            (column "eval_alloc_bytes" "int64")
            (column "commit_sha" "string")
            (column "branch" "string")
            (column "pr_number" "int64")
            (column "project" "string")
          ];
          primaryKey = [
            "build_id"
            "attr"
          ];
          timeIndex = "finished_at";
        };
        ci_build = {
          columns = [
            (column "build_id" "int64")
            (column "created_at" "timestamp")
            (column "started_at" "timestamp")
            (timeIndex "finished_at")
            (column "eval_duration_ms" "int64")
            (column "status" "string")
            (column "pr_number" "int64")
            (column "branch" "string")
          ];
          primaryKey = [ "build_id" ];
          timeIndex = "finished_at";
        };
        batch_event = {
          columns = [
            (column "batch" "int64")
            (column "msg" "string")
            (column "build" "int64")
            (column "sha" "string")
            (column "failed_check" "string")
            (column "members" "int64")
            (column "landed" "int64")
            (column "ejected" "int64")
            (column "builds" "int64")
            (column "flaky" "boolean")
            (timeIndex "ts")
          ];
          primaryKey = [
            "batch"
            "msg"
          ];
          timeIndex = "ts";
        };
        deploy_record = {
          columns = [
            (column "host" "string")
            (column "closure" "string")
            (column "previous_closure" "string")
            (timeIndex "ts")
          ];
          primaryKey = [ "host" ];
          timeIndex = "ts";
        };
      };
  };
}

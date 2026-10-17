# Single source of the collector's allow-lists and bounds (ADR-004
# "Implementation surface"; design D8, D9). The otel-collector clan service
# builds its receivers, transforms and exporter headers from it, and
# checks.x86_64-linux.otel-collector-config compares magnetite's evaluated
# configuration against it. import-tree loads every .nix file under
# modules/, so this is a flake-parts module exposing the data as
# flake.lib.otelCollectorSchema; nothing imports it by path. S1 carries the
# keys S1 deploys; later slices add theirs here.
{ ... }:
{
  flake.lib.otelCollectorSchema = {
    # ADR-004's systemd unit allow-list, `.service` units only, as systemd
    # unit patterns. At most 40 units may match on one host (ADR-004 Q12).
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

    # process.memory.usage is stored only for executables holding at least
    # minBytes after same-name aggregation (ADR-003 item 16). maxNames is the
    # per-host bound on distinct names (ADR-004), observed at deployment and
    # regulated at runtime from S4; no collector stage enforces it.
    process = {
      minBytes = 67108864;
      maxNames = 30;
    };

    # Store databases and their retention, one otlp_http exporter each
    # (design D8). magnetite's services.greptimedb.databases reads this map,
    # and the ingress role asserts the store creates exactly these names.
    databases = {
      fleet = "30d";
      devloop = "365d";
      agent = "90d";
    };
  };
}

# zpool-probe: each ZFS pool's size, fullness and errors, and each dataset
# with a quota against it, for node_exporter's textfile collector.
# node_exporter's zfs collector (1.12.1, as run on magnetite) reports each
# pool's state and per-dataset I/O counters from /proc/spl/kstat/zfs, and
# no pool size, allocation, fragmentation or dataset space, so fleet-alert's
# pool and quota rules read this probe instead.
#
# Where node_exporter runs on a host with ZFS (boot.zfs.enabled),
# zpool-probe.service runs every 60 s as node_exporter's user, which
# /dev/zfs (0666) lets list pools, reads `zpool list -Hp` and writes
# zpool.prom into the host's one textfile directory
# (./node-exporter-textfile.nix) by write-then-rename, per pool under the
# label `zpool`, as node_zfs_zpool_state carries it:
# - vanixiets_zpool_size_bytes, _allocated_bytes and _free_bytes, the
#   pool's raw space as `zpool list` reports it, before the 1/32 of the
#   pool ZFS holds back as slop and before any dataset's reservation;
# - vanixiets_zpool_capacity_ratio, allocated over size, the ratio `zpool
#   list` rounds into CAP;
# - vanixiets_zpool_fragmentation_ratio, FRAG over 100, the fragmentation
#   of the pool's free space, left out where the pool reports none;
# and, per dataset whose `quota` is set locally (`zfs get -s local`), under
# the label `dataset`, so the layer datasets a container engine creates
# below a dataset with a quota are not listed unless one sets its own:
# - vanixiets_zfs_dataset_used_bytes, its USED, which counts its children
#   and snapshots, as its quota does, where statfs on its mount counts
#   neither;
# - vanixiets_zfs_dataset_quota_bytes, its quota;
# - vanixiets_zfs_dataset_snapshots_used_bytes, its USEDSNAP;
# and, per pool under `zpool`, from `zpool status -jp --json-int` (OpenZFS
# 2.3 and later), read with jq rather than from the status text:
# - vanixiets_zpool_data_errors, the pool's `error_count`, the entries
#   `zpool status -v` lists under `errors:`, which can be non-zero while the
#   pool's state stays ONLINE and its device counters stay zero;
# - vanixiets_zpool_device_errors, the sum of `read_errors`, `write_errors`
#   and `checksum_errors` over every vdev of the pool, its root, interior,
#   log, cache and spare vdevs included, so an error a mirror and its disk
#   both count counts twice: the rule reads only whether it is above zero;
# - vanixiets_zpool_scrub_end_timestamp_seconds and
#   vanixiets_zpool_scrub_errors, the end and error count of the pool's
#   last scan where that scan is a finished scrub, left out while a scrub
#   or resilver runs and where none has finished, so a stale error entry
#   can be told from a fresh one.
# Where `zpool status -j` fails, as before OpenZFS 2.3, the four are left
# out and RuleSignalMissing reports the host.
# omnigraph-probe also reports the used bytes and quota of the one dataset
# holding an omnigraph root, quota or not, which the OmniGraph view reads;
# these cover every dataset with a quota for the quota rule and the Fleet
# hosts view.
# The keep-list keeps only seriesNames, the series fleet-alert's
# ZfsPoolErrors, ZfsPoolCapacityWarn, ZfsPoolCapacityCritical and
# ZfsDatasetQuotaFilling and the Fleet hosts view read; the pool byte series
# stay on the host's node_exporter for reading there.
# The assertions keep the keep-list, the textfile collector and the writer
# from drifting apart from the probe, and hold every collecting NixOS row
# of flake.lib.observabilityHosts to a host that runs the probe, because
# the pool rules expect its series there. HostProbeStale reports a probe
# that stops writing.
{ config, lib, ... }:
let
  schema = config.flake.lib.otelCollectorSchema;
  hosts = config.flake.lib.observabilityHosts;
  inherit (config.flake.lib.nodeExporterTextfile) flag;

  writer = "zpool";
  seriesNames = [
    "vanixiets_zpool_capacity_ratio"
    "vanixiets_zpool_fragmentation_ratio"
    "vanixiets_zfs_dataset_used_bytes"
    "vanixiets_zfs_dataset_quota_bytes"
    "vanixiets_zfs_dataset_snapshots_used_bytes"
    "vanixiets_zpool_data_errors"
    "vanixiets_zpool_device_errors"
    "vanixiets_zpool_scrub_end_timestamp_seconds"
    "vanixiets_zpool_scrub_errors"
  ];

  probe =
    pkgs: zfs:
    pkgs.writeShellApplication {
      name = "zpool-probe";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gawk
        pkgs.jq
        zfs
      ];
      text = ''
        out=$1
        pools=$(zpool list -H -p -o name,size,allocated,free,fragmentation)
        quotas=$(zfs get -H -p -s local -t filesystem -o name quota)
        datasets=
        if [ -n "$quotas" ]; then
          mapfile -t names <<<"$quotas"
          datasets=$(zfs list -H -p -o name,used,quota,usedbysnapshots -- "''${names[@]}")
        fi
        exec 3>"$out.tmp"
        awk -F'\t' '
          { name[NR] = $1; size[NR] = $2; alloc[NR] = $3; free[NR] = $4; frag[NR] = $5 }
          function family(metric, help) {
            printf "# HELP %s %s\n# TYPE %s gauge\n", metric, help, metric
          }
          function sample(metric, i, value) {
            printf "%s{zpool=\"%s\"} %s\n", metric, name[i], value
          }
          END {
            family("vanixiets_zpool_size_bytes", "The pool size zpool list reports, before slop space and reservations.")
            for (i = 1; i <= NR; i++) sample("vanixiets_zpool_size_bytes", i, size[i])
            family("vanixiets_zpool_allocated_bytes", "The bytes allocated in the pool, as zpool list reports them.")
            for (i = 1; i <= NR; i++) sample("vanixiets_zpool_allocated_bytes", i, alloc[i])
            family("vanixiets_zpool_free_bytes", "The pool size less its allocated bytes, as zpool list reports it.")
            for (i = 1; i <= NR; i++) sample("vanixiets_zpool_free_bytes", i, free[i])
            family("vanixiets_zpool_capacity_ratio", "Allocated bytes over the pool size, the ratio zpool list rounds into CAP.")
            for (i = 1; i <= NR; i++) if (size[i] > 0) sample("vanixiets_zpool_capacity_ratio", i, sprintf("%.6f", alloc[i] / size[i]))
            family("vanixiets_zpool_fragmentation_ratio", "The fragmentation of the pool free space, zpool list FRAG over 100.")
            for (i = 1; i <= NR; i++) if (frag[i] ~ /^[0-9]+$/) sample("vanixiets_zpool_fragmentation_ratio", i, sprintf("%.2f", frag[i] / 100))
          }' <<<"$pools" >&3
        awk -F'\t' '
          NF == 4 && $3 > 0 { name[++n] = $1; used[n] = $2; quota[n] = $3; snap[n] = $4 }
          function family(metric, help) {
            printf "# HELP %s %s\n# TYPE %s gauge\n", metric, help, metric
          }
          function sample(metric, i, value) {
            printf "%s{dataset=\"%s\"} %s\n", metric, name[i], value
          }
          END {
            family("vanixiets_zfs_dataset_used_bytes", "USED of a dataset with a local quota, its children and snapshots included.")
            for (i = 1; i <= n; i++) sample("vanixiets_zfs_dataset_used_bytes", i, used[i])
            family("vanixiets_zfs_dataset_quota_bytes", "The local quota of a dataset.")
            for (i = 1; i <= n; i++) sample("vanixiets_zfs_dataset_quota_bytes", i, quota[i])
            family("vanixiets_zfs_dataset_snapshots_used_bytes", "USEDSNAP of a dataset with a local quota, the space its snapshots alone hold.")
            for (i = 1; i <= n; i++) sample("vanixiets_zfs_dataset_snapshots_used_bytes", i, snap[i])
          }' <<<"$datasets" >&3
        # `zpool status -j` came with OpenZFS 2.3: where it fails, the error
        # series are left out rather than read from the status text.
        if status=$(zpool status -jp --json-int); then
          jq -r '
            def family($metric; $help): "# HELP \($metric) \($help)\n# TYPE \($metric) gauge";
            def sample($metric; $value): "\($metric){zpool=\"\(.name)\"} \($value)";
            def scrubbed: select(.scan_stats.function == "SCRUB" and .scan_stats.state == "FINISHED");
            [.pools // {} | .[]] as $pools
            | family("vanixiets_zpool_data_errors"; "The data errors zpool status -v lists for the pool, its error_count."),
              ($pools[] | select(.error_count != null) | sample("vanixiets_zpool_data_errors"; .error_count)),
              family("vanixiets_zpool_device_errors"; "Read, write and checksum errors summed over every vdev of the pool."),
              ($pools[] | sample("vanixiets_zpool_device_errors"; [.. | objects | select(has("read_errors")) | .read_errors + .write_errors + .checksum_errors] | add // 0)),
              family("vanixiets_zpool_scrub_end_timestamp_seconds"; "The end of the last scrub of the pool, where its last scan is a finished scrub."),
              ($pools[] | scrubbed | sample("vanixiets_zpool_scrub_end_timestamp_seconds"; .scan_stats.end_time)),
              family("vanixiets_zpool_scrub_errors"; "The errors the last finished scrub of the pool found."),
              ($pools[] | scrubbed | sample("vanixiets_zpool_scrub_errors"; .scan_stats.errors))
          ' <<<"$status" >&3
        fi
        exec 3>&-
        mv -f -- "$out.tmp" "$out"
      '';
    };

  module =
    { config, pkgs, ... }:
    let
      node = config.services.prometheus.exporters.node;
      directory = config.vanixiets.nodeExporter.textfileDirectory;
      active = config.boot.zfs.enabled && node.enable;
      row = hosts.${config.networking.hostName} or null;
      program = probe pkgs config.boot.zfs.package;
    in
    {
      assertions = [
        {
          assertion = row == null || !row.collect || row.platform != "nixos" || active;
          message = "zpool-probe: ${config.networking.hostName} collects on NixOS in flake.lib.observabilityHosts, so ZfsPoolUnhealthy, ZfsPoolErrors, ZfsPoolCapacityWarn and ZfsPoolCapacityCritical expect its pool series, but it ${
            if config.boot.zfs.enabled then "runs no node_exporter" else "has no ZFS"
          }; give it the pool, or render those rules' expected hosts from a row field.";
        }
      ]
      ++ lib.optional active {
        assertion =
          lib.all (name: lib.elem name schema.nodeExporterKeep) seriesNames
          && lib.elem writer config.vanixiets.nodeExporter.textfileWriters
          && lib.elem "${flag}=${directory}" node.extraFlags;
        message = "zpool-probe: node_exporter must run its textfile collector on ${directory} with ${writer} among vanixiets.nodeExporter.textfileWriters, and nodeExporterKeep must keep ${lib.concatStringsSep ", " seriesNames}, or the pool error and capacity rules and the Fleet hosts view never see a pool.";
      };

      vanixiets.nodeExporter.textfileWriters = lib.mkIf active [ writer ];

      # node_exporter's own user writes into the directory node_exporter
      # reads: a DynamicUser's files would sit under /run/private, which
      # node_exporter cannot traverse (./magnetite-memory-budget.nix).
      systemd.services.zpool-probe = lib.mkIf active {
        description = "ZFS pool size, capacity, fragmentation and errors for node_exporter's textfile collector";
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe program} ${directory}/${writer}.prom";
          User = node.user;
          Group = node.group;
          ReadWritePaths = [ directory ];
          UMask = "0022";
          MemoryMax = "32M";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
        };
      };

      systemd.timers.zpool-probe = lib.mkIf active {
        description = "Every minute: ZFS pool size, capacity, fragmentation and errors";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "60s";
          AccuracySec = "5s";
        };
      };
    };
in
{
  flake.lib.zpoolProbe = {
    inherit seriesNames writer probe;
  };

  flake.modules.nixos.zpool-probe = module;
}

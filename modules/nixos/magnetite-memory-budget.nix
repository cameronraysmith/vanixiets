# magnetite's memory budget (CAM-111 design D11): what competes with nixbot's
# evaluations for magnetite's memory, recorded every minute beside the
# evaluation records. ZFS ARC, swap use, available memory and OOM kills are
# already stored by the otel-collector agent (node_exporter keep-list, the
# paging scraper); the collector's systemd receiver reports no unit memory at
# contrib 0.155.0, and nothing reports the RAM zram itself holds. This module
# adds those: magnetite-memory-budget.service, every 60 s, writes systemd's
# MemoryCurrent and MemoryPeak for flake.lib.otelCollectorSchema's
# memoryBudgetUnits, system.slice and user.slice, and zram0's mm_stat sizes,
# to node_exporter's textfile collector (./magnetite-memory-budget/probe.py).
# The five series names are in nodeExporterKeep; the assertion below keeps
# the keep-list and the textfile collector from drifting apart from the
# probe. checks.x86_64-linux.magnetite-memory-budget runs the probe's
# formatting against recorded systemctl output.
{ config, lib, ... }:
let
  schema = config.flake.lib.otelCollectorSchema;

  seriesNames = [
    "vanixiets_unit_memory_current_bytes"
    "vanixiets_unit_memory_peak_bytes"
    "vanixiets_zram_orig_data_bytes"
    "vanixiets_zram_compr_data_bytes"
    "vanixiets_zram_mem_used_bytes"
  ];

  probeConfig = {
    units = schema.memoryBudgetUnits;
    aliases = schema.ownerAliases;
  };

  probe =
    pkgs:
    pkgs.writers.writePython3Bin "magnetite-memory-budget" {
      flakeIgnore = [ "E501" ];
    } (builtins.readFile ./magnetite-memory-budget/probe.py);

  directory = "/run/magnetite-memory-budget";
in
{
  flake.lib.magnetiteMemoryBudget = {
    inherit seriesNames probeConfig probe;
  };

  flake.modules.nixos.magnetite-memory-budget =
    {
      config,
      pkgs,
      ...
    }:
    let
      configFile = pkgs.writeText "magnetite-memory-budget.json" (builtins.toJSON probeConfig);
      textfileFlag = "--collector.textfile.directory=${directory}";
      nodeFlags = config.services.prometheus.exporters.node.extraFlags;
      nodeUser = config.services.prometheus.exporters.node.user;
      probeService = config.systemd.services.magnetite-memory-budget.serviceConfig;
    in
    {
      assertions = [
        {
          assertion =
            lib.all (name: lib.elem name schema.nodeExporterKeep) seriesNames
            && lib.elem "--collector.textfile" nodeFlags
            && lib.elem textfileFlag nodeFlags;
          message = "magnetite-memory-budget: node_exporter must run its textfile collector on ${directory} and nodeExporterKeep must keep ${lib.concatStringsSep ", " seriesNames}, or the budget never reaches the store (CAM-111 design D11).";
        }
        # A DynamicUser's RuntimeDirectory lives under /run/private, which
        # only root may traverse, so node_exporter could not read it; the
        # first deploy (2026-11-18) showed exactly that ("open
        # /run/magnetite-memory-budget: permission denied"). The probe runs
        # as node_exporter's own user instead.
        {
          assertion = !(probeService.DynamicUser or false) && (probeService.User or null) == nodeUser;
          message = "magnetite-memory-budget: the probe must run as node_exporter's user ${nodeUser}, not as a DynamicUser, or node_exporter cannot read ${directory} (CAM-111 design D11).";
        }
      ];

      services.prometheus.exporters.node.extraFlags = [
        "--collector.textfile"
        textfileFlag
      ];

      # node_exporter's own user reads unit properties over D-Bus and zram's
      # mm_stat, both world-readable, and owns the directory node_exporter
      # reads.
      systemd.services.magnetite-memory-budget = {
        description = "magnetite's memory budget for node_exporter's textfile collector";
        path = [ config.systemd.package ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe (probe pkgs)} ${configFile} ${directory}/memory-budget.prom";
          User = nodeUser;
          Group = config.services.prometheus.exporters.node.group;
          RuntimeDirectory = "magnetite-memory-budget";
          RuntimeDirectoryMode = "0755";
          RuntimeDirectoryPreserve = true;
          UMask = "0022";
          MemoryMax = "64M";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
        };
      };

      systemd.timers.magnetite-memory-budget = {
        description = "Every minute: magnetite's memory budget";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "60s";
          AccuracySec = "5s";
        };
      };
    };
}

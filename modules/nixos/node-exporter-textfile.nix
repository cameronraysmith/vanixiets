# One textfile collector directory per host for node_exporter (F75).
# node_exporter takes `--collector.textfile.directory` once: on 2026-11-19
# magnetite's unit carried the memory budget's directory and the collation
# probe's, and node_exporter refused to start ("flag 'collector.textfile'
# cannot be repeated"). So the directory is declared here, once, as
# vanixiets.nodeExporter.textfileDirectory; a probe that writes a textfile
# names itself in vanixiets.nodeExporter.textfileWriters and writes its own
# `<name>.prom` there by write-then-rename. Where a writer is named, this
# module turns on the textfile collector with that directory and has
# systemd-tmpfiles create it 0755 for node_exporter's user, so it outlives
# restarts of node_exporter and of every probe.
# The assertion keeps the directory flag to at most one in node_exporter's
# rendered ExecStart, whoever adds it; checks.x86_64-linux.node-exporter-textfile
# shows a second flag failing it. Imported by every NixOS base, and by
# ./omnigraph-probe.nix and ./omnigraph-backup.nix, which the omnigraph module
# also brings onto nodes without base (the omnigraph runtime tests); the
# shared key loads it once on a host holding both.
{ config, lib, ... }:
let
  inherit (config.flake) modules;
  hosts = config.flake.lib.observabilityHosts;

  flag = "--collector.textfile.directory";

  module =
    { config, ... }:
    let
      cfg = config.vanixiets.nodeExporter;
      node = config.services.prometheus.exporters.node;
      enabled = node.enable && cfg.textfileWriters != [ ];
      execStart = toString (
        config.systemd.services.prometheus-node-exporter.serviceConfig.ExecStart or ""
      );
      flagCount = lib.length (lib.splitString flag execStart) - 1;
      row = hosts.${config.networking.hostName} or null;
    in
    {
      key = "vanixiets#node-exporter-textfile";

      options.vanixiets.nodeExporter = {
        textfileDirectory = lib.mkOption {
          type = lib.types.path;
          default = "/run/node-exporter-textfile";
          description = "The host's one directory for node_exporter's textfile collector, where every textfile probe writes its own .prom file.";
        };
        textfileWriters = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "The probes writing a textfile into textfileDirectory; naming one turns the textfile collector on.";
        };
      };

      config = {
        assertions = [
          {
            assertion = flagCount <= 1;
            message = "node-exporter-textfile: node_exporter's ExecStart carries ${flag} ${toString flagCount} times; node_exporter refuses a repeated flag (F75), so every textfile probe writes into vanixiets.nodeExporter.textfileDirectory instead.";
          }
          # F76: HostProbeStale expects textfile series from the hosts whose
          # row says `textfile`, so the row follows this configuration.
          {
            assertion = row == null || !row.collect || row.textfile == enabled;
            message = "node-exporter-textfile: ${config.networking.hostName}'s row in flake.lib.observabilityHosts has textfile = ${
              lib.boolToString (row.textfile or false)
            }, but its textfile collector is ${
              if enabled then "on, for ${builtins.toJSON cfg.textfileWriters}" else "off"
            }; set the row's textfile to match, so HostProbeStale expects exactly the hosts that write a textfile (F76).";
          }
        ];

        # Conditions on the leaves: node_exporter's own options decide them.
        services.prometheus.exporters.node.extraFlags = lib.mkIf enabled [
          "--collector.textfile"
          "${flag}=${cfg.textfileDirectory}"
        ];

        systemd.tmpfiles.settings."10-node-exporter-textfile" = lib.mkIf enabled {
          ${cfg.textfileDirectory}.d = {
            inherit (node) user group;
            mode = "0755";
          };
        };
      };
    };
in
{
  flake.lib.nodeExporterTextfile = {
    inherit flag;
  };

  flake.modules.nixos.node-exporter-textfile = module;
  flake.modules.nixos.base.imports = [ modules.nixos.node-exporter-textfile ];
}

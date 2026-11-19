# The agent hosts and what each reports (design D6). The inventory's agent
# machines, whether each collects, each host's platform, notified units and
# SMART devices, and the alert rules' always-on hosts, expected hosts and
# SystemdUnitFailed exclusion are read from here. A host's `collect` turns
# the agent role on; a host joining the fleet enters with its `collect`
# false until its watched first deploy. A host joins alwaysOn only by an
# edit here when it becomes permanently provisioned (ADR-009 item 16).
{ ... }:
{
  flake.lib.observabilityHosts =
    let
      agent = extra: {
        collect = true;
        platform = "nixos";
        alwaysOn = false;
        smartDevices = [ ];
        notifiedUnits = [
          "opentelemetry-collector"
          "otel-envelope"
        ]
        ++ extra;
      };
    in
    {
      magnetite =
        agent [
          "devloop-pg-grants"
          "devloop-reconcile"
          "fleet-alert"
          "greptimedb"
          "greptimedb-envelope"
          "greptimedb-schema"
          "perses"
          "postgresql-collation"
          "zfs-assert-root-docker-noautosnap"
          "zfs-assert-root-greptimedb-noautosnap"
          "zfs-assert-root-nix-noautosnap"
          "zfs-assert-root-podman-noautosnap"
          "zfs-set-root-greptimedb-quota"
          "zfs-set-root-greptimedb-reservation"
          "zfs-set-root-home-reservation"
          "zfs-set-root-nix-quota"
          "zfs-set-root-nixos-reservation"
        ]
        // {
          alwaysOn = true;
        };
      cinnabar =
        agent [
          "fleet-deadman"
          "caddy-root-check"
          "fleet-deployer-keycheck"
        ]
        // {
          alwaysOn = true;
        };
      pyrite = agent [ ] // {
        smartDevices = [ "/dev/nvme0" ];
      };
      electrum = agent [ ];
      galena = agent [ ];
      scheelite = agent [ ];
      # A darwin workstation: launchd jobs and the probe's textfile instead of
      # systemd units; its SMART device is read by the probe (design D4, D7).
      stibnite = agent [ ] // {
        platform = "darwin";
        notifiedUnits = [ "otel-envelope" ];
        smartDevices = [ "disk0" ];
      };
      # The laptops that build for the fleet and fill their store disks
      # (bound-fleet-garbage-collection D6). Collecting since operator
      # decision Q44 (2026-11-18); each is a recipient of the shared
      # ntfy-alerter token the collector role wires, which
      # sharedVarsObligations holds on the machine checks.
      rosegold = agent [ ] // {
        platform = "darwin";
        notifiedUnits = [ "otel-envelope" ];
        smartDevices = [ "disk0" ];
      };
      argentum = agent [ ] // {
        platform = "darwin";
        notifiedUnits = [ "otel-envelope" ];
        smartDevices = [ "disk0" ];
      };
      # A reserved name with no machine (modules/clan/inventory/services/tincr.nix):
      # it stays off until a machine takes the name, and nothing can be watched.
      blackphos = agent [ ] // {
        collect = false;
        platform = "darwin";
        notifiedUnits = [ "otel-envelope" ];
      };
    };
}

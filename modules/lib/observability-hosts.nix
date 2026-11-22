# The agent hosts and what each reports (design D6). The inventory's agent
# machines, whether each collects, each host's platform, notified units and
# SMART devices, and the alert rules' always-on hosts, expected hosts and
# SystemdUnitFailed exclusion are read from here. A host's `collect` turns
# the agent role on; a host joining the fleet enters with its `collect`
# false until its watched first deploy. A host joins alwaysOn only by an
# edit here when it becomes permanently provisioned (ADR-009 item 16).
# A NixOS host's `textfile` says it registers a node_exporter textfile
# writer (vanixiets.nodeExporter.textfileWriters), so HostProbeStale expects
# its textfile series; modules/nixos/node-exporter-textfile.nix asserts it
# against the host's own configuration, which its machine check evaluates
# anyway (F76). Every collecting darwin host's probe writes a textfile.
# A NixOS host's `agentTelemetry` turns on the agent-session collector,
# otel-agent-session.service with its loopback receiver, for its agent
# sessions and, through the agent-telemetry home module, the emitters of
# every person and Omnigent worker on it (agent-session-telemetry design D8,
# D14); its row also lists that unit and its envelope among the notified
# units, which the agent role asserts. It is a NixOS option only, so a
# darwin row keeps it false.
{ ... }:
{
  flake.lib.observabilityHosts =
    let
      agent = extra: {
        collect = true;
        platform = "nixos";
        alwaysOn = false;
        smartDevices = [ ];
        textfile = false;
        agentTelemetry = false;
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
          "cache-completeness"
          "devloop-pg-grants"
          "devloop-reconcile"
          "fleet-alert"
          "greptimedb"
          "greptimedb-envelope"
          "greptimedb-schema"
          "otel-agent-session"
          "otel-agent-session-envelope"
          "perses"
          "postgresql-dump-globals"
          "postgresqlBackup-gitea"
          "postgresqlBackup-gitea-mq"
          "postgresqlBackup-matrix-synapse"
          "postgresqlBackup-niks3"
          "postgresqlBackup-nixbot"
          "postgresqlBackup-omnigent"
          "r2-usage"
          "restic-backups-postgresql"
          "zfs-assert-root-docker-noautosnap"
          "zfs-assert-root-greptimedb-noautosnap"
          "zfs-assert-root-nix-noautosnap"
          "zfs-assert-root-podman-noautosnap"
          "zfs-assert-root-postgresql-dumps-noautosnap"
          "zfs-set-root-greptimedb-quota"
          "zfs-set-root-greptimedb-reservation"
          "zfs-set-root-home-reservation"
          "zfs-set-root-nix-quota"
          "zfs-set-root-nixos-reservation"
          "zfs-set-root-postgresql-dumps-quota"
        ]
        // {
          alwaysOn = true;
          textfile = true;
          agentTelemetry = true;
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
      pyrite =
        agent [
          "otel-agent-session"
          "otel-agent-session-envelope"
        ]
        // {
          smartDevices = [ "/dev/nvme0" ];
          agentTelemetry = true;
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

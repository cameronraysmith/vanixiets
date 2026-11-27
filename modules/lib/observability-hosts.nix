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
# anyway (F76). It defaults to set: every collecting NixOS host runs
# zpool-probe, which modules/nixos/zpool-probe.nix asserts. Every
# collecting darwin host's probe writes a textfile.
# A host's `agentTelemetry` turns on the agent-session collector, with its
# loopback receiver on 127.0.0.1:4318, for its agent sessions: on NixOS
# otel-agent-session.service and, through the agent-telemetry home module,
# the emitters of every person and Omnigent worker on it
# (agent-session-telemetry design D8, D14); on darwin the launchd daemon
# org.nixos.otel-agent-session under _otelagent, with the fleet collector's
# own receiver moved to 4319 (darwin-agent-session-telemetry design D2, D3),
# and the emitters of its human homes and its standalone Omnigent workers
# (design D10); org.nixos.otel-agent-session joins that host's kept-alive list
# (flake.lib.launchdKeptAlive, design D6). Its row lists the collector's
# envelope among the notified units, and on NixOS the unit too, which the
# agent role asserts. `agentSpanQueueMiB` sizes a darwin agent-session
# daemon's span queue (design D7): 256 on stibnite, a week of its average
# use off the mesh; the NixOS unit keeps flake.lib.agentSessionCollector's
# default, the 44 of the base row, because its VM tests run it under host
# names that have no row.
# A host's `langfuse`, which requires its `agentTelemetry`, also fans that
# collector's filtered, capped and masked agent spans out to Langfuse Cloud
# (agent-session-telemetry design D16); the agent role asserts the
# requirement, and the host must be a recipient of the shared `langfuse` var
# (flake.lib.sharedVarsObligations). magnetite, pyrite and stibnite set both
# flags; rosegold and argentum neither.
# A row's `platform` is its host's flake.fleet.hosts class, so the rules
# choose a host's expected signals by the class clan builds it as.
# flake.lib.observabilityHostProblems judges a table against the row schema
# (register-fleet-obligations design D8): one message per unknown field, per
# missing field and per value of the wrong type. `platform` must be nixos or
# darwin, which the class's own type does not ensure (it also admits
# android). checks.x86_64-linux.otel-collector-config runs it over this table
# and one mutant per rule; the readers read the table without it.
{ config, lib, ... }:
{
  flake.lib.observabilityHosts =
    let
      agent = extra: {
        collect = true;
        platform = "nixos";
        alwaysOn = false;
        smartDevices = [ ];
        textfile = true;
        agentTelemetry = false;
        langfuse = false;
        agentSpanQueueMiB = 44;
        notifiedUnits = [
          "opentelemetry-collector"
          "otel-envelope"
        ]
        ++ extra;
      };
    in
    lib.mapAttrs (name: row: row // { platform = config.flake.fleet.hosts.${name}.class; }) {
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
          "omnigraph-backup-metric"
          "omnigraph-server"
          "perses"
          "postgresql-dump-globals"
          "postgresqlBackup-gitea"
          "postgresqlBackup-gitea-mq"
          "postgresqlBackup-matrix-synapse"
          "postgresqlBackup-niks3"
          "postgresqlBackup-nixbot"
          "postgresqlBackup-omnigent"
          "r2-usage"
          "restic-backups-omnigraph"
          "restic-backups-postgresql"
          "zfs-assert-root-docker-noautosnap"
          "zfs-assert-root-greptimedb-noautosnap"
          "zfs-assert-root-nix-noautosnap"
          "zfs-assert-root-podman-noautosnap"
          "zfs-assert-root-postgresql-dumps-noautosnap"
          "zfs-set-root-docker-quota"
          "zfs-set-root-greptimedb-quota"
          "zfs-set-root-greptimedb-reservation"
          "zfs-set-root-home-noreservation"
          "zfs-set-root-nix-quota"
          "zfs-set-root-nixos-reservation"
          "zfs-set-root-omnigraph-quota"
          "zfs-set-root-podman-quota"
          "zfs-set-root-postgresql-dumps-quota"
        ]
        // {
          alwaysOn = true;
          agentTelemetry = true;
          langfuse = true;
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
          "enormous-tests"
          "otel-agent-session"
          "otel-agent-session-envelope"
        ]
        // {
          smartDevices = [ "/dev/nvme0" ];
          agentTelemetry = true;
          langfuse = true;
        };
      electrum = agent [ ];
      galena = agent [ ];
      scheelite = agent [ ];
      # A darwin workstation: launchd jobs and the probe's textfile instead of
      # systemd units; its SMART device is read by the probe (design D4, D7).
      stibnite = agent [ ] // {
        notifiedUnits = [
          "otel-envelope"
          "otel-agent-session-envelope"
        ];
        smartDevices = [ "disk0" ];
        agentTelemetry = true;
        langfuse = true;
        agentSpanQueueMiB = 256;
      };
      # The laptops that build for the fleet and fill their store disks
      # (bound-fleet-garbage-collection D6). Collecting since operator
      # decision Q44 (2026-11-18); each is a recipient of the shared
      # ntfy-alerter token the collector role wires, which
      # sharedVarsObligations holds on the machine checks.
      rosegold = agent [ ] // {
        notifiedUnits = [ "otel-envelope" ];
        smartDevices = [ "disk0" ];
      };
      argentum = agent [ ] // {
        notifiedUnits = [ "otel-envelope" ];
        smartDevices = [ "disk0" ];
      };
      # A reserved name with no machine (flake.fleet.hosts.blackphos.enrolled is
      # false): it stays off until a machine takes the name, and nothing can be
      # watched.
      blackphos = agent [ ] // {
        collect = false;
        notifiedUnits = [ "otel-envelope" ];
      };
    };

  flake.lib.observabilityHostProblems =
    let
      isStrings = v: lib.isList v && lib.all lib.isString v;
      rules = {
        collect = lib.isBool;
        platform =
          v:
          lib.elem v [
            "nixos"
            "darwin"
          ];
        alwaysOn = lib.isBool;
        smartDevices = isStrings;
        textfile = lib.isBool;
        agentTelemetry = lib.isBool;
        langfuse = lib.isBool;
        agentSpanQueueMiB = v: lib.isInt v && v > 0;
        notifiedUnits = isStrings;
      };
      rowProblems =
        name: row:
        map (field: "${name}: unknown field ${field}") (
          lib.filter (field: !(rules ? ${field})) (lib.attrNames row)
        )
        ++ lib.concatLists (
          lib.mapAttrsToList (
            field: valid:
            if !(row ? ${field}) then
              [ "${name}: missing field ${field}" ]
            else
              lib.optional (
                !valid row.${field}
              ) "${name}: ${field} is ${builtins.toJSON row.${field}}, of the wrong type"
          ) rules
        );
    in
    table: lib.concatLists (lib.mapAttrsToList rowProblems table);
}

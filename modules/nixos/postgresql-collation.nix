# PostgreSQL collation version drift on the fleet's PostgreSQL hosts (F61).
# On 2026-11-19 every database on magnetite recorded glibc collation version
# 2.42 while the deployed glibc provided 2.44, so their indexes on
# en_US.UTF-8 text were stale, and nothing noticed until pg_dump warned.
# Nothing carried the signal: the collector reads PostgreSQL only for
# devloop's logs, so this module adds a probe in the memory-budget probe's
# form (./magnetite-memory-budget.nix): postgresql-collation.service, every
# 60 s, runs ./postgresql-collation/drift.sql as node_exporter's own user
# over the local socket, peer-authenticated as a role of that name holding
# no grant, and writes vanixiets_postgresql_collation_drift{datname,
# collversion_recorded, collversion_actual}, 1 for a drifted database and 0
# otherwise, to node_exporter's textfile collector; fleet-alert's
# PostgresqlCollationDrift fires on the 1s (modules/nixos/fleet-alert/rules.nix).
# A parked service's database is left out through
# vanixiets.postgresqlCollation.parkedDatabases, which that service's module
# sets while it is off, so reviving it brings its database back under the
# alert. Imported by every NixOS base; acts only where PostgreSQL runs.
# checks.x86_64-linux.postgresql-collation runs the probe against a real
# PostgreSQL with its mutants.
{ config, lib, ... }:
let
  inherit (config.flake) modules;
  schema = config.flake.lib.otelCollectorSchema;

  seriesName = "vanixiets_postgresql_collation_drift";
  directory = "/run/postgresql-collation";

  # The probe, with the query as an argument so the check can build its
  # mutants from the same script. PARKED_FILE holds a JSON array of
  # database names; without OUTPUT_FILE the textfile goes to stdout.
  probe =
    {
      pkgs,
      postgresql,
      sql ? builtins.readFile ./postgresql-collation/drift.sql,
    }:
    pkgs.writeShellApplication {
      name = "postgresql-collation";
      runtimeInputs = [
        postgresql
        pkgs.coreutils
      ];
      text = ''
        parked=$(cat "$1")
        output=''${2:-/dev/stdout}
        lines=$(psql -X -q -A -t -v ON_ERROR_STOP=1 -d postgres -v parked="$parked" -f ${pkgs.writeText "drift.sql" sql})
        text=$(
          echo "# HELP ${seriesName} 1 when the database's recorded collation version differs from the system's."
          echo "# TYPE ${seriesName} gauge"
          if [ -n "$lines" ]; then echo "$lines"; fi
        )
        if [ "$output" = /dev/stdout ]; then
          echo "$text"
        else
          echo "$text" > "$output.tmp"
          chmod 0644 "$output.tmp"
          mv -f "$output.tmp" "$output"
        fi
      '';
    };

  module =
    {
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.vanixiets.postgresqlCollation;
      node = config.services.prometheus.exporters.node;
      textfileFlag = "--collector.textfile.directory=${directory}";
      parkedFile = pkgs.writeText "postgresql-collation-parked.json" (
        builtins.toJSON (lib.naturalSort cfg.parkedDatabases)
      );
      probeService = config.systemd.services.postgresql-collation.serviceConfig;
    in
    {
      options.vanixiets.postgresqlCollation.parkedDatabases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Databases of parked services, which the collation drift probe leaves out; a service's module sets its database here only while the service is off.";
      };

      config = lib.mkIf config.services.postgresql.enable {
        assertions = [
          {
            assertion =
              node.enable
              && lib.elem seriesName schema.nodeExporterKeep
              && lib.elem "--collector.textfile" node.extraFlags
              && lib.elem textfileFlag node.extraFlags;
            message = "postgresql-collation: node_exporter must run its textfile collector on ${directory} and nodeExporterKeep must keep ${seriesName}, or collation drift never reaches the store (F61).";
          }
          # F54: a DynamicUser's RuntimeDirectory is under /run/private,
          # which node_exporter cannot traverse.
          {
            assertion = !(probeService.DynamicUser or false) && (probeService.User or null) == node.user;
            message = "postgresql-collation: the probe must run as node_exporter's user ${node.user}, not as a DynamicUser, or node_exporter cannot read ${directory} (F54).";
          }
        ];

        # node_exporter 1.12.1 takes the textfile directory flag repeated,
        # and the textfile flag itself repeated, beside the memory budget's.
        services.prometheus.exporters.node.extraFlags = [
          "--collector.textfile"
          textfileFlag
        ];

        services.postgresql.ensureUsers = [ { name = node.user; } ];

        systemd.services.postgresql-collation = {
          description = "PostgreSQL collation version drift for node_exporter's textfile collector";
          after = [
            "postgresql.service"
            "postgresql-setup.service"
          ];
          environment.PGHOST = "/run/postgresql";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${
              lib.getExe (probe {
                inherit pkgs;
                postgresql = config.services.postgresql.package;
              })
            } ${parkedFile} ${directory}/collation.prom";
            User = node.user;
            Group = node.group;
            RuntimeDirectory = "postgresql-collation";
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

        systemd.timers.postgresql-collation = {
          description = "Every minute: PostgreSQL collation version drift";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "1min";
            OnUnitActiveSec = "60s";
            AccuracySec = "5s";
          };
        };
      };
    };
in
{
  flake.lib.postgresqlCollation = {
    inherit seriesName probe;
  };

  flake.modules.nixos.postgresql-collation = module;
  flake.modules.nixos.base.imports = [ modules.nixos.postgresql-collation ];
}

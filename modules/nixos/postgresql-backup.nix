# Nightly off-host backups of a host's PostgreSQL databases (openspec change
# back-up-postgresql-off-host, design D2-D11, D15).
#
# Where vanixiets.postgresqlBackup.enable is set on a host running
# PostgreSQL:
# - services.postgresqlBackup dumps each database of the backup set,
#   `ensureDatabases` minus vanixiets.postgresqlCollation.parkedDatabases
#   (D2), as uncompressed `pg_dump -C` SQL into
#   flake.lib.postgresqlBackup.location, with no timer of its own (D3);
#   postgresql-dump-globals.service writes the roles beside them.
# - restic-backups-postgresql, nightly at 02:30 UTC, starts every dump in its
#   prepare step and fails if any fails (D4), then uploads exactly the dump
#   files to its repository in R2 bucket sciexp-postgresql-backup under the
#   host's name (D6), prunes to 7 daily, 4 weekly and 6 monthly copies and
#   reads back a tenth of the repository (D7). `restic-postgresql` is the
#   job's wrapper for listing and restoring.
# - The key and the repository password are clan vars generators
#   postgresql-backup-r2 (prompted, hidden) and postgresql-backup-restic
#   (generated) (D8). Never regenerate postgresql-backup-restic: the
#   repository is readable only with the password it was created under.
# - On success the job records its time in
#   flake.lib.postgresqlBackup.metricsDirectory, under /var/lib so it
#   survives reboots, and writes it into the host's one textfile directory
#   (./node-exporter-textfile.nix) as postgresql-backup.prom.
#   postgresql-backup-metric.service seeds the record with the time of its
#   first run when none exists, so a host that never completes a backup
#   ages too, and republishes it every minute, so the file outlives reboots
#   of /run and stays fresh for HostProbeStale. fleet-alert's
#   PostgresqlBackupStale fires 36 h after the last success (D11).
#
# The option is off by default: declaring the generators makes
# `clan machines update` run them for the host before any deploy, and an
# unattended deploy would prompt for the key or generate the restic password
# outside the repository. A host turns it on in the commit that adds its
# generated vars, and leaves flake.lib.postgresqlBackup.awaitingSecrets in
# that commit. flake.lib.postgresqlBackupObligations.failures, asserted on
# every machine check by modules/checks/machines.nix, fails a PostgreSQL
# host that neither backs up nor awaits its secrets, a host that backs up
# without its vars in the repository, and every drift of the backup set,
# the dumps' timers, the uploaded paths, the prepare step and the notified
# units from each other; checks.x86_64-linux.postgresql-backup-obligations
# judges the judge over literal fixtures.
#
# Imported by every NixOS base. vmTests.x86_64-linux.postgresql-backup-restore
# drops and restores two databases from the job's own snapshot; rerun it on
# every change to this module.
{ config, lib, ... }:
let
  inherit (config.flake) modules;
  schema = config.flake.lib.otelCollectorSchema;
  inherit (config.flake.lib) vars;
  inherit (config.flake.lib.nodeExporterTextfile) flag;

  location = "/var/backup/postgresql-nightly";
  jobName = "postgresql";
  metricsDirectory = "/var/lib/postgresql-backup-metrics";
  seriesName = "vanixiets_postgresql_backup_last_success_timestamp_seconds";
  writer = "postgresql-backup";
  bucket = "sciexp-postgresql-backup";
  endpoint = "https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com";
  generators = {
    r2 = "postgresql-backup-r2";
    restic = "postgresql-backup-restic";
  };
  # PostgreSQL hosts whose vars the operator has not yet generated; such a
  # host runs with the backup off and the obligation accepts it.
  awaitingSecrets = [ ];

  dumpUnit = db: "postgresqlBackup-${db}";
  globalsUnit = "postgresql-dump-globals";
  jobUnit = "restic-backups-${jobName}";

  # The pure judge (design D15). `facts`:
  #   postgresql        { enable; ensureDatabases; }
  #   enable            vanixiets.postgresqlBackup.enable
  #   awaiting          the host is in awaitingSecrets
  #   secretsGenerated  both generators' deployed files are in the repository
  #   parked            vanixiets.postgresqlCollation.parkedDatabases
  #   postgresqlBackup  { databases; compression; location; }
  #   services          systemd.services
  #   restic            services.restic.backups.postgresql, or null
  #   notifiedUnits     the host's row in flake.lib.observabilityHosts
  problems =
    {
      postgresql,
      enable,
      awaiting,
      secretsGenerated,
      parked,
      postgresqlBackup,
      services,
      restic,
      notifiedUnits,
    }:
    let
      backupSet = lib.subtractLists parked postgresql.ensureDatabases;
      dumped = postgresqlBackup.databases;
      paths = if restic == null then [ ] else restic.paths or [ ];
      prepare = if restic == null then "" else toString (restic.backupPrepareCommand or "");
      units = map dumpUnit dumped ++ [ globalsUnit ];
    in
    if !postgresql.enable then
      [ ]
    else if !enable then
      lib.optional (!awaiting)
        "PostgreSQL runs without vanixiets.postgresqlBackup.enable, and the host is not in flake.lib.postgresqlBackup.awaitingSecrets"
    else
      lib.optional awaiting "vanixiets.postgresqlBackup.enable is set but the host is still in flake.lib.postgresqlBackup.awaitingSecrets"
      ++
        lib.optional (!secretsGenerated)
          "vanixiets.postgresqlBackup.enable is set but the vars of ${generators.r2} and ${generators.restic} are not in the repository; run `clan vars generate` for both first, or a deploy would generate the repository password outside the repository"
      ++ map (db: "database ${db} is not in services.postgresqlBackup.databases") (
        lib.subtractLists dumped backupSet
      )
      ++ map (db: "${dumpUnit db} has a timer of its own; the backup job starts the dumps (D4)") (
        lib.filter (db: lib.toList (services.${dumpUnit db}.startAt or [ ]) != [ ]) dumped
      )
      ++ lib.optional (
        postgresqlBackup.compression != "none"
      ) "services.postgresqlBackup.compression is ${postgresqlBackup.compression}, not none (D3)"
      ++ map (file: "${file} is not in the backup job's paths") (
        lib.filter (file: !lib.elem file paths) (
          map (db: "${postgresqlBackup.location}/${db}.sql") dumped
          ++ [ "${postgresqlBackup.location}/globals.sql" ]
        )
      )
      ++ map (unit: "${unit}.service is not started by the backup job's backupPrepareCommand") (
        lib.filter (unit: !lib.hasInfix "${unit}.service" prepare) units
      )
      ++ map (unit: "${unit} is not in the host's notifiedUnits") (
        lib.filter (unit: !lib.elem unit notifiedUnits) ([ jobUnit ] ++ units)
      );

  factsOf = name: hostConfig: {
    postgresql = {
      enable = hostConfig.services.postgresql.enable or false;
      ensureDatabases = hostConfig.services.postgresql.ensureDatabases or [ ];
    };
    enable = hostConfig.vanixiets.postgresqlBackup.enable or false;
    awaiting = lib.elem name awaitingSecrets;
    secretsGenerated =
      vars.exists {
        machine = name;
        generator = generators.r2;
        file = "env";
      }
      && vars.exists {
        machine = name;
        generator = generators.restic;
        file = "password";
      };
    parked = hostConfig.vanixiets.postgresqlCollation.parkedDatabases or [ ];
    postgresqlBackup = {
      inherit (hostConfig.services.postgresqlBackup) databases compression location;
    };
    services = hostConfig.systemd.services;
    restic = hostConfig.services.restic.backups.${jobName} or null;
    notifiedUnits = config.flake.lib.observabilityHosts.${name}.notifiedUnits or [ ];
  };

  module =
    {
      config,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.vanixiets.postgresqlBackup;
      node = config.services.prometheus.exporters.node;
      directory = config.vanixiets.nodeExporter.textfileDirectory;
      record = "${metricsDirectory}/backup.prom";
      published = "${directory}/${writer}.prom";
      backupSet = lib.subtractLists config.vanixiets.postgresqlCollation.parkedDatabases config.services.postgresql.ensureDatabases;
      units = map (db: "${dumpUnit db}.service") backupSet ++ [ "${globalsUnit}.service" ];
      gens = config.clan.core.vars.generators;

      # Copies the record into the textfile directory by write-then-rename,
      # so node_exporter never reads a partial file.
      publish = pkgs.writeShellScript "postgresql-backup-publish" ''
        set -eu
        ${pkgs.coreutils}/bin/install -m 0644 ${record} ${published}.tmp
        ${pkgs.coreutils}/bin/mv -f ${published}.tmp ${published}
      '';
      # Writes the record with the current time, then publishes it.
      stamp = pkgs.writeShellScript "postgresql-backup-stamp" ''
        set -eu
        {
          echo "# HELP ${seriesName} Unix time of the last backup run whose backup, prune and check all succeeded."
          echo "# TYPE ${seriesName} gauge"
          echo "${seriesName} $(${pkgs.coreutils}/bin/date +%s)"
        } > ${record}.tmp
        ${pkgs.coreutils}/bin/chmod 0644 ${record}.tmp
        ${pkgs.coreutils}/bin/mv -f ${record}.tmp ${record}
        ${publish}
      '';
    in
    {
      options.vanixiets.postgresqlBackup.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Back up this host's PostgreSQL databases to R2 nightly. Set it in the commit that adds the host's generated postgresql-backup-r2 and postgresql-backup-restic vars.";
      };

      config = lib.mkIf (cfg.enable && config.services.postgresql.enable) (
        lib.mkMerge [
          {
            assertions = [
              {
                assertion =
                  node.enable
                  && lib.elem seriesName schema.nodeExporterKeep
                  && lib.elem "${flag}=${directory}" node.extraFlags;
                message = "postgresql-backup: node_exporter must run its textfile collector on ${directory} and nodeExporterKeep must keep ${seriesName}, or PostgresqlBackupStale never sees a backup.";
              }
            ];

            services.postgresqlBackup = {
              enable = true;
              databases = backupSet;
              compression = "none";
              startAt = [ ];
              inherit location;
            };

            systemd.services.${globalsUnit} = {
              description = "Dump of PostgreSQL's roles and tablespaces";
              requires = [ "postgresql.target" ];
              after = [ "postgresql.target" ];
              path = [
                pkgs.coreutils
                config.services.postgresql.package
              ];
              script = ''
                set -e -o pipefail
                umask 0077
                pg_dumpall --globals-only > ${location}/globals.sql.in-progress
                mv ${location}/globals.sql.in-progress ${location}/globals.sql
              '';
              serviceConfig = {
                Type = "oneshot";
                User = "postgres";
              };
            };

            services.restic.backups.${jobName} = {
              repository = "s3:${endpoint}/${bucket}/${config.networking.hostName}";
              extraOptions = [
                "s3.bucket-lookup=path"
                "s3.region=auto"
              ];
              initialize = true;
              createWrapper = true;
              paths = map (db: "${location}/${db}.sql") backupSet ++ [ "${location}/globals.sql" ];
              # Sequentially, so one dump at a time holds memory; every dump
              # is attempted, and any failure fails the job before upload.
              backupPrepareCommand = ''
                #!${pkgs.runtimeShell}
                failed=0
                for unit in ${lib.escapeShellArgs units}; do
                  ${config.systemd.package}/bin/systemctl start --wait "$unit" || {
                    echo "$unit failed" >&2
                    failed=1
                  }
                done
                exit "$failed"
              '';
              # The timer of a notified unit names its zone, as
              # modules/nixos/observability-notify.nix asserts.
              timerConfig = {
                OnCalendar = "*-*-* 02:30:00 UTC";
                RandomizedDelaySec = "15m";
                Persistent = true;
              };
              pruneOpts = [
                "--keep-daily 7"
                "--keep-weekly 4"
                "--keep-monthly 6"
                "--group-by host"
              ];
              checkOpts = [ "--read-data-subset=10%" ];
            };

            # Runs only after backup, prune and check have all succeeded.
            systemd.services.${jobUnit}.serviceConfig.ExecStartPost = [ "${stamp}" ];

            vanixiets.nodeExporter.textfileWriters = [ writer ];

            systemd.tmpfiles.settings."10-postgresql-backup-metrics".${metricsDirectory}.d = {
              user = "root";
              group = "root";
              mode = "0755";
            };

            systemd.services.postgresql-backup-metric = {
              description = "Seed and publish the last successful PostgreSQL backup time";
              wantedBy = [ "multi-user.target" ];
              script = ''
                set -eu
                if [ ! -e ${record} ]; then
                  ${stamp}
                else
                  ${publish}
                fi
              '';
              serviceConfig = {
                Type = "oneshot";
                MemoryMax = "32M";
              };
            };

            systemd.timers.postgresql-backup-metric = {
              description = "Every minute: publish the last successful PostgreSQL backup time";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnBootSec = "1min";
                OnUnitActiveSec = "60s";
                AccuracySec = "5s";
              };
            };
          }
          {
            services.restic.backups.${jobName} = {
              passwordFile = lib.mkDefault gens.${generators.restic}.files.password.path;
              environmentFile = lib.mkDefault gens.${generators.r2}.files.env.path;
            };
          }
          (lib.optionalAttrs (options ? clan.core.vars) {
            clan.core.vars.generators.${generators.r2} = {
              prompts.access-key = {
                description = ''
                  Cloudflare R2 S3 access key ID of an Account API token with
                  Object Read & Write on bucket ${bucket} only. Minted in the
                  Cloudflare dashboard; used by no other service.
                '';
                type = "hidden";
                persist = true;
                display = {
                  group = "postgresql-backup";
                  label = "AWS_ACCESS_KEY_ID";
                };
              };
              prompts.secret-key = {
                description = "Cloudflare R2 S3 secret access key paired with the access key ID above.";
                type = "hidden";
                persist = true;
                display = {
                  group = "postgresql-backup";
                  label = "AWS_SECRET_ACCESS_KEY";
                };
              };
              files.access-key.deploy = false;
              files.secret-key.deploy = false;
              files.env = { };
              script = ''
                {
                  printf 'AWS_ACCESS_KEY_ID=%s\n' "$(cat "$prompts/access-key")"
                  printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$(cat "$prompts/secret-key")"
                } > "$out/env"
              '';
            };

            clan.core.vars.generators.${generators.restic} = {
              files.password = { };
              runtimeInputs = [
                pkgs.openssl
                pkgs.coreutils
              ];
              script = ''
                openssl rand -base64 32 | tr -d '\n' > "$out/password"
              '';
            };
          })
        ]
      );
    };
in
{
  flake.lib.postgresqlBackup = {
    inherit
      location
      jobName
      metricsDirectory
      seriesName
      bucket
      awaitingSecrets
      ;
  };

  flake.lib.postgresqlBackupObligations = {
    inherit problems factsOf;
    failures = name: hostConfig: problems (factsOf name hostConfig);
  };

  fleetObligations.postgresqlBackupObligations.failures =
    config.flake.lib.postgresqlBackupObligations.failures;

  flake.modules.nixos.postgresql-backup = module;
  flake.modules.nixos.base.imports = [ modules.nixos.postgresql-backup ];
}

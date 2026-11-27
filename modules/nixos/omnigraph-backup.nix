# Nightly off-host backups of a host's local omnigraph root (openspec change
# serve-omnigraph-from-local-disk, design D5), modelled on
# ./postgresql-backup.nix.
#
# Where vanixiets.omnigraphBackup.enable is set on a host whose
# services.omnigraph.storageUri is a root under
# flake.lib.omnigraphClusterRoots.localDirectory, on ZFS dataset
# zroot/root/omnigraph mounted at /var/lib/omnigraph, the omnigraph units'
# state directory itself, owned by their static user:
# - restic-backups-omnigraph, nightly at 03:30 UTC, takes the snapshot
#   zroot/root/omnigraph@restic in its prepare step (destroying one a failed
#   run left), backs up only the snapshot's directory
#   /var/lib/omnigraph/.zfs/snapshot/restic, a fixed path so restic
#   finds each run's parent snapshot, and destroys the snapshot in its
#   cleanup step. A snapshot is an instant image of the root and its
#   bootstrap markers; a file-by-file copy of a live root is not a backup
#   (the omnigraph runbook), so the module refuses any other path.
# - The repository is R2 bucket sciexp-omnigraph-backup under the host's
#   name; the job prunes to 7 daily, 4 weekly and 6 monthly copies and reads
#   back a tenth of the repository each night. `restic-omnigraph` is the
#   job's wrapper for listing and restoring.
# - The key and the repository password are clan vars generators
#   omnigraph-backup-r2 (prompted, hidden) and omnigraph-backup-restic
#   (generated). Never regenerate omnigraph-backup-restic: the repository is
#   readable only with the password it was created under.
# - On success the job records its time in /var/lib/omnigraph-backup-metrics
#   and writes it into the host's one textfile directory as
#   omnigraph-backup.prom; omnigraph-backup-metric seeds the record on its
#   first run when none exists and republishes it every minute, so a host
#   that never completes a backup ages too. fleet-alert's
#   OmnigraphBackupStale fires 36 h after the last success.
#
# The option is off by default: declaring the generators makes
# `clan machines update` run them for the host, and a host turns it on in
# the commit that adds its generated vars. The module asserts the local
# root, the snapshot path, and that the job, its publisher and the dataset's
# quota oneshot are notified units of the host.
# vmTests.x86_64-linux.omnigraph-local-root backs up a served root to a
# local repository, empties the dataset and restores it.
{ config, lib, ... }:
let
  inherit (config.flake) modules;
  schema = config.flake.lib.otelCollectorSchema;
  inherit (config.flake.lib.nodeExporterTextfile) flag;
  inherit (config.flake.lib.omnigraphServer) localRootOf;
  roots = config.flake.lib.omnigraphClusterRoots;

  dataset = "zroot/root/omnigraph";
  mountpoint = "/var/lib/omnigraph";
  snapshot = "${dataset}@restic";
  snapshotPath = "${mountpoint}/.zfs/snapshot/restic";
  jobName = "omnigraph";
  jobUnit = "restic-backups-${jobName}";
  metricUnit = "omnigraph-backup-metric";
  quotaUnit = "zfs-set-${
    lib.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "zroot/" dataset)
  }-quota";
  metricsDirectory = "/var/lib/omnigraph-backup-metrics";
  seriesName = "vanixiets_omnigraph_backup_last_success_timestamp_seconds";
  writer = "omnigraph-backup";
  bucket = "sciexp-omnigraph-backup";
  endpoint = "https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com";
  generators = {
    r2 = "omnigraph-backup-r2";
    restic = "omnigraph-backup-restic";
  };

  module =
    {
      config,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.vanixiets.omnigraphBackup;
      node = config.services.prometheus.exporters.node;
      directory = config.vanixiets.nodeExporter.textfileDirectory;
      record = "${metricsDirectory}/backup.prom";
      published = "${directory}/${writer}.prom";
      gens = config.clan.core.vars.generators;
      zfs = "${config.boot.zfs.package}/bin/zfs";
      localRoot = localRootOf config.services.omnigraph.storageUri;
      notified = config.services.observability-notify.units or [ ];
      unnotified = lib.filter (unit: !lib.elem unit notified) [
        jobUnit
        metricUnit
        quotaUnit
      ];

      publish = pkgs.writeShellScript "omnigraph-backup-publish" ''
        set -eu
        ${pkgs.coreutils}/bin/install -m 0644 ${record} ${published}.tmp
        ${pkgs.coreutils}/bin/mv -f ${published}.tmp ${published}
      '';
      stamp = pkgs.writeShellScript "omnigraph-backup-stamp" ''
        set -eu
        {
          echo "# HELP ${seriesName} Unix time of the last omnigraph backup run whose backup, prune and check all succeeded."
          echo "# TYPE ${seriesName} gauge"
          echo "${seriesName} $(${pkgs.coreutils}/bin/date +%s)"
        } > ${record}.tmp
        ${pkgs.coreutils}/bin/chmod 0644 ${record}.tmp
        ${pkgs.coreutils}/bin/mv -f ${record}.tmp ${record}
        ${publish}
      '';
      resticCommand =
        let
          job = config.services.restic.backups.${jobName};
        in
        "${lib.getExe job.package}${lib.concatMapStrings (option: " -o ${option}") job.extraOptions}";
    in
    {
      # Declares the vanixiets.nodeExporter options set below, which the
      # module system requires even while the backup is off.
      imports = [ modules.nixos.node-exporter-textfile ];

      options.vanixiets.omnigraphBackup.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Back up this host's local omnigraph root to R2 nightly from a ZFS snapshot of ${dataset}. Set it in the commit that adds the host's generated ${generators.r2} and ${generators.restic} vars.";
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            assertions = [
              {
                assertion = localRoot != null && lib.hasPrefix "${roots.localDirectory}/" localRoot;
                message = "omnigraph-backup: services.omnigraph.storageUri (${config.services.omnigraph.storageUri}) must be a root under ${roots.localDirectory}, on ${dataset} mounted at ${mountpoint}; a root in a bucket has no snapshot to back up.";
              }
              {
                assertion = config.services.restic.backups.${jobName}.paths == [ snapshotPath ];
                message = "omnigraph-backup: ${jobUnit} must back up only ${snapshotPath}, the snapshot its prepare step takes; a copy of the live root is not a backup.";
              }
              {
                assertion = unnotified == [ ];
                message = "omnigraph-backup: ${lib.concatStringsSep ", " unnotified} must be in services.observability-notify.units (the host's notifiedUnits), so that their failures post a notice.";
              }
              {
                assertion =
                  node.enable
                  && lib.elem seriesName schema.nodeExporterKeep
                  && lib.elem "${flag}=${directory}" node.extraFlags;
                message = "omnigraph-backup: node_exporter must run its textfile collector on ${directory} and nodeExporterKeep must keep ${seriesName}, or OmnigraphBackupStale never sees a backup.";
              }
            ];

            services.restic.backups.${jobName} = {
              repository = "s3:${endpoint}/${bucket}/${config.networking.hostName}";
              extraOptions = [
                "s3.bucket-lookup=path"
                "s3.region=auto"
              ];
              initialize = true;
              createWrapper = true;
              paths = [ snapshotPath ];
              backupPrepareCommand = ''
                #!${pkgs.runtimeShell}
                set -eu
                if ${zfs} list -H -t snapshot ${snapshot} >/dev/null 2>&1; then
                  ${zfs} destroy ${snapshot}
                fi
                ${zfs} snapshot ${snapshot}
              '';
              backupCleanupCommand = ''
                #!${pkgs.runtimeShell}
                ${zfs} destroy ${snapshot}
              '';
              # The timer of a notified unit names its zone, as
              # ./observability-notify.nix asserts. 03:30 keeps the job apart
              # from the PostgreSQL backup at 02:30.
              timerConfig = {
                OnCalendar = "*-*-* 03:30:00 UTC";
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

            systemd.services.${jobUnit}.serviceConfig = {
              # Runs only after backup, prune and check have all succeeded.
              ExecStartPost = [ "${stamp}" ];
              # restic refuses the backup's lock while any exclusive lock
              # is in the repository, stale or not, and nixpkgs runs
              # `unlock` only after the backup, so a run interrupted in its
              # prune or check would fail every later run. `unlock` removes
              # only stale locks: one older than 30 minutes, which a running
              # restic refreshes every 5, or one taken on this host by a
              # process that is gone (restic 0.20.0,
              # internal/repository/lock_file.go).
              ExecStart = lib.mkBefore [ "${resticCommand} unlock" ];
            };

            vanixiets.nodeExporter.textfileWriters = [ writer ];

            systemd.tmpfiles.settings."10-omnigraph-backup-metrics".${metricsDirectory}.d = {
              user = "root";
              group = "root";
              mode = "0755";
            };

            systemd.services.${metricUnit} = {
              description = "Seed and publish the last successful omnigraph backup time";
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

            systemd.timers.${metricUnit} = {
              description = "Every minute: publish the last successful omnigraph backup time";
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
                  group = "omnigraph-backup";
                  label = "AWS_ACCESS_KEY_ID";
                };
              };
              prompts.secret-key = {
                description = "Cloudflare R2 S3 secret access key paired with the access key ID above.";
                type = "hidden";
                persist = true;
                display = {
                  group = "omnigraph-backup";
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
  flake.lib.omnigraphBackup = {
    inherit
      dataset
      mountpoint
      snapshot
      snapshotPath
      jobName
      metricsDirectory
      seriesName
      bucket
      ;
    # The units that exist only beside a local root, the backup job, its
    # publisher and the dataset's quota oneshot, which a host's row in
    # flake.lib.observabilityHosts notifies only while its store is "local".
    localRootUnits = [
      jobUnit
      metricUnit
      quotaUnit
    ];
  };

  flake.modules.nixos.omnigraph-backup = module;
  flake.modules.nixos.omnigraph.imports = [ modules.nixos.omnigraph-backup ];
}

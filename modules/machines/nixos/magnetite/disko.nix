# Disko disk configuration for magnetite (Hetzner CX53 BIOS boot)
{ ... }:
{
  flake.modules.nixos."machines/nixos/magnetite" =
    { config, lib, ... }:
    {
      disko.devices = {
        disk.main = {
          type = "disk";
          device = "/dev/sda";
          content = {
            type = "gpt";
            partitions = {
              # BIOS boot partition (required for GRUB on GPT)
              boot = {
                size = "1M";
                type = "EF02";
              };
              grub = {
                size = "1G";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/boot";
                };
              };
              zfs = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "zroot";
                };
              };
            };
          };
        };
        zpool.zroot = {
          type = "zpool";
          rootFsOptions = {
            compression = "lz4";
            "com.sun:auto-snapshot" = "true";
          };
          datasets = {
            "root" = {
              type = "zfs_fs";
              options.mountpoint = "none";
            };
            "root/nixos" = {
              type = "zfs_fs";
              options = {
                mountpoint = "/";
                reservation = "10G";
              };
              mountpoint = "/";
            };
            "root/home" = {
              type = "zfs_fs";
              options = {
                mountpoint = "/home";
                reservation = "4G";
              };
              mountpoint = "/home";
            };
            "root/nix" = {
              type = "zfs_fs";
              options = {
                mountpoint = "/nix";
                "com.sun:auto-snapshot" = "false";
                quota = "250G";
              };
              mountpoint = "/nix";
            };
            "root/podman" = {
              type = "zfs_fs";
              options.mountpoint = "/var/lib/containers";
              mountpoint = "/var/lib/containers";
            };
            "root/cognee" = {
              type = "zfs_fs";
              options.mountpoint = "/var/lib/cognee";
              mountpoint = "/var/lib/cognee";
            };
            # Telemetry store WAL and caches (ADR-007; design D5). Created by hand
            # on the installed host (tasks.md 8.3); this declaration covers a
            # reinstall, and the zfs-*-root-greptimedb-* oneshots in default.nix
            # enforce the properties on every boot.
            "root/greptimedb" = {
              type = "zfs_fs";
              options = {
                mountpoint = "/var/lib/greptimedb";
                "com.sun:auto-snapshot" = "false";
                quota = "16G";
                reservation = "12G";
              };
              mountpoint = "/var/lib/greptimedb";
            };
            # Nightly PostgreSQL dumps (back-up-postgresql-off-host design D5),
            # at flake.lib.postgresqlBackup.location: off auto-snapshot, since
            # restic keeps every night's copy and snapshots would pin each
            # rewrite, and quota-bound. Created by hand on the installed host
            # (tasks.md 2.1) before the backup is turned on; this declaration
            # covers a reinstall, and the zfs-*-root-postgresql-dumps-* oneshots
            # in default.nix enforce the properties on every boot. Declared only
            # with the backup on, so the mount never precedes the dataset.
            "root/postgresql-dumps" = lib.mkIf config.vanixiets.postgresqlBackup.enable {
              type = "zfs_fs";
              options = {
                mountpoint = "/var/backup/postgresql-nightly";
                "com.sun:auto-snapshot" = "false";
                quota = "16G";
              };
              mountpoint = "/var/backup/postgresql-nightly";
            };
            # The local omnigraph root and its bootstrap markers, one dataset so
            # one snapshot holds both (openspec change
            # serve-omnigraph-from-local-disk). Mounted at the omnigraph units'
            # state directory itself, quota-bound so the graph data cannot
            # starve the pool, and left on auto-snapshot for local restore
            # points; restic-backups-omnigraph copies its own snapshot off host.
            # Created by hand on the installed host; this declaration covers a
            # reinstall, and zfs-set-root-omnigraph-quota in default.nix
            # enforces the quota on every boot. Declared only with the root on
            # the local store, so the mount never precedes the dataset.
            "root/omnigraph" = lib.mkIf (config.vanixiets.omnigraphRootStore == "local") {
              type = "zfs_fs";
              options = {
                mountpoint = "/var/lib/omnigraph";
                quota = "20G";
              };
              mountpoint = "/var/lib/omnigraph";
            };
            # Dedicated dataset for docker graphroot to use the native ZFS
            # storage driver (docker's overlay2 does not layer cleanly on ZFS,
            # and /var/lib/docker must be its own dataset for the zfs driver).
            # Coexists with zroot/root/podman; disjoint mountpoints.
            "root/docker" = {
              type = "zfs_fs";
              options.mountpoint = "/var/lib/docker";
              mountpoint = "/var/lib/docker";
            };
          };
        };
      };
    };
}

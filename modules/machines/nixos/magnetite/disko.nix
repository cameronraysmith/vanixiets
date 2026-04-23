# Disko disk configuration for magnetite (Hetzner CX53 BIOS boot)
{ ... }:
{
  flake.modules.nixos."machines/nixos/magnetite" = {
    # Disko disk configuration for BIOS boot
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
            # Boot partition for GRUB
            grub = {
              size = "1G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/boot";
              };
            };
            # ZFS partition
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
            options.mountpoint = "/";
            mountpoint = "/";
          };
          "root/home" = {
            type = "zfs_fs";
            options.mountpoint = "/home";
            mountpoint = "/home";
          };
          "root/nix" = {
            type = "zfs_fs";
            options.mountpoint = "/nix";
            mountpoint = "/nix";
          };
          "root/podman" = {
            type = "zfs_fs";
            options.mountpoint = "/var/lib/containers";
            mountpoint = "/var/lib/containers";
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

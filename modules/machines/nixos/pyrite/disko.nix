# Disko disk configuration for pyrite (Apple MacBookPro14,1, UEFI boot, encrypted ZFS root)
{ ... }:
{
  # Sibling-file auto-merge into the pyrite host module (no import statement), the
  # pattern every existing machine uses. The value is a module function because the
  # encrypted-root keylocation reads the clan vars generator path and the generator
  # script reads pkgs.
  flake.modules.nixos."machines/nixos/pyrite" =
    {
      config,
      pkgs,
      ...
    }:
    {
      # The create-time key: a human-typeable passphrase, not hex. clan-cli resolves a
      # neededFor = "partitioning" file to /run/partitioning-secrets/zfs/key during the
      # install and appends it to nixos-anywhere's --disk-encryption-keys automatically.
      # Not build01's `| tr -d "\n"`: that trim serves cryptsetup --key-file, whereas ZFS
      # trims one trailing newline itself for non-RAW keyformats. Writes $out/key to match
      # the files.key attribute the layout reads as files.key.path. See D4.
      clan.core.vars.generators.zfs = {
        files.key.neededFor = "partitioning";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.xkcdpass
        ];
        script = ''
          xkcdpass --numwords 6 --random-delimiters --case random > $out/key
        '';
      };

      disko.devices = {
        disk.primary = {
          type = "disk";
          # nvme0n1 (465.9 GiB). The controller exposes a second 8 KiB namespace,
          # nvme0n2, reachable at the by-id name ending _2 which must never be written;
          # the unsuffixed name is a bare prefix of both, so the namespace is named
          # explicitly via the _1 suffix. See D3.
          device = "/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "1G";
                # EF00 stated explicitly: Apple's EFI firmware discovers the ESP by
                # partition type, and disko defaults an unspecified type to 8300 (Linux
                # filesystem), which is not discoverable as an ESP. The failure surfaces
                # only after macOS has been irreversibly wiped, with no fallback OS to
                # correct it from. See D3/spec.
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                };
              };
              # Sibling of the ESP: this partition's zfs content is the only thing that
              # registers a device into $disko_devices_dir/zfs_zroot, which the zpool
              # block reads back to build its vdev list. Without it, pool creation exits 1
              # after the wipe has already destroyed macOS.
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
          # ashift = 12 because the disk reports 4096-byte logical/physical sectors
          # (2^12 = 4096); no other machine in the fleet sets this, since all five are
          # 512-byte cloud disks, and disko performs no sector-size detection, passing
          # zpool options through verbatim to `zpool create -o`. See D2.
          options.ashift = "12";
          rootFsOptions = {
            compression = "lz4";
            "com.sun:auto-snapshot" = "true";
          };
          datasets = {
            "root" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                encryption = "aes-256-gcm";
                keyformat = "passphrase";
                keylocation = "file://${config.clan.core.vars.generators.zfs.files.key.path}";
              };
              # The create-time /run/partitioning-secrets/zfs/key path exists only during
              # the install; nothing recreates it at boot. The flip to prompt is what makes
              # the machine bootable — a dataset left at the file:// value boots unable to
              # find its key. keylocation is settable post-create (absent from disko's
              # onetimeProperties), unlike encryption and keyformat. See D1/D4.
              postCreateHook = ''zfs set keylocation="prompt" "zroot/root"'';
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
          };
        };
      };
    };
}

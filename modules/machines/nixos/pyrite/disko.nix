# Disko disk configuration for pyrite (Apple MacBookPro14,1, UEFI boot, LUKS2-encrypted ZFS root)
{ ... }:
{
  # Sibling-file auto-merge into the pyrite host module (no import statement), the
  # pattern every existing machine uses. The value is a module function because the
  # LUKS content's passwordFile/additionalKeyFiles read the clan vars generator path
  # and the generator script reads pkgs.
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
      # The script strips the trailing newline with `| tr -d "\n"` (build01's
      # disko.nix:78): additionalKeyFiles hands this path to `cryptsetup luksAddKey`
      # verbatim (lib/types/luks.nix:259), so a trailing newline enrolls a keyslot that
      # opens for no one — the passwordFile open and a person typing at the prompt both
      # present the passphrase without the newline. Writes $out/key to match the files.key
      # attribute the layout reads as files.key.path. The delimiter is a layout-stable
      # hyphen rather than --random-delimiters so the fallback passphrase is typeable at
      # the initrd console. See D4/D27.
      clan.core.vars.generators.zfs = {
        files.key.neededFor = "partitioning";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.xkcdpass
        ];
        script = ''
          xkcdpass --numwords 6 --delimiter - --case random | tr -d "\n" > $out/key
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
              # Sibling of the ESP: this partition carries a LUKS2 container named
              # cryptroot whose nested zfs content is the only thing that registers a device
              # — /dev/mapper/cryptroot — into $disko_devices_dir/zfs_zroot, which the zpool
              # block reads back to build its vdev list. disko fixes the nested content's
              # device to the mapper (lib/types/luks.nix:184-187) and splices its _create
              # after the container is formatted and opened (:303). Without the nested zfs
              # content the zpool block has no device and pool creation exits 1 after the
              # wipe has already destroyed macOS. See D1.
              zfs = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "cryptroot";
                  settings = {
                    allowDiscards = true;
                    bypassWorkqueues = true;
                  };
                  enrollFido2 = true;
                  enrollRecovery = false;
                  passwordFile = config.clan.core.vars.generators.zfs.files.key.path;
                  additionalKeyFiles = [ config.clan.core.vars.generators.zfs.files.key.path ];
                  content = {
                    type = "zfs";
                    pool = "zroot";
                  };
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
          # zpool options through verbatim to `zpool create -o`. Under D1 the vdev is
          # /dev/mapper/cryptroot, whose autodetected sector size would follow the LUKS2
          # header rather than the media beneath it, so the explicit 12 (the physical
          # sector size) is more load-bearing than under ZFS-native encryption, not less.
          # See D2.
          options.ashift = "12";
          rootFsOptions = {
            compression = "lz4";
            "com.sun:auto-snapshot" = "true";
            # Both inherit to every dataset and are settled in this create window (7.12's
            # reinstall is the last scheduled occasion to influence root-dataset creation).
            # xattr=sa stores extended attributes inline in the dnode; acltype=posixacl is
            # needed because journald applies POSIX ACLs to the per-user journals under
            # /var/log/journal and a pool without it drops them silently. Both are settable
            # after creation, but zfs set applies each only to attributes written afterward,
            # so a retrofit on a populated root is partial in a way the reported value hides.
            # normalization is deliberately left unset: it is create-only and any value
            # other than none implicitly sets utf8only=on, rejecting non-UTF-8 filenames a
            # general-purpose laptop root will encounter. See D23.
            xattr = "sa";
            acltype = "posixacl";
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
          };
        };
      };
    };
}

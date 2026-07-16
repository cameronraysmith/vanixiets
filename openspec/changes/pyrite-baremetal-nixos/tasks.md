## 1. Phase 1 — Flake input scaffolding

- [ ] 1.1 Add `nixos-hardware` to `flake.nix` inputs with `inputs.nixpkgs.follows = "nixpkgs"`, mirroring the disko declaration at `flake.nix:83-84`
- [ ] 1.2 Confirm `nix flake check` still passes with the input added and unused, before any machine imports it

## 2. Phase 2 — The pyrite host module

- [ ] 2.1 Create `modules/machines/nixos/pyrite/default.nix` exporting `flake.modules.nixos."machines/nixos/pyrite"`, shaped after `modules/machines/nixos/electrum/default.nix` (the fleet's only UEFI/systemd-boot host), importing `base`, `hm-sops-bridge`, `ssh-known-hosts`, home-manager, and `nixos-hardware.nixosModules.apple-macbook-pro-14-1`
- [ ] 2.2 Set `networking.enableB43Firmware = false` and `hardware.facetimehd.enable = false` — plain `false`, not `mkForce`, since both upstream values are `lib.mkDefault` — with a comment recording that b43 is a misdetection for BCM4350/brcmfmac silicon rather than an evaluation workaround
- [ ] 2.3 Set `boot.loader.systemd-boot.enable = true`, `boot.loader.efi.canTouchEfiVariables = true`, `boot.zfs.devNodes = "/dev/disk/by-id"`, `networking.hostName = "pyrite"`, and `system.stateVersion`
- [ ] 2.4 Wire the admin user `cameron` exactly as electrum does: `hm-sops-bridge.users.cameron = { };` and `home-manager.users.cameron = { imports = flakeUsers.cameron.modules; };` — cameron is the preferred username on new machines and folds to crs58 by alias
- [ ] 2.5 Disable `boot.initrd.network.ssh`, which cannot function on a `brcmfmac`-only machine. Do NOT touch `boot.initrd.kernelModules`: `lib.mkForce` on that list would discard the profile's SPI modules and `i915` and render the passphrase prompt unanswerable. `base`'s virtio entries are inert on bare metal and are left alone
- [ ] 2.6 State `hardware.enableRedistributableFirmware` and `hardware.cpu.intel.updateMicrocode` explicitly rather than inheriting the facter bare-metal branch's `mkDefault` values, which are dead on every existing machine
- [ ] 2.7 Keep `base`'s `boot.zfs.forceImportRoot = true` and comment why it is load-bearing for a re-runnable install: an install re-run touches the pool from the installer, and importing without force after that lands the next boot in an emergency shell
- [ ] 2.8 Set no `networking.hostId`; clan-core's `mkDefault "8425e349"` matches the installer and nixos-anywhere by design
- [ ] 2.9 Do not enable `boot.plymouth`; it swaps the ask-password agent away from the verified console path
- [ ] 2.10 Add the networkd config for `wlp2s0`, the machine's only non-loopback interface (the cloud hosts' `matchConfig.Name = "en*"` does not match it)

## 3. Phase 3 — The disko layout

- [ ] 3.1 Create `modules/machines/nixos/pyrite/disko.nix` assigning into `flake.modules.nixos."machines/nixos/pyrite"` with no import statement, following the sibling-file auto-merge pattern every existing machine uses
- [ ] 3.2 Set `device = "/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1"` with a comment recording the 8 KiB `nvme0n2` namespace reachable at the `_2` suffix — this is a footgun a reader cannot recover from the path itself
- [ ] 3.3 Set `zpool.zroot.options.ashift = "12"` with a comment recording the disk's 4096-byte logical sector size, which no other machine in the fleet has and which disko does not detect
- [ ] 3.4 Declare the ESP with `type = "EF00"` and `size = "1G"`, vfat, mounted at `/boot`, with a comment recording that Apple's EFI discovers the ESP by partition type and that disko's default is `8300` — the failure surfaces only after macOS is wiped
- [ ] 3.5 Declare the ESP's sibling partition `zfs` with `size = "100%"` and `content = { type = "zfs"; pool = "zroot"; }`, matching the fleet's form at `modules/machines/nixos/electrum/disko.nix:22-28`. This is the partition that registers the vdev into `$disko_devices_dir/zfs_zroot`; without it the `zpool.zroot` block below has no device and pool creation fails after the wipe has already destroyed macOS
- [ ] 3.6 Declare the `zroot` datasets `root`, `root/nixos`, `root/home`, `root/nix`, matching the fleet's layout
- [ ] 3.7 Add `clan.core.vars.generators.zfs` with `files.key.neededFor = "partitioning"`, `runtimeInputs = [ pkgs.coreutils pkgs.xkcdpass ]`, and a script emitting a human-typeable passphrase after clan-infra `machines/build01/disko.nix:71-80` (`xkcdpass --numwords 6 --random-delimiters --case random`). Not hex — a person types this at a boot prompt. The script MUST write to `$out/key`, matching the `files.key` attribute the layout reads as `files.key.path`; build01 writes `$out/password` because its file attribute is `files.password`, and copying that literal yields a `clan vars generate` failure. Do NOT append build01's `| tr -d "\n"`; that trim exists for build01's consumer, `cryptsetup --key-file`, which does not trim, whereas ZFS trims one trailing newline for non-RAW keyformats on both the file and prompt paths
- [ ] 3.8 Set the `root` dataset's `encryption = "aes-256-gcm"`, `keyformat = "passphrase"`, and create-time `keylocation = "file://${config.clan.core.vars.generators.zfs.files.key.path}"`
- [ ] 3.9 Add `postCreateHook = ''zfs set keylocation="prompt" "zroot/root"'';` to the `root` dataset, with a comment recording that the create-time `/run/partitioning-secrets` path does not exist at boot, so the flip is what makes the machine bootable
- [ ] 3.10 Confirm `nix eval .#nixosConfigurations.pyrite.config.system.build.toplevel.drvPath` succeeds — the machine must evaluate before any hardware detection or install runs

## 4. Phase 4 — Registration

- [ ] 4.1 Add `pyrite` to `modules/clan/machines.nix`
- [ ] 4.2 Add the `pyrite` entry to `modules/clan/inventory/machines.nix` with `machineClass = "nixos"`, `deploy.targetHost = "root@pyrite.zt"`, and tags `nixos`, `laptop`, `peer`
- [ ] 4.3 Change `modules/clan/inventory/services/tor.nix` from `roles.server.tags."nixos"` to `roles.server.machines` naming cinnabar, electrum, galena, magnetite, and scheelite, so pyrite keeps sshd but publishes no onion service. The file's header comment must accurately describe the server role as a v3 onion service and disclaim Tor relaying — it read "Tor relay service for NixOS machines", which is false and is the likely seed of the refuted relay claim; confirm the corrected wording survives the selector edit and no longer says "for NixOS machines", which the explicit machine list falsifies
- [ ] 4.4 Add `roles.default.machines."pyrite" = { };` to `modules/clan/inventory/services/users/cameron.nix`
- [ ] 4.5 Add `"pyrite"` alphabetically to both hardcoded lists in `modules/checks/structure/flake-shape.nix` (after `magnetite`, before `rosegold` in the inventory list; after `magnetite`, before `scheelite` in the nixosConfigurations list)
- [ ] 4.6 Move `openspec/changes/pyrite-baremetal-nixos/pyrite-facter.json` to `machines/pyrite/facter.json` and git-track it — in the same commit as 2.1, 3.1, 4.1, 4.2, and 4.5, never before them, because creating `machines/pyrite/` alone injects an unconfigured inventory machine via clan-core's readDir scan
- [ ] 4.7 Confirm `nix flake check` passes, including the auto-emitted `nixos-pyrite` toplevel build and the unchanged tor evaluation for the five cloud hosts

## 5. Phase 5 — Secrets and ZeroTier vars

- [ ] 5.1 Run `clan vars generate pyrite` and commit the generated vars, sops machine key, ZeroTier identity/IP, and the zfs passphrase
- [ ] 5.2 Record the generated passphrase somewhere the operator can read it before the first boot — the install writes it, but a person types it, and it is unrecoverable if lost (one key per encryption root, no escrow)
- [ ] 5.3 Add the `&pyrite` age anchor to `.sops.yaml` and `*pyrite` to the `secrets/bridge/.*` creation rule
- [ ] 5.4 Run `just update-all-keys` to re-encrypt, and confirm the existing machines can still decrypt the bridge secret
- [ ] 5.5 Run `clan machines update cinnabar` so the controller's autoaccept unit admits the new peer

## 6. Phase 6 — The recorded install path

- [ ] 6.1 Write the install path as a recorded, re-runnable artifact (justfile recipe and/or a documented runbook), whose first step wipes the disk (`sgdisk --zap-all` then `wipefs -a` against the `_1` by-id path) and which then invokes `clan machines install pyrite --target-host root@<installer-ip> -i <key> --yes` with `--update-hardware-config` left at its default of `none`
- [ ] 6.2 Record why the wipe is a step rather than an assumption: disko's create phase skips `sgdisk --clear` when `blkid` succeeds, and pyrite has an Apple GPT today
- [ ] 6.3 Document that `--disk-encryption-keys` is appended automatically by clan-cli from the `neededFor = "partitioning"` generator and is not passed by hand
- [ ] 6.4 Document the ISO-boot prerequisites in the runbook: Option-key boot, sshd reachable, and that key authorization does not survive rebooting the installer
- [ ] 6.5 Document that `clan init`, `clan machines create`, and `clan templates apply disk` are all skipped, and why
- [ ] 6.6 Document the build-host behaviour: stibnite's `magnetite-builder` is preferred but mesh-only, so an off-mesh install falls back to the local Rosetta builder
- [ ] 6.7 Document the USB-keyboard recovery path, stating that a MacBookPro14,1 is USB-C only and that a USB-C keyboard or adapter must be on hand before the first boot rather than sourced after a failure

## 7. Phase 7 — Install and post-install

- [ ] 7.1 Boot the stock installer ISO, authorize a key, and run the recorded install path — this wipes macOS and is irreversible
- [ ] 7.2 Confirm the machine boots, the stage-1 passphrase prompt appears on the internal keyboard, and the root unlocks with the generated passphrase
- [ ] 7.3 Confirm `zfs get keylocation zroot/root` returns `prompt`, `zfs get keyformat zroot/root` returns `passphrase`, and `zpool get ashift zroot` returns `12`
- [ ] 7.4 Confirm `wlp2s0` associates and the machine joins the ZeroTier mesh
- [ ] 7.5 Confirm no tor daemon is running (`systemctl status tor` inactive), and that sshd host certificates are present
- [ ] 7.6 Add the `/pyrite.zt/<address>` record to `modules/machines/nixos/cinnabar/zt-dns.nix` and redeploy cinnabar
- [ ] 7.7 Add the `pyrite.zt` entries to `modules/system/ssh-known-hosts.nix` (public key resolves automatically from the flake for NixOS machines; only the address literal is hand-written) and `modules/home/core/ssh.nix`
- [ ] 7.8 Commit `inventory.json` if clan wrote `installedAt`
- [ ] 7.9 Re-run the install path a second time from a fresh ISO boot, including the wipe, and repeat 7.3 — a re-run against a surviving pool reuses it and skips the create path entirely, so it would go green without proving anything

## 8. Phase 8 — Open question to close before Phase 7

- [ ] 8.1 Acquire `nix-community/nixos-anywhere` per the `dependency-source-acquisition` ghq flow and establish its default `--disko-mode`, since `clan_lib/machines/install.py` passes none. The explicit wipe in 6.1 makes the install correct either way; this determines whether the wipe is belt-and-braces or load-bearing, and the answer belongs in design.md

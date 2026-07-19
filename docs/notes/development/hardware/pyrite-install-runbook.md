---
title: pyrite bare-metal install runbook
status: working-note
source-issue: CAM-32
---

# pyrite bare-metal install runbook

## Scope and provenance

This note records the re-runnable bare-metal install path for `pyrite`, an Apple MacBookPro14,1 enrolled as an encrypted-ZFS-root NixOS machine.
It is the recorded artifact Phase 6 of the pyrite-baremetal-nixos change (CAM-32) requires: the install is a recorded procedure in the repository, not something performed ad hoc.
The mechanics below were established by the change's design (see `openspec/changes/pyrite-baremetal-nixos/design.md`, decisions D8, D13, D18, D19) and its `bare-metal-install-path` spec, and they hold for nixos-anywhere 1.13.0, the version resolved through `clan-core.inputs.nixpkgs` at the current `flake.lock` (D13).
Do not run `nix flake update` before the install; an update can move nixos-anywhere's version with no visible entry in the lock, and every mechanic here was read from 1.13.0 (Phase 8, D13).

This document is the working-note home for the path.
Promoting it to published reference documentation under `docs/reference/` is a separate, deferred follow-on change and is out of scope for Phase 6.

Phase 7 of the change is where this path is executed and its re-runnability demonstrated; this note records the path and the reasons its steps are shaped as they are.

## Prerequisites before the first install

The fleet SSID must be broadcasting and the machine's clan vars must be generated and committed before the install runs.
The fleet network is the pre-existing household network `furtadosmith`, which the operator decided to use as the fleet network rather than standing up a distinct SSID (D14), so no router work is required and the network is already broadcasting.
Phase 5 covers the rest: run `clan vars generate pyrite` from the admin box and commit the generated vars — the sops machine key, the ZeroTier identity and IP, the ZFS root passphrase, and the wifi SSID and PSK — along with the sops recipient changes.
The wifi credentials are shared clan vars under `vars/shared/wifi.fleet/`, so the reinstalled machine associates with no operator typing credentials into it; if the vars are absent the NetworkManager profile interpolates empty strings and association fails silently at first boot, with nothing at eval time to catch it.

A USB-C keyboard or a USB-C-to-USB-A adapter must be physically on hand before the first boot.
See "USB-C keyboard is a first-boot prerequisite" below.

The install is driven from the admin box (stibnite).
The internal disk's namespace-explicit device path is `/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1` — the `_1` namespace, matching the disko layout's `device`.
Substitute `<installer-ip>` throughout with the address the booted installer reports for its wireless interface.

## Boot the installer and authorize a key

The install artifact is an upstream stock NixOS graphical installer ISO, `dd`-written to external media, carrying no key, credential, or machine closure (D18).
The image whose behaviour was measured on this unit is `nixos-graphical-26.05.5092.4382ed2b7a68-x86_64-linux.iso`, sha256 `61f409eeabb54d5289b91ce384cc33a7b1f82ac1cb22707407bf56f8bc4b9758`; the machine's only NIC is a BCM4350 driven by `brcmfmac`, and this image was observed loading that firmware unaided, which is why it is preferred over an unverified image at the one moment the disk is about to be destroyed.

Boot it with the Option key held at power-on; there is no firmware password.

Select `NixOS 26.05.5092.4382ed2b7a68 Installer GNOME (Linux LTS)` at the GRUB menu.
This is not cosmetic and it is the one menu choice that can destroy the disk.
The image presents four entries, read from `/iso/EFI/BOOT/grub.cfg` at `:68`, `:78`, `:88`, and `:98`: GNOME (Linux LTS), GNOME (Linux 7.1.3), Plasma (Linux LTS), and Plasma (Linux 7.1.3).
The two `7.1.3` entries are the `*_latest_kernel` specialisations, which import `nixos/modules/installer/cd-dvd/latest-kernel.nix`, whose `:4` sets `boot.supportedFilesystems.zfs = false` — so on those entries there is no `zfs` kernel module and no `zpool` on PATH.
Booting one of them and proceeding would run the `blkdiscard`, destroy macOS, and then fail at `zpool create` with nothing to fall back to.
The LTS entries carry `zfs.ko.xz`, `spl.ko.xz`, and `zpool` from `zfs-user-2.4.2` on kernel 6.18.38.
The GNOME LTS entry is GRUB's default — the config sets no `set default`, so entry 0 is selected, and `set timeout=10` means an unattended boot lands on it — but the menu is presented for ten seconds and a keypress can move off it, so the selection is confirmed rather than assumed.
The Plasma LTS entry would also pass the ZFS check; it is not chosen because it changes the desktop the recon was performed under for no gain.
Selecting LTS does not put the NIC at risk: the firmware closure is the identical store path across both specialisations and `brcmfmac` is present in the 6.18.38 `modules.dep`.

In the GNOME session the ISO presents, join the fleet SSID through the NetworkManager applet (or `nmtui`), and set a password for the `nixos` account with `passwd nixos` — the profile ships empty passwords and sshd refuses empty-password auth, so a password is required before ssh works.
sshd is already running on the stock installer; no `systemctl start sshd` is needed.

From the admin box, authorize a key against the running installer session:

```bash
ssh-copy-id nixos@<installer-ip>
```

Appending the public key directly is equivalent and is the form the recorded run used, from the machine's own GNOME session rather than from the admin box:

```bash
curl -sSL https://github.com/cameronraysmith.keys >> ~/.ssh/authorized_keys
```

Either writes `/home/nixos/.ssh/authorized_keys` and authorizes the key for the running installer session only.
It is not written to the installer media, so it must be repeated if the installer is rebooted — including the reboot onto the LTS entry, if the machine came up on a `7.1.3` entry first.

Then place the same key for root:

```bash
sudo mkdir -p /root/.ssh && sudo cp ~/.ssh/authorized_keys /root/.ssh/
```

This is a standing prerequisite rather than a contingency for a particular invocation.
It defuses the `root@` rewrite failure mode described below: `src/nixos-anywhere.sh:978-983` rewrites `sshConnection` to `root@${sshHost}` whenever the `kexec` phase is absent, and it does so before `uploadSshKey` at `:983`, which wraps `ssh-copy-id` in an `until ... sleep 3` loop with no abort — so against a root account that has an empty password sshd refuses (`installation-device.nix:48`) and no authorized_keys, the install hangs indefinitely on "Uploading install SSH keys" rather than failing.
Authorizing root up front means that path terminates even if a `--phases` flag is ever passed by accident, which is a cheap hedge against a hang that would otherwise land after the irreversible wipe.
Like the `nixos` authorization, it does not persist to the media and must be repeated after any installer reboot.

The install targets `nixos@<installer-ip>`, not `root@`.
The stock installer autologins the `nixos` user, places it in `wheel`, and gives it passwordless sudo, while both `nixos` and `root` ship empty passwords that sshd refuses for password auth.
`root@` would therefore need a key hand-installed into `/root/.ssh` first, whereas `nixos@` needs only the key authorized in the GNOME session already open on the machine, and nixos-anywhere escalates to root through that passwordless sudo.
The installed system's `deploy.targetHost = "root@pyrite.zt"` (registration task 4.2) is a different thing entirely — it deploys over ZeroTier to the installed machine's own host key — and it stays as it is.

The live ISO is itself the installer environment (`VARIANT_ID=installer`), so nixos-anywhere's kexec phase is a no-op: it returns immediately when the target is already an installer, and the running live-CD ssh access is exactly and sufficiently what the install consumes.
This forecloses any "physical install, then update over the network" misconception — there is no second step.
Keep nixos-anywhere's default phases; do not drop `kexec`, because dropping it rewrites the ssh connection to `root@` before the key is uploaded and breaks sudo escalation from the non-root installer session (D13).

## The recorded install path

The path's first step wipes the disk explicitly, at every offset rather than only at the partition table, and only then invokes `clan machines install`.

```bash
# 0. Realise nixos-anywhere on the admin box BEFORE the wipe. Substitutable
#    from cache.nixos.org: 22 paths, 78.9 MiB.
nix build --no-link /nix/store/2svzjf9qgwn6m2i69mqpjlb5n94dgm5g-nixos-anywhere-1.13.0
nix path-info /nix/store/2svzjf9qgwn6m2i69mqpjlb5n94dgm5g-nixos-anywhere-1.13.0

# 1. Wipe the target disk at every offset. THIS IS THE POINT OF NO RETURN:
#    macOS on the internal disk is destroyed here. This is the last step
#    whose success the operator can observe before the install commits.
blkdiscard /dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1

# 2. Install. --update-hardware-config is left at its default of `none`;
#    the committed machines/pyrite/facter.json is what the build consumes.
clan machines install pyrite \
  --target-host nixos@<installer-ip> \
  -i ~/.ssh/id_ed25519 \
  --yes
```

Step 0 is ordered ahead of the wipe rather than left to the install to resolve, because nixos-anywhere is fetched lazily and is first needed strictly after the point of no return.
clan resolves it at install time from a runtime-deps flake vendored inside the clan-cli derivation, not from the admin box's environment — `CLAN_PROVIDED_PACKAGES` is `age:git:nix` and does not include it — and the store path was not realised locally when this was checked.
A network failure at that moment would land after macOS is already destroyed, on a machine whose only NIC is wireless, which is a worse place to discover a missing 78.9 MiB than before the wipe.
`nix path-info` exiting 0 against the path is the confirmation; the operator realised it ahead of the install, so this is a recorded step of the path rather than an open action.

`blkdiscard` is on the installer's PATH (it ships in `util-linux`, folded into every NixOS system's `environment.systemPackages`); Phase 7 confirms this on the machine with a two-command check before relying on it, together with `blockdev --getss /dev/nvme0n1` to record the logical sector size the `ashift = "12"` decision assumes.

The wipe uses `blkdiscard`, not `sgdisk --zap-all` and not `wipefs -a` on the whole disk.
This follows the form clan-core's own encrypted-root guide prescribes at `docs/src/guides/disk-encryption.md:84-88`.
Zapping the GPT first is actively harmful on a re-run: disko's `disk-deactivate.jq` reaches `zpool destroy -f` and `zpool labelclear -f` only through partition-level children reported by `lsblk`, so a disk with no partition table presents no children, the partition-level wipe never runs, the whole-disk `wipefs` and `dd bs=440` touch disk offsets only while the ZFS labels live inside the second partition, disko then recreates its deterministic layout so that partition reappears at the same offset with its labels intact, and `zpool import -N -f "zroot"` reuses the old pool under the old passphrase — the tautological green the re-runnability criterion forbids, produced by the step meant to prevent it.
`blkdiscard` against the `_1` namespace path destroys labels at every offset and has no such hole.
If `blkdiscard` is ever unavailable, the fallback order is absolute: `zpool labelclear -f <device>-part2`, then `sgdisk --zap-all`, then `wipefs -a`, in that order, because the labelclear depends on the partition table the zap destroys.

### Why the wipe is a step, not an assumption

The wipe is not there because the run is create-only.
The default disko mode destroys before it creates: `clan_lib/machines/install.py` passes no `--disko-mode`, so nixos-anywhere's default selects disko's `diskoScript`, which composes `_legacyDestroy` then `_create` then `_mount` (D8).
So on the happy path the wipe is belt-and-braces, and it is retained anyway for three reasons.
`_legacyDestroy` runs without `set -e`, so a destroy that fails silently falls through to `_create`, where a surviving Apple GPT causes `sgdisk --clear` to be skipped, the subsequent `sgdisk --new` calls re-typecode Apple's partitions in place, `mkfs.vfat` is skipped on an ESP already reporting a type, and the machine boots Apple's 300 MiB ESP rather than the declared layout.
The explicit wipe is also the only step whose success the operator can independently observe before committing to an irreversible install.
And clan-core's own encrypted-root guide prescribes a manual `blkdiscard` before `clan machines install` for exactly this scenario, so upstream treats a pre-wipe as normal practice here rather than as belt-and-braces.

There is a fourth reason, and on the LTS boot entry it is stronger than the three above.
ZFS is live on that entry, so a `zroot` surviving on the disk is importable, and disko's `lib/types/zpool.nix:298` tries `zpool import -N -f "zroot"` before it considers creating anything.
If that import succeeds, `:299` logs "not creating zpool zroot as a pool with that name already exists" and pool creation is skipped entirely — the run goes green while reusing the old pool under the old passphrase, never re-applying `ashift`, `encryption`, or `keyformat`.
That is the tautological green the re-runnability criterion forbids, and it is the exact failure task 7.12's second install exists to detect.
The wipe is what forecloses it, which makes it load-bearing rather than belt-and-braces on any run where a pool could survive.
This matters most for 7.12 and not for the first install: the disk currently holds APFS and carries no ZFS pool, so there is nothing for the first run's import to find.

### What `--yes` does and does not do, and how the keys are supplied

`--disk-encryption-keys` is not passed by hand.
clan-cli appends it automatically from the `neededFor = "partitioning"` generator — the ZFS root-key generator declared in the disko layout — so the create-time keyfile reaches the installer without the operator naming it.

`--yes` confirms the install but does not auto-accept the vars-generator prompts.
The install path calls `run_generators` without `auto_accept_prompts`, whose default is `False`, so an install run with Phase 5 incomplete stops interactively on the admin box asking for the fleet SSID and PSK rather than failing.
Phase 5.2 front-loads vars generation precisely so this ordering is already right and the install does not stop to prompt.

## clan subcommands that are skipped, and why

`clan init`, `clan machines create`, and `clan templates apply disk` are all skipped, even though the upstream physical-machine guide directs them.
The first two write through `InventoryStore` against this repository's nix-declared inventory, which owns the machine binding and the inventory entry already (registration tasks 4.1 and 4.2).
`clan templates apply disk` writes `machines/pyrite/disko.nix`, which clan-core would auto-import alongside this repository's own `modules/machines/nixos/pyrite/disko.nix`, producing a duplicate disko module.
The machine is fully declared in nix, so none of the three has anything to add and each would fight the declaration.

## Build host behaviour

stibnite's remote linux builder `magnetite-builder` is preferred, but it is reachable only over the ZeroTier mesh.
An install driven from off the mesh therefore falls back to stibnite's local Rosetta builder, which builds the x86_64-linux closure locally under emulation.
Either way the closure is what nixos-anywhere pushes to the target; the build-host choice affects only where it is built.

## USB-C keyboard is a first-boot prerequisite

A MacBookPro14,1 has USB-C ports only and no USB-A port.
A USB-C keyboard, or a USB-C-to-USB-A adapter for a USB-A keyboard, must be physically present before the first boot after the install, not sourced after a failed boot.
The internal keyboard is SPI-attached and reaches the stage-1 passphrase prompt through the profile's force-loaded SPI modules; if that path does not bind on the first boot, an external USB keyboard answers the prompt through `usbhid`, `hid-generic`, and `hid-apple`, which reach the initrd through udev autoloading rather than force-loading.
The prompt waits with an unbounded timeout, so the recovery path is available — but only if the adapter or keyboard is already on hand, which on a USB-C-only machine cannot be improvised at the prompt.

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

## Which host runs which command

Every command block in this note opens with a `# host:` comment naming the machine that command runs on, and no block mixes hosts.
Three hosts appear: `stibnite` is the admin box, `pyrite (installer)` is pyrite running the booted installer ISO, and `pyrite (installed)` is pyrite running its own installed system.
The distinction is load-bearing rather than bookkeeping.
`blkdiscard` and every `/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_...` path below name pyrite's internal disk, and stibnite has a device namespace of its own in which the same commands run against stibnite's disk without complaint.
The install steps that bracket the wipe run on stibnite, so an operator working down the page without reading the host lines is one paste away from discarding the wrong machine's disk.
Read the `# host:` line before typing anything.

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
# host: stibnite
ssh-copy-id nixos@<installer-ip>
```

Appending the public key directly is equivalent and is the form the recorded run used, from the machine's own GNOME session rather than from the admin box:

```bash
# host: pyrite (installer), from the GNOME session on the machine itself
curl -sSL https://github.com/cameronraysmith.keys >> ~/.ssh/authorized_keys
```

Either writes `/home/nixos/.ssh/authorized_keys` and authorizes the key for the running installer session only.
It is not written to the installer media, so it must be repeated if the installer is rebooted — including the reboot onto the LTS entry, if the machine came up on a `7.1.3` entry first.

Then place the same key for root:

```bash
# host: pyrite (installer)
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
The three steps do not run on one host: step 0 and step 2 run on stibnite, and step 1 runs on pyrite's booted installer.
They are written as three blocks for that reason, and the middle one is the one that destroys a disk.

```bash
# host: stibnite
# 0. Realise nixos-anywhere BEFORE the wipe. Substitutable from
#    cache.nixos.org: 22 paths, 78.9 MiB.
nix build --no-link /nix/store/2svzjf9qgwn6m2i69mqpjlb5n94dgm5g-nixos-anywhere-1.13.0
nix path-info /nix/store/2svzjf9qgwn6m2i69mqpjlb5n94dgm5g-nixos-anywhere-1.13.0
```

```bash
# host: pyrite (installer)
# 1. Wipe the target disk at every offset. THIS IS THE POINT OF NO RETURN:
#    macOS on the internal disk is destroyed here. This is the last step
#    whose success the operator can observe before the install commits.
#    This by-id path names pyrite's internal NVMe. Run it in a shell on
#    the booted installer -- over ssh from stibnite or at pyrite's own
#    console -- never in a stibnite shell, where the same command finds
#    stibnite's own devices.
blkdiscard /dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1
```

```bash
# host: stibnite
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

`blkdiscard` from util-linux 2.42 prints `/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1: contains existing partition (gpt).` and then performs the discard.
This is a warning, not a refusal, and it reads exactly like one — the message names the obstacle and offers no result, so an operator reasonably reads it as the reason nothing happened.
It was observed on the install and the wipe was verified complete afterward: zero non-zero bytes in the first 64 MiB, no filesystem or pool signatures, no GPT, and the offset the old APFS container occupied reading zeros.
Do not go looking for a `--force` flag on the strength of this message.
There is nothing to force and re-running the command changes nothing.
The check that settles it is the post-wipe verification above, not the command's output; task 7.12's re-run will print the same line against whatever the previous install left behind.

The wipe uses `blkdiscard`, not `sgdisk --zap-all` and not `wipefs -a` on the whole disk.
This follows the form clan-core's own encrypted-root guide prescribes at `docs/src/guides/disk-encryption.md:84-88`.
Under D1's container the reason is restated rather than carried across from the ZFS-native layout, because what survives a partial wipe is no longer a pool.
Partition 2's `fstype` is now `crypto_LUKS` and not `zfs_member`, so disko's `disk-deactivate.jq` cannot reach its `zpool destroy -f` and `zpool labelclear -f` branch at `:7-9` for that partition at all — the branch is unreachable by type.
What runs instead is the bare `wipefs --all -f` partition arm at `:42-45`, which erases the primary LUKS2 signature while leaving the secondary header and the whole 16 MiB keyslot area intact, so the old passphrase and the old FIDO2 enrollment survive a wipe that reads as complete.
Zapping the GPT first is worse still: with no partition table there are no children for `lsblk` to report, so even that arm never runs, and the next install finds a valid header, skips `luksFormat` (`lib/types/luks.nix:202`), and skips the FIDO2 enrollment (`:276`) — the tautological green the re-runnability criterion forbids, produced by the step meant to prevent it.
`blkdiscard` against the `_1` namespace path destroys the header, the keyslot area, and every label at every offset, and has no such hole.

If `blkdiscard` is ever unavailable, the fallback order is absolute, and under D1's container it is no longer the ZFS one: `cryptsetup luksErase --batch-mode <device>-part2` first, then `dd if=/dev/zero of=<device>-part2 bs=1M count=32`, then `sgdisk --zap-all`, then `wipefs -a`.
`luksErase` goes first because it needs a header that still probes, and every step below it destroys the magic that probe depends on.
The 32 MiB overwrite follows because it covers both LUKS2 headers and the whole default 16 MiB keyslot area, rather than the primary signature alone.
The zap precedes the whole-disk `wipefs` for the reason the ZFS-era order recorded, that a partition-scoped step depends on the partition table the zap destroys.
`zpool labelclear -f <device>-part2` is dropped from the order rather than reordered: under a container p2 holds no ZFS labels to clear, because they live inside the container and are unreachable without opening it, so the command that used to open this list would now succeed at nothing and read as progress.

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

## Verifying what is inside an initrd, and why the obvious check silently lies

Checking for a module's presence inside a NixOS initrd by piping it to `cpio -t` and grepping fails silently.
NixOS initrds are multi-segment: an uncompressed early cpio carrying CPU microcode, followed by the compressed main archive.
A naive `zstdcat … | cpio -t` reads only the first segment and lists a single entry, so a grep for an absent module returns zero hits — indistinguishable from a genuine absence.
This produced two near-miss false conclusions during the initrd-networking diagnosis and will recur at task 7.12.

Two disciplines defeat it.
Always include a positive control: grep for a module that must be present, such as `applespi`, and treat a zero-hit control as proof the listing itself failed rather than as evidence about the module under test.
And prefer the authoritative artifact over the archive — the `initrd-nixos.conf` the initrd derivation actually consumes, located via `nix derivation show` on the `drvPath` from `config.system.build.initialRamdisk`, then tied to the deployed system by comparing that derivation's output path against `readlink -f /run/current-system/initrd`.

The same class of error also reached a store path that had not been realised locally, where `find` and `ls` returned empty and read as evidence of absence.
The general rule is that an empty result is evidence only once the query itself has been shown to work.

## Key lifecycle: header backup, YubiKey enrollment, and revocation

D1's move to a LUKS2 container places a discrete header at the head of the container partition, and that header holds every keyslot, so losing or corrupting it loses the pool no matter how many credentials are enrolled or how many tokens are in hand (D26).
Under the prior ZFS-native encryption there was no such header to lose, so this maintenance is new material rather than an inherited practice.
The container is partition 2 of the internal disk, so every command below targets the by-id `-part2` path the install's other `cryptsetup` steps use:

```bash
# host: pyrite (installed)
part2=/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1-part2
```

Every block in this section runs on pyrite, on the installed system, against that path — with the single exception of the Bitwarden upload, which happens at stibnite and is called out where it appears.

### Capturing and storing the header backup

The backup is roughly 16 MiB — the LUKS2 header and its keyslot area — and it is key material, because it contains the keyslots themselves.
Capture it to RAM-backed tmpfs, encrypt the copy that leaves the machine to the `&admin-user` recovery recipient, then remove the plaintext:

```bash
# host: pyrite (installed)
uuid=$(cryptsetup luksUUID "$part2")   # provenance: the container UUID
today=$(date +%F)                      # provenance: the capture date, YYYY-MM-DD

# cryptsetup opens the backup target with O_CREAT|O_EXCL and refuses a path that
# already exists, so the target must not pre-exist -- which rules out /dev/stdout.
# /dev/shm is tmpfs, so the plaintext header never touches persistent storage.
tmp=/dev/shm/pyrite-luks-header.$$.img
cryptsetup luksHeaderBackup "$part2" --header-backup-file "$tmp"

age -r age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8 \
  -o "$HOME/pyrite-luks-header-$today-$uuid.age" "$tmp"

shred -u "$tmp"
```

The recipient is the `&admin-user` recovery key, the same human key that decrypts the machine's vars and that task 5.3 records as the sole human recipient of the passphrase var.
A header backup is worthless unless it can be decrypted, and the `&admin-user` private half is the one demonstrably in our custody, while the offline `&admin` key's private half is not reliably held.
Encrypting to `&admin-user` puts the header backup and the passphrase var under one key, which is acceptable here: an `&admin-user` compromise already yields the passphrase directly, the passphrase is itself a full unlock credential, so the header backup adds no incremental exposure.
On tmpfs the RAM backing is the real protection and `shred` is belt-and-suspenders — a plain `rm` would remove it as well — but the plaintext is gone before the operator moves on either way.
The capture date and container UUID travel in the filename so a stale backup is identifiable without decrypting it, and the UUID ties the backup to one `luksFormat`: a re-install mints a new UUID (task 7.6 records it), so a backup whose UUID no longer matches the live container restores nothing.

The `.age` file is ciphertext and can sit in the operator's home directory until it is uploaded.
Upload it to the machine's Bitwarden entry — the same `pyrite/zfs-root` entry that holds the passphrase — as a file attachment, so that entry holds only ciphertext; the header is never committed to this repository and never placed in sops.
Bitwarden file attachments require a paid plan and the ~16 MiB backup is well within the per-attachment size limit, so confirm the account allows attachments before relying on this path.
Delete the local `.age` once the upload succeeds — it is only ciphertext, so this is tidiness rather than a security step.

### Restoring the header

Restoration reverses the capture and keeps the same tmpfs hygiene, since the decrypted header is again key material.
It needs the `&admin-user` identity, the same key that decrypts the machine's vars, and a tmpfs mount, which `/dev/shm` and `/run` both provide on any NixOS or rescue environment:

```bash
# host: pyrite (installed), or whatever rescue environment holds the container
age -d -i <admin-user-identity> pyrite-luks-header-<YYYY-MM-DD>-<luksUUID>.age \
  > /dev/shm/pyrite-luks-header.img
cryptsetup luksHeaderRestore "$part2" --header-backup-file /dev/shm/pyrite-luks-header.img
shred -u /dev/shm/pyrite-luks-header.img
```

`luksHeaderRestore` reads the backup file rather than creating it, so it carries none of the `O_EXCL` constraint the capture does, and it prompts before it overwrites the live header.

### The slot inventory and its provenance

Both YubiKey 5C Nano tokens report the same AAGUID and are physically identical, so once both are enrolled `systemd-cryptenroll "$part2"` lists two `fido2` slots with nothing in the header telling them apart (D25).
The slot index is therefore the only discriminator, and it cannot be reconstructed after the fact.
Record in the same `pyrite/zfs-root` Bitwarden entry the mapping from slot index to credential — YubiKey-A's serial, YubiKey-B's serial, and the passphrase slot — reading the actual indices back from `systemd-cryptenroll "$part2"` at the moment each is enrolled.
Record alongside it the capture date and container UUID of the header backup currently attached, so the entry names both which credential occupies which slot and which `luksFormat` the stored backup belongs to.

### Re-taking after enrollment changes, and revocation

A header backup freezes the keyslot set exactly as it stood when taken, so restoring one that predates a revocation reinstates the revoked slot verbatim and decrypts the disk again (D26).
The backup is thus itself an enrolled credential, and the retention rule is not "keep them all": after any change to the enrolled set, take a fresh backup, upload it, and delete the superseded Bitwarden attachment, because a stale attachment is an un-revoked credential sitting in storage.
The triggers are every enrollment change without exception — the second-YubiKey enrollment in task 7.12a, any revocation, and any future token added — and each re-runs the capture above and updates the slot inventory.

Revocation removes one slot from the live header:

```bash
# host: pyrite (installed)
systemd-cryptenroll "$part2"                 # list the occupied slots and their types
systemd-cryptenroll "$part2" --wipe-slot=<n> # remove slot n, the lost credential
```

Replacing a lost token means wiping its slot, seating the replacement alone, re-enrolling with `systemd-cryptenroll "$part2" --fido2-device=auto`, then re-taking the header backup and destroying the previous one.
The passphrase slot is not wiped as part of this: it keeps the sequence survivable if the replacement enrollment fails partway, and it is what makes the procedure performable at all while no valid token is enrolled.

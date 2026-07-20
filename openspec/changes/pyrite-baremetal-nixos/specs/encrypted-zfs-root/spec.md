## ADDED Requirements

### Requirement: The root is a ZFS pool created with an explicit ashift matching the disk's 4096-byte sectors

The disko layout SHALL declare a `zroot` pool with `options.ashift = "12"` and the fleet's dataset layout (`root`, `root/nixos` at `/`, `root/home` at `/home`, `root/nix` at `/nix`).
`ashift` MUST be set explicitly rather than left to ZFS autodetection.
`rootFsOptions` SHALL additionally carry `xattr = "sa"` and `acltype = "posixacl"`, and `normalization` MUST NOT be set.

#### Scenario: ashift is the caller's responsibility

- **WHEN** the pool is created on a disk reporting 4096-byte logical and physical sector size
- **THEN** `options.ashift = "12"` is set in the layout, because 2^12 = 4096, disko performs no sector-size detection and passes zpool options through verbatim to `zpool create -o`, and ZFS's `ashift=0` autodetect was not verified to arrive at 12 on this device
- **AND** the value carries a comment recording the sector-size coupling, because a reader cannot recover the relationship between `12` and this disk from the literal

#### Scenario: ZFS root matches the fleet, encryption does not follow any in-repo precedent

- **WHEN** the filesystem choice is justified
- **THEN** the justification is that all five existing NixOS machines root on ZFS with a `zroot` pool and none has a non-ZFS root
- **AND** the justification is NOT that `base` sets `boot.zfs.forceImportRoot = true`, which is an unconditional defensive setting inert on a machine with no pool and which proves nothing about ZFS usage
- **AND** the encryption layer is acknowledged as having no in-repo precedent, since no machine in this repository encrypts a disk by any mechanism, and the FIDO2 enrollment has no precedent in clan-infra either — `machines/build01/disko.nix:90-97` is LUKS opened by a passphrase with no token

#### Scenario: the properties whose window closes at creation are decided in this window

- **WHEN** the pool and its root dataset are created by the single destructive install, which is the only scheduled occasion to influence them
- **THEN** `rootFsOptions` carries `xattr = "sa"`, storing extended attributes inline in the dnode rather than in a hidden per-file directory, and `acltype = "posixacl"`, because journald applies POSIX ACLs to the per-user journals it creates under `/var/log/journal` and a pool without `acltype` set drops them
- **AND** these two are decided here rather than deferred, because `zfs set` applies each only to attributes and ACLs written after the change and leaves everything already on disk in the old form, so a retrofit on a populated root is partial in a way the reported property value does not reveal
- **AND** `normalization` is NOT set, and the decline is recorded: it is settable only at creation, and any value other than `none` implicitly sets `utf8only=on`, which makes the filesystem reject filenames that are not valid UTF-8 — a failure mode with no in-repo precedent to justify accepting
- **AND** `ashift` is distinguished from all of the above as the one property with no post-create remedy at all, partial or otherwise

---

### Requirement: The ESP is typed EF00 and sized 1G

The disko layout SHALL declare an ESP partition with `type = "EF00"` and `size = "1G"`, carrying a vfat filesystem mounted at `/boot`, with systemd-boot as the loader.
The partition type MUST be stated explicitly.

#### Scenario: the ESP type is stated because disko's default would brick the boot

- **WHEN** disko's `lib/types/gpt.nix:48-52` defaults a partition's `type` to `"8300"` (Linux filesystem) for any content type other than swap
- **THEN** the layout sets `type = "EF00"` explicitly, because Apple's EFI firmware discovers the ESP by partition type and an `8300`-typed partition is not discoverable as one
- **AND** the field carries a comment recording that the boot depends on it, because the failure surfaces only after macOS has been irreversibly wiped and there is no fallback OS from which to correct it
- **AND** this matches the fleet's three UEFI machines, `modules/machines/nixos/{electrum,galena,scheelite}/disko.nix:15`, each of which sets `type = "EF00"`; cinnabar and magnetite set `EF02` because they are BIOS-boot

#### Scenario: the ESP size is stated because disko's default is zero

- **WHEN** disko's `lib/types/gpt.nix:158-166` defaults `size` to `"0"`
- **THEN** the layout sets `size = "1G"`, matching every existing machine in the fleet

---

### Requirement: A sibling partition carries the ZFS content that becomes the pool's vdev

The disko layout SHALL declare, alongside the ESP, a second GPT partition with `size = "100%"` whose content is `{ type = "luks"; }` and whose nested `content` is `{ type = "zfs"; pool = "zroot"; }`, so the pool's vdev is the `/dev/mapper` device rather than the partition.
The fleet's unencrypted form at `modules/machines/nixos/electrum/disko.nix:22-28` names the zfs content directly on the partition; pyrite interposes the LUKS layer and is otherwise identical.
The pool declared by the `zpool.zroot` block MUST have a device contributing a vdev to it.

#### Scenario: the pool has a device to be created on

- **WHEN** the layout declares a `zpool.zroot` block with its options and datasets
- **THEN** a sibling partition of the ESP carries a LUKS content whose own `content` declares `{ type = "zfs"; pool = "zroot"; }`, because that content type's `_create` at disko `lib/types/zfs.nix:39-43` is the only thing that appends a device to `$disko_devices_dir/zfs_zroot`, which `lib/types/zpool.nix:291` reads back with `readarray` to build the `zpool create` vdev list
- **AND** the device it appends is `/dev/mapper/<name>`, because the LUKS type fixes its nested content's `device` to exactly that at disko `lib/types/luks.nix:184-187` and splices that content's `_create` after the container has been formatted and opened (`lib/types/luks.nix:303`)
- **AND** the partition takes `size = "100%"`, consuming the disk remaining after the 1G ESP

#### Scenario: an ESP-only layout fails after the disk is already destroyed

- **WHEN** a layout declares the ESP and the `zpool.zroot` block but no partition carrying zfs content
- **THEN** nothing appends to `$disko_devices_dir/zfs_zroot`, and disko's guard at `lib/types/zpool.nix:292-295` exits 1 with "no devices found for zpool zroot. Did you misspell the pool name?"
- **AND** the failure surfaces during the install's create phase, after the recorded wipe has already destroyed macOS and with no fallback OS to correct it from, which is why the partition is declared and evaluated before the install rather than discovered at it

---

### Requirement: The pool device is named by a namespace-explicit by-id path

The disko `device` SHALL be `/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1`, and the module SHALL set `boot.zfs.devNodes = "/dev/disk/by-id"` rather than the `by-path` every existing machine uses.
The device MUST NOT be named by any prefix or glob over the by-id family.

#### Scenario: the 8 KiB second namespace is never a write target

- **WHEN** the controller exposes two namespaces, `nvme0n1` (the 465.9 GiB disk) and `nvme0n2` (8 KiB), whose by-id names differ only by a `_1`/`_2` suffix and share a common unsuffixed prefix
- **THEN** the layout names `_1` explicitly, because the unsuffixed name is a bare prefix of both suffixed names and any prefix or glob match over the family can reach `_2`
- **AND** the device carries a comment recording the `_2` namespace, because the hazard is not recoverable from the path literal
- **AND** ZFS scanning `_2` during import is harmless, since the hazard is a write and only the disko `device` writes

#### Scenario: by-path is not inherited from the cloud machines

- **WHEN** every existing machine sets `boot.zfs.devNodes = "/dev/disk/by-path"` with a comment reading "more stable for cloud VMs"
- **THEN** pyrite sets `by-id` instead, because that reasoning is scoped to cloud VMs and this machine has a stable by-id path

---

### Requirement: The pool sits inside a LUKS2 container unlocked by a FIDO2 token, with a clan-vars passphrase in a second keyslot

The disko layout SHALL wrap the 100% partition in `content = { type = "luks"; }` carrying `enrollFido2 = true`, and the `zroot` pool SHALL take the resulting `/dev/mapper` device as its vdev.
The container SHALL hold at least two keyslots: one enrolled to a FIDO2 token by `systemd-cryptenroll`, and one holding a human-typeable passphrase supplied as a clan vars partitioning secret through disko's `additionalKeyFiles`.
`settings.allowDiscards` and `settings.bypassWorkqueues` SHALL both be `true`, and `enrollRecovery` SHALL be `false`.
ZFS native encryption MUST NOT be used: no dataset carries `encryption`, `keyformat`, or `keylocation`, and no `postCreateHook` flips a key location.

#### Scenario: the create-time key arrives through clan's partitioning-secrets channel

- **WHEN** `clan.core.vars.generators.zfs` declares `files.key.neededFor = "partitioning"`
- **THEN** clan-core resolves that file's `path` to `/run/partitioning-secrets/zfs/key`, per `nixosModules/clanCore/vars/secret/sops/default.nix:30-32`
- **AND** `clan machines install` places the file there automatically, because `pkgs/clan-cli/clan_lib/machines/install.py:171-182` rglob-walks the generated partitioning-secrets tree and appends one `--disk-encryption-keys <remote path> <local path>` pair per file to the `nixos-anywhere` invocation
- **AND** the LUKS content names that same generator path in both `passwordFile` and `additionalKeyFiles`, following clan-infra `machines/build01/disko.nix:93`'s `passwordFile` form, so the file that opens the container during the install is also the file added as a persistent keyslot

#### Scenario: the generated key is a human-typeable passphrase, not hex

- **WHEN** the vars generator script produces the key
- **THEN** it emits a human-typeable passphrase with `xkcdpass --numwords 6 --delimiter - --case random`, adapting clan-infra `machines/build01/disko.nix:71-80`'s `xkcdpass --numwords 6 --random-delimiters --case random` (the same generator shape build01 feeds to its own LUKS `passwordFile` at `machines/build01/disko.nix:93`) by fixing the delimiter to a layout-stable hyphen per D27
- **AND** it MUST NOT emit hex via `dd if=/dev/urandom | xxd` as clan-infra `web01` does, because `web01` is a server unlocked over the network by another machine while pyrite's passphrase is typed by a person standing at the machine whenever the token is absent, forgotten, or broken
- **AND** this passphrase is the recovery credential of record, which is why disko's `enrollRecovery` is declined rather than used in its place: the passphrase already exists, is already replicated in sops, and is already transcribable, whereas disko's recovery key is shown once as a QR code on the console behind a `read -p` (`lib/types/luks.nix:264-274`) that would block a non-interactive install outright

#### Scenario: the passphrase keyslot survives the slot-zero wipe because of the order disko runs in

- **WHEN** `enrollFido2 = true` sets disko's `autogeneratedPassword` at `lib/types/luks.nix:12`, so `_create` mints a throwaway key with `openssl rand -hex 32` and exports `SLOT_ZERO_TO_DELETE=true` (`lib/types/luks.nix:232-243`), formats the container with it (`:244`), and opens it (`:246-247`)
- **THEN** the clan-vars passphrase named in `additionalKeyFiles` is added as a further keyslot at `lib/types/luks.nix:256-262`, by a `cryptsetup luksAddKey` that unlocks with the throwaway key and adds the passphrase file
- **AND** only afterwards does `lib/types/luks.nix:275-302` run `systemd-cryptenroll --fido2-device=auto --wipe-slot=0`, so the wipe removes the throwaway slot and leaves the FIDO2 slot and the passphrase slot standing
- **AND** the ordering is load-bearing rather than incidental: `additionalKeyFiles` omitted, or an equivalent enrollment performed after the wipe, yields a container whose only credential is the token, on a machine with no fallback OS from which to add another

#### Scenario: the generator strips the trailing newline, because disko's two key paths disagree about it

- **WHEN** the same generator file is named in both `passwordFile` and `additionalKeyFiles`
- **THEN** the generator script appends `| tr -d "\n"`, matching clan-infra `machines/build01/disko.nix:78`
- **AND** the reason is that disko reads the file two different ways: `passwordFile` is dereferenced through a command substitution at `lib/types/luks.nix:23`, `<(set +x; echo -n "$(cat ...)"; set -x)`, which drops trailing newlines, while `additionalKeyFiles` is handed to `cryptsetup luksAddKey` as a bare path at `lib/types/luks.nix:259`, and cryptsetup reads a regular key file verbatim including its final byte
- **AND** without the trim the enrolled keyslot holds the passphrase followed by a newline while every path that presents it — the `passwordFile` open, and a person typing at the boot prompt — presents it without one, so the passphrase slot exists and unlocks nothing
- **AND** this reverses the guidance the ZFS-native design recorded, which forbade the trim on the ground that ZFS strips one trailing newline itself for non-RAW keyformats; that reasoning was specific to ZFS keyformat handling and does not survive the move to LUKS

#### Scenario: the layout re-formats the container rather than reusing it on any later reinstall

- **WHEN** the install path is run against a disk that already holds a LUKS container
- **THEN** disko's guard at `lib/types/luks.nix:202`, `if ! blkid "<device>" >/dev/null || ! cryptsetup isLuks "<device>"`, finds no LUKS header on a disk the recorded `blkdiscard` has discarded, and re-runs the whole format-add-enroll sequence
- **AND** against a container that survived the wipe it would skip the format entirely, and the FIDO2 guard at `lib/types/luks.nix:276` — `systemd-cryptenroll <device> | grep -qw fido2` — would skip the enrollment too, which is the same tautological green the create-path requirement in `bare-metal-install-path` forbids for the pool
- **AND** this is recorded as a property of the layout for any future reinstall rather than as an acceptance criterion of this change, because this machine's disk carries no LUKS header before its single install and there is therefore no earlier container UUID to compare against

#### Scenario: the boot-time unlock reaches the console and needs no new stage-1 options

- **WHEN** the machine boots with `boot.initrd.systemd.enable = true`, which `base` already sets at `modules/system/initrd-networking.nix:7` and which disko would set anyway for a FIDO2 container (`lib/types/luks.nix:354`)
- **THEN** disko's `_config` emits a `boot.initrd.luks.devices.<name>` entry carrying `crypttabExtraOpts = [ "fido2-device=auto" ]` (`lib/types/luks.nix:348`), nixpkgs renders it into the stage-1 crypttab at `nixos/modules/system/boot/luksroot.nix:590-598` and installs that file as `/etc/crypttab` at `:1221`, and `systemd-cryptsetup` unlocks the container before ZFS is asked to import anything
- **AND** no stage-1 option is added for this: `boot.initrd.systemd.fido2.enable` defaults to `config.boot.initrd.systemd.package.withFido2` at `nixos/modules/system/boot/systemd/fido2.nix:12-15`, and its config block at `:19-30` already places `60-fido-id.rules`, `fido_id`, `libcryptsetup-token-systemd-fido2.so`, and `libfido2.so.1` inside the initrd — all four confirmed present by extracting the deployed initrd, whose `/init` symlinks to systemd
- **AND** `settings.allowDiscards` and `settings.bypassWorkqueues` reach the running system rather than only the install, because `luksroot.nix:590-598` folds them into the crypttab options as `discard`, `no-read-workqueue`, and `no-write-workqueue`
- **AND** both tokens carry a FIDO2 client PIN, so `systemd-cryptenroll`'s default `--fido2-with-client-pin=yes` applies and the unlock is a typed PIN followed by a physical touch, which keeps the SPI keyboard requirement recorded in `apple-laptop-hardware-support` load-bearing rather than retiring it
- **AND** the prompt is rendered by `systemd-ask-password-console.service`, which is started by `systemd-ask-password-console.path`'s level-triggered `DirectoryNotEmpty=/run/systemd/ask-password` rather than by the unit's `After=` on it — that `After=` edge is vacuous because the service is not in the boot transaction, and nothing in this design depends on it
- **AND** `i915` in initrd provides the framebuffer console that displays it

#### Scenario: hostId is inherited rather than pinned

- **WHEN** ZFS requires `networking.hostId`
- **THEN** pyrite sets nothing and inherits clan-core's `nixosModules/clanCore/zfs.nix:10` `lib.mkDefault "8425e349"`, whose stated purpose is to match the install ISO and nixos-anywhere so that the installer that creates the pool and the system that imports it present the same hostid
- **AND** a machine-specific hostid is NOT pinned, because it would manufacture the very mismatch that default exists to prevent

#### Scenario: forceImportRoot is kept as a deliberate decision

- **WHEN** `base` supplies `boot.zfs.forceImportRoot = true`
- **THEN** pyrite keeps it, because the install path touches the pool from the installer environment and, per Mic92's `nixosModules/zfs.nix:16-18`, importing without force after such a touch lands the next boot in an emergency shell
- **AND** its known cost, that the nixpkgs assertion `unsafeAllowHibernation -> !forceImportRoot` forecloses ZFS hibernation at evaluation time, is accepted because hibernation is a non-goal of this change

---

### Requirement: The costs and the gains of the LUKS layer are both recorded rather than discovered later

The design SHALL record what moving from ZFS native encryption to a LUKS2 container costs and what it gains, because both are structural and neither is remediable by configuration.

#### Scenario: there are several keyslots and a defined recovery path

- **WHEN** the container is created and enrolled
- **THEN** it is recorded that LUKS2 holds several independent keyslots, and that this design occupies at least two of them — a FIDO2 token and the clan-vars passphrase — so losing one credential does not lose the disk
- **AND** it is recorded that the passphrase is a committed, sops-encrypted clan var, which makes it the recovery credential and closes the escrow gap the ZFS-native design accepted
- **AND** it is recorded that the second YubiKey, and any later TPM enrollment on a machine that had one, are `systemd-cryptenroll` operations against the existing container requiring no re-install, which is exactly the property ZFS native encryption structurally could not offer, since it permits one key per encryption root and `zfs change-key` replaces rather than adds

#### Scenario: pool and dataset metadata are encrypted

- **WHEN** an attacker obtains the disk
- **THEN** it is recorded that the container encrypts everything above it, so pool layout, dataset names, and snapshot names are unreadable, and only the LUKS header and the 1G ESP remain legible
- **AND** it is recorded that this inverts the cost the ZFS-native design accepted, under which those names were readable and only dataset contents were protected

#### Scenario: dm-crypt's AES-XTS is unauthenticated, where ZFS native aes-256-gcm was not

- **WHEN** a byte on the disk is altered, by a fault or by an adversary with write access
- **THEN** it is recorded that LUKS2's default `aes-xts-plain64` provides confidentiality without integrity, so the block layer decrypts altered ciphertext into altered plaintext and raises nothing on its own
- **AND** it is recorded that ZFS's `aes-256-gcm` was authenticated, and that this design gives that property up deliberately rather than by oversight
- **AND** it is recorded that ZFS checksums above the container still detect the resulting corruption, so the data is not silently served, while nothing distinguishes a deliberate modification from bit rot — the detection survives the change, the attribution does not

---

### Requirement: The LUKS header and the keyslot inventory are maintained artifacts, not install-time byproducts

A LUKS2 header backup SHALL be taken once the container's keyslots reach their intended state, stored off the machine, and handled as key material.
The slot index each credential occupies SHALL be recorded at the time it is enrolled.
Revoking a credential SHALL wipe its slot and re-take the header backup.

#### Scenario: a lost header loses the pool regardless of which credentials are held

- **WHEN** the LUKS2 header at the head of the partition is corrupted or overwritten
- **THEN** it is recorded that no enrolled credential recovers the pool, because every keyslot lives inside that header, and that this is a failure mode the ZFS-native design did not have — there was no header to lose
- **AND** the header is backed up with `cryptsetup luksHeaderBackup` once enrollment settles, and the backup is stored off the machine and handled as key material, because it contains the keyslots themselves

#### Scenario: a stale header backup silently restores a revoked credential

- **WHEN** a header backup is taken, a credential is later revoked, and the old backup is then restored
- **THEN** it is recorded that the restore reinstates the revoked keyslot verbatim, because a header backup freezes the keyslot set as of the moment it was taken and carries no notion of a later revocation
- **AND** the procedure is therefore to re-take the backup after every enrollment change and destroy the superseded copy, rather than to accumulate backups

#### Scenario: the two tokens are indistinguishable after enrollment unless the slot index is written down

- **WHEN** both YubiKey 5C Nano tokens are enrolled and `systemd-cryptenroll <device>` lists the resulting slots
- **THEN** the slot index each token occupies is recorded as it is enrolled, because the two report the same AAGUID and the listing offers nothing else that tells them apart
- **AND** without that record, revoking one lost token means revoking both and re-enrolling the survivor, or guessing

#### Scenario: revocation is a slot wipe followed by a fresh header backup

- **WHEN** a token is lost or a credential is to be retired
- **THEN** the procedure is to list slots with `systemd-cryptenroll <device>`, wipe the identified one with `systemd-cryptenroll --wipe-slot=<n> <device>`, enroll the replacement with only that token seated, and re-take the header backup
- **AND** the passphrase slot is not wiped as part of this, because it is the credential that makes the sequence survivable if the replacement enrollment fails partway

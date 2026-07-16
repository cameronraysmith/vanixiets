## ADDED Requirements

### Requirement: The root is a ZFS pool created with an explicit ashift matching the disk's 4096-byte sectors

The disko layout SHALL declare a `zroot` pool with `options.ashift = "12"` and the fleet's dataset layout (`root`, `root/nixos` at `/`, `root/home` at `/home`, `root/nix` at `/nix`).
`ashift` MUST be set explicitly rather than left to ZFS autodetection.

#### Scenario: ashift is the caller's responsibility

- **WHEN** the pool is created on a disk reporting 4096-byte logical and physical sector size
- **THEN** `options.ashift = "12"` is set in the layout, because 2^12 = 4096, disko performs no sector-size detection and passes zpool options through verbatim to `zpool create -o`, and ZFS's `ashift=0` autodetect was not verified to arrive at 12 on this device
- **AND** the value carries a comment recording the sector-size coupling, because a reader cannot recover the relationship between `12` and this disk from the literal

#### Scenario: ZFS root matches the fleet, encryption does not follow any in-repo precedent

- **WHEN** the filesystem choice is justified
- **THEN** the justification is that all five existing NixOS machines root on ZFS with a `zroot` pool and none has a non-ZFS root
- **AND** the justification is NOT that `base` sets `boot.zfs.forceImportRoot = true`, which is an unconditional defensive setting inert on a machine with no pool and which proves nothing about ZFS usage
- **AND** the encryption layer is acknowledged as having no in-repo precedent, since no machine in this repository encrypts a disk by any mechanism

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

The disko layout SHALL declare, alongside the ESP, a second GPT partition with `size = "100%"` whose content is `{ type = "zfs"; pool = "zroot"; }`, matching the fleet's form at `modules/machines/nixos/electrum/disko.nix:22-28`.
The pool declared by the `zpool.zroot` block MUST have a partition contributing a vdev to it.

#### Scenario: the pool has a device to be created on

- **WHEN** the layout declares a `zpool.zroot` block with its options and datasets
- **THEN** a sibling partition of the ESP declares `content = { type = "zfs"; pool = "zroot"; }`, because that content type's `_create` at disko `lib/types/zfs.nix:39-43` is the only thing that appends the partition's device to `$disko_devices_dir/zfs_zroot`, which `lib/types/zpool.nix:291` reads back with `readarray` to build the `zpool create` vdev list
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

### Requirement: The root dataset uses ZFS native encryption, created from a keyfile and flipped to a boot-time prompt

The `root` dataset SHALL carry `encryption = "aes-256-gcm"` and `keyformat = "passphrase"`.
It SHALL be created with `keylocation` pointing at a clan vars partitioning secret, and a `postCreateHook` SHALL run `zfs set keylocation="prompt" zroot/root` so that every subsequent boot prompts locally.
LUKS MUST NOT be used at any layer.
`zfs change-key` MUST NOT be used.

#### Scenario: the create-time key arrives through clan's partitioning-secrets channel

- **WHEN** `clan.core.vars.generators.zfs` declares `files.key.neededFor = "partitioning"`
- **THEN** clan-core resolves that file's `path` to `/run/partitioning-secrets/zfs/key`, per `nixosModules/clanCore/vars/secret/sops/default.nix:30-32`
- **AND** `clan machines install` places the file there automatically, because `pkgs/clan-cli/clan_lib/machines/install.py:171-182` rglob-walks the generated partitioning-secrets tree and appends one `--disk-encryption-keys <remote path> <local path>` pair per file to the `nixos-anywhere` invocation
- **AND** the dataset's create-time `keylocation` is `file://` that generator path, following clan-infra `machines/web01/disko.nix:96`

#### Scenario: the generated key is a human-typeable passphrase, not hex

- **WHEN** the vars generator script produces the key
- **THEN** it emits a human-typeable passphrase in the spirit of clan-infra `machines/build01/disko.nix:71-80`'s `xkcdpass --numwords 6 --random-delimiters --case random`
- **AND** it MUST NOT emit hex via `dd if=/dev/urandom | xxd` as clan-infra `web01` does, because `web01` is a server unlocked over the network by another machine while pyrite's key is typed by a person at a boot prompt

#### Scenario: the keylocation flip is mechanically supported by disko

- **WHEN** the dataset is created with `keylocation` set to a `file://` path
- **THEN** a `postCreateHook` running `zfs set keylocation="prompt" zroot/root` flips it, because `keylocation` is deliberately absent from disko's `onetimeProperties` list at `lib/types/zfs_fs.nix:80-91` while `encryption` and `keyformat` are present and could not be changed after creation
- **AND** `postCreateHook` is a declared option (`lib/default.nix:476`) spliced after the create body (`lib/default.nix:507-511`), and the flip is disko's own documented idiom at `example/zfs.nix:104-113`
- **AND** the key material is unchanged by the flip; only the location ZFS reads it from changes, making this the ZFS-native analog of LUKS's `passwordFile`

#### Scenario: the flip is required for the machine to boot at all

- **WHEN** the `/run/partitioning-secrets/zfs/key` path exists only during the install, because nixos-anywhere places it there and nothing recreates it at boot
- **THEN** the flip to `prompt` is load-bearing rather than cosmetic, because a dataset left at the `file://` value would boot unable to find its key
- **AND** clan-infra `web01` does not flip precisely because a separate mechanism supplies its key at boot — `machines/web01/disko.nix:63-67` runs an initrd unit spinning until the file appears — which is a server posture pyrite does not share

#### Scenario: a re-run of the install path leaves keylocation at prompt

- **WHEN** the install path runs a second time against a pool whose `root` dataset already exists
- **THEN** disko's else branch at `lib/types/zfs_fs.nix:109-114` runs `zfs set -u <updateOptions>`, which still contains `keylocation=file://...` because `updateOptions` is the create options minus the one-time properties
- **AND** the `postCreateHook` runs afterward regardless of which branch was taken and sets `keylocation=prompt`, so the net state is `prompt` on both the create path and the re-run path

#### Scenario: the boot-time prompt reaches the console

- **WHEN** the machine boots with `boot.initrd.systemd.enable = true`, which `base` already sets
- **THEN** the `zfs-import-zroot` initrd unit issues `systemd-ask-password --timeout=${passwordTimeout}` (`nixos/modules/tasks/filesystems/zfs.nix:227`), where `boot.zfs.passwordTimeout` defaults to `0` — "waits forever" — at `zfs.nix:402-410`, after `systemd-modules-load.service` (`zfs.nix:159-165`), which is the ordering that matters because it guarantees the SPI input modules are modprobed before the prompt is issued
- **AND** the prompt is rendered by `systemd-ask-password-console.service`, which is started by `systemd-ask-password-console.path`'s level-triggered `DirectoryNotEmpty=/run/systemd/ask-password` rather than by the unit's `After=` on it — that `After=` edge is vacuous because the service is not in the boot transaction, and nothing in this design depends on it
- **AND** `i915` in initrd provides the framebuffer console that displays it

#### Scenario: hostId is inherited rather than pinned

- **WHEN** ZFS requires `networking.hostId`
- **THEN** pyrite sets nothing and inherits clan-core's `nixosModules/clanCore/zfs.nix:10` `lib.mkDefault "8425e349"`, whose stated purpose is to match the install ISO and nixos-anywhere so that the installer that creates the pool and the system that imports it present the same hostid
- **AND** a machine-specific hostid is NOT pinned, because it would manufacture the very mismatch that default exists to prevent

#### Scenario: forceImportRoot is kept as a deliberate decision

- **WHEN** `base` supplies `boot.zfs.forceImportRoot = true`
- **THEN** pyrite keeps it, because a re-run of the install path touches the pool from a rescue or installer environment and, per Mic92's `nixosModules/zfs.nix:16-18`, importing without force after such a touch lands the next boot in an emergency shell — which would defeat the re-runnability acceptance criterion
- **AND** its known cost, that the nixpkgs assertion `unsafeAllowHibernation -> !forceImportRoot` forecloses ZFS hibernation at evaluation time, is accepted because hibernation is a non-goal of this change

---

### Requirement: The accepted costs of ZFS native encryption are recorded rather than discovered later

The design SHALL record the properties ZFS native encryption does not offer, because they are structural and not remediable by configuration.

#### Scenario: there is exactly one key and no recovery path

- **WHEN** the encryption root is created with a single passphrase
- **THEN** it is recorded that ZFS permits exactly one key per encryption root and that `zfs change-key` replaces the key rather than adding one
- **AND** it is recorded that there is consequently no recovery passphrase, no escrow key, and no future `systemd-cryptenroll` path to a TPM or FIDO2 token, because those are LUKS keyslot features and ZFS has no keyslots
- **AND** these costs were accepted knowingly rather than overlooked

#### Scenario: pool and dataset metadata are not encrypted

- **WHEN** an attacker obtains the disk
- **THEN** it is recorded that ZFS native encryption leaves pool layout, dataset names, and snapshot names readable, and that only dataset contents are protected

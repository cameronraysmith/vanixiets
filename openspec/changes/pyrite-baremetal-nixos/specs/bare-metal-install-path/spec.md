## ADDED Requirements

### Requirement: The install path is recorded in the repository and is re-runnable

A bare-metal install path SHALL be recorded in the repository as a runnable artifact, not performed ad hoc.
It targets a stock NixOS installer ISO booted on the machine with sshd reachable, and it MUST be safe to run more than once.
It SHALL discard the disk explicitly, at every offset rather than only at the partition table, before invoking `clan machines install`.

#### Scenario: the wipe is blkdiscard, because zapping the GPT first disables disko's own pool destroy

- **WHEN** the recorded path wipes the disk on the installer before invoking `clan machines install`
- **THEN** it uses `blkdiscard` against the namespace-explicit `_1` path, following the form clan-core's own encrypted-root guide prescribes at `docs/src/guides/disk-encryption.md:84-88`
- **AND** it MUST NOT use `sgdisk --zap-all` or `wipefs -a` on the whole disk for this purpose, because disko's `disk-deactivate/disk-deactivate.jq:7-9` reaches `zpool destroy -f` and `zpool labelclear -f` only through a node whose `fstype` is `zfs_member`, and `:71-78` enumerates those nodes as children reported by `lsblk`, so a disk whose partition table was already zapped presents no children, the partition-level wipe never runs, the whole-disk `wipefs` at `:38` and `dd bs=440` at `:40` touch disk offsets while the ZFS labels live inside p2, disko recreates its deterministic layout so p2 reappears at the same offset with labels intact, and `lib/types/zpool.nix:298`'s `zpool import -N -f "zroot"` then succeeds and `:299` reports "not creating zpool as a pool with that name already exists" — reusing the old pool under the old passphrase, which is precisely the tautological green the re-runnability requirement below forbids
- **AND** if `blkdiscard` is unavailable, the fallback order is `zpool labelclear -f <device>-part2`, then `sgdisk --zap-all`, then `wipefs -a`, in that order, because the labelclear depends on the partition table the zap destroys

#### Scenario: the wipe is retained even though the default disko mode already destroys

- **WHEN** `clan_lib/machines/install.py` passes no `--disko-mode` — zero hits across clan-core at rev `d332b69` — so `src/nixos-anywhere.sh:419` sets `diskoMode=disko`, `:422` forms `diskoAttr="${diskoMode}Script"`, and disko's `lib/default.nix:889-894` `diskoScript` runs `_disko`, which `lib/default.nix:1094-1098` composes as `_legacyDestroy` then `_create` then `_mount`
- **THEN** the wipe is belt-and-braces on the happy path rather than load-bearing, and it is retained anyway
- **AND** it is retained because `_legacyDestroy` runs without `set -e`, so a destroy that fails silently falls through to `_create`, where `lib/types/gpt.nix:282-284` skips `sgdisk --clear` on a surviving Apple GPT because `blkid` succeeds, the subsequent `sgdisk --new` calls re-typecode Apple's partitions in place, `lib/types/filesystem.nix:54-58` skips `mkfs.vfat` on an ESP already reporting a `TYPE=`, and the machine boots Apple's 300 MiB ESP rather than the declared layout
- **AND** it is retained because the explicit wipe is the only step whose success the operator can independently observe before committing to an irreversible install

#### Scenario: the recorded path replaces the terranix invocation that does not apply

- **WHEN** `modules/terranix/{hetzner,gcp}.nix` hold the repository's only recorded `clan machines install` invocation, as a cloud-only `null_resource` local-exec, and no justfile recipe or other invocation site exists
- **THEN** pyrite gains its own recorded invocation carrying the target host, the identity file, and the no-facter-regeneration specifics, because without one the machine ships as a one-off manual install

#### Scenario: pyrite needs no terranix entry

- **WHEN** the machine has no cloud resource to provision
- **THEN** no terranix entry is added, because nothing in the clan inventory or any flake check reads one, and three existing NixOS machines already evaluate and check clean with `enabled = false` entries whose resources do not exist

#### Scenario: install-time ssh access is reconstituted by hand

- **WHEN** terranix would otherwise mint a deploy keypair, register the public half with the cloud provider, and enable root login via cloud-init
- **THEN** the recorded path instead authorizes a key against the booted installer session by hand, and documents that this authorization does not survive rebooting the installer

#### Scenario: clan subcommands that fight the nix-declared inventory are skipped

- **WHEN** the upstream physical-machine guide directs `clan init`, `clan machines create`, and `clan templates apply disk`
- **THEN** all three are skipped, because the first two write through `InventoryStore` against this repository's nix-declared inventory and the third writes `machines/pyrite/disko.nix`, which clan-core would auto-import alongside this repository's own disko module

---

### Requirement: Re-runnability is demonstrated by an install that exercises the create path, not by one that skips it

The acceptance criterion for re-runnability SHALL be a second install that destroys the pool and recreates it.
A re-run against a surviving pool MUST NOT be accepted as evidence.

#### Scenario: a re-run against a surviving pool proves nothing

- **WHEN** disko's `lib/types/zpool.nix:298` reuses a pool that already imports, logging "not creating zpool as a pool with that name already exists", and `lib/types/zfs_fs.nix:94`'s `zfs get type` probe skips creation of datasets that already exist
- **THEN** a re-run against a surviving pool never re-applies `ashift`, `encryption`, or `keyformat`, so it goes green without exercising the create path at all
- **AND** such a run is NOT accepted as evidence of re-runnability, because the criterion would be satisfied tautologically

#### Scenario: the second install destroys the pool first

- **WHEN** the re-runnability criterion is exercised
- **THEN** the disk is wiped as the recorded path's first step, per the wipe requirement above, so the second install creates the pool and datasets from scratch
- **AND** the check confirms that `ashift` is `12`, that the `root` dataset is encrypted with `keyformat = "passphrase"`, and that `keylocation` resolves to `prompt` after the run, since those are the properties a skipped create path would silently leave unverified

---

### Requirement: The tor onion service is declined by making its selector explicit

`modules/clan/inventory/services/tor.nix` SHALL target `roles.server.machines` naming the five cloud hosts rather than `roles.server.tags."nixos"`.
pyrite MUST NOT run a tor onion service.

#### Scenario: the nixos tag cannot simply be dropped

- **WHEN** `modules/clan/inventory/services/tor.nix` targets `roles.server.tags."nixos"` and `modules/clan/inventory/services/sshd.nix` targets the same tag for both its server and client roles
- **THEN** the tag is kept on pyrite and the tor selector is changed instead, because dropping the tag would silently forfeit persistent sshd host keys and CA-signed host certificates
- **AND** clan-core's inventory offers no per-machine exclusion from a tag-selected role, so changing the selector is the only available mechanism

#### Scenario: what is declined is an onion service, not a relay

- **WHEN** the clan-core tor server role's `nixosModule` sets `services.tor.enable = true` and `services.tor.relay.onionServices."clan_<instance>"` with a default `portMapping` exposing port 22
- **THEN** it is recorded that this publishes a v3 onion service exposing the machine's sshd to the Tor network, plus a `tor_<instance>` onion secret-key generator
- **AND** it is recorded that this is NOT a Tor relay, because `services.tor.relay.enable` — "Whether to enable relaying of Tor traffic for others" — is a separate `mkEnableOption` at `nixos/modules/services/security/tor.nix:531-545` that defaults false and is not set, so nothing forwards other people's traffic
- **AND** it is declined anyway, because an always-on daemon publishing an ssh endpoint of a laptop that moves between untrusted networks is not wanted

#### Scenario: the five cloud hosts keep the service unchanged

- **WHEN** the selector changes from tag-based to name-based
- **THEN** cinnabar, electrum, galena, magnetite, and scheelite are named explicitly and their behaviour is identical
- **AND** the cost is recorded: a future NixOS machine must be added to the list to gain the onion service, which is the same hand-maintained-list burden `modules/checks/structure/flake-shape.nix` already imposes

---

### Requirement: The hardware report is committed as static data and never regenerated on the target

`machines/pyrite/facter.json` SHALL be committed, git-tracked, with no import line and no flake input.
`clan machines install` MUST leave `--update-hardware-config` at its default of `none`.

#### Scenario: static consumption needs no facter binary

- **WHEN** the report exists at `machines/pyrite/facter.json`
- **THEN** clan-core wires `hardware.facter.reportPath` by path existence and nixpkgs supplies the `hardware.facter` option, so no flake input, no import line, and no facter binary is required
- **AND** the report must be git-tracked, because `reportPath` resolves to the store copy and an untracked file silently evaluates to no facter

#### Scenario: regeneration on this hardware is broken and is documented rather than solved

- **WHEN** `--update-hardware-config nixos-facter` would regenerate the report on the target
- **THEN** the flag is not used, because nixos-facter fails on this machine with `unsupported bus type: Spi` caused by `applespi`, pending nix-community/nixos-facter#672
- **AND** the residual dependency is documented: consuming the report is unblocked, regenerating it is not

#### Scenario: the machines directory is created atomically with the module and registrations

- **WHEN** clan-core `readDir`-scans `${directory}/machines` and injects an inventory machine per subdirectory with `machineClass` defaulting to `"nixos"`, from which `nixosConfigurations` is filtered
- **THEN** `machines/pyrite/facter.json` lands in the same commit as the host module and both registrations, never before them, because creating the directory alone materializes a `nixosConfigurations.pyrite` with no filesystems and no boot loader and breaks both hardcoded name lists in `modules/checks/structure/flake-shape.nix`

#### Scenario: previously-dormant facter code paths are asserted rather than inherited

- **WHEN** the report reports `virtualisation = "none"` against the five existing reports' `kvm` and `google`, and carries a `uefi` key they lack
- **THEN** the machine module states what it wants for `hardware.enableRedistributableFirmware` and `hardware.cpu.intel.updateMicrocode`, which `nixos/modules/hardware/facter/firmware.nix` newly sets as `mkDefault` because its whole block is gated on bare-metal detection and is dead on every existing machine

---

### Requirement: The machine is registered across every hand-maintained list a new machine touches

Registration SHALL cover the clan machine binding, the inventory entry, both hardcoded structure-check lists, the sops bridge recipient, and — after the ZeroTier address is known — the address records.

#### Scenario: both hardcoded structure-check lists are updated

- **WHEN** `modules/checks/structure/flake-shape.nix` carries two literal machine-name lists, one of nine inventory names and one of five `nixosConfigurations` names
- **THEN** `pyrite` is added alphabetically to both, because omitting either hard-fails `structure-inventory-machines` or `structure-nixos-configurations`
- **AND** `modules/checks/machines.nix` and `modules/checks/structure/inventory-class-discovery.nix` need no edit, because both are programmatic

#### Scenario: sops ordering is driven by when the machine age key first exists

- **WHEN** the age key does not exist until `clan vars generate pyrite` has run
- **THEN** the order is: generate vars, commit them, add the `&pyrite` anchor and `*pyrite` bridge key_group membership to `.sops.yaml`, re-encrypt with `just update-all-keys`, and only then install

---

### Requirement: ZeroTier admission requires redeploying the controller

pyrite SHALL be tagged `peer` and enrolled as a clan-managed ZeroTier peer with `deploy.targetHost = "root@pyrite.zt"`, and MUST NOT be added to `allowedIps`.
cinnabar MUST be redeployed after pyrite's ZeroTier IP var exists.

#### Scenario: a clan-managed peer needs no allowedIps entry

- **WHEN** the controller computes its authorization list at build time by folding `zerotier-ip-<name>-<instance>` public vars over every inventory machine in the moon, controller, and peer roles
- **THEN** the `peer` tag alone admits pyrite, because `allowedIps` holds only darwin and external members not managed by the clan zerotier service

#### Scenario: the address is knowable before the machine exists

- **WHEN** identity and IP are generated offline on the admin box via `zerotier-generate --mode identity-only` then `--mode compute-ip`
- **THEN** pyrite's ZeroTier address is known before it is ever installed, and the post-install address records can be prepared in advance

#### Scenario: the controller redeploy is an explicit step

- **WHEN** pyrite's `zerotier-ip-pyrite-zerotier` var is generated and committed
- **THEN** `clan machines update cinnabar` runs to regenerate and re-run the autoaccept unit, because without it the new peer is never admitted

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

### Requirement: Network association is declarative, and the committed credential is a network this repository originates

pyrite SHALL associate with a dedicated fleet SSID — a wireless network this repository stands up for the fleet — through clan-core's wifi clanService, instanced in `modules/clan/inventory/services/wifi.nix` and targeting `roles.default.machines."pyrite"`.
That network's SSID and PSK SHALL be clan vars, sops-encrypted and committed, and MUST NOT be entered interactively on the machine nor stored only in its `/var/lib`.
The household network's PSK MUST NOT appear in this repository in any form, because `github.com/cameronraysmith/vanixiets` is public and the credential is not solely this operator's to publish; if pyrite joins that network it does so interactively through `nmcli`.
The admitting test for any network is origination: a network this repository defines MAY have its credential committed, and a network this repository merely joins MUST NOT.
The credentials are shared clan vars — `clanServices/wifi/default.nix:88` sets `share = true` on the per-network generator carrying both prompts, and `roles.default.interface` exposes no setting through which an instance declines it — which is the intent here, since the fleet SSID exists to serve the fleet.
The first and third scenarios below are decidable by `nix eval` against the built configuration; the second and fifth are observed at install and first boot; the fourth is decidable by inspection of the repository.

#### Scenario: the built configuration carries NetworkManager and the declared profile

- **WHEN** `nix eval .#nixosConfigurations.pyrite.config.networking.networkmanager.enable` is evaluated
- **THEN** it returns `true`, which `clanServices/wifi/default.nix:96` sets unconditionally — not as a `mkDefault` — inside the `lib.mkIf (settings.networks != {})` opened at `:92`, making pyrite the fleet's first NetworkManager host
- **AND** `nix eval --json .#nixosConfigurations.pyrite.config.networking.networkmanager.ensureProfiles.profiles --apply builtins.attrNames` returns the declared network's identifier, and `networking.useDHCP` evaluates to `false`, forced by `nixos/modules/services/networking/networkmanager.nix:690`

#### Scenario: the credentials survive the wipe because they are repository state

- **WHEN** the recorded install path is re-run from a fresh ISO boot and its `blkdiscard` first step destroys `/var/lib` along with the rest of the disk
- **THEN** the SSID and the PSK are unaffected, because they are sops-encrypted clan vars in the repository rather than state on the machine
- **AND** the reinstalled machine associates with no operator entering credentials, which is what makes the post-install association check an observation that can fail rather than a step that produces its own result

#### Scenario: the zerotier unmanaged rule is already correct and nothing is added for it

- **WHEN** `nix eval --json .#nixosConfigurations.pyrite.config.networking.networkmanager.unmanaged` is evaluated
- **THEN** it contains `interface-name:zt*`, which `clanServices/zerotier/default.nix:461` sets unconditionally and which has been inert fleet-wide because no machine enabled NetworkManager
- **AND** this change declares no additional `unmanaged` entry, because zerotier's `systemd.network.networks."09-zerotier"` (`:450-457`) means networkd is intended to own `zt*` and the existing entry is what keeps NetworkManager off it

#### Scenario: the committed credential is a network this repository originates

- **WHEN** the repository's committed vars are inspected
- **THEN** every committed wifi credential belongs to a network this repository defines, held as a `wifi.<name>` generator whose files land under `vars/shared/` rather than `vars/per-machine/pyrite/`, per the `shared` path fragment `clan_lib/vars/_types.py:41-49` returns
- **AND** the household network's SSID and PSK appear nowhere in the repository, as plaintext or as sops ciphertext, because the repository is public, the ciphertext is therefore permanent and world-readable, and the credential is borrowed rather than originated
- **AND** the test is the one both reference repositories follow: clan-infra commits the disk secrets it generates (`machines/web01/disko.nix:49-58`, `machines/build01/disko.nix:71-80`) and Mic92 commits his OpenWRT access point's own key (`openwrt/example.nix:91-108`, `openwrt/secrets.yml:1`) while committing no credential for any network his four NixOS laptops merely join
- **AND** a future network is admitted to this treatment only under the same test, so a borrowed network is added by interactive `nmcli` association with its credential kept in a password manager, never as a second entry under `settings.networks`

#### Scenario: unattended association depends on the router serving the SSID and the vars existing before the deploy

- **WHEN** the fleet SSID is broadcasting with the PSK the operator generated, and `clan vars generate pyrite` has run against those values and its output has been committed before `clan machines install`
- **THEN** the machine associates unattended at first boot, because `autoConnect` defaults true (`clanServices/wifi/default.nix:30-33`) and lands as `connection.autoconnect` in the profile (`:107`)
- **AND** if the vars do not exist the profile interpolates empty strings and association fails silently, because no assertion and no eval-time error guards the condition
- **AND** if the SSID recorded in the var is not the one the router serves the interface never associates, which is equally unguarded, because the SSID reaches the var through a prompt the operator types and nothing compares it against the network

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

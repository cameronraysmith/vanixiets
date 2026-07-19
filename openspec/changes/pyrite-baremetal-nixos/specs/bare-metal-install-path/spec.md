## ADDED Requirements

### Requirement: The install path is recorded in the repository and is re-runnable

A bare-metal install path SHALL be recorded in the repository as a runnable artifact, not performed ad hoc.
It targets a stock NixOS installer ISO booted on the machine with sshd reachable, and it MUST be safe to run more than once.
It SHALL discard the disk explicitly, at every offset rather than only at the partition table, before invoking `clan machines install`.

#### Scenario: the wipe is blkdiscard, because zapping the GPT first disables disko's own pool destroy

- **WHEN** the recorded path wipes the disk on the installer before invoking `clan machines install`
- **THEN** it uses `blkdiscard` against the namespace-explicit `_1` path, following the form clan-core's own encrypted-root guide prescribes at `docs/src/guides/disk-encryption.md:84-88`
- **AND** it MUST NOT use `sgdisk --zap-all` or `wipefs -a` on the whole disk for this purpose, and the ground is restated under LUKS rather than carried over: with the pool inside a LUKS2 container, p2's `fstype` is `crypto_LUKS`, not `zfs_member`, so disko's `disk-deactivate/disk-deactivate.jq` `remove` falls through to `[]` at `:26-27` and the `zpool destroy -f` / `zpool labelclear -f` branch at `:7-9` is unreachable for p2 by type rather than by absence of children
- **AND** what runs against p2 instead is `deactivate`'s partition arm at `:42-45`, a bare `wipefs --all -f`, which erases the primary LUKS2 signature while the secondary header and the whole default 16 MiB keyslot area are left in place, so the old keyslots — the clan-vars passphrase and the enrolled FIDO2 credential — survive a wipe an operator would read as complete
- **AND** a disk whose partition table was zapped first is worse still, because `:71-78` enumerates the nodes `deactivate` visits as children reported by `lsblk`, so with no partition table there are no children, the p2 arm never runs at all, and the whole-disk `wipefs` at `:38` and `dd bs=440` at `:40` touch only disk offsets — after which disko recreates its deterministic layout, p2 reappears at the same offset with its header intact, `lib/types/luks.nix:202`'s `if ! blkid "$dev" || ! cryptsetup isLuks "$dev"` guard finds a valid container and skips `luksFormat`, and `:275-276`'s `if ! systemd-cryptenroll "$dev" | grep -qw fido2` finds the surviving enrollment and skips that too, so the install reuses the old container under the old credentials, which is precisely the tautological green the re-runnability requirement below forbids
- **AND** if `blkdiscard` is unavailable, the fallback order is `cryptsetup luksErase --batch-mode <device>-part2`, then `dd if=/dev/zero of=<device>-part2 bs=1M count=32`, then `sgdisk --zap-all`, then `wipefs -a`, in that order — `luksErase` first because it needs a header that still probes and every step below it destroys the magic, the 32 MiB overwrite next because it covers both LUKS2 headers and the whole default 16 MiB keyslot area rather than the primary signature alone, and the zap before the whole-disk `wipefs` for the reason the previous fallback recorded, that a partition-scoped step depends on the partition table the zap destroys
- **AND** `zpool labelclear -f <device>-part2` is removed from the fallback order rather than reordered, because under a LUKS container p2 holds no ZFS labels to clear — they live inside the container and are unreachable without opening it — so the command that used to be the first fallback would now succeed at nothing and read as progress

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

The acceptance criterion for re-runnability SHALL be a second install that destroys the LUKS container and the pool inside it and recreates both.
A re-run against a surviving container, or against a surviving pool, MUST NOT be accepted as evidence.

#### Scenario: a re-run against a surviving container or pool proves nothing

- **WHEN** disko's `lib/types/luks.nix:202` guard `if ! blkid "$dev" || ! cryptsetup isLuks "$dev"` finds a valid container and skips `luksFormat`, `:275-276`'s `if ! systemd-cryptenroll "$dev" | grep -qw fido2` finds a surviving enrollment and skips the FIDO2 enrollment, `:257-258`'s `cryptsetup open --test-passphrase` finds the passphrase already accepted and adds no key, `lib/types/zpool.nix:298` reuses a pool that already imports, logging "not creating zpool as a pool with that name already exists", and `lib/types/zfs_fs.nix:94`'s `zfs get type` probe skips creation of datasets that already exist
- **THEN** the run re-applies neither the container's format nor any of its keyslots nor `ashift` nor any create-time dataset property, so it goes green having exercised no create path at all
- **AND** such a run is NOT accepted as evidence of re-runnability, because the criterion would be satisfied tautologically
- **AND** the FIDO2 skip is the sharpest instance, because a surviving enrollment makes the second install appear to have enrolled a token it never touched, which is a false green about the machine's own unlock credential

#### Scenario: the second install destroys the pool first

- **WHEN** the re-runnability criterion is exercised
- **THEN** the disk is wiped as the recorded path's first step, per the wipe requirement above, so the second install formats a new LUKS container and creates the pool and datasets from scratch
- **AND** the check confirms that `cryptsetup luksUUID <device>-part2` differs from the UUID recorded after the first install, that `cryptsetup luksDump <device>-part2` shows exactly one `systemd-fido2` token and no surviving keyslot 0 from the throwaway `openssl rand` key disko wipes, that `zpool get -H -o value guid zroot` differs from the guid recorded after the first install, and that `zpool get ashift zroot` returns `12`, since those are the properties a skipped create path would silently leave unverified
- **AND** the second token's enrollment and the LUKS2 header backup are both destroyed by this re-run and MUST be redone against the new container afterward, because disko enrolls only the first token and a header backup taken against the previous container decrypts nothing and restores nothing

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

### Requirement: Network association is declarative, and the credentials are sops-encrypted clan vars

pyrite SHALL associate with the fleet's wireless network through clan-core's wifi clanService, instanced in `modules/clan/inventory/services/wifi.nix` and targeting `roles.default.machines."pyrite"`, so that the machine associates with no operator typing credentials into the installed system.
That network's SSID and PSK SHALL be clan vars, sops-encrypted and committed, and MUST NOT be entered interactively on the machine nor stored only in its `/var/lib`.
Neither value may appear as plaintext in this repository or in a world-readable store path; the SSID is a var for the same reason the PSK is, since the NetworkManager profile the service emits is world-readable.
The credentials are shared clan vars — `clanServices/wifi/default.nix:88` sets `share = true` on the per-network generator carrying both prompts, and `roles.default.interface` exposes no setting through which an instance declines it — so both land under `vars/shared/wifi.<name>/` rather than `vars/per-machine/pyrite/`, which is the intent here, since the network exists to serve the fleet.
Which network the `fleet` identifier denotes, and the origination reasoning that the choice of the pre-existing household network supersedes, are settled in design.md's D14 and are recorded there rather than imposed here.
The first and third scenarios below are decidable by `nix eval` against the built configuration; the second, fourth, and fifth are observed at install and first boot.

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

#### Scenario: the association is declarative, from committed vars, with nothing typed into the installed system

- **WHEN** the installed machine is cold-booted and its wireless state is inspected
- **THEN** the active connection is the fleet network on `wlp2s0`, reached unattended across the boot, with no operator having entered an SSID or a PSK into the installed system at any point
- **AND** the profile backing it is `/var/run/NetworkManager/system-connections/fleet.nmconnection` — the path `ensureProfiles` writes, under `/run` — so the profile came from the built configuration rather than from the machine
- **AND** `/etc/NetworkManager/system-connections/` is empty, which is what separates a declared profile from one an operator added by hand through `nmcli` after the fact
- **AND** the SSID and PSK it interpolates come from the sops-encrypted `wifi.fleet` generator's files under `vars/shared/`, per the `shared` path fragment `clan_lib/vars/_types.py:41-49` returns, so neither value exists as plaintext in the repository or in the world-readable store path holding the profile

#### Scenario: unattended association depends on the router serving the SSID and the vars existing before the deploy

- **WHEN** the fleet SSID is broadcasting with the PSK the router serves, and `clan vars generate pyrite` has run against those values and its output has been committed before `clan machines install`
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

---

### Requirement: A FIDO2 token is verified present before the wipe, because this machine defeats disko's own guard

The recorded install path SHALL verify that a FIDO2 token is seated and answering before the `blkdiscard` that opens the point of no return.
Disko's `wait_for_token` MUST NOT be relied upon as that verification.

#### Scenario: the internal SPI keyboard satisfies disko's guard with no token seated

- **WHEN** disko's `wait_for_token` at `lib/types/luks.nix:277-292` polls `if ls /dev/hidraw* &>/dev/null` at `:283` and breaks on the first match
- **THEN** the guard passes immediately on this machine with no token present, because the internal Apple SPI keyboard registers a `hidraw` node of its own independently of any token, so the guard tests for the wrong thing here
- **AND** `systemd-cryptenroll --fido2-device=auto` at `:295-300` then finds nothing, the script exits under `set -e`, and it does so after the `luksFormat` at `:244` has already replaced the container — on a machine with no fallback OS, which makes it an unrecoverable post-wipe abort rather than a failed step

#### Scenario: the verification names the token rather than counting hidraw nodes

- **WHEN** the pre-wipe check runs
- **THEN** it enumerates FIDO2 tokens specifically — `fido2-token -L` listing at least one device, or `ykman fido info` returning a PIN-attempt count — rather than testing `ls /dev/hidraw*`, which the keyboard already satisfies
- **AND** it confirms exactly one token is seated, because `--fido2-device=auto` requires exactly one and disko passes no device path

#### Scenario: the second token is a post-install step, not part of the install

- **WHEN** two tokens are to be enrolled
- **THEN** the install enrolls only the first, because `:276`'s guard skips enrollment once any `fido2` slot exists and `--fido2-device=auto` requires exactly one token plugged in, so the second is enrolled by hand afterward with the first removed
- **AND** the LUKS slot index each token occupies is recorded at enrollment, because both report the same AAGUID and nothing distinguishes them afterward

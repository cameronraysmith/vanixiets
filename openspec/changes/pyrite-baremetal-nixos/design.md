## Context

pyrite is an Apple MacBookPro14,1 (2017 13-inch, non-Touch-Bar) that would become the vanixiets fleet's first bare-metal NixOS machine.
The fleet today is four nix-darwin laptops and five NixOS cloud VMs, and every NixOS machine ever created in this repository is a cloud VM.
Every hardware assumption in the shared `base` layer is consequently untested on physical hardware, and several of them are cloud-VM assumptions that do not hold here.

Live reconnaissance on 2026-07-16 (Linear CAM-31, complete) established the hardware surface from the running machine over ssh while it was booted from a stock NixOS 26.05 installer ISO.
`docs/notes/development/hardware/pyrite-hardware-inventory.md` records what was observed; the raw dumps sit beside it.
`docs/notes/development/hardware/mbp141-nixos-clan-research.md` records the prior inference-based research, and its own provenance header names the three places the live recon supersedes it.

This change implements CAM-32.
It adds the machine, and it adds the bare-metal install path — which is the more durable of the two, because the repository presently has no install path that does not route through terranix.

## Adversarial verdicts that change the design

Several load-bearing claims went to adversarial verification and were refuted.
They are recorded here rather than designed around silently, because they alter the justification for decisions the user has already made and one of them alters the ordering of the apply.

### Refuted: "ZFS is fleet convention because base forces forceImportRoot"

This was the premise the ZFS decision was originally stated to rest on, and as an argument it does not hold.

`modules/system/zfs-force-import.nix:19-21` does set `boot.zfs.forceImportRoot = true` on `flake.modules.nixos.base`, and all five NixOS machines import `base`, so the setting is real.
But the inference from that setting to "ZFS is convention" is invalid.
The option is declared unconditionally in nixpkgs, keyed on `stateVersion` alone with no reference to whether ZFS is enabled, and it is inert on a machine with no pool.
clan-core demonstrates the distinction structurally: `nixosModules/clanCore/zfs.nix` sets `boot.zfs.forceImportRoot = lib.mkDefault false` unconditionally while gating `services.zfs` behind `lib.mkIf config.boot.zfs.enabled` in adjacent lines.
The setting is a defensive default and proves nothing about ZFS usage.

The conclusion survives on evidence the original argument never cited.
All five NixOS machines root on ZFS via disko with a `zroot` pool and datasets `root`, `root/nixos`, `root/home`, `root/nix`; none has a non-ZFS root.
ZFS-on-root is genuinely the convention, and the decision stands — but it is a filesystem argument, not an argument about `forceImportRoot`.

### Refuted: "ZFS native encryption requires a key pushed at every boot by a second machine"

This is the false premise on which an earlier revision of this document recommended LUKS, and it is the reason this design was rewritten.

The premise came from reading clan-infra's `web01`, whose `machines/web01/disko.nix:96` sets `keylocation = "file://${config.clan.core.vars.generators.zfs.files.key.path}"` and keeps that value at boot, backed by an initrd unit at `disko.nix:63-67` that spins waiting for the key file to appear.
Generalizing from that one machine produced the conclusion that ZFS native encryption structurally cannot use a boot-time prompt under a non-interactive install, and therefore that LUKS — whose `cryptsetup luksFormat` reads a `passwordFile` without any interactive phase — was the only mechanism satisfying both re-runnability and a typed passphrase.

The generalization is wrong, and disko refutes it directly.
`lib/types/zfs_fs.nix:80-91` enumerates the properties ZFS treats as `PROP_ONETIME` — `encryption`, `casesensitivity`, `utf8only`, `normalization`, `volblocksize`, `pbkdf2iters`, `pbkdf2salt`, `keyformat`.
`keylocation` is deliberately absent from that list, which is what makes it settable after creation.
disko then documents the resulting idiom in its own encrypted-root example at `example/zfs.nix:104-113`: create the dataset with `keylocation = "file:///tmp/secret.key"`, and flip it with a `postCreateHook` running `zfs set keylocation="prompt"`.
`postCreateHook` is a real option declared at `lib/default.nix:476` and spliced after the create body at `lib/default.nix:507-511`, so the flip is ordinary supported disko, not a trick.

The key material never changes across that flip; only the location from which ZFS reads it does.
This is the exact ZFS-native analog of LUKS's `passwordFile`, and it dissolves the only advantage LUKS had.
`zfs change-key` is not involved, is not needed, and appears nowhere in clan-core, clan-infra, or Mic92's dotfiles.

web01 is a server that is unlocked remotely by another machine, so it has no reason to flip the property and does not.
Reading pyrite's requirements off web01's configuration was the error.

### Refuted: "facter.json can be placed exactly like the other five, with no special casing"

Two of the three conjuncts fail, and the first one changes the apply ordering.

The placement path is symmetric and that part holds: `machines/pyrite/facter.json`, git-tracked, no import line, no flake input, no facter binary.
clan-core wires it by path existence at `nixosModules/clanCore/nixos-facter.nix:5,10`, and `hardware.facter` itself is upstreamed into nixpkgs rather than supplied by an input.

But `machines/pyrite/` is not an inert data directory.
clan-core `modules/clan/module.nix:141-148` `readDir`-scans `${directory}/machines` and injects an inventory machine per subdirectory, with `machineClass` defaulting to `"nixos"`, from which `nixosConfigurations` is filtered.
Creating the directory therefore materializes an inventory entry and a `nixosConfigurations.pyrite` before any module exists to configure it, breaking both hardcoded name lists in `modules/checks/structure/flake-shape.nix` and emitting a `checks.nixos-pyrite` that builds a machine with no filesystems and no boot loader.
The consequence is an ordering constraint recorded in tasks.md: the facter report lands in the same commit as the module and the registrations, never before them.
This is why the report is staged inside this change directory rather than in `machines/` while the change is in flight.

The report is also a superset, not a match.
pyrite's carries a `uefi` key the five lack, and reports `virtualisation = "none"` against their `kvm` and `google`.
Three nixpkgs facter code paths that are dead on every existing machine become live: `hardware/facter/boot.nix` reads `uefi.supported` and sets `boot.loader.grub.efiSupport` (inert under systemd-boot); `hardware/facter/firmware.nix` gates its entire block on bare-metal detection and newly sets `hardware.enableRedistributableFirmware` and `hardware.cpu.intel.updateMicrocode`, both `mkDefault`; and `hardware/facter/networking/initrd.nix` injects `brcmfmac` into `boot.initrd.kernelModules` because `base` sets `boot.initrd.network.enable = true`.
None of these is harmful, but they are unreviewed defaults no one in this fleet has evaluated, and the design asserts what it wants rather than inheriting them.

Note what facter does not supply: `hardware/facter/keyboard.nix` sources initrd keyboard modules from the USB controller report only, and `applespi` is SPI.
The stage-1 passphrase prompt gains nothing from facter and must carry its own modules.

### Refuted: "removing terranix leaves no functional gap other than a disko layout"

The dependency half of this claim holds and is worth stating, because it makes the change smaller than it looks.
terranix supplies pyrite no dependency: no DNS, no IP, no ssh host key, no cloud-init, no bootstrap secret, no `targetHost` value, and nothing the clan inventory or any flake check reads.
Three NixOS machines already run with `enabled = false` terranix entries whose cloud resources do not exist, so a machine with no entry at all evaluates and checks clean.
pyrite needs no terranix entry.

The capability half fails, and its carve-out names the wrong thing.
terranix never supplied disko — disko has always lived at `modules/machines/nixos/<name>/disko.nix`.
What terranix does supply, and pyrite needs an analog of, is two things the claim omits: the repository's only recorded `clan machines install` invocation, and install-time SSH credential material with root-login enablement.
There is no `clan machines install` recipe in the justfile and no other invocation site anywhere.
Taken at face value, this claim would ship a machine module with a disko layout and no recorded install path — a one-off manual install, which the binding decision rules unacceptable.
D8 exists because of this.

### Refuted: "tagging `nixos` in the inventory auto-enrolls the machine as a Tor relay"

The mechanism is real; the characterization is wrong, and the correction matters because it changes what is being avoided.

`modules/clan/inventory/services/tor.nix` does target `roles.server.tags."nixos"`, and `modules/clan/inventory/services/sshd.nix` targets the same tag for both its server and client roles, so the tag that supplies sshd host keys and CA certificates does also select the tor server role.
That much of the claim holds.

But clan-core's tor server role is not a relay.
`clanServices/tor/default.nix` describes the role as "Sets up a Tor onion service for the machine, thus making it reachable over Tor", and its `nixosModule` sets only `services.tor.enable = true` and `services.tor.relay.onionServices."clan_<instance>"`, with a default `portMapping` exposing port 22.
In nixpkgs, `services.tor.relay.enable` — "Whether to enable relaying of Tor traffic for others" — is a separate `mkEnableOption` at `nixos/modules/services/security/tor.nix:531-545`, defaulting false, and it gates the `ExitPolicy`/`BridgeRelay` settings at `tor.nix:1277-1296`.
The `relay.onionServices` attribute lives under the `relay` namespace but does not enable relaying; nothing forwards other people's traffic.

What the tag actually produces on pyrite is a continuously running tor daemon publishing a v3 onion service that exposes the machine's sshd to the Tor network, plus a `tor_tor` vars generator holding the onion secret key.
That is still not wanted on a travelling laptop — it is an always-on daemon publishing an ssh endpoint of a machine whose whole point is to move between untrusted networks — but it should be declined for what it is.
See D10.

### Confirmed: the stage-1 passphrase prompt works on the internal keyboard

This is the safety-critical claim, because a wrong answer means being locked out of a freshly-wiped laptop with no macOS to fall back to.
It was verified end to end and it holds, with one mechanism in the earlier write-up corrected below.

The nixos-hardware profile at `apple/macbook-pro/14-1/default.nix:18-25` sets `boot.initrd.kernelModules` — the strong option that force-loads, not merely `availableKernelModules` — to `applespi`, `spi_pxa2xx_platform`, `intel_lpss_pci`, and `applesmc`, under a comment reading "Make the keyboard work in stage1".
The module closure was built at this repository's pinned nixpkgs (kernel 6.18.37, not the ISO's 7.1.3) with `allowMissing = false`, which exits non-zero on any unresolved root module, and it succeeded — producing `applespi.ko.xz`, `spi-pxa2xx-platform.ko.xz`, `spi-pxa2xx-core.ko.xz`, `intel-lpss.ko.xz`, `intel-lpss-pci.ko.xz`, and `applesmc.ko.xz`, matching the set recon observed running.

The prompt-display mechanism, stated precisely.
`nixos/modules/tasks/filesystems/zfs.nix:159-165` gives the `zfs-import-zroot` unit `after = [ "systemd-modules-load.service" "systemd-ask-password-console.service" ]`, and `zfs.nix:227` runs `systemd-ask-password --timeout=${passwordTimeout}` with the option defaulting to an unbounded wait.
The `systemd-modules-load.service` half of that ordering is real and load-bearing: the unit is in the initrd transaction, so the SPI modules are modprobed before the prompt is issued.
The `systemd-ask-password-console.service` half is vacuous.
That service is not in the boot transaction; it is triggered by `systemd-ask-password-console.path`, whose `[Path] DirectoryNotEmpty=/run/systemd/ask-password` is level-triggered, so the agent starts when the password request appears regardless of ordering.
`nixos/modules/system/boot/systemd/initrd.nix:96-97` includes both the `.path` and the `.service` in the initrd unit set, which is what actually makes the prompt render.
Nothing in the design depends on the vacuous edge, but the earlier statement that it orders the prompt was wrong and is corrected here.

`i915` reaches initrd via the profile's import chain (`apple/macbook-pro/14-1` imports `common/cpu/intel/kaby-lake`, which reaches `common/gpu/intel`, whose `default.nix:90` adds `cfg.driver` to `boot.initrd.kernelModules` when `loadInInitrd`), providing the framebuffer console that displays the prompt.
This is why D5 has no "skip the profile" fallback.

Two residual honesties.
The modules are proven shipped and loaded; that `applespi` binds and yields working input at 6.18.37 in initrd specifically is a strong inference from recon's observation at 7.1.3 in a full system, not direct evidence.
And `systemd-modules-load` returns when `modprobe` returns, not when the input device exists, so the prompt can appear seconds before the keyboard is live — mitigated by the unbounded timeout, and not a lockout.
A not-yet-live keyboard submits nothing and therefore burns no attempt, because `--timeout=0` blocks until Enter rather than returning empty.

Wrong answers are capped, however.
`zfs.nix:224-231` wraps the prompt in a `tries=3` loop and gates the unit on `[[ $success = true ]]`, so a third consecutive mistyped passphrase fails `zfs-import-zroot` and drops the boot to an emergency shell.
That is a reboot and a retry rather than a lockout — the pool is untouched and the key is unchanged — but it is a plausible outcome for a roughly 45-character random passphrase typed blind, and it is the reason D4's generator emits words rather than hex.

Lockout is in any case not the intended failure mode: `usbhid`, `hid-generic`, and `hid-apple` reach the initrd through `availableKernelModules` and udev autoloading rather than through the force-loading `kernelModules`, so an external keyboard is a recovery path that depends on udev probing rather than on an unconditional modprobe.
The runbook carries this, along with the fact that a MacBookPro14,1 has USB-C ports only — a USB-C keyboard or a USB-A adapter must be physically on hand before the first boot, not sourced after a failure.

## Goals / Non-Goals

**Goals:**
- Add pyrite to the fleet as a NixOS machine with a full laptop hardware surface.
- Encrypt the root with a passphrase the operator types on the internal keyboard at boot.
- Produce a bare-metal install path that is re-runnable, not a one-off manual sequence.
- Reach travel-readiness: the machine is usable away from the ZeroTier mesh and away from a build host.

**Non-Goals:**
- Audio. Out of scope by binding decision, not a deferred work item. Recorded in the hardware inventory note as an upstream watch-item.
- Suspend/resume and the `d3cold` workaround. Deferred to a separate change; necessity unverified on this unit.
- Hibernation. Deferred by binding decision, which is what makes D6 costless today.
- Correcting `base`'s cloud-VM initrd assumptions for the fleet. pyrite overrides per-machine; gating the shared module is a separate change touching five machines.
- Regenerating facter reports on this hardware. Blocked upstream on nixos-facter#672; consuming a static report is not blocked.
- A terranix entry for pyrite. Nothing reads one.
- Fixing the pre-existing justfile defects a new machine walks into (`check-uncached-machine` hardcodes four hosts and already omits magnetite).

## Decisions

### D1: ZFS native encryption, created from a keyfile and flipped to a boot-time prompt

- **Choice**: a ZFS `zroot` pool with a `root` dataset carrying `encryption = "aes-256-gcm"` and `keyformat = "passphrase"`, created with `keylocation = "file://<partitioning-secret path>"` and a `postCreateHook` running `zfs set keylocation="prompt" zroot/root`, so every subsequent boot prompts locally. The dataset layout matches the fleet's `root`, `root/nixos`, `root/home`, `root/nix`.
- **Rationale**: three independent supports. Fleet parity — all five NixOS machines root on ZFS with a `zroot` pool and none has a non-ZFS root; ext4-on-LUKS would make pyrite the only non-ZFS root, forfeiting snapshots, compression, and the dataset layout every sibling uses. Exact parity with the closest available precedent — Mic92 is a clan-core developer, and both of his encrypted laptops (`machines/turingmachine/modules/disko.nix:47-56` and `machines/jacquardmachine/disko.nix:44-51`) are ZFS native, `aes-256-gcm`, `keyformat = "passphrase"`, `keylocation = "prompt"`, `ashift = "12"`, unlocked by a typed passphrase with no initrd SSH (only his server `eve` has that, `machines/eve/modules/network.nix:46`). And attestation — the create-from-keyfile-then-flip idiom is disko's own documented example, not an invention of this change.
- **Alternatives considered**: ext4-on-LUKS. An earlier revision of this design recommended it, on the premise that ZFS native encryption structurally requires a key pushed at every boot by a second machine and therefore could not have a boot-time prompt under a non-interactive install. That premise is false — see the refuted verdict above — and with it removed LUKS's only advantage disappears while its filesystem-inconsistency cost remains.
- **Accepted cost, stated plainly**: ZFS native encryption permits exactly one key per encryption root. `zfs change-key` replaces the key; it cannot add a second one. There is therefore no recovery passphrase, no escrow key, and no future `systemd-cryptenroll` path to a TPM or a FIDO2 token — those are LUKS keyslot features and ZFS has no keyslots. Additionally, ZFS native encryption does not encrypt pool layout, dataset names, or snapshot names; an attacker with the disk learns the dataset structure. The user chose this knowingly.
- **Consequence for hibernation**: none today, because hibernation is a non-goal. See D6.

### D2: `ashift = "12"`, set explicitly

- **Choice**: `zpool.zroot.options.ashift = "12"`.
- **Rationale**: the disk reports 4096-byte logical and physical sectors, and 2^12 = 4096. Disko performs no sector-size detection and passes zpool options through verbatim to `zpool create -o`, so this is entirely the caller's responsibility. It is also unanimous across all seven of Mic92's pools. ZFS's `ashift=0` autodetect should arrive at 12 as well, but that was not grounded against OpenZFS source and is not relied on.
- **Note**: no existing machine in this repository sets `ashift`, because all five are 512-byte-sector cloud disks. pyrite is the first, and the resulting inconsistency is visible but not a defect in the others.

### D3: namespace-explicit `by-id` device path, and `boot.zfs.devNodes = "/dev/disk/by-id"`

- **Choice**: `device = "/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1"`.
- **Rationale**: the controller exposes two namespaces. `nvme0n1` is the 465.9 GiB disk; `nvme0n2` is 8 KiB and must never be written. Their by-id names differ only by a `_1`/`_2` suffix, and the unsuffixed name is a bare prefix of both. `_1` and the unsuffixed name were both observed resolving to `nvme0n1`; `_1` is chosen because it names the namespace rather than relying on which namespace the unsuffixed alias points at.
- **Alternatives considered**: the unsuffixed name (rejected: prefix-ambiguous with the dangerous namespace); the wwid form `nvme-nvme.106b-...-00000001` (namespace-explicit and equally correct, rejected as unreadable at a review site where readability is the safety property).
- **devNodes**: every existing machine sets `by-path` with a comment reading "more stable for cloud VMs". That reasoning does not transfer to a laptop with a stable by-id path, and by-id is the bare-metal norm. ZFS scanning the 8 KiB namespace during import is harmless; the hazard is a write, and only the disko `device` writes.

### D4: the create-time key is a clan vars generator producing a human-typeable passphrase

- **Choice**: `clan.core.vars.generators.zfs` with `files.key.neededFor = "partitioning"`, whose script emits a human-typeable passphrase in the spirit of clan-infra `build01`'s `xkcdpass --numwords 6 --random-delimiters --case random` (`machines/build01/disko.nix:71-80`). The dataset's create-time `keylocation` points at that generator's `files.key.path`.
- **Rationale**: this is the channel `clan machines install` is built around, verified at the clan-core revision pinned in `flake.lock` (`d332b6935fbebebc0ca151efe0b3144f8dcd9d96`). `nixosModules/clanCore/vars/secret/sops/default.nix:30-32` resolves the `path` of any file with `neededFor == "partitioning"` to `/run/partitioning-secrets/<generator>/<file>`, and `pkgs/clan-cli/clan_lib/machines/install.py:171-182` rglob-walks that generated file tree and appends one `--disk-encryption-keys /run/partitioning-secrets/<...> <local path>` pair per file to the `nixos-anywhere` invocation automatically. Nothing is passed by hand.
- **`keyformat` MUST be `passphrase`, not `hex`**: clan-infra's `web01` uses `keyformat = "hex"` with `dd if=/dev/urandom | xxd` because it is a server unlocked over the network by a machine. A hex key is not usable by a person standing at a boot prompt. `build01`'s `xkcdpass` generator is the right shape; only its consumer (LUKS `passwordFile`) differs.
- **Why the flip is necessary rather than cosmetic**: the `/run/partitioning-secrets/...` path that `.path` resolves to exists only during the install, because nixos-anywhere places it there. It does not exist at boot. Leaving `keylocation` at that `file://` value would produce a machine that cannot find its key — which is precisely why web01 carries an initrd unit spinning until the file appears from elsewhere. The `postCreateHook` flip to `prompt` is what makes the boot self-sufficient.
- **Re-run idempotency**: verified against disko `lib/types/zfs_fs.nix:94-114`. On a first run the `zfs get type` probe fails and the create branch runs `zfs create -up ... -o keylocation=file://...`; on a re-run against an existing dataset the probe succeeds and the else branch runs `zfs set -u <updateOptions>`, where `updateOptions` is the create options minus `onetimeProperties` and therefore still contains `keylocation=file://...`. In both cases the `postCreateHook` runs afterward — `lib/default.nix:507-511` splices it after the create body unconditionally — and sets `keylocation=prompt`. The net state is `prompt` on either path.

### D5: import the nixos-hardware profile, disable two unwanted pulls

- **Choice**: add `nixos-hardware` as a flake input with `inputs.nixpkgs.follows = "nixpkgs"` mirroring disko's declaration at `flake.nix:83-84`, import `nixos-hardware.nixosModules.apple-macbook-pro-14-1`, and set `networking.enableB43Firmware = false` and `hardware.facetimehd.enable = false`.
- **Plain `false`, not `mkForce`**: both upstream values are `lib.mkDefault` — `apple/macbook-pro/14-1/default.nix:50` sets `networking.enableB43Firmware = lib.mkDefault true` and `apple/default.nix:4` sets `hardware.facetimehd.enable = lib.mkDefault (config.nixpkgs.config.allowUnfree or false)`. A plain definition overrides `mkDefault` at normal priority. An earlier revision of this document claimed `mkForce` was required because the values arrive from inside an imported profile; that is not how the module system's priority resolution works, and `mkForce` here would be unnecessary noise that also suppresses any future legitimate override.
- **b43**: a misdetection. The profile pulls `b43Firmware` for silicon this machine does not have; its WiFi is BCM4350 driven by `brcmfmac` from redistributable `linux-firmware`. This is a correction, not a workaround. The claim that the pull hard-fails evaluation is false — `modules/nixpkgs/base-defaults.nix:23` sets `allowUnfree = true` fleet-wide, so it evaluates. It is disabled to keep an unfree blob for foreign silicon out of the closure, not to make evaluation succeed.
- **facetimehd**: the fleet's global `allowUnfree = true` resolves the profile's `mkDefault` to true, auto-enabling an out-of-tree kernel module and unfree firmware on import. Disabled; the camera is not wanted and was not exercised during recon.
- **Consequence**: unfree firmware is absent from binary caches and must build locally, which surfaced during verification as a store-signature failure when pushing to the remote linux builder. Disabling both is what keeps the install path buildable from the darwin admin box.
- **No "skip the profile" fallback**: an earlier revision offered setting the four initrd modules directly and skipping the profile. That fallback is withdrawn, because it contradicts the prompt-visibility mechanism this design relies on: `i915` reaches initrd only through the profile's import chain into `common/gpu/intel`, and without it there is no framebuffer console to render the passphrase prompt. Hand-copying the four SPI modules while silently dropping `i915` produces an eval-clean, build-clean configuration with an invisible prompt.

### D6: keep `forceImportRoot = true`

- **Choice**: keep the `true` that `base` supplies, and record it as a decision rather than an inheritance.
- **Rationale**: it is load-bearing for a re-runnable install, which is this change's binding acceptance criterion. Mic92's `nixosModules/zfs.nix:16-18` states the mechanism in a comment scoped to exactly this class of machine: "Single-machine laptops/desktops: allow import after rescue/installer touched the pool with a different hostid, avoiding an emergency shell on next boot." A re-run of the install path touches the pool from the installer environment; without `forceImportRoot` the next boot lands in an emergency shell. The remaining interlock is unclean-export, where `false` would block boot after every unclean shutdown until someone types `zfs_force=1` at the console — a poor trade on a laptop, where an unclean shutdown is a normal event rather than an incident.
- **Known cost, and why it is not a cost today**: nixpkgs asserts `unsafeAllowHibernation -> !forceImportRoot && !forceImportAll`. `true` therefore forecloses ZFS hibernation at evaluation time, and because `base` assigns the value plainly rather than with `mkDefault`, changing it later requires `lib.mkForce`. Hibernation is deferred by binding decision, so this interlock blocks nothing in scope. If suspend-to-disk is later wanted, this decision is what must change.

### D7: `networking.hostId` is inherited, not pinned

- **Choice**: set nothing. pyrite inherits clan-core's `nixosModules/clanCore/zfs.nix:10` `networking.hostId = lib.mkDefault "8425e349"`, as the whole fleet already does.
- **Rationale**: clan-core's own comment states the reason and it applies exactly here — "Use the same default hostID as the NixOS install ISO and nixos-anywhere. This allows us to import zfs pool without using a force import." The hostid-mismatch condition that `forceImportRoot` exists to override is the one this default is chosen to prevent: the installer that creates the pool and the installed system that imports it present the same hostid. Pinning a machine-specific hostid would manufacture the mismatch this default avoids and would make D6 load-bearing for a reason it does not currently need to be.
- **Alternatives considered**: pin a pyrite-specific hostid, as disko's own `tests/zfs-encrypted-root.nix:8-9` does on both installer and system. Rejected: that test pins the same value on both sides precisely to keep them matched, which is what the clan-core default already achieves fleet-wide without a per-machine literal. Mic92's two laptops pin nothing and lean on `forceImportRoot`, which is the same posture this arrives at with the additional safety of a matched hostid.
- **Relationship to D6**: these are belt and braces, not redundancy. The matched hostid means force-import is not needed in the ordinary case; `forceImportRoot` covers the unclean-export case and any rescue environment that does not share the default.

### D8: a recorded, re-runnable install path that destroys the existing partition table

- **Choice**: the install path is `clan machines install` against a booted stock installer ISO with sshd, with `--update-hardware-config` left at its default of `none` and the pre-generated report committed instead. The path is recorded in the repository, not performed ad hoc. It is preceded by an explicit, recorded disk-wipe step.
- **Rationale**: the binding requirement is that the path run repeatedly. terranix's `null_resource` local-exec is the only recorded invocation in the repository and it is cloud-only; without a recorded analog, pyrite ships as a one-off manual install.
- **The wipe is not optional, and disko's create phase will not do it**: `lib/types/gpt.nix:282-284` runs `sgdisk --clear` only `if ! blkid "${config.device}"` — that is, only when the device has no recognizable signature. pyrite ships with an Apple GPT today, so `blkid` succeeds and the clear is skipped; the subsequent `sgdisk --new` calls then merely re-typecode Apple's existing partitions in place. `lib/types/filesystem.nix:54-58` compounds it, skipping `mkfs.vfat` when `blkid` already reports a `TYPE=`, which Apple's existing ESP does. The net effect of a create-only run against an unwiped disk is booting Apple's 300 MiB ESP rather than the declared layout. The recorded path therefore wipes the disk explicitly on the installer (`sgdisk --zap-all` plus `wipefs -a` against the `_1` namespace path from D3) before invoking `clan machines install`, which is deterministic and does not depend on any tool's default mode.
- **Unresolved and carried as a task**: `clan_lib/machines/install.py:158-190` builds the `nixos-anywhere` argv without passing `--disko-mode`, so nixos-anywhere's default applies. disko itself supports `destroy`, `format`, `mount`, `unmount`, `format,mount`, and `destroy,format,mount` (`disko:29-34,139-146`), and only the `destroy,` prefixed mode wipes. Which of these nixos-anywhere defaults to could not be verified: there is no local clone of `nix-community/nixos-anywhere`. The explicit wipe above makes the answer non-load-bearing for correctness, but it should be established rather than assumed. See the open questions.

### D9: ZeroTier peer, with the cinnabar redeploy as an explicit step

- **Choice**: tags include `nixos` and `peer`; `deploy.targetHost = "root@pyrite.zt"`; no `allowedIps` entry.
- **Rationale**: ZeroTier admission is declarative and evaluated at build time. The controller folds over every inventory machine in the moon, controller, and peer roles and reads each one's `zerotier-ip-<name>-<instance>` public var. The `allowedIps` list holds only darwin and external members not managed by the clan service; a NixOS peer needs no entry there.
- **The step that is easy to miss**: cinnabar must be redeployed after pyrite's ZeroTier IP var exists, or the new peer is never admitted. Identity and IP are generated offline on the admin box without touching the target, so pyrite's address is knowable before the machine is ever installed.

### D10: decline the tor onion service by making tor.nix target machines explicitly

- **Choice**: change `modules/clan/inventory/services/tor.nix` from `roles.server.tags."nixos"` to an explicit `roles.server.machines` list naming the five cloud hosts, leaving their behaviour identical and excluding pyrite.
- **Rationale**: the `nixos` tag cannot be dropped from pyrite — `modules/clan/inventory/services/sshd.nix` selects both its server and client roles by the same tag, and dropping it forfeits persistent host keys and CA-signed host certificates. clan-core's inventory offers no per-machine exclusion from a tag-selected role, so the only way to decline the tor role while keeping sshd is to change the selector. What is being declined is an always-on tor daemon publishing a v3 onion service that exposes pyrite's sshd to the Tor network, along with a `tor_tor` onion secret-key generator — see the refuted verdict above for why this is not a relay.
- **Cost**: the five cloud machines move from tag-selected to name-selected, so a future NixOS machine must be added to the list to gain the onion service. That is the same hand-maintained-list burden `flake-shape.nix` already imposes, and it is the correct default for a fleet that now contains a machine that travels.
- **Alternatives considered**: keep the tag and accept the onion service (rejected — the user does not want an ssh endpoint of a travelling laptop published to Tor); drop the `nixos` tag from pyrite (rejected — it silently takes sshd's host keys and CA certificates with it).

### D11: no plymouth

- **Choice**: set nothing; `boot.plymouth.enable` stays at its nixpkgs default of false, matching the fleet, which uses plymouth nowhere.
- **Rationale**: plymouth changes which agent renders the passphrase prompt, and the prompt is this machine's safety-critical path. `systemd-ask-password-console.path` carries `ConditionPathExists=!/run/plymouth/pid`, so when plymouth is running the console agent does not start at all; `nixos/modules/system/boot/plymouth.nix:213-214` instead wires `systemd-ask-password-plymouth` into `sysinit.target` and `plymouth.nix:240-253` builds a reduced plugin and theme set for the initrd. The prompt still renders under that arrangement, but through a different agent, a different renderer, and a graphical stack whose interaction with `i915` on this specific model has not been verified.
- **Why Mic92 running it is not an argument**: `nixosModules/workstation.nix:40-41` does set `boot.plymouth.enable = true` alongside `initrd.systemd`, which establishes that the combination works on his hardware. It does not establish that it works on a MacBookPro14,1 at this repository's pinned kernel, and adopting an unverified graphical layer on the one machine that cannot be recovered by reboot is not a trade worth making for a splash screen.
- **Revisit**: after the machine is installed and booting reliably, enabling plymouth is a low-risk cosmetic change that can be tested with a known-good fallback.

### D12: build host

- **Choice**: no new configuration. stibnite already provisions two x86_64-linux builders — `nix-rosetta-builder` locally and `magnetite-builder` natively, the latter preferred by speed factor.
- **Travel caveat**: magnetite is reachable only over the ZeroTier mesh, so an install performed away from the mesh falls back to the Rosetta-translated local builder. Slower, always available, and it does not block. Stated because travel-readiness is an acceptance criterion.

## Invariants

### pyrite MUST NOT `mkForce` `boot.initrd.kernelModules`

`base` contributes `virtio_pci` and `virtio_net` to `boot.initrd.kernelModules` at `modules/system/initrd-networking.nix:33-37`, and those entries are meaningless on bare metal.
The natural-looking way to drop them is `boot.initrd.kernelModules = lib.mkForce [ ... ]`, and that is a lockout.
The option is a list that accumulates from four sources: `base`'s virtio pair, the nixos-hardware profile's `applespi`/`spi_pxa2xx_platform`/`intel_lpss_pci`/`applesmc`, `common/gpu/intel`'s `i915`, and facter's `brcmfmac`.
`mkForce` discards every definition it does not name, so a list containing only the intended survivors would silently drop the SPI input modules, the framebuffer driver, or both — producing a configuration that evaluates cleanly, builds cleanly, and boots to a passphrase prompt that is either invisible or unanswerable on a machine with no macOS to fall back to.

The virtio entries are inert on bare metal: they modprobe, find no matching device, and cost a few kilobytes of initrd.
They are left alone.
What pyrite overrides is `boot.initrd.network.ssh`, which is a distinct option and can be disabled without touching the module list.

## Open questions

### nixos-anywhere's default disko mode is unverified

`clan_lib/machines/install.py` passes no `--disko-mode`, so whichever mode nixos-anywhere defaults to is what runs.
This could not be checked: `nix-community/nixos-anywhere` has no local clone, and the style conventions forbid substituting a web fetch for reading the source when a clone is the authoritative path.
D8's explicit wipe step makes the install correct regardless of the answer, so this is not a blocker, but the answer determines whether the wipe is belt-and-braces or the only thing standing between the install and a boot from Apple's ESP.

Resolution requires acquiring the source per the `dependency-source-acquisition` skill's ghq flow, as a Category-2 reference repository:

```
ghq get https://github.com/nix-community/nixos-anywhere
```

## Open risks

### The linear binding is unverified

The registry entry in `openspec/linear.yaml` records `id: "48b4123d589b"`, which is the project slug fragment supplied at bind time rather than a verified Linear project UUID; the sibling `cognee-memory-layer` entry carries a UUID.
The existing bound changes also disagree on `linear_story_id`: `apm-skills-marketplace` uses the identifier `CAM-30` while `declarative-cognee-endpoint` uses a UUID.
This change follows the identifier form.
Both must be reconciled before the archive-time document upsert, which resolves by id.

### Regeneration stays broken until nixos-facter#672 merges

Consuming a static report is not blocked and nothing in the evaluation path needs a facter binary.
Regenerating one is blocked, including via `clan machines update-hardware-config`.
This is worth documenting rather than solving; the PR is open and mergeable and fixes an issue filed against this exact model.

### `base`'s cloud-VM initrd assumptions are overridden per-machine, not corrected

`modules/system/initrd-networking.nix` puts initrd SSH on port 2222 and `virtio_pci`/`virtio_net` into every NixOS machine.
On pyrite the virtio modules are inert and the SSH server cannot function, because `brcmfmac` will not associate in initrd.
Leaving the SSH server enabled is arguably worse than inert: it advertises a remote-unlock path that cannot work.
Gating the module behind an option is the correction and touches five machines; this change takes the per-machine override and leaves the correction to a separate change, which means the next bare-metal host rediscovers this.
The virtio half is not overridden at all, for the reason the invariant above gives.

### `hardware-configuration.nix` must never be created

clan-core warns when it coexists with a facter report, and `nixos-generate-config` on this machine misdetects the WiFi as b43 — the same misdetection the profile carries, arriving by a second route.
The machine's configuration must not be seeded from its output.

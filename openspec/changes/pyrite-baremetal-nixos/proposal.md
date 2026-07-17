---
linear_story_id: CAM-32
linear_story_identifier: CAM-32
linear_story_title: "Bare-metal install path for the vanixiets clan"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-32
linear_story_state: Backlog
linear_team: CAM
linear_project: pyrite-baremetal-nixos
last_synced_state: Backlog
last_synced_at: "2026-07-16T00:00:00Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-07-16T00:00:00Z", transition: "Backlog->Todo", outcome: "dropped", note: "artifacts authored offline; T1 bind not posted (no network in authoring session)." }
---

## Why

Every NixOS machine in this fleet is a cloud VM provisioned by terranix, supplying its existence, an IPv4, a DNS record, and the repository's only recorded `clan machines install` invocation.
pyrite is an Apple MacBookPro14,1 with none of those, and no install path here avoids terranix.
CAM-31's live recon established the hardware surface and disproved the firmware-extraction risk that gated wiping macOS.
pyrite is wanted as a working laptop, not a demonstration: a full laptop hardware surface, encrypted at rest, usable away from the mesh and from a build host.
Travel-readiness is the acceptance criterion; test-bench tolerance holds only during construction.
Reaching it takes several installs, not one, which makes the install path the durable deliverable and a one-off manual sequence unacceptable.
This change adds the machine and, more durably, the re-runnable bare-metal install path — the reusable half of the epic, inherited by every future physical machine.

## What Changes

**The pyrite machine module**
- From: no bare-metal NixOS machine exists; `nixos-hardware` is not a flake input.
- To: `modules/machines/nixos/pyrite/` defines the host, importing `nixos-hardware.nixosModules.apple-macbook-pro-14-1` with `networking.enableB43Firmware` and `hardware.facetimehd.enable` set false.
- Reason: the profile supplies the stage-1 `applespi` initrd module list that makes a passphrase prompt on the internal keyboard work, and the `i915` that renders it; the two disabled pulls are firmware this machine has no use for — b43 serves BCM43xx silicon it does not have, and facetimehd drives a camera that is out of scope. Neither is declined for being unfree, and the machine separately affirms the redistributable firmware its only NIC needs.
- Impact: additive. `nixos-hardware` is a new flake input; no existing machine imports the profile.

**Encrypted ZFS root**
- From: no machine in this repository encrypts a disk by any mechanism.
- To: `modules/machines/nixos/pyrite/disko.nix` declares a ZFS `zroot` pool with `options.ashift = "12"` and an `EF00`-typed ESP, on a namespace-explicit `/dev/disk/by-id` path, whose `root` dataset uses native `aes-256-gcm` encryption with `keyformat = "passphrase"` — created from a clan `neededFor = "partitioning"` vars generator and flipped to `keylocation = "prompt"` by a `postCreateHook`, so every boot prompts on the internal keyboard.
- Reason: ZFS-on-root matches the fleet's five other NixOS machines and the two encrypted laptops of a clan-core developer; the create-then-flip idiom is disko's own documented mechanism and keeps the install non-interactive and re-runnable; `ashift = "12"` is mandatory on this disk's 4096-byte logical sectors; `type = "EF00"` is mandatory because disko defaults to `8300` and Apple's EFI discovers the ESP by type; the namespace-explicit path is mandatory because the controller exposes an 8 KiB second namespace sharing a by-id prefix.
- Impact: pyrite is the fleet's first encrypted machine. The encryption layer has no in-repo precedent. LUKS is not used at any layer. The accepted cost is that ZFS has one key per encryption root: no recovery passphrase, no TPM/FIDO2 path, and unencrypted dataset metadata.

**A bare-metal install path**
- From: the only recorded install invocation lives in `modules/terranix/{hetzner,gcp}.nix` as a `null_resource` local-exec.
- To: a documented, re-runnable procedure that wipes the disk explicitly and then targets a booted stock installer ISO with sshd, plus the hardware report committed as static data rather than regenerated on the target.
- Reason: `--update-hardware-config nixos-facter` fails on this machine with `unsupported bus type: Spi`; disko's destroy phase runs without `set -e`, so a failed destroy falls through to a create phase that will not clear the Apple GPT pyrite carries today; a one-off manual install is not an acceptable deliverable.
- Impact: additive; no cloud machine's path changes.

**Fleet registration**
- clan machine binding, inventory entry, sops bridge recipient, ZeroTier enrollment against cinnabar, and the post-install address records.

**Network association**
- From: every NixOS machine in the fleet is a cloud VM with a wired interface; no machine enables NetworkManager, and clan-core's wifi service is unused.
- To: `modules/clan/inventory/services/wifi.nix` instances clan-core's first-party wifi service for pyrite against a dedicated fleet SSID this repository stands up, whose SSID and PSK become sops-encrypted clan vars prompted by `clan vars generate pyrite` alongside the disk passphrase. The household network's PSK is not committed; if pyrite joins that network it associates interactively through `nmcli`.
- Reason: the install path is re-runnable and its first step `blkdiscard`s the disk, so credentials entered interactively on the machine die on every re-install — and worse, they would turn the post-install association check into a step that produces its own result rather than a test that can fail. Credentials held as clan vars are repository state and survive the wipe. Which credentials may be held that way is decided by origination: this repository commits secrets it originates, as clan-infra does for the disk keys it generates and Mic92 does for his own access point's key, and withholds secrets it borrows, as Mic92 does for every network his laptops merely join. A fleet SSID is originated; the household network is not.
- Impact: pyrite becomes the fleet's first NetworkManager host, which brings the nixpkgs module's transitive effects with it — `networking.useDHCP` forced false, wpa_supplicant enabled under NetworkManager's control, and a modemmanager `mkDefault` on a laptop with no WWAN radio. It also adds an operator prerequisite outside the repository: the router must serve the fleet SSID before the vars can be generated. `share = true` on the credential generator is not overridable, which is the intent rather than a cost, since the fleet SSID exists to serve the fleet; it does not widen the recipient set, and its one residual is that a network's attribute name is a clan-wide identity, so a machine on a different network takes a differently-named network. clan-core's zerotier `unmanaged` rule becomes live and is correct as written.

**Graphical desktop**
- From: no NixOS machine in this fleet runs a graphical session; every one is a headless cloud VM.
- To: the pyrite host module enables a stock GNOME desktop under GDM with two system options (`services.displayManager.gdm.enable` and `services.desktopManager.gnome.enable`), the pair nixpkgs seeds into `nixos-generate-config`.
- Reason: a travel laptop's primary interface is its own screen; GNOME under GDM was proven on this exact hardware from the installer ISO, is two lines rather than niri's roughly-twelve-component assembly, and is the recovery floor on a machine recoverable only by an ISO reflash.
- Impact: system-level only — cameron's home-manager is already imported and a stock GNOME session needs nothing from it. niri is the eventual daily-driver target and is deferred to a reversible follow-up deployed via `clan machines update`; it is not in this change.

Audio is out of scope: the only out-of-tree module carrying the CS8409 amplifier init tops out below this repository's pinned kernel, and pinning the kernel backward for audio is ruled out.
If mainline lands that init, sound arrives on a routine kernel bump at no cost; the hardware inventory note carries it as an upstream watch-item.
Hibernation is deferred, which is what makes keeping `base`'s `boot.zfs.forceImportRoot = true` costless here.
Suspend/resume (the `d3cold` workaround) and the correction of `base`'s cloud-VM initrd assumptions are both out of scope and left to separate changes.

## Capabilities

### New Capabilities
- `apple-laptop-hardware-support`: how a MacBookPro14,1 is configured as a NixOS host — `nixos-hardware.nixosModules.apple-macbook-pro-14-1` imported with its b43 and facetimehd pulls declined on redistributability rather than freeness, while `hardware.enableRedistributableFirmware` and `hardware.cpu.intel.updateMicrocode` are affirmed explicitly rather than inherited from a facter branch this fleet has never evaluated; the four SPI/SMC modules the profile force-loads into stage 1 to make the passphrase prompt answerable, and the standing prohibition on `mkForce`-ing `boot.initrd.kernelModules` that protects them and both `i915` definitions; the two daemons the profile starts; the USB-C keyboard as a first-boot prerequisite rather than an improvised recovery; and the bar on ever seeding the machine from `nixos-generate-config`.
- `encrypted-zfs-root`: how a natively-encrypted ZFS root is declared for bare metal — a `zroot` pool with an explicit `ashift = "12"` matching the disk's 4096-byte sectors, on a namespace-explicit `/dev/disk/by-id` path that names the namespace rather than a prefix shared with an 8 KiB one, an `EF00`-typed 1G ESP beside the sibling partition that becomes the pool's vdev, and a `root` dataset carrying `aes-256-gcm` with `keyformat = "passphrase"` created from a clan `neededFor = "partitioning"` generator and flipped to `keylocation = "prompt"` by a `postCreateHook` so the boot is self-sufficient; `hostId` inherited and `forceImportRoot` kept as decisions rather than inheritances; and the one-key-per-encryption-root costs recorded rather than discovered later.
- `bare-metal-install-path`: how a machine with no terranix entry is installed and registered — a recorded, re-runnable `clan machines install` against a booted stock installer ISO, preceded by a `blkdiscard` that must not be a GPT zap, and demonstrated by a second install that exercises the create path rather than one that reuses a surviving pool; the hardware report committed as static data, never regenerated on the target, and landed atomically with the module because clan-core `readDir`-scans `machines/`; registration across every hand-maintained list a new machine touches; declarative network association through clan-core's wifi clanService, with origination as the test admitting the committed credential and withholding the borrowed one; and ZeroTier admission through an explicit controller redeploy.
- `graphical-desktop-session`: how pyrite provides a local graphical desktop — a stock GNOME session under GDM enabled by the two system options nixpkgs seeds into `nixos-generate-config`, system-level with no home-manager desktop configuration because the admin user's home-manager is already imported and a stock GNOME session needs nothing from it; the graphical login proven on this exact hardware from the installer ISO rather than inferred, with `systemctl is-active display-manager` recorded as necessary-but-insufficient so acceptance rests on a rendered greeter and a reached interactive shell; the stage-1 ZFS passphrase prompt shown independent of GDM because a display manager is a stage-2 unit that touches no initrd path and enables no plymouth; and niri named as the eventual daily-driver target but deferred to a reversible follow-up so the irreversible wipe carries only the measured desktop.

### Modified Capabilities
<!-- None. `openspec/specs/` does not exist, so all four capabilities above are new; no existing capability's requirements change. -->

## Impact

Files added: `modules/machines/nixos/pyrite/{default.nix,disko.nix}` and `modules/clan/inventory/services/wifi.nix` (import-tree discovers both; no import line is added), plus `machines/pyrite/facter.json` — which must land in the same commit as the module and the registrations, never before them, because clan-core `readDir`-scans `machines/` and the bare directory materializes a `nixosConfigurations.pyrite` with no filesystems and no boot loader.
Files updated: `modules/clan/machines.nix`, `modules/clan/inventory/machines.nix`, `modules/clan/inventory/services/users/cameron.nix`, both hardcoded lists in `modules/checks/structure/flake-shape.nix`, `.sops.yaml` (the `&pyrite` anchor and the `secrets/bridge/.*` rule), and `modules/machines/nixos/cinnabar/zt-dns.nix` (the `/pyrite.zt/<address>` record).
`nixos-hardware` becomes a new flake input: it appears in neither `flake.nix` nor `flake.lock` today, so this change owns both its addition and its lock entry.
pyrite becomes the fleet's first bare-metal machine, its first encrypted root, and its first NetworkManager host — each a first for this repository rather than for nixpkgs, and the NetworkManager module's transitive effects arrive with it.
Two effects reach past pyrite: the wifi service's `share = true` makes the fleet SSID's credential a clan-wide identity that any future wireless machine takes by name, and cinnabar is redeployed twice, once to admit the ZeroTier peer and once for the `.zt` record.
One prerequisite lives outside the repository: the operator must stand up the fleet SSID on the router before `clan vars generate pyrite` can be answered.
No cloud machine's install path changes, and `modules/clan/inventory/services/tor.nix`'s `nixos` selector is deliberately left alone.
Out of scope: audio, suspend/resume and the `d3cold` workaround, hibernation, a terranix entry for pyrite, and correcting `base`'s cloud-VM initrd assumptions for the fleet — pyrite overrides those per-machine and the correction touches five machines in its own change.

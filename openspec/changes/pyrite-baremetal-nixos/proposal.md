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
  - { at: "2026-07-16T00:00:00Z", transition: "Backlog->Todo", outcome: "deferred", note: "artifacts authored offline; T1 bind not posted (no network in authoring session). Linear story UUID and project id unverified — see linear.yaml comment and design.md open risks." }
---

## Why

Every NixOS machine in this fleet is a cloud VM provisioned by terranix, which supplies machine existence, an IPv4, a DNS record, and the only recorded `clan machines install` invocation in the repository.
pyrite is an Apple MacBookPro14,1 with none of those, and the repository has no install path that does not route through terranix.
CAM-31 established the hardware surface by live recon and disproved the firmware-extraction risk that gated wiping macOS.
This change adds the machine and, more durably, the bare-metal install path itself, written to be re-runnable rather than performed once by hand.

## What Changes

**The pyrite machine module**
- From: no bare-metal NixOS machine exists; `nixos-hardware` is not a flake input.
- To: `modules/machines/nixos/pyrite/` defines the host, importing `nixos-hardware.nixosModules.apple-macbook-pro-14-1` with `networking.enableB43Firmware` and `hardware.facetimehd.enable` set false.
- Reason: the profile supplies the stage-1 `applespi` initrd module list that makes a passphrase prompt on the internal keyboard work, and the `i915` that renders it; the two disabled pulls are unwanted unfree firmware, one of them a misdetection for this silicon.
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

**Tor selector narrowed**
- From: `modules/clan/inventory/services/tor.nix` selects `roles.server.tags."nixos"`.
- To: it names the five cloud hosts explicitly.
- Reason: the `nixos` tag also carries sshd's host keys and CA certificates and so cannot be dropped from pyrite, but the tor server role publishes an onion service exposing sshd over Tor — not a relay, but not wanted on a laptop that travels.
- Impact: the five cloud hosts' behaviour is unchanged; a future NixOS machine must be named to gain the service.

Audio is out of scope by binding decision and is not a deferred work item.
Hibernation is deferred, which is what makes keeping `base`'s `boot.zfs.forceImportRoot = true` costless here.
Suspend/resume (the `d3cold` workaround) and the correction of `base`'s cloud-VM initrd assumptions are both out of scope and left to separate changes.

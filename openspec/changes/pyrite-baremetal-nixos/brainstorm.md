<!--
Raw capture of the pyrite-baremetal-nixos design exploration.
Decision-log format: background -> decision chain Q1-Qn -> design trade-offs.
design.md reorganizes this content into structured sections; do not copy this file into design.md.
-->

# Brainstorm: pyrite-baremetal-nixos

## Background

The vanixiets fleet has nine machines: four nix-darwin laptops and five NixOS cloud VMs.
Every NixOS machine ever created in this repository is a cloud VM — `git log --all --diff-filter=A --name-only -- 'modules/machines/nixos/*'` yields cinnabar, electrum, galena, magnetite, scheelite, and a deleted gcp-vm, and nothing else.
Every hardware assumption in the shared layers is therefore untested on physical hardware.

pyrite is an Apple MacBookPro14,1 (2017 13-inch, non-Touch-Bar) that would be the fleet's first bare-metal NixOS machine.
Live reconnaissance on 2026-07-16 (CAM-31) established the hardware surface; `docs/notes/development/hardware/pyrite-hardware-inventory.md` records it.
The decisive observations are that the machine boots external media with no firmware password, that WiFi firmware loads from stock nixpkgs with no extraction from macOS, and that the internal keyboard is live under mainline `applespi`.
Together these make a single-boot wipe of macOS safe and a stage-1 passphrase prompt viable.

The machine's posture is a full laptop hardware surface with test-bench tolerance during construction and travel-readiness as the acceptance criterion.
The install path is expected to run repeatedly rather than once, which rules out a one-off manual install as the deliverable.

## Decision chain

### Q1 — Is the wipe of macOS safe?

The gating risk was firmware extraction: if any component's firmware came from the local macOS install, wiping macOS would be irreversible in a way that matters.
It does not.
WiFi firmware ships in `linux-firmware` redistributably and was observed loading from the stock ISO.
Bluetooth needs no blob to enumerate.
The camera's firmware, if ever wanted, is fetched from Apple's CDN rather than from the local disk.

Decision: single-boot NixOS, macOS wiped.
The risk that gated this is disproven, not accepted.

### Q2 — Filesystem and encryption

Two candidates: ZFS with native encryption, or ext4 on LUKS.

The original argument for ZFS was that the fleet's base module forces `boot.zfs.forceImportRoot = true`, implying ZFS is already fleet convention, so a non-ZFS machine would fight the shared layer.
Adversarial verification refuted that argument.
`boot.zfs.forceImportRoot` is declared unconditionally in nixpkgs and is inert on a machine with no pool; clan-core sets it to `lib.mkDefault false` unconditionally while gating `services.zfs` behind `config.boot.zfs.enabled` in adjacent lines, which is exactly the distinction the argument elides.
The setting proves nothing about whether ZFS is used.

The conclusion survives on evidence the original argument never cited: all five NixOS machines root on ZFS via disko with a `zroot` pool, and none has a non-ZFS root.
ZFS-on-root is genuinely the convention.

What does not survive is any claim that ZFS *encryption* is conventional here.
No machine in this repository encrypts a disk by any mechanism — not LUKS, not ZFS native.
pyrite is the fleet's first encrypted machine either way, so the encryption layer has no in-repo pattern to copy regardless of which is chosen.

Decision: ZFS with native encryption.
The rationale is filesystem consistency with the five other NixOS machines, exact parity with the two encrypted laptops belonging to a clan-core developer, and disko's own attestation of the mechanism — not encryption precedent in this repository, of which there is none.

### Q3 — Key delivery: passphrase prompt or keyfile?

clan-infra's pattern is a `clan.core.vars.generators.zfs` with `files.key.neededFor = "partitioning"`, consumed as `keylocation = "file://<vars path>"`, with the key routed to the target by `clan machines install --disk-encryption-keys`.
Read off `web01`, that pattern looks like it is designed for a headless server that unlocks over initrd SSH on port 2222, and therefore like something a laptop must diverge from.

pyrite is a laptop.
Its only NIC is `brcmfmac` WiFi, which will not associate in initrd, so remote unlock is not a plan — the operator is physically at the keyboard.
Recon confirmed the internal keyboard is live under `applespi`, and adversarial verification confirmed end to end that the module closure builds at the pinned kernel and that the ZFS initrd prompt reaches the console with an unbounded timeout.

Decision: passphrase prompt at initrd — and, as Q4 shows, this does not require diverging from clan's keyfile channel at all.
The two are different phases of the same install, not competing designs.

### Q4 — How does a passphrase reach disko during a non-interactive install?

This was the question that briefly derailed the whole design, and it has a clean answer.

Framed wrongly, it reads: `keylocation = "prompt"` is applied at dataset *create* time, so disko emits `zfs create -up ... -o keylocation=prompt`, which reads from stdin during a phase `clan machines install` drives over ssh; re-runnability collides with an interactive prompt mid-automation; ZFS native encryption therefore cannot do this and LUKS, whose `luksFormat` reads a `passwordFile`, is the only mechanism left.
That framing produced a LUKS recommendation, and it rests on a false premise.

The premise is false because `keylocation` is not fixed at create time.
Disko's `onetimeProperties` list names `encryption`, `keyformat`, `pbkdf2iters`, and others — the properties ZFS marks `PROP_ONETIME` — and `keylocation` is deliberately not among them.
So the dataset is created from a keyfile like any clan machine, and a `postCreateHook` running `zfs set keylocation="prompt"` flips it afterward.
Disko documents exactly this in its own encrypted-root example.
The key material never changes; only where ZFS looks for it does.
That is precisely what LUKS's `passwordFile` does, so LUKS's supposed advantage evaporates.

The flip is not merely permitted, it is required: the `/run/partitioning-secrets/...` path the keyfile lives at exists only during the install, because nixos-anywhere puts it there. It is gone at boot.
web01 does not flip because a separate initrd unit supplies its key from elsewhere — a server posture, and reading pyrite's requirements off it was the error.

One correction to the keyfile's *content*: web01 generates hex via `dd if=/dev/urandom | xxd`, which is unusable by a person at a boot prompt. clan-infra's `build01` generates `xkcdpass --numwords 6` for its LUKS passphrase, and that is the right shape here — only its consumer differs.

Decision: settled. Create from a `neededFor = "partitioning"` vars generator emitting a human-typeable passphrase, flip to `prompt` in a `postCreateHook`. No spike required; the mechanism is documented upstream and idempotent on re-run.

### Q4b — What does choosing ZFS native encryption cost?

The costs are structural, not configuration defects, and they were accepted with the decision.

ZFS permits exactly one key per encryption root. `zfs change-key` replaces the key; it cannot add a second.
So there is no recovery passphrase and no escrow key: lose the passphrase, lose the pool.
There is also no future path to unlocking by TPM or FIDO2 token via `systemd-cryptenroll`, because that operates on LUKS keyslots and ZFS has none.
And ZFS native encryption does not encrypt pool layout, dataset names, or snapshot names; an attacker with the disk learns the structure, just not the contents.

LUKS would have offered all three — multiple keyslots, a recovery passphrase, and a cryptenroll path.
That is the real trade, and it is a different trade from the one the false premise described.

### Q5 — nixos-hardware profile, or hand-copied module list?

The profile supplies `boot.initrd.kernelModules = [applespi spi_pxa2xx_platform intel_lpss_pci applesmc ...]` under a comment naming stage-1 keyboard support, which is precisely the load-bearing content.
Against that, importing it drags in three things this machine does not want: a `b43Firmware` pull for silicon it does not have, `facetimehd` auto-enabled because the fleet sets `allowUnfree = true` globally, and `mbpfan`.
Both b43 and facetimehd firmware are unfree and therefore absent from binary caches, which surfaced as a real remote-builder signature failure during verification.

Decision: import the profile, and set `networking.enableB43Firmware = false` and `hardware.facetimehd.enable = false`.
Both upstream values are `lib.mkDefault`, so a plain `false` overrides each; `mkForce` is unnecessary.
Rationale: the profile is upstream's record of this exact model, and hand-copying its initrd list duplicates upstream for no benefit.

The alternative — setting the four SPI modules directly and skipping the profile — is rejected outright rather than held as a fallback.
`i915` reaches initrd only through the profile's import chain, and without `i915` there is no framebuffer console to display the passphrase prompt.
A hand-copied list that drops it evaluates and builds cleanly and produces an invisible prompt.

### Q6 — Disk device path

The device must be named explicitly, because the controller exposes an 8 KiB second namespace at `nvme0n2` whose by-id name shares a prefix with the real disk's.

Decision: `/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1`, the namespace-explicit form, and `boot.zfs.devNodes = "/dev/disk/by-id"` rather than the `by-path` every cloud machine uses.

### Q7 — Audio

Out of scope, and not a deferred work item.
Recorded in the hardware inventory note as a hardware fact and an upstream watch-item.

### Q8 — Does the `nixos` tag make pyrite a Tor relay?

A claim in circulation held that tagging `nixos` auto-enrolls the machine as a Tor relay.
Checked against clan-core at the pinned revision and against nixpkgs, the mechanism is real but the characterization is wrong.
The tag does select the tor server role, and that role publishes a v3 onion service exposing sshd over Tor — but it is not a relay: `services.tor.relay.enable` is a separate option defaulting false, and nothing forwards other people's traffic.

The tag cannot simply be dropped, because sshd's server and client roles select on the same tag and dropping it forfeits host keys and CA certificates.

Decision: change tor.nix's selector from the `nixos` tag to an explicit list of the five cloud hosts.
An always-on daemon publishing a travelling laptop's ssh endpoint to Tor is not wanted, even though it is not a relay.

## Design trade-offs and consequences

Choosing ZFS buys filesystem consistency with the fleet's five other NixOS machines, parity with the closest available precedent (a clan-core developer's two encrypted laptops, both ZFS-native with a typed passphrase), and a mechanism disko documents itself.
It costs the LUKS keyslot features enumerated in Q4b: no second key, no recovery passphrase, no cryptenroll path, and unencrypted dataset metadata.
Choosing a passphrase prompt costs nothing structural, because the create-from-keyfile-then-flip idiom keeps the clan-native keyfile channel intact — Q4's bill turned out to be a misreading.
Choosing the nixos-hardware profile buys upstream's model-specific knowledge, including the `i915` the prompt depends on, and costs two `false` lines plus an inherited maintenance dependency on a profile whose last model-specific attention was in 2024.

The fleet's shared `base` module carries two cloud-VM assumptions that pyrite inherits and neither of which functions on it: initrd SSH on port 2222, and `virtio_pci`/`virtio_net` in initrd.
Gating that module behind an option would be the correction; a per-machine override is the smaller change.
This change takes the smaller path and records the correction as out of scope.

## Context

A14 evidence is retained in `logs/pyrite-audio-driver-compatibility-20260911.md` and its build, source, ABI-layout and selection logs.
The exact native kernel derivation is `/nix/store/lz7dqdkakglc1f0ksh8vkd1bsd5cfdhs-linux-6.18.42.drv`.
Upstream's `patch_cs8409.c.diff` dispatches unmatched Apple codecs to its handler; `patch_cirrus/cirrus_apple.h` explicitly accepts `106b3300`.
The default `use_data=0` selects real configuration, including CS42L83 and SSM3 initialization, rather than optional data replay.
These source observations establish the intended initialization route, not its runtime success on pyrite.

## Goals and non-goals

Build a reproducible, kernel-scoped Apple replacement and select it through standard NixOS module aggregation.
Preserve the kernel and unrelated machine state.
Do not load a module, activate, alter mixers, play or record sound, change power management, or modify amplifier programming.
Do not claim microphone support, reliable headphone routing, suspend correctness, Apple-equivalent DSP or safe maximum volume.

## Decisions

### Package and upstream boundary

Keep the package outside the auto-imported `modules/` tree at `pkgs/kernel-modules/snd-hda-macbookpro.nix`.
Instantiate it with `config.boot.kernelPackages.callPackage`, not the global package set's unrelated kernel.
Pin upstream with fixed-output hash `sha256-5iDybAlRG5HldUA24L9+rSlgEiUPZg50K8IYC+Lie4U=` and leave the lockfile unchanged.
Extract the selected kernel's `sound/hda`, overlay upstream's restricted Makefiles and six Apple headers, and apply only its existing 6.17+ C/header patches with zero fuzz.
Never invoke the upstream installer, DKMS or root installation target.

The initial support boundary is deliberately Linux 6.18.42 only.
A kernel update must revalidate internal layout, source/config matching, symbol coverage and module selection before widening that guard.
Compare `generic.h` and `hda_auto_parser.h` against the selected kernel's prepared source headers to address the mismatch mechanism reported in upstream issue 193.
Assert upstream's normal Apple compiler flags, HDA modular configuration and RECONFIG setting.
Optional microphone-only, data-replay and debug flags remain disabled.

### Delivered ELF boundary

Strip debug information, not the module's required symbols, and disable patchelf for relocatable ELF.
Check undefined symbols against the selected kernel's `Module.symvers` after stripping and reject retained kernel.dev references.
Retain a source SHA256 manifest without source-store path references.
A14's full native BTF versus diagnostic DWARF comparison remains supporting evidence; matching final compiled-source hashes connects the stripped product to that checked source, not to the old binary hash.
The exact kernel has neither MODVERSIONS nor module signing enabled; metadata and MODPOST do not provide those protections.

### Loader boundary

Install the replacement under `lib/modules/${kernel.modDirVersion}/updates/codecs/cirrus`, leaving the native `kernel/sound/hda/codecs/cirrus` path intact.
Use NixOS's actual full `system.modulesTree`, including ZFS and any other configured extra modules, for name/alias and dependency checks.
Do not blacklist the shared name, disable the native kernel option, remove native files or add depmod precedence overrides.
Inspect the candidate initrd without making audio initrd-required for the sake of a test.
If it contains audio, verify it cannot preload the native CS8409 before root-stage selection.

## Risks and later rollout

Upstream's README warns that direct `hw:0,0` and `plughw:0,0` playback has no volume control and can be very loud.
The driver lacks Apple's speaker DSP filtering and changes the effective gain/control path; previous native PCM and PipeWire settings are not a calibrated safety baseline.
Upstream issue 211 discusses possible damage during related-board experiments without establishing it; none of its gain, format or register experiments is included.

Before any activation, binding or reboot into the candidate, the parent and operator must agree a no-startup-sound policy covering the greeter, desktop, notifications, browsers and restored media sessions.
Prepare and verify the software-volume route while sound producers are quiescent; use the PipeWire-managed output, not raw ALSA, and verify its mute/low gain after the replacement appears and before opening a stream.
For a later explicitly authorized first playback, use a short, pre-attenuated test asset with a verified peak amplitude (for example at most -60 dBFS), a separately verified low software-volume setting, and an operator-controlled immediate stop.
These are conservative starting controls, not a proven safe amplitude for this uncalibrated speaker system; do not infer safety from slider percentages or test full volume.
No muting, profile override or playback action is performed by this implementation or its checks.

Keep `snd_hda_intel` power_save=10 and controller=Y unchanged.
The different-board issue 209 does not establish a pyrite defect; test controller power management separately after basic acceptance.
Issue 199 records unresolved jack-event/routing limitations; headphone and power tests remain separate.
The parent owns normal checked-source jj/just/clan deployment, a verified prior-generation recovery path, and operator-coordinated reboot with the known warm-reboot/network caveats.
Live module reload is not an alternative.

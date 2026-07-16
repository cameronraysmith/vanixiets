## ADDED Requirements

### Requirement: The pyrite host module imports the upstream model profile with its unwanted firmware pulls disabled

The pyrite host module SHALL import `nixos-hardware.nixosModules.apple-macbook-pro-14-1`, which requires adding `nixos-hardware` as a flake input declaring `inputs.nixpkgs.follows = "nixpkgs"`.
The module MUST set `networking.enableB43Firmware = false` and `hardware.facetimehd.enable = false`.
No `allowUnfree` setting is required for this machine's networking, and none SHALL be added for that purpose.

#### Scenario: plain false suffices because both upstream values are mkDefault

- **WHEN** `nixos-hardware`'s `apple/macbook-pro/14-1/default.nix:50` sets `networking.enableB43Firmware = lib.mkDefault true` and `apple/default.nix:4` sets `hardware.facetimehd.enable = lib.mkDefault (config.nixpkgs.config.allowUnfree or false)`
- **THEN** a plain `false` definition overrides each at normal module-system priority
- **AND** `lib.mkForce` is NOT used, because the claim that values arriving from inside an imported profile cannot be declined at the import site is false — priority resolution does not depend on where a definition originates — and `mkForce` would additionally suppress any future legitimate override

#### Scenario: b43 is disabled as a correction for foreign silicon

- **WHEN** the profile pulls the unfree `b43Firmware` package
- **THEN** the module sets it false, because the machine's WiFi is a BCM4350 driven by `brcmfmac` from redistributable `linux-firmware` and b43 firmware is for entirely different silicon
- **AND** this is a correction rather than an evaluation workaround, because `modules/nixpkgs/base-defaults.nix:23` already sets `allowUnfree = true` fleet-wide so the pull would evaluate successfully

#### Scenario: facetimehd is disabled before the fleet's global allowUnfree auto-enables it

- **WHEN** the fleet's global `allowUnfree = true` would resolve the profile's `mkDefault` to true
- **THEN** the module sets it false, so no out-of-tree kernel module or unfree camera firmware enters the closure

#### Scenario: unfree firmware absent from the closure keeps the install buildable from the darwin admin box

- **WHEN** an install is driven from stibnite through a remote linux builder
- **THEN** the build succeeds, because unfree firmware is absent from binary caches and would otherwise have to be built locally and pushed, which fails a store-path signature check on the remote builder

#### Scenario: the profile is imported rather than replaced by a hand-copied module list

- **WHEN** an alternative of setting the four SPI initrd modules directly and skipping the profile is considered
- **THEN** it is rejected rather than held as a fallback, because `i915` reaches the initrd only through the profile's import chain (`apple/macbook-pro/14-1` imports `common/cpu/intel/kaby-lake`, reaching `common/gpu/intel`, whose `default.nix:90` adds the driver to `boot.initrd.kernelModules`)
- **AND** dropping `i915` would remove the framebuffer console that renders the passphrase prompt, producing a configuration that evaluates and builds cleanly but whose prompt is invisible

---

### Requirement: The stage-1 initrd carries the SPI input modules that make the passphrase prompt reachable

The initrd SHALL force-load `applespi`, `spi_pxa2xx_platform`, and `intel_lpss_pci` via `boot.initrd.kernelModules`, which the imported profile supplies.
The facter report MUST NOT be relied upon for these, and the fleet's `base` module MUST NOT be relied upon for these.

#### Scenario: the profile supplies the modules that base does not

- **WHEN** `modules/system/initrd-networking.nix:33-37` contributes only `virtio_pci` and `virtio_net` to `boot.initrd.kernelModules` for every NixOS machine
- **THEN** the SPI modules arrive from the imported profile instead, which sets `boot.initrd.kernelModules` — the option that force-loads — rather than `availableKernelModules`, which only makes a module present

#### Scenario: facter supplies no SPI keyboard modules

- **WHEN** the committed facter report is evaluated
- **THEN** it contributes no `applespi` or `intel_lpss` initrd modules, because `nixos/modules/hardware/facter/keyboard.nix` sources initrd keyboard modules from the USB controller report only and the keyboard on this machine is SPI-attached

---

### Requirement: boot.initrd.kernelModules is never overridden with mkForce

The pyrite host module MUST NOT set `boot.initrd.kernelModules` with `lib.mkForce`.
The virtio entries `base` contributes SHALL be left in place.

#### Scenario: mkForce on the module list is a lockout, not a cleanup

- **WHEN** the intent is to drop `base`'s cloud-VM `virtio_pci` and `virtio_net` entries, for which `lib.mkForce [ ... ]` is the natural-looking mechanism
- **THEN** it MUST NOT be used, because the option accumulates from four sources — `base`'s virtio pair, the profile's `applespi`/`spi_pxa2xx_platform`/`intel_lpss_pci`/`applesmc`, `common/gpu/intel`'s `i915`, and facter's `brcmfmac` — and `mkForce` discards every definition it does not name
- **AND** the resulting configuration would evaluate cleanly, build cleanly, and boot to a passphrase prompt that is invisible or unanswerable, on a machine with no macOS to fall back to
- **AND** the virtio entries are left alone because on bare metal they modprobe, find no matching device, and cost a few kilobytes of initrd

#### Scenario: initrd SSH is disabled without touching the module list

- **WHEN** `base` enables `boot.initrd.network.ssh` on port 2222 for remote unlock
- **THEN** pyrite overrides that option specifically, because its only NIC is `brcmfmac` WiFi which will not associate in initrd, and an advertised remote-unlock path that cannot function is worse than none
- **AND** this is a distinct option from `boot.initrd.kernelModules` and requires no list override

---

### Requirement: A USB-C keyboard is a prerequisite of the first boot, not a recovery improvised afterward

The runbook SHALL state that a USB-C keyboard or a USB-C-to-USB-A adapter is on hand before the first boot after the install.

#### Scenario: the USB recovery path rests on udev autoloading, not force-loading

- **WHEN** an external keyboard is used to answer the passphrase prompt because the internal keyboard is not yet bound
- **THEN** it is recorded that `usbhid`, `hid-generic`, and `hid-apple` reach the initrd through `availableKernelModules` and udev autoloading rather than through the force-loading `boot.initrd.kernelModules`, so the path depends on udev probing the device rather than on an unconditional modprobe
- **AND** the prompt remains answerable in the ordinary case because the ZFS initrd unit requests credentials with an unbounded timeout

#### Scenario: the machine has no USB-A port

- **WHEN** the recovery keyboard is selected
- **THEN** the runbook states that a MacBookPro14,1 has USB-C ports only, so a USB-C keyboard or an adapter must be physically present before the wipe rather than sourced after a failed boot

---

### Requirement: The machine's configuration is never seeded from nixos-generate-config

A `machines/pyrite/hardware-configuration.nix` MUST NOT be created.

#### Scenario: hardware-configuration.nix is never created

- **WHEN** hardware facts are needed for the machine
- **THEN** they come from the committed facter report only, because clan-core warns when `hardware-configuration.nix` coexists with a facter report, and `nixos-generate-config` on this machine misdetects the WiFi as b43 and would import `broadcom-43xx.nix`

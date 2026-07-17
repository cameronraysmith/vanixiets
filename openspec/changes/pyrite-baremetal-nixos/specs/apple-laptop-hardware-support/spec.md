## ADDED Requirements

### Requirement: The pyrite host module imports the upstream model profile with its unwanted firmware pulls disabled

The pyrite host module SHALL import `nixos-hardware.nixosModules.apple-macbook-pro-14-1`, which requires adding `nixos-hardware` as a flake input declaring `inputs.nixpkgs.follows = "nixpkgs"`.
The module MUST set `networking.enableB43Firmware = false` and `hardware.facetimehd.enable = false`.
No `allowUnfree` setting is required for this machine's networking, and none SHALL be added for that purpose.

#### Scenario: plain false suffices because both upstream values are mkDefault

- **WHEN** `nixos-hardware`'s `apple/macbook-pro/14-1/default.nix:50` sets `networking.enableB43Firmware = lib.mkDefault true` and `apple/default.nix:4` sets `hardware.facetimehd.enable = lib.mkDefault (config.nixpkgs.config.allowUnfree or false)`
- **THEN** a plain `false` definition overrides each at normal module-system priority
- **AND** `lib.mkForce` is NOT used, because the claim that values arriving from inside an imported profile cannot be declined at the import site is false — priority resolution does not depend on where a definition originates — and `mkForce` would additionally suppress any future legitimate override

#### Scenario: b43 is disabled for its silicon, not for its licence

- **WHEN** the profile sets `networking.enableB43Firmware = lib.mkDefault true`, which pulls `b43Firmware_5_1_138` (`nixos/modules/hardware/network/b43.nix:17,30`)
- **THEN** the module sets it false, because that firmware serves the older SoftMAC BCM43xx parts and this machine's WiFi is a BCM4350 driven by `brcmfmac`
- **AND** it is NOT disabled for being unfree, and this scenario is not evidence against `hardware.enableRedistributableFirmware`, which the firmware-affirmation requirement below sets true

#### Scenario: facetimehd is disabled before the fleet's global allowUnfree auto-enables it

- **WHEN** the fleet's global `allowUnfree = true` would resolve the profile's `mkDefault` to true
- **THEN** the module sets it false, so no out-of-tree kernel module or unfree camera firmware enters the closure

#### Scenario: non-redistributable firmware absent from the closure keeps the install buildable from the darwin admin box

- **WHEN** an install is driven from stibnite through a remote linux builder
- **THEN** no non-redistributable firmware is in the closure, so nothing has to be built locally and pushed as a store path signed by no trusted key
- **AND** the discriminating property is redistributability rather than freeness, since `linux-firmware` is proprietary, is `unfreeRedistributableFirmware`, and is fetched from a cache rather than built

#### Scenario: the profile is imported rather than replaced by a hand-copied module list

- **WHEN** an alternative of setting the four SPI initrd modules directly and skipping the profile is considered
- **THEN** it is rejected rather than held as a fallback, because `i915` reaches the initrd only through the profile's import chain (`apple/macbook-pro/14-1` imports `common/cpu/intel/kaby-lake`, reaching `common/gpu/intel`, whose `default.nix:90` adds the driver to `boot.initrd.kernelModules`)
- **AND** dropping `i915` would remove the framebuffer console that renders the passphrase prompt, producing a configuration that evaluates and builds cleanly but whose prompt is invisible

---

### Requirement: The machine module states its firmware affirmations rather than inheriting them

The pyrite host module SHALL set `hardware.enableRedistributableFirmware = true` and `hardware.cpu.intel.updateMicrocode = true`.
Both MUST be stated in the module rather than left to the `mkDefault` values facter's bare-metal branch supplies.
Neither SHALL be set false as an extension of the firmware pulls the profile-import requirement above declines, because those decline foreign silicon and an unwanted camera rather than firmware as such.
Every scenario below is decidable by `nix eval` against the built configuration; none requires the hardware.

#### Scenario: both values are true in the built configuration

- **WHEN** `nix eval .#nixosConfigurations.pyrite.config.hardware.enableRedistributableFirmware` and `nix eval .#nixosConfigurations.pyrite.config.hardware.cpu.intel.updateMicrocode` are evaluated
- **THEN** both return `true`
- **AND** they return `true` independently of facter's bare-metal detection, because the module's own definitions override the `mkDefault`s `nixos/modules/hardware/facter/firmware.nix` supplies, which is the point of stating them

#### Scenario: linux-firmware is in the machine's firmware closure

- **WHEN** `nix eval --json .#nixosConfigurations.pyrite.config.hardware.firmware --apply 'map (p: p.pname or p.name)'` is evaluated
- **THEN** the result contains `linux-firmware`, which `nixos/modules/hardware/all-firmware.nix:75` adds to `hardware.firmware` inside the config block `:71-86` that `enableRedistributableFirmware` gates
- **AND** that package is what carries the BCM4350's `brcm/brcmfmac4350-pcie.bin` and `brcm/brcmfmac4350c2-pcie.bin`, both listed in its `WHENCE` under `Driver: brcmfmac` with "Licence: Redistributable"

#### Scenario: b43 false and enableRedistributableFirmware true are consistent, not contradictory

- **WHEN** `nix eval .#nixosConfigurations.pyrite.config.networking.enableB43Firmware` is evaluated
- **THEN** it returns `false` while `hardware.enableRedistributableFirmware` returns `true`
- **AND** the two are consistent, because the discriminating property is redistributability and not freeness: `b43Firmware_5_1_138` is `lib.licenses.unfree`, evaluating to `{ free = false; redistributable = false; }`, and serves BCM43xx silicon this machine does not have, while `linux-firmware` is `unfreeRedistributableFirmware`, evaluating to `{ free = true; redistributable = true; }`, and carries the blob this machine's only NIC needs to probe

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

Hardware facts for pyrite SHALL come from the committed facter report.
A `machines/pyrite/hardware-configuration.nix` SHOULD NOT be created.
The strength is SHOULD NOT rather than MUST NOT because the ground — that clan-core warns when a `hardware-configuration.nix` coexists with a facter report — is recorded uncited and is tracked as an open risk in design.md; the previously-recorded second ground, that `nixos-generate-config` misdetects this machine's WiFi as b43, is false and is retracted there.

#### Scenario: the repository carries a facter report and no generated hardware module

- **WHEN** the machine's source tree is inspected after the change is applied
- **THEN** `machines/pyrite/facter.json` exists and is git-tracked
- **AND** no `machines/pyrite/hardware-configuration.nix` exists

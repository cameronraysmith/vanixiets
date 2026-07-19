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

- **WHEN** an alternative of setting the four SPI/SMC initrd modules directly and skipping the profile is considered
- **THEN** it is rejected rather than held as a fallback, because the profile is what puts `applespi`, `spi_pxa2xx_platform`, `intel_lpss_pci`, and `applesmc` into `boot.initrd.kernelModules` (`apple/macbook-pro/14-1/default.nix:19-24`) and nothing else in the machine's module set puts any of them there
- **AND** `hardware.intelgpu` cannot be hand-copied at all, because nixpkgs declares no such option — `nixos-hardware` declares it at `common/gpu/intel/default.nix:8-54` and `common/gpu/intel/kaby-lake/default.nix:10-13` sets it — so copying its effect means re-deriving a package-selection module to its concrete answer, three `extraPackages` on this machine, and maintaining that answer by hand
- **AND** it is NOT rejected on the ground that `i915` reaches the initrd only through the profile's import chain, which is false: `nixos/modules/module-list.nix:70` imports `hardware/facter` into every NixOS configuration and `nixos/modules/hardware/facter/graphics/default.nix:33` assigns the report's graphics driver modules into `boot.initrd.kernelModules` at plain priority, so skipping the profile leaves `i915` in place and produces a prompt that renders and cannot be typed into rather than one that is invisible
- **AND** the rejection is decidable by `nix eval` of `.#nixosConfigurations.pyrite.config.boot.initrd.kernelModules`, which contains all four SPI/SMC modules with the profile imported

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

- **WHEN** `nix eval .#nixosConfigurations.pyrite.config.hardware.firmware.paths --apply 'ps: builtins.any (p: (builtins.match "linux-firmware.*" (p.pname or p.name)) != null) ps'` is evaluated — on the pinned nixpkgs (26.11pre) `hardware.firmware` resolves to a single merged derivation rather than a list, so the closure is read through its `.paths` attribute, the list of firmware packages the merge unions, and `map (p: p.pname or p.name)` over `hardware.firmware` itself fails with "expected a list but found a set"
- **THEN** it returns `true`, because `linux-firmware` is one of those packages, which `nixos/modules/hardware/all-firmware.nix:75` adds to `hardware.firmware` inside the config block `:71-86` that `enableRedistributableFirmware` gates
- **AND** that package is what carries the BCM4350's `brcm/brcmfmac4350-pcie.bin` and `brcm/brcmfmac4350c2-pcie.bin`, both listed in its `WHENCE` under `Driver: brcmfmac` with "Licence: Redistributable"

#### Scenario: b43 false and enableRedistributableFirmware true are consistent, not contradictory

- **WHEN** `nix eval .#nixosConfigurations.pyrite.config.networking.enableB43Firmware` is evaluated
- **THEN** it returns `false` while `hardware.enableRedistributableFirmware` returns `true`
- **AND** the two are consistent, because the discriminating property is redistributability and not freeness: `b43Firmware_5_1_138` is `lib.licenses.unfree`, evaluating to `{ free = false; redistributable = false; }`, and serves BCM43xx silicon this machine does not have, while `linux-firmware` is `unfreeRedistributableFirmware`, evaluating to `{ free = true; redistributable = true; }`, and carries the blob this machine's only NIC needs to probe

---

### Requirement: The stage-1 initrd force-loads the four SPI/SMC modules that make the unlock prompt answerable

The initrd SHALL force-load `applespi`, `spi_pxa2xx_platform`, `intel_lpss_pci`, and `applesmc` via `boot.initrd.kernelModules`, which the imported profile supplies at `apple/macbook-pro/14-1/default.nix:19-24`.
The facter report MUST NOT be relied upon for these, and the fleet's `base` module MUST NOT be relied upon for these.
The dependency is stronger under a LUKS container unlocked by FIDO2 than it was under a typed ZFS passphrase, because both enrolled tokens carry a FIDO2 client PIN, so `systemd-cryptenroll`'s default `--fido2-with-client-pin=yes` makes every boot a typed PIN plus a touch, and the committed clan-vars passphrase is a fallback typed on the same keyboard.
The requirement is decidable by `nix eval` of `.#nixosConfigurations.pyrite.config.boot.initrd.kernelModules` against the built configuration and does not require the hardware.

#### Scenario: the profile supplies the modules that base does not

- **WHEN** `modules/system/initrd-networking.nix:33-37` contributes only `virtio_pci` and `virtio_net` to `boot.initrd.kernelModules` for every NixOS machine
- **THEN** the SPI modules arrive from the imported profile instead, which sets `boot.initrd.kernelModules` — the option that force-loads — rather than `availableKernelModules`, which only makes a module present
- **AND** a two-way evaluation carrying the facter report and differing only by the import gives `["dm_mod" "i915"]` without the profile and `["applesmc" "applespi" "dm_mod" "i915" "intel_lpss_pci" "spi_pxa2xx_platform"]` with it, so all four are the profile's marginal contribution and none is supplied elsewhere

#### Scenario: facter supplies no SPI keyboard modules

- **WHEN** the committed facter report is evaluated
- **THEN** it contributes no `applespi` or `intel_lpss` initrd modules, because `nixos/modules/hardware/facter/keyboard.nix` sources initrd keyboard modules from the USB controller report only and the keyboard on this machine is SPI-attached

---

### Requirement: boot.initrd.kernelModules is never overridden with mkForce

The pyrite host module MUST NOT set `boot.initrd.kernelModules` with `lib.mkForce`.
The virtio entries `base` contributes SHALL be left in place.

#### Scenario: mkForce on the module list is a lockout, not a cleanup

- **WHEN** the intent is to drop `base`'s cloud-VM `virtio_pci` and `virtio_net` entries, for which `lib.mkForce [ ... ]` is the natural-looking mechanism
- **THEN** it MUST NOT be used, because the option accumulates from an open set of sources this specification does not close over — `base`'s virtio pair, the profile's `applespi`/`spi_pxa2xx_platform`/`intel_lpss_pci`/`applesmc`, `common/gpu/intel`'s `i915`, facter's `brcmfmac`, facter's own `i915` (`nixos/modules/hardware/facter/graphics/default.nix:33`), and stock nixpkgs modules that no configuration imports deliberately, among them `dm_mod` (`nixos/modules/system/boot/kernel.nix:379`), `af_packet` (`nixos/modules/system/boot/initrd-network.nix:124`), and `zfs` (`nixos/modules/tasks/filesystems/zfs.nix:726`) — and `mkForce` discards every definition it does not name
- **AND** the openness of that set is the ground for the prohibition rather than a gap in it, since a prohibition that does not depend on enumerating the contributors cannot be defeated by finding another one, and the enumeration has already been wrong twice
- **AND** the stock contributions are decidable by `nix eval` without pyrite's hardware: `nix eval --json .#nixosConfigurations.cinnabar.config.boot.initrd.kernelModules` returns `["af_packet","dm_mod","virtio_balloon","virtio_console","virtio_gpu","virtio_net","virtio_pci","virtio_rng","zfs"]` on a machine that imports no nixos-hardware profile
- **AND** compliance is decidable by `nix eval` of `.#nixosConfigurations.pyrite.config.boot.initrd.kernelModules` against the built configuration, which SHALL contain the four SPI/SMC modules, `i915`, and `base`'s virtio pair
- **AND** the resulting configuration would evaluate cleanly, build cleanly, and boot to an unlock prompt that is invisible or unanswerable, on a machine with no macOS to fall back to
- **AND** the virtio entries are left alone because on bare metal they modprobe, find no matching device, and cost a few kilobytes of initrd

#### Scenario: initrd SSH is disabled without touching the module list

- **WHEN** `base` enables `boot.initrd.network.ssh` on port 2222 for remote unlock
- **THEN** pyrite overrides that option specifically, because its only NIC is `brcmfmac` WiFi which will not associate in initrd, and an advertised remote-unlock path that cannot function is worse than none
- **AND** this is a distinct option from `boot.initrd.kernelModules` and requires no list override

---

### Requirement: A USB-C keyboard and a seated FIDO2 token are prerequisites of the first boot, not recoveries improvised afterward

The runbook SHALL state that a USB-C keyboard or a USB-C-to-USB-A adapter is on hand before the first boot after the install, and that at least one enrolled token is seated.
A first boot with neither the token nor the passphrase to hand strands the machine at the stage-1 prompt with no fallback OS, which is the same class of failure the keyboard prerequisite exists to prevent.

#### Scenario: the USB recovery path rests on udev autoloading, not force-loading

- **WHEN** an external keyboard is used to answer the stage-1 unlock prompt — the FIDO2 client PIN, or the passphrase fallback — because the internal keyboard is not yet bound
- **THEN** it is recorded that `usbhid`, `hid-generic`, and `hid-apple` reach the initrd through `availableKernelModules` and udev autoloading rather than through the force-loading `boot.initrd.kernelModules`, so the path depends on udev probing the device rather than on an unconditional modprobe
- **AND** the ZFS-specific ground previously recorded here — that the ZFS initrd unit requests credentials with an unbounded timeout — is retracted, because the credential query is now `systemd-cryptsetup`'s, driven by the crypttab entry disko emits through `boot.initrd.luks.devices.<name>.crypttabExtraOpts = [ "fido2-device=auto" ]` (disko `lib/types/luks.nix:348`)
- **AND** how long that query waits before failing is NOT asserted here, because it was not verified against this configuration; it is an on-hardware observation of the first boot rather than a property inherited from the ZFS path

#### Scenario: the machine has no USB-A port

- **WHEN** the recovery keyboard is selected
- **THEN** the runbook states that a MacBookPro14,1 has USB-C ports only, so a USB-C keyboard or an adapter must be physically present before the wipe rather than sourced after a failed boot
- **AND** the two Thunderbolt 3 ports are the whole budget, and the USB-C token the unlock now needs occupies one of them, so a keyboard, a token, and power cannot all be seated at once — which is a reason to verify the token before the wipe rather than discover the contention after a failed boot

---

### Requirement: The machine's configuration is never seeded from nixos-generate-config

Hardware facts for pyrite SHALL come from the committed facter report.
A `machines/pyrite/hardware-configuration.nix` SHOULD NOT be created.
The strength is SHOULD NOT rather than MUST NOT because the ground — that clan-core warns when a `hardware-configuration.nix` coexists with a facter report — is recorded uncited and is tracked as an open risk in design.md; the previously-recorded second ground, that `nixos-generate-config` misdetects this machine's WiFi as b43, is false and is retracted there.

#### Scenario: the repository carries a facter report and no generated hardware module

- **WHEN** the machine's source tree is inspected after the change is applied
- **THEN** `machines/pyrite/facter.json` exists and is git-tracked
- **AND** no `machines/pyrite/hardware-configuration.nix` exists

---

### Requirement: The profile's dormant NVMe d3cold workaround is activated deliberately

The pyrite host module SHALL define a `systemd.services.disable-nvme-d3cold` unit running `nixos-hardware`'s `apple/macbook-pro/14-1/disable-nvme-d3cold.sh`, `Type = "oneshot"`, ordered `before` `suspend.target` and `wantedBy` both `multi-user.target` and `suspend.target`, matching the block the profile carries commented out at `apple/macbook-pro/14-1/default.nix:60-68`.
Importing the profile does NOT activate it: that block is commented out upstream under "[Enable only if needed!]", so the machine defines its own.
The observable is that `/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed` reads `0` after boot; it reads `1` on the machine as currently installed.

#### Scenario: the upstream script applies to this machine unmodified

- **WHEN** `disable-nvme-d3cold.sh:3` hardcodes `driver_path=/sys/bus/pci/devices/0000:01:00.0`
- **THEN** it is used as-is rather than forked, patched, or reimplemented, because that is exactly this machine's NVMe controller address — the same device the disko layout reaches through `/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1`
- **AND** the script's only reachable failure is `:5-7`, which exits 1 when that path is absent, which is the failure worth having: it fires when the controller has moved and the workaround would otherwise silently target nothing

#### Scenario: the script's driver guard is fail-open and is not relied upon

- **WHEN** `disable-nvme-d3cold.sh:12` reads `if [[ "$driver" -ne "nvme" ]]`, applying bash arithmetic `-ne` to string operands
- **THEN** the guard can never fire, because non-numeric operands evaluate to `0` in arithmetic context and the comparison is always `0 -ne 0`
- **AND** nothing in this specification depends on that guard; the address check at `:5-7` is the only check relied upon, and the defect is recorded so a later reader does not mistake the guard for protection

#### Scenario: d3cold_allowed reads 0 on the running machine

- **WHEN** the machine has booted and the workaround is checked
- **THEN** `cat /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed` returns `0`
- **AND** the sysfs read is the criterion rather than `systemctl is-active disable-nvme-d3cold`, because a `Type=oneshot` unit reports `inactive (dead)` in the correct steady state, and a unit that ran and wrote nothing reports success exactly as one that wrote `0` does

---

### Requirement: Suspend is entered through the systemd-sleep path and resumes with the pool intact

Suspend and resume SHALL be exercised through `systemctl suspend` — the `systemd-sleep` path the `before = [ "suspend.target" ]` ordering hooks — rather than through a lid close, so the d3cold workaround is demonstrated to have run before the transition rather than assumed to.
Until a resume is demonstrated, `services.logind.settings.Login.HandleLidSwitch` and `HandleLidSwitchExternalPower` SHALL remain `"lock"` and `HandleLidSwitchDocked` `"ignore"`, so a lid close cannot reach the suspend path.
Restoring the lid handlers to `"suspend"` is gated on the resume criterion below.

#### Scenario: the resume criterion is a surviving journal, not a lit screen

- **WHEN** the machine is suspended with `systemctl suspend` and resumed after several minutes
- **THEN** `journalctl -b -0` carries a resume line followed by continued logging with timestamps on the far side of the suspended interval, which is the criterion, because the failure this workaround addresses is precisely an absence: the pre-fix journal ends at the instant of suspend and carries nothing for the tens of minutes the machine demonstrably kept running, though journald's default `SyncIntervalSec` of five minutes would have committed several times
- **AND** a lit screen is NOT sufficient evidence, because the pre-fix failure left the machine running with every process blocked in `TASK_UNINTERRUPTIBLE` behind a dead NVMe, which a display test does not distinguish from a healthy resume
- **AND** `zpool status zroot` reports no errors and the dm-crypt mapping is still open, since the pool now sits inside a LUKS container whose backing device is the controller that failed to resume

#### Scenario: the i915 PSR hypothesis is retracted rather than carried

- **WHEN** `i915.enable_psr=2` is proposed as the fix for a dark panel after resume
- **THEN** it is rejected on direct observation, because the panel on this unit reports "PSR = no, Panel Replay = no", so the parameter is inert here and setting it would be a change with no mechanism
- **AND** the dark panel is recorded as a consequence of every process blocking on I/O rather than as a display fault, alongside the fans going to full speed because `mbpfan` — which holds the SMC in manual mode with `fan1_manual=1` — blocked in D state and stopped feeding its heartbeat, so the SMC reverted to its thermal-safety default

#### Scenario: the deep and s2idle states are discriminated rather than assumed equivalent

- **WHEN** the two recorded pre-fix failures are compared — deep S3, the kernel default on this unit, whose boots ended at "PM: suspend entry (deep)" with no resume line, and s2idle, which resumed the kernel and briefly restored networking before the machine died about a minute later
- **THEN** the resume criterion is exercised against whichever state `cat /sys/power/mem_sleep` reports as active, and that state is recorded with the result
- **AND** the two are NOT asserted to share the d3cold cause, because a dead NVMe produces the same journal silence in both and the journal cannot discriminate them; a pass in one state and a failure in the other is a finding rather than a contradiction

---

### Requirement: A hang that outlives the disk is recorded through EFI pstore, because every other channel is unavailable on this machine

The pyrite host module SHALL configure panic-on-hang with automatic reboot and SHALL keep the `pstore` filesystem and `systemd-pstore` archival available, so a repeat of the resume failure leaves a record.
The record MUST reach a medium that does not depend on the NVMe controller, which is the component whose failure is under investigation.
The operator procedure for reading a captured record back belongs in the runbook rather than here; this requirement covers only what the built configuration carries.

#### Scenario: EFI pstore is chosen because the failure destroys every disk-backed channel

- **WHEN** a hang leaves the NVMe controller dead and ZFS blocking all I/O
- **THEN** `efi_pstore` is the recording channel, because it writes to EFI variables in the machine's SPI boot ROM rather than to the disk, which is why it survives the failure that erases the journal
- **AND** the alternatives are recorded as unavailable rather than untried: no hardware watchdog exists, since `iTCO_wdt` is disabled by Apple firmware and no `/dev/watchdog` is present; no serial console exists, since the machine has USB-C ports only and no UART; and netconsole is unavailable, since `brcmfmac` implements no `ndo_poll_controller`

#### Scenario: the configuration half is decidable off the hardware and the recording half is not

- **WHEN** `nix eval --json .#nixosConfigurations.pyrite.config.boot.kernelParams` and `nix eval --json .#nixosConfigurations.pyrite.config.boot.kernel.sysctl` are evaluated
- **THEN** the panic-on-hang and auto-reboot settings are present in the built configuration, discharging the eval half without touching the machine
- **AND** the eval does NOT discharge the requirement, because a setting that is present and a record that is actually written are different claims, and only a deliberately induced hang distinguishes them

#### Scenario: the auto-reboot is not a remote-recovery claim

- **WHEN** automatic reboot on panic is enabled
- **THEN** it is recorded that the machine does not return to service unattended, because the reboot lands at the stage-1 LUKS unlock, which needs a seated token and a typed client PIN, or the passphrase
- **AND** this is accepted rather than mitigated, because the machine already cannot be rebooted remotely under any encryption scheme — `boot.initrd.network.enable` is forced false and there is no initrd SSH — so auto-reboot converts an indefinite hang into a machine waiting at a prompt, which is strictly better and claims nothing more

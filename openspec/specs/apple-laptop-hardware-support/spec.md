# apple-laptop-hardware-support Specification

## Purpose

This capability covers the hardware surface of an Apple MacBookPro14,1 running NixOS.
It governs the import of the upstream `nixos-hardware` model profile together with the firmware pulls that import declines, the firmware affirmations the host module states in its own right, and the SPI keyboard and SMC modules force-loaded into the initrd so that the stage-1 credential prompt renders on the internal panel and accepts input from the internal keyboard.
It covers the machine's sleep path — the PCI d3cold sweep, the storage-controller guard that gates each transition, the lid wake source, and the display and storage kernel parameters carried alongside them — and the EFI pstore channel through which a panic is recorded on a machine that has no watchdog, no serial console, and no disk-backed channel surviving the failure being recorded.
Hardware facts reach the configuration through a committed facter report rather than a generated hardware module.
The requirements are written against the model, so they hold for any fleet machine importing that profile; pyrite is the only one at present.

## Requirements

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
The dependency is at least as strong under a LUKS container as it was under a typed ZFS passphrase, across the pre-enrollment and post-enrollment credential states.
Between the install and the enrollment of a token (D30), every boot is the committed clan-vars passphrase typed on this keyboard and there is no other credential.
After both tokens are enrolled, every boot is a FIDO2 client PIN typed on this keyboard followed by a touch, because both tokens carry a client PIN and `systemd-cryptenroll` defaults to `--fido2-with-client-pin=yes`, with the passphrase as the fallback typed on the same keyboard.
The fallback is reached by pressing Enter on an empty PIN at the token prompt, which is itself a keypress on this keyboard, so no credential path on this machine avoids it.
The requirement is decidable by `nix eval` of `.#nixosConfigurations.pyrite.config.boot.initrd.kernelModules` against the built configuration and does not require the hardware.

#### Scenario: the profile supplies the modules that base does not

- **WHEN** `modules/system/initrd-networking.nix:31-34` contributes only `virtio_pci` and `virtio_net` to `boot.initrd.kernelModules` for every NixOS machine
- **THEN** the SPI modules arrive from the imported profile instead, which sets `boot.initrd.kernelModules` — the option that force-loads — rather than `availableKernelModules`, which only makes a module present
- **AND** a two-way evaluation carrying the facter report and differing only by the import gives `["dm_mod" "i915"]` without the profile and `["applesmc" "applespi" "dm_mod" "i915" "intel_lpss_pci" "spi_pxa2xx_platform"]` with it, so all four are the profile's marginal contribution and none is supplied elsewhere

#### Scenario: facter supplies no SPI keyboard modules

- **WHEN** the committed facter report is evaluated
- **THEN** it contributes no `applespi` or `intel_lpss` initrd modules, because `nixos/modules/hardware/facter/keyboard.nix` sources initrd keyboard modules from the USB controller report only and the keyboard on this machine is SPI-attached

### Requirement: boot.initrd.kernelModules is never overridden with mkForce

The pyrite host module MUST NOT set `boot.initrd.kernelModules` with `lib.mkForce`.
The virtio entries `base` contributes SHALL be left in place.

#### Scenario: mkForce on the module list is a lockout, not a cleanup

- **WHEN** the intent is to drop `base`'s cloud-VM `virtio_pci` and `virtio_net` entries, for which `lib.mkForce [ ... ]` is the natural-looking mechanism
- **THEN** it MUST NOT be used, because the option accumulates from an open set of sources this specification does not close over — `base`'s virtio pair, the profile's `applespi`/`spi_pxa2xx_platform`/`intel_lpss_pci`/`applesmc`, `common/gpu/intel`'s `i915`, facter's `brcmfmac`, facter's own `i915` (`nixos/modules/hardware/facter/graphics/default.nix:33`), and stock nixpkgs modules that no configuration imports deliberately, among them `dm_mod` (`nixos/modules/system/boot/kernel.nix:379`), `af_packet` (`nixos/modules/system/boot/initrd-network.nix:124`), and `zfs` (`nixos/modules/tasks/filesystems/zfs.nix:726`) — and `mkForce` discards every definition it does not name
- **AND** the openness of that set is the ground for the prohibition rather than a gap in it, since a prohibition that does not depend on enumerating the contributors cannot be defeated by finding another one
- **AND** the stock contributions are decidable by `nix eval` without pyrite's hardware: `nix eval --json .#nixosConfigurations.cinnabar.config.boot.initrd.kernelModules` returns `["af_packet","dm_mod","virtio_balloon","virtio_console","virtio_gpu","virtio_net","virtio_pci","virtio_rng","zfs"]` on a machine that imports no nixos-hardware profile
- **AND** compliance is decidable by `nix eval` of `.#nixosConfigurations.pyrite.config.boot.initrd.kernelModules` against the built configuration, which SHALL contain the four SPI/SMC modules, `i915`, and `base`'s virtio pair
- **AND** the resulting configuration would evaluate cleanly, build cleanly, and boot to an unlock prompt that is invisible or unanswerable, on a machine with no macOS to fall back to
- **AND** the virtio entries are left alone because on bare metal they modprobe, find no matching device, and cost a few kilobytes of initrd

#### Scenario: initrd SSH is disabled without touching the module list

- **WHEN** `base` enables `boot.initrd.network.ssh` on port 2222 for remote unlock
- **THEN** pyrite overrides that option specifically, because its only NIC is `brcmfmac` WiFi which will not associate in initrd, and an advertised remote-unlock path that cannot function is worse than none
- **AND** this is a distinct option from `boot.initrd.kernelModules` and requires no list override

---

### Requirement: A USB-C keyboard and the clan-vars passphrase are prerequisites of the first boot, not recoveries improvised afterward

The runbook SHALL state that a USB-C keyboard or a USB-C-to-USB-A adapter is on hand before the first boot after the install, and that the clan-vars passphrase is readable off the machine before it is rebooted.
The passphrase is the prerequisite rather than a token, because under D30 the install enrolls none and the crypttab names none, so the first boot has exactly one credential and it is typed.
Read it with `clan vars get pyrite zfs/key` on the admin box before rebooting: the prompt offers no shell and no clipboard, and plymouth is deliberately off.
A first boot without it strands the machine at the stage-1 prompt with no fallback OS, which is the same class of failure the keyboard prerequisite exists to prevent.
A seated token becomes the ordinary credential of the later boots once either token is enrolled, and the keyboard is the prerequisite in both states rather than the token: with no token seated the prompt asks for a LUKS2 token PIN, and an Enter pressed on the empty PIN falls through to the passphrase prompt, both typed on this keyboard.

#### Scenario: the USB recovery path rests on udev autoloading, not force-loading

- **WHEN** an external keyboard is used to answer the stage-1 unlock prompt — the FIDO2 client PIN, or the passphrase fallback — because the internal keyboard is not yet bound
- **THEN** it is recorded that `usbhid`, `hid-generic`, and `hid-apple` reach the initrd through `availableKernelModules` and udev autoloading rather than through the force-loading `boot.initrd.kernelModules`, so the path depends on udev probing the device rather than on an unconditional modprobe
- **AND** the credential query is `systemd-cryptsetup`'s rather than the ZFS initrd unit's, driven by the crypttab entry disko emits for `boot.initrd.luks.devices.<name>` and by the `systemd-fido2` tokens in the header, with `crypttabExtraOpts` empty
- **AND** that query does not fail on its own: with no token seated the prompt reads "Please enter LUKS2 token PIN" and waits, with no device-absent timeout, and pressing Enter on an empty PIN is what falls through to the passphrase prompt

#### Scenario: the machine has no USB-A port

- **WHEN** the recovery keyboard is selected
- **THEN** the runbook states that a MacBookPro14,1 has USB-C ports only, so a USB-C keyboard or an adapter must be physically present before the wipe rather than sourced after a failed boot
- **AND** the two Thunderbolt 3 ports are the whole budget, and the USB-C token the end-state unlock needs occupies one of them, so a keyboard, a token, and power cannot all be seated at once — which bites at the two enrollment steps and at every boot once the tokens are enrolled, and is a reason to plan the port budget before the enrollments rather than discover the contention at a prompt

---

### Requirement: The machine's configuration is never seeded from nixos-generate-config

Hardware facts for pyrite SHALL come from the committed facter report.
A `machines/pyrite/hardware-configuration.nix` SHOULD NOT be created.
The strength is SHOULD NOT rather than MUST NOT because the ground — that clan-core warns when a `hardware-configuration.nix` coexists with a facter report — is recorded uncited and is tracked as an open risk in design.md.

#### Scenario: the repository carries a facter report and no generated hardware module

- **WHEN** the machine's source tree is inspected after the change is applied
- **THEN** `machines/pyrite/facter.json` exists and is git-tracked
- **AND** no `machines/pyrite/hardware-configuration.nix` exists

---

### Requirement: The sleep path is gated by three units the machine module defines itself

The pyrite host module SHALL define `disable-d3cold-all`, a `Type = "oneshot"` unit writing `0` to every `/sys/bus/pci/devices/*/d3cold_allowed` node, ordered `before` and `wantedBy` `systemd-suspend.service`, `systemd-hybrid-sleep.service`, and `systemd-suspend-then-hibernate.service`.
It SHALL define `nvme-d3cold-suspend-guard`, a `oneshot` ordered `after` that sweep, `before` those same three units and `requiredBy` them, exiting non-zero unless `/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed` reads `0`.
It SHALL define `disable-lid-wakeup`, a `oneshot` with `RemainAfterExit`, `wantedBy` `multi-user.target`, writing `disabled` to the `power/wakeup` attribute of the ACPI lid device `PNP0C0D:00`.
The profile's own `systemd.services.disable-nvme-d3cold` block, which it carries commented out at `apple/macbook-pro/14-1/default.nix:60-68` under "[Enable only if needed!]", MUST NOT be enabled in their place: importing the profile activates nothing, and the single endpoint it names is not sufficient on this machine.

#### Scenario: the sweep covers every PCI device, because clearing the storage endpoint alone does not resume

- **WHEN** `disable-nvme-d3cold.sh:3` hardcodes `driver_path=/sys/bus/pci/devices/0000:01:00.0`, which is this machine's NVMe controller — the same device the disko layout reaches through `/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1`
- **THEN** the sweep iterates `/sys/bus/pci/devices/*/d3cold_allowed` rather than taking that address, because a resume with the Alpine Ridge Thunderbolt switch at `0000:04:00.0`, its `05:0x.0` bridges, and the BCM4350 WiFi still at `d3cold_allowed = 1` wedges, and clearing the attribute on every PCI device is what lets the machine come back
- **AND** iterating the tree at transition time rather than naming a fixed address also survives PCI renumbering
- **AND** the sweep is best-effort: a node that rejects the write is logged and skipped, because refusing an unsafe transition is the guard's job rather than the sweep's

#### Scenario: the guard is fail-closed and is scoped to the storage controller

- **WHEN** `nvme-d3cold-suspend-guard` runs and finds `/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed` reading anything other than `0`
- **THEN** it exits non-zero, which aborts the sleep transition that requires it, rather than letting the machine suspend with the controller still able to enter d3cold
- **AND** it is ordered `after` the sweep, so what it validates is the post-sweep state rather than the state the sweep was asked to correct
- **AND** it asserts over that one address rather than over the whole tree, because the on-board NVMe is soldered and its address is stable, while a whole-tree assertion would let any transiently-unwritable node block suspend indefinitely
- **AND** the storage controller is the scope because its failure is the unrecoverable one: the pool sits behind it and ZFS's default `failmode=wait` turns its loss into an indefinite whole-system block, which no other endpoint on this machine produces

#### Scenario: the sysfs attribute is a residue of a completed transition rather than a boot-time observable

- **WHEN** `cat /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed` is read on a machine that has booted but not yet slept
- **THEN** it returns the kernel default `1`, because the sweep is wanted by the three sleep units rather than by `multi-user.target` and has not run
- **AND** the criterion is therefore the ordering and the run — both units logging `Finished` immediately ahead of each `PM: suspend entry` in `journalctl -b -0`, across the whole `/sys/bus/pci/devices/*` tree rather than at the one endpoint — because on a machine that has slept the guard makes any other reading impossible
- **AND** `systemctl is-active` is not the criterion either, because a `Type = "oneshot"` unit reports `inactive (dead)` in the correct steady state, and a unit that ran and wrote nothing reports success exactly as one that wrote `0` does

#### Scenario: the lid switch is removed from the S3 wake sources

- **WHEN** the machine is suspended with the lid open
- **THEN** the ACPI lid device `PNP0C0D:00` does not wake it, because `disable-lid-wakeup` has written `disabled` to that device's `power/wakeup` attribute, and it is otherwise an active wake source that fires seconds into the transition
- **AND** `/sys/kernel/debug/wakeup_sources` is where the active sources are read back, which is what identifies the lid rather than another device
- **AND** the write is idempotent, which is what makes this a boot-time unit with `RemainAfterExit` rather than a toggle against `/proc/acpi/wakeup`
- **AND** the unit exits non-zero when neither candidate path exists, so a kernel or firmware change that moves the attribute surfaces as a failed unit rather than as a machine that resumes seconds after it suspends
- **AND** the power button and the keyboard remain wake sources, so the machine is still resumable by hand

---

### Requirement: Suspend is entered through the systemd-sleep path and resumes with the pool intact

Suspend and resume SHALL be exercised through `systemctl suspend` — the `systemd-sleep` path the sweep and the guard are ordered against — rather than through a lid close, so both units are demonstrated to have run before the transition rather than assumed to.
`services.logind.settings.Login.HandleLidSwitch` and `HandleLidSwitchExternalPower` SHALL be `"lock"` and `HandleLidSwitchDocked` `"ignore"`, so a lid close locks the session and leaves the machine running.
They SHALL NOT be set to `"suspend"` while a warm reboot taken after a suspend loses the Thunderbolt subtree, because a lid close is the most common suspend trigger and moving the handlers would put that failure on the ordinary path.
That is a decision on the evidence recorded below rather than a permanent exclusion: it is revisited when a suspend followed by a warm reboot leaves the subtree intact.

#### Scenario: the resume criterion is a surviving journal, not a lit screen

- **WHEN** the machine is suspended with `systemctl suspend` and resumed after several minutes
- **THEN** `journalctl -b -0` carries a resume line followed by continued logging with timestamps on the far side of the suspended interval, which is the criterion, because the failure these units address is precisely an absence: the pre-fix journal ends at the instant of suspend and carries nothing for the tens of minutes the machine demonstrably kept running, though journald's default `SyncIntervalSec` of five minutes would have committed several times
- **AND** a lit screen is NOT sufficient evidence, because the pre-fix failure left the machine running with every process blocked in `TASK_UNINTERRUPTIBLE` behind a dead NVMe, which a display test does not distinguish from a healthy resume
- **AND** `zpool status zroot` reports no errors and the dm-crypt mapping is still open, since the pool now sits inside a LUKS container whose backing device is the controller that failed to resume

#### Scenario: the display and storage kernel parameters are carried without their contribution being separated

- **WHEN** `nix eval --json .#nixosConfigurations.pyrite.config.boot.kernelParams` is evaluated
- **THEN** it carries `i915.enable_psr=0`, `i915.enable_fbc=0`, `i915.enable_dc=0`, `nvme_core.default_ps_max_latency_us=0`, `nvme.noacpi=1`, and `pci=noaer`, which address the resume variant in which the kernel returns and the panel does not
- **AND** they reached the machine on the same boot as the d3cold sweep, so nothing here separates their contribution from it
- **AND** `nixos-hardware`'s `common/gpu/intel/kaby-lake` module, whose `default.nix:5-7` sets `i915.enable_guc=2`, `i915.enable_fbc=1`, and `i915.enable_psr=2`, is dropped through `disabledModules` with only `enable_guc=2` restored to the command line by hand, so the profile's PSR and FBC enables do not sit alongside the zeros above
- **AND** enabling PSR is not a candidate mechanism in the other direction, because the panel on this unit reports "PSR = no, Panel Replay = no"
- **AND** a dark panel is NOT by itself a display fault, because the failure these units address left every process blocked in `TASK_UNINTERRUPTIBLE` behind a dead NVMe, which also stopped `mbpfan` feeding the heartbeat that holds the SMC in manual mode with `fan1_manual=1`, so the fans reverted to their thermal-safety default

#### Scenario: the sleep state is recorded with the result and a pass in one state does not cover the other

- **WHEN** the resume criterion is exercised
- **THEN** whichever state `cat /sys/power/mem_sleep` reports as active is recorded alongside the result, because `mem_sleep_default` is left unpinned
- **AND** a pass in one state is NOT taken as covering the other: without these units deep S3, the kernel default on this unit, ended the boot at "PM: suspend entry (deep)" with no resume line, while s2idle resumed the kernel and briefly restored networking before the machine died about a minute later
- **AND** the two are NOT asserted to share a cause either, because a dead NVMe produces the same journal silence in both and the journal cannot discriminate them; a pass in one state and a failure in the other is a finding rather than a contradiction

#### Scenario: the lid handlers are held at "lock" by the warm-reboot failure, not by the resume observation

- **WHEN** `nix eval --json .#nixosConfigurations.pyrite.config.services.logind.settings.Login` is evaluated
- **THEN** `HandleLidSwitch` and `HandleLidSwitchExternalPower` read `"lock"` and `HandleLidSwitchDocked` reads `"ignore"`, so a lid close locks the session and leaves the machine running
- **AND** a demonstrated suspend and resume does NOT release them, because that is a different claim from a suspend followed by a warm reboot: the Alpine Ridge Thunderbolt subtree does not survive that reboot, and `dmesg` carries "Unable to change power state from D3cold to D0, device inaccessible" against `pcieport 0000:00:1c.4` and the `05:0x.0` ports after each resume
- **AND** holding the handlers is what keeps that failure off the ordinary path, since a lid close is the most common suspend trigger, so they move when a suspend followed by a warm reboot leaves the subtree intact and not before

---

### Requirement: A panic that outlives the disk is recorded through EFI pstore, because every other channel is unavailable on this machine

The pyrite host module SHALL set `boot.kernel.sysctl."kernel.panic"` to a nonzero timeout, so a panic reboots the machine rather than leaving it dark, and SHALL leave the `pstore` filesystem and `systemd-pstore` archival at the nixpkgs defaults that mount `efi_pstore` and run the archival unit.
It MUST NOT carry `kernel.hung_task_panic`, `kernel.softlockup_panic`, or `kernel.hardlockup_panic` in the built configuration: those turn a long ZFS scrub or a long nix build into a reboot, which is not a behaviour a daily driver can carry, and they are set by hand for the duration of a supervised test instead.
The record MUST reach a medium that does not depend on the NVMe controller, which is the component whose failure it records.
The operator procedure for reading a captured record back belongs in the runbook rather than here; this requirement covers only what the built configuration carries.

#### Scenario: EFI pstore is chosen because the failure destroys every disk-backed channel

- **WHEN** a hang leaves the NVMe controller dead and ZFS blocking all I/O
- **THEN** `efi_pstore` is the recording channel, because it writes to EFI variables in the machine's SPI boot ROM rather than to the disk, which is why it survives the failure that erases the journal
- **AND** the alternatives are recorded as unavailable rather than untried: no hardware watchdog exists, since `iTCO_wdt` is disabled by Apple firmware and no `/dev/watchdog` is present; no serial console exists, since the machine has USB-C ports only and no UART; and netconsole is unavailable, since `brcmfmac` implements no `ndo_poll_controller`

#### Scenario: the configuration is what this requirement asserts, and a captured record is a separate claim

- **WHEN** `nix eval --json .#nixosConfigurations.pyrite.config.boot.kernel.sysctl` is evaluated
- **THEN** `kernel.panic` carries the reboot timeout and the three panic-on-hang keys are absent, which is the whole of what this requirement asserts
- **AND** the reboot timeout is a sysctl rather than a kernel parameter, so `boot.kernelParams` does not carry it — that list holds the sleep and display parameters instead
- **AND** a record actually written to EFI variables and archived is a different claim from a setting being present, and only a deliberately induced hang distinguishes them

#### Scenario: the auto-reboot is not a remote-recovery claim

- **WHEN** automatic reboot on panic is enabled
- **THEN** it is recorded that the machine does not return to service unattended, because the reboot lands at the stage-1 LUKS unlock, which needs a seated token and a typed client PIN, or the passphrase
- **AND** this is accepted rather than mitigated, because the machine already cannot be rebooted remotely under any encryption scheme — `boot.initrd.network.enable` is forced false and there is no initrd SSH — so auto-reboot converts an indefinite hang into a machine waiting at a prompt, which is strictly better and claims nothing more

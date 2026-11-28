## MODIFIED Requirements

### Requirement: The stage-1 initrd force-loads the four SPI/SMC modules that make the unlock prompt answerable

The initrd SHALL force-load `applespi`, `spi_pxa2xx_platform`, `intel_lpss_pci`, and `applesmc` via `boot.initrd.kernelModules`, which the imported profile supplies at `apple/macbook-pro/14-1/default.nix:19-24`.
The facter report MUST NOT be relied upon for these, and modules the fleet shares MUST NOT be relied upon for these.
The requirement is decidable by `nix eval` of `.#nixosConfigurations.pyrite.config.boot.initrd.kernelModules` and does not require the hardware.

#### Scenario: every credential path passes through this keyboard

- **WHEN** the machine boots to the stage-1 unlock prompt
- **THEN** the dependency on these modules is at least as strong under a LUKS container as it was under a typed ZFS passphrase, across the pre-enrollment and post-enrollment credential states
- **AND** between the install and the enrollment of a token (D30), every boot is the committed clan-vars passphrase typed on this keyboard and there is no other credential
- **AND** after both tokens are enrolled, every boot is a FIDO2 client PIN typed on this keyboard followed by a touch, because both tokens carry a client PIN and `systemd-cryptenroll` defaults to `--fido2-with-client-pin=yes`, with the passphrase as the fallback typed on the same keyboard
- **AND** the fallback is reached by pressing Enter on an empty PIN at the token prompt, which is itself a keypress on this keyboard, so no credential path on this machine avoids it

#### Scenario: the profile supplies the modules that base does not

- **WHEN** pyrite imports no module the fleet shares that contributes to `boot.initrd.kernelModules`, since `initrd-networking`, which contributes `virtio_pci` and `virtio_net`, is imported only by `modules/nixos/hetzner-cloud.nix` and `modules/nixos/gcp-cloud.nix`
- **THEN** the SPI modules arrive from the imported profile, which sets `boot.initrd.kernelModules` — the option that force-loads — rather than `availableKernelModules`, which only makes a module present
- **AND** a two-way evaluation carrying the facter report and differing only by the import gives `["dm_mod" "i915"]` without the profile and `["applesmc" "applespi" "dm_mod" "i915" "intel_lpss_pci" "spi_pxa2xx_platform"]` with it, so all four are the profile's marginal contribution and none is supplied elsewhere

#### Scenario: facter supplies no SPI keyboard modules

- **WHEN** the committed facter report is evaluated
- **THEN** it contributes no `applespi` or `intel_lpss` initrd modules, because `nixos/modules/hardware/facter/keyboard.nix` sources initrd keyboard modules from the USB controller report only and the keyboard on this machine is SPI-attached

### Requirement: boot.initrd.kernelModules is never overridden with mkForce

The pyrite host module MUST NOT set `boot.initrd.kernelModules` with `lib.mkForce`.
Compliance is decidable by `nix eval` of `.#nixosConfigurations.pyrite.config.boot.initrd.kernelModules`, which SHALL contain the four SPI/SMC modules and `i915`.
Initrd networking SHALL be off on pyrite because no module enables it, and the pyrite host module SHALL assert that `boot.initrd.network.enable` is false.

#### Scenario: mkForce on the module list is a lockout, not a cleanup

- **WHEN** the intent is to drop an entry another module contributes, for which `lib.mkForce [ ... ]` is the natural-looking mechanism
- **THEN** it MUST NOT be used, because the option accumulates from an open set of sources this specification does not close over — the profile's `applespi`/`spi_pxa2xx_platform`/`intel_lpss_pci`/`applesmc`, `common/gpu/intel`'s `i915`, facter's own `i915` (`nixos/modules/hardware/facter/graphics/default.nix:33`), and stock nixpkgs modules that no configuration imports deliberately, among them `dm_mod` (`nixos/modules/system/boot/kernel.nix:379`) and `zfs` (`nixos/modules/tasks/filesystems/zfs.nix:726`) — and `mkForce` discards every definition it does not name
- **AND** the openness of that set is the ground for the prohibition rather than a gap in it, since a prohibition that does not depend on enumerating the contributors cannot be defeated by finding another one
- **AND** the stock contributions are decidable by `nix eval` without pyrite's hardware: `nix eval --json .#nixosConfigurations.cinnabar.config.boot.initrd.kernelModules` returns `["af_packet","dm_mod","virtio_balloon","virtio_console","virtio_gpu","virtio_net","virtio_pci","virtio_rng","zfs"]` on a machine that imports no nixos-hardware profile
- **AND** `nix eval --json .#nixosConfigurations.pyrite.config.boot.initrd.kernelModules` returns `["applesmc","applespi","dm_mod","i915","intel_lpss_pci","spi_pxa2xx_platform","zfs"]`
- **AND** the resulting configuration would evaluate cleanly, build cleanly, and boot to an unlock prompt that is invisible or unanswerable, on a machine with no macOS to fall back to

#### Scenario: initrd SSH is disabled without touching the module list

- **WHEN** pyrite imports neither cloud provider aspect, so no module imports `initrd-networking`
- **THEN** `nix eval .#nixosConfigurations.pyrite.config.boot.initrd.network.enable` returns `false`, its default, and there is no initrd SSH, which suits a machine whose only NIC is `brcmfmac` WiFi that will not associate in initrd
- **AND** a module enabling it fails pyrite's evaluation on the host module's assertion, because nixpkgs' `hardware/facter/networking/initrd.nix` would then put `brcmfmac` in stage 1, where its per-vendor sub-module cannot load and the failed attach leaves the machine with no network device
- **AND** this is a distinct option from `boot.initrd.kernelModules` and requires no list override

### Requirement: A panic that outlives the disk is recorded through EFI pstore, because every other channel is unavailable on this machine

The pyrite host module SHALL set `boot.kernel.sysctl."kernel.panic"` to a nonzero timeout and SHALL leave `pstore` and `systemd-pstore` at the nixpkgs defaults that mount `efi_pstore` and run the archival unit.
It MUST NOT carry `kernel.hung_task_panic`, `kernel.softlockup_panic`, or `kernel.hardlockup_panic`.
The record MUST reach a medium that does not depend on the NVMe controller, which is the component whose failure it records.

#### Scenario: the panic-on-hang keys are left to supervised tests

- **WHEN** a long ZFS scrub or a long nix build runs on the built configuration
- **THEN** it does not reboot the machine, because the three panic-on-hang keys are absent, and they are set by hand for the duration of a supervised test instead
- **AND** the operator procedure for reading a captured record back belongs in the runbook; this requirement covers only what the built configuration carries

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
- **AND** this is accepted rather than mitigated, because the machine already cannot be rebooted remotely under any encryption scheme — `boot.initrd.network.enable` is false and there is no initrd SSH — so auto-reboot converts an indefinite hang into a machine waiting at a prompt, which is strictly better and claims nothing more

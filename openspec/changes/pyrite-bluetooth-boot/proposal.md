# Pyrite Bluetooth boot candidate

## Why

Prepare a reproducible boot candidate for the observed native UART initialization failure without mistaking a manual reload recovery for a persistent fix.
Hardware efficacy is unproven.

## What changes

Package the historical BCM power-transition wake omission as one replacement `hci_uart.ko` for the selected Linux 6.18.42 kernel.
Contribute it only to Pyrite's `boot.extraModulePackages` and check actual aggregate module selection by name and ACPI alias.
Preserve native dependencies, kernel image, initrd preload/crypto configuration, ZFS and the existing CS8409 package.

## Capabilities

### New capabilities

- `pyrite-bluetooth-boot-candidate` (interface): reproducible, machine-scoped module packaging and observable boot-artifact selection.
  Its trust boundary ends at source/build inspection; store outputs cannot establish device initialization, headset sound or power-management reliability.

### Modified capabilities

None.

## Impact

Only `pkgs/kernel-modules/hci-uart-macbook.{nix,patch}`, `modules/checks/pyrite-bluetooth.nix`, the extra-module contribution in `modules/machines/nixos/pyrite/default.nix`, and this change's artifacts are in scope.
No source pins, desktop/audio policy, firmware or runtime state changes are included.
The single local delivery remains a child of exact audio baseline `5f88cb1ff50857614e5a0613386b4fd786dd3061`; Linear binding is deferred.

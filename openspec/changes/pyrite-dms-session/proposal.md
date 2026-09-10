# DankMaterialShell in pyrite's niri session

## Why

The selectable niri session currently lacks a bar, launcher, notifications and screen locker.
Add those facilities without replacing the established GNOME/GDM login path or reopening unreliable suspend behavior.

## What Changes

Import the upstream DMS v1.5.3 home-manager module through one pinned non-flake source input.
Compose a DMS aggregate only into pyrite's cameron home, selecting native DMS and Quickshell packages and niri-only service ownership.
Add typed IPC bindings while retaining the existing compositor bindings.
Declare native password PAM lock, logind locking, 1800-second lock intervals and zero automatic-suspend timeouts.
Add evaluated desktop assertions and validate the generated configuration with installed native niri where local build capability permits.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `machine-interface` (interface): add the DMS session configuration, package, service, lock and preservation contract.
  Trust boundary: evaluated declarations and binary configuration validation do not establish physical rendering, authentication, service ownership or performance.

## Impact

Owned paths are `flake.nix`, `flake.lock`, `modules/home/dms/default.nix`, `modules/home/niri/default.nix`, `modules/machines/nixos/pyrite/default.nix`, `modules/checks/pyrite-desktop.nix` and this change directory.
No runtime activation, network/hardware policy change or external tracker binding occurs.
CAM-59 and CAM-66 remain unrepaired; physical acceptance and independent review precede any later deployment decision.

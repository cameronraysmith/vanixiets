## Why

The prepared niri/DMS desktop still declares GDM and GNOME.
The operator wants native DankGreeter to provide authenticated entry into that desktop, while retaining existing power and hardware policy and normal password authentication.
The user explicitly approved rejecting empty passwords in shared login PAM, including console login.
Preparation must establish a buildable candidate without disturbing the running GDM system.

## What Changes

Replace declared GDM/GNOME with nixpkgs `services.displayManager.dms-greeter` and greetd, explicitly selecting niri and native DMS/Quickshell.
Generate typed greeter configuration with ordinary power-key handling disabled.
Retain B's desktop ownership and GNOME's effective supporting services.
Add evaluated assertions and a native niri validation check for the greeter.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `machine-interface` (interface): native authenticated greeter configuration, typed compositor configuration and preservation of the prepared desktop's supporting interfaces.

The trust boundary is between declared Nix/PAM/unit configuration and upstream runtime behavior on physical hardware.
Build and source evidence do not establish successful login, locking, portal transactions or rendering.

## Impact

Only `modules/machines/nixos/pyrite/default.nix`, `modules/checks/pyrite-desktop.nix` and this change directory change.
No input pins, boot/LUKS/SSH/network/hardware policy, CAM-59 or CAM-66 changes are authorized.
GNOME is not retained as a locking fallback without GDM.
Linear binding, publication, archive and activation are deferred.

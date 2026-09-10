## Context

B (`a8f9f6b6fd40754be016bab1dc874f7adf42ba52`) prepares a native niri/DMS desktop; its equivalent source passed native Linux validation and a full pyrite build.
Neither B nor C is physically accepted.
Pinned nixpkgs `85f62611fa3f3eacbcfe3bc7a6d6518b443ca442` provides the native greeter module and runtime packages.

## Goals / Non-Goals

Prepare an authenticated native DankGreeter candidate while preserving B's desktop ownership, power policy and effective supporting services.
Do not activate, tune hardware, fix suspend, replace authentication, add a lifecycle service or alter dependencies.

## Decisions

### D1: Native greeter and PAM ownership

Use nixpkgs DankGreeter with explicit niri, DMS and Quickshell package selection.
Select `general.service=greetd` for authenticated login and `default_session.service=dms-greeter` for the dedicated greeter account.
Retain native login keyring integration and reject initial-session/autologin configuration.
At the first-party/upstream boundary, configure the native module rather than importing the DMS flake greeter or writing a launcher/authentication wrapper.
The user approved disabling empty-password authentication in shared login PAM, including console login, on 2026-09-10.
Set `security.pam.services.login.allowNullPassword = lib.mkForce false` because native `shadow.nix` assigns true at normal priority.
This is the explicit exception to preserving console authentication policy; normal password authentication remains native and enabled.
Enable `security.pam.services.dms-greeter.startSession` so the dedicated compositor's PAM session includes native `pam_systemd.so` for logind seat access; seatd remains disabled.
Native `setLoginUid` defaults to `startSession`, so this also enables native `pam_loginuid.so`; both session additions are recorded in the C preservation comparison.
The guard checks the session rule's enablement, native module path and native `optional` control, plus the login auth deny rule's exact native `pam_deny.so` path.

### D2: Typed greeter configuration

Render through an isolated home-manager configuration importing only the existing epireyn configuration module.
Use native niri as its package, disable power-key handling and hot corners, skip the hotkey overlay and set `DMS_RUN_GREETER=1`.
Pass the rendered configuration to native `customConfig`; a flake check runs the installed niri validator against that exact text and verifies native launcher/QML assets exist.
The upstream launcher appends its Quickshell spawn and recognizes two optional system override files; declare neither and inspect them before any future activation.
At the source/delivered boundary, validation checks generated text rather than a hand-maintained KDL fixture.

### D3: Preserve support and desktop ownership

Remove GNOME/GDM session registration, not the native niri GNOME/GTK/keyring portal backends.
Explicitly retain NetworkManager, UPower, power-profiles-daemon with TLP disabled, AccountsService, keyring/GCR agent, polkit/rtkit, Bluetooth, bolt, udisks and libinput.
Keep B's niri-scoped DMS unit, bindings, password-lock PAM and idle timers unchanged.
Retain existing dconf policy as inert defaults rather than changing an unrelated user database.

### D4: Evidence without activation

Use one signed delivery change after B and immutable candidate URLs for evaluation/builds.
Local RED, merged assertions, preservation comparisons, mutations and source inspection precede private transfer.
Build the native greeter check, existing user niri configuration and full toplevel in a dedicated transient user build unit on pyrite.
Preserve remote HEAD, dirty paths, current/booted closure, existing session and service identities.

### D5: Unsynchronized greeter state

Set `systemd.services.greetd.preStart = lib.mkForce ""` while retaining `configHome=null` and `configFiles=[]`.
The [pinned native module](https://github.com/NixOS/nixpkgs/blob/85f62611fa3f3eacbcfe3bc7a6d6518b443ca442/nixos/modules/services/display-managers/dms-greeter.nix#L307-L384) installs a root synchronization hook even with no declared sync inputs.
That hook trusts greeter-owned mutable state; this configuration does not use its config, wallpaper, theme or color-file synchronization.
Disabling it leaves native account/home/tmpfiles creation and greetd's root-daemon/dedicated-greeter separation intact.
Assertions require both empty `preStart` and absent generated `ExecStartPre`, alongside the no-sync inputs.
This is a bounded workaround for this unsynchronized configuration, not a hardened synchronization implementation; enabling synchronization later requires a separate design and review.
The detailed security review remains in ignored local logs; no upstream report or public disclosure is authorized here.

## Risks / Trade-offs

Build validation cannot observe physical authentication, display rendering or live ownership; keep those acceptance tasks unchecked.
Upstream mutable-state migration and optional override inputs remain runtime assumptions; inspect without resetting them before a separately authorized activation.
Native PAM's `startSession` defaults false and gates the `optional` systemd session rule ([pinned PAM module](https://github.com/NixOS/nixpkgs/blob/85f62611fa3f3eacbcfe3bc7a6d6518b443ca442/nixos/modules/security/pam.nix#L1660-L1665)).
Enabling that rule fixes the declared logind wiring but does not prove seat acquisition or graphical startup on hardware.
Manual suspend remains available but risky; no suspend experiment or CAM-59 repair is authorized.
CAM-66 remains unresolved; any future authorized display-manager restart requires niri.service inactive first.

## Migration Plan

Prepare, evaluate, privately transfer and build only.
The repair phase is local-only; independent re-review and the parent's exact-final B/C builds remain pending in an external evidence lane.
Keep B's `/nix/store/dfydvmxbybr6kian1hclygfwysdivwgv-nixos-system-pyrite-26.11.20260804.85f6261` available and leave the running GDM system unchanged.
Future activation and rollback require separate operator authorization and physical acceptance; neither is performed here.

## Open Questions

No implementation choice is outstanding.
Physical login/logout, greeter return, rendering/input, locking, keyring unlock, polkit and portal transactions remain unobserved.

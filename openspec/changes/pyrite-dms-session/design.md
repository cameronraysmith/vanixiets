# Design

## Context

Slice A registers native nixpkgs niri alongside GNOME under GDM.
Its archived design D2 accepts only epireyn's typed `homeModules.config`; D3 requires identical runtime and validator store paths; D4 preserves saved choices through an explicit null default session.
The new shell must independently disable idle suspend because GNOME dconf does not govern niri.

## Goals / Non-Goals

Provide the requested DMS controls and native password lock inside niri, with one declared service owner and preserved compositor binds.
Keep GNOME/GDM and existing logind, sleep, network, SSH, boot, LUKS and hardware behavior unchanged.
Do not add greeter configuration, optional integrations, lifecycle repairs, cursor themes or X11 compatibility packages.

## Decisions

### D1: upstream module, native packages

At the vendored/first-party boundary, import only `distro/nix/home.nix` from AvengeMedia/DankMaterialShell commit `069ddab041c738236a8910e4c39b65d9628d3018` (v1.5.3).
Adapt its `dmsPkgs` argument to native pkgs and explicitly select `pkgs.dms-shell` and `pkgs.quickshell`.
Do not import its NixOS, greeter or niri helper modules.
Keep epireyn/niri-flake at `db2615fc6b3f75539ec681a984e3311b8d79ede0` for typed configuration only.

### D2: one shell owner per niri session

At the source/delivered boundary, the upstream HM service targets `niri.service` with exact PartOf, After, Requisite and WantedBy relationships and `XDG_CURRENT_DESKTOP=niri` condition.
Use the upstream notification bus contract (`Type=dbus`, `org.freedesktop.Notifications`) and enable DMS's built-in polkit agent explicitly.
No compositor spawn, mutable KDL include, separate Quickshell service or native NixOS DMS service is added.
Native niri portals and the GNOME/keyring support packages remain responsible for portal routing.
This is declared lifecycle ownership, not evidence of live bus ownership.

### D3: settings and locking

Use one declarative bar with upstream appearance defaults and the required launcher, workspace, focused-window, music, clock, tray, clipboard, notification, battery and control-center widgets.
Disable optional helper dependencies rather than assembling another desktop stack.
Native `security.pam.services.dankshell = {}` supplies password authentication; DMS selects `/etc/pam.d/dankshell` as externally managed.
Enable loginctl locking and lock-before-suspend, with AC and battery locks at 1800 seconds and suspend timeouts at zero.
Existing session state can migrate old timeout values at startup: inspect `~/.local/state/DankMaterialShell/session.json` before any later activation, and never overwrite it silently.
Declared read-only settings do not prohibit later manual or in-memory changes.

### D4: verification and delivery boundary

One local signed delivery commit follows the niri tip on the shared development join.
Evaluate assertions against an immutable candidate revision; the generated HM niri config derivation runs the same package installed by NixOS.
Build that derivation and native DMS with remote builders disabled; lack of local Linux execution is a blocker, not a successful validation.
No physical or deployment task is closed by evaluation.

## Risks / Trade-offs

The hand-maintained typed niri schema can accept invalid actions; actual native binary validation remains necessary.
DMS's upstream module and JSON settings are version-coupled to native v1.5.3; the assertions make package and input drift visible.
GNOME remains the normal fallback after clean niri exit, but CAM-66 excludes display-manager restart while niri is live.
CAM-59 manual resume remains unreliable; no suspend experiments are included.
Existing cursor and X11 limitations are retained.

## Migration Plan

This change prepares source only.
A later authorized activation must inspect existing DMS state, resolve Linux build blockers and complete independent review first.
Do not restart the display manager unless the affected user's `niri.service` is confirmed inactive under separate authorization.
Physical login/logout, GNOME fallback, lock/unlock, rendering, input, portal transactions and runtime ownership remain pending.
Source rollback removes this aggregate and its bindings while retaining the slice-A session; it does not repair stranded runtime units.

## Open Questions

No product decision blocks local implementation.
Linear binding is explicitly deferred; physical acceptance and any deployment require separate authorization.

## ADDED Requirements

### Requirement: DMS configuration uses native packages and a single niri-scoped service

Pyrite's cameron home configuration SHALL enable upstream DankMaterialShell v1.5.3 with native nixpkgs DMS and Quickshell packages.
The niri runtime and typed configuration validator MUST resolve to the same native nixpkgs niri store path.
The epireyn input MUST remain at `db2615fc6b3f75539ec681a984e3311b8d79ede0`, using only `homeModules.config`; the upstream DMS module source MUST be pinned to `069ddab041c738236a8910e4c39b65d9628d3018`.
One DMS user service MUST have PartOf, After, Requisite and WantedBy equal to `[niri.service]`, condition `XDG_CURRENT_DESKTOP=niri`, native `dms run --session`, Type `dbus` and BusName `org.freedesktop.Notifications`.
No additional Quickshell, notification, clipboard, network applet, polkit agent, idle daemon or locker startup SHALL be declared for niri.
DMS MUST enable its built-in polkit agent; native niri portal routing and supporting services MUST remain intact.
The configuration MUST contain no compositor shell spawn or mutable KDL includes.
This contract describes evaluated configuration and does not establish live service or bus ownership.

#### Scenario: Evaluate the shell configuration

- **WHEN** the pyrite configuration is evaluated
- **THEN** package paths, pinned inputs, native option provenance and the DMS service relationships satisfy the declared ownership contract
- **AND** the generated niri configuration is checked by the installed native niri binary before delivery

### Requirement: DMS exposes the requested controls and typed shortcuts

DMS SHALL declare one enabled bar exposing launcherButton, workspaceSwitcher, focusedWindow, music, clock, systemTray, clipboard, notificationButton, battery and controlCenterButton.
Clipboard support MUST be enabled; optional monitoring, VPN helpers, calendar events, audio visualization, dynamic theming and plugins MUST remain disabled.
Typed niri bindings SHALL use the absolute native DMS executable for launcher, notifications, settings, lock, clipboard, power menu, audio, brightness and media IPC commands.
Existing terminal, navigation, close and quit bindings MUST be preserved.
Only audio, brightness and media bindings MAY run while locked.
Evaluated controls and bindings do not establish usable physical rendering or input.

#### Scenario: Inspect generated shell controls

- **WHEN** the DMS settings and typed niri bindings are evaluated
- **THEN** the required widgets and native IPC argument vectors are present
- **AND** existing compositor bindings remain unchanged

### Requirement: DMS locks without introducing idle suspend

DMS SHALL select externally managed `/etc/pam.d/dankshell`, backed by native password PAM authentication without passwordless bypass or credential-capture hooks.
DMS MUST enable loginctl lock integration and lock-before-suspend.
Both AC and battery lock timeouts MUST equal 1800 seconds; both suspend timeouts MUST equal zero.
Existing logind lid settings lock/lock/ignore, idle and power-key ignore, disabled niri power-key handling, manual-suspend guards and unmasked sleep capability MUST remain unchanged.
Declarative settings do not establish successful physical lock/unlock or constrain later manual state changes.

#### Scenario: Evaluate lock and idle policy

- **WHEN** the configured DMS settings and native PAM rules are evaluated
- **THEN** the password lock path and both lock intervals match the contract
- **AND** neither declared DMS inactivity timeout requests suspend
- **AND** existing logind and manual-suspend policy is preserved

### Requirement: Adding DMS preserves GNOME and GDM

GNOME and GDM SHALL remain enabled with registered sessions `[gnome, niri]`, explicit null defaultSession, no autologin, and GDM autoSuspend false.
Existing GNOME AC and battery sleep timeouts MUST remain zero, action types and power-button action MUST remain nothing, and idle-delay MUST remain 1800 seconds.
GNOME remains the no-history fallback; saved session choices MUST NOT be overwritten by host default-session configuration.
The known live-niri display-manager-restart exception remains excluded and unrepaired.

#### Scenario: Evaluate the additive desktop configuration

- **WHEN** DMS is added to the niri home configuration
- **THEN** GNOME/GDM registration, default selection and inactivity settings retain their existing values
- **AND** no greeter replacement or automatic login is configured

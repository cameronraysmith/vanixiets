# Slice B decision capture

The operator approved local implementation of upstream DankMaterialShell inside the existing niri session, retaining GNOME/GDM.
This is a bounded desktop integration following the archived `2026-09-10-pyrite-niri-second-session` design, not a display-manager migration.
The supplied pinned research at `/Users/crs58/.local/state/atomic/pyrite-desktop/run-o0V32M/research.json` supplies the module and lifecycle decisions.

Use the upstream v1.5.3 home-manager module with native nixpkgs DMS and Quickshell packages.
Reject the upstream NixOS module, mutable niri helper includes, an additional Quickshell service, and a custom lifecycle daemon.
Retain epireyn's configuration-only input at its existing pin; installed native niri validates the generated configuration.

One niri-scoped DMS service supplies bar, launcher, notifications, clipboard, audio/network controls and password lock.
Keep lock timers at 1800 seconds and both suspend timers at zero.
Preserve existing binds, GNOME/GDM session selection, portals, logind and hardware policy.
Optional monitoring, VPN helpers, calendar, audio visualizer, dynamic theming and plugins are excluded.
Cursor-theme installation and X11 satellite remain inherited limitations rather than implicit additions to this scope.

Local evaluation and build attempts are authorized; physical acceptance is not.
No remote builder, activation, service control, tracker write, archive, workflow repair or slice C is authorized.
The explicit directly supervised worker and shared jj join instructions override the installed schema's worktree/nested-executor ceremony.
Linear binding remains deferred.

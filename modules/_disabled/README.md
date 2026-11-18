# Disabled modules

import-tree discovers modules by walking `./modules` and filtering with `andNot (hasInfix "/_") (hasSuffix ".nix")` (see `~/ghq/github.com/vic/import-tree/default.nix:50`).
Every path under this directory contains `/_`, so nothing here is imported by `flake.nix`, and none of these options exist in the evaluated configuration.

The files below are complete, working modules, not broken drafts.
They were moved here, not deleted, because beads and dolt no longer own issue tracking in this workspace: Linear and OpenSpec do, as of 2026-08-26.
The beads-ui kanban board (its darwin agent, clan service and inventory, workspace registry and packages) was deleted outright on 2026-11-18, when Linear replaced it for good; recover it from version control if ever needed.

## Contents and restoration

Each entry lists the file's disabled name, its original path, and the `mv` command that restores it.
Restoring a module re-registers its options but does not turn the corresponding service on; each module's `enable` option still defaults to `false` and must be set explicitly by the machine or role configuration that wants it.

- `system-dolt-sql-server.nix` — originally `modules/system/dolt-sql-server.nix`.
  Defines `services.dolt-sql-server` for both darwin and nixos.
  Restore: `mv modules/_disabled/system-dolt-sql-server.nix modules/system/dolt-sql-server.nix`.
  Then set `services.dolt-sql-server.enable = true;` on the machine that should run the dolt SQL server.

- `machines-nixos-cinnabar-dolt.nix` — originally `modules/machines/nixos/cinnabar/dolt.nix`.
  Sets `services.dolt-sql-server.user`/`.group` on machine `cinnabar`, with `enable = false`.
  Restore: `mv modules/_disabled/machines-nixos-cinnabar-dolt.nix modules/machines/nixos/cinnabar/dolt.nix`.
  Requires `system-dolt-sql-server.nix` restored first.
  Then flip `enable = true;` in this file.

- `home-tools-dolt-config.nix` — originally `modules/home/tools/dolt-config.nix`.
  Declaratively manages `~/.dolt/config_global.json` and defines `services.beads.doltServerPort`.
  Restore: `mv modules/_disabled/home-tools-dolt-config.nix modules/home/tools/dolt-config.nix`.
  No `enable` toggle; it applies unconditionally once imported.

## Full restoration example

To bring the whole family back at once:

```sh
mv modules/_disabled/system-dolt-sql-server.nix modules/system/dolt-sql-server.nix
mv modules/_disabled/machines-nixos-cinnabar-dolt.nix modules/machines/nixos/cinnabar/dolt.nix
mv modules/_disabled/home-tools-dolt-config.nix modules/home/tools/dolt-config.nix
```

Then set `services.dolt-sql-server.enable` to `true` wherever the service should actually run.

The `beads` and `dolt` packages moved alongside these modules, into `pkgs/disabled/` (see `modules/nixpkgs/per-system.nix` for how `pkgs/by-name/` membership defines the package set); restore each with `mv pkgs/disabled/<name> pkgs/by-name/<name>`.

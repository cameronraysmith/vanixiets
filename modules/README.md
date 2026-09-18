---
title: Nix module tree
created: 2026-08-25
---

## Nix module tree

Every `.nix` file under this directory is a flake-parts module, discovered automatically by `import-tree` rather than listed in an import set.
Files are organised by aspect — what a module configures — rather than by host, and a module assigns `deferredModule` values into class-organised namespaces such as `flake.modules.darwin.*`, `flake.modules.homeManager.*`, and `flake.modules.nixos.*`.

The consequence worth knowing before editing here is that adding a file is enough to activate it.
There is no registration step, so a file placed in this tree takes effect on the next evaluation whether or not that was intended.
A file must also be tracked by git before a flake build can see it, because flake sources are git-tracked only and an untracked file is absent from the build rather than an error.

## Children

- `apps/` — flake apps, invoked as `nix run .#<name>`.
- `brand/` — shared brand assets and palette definitions.
- `checks/` — flake checks; see `preferences-nix-checks-architecture` for the check taxonomy.
- `clan/` — clan inventory, services, and machine registration.
- `containers/` — OCI image definitions.
- `darwin/` — nix-darwin system aspects.
- `devshells/` — development shells surfaced through direnv.
- `effects/` — deployment effects run outside the build sandbox.
- `home/` — home-manager aspects; the largest subtree, indexed by its own README.
- `lib/` — helper functions shared across modules.
- `machines/` — per-machine composition, binding aspects to hosts.
- `nixos/` — NixOS system aspects.
- `nixpkgs/` — channel selection and the overlay stack.
- `system/` — cross-platform system aspects.
- `terranix/` — cloud resource definitions rendered to OpenTofu.
- `vm-tests/` — on-demand KVM-only tests exported as `vmTests.<system>.<name>`, outside PR gating.

Top-level files configure the flake itself: `flake-parts.nix`, `formatting.nix`, `systems.nix`, `debug.nix`, `kubernetes.nix`, and `nixidy.nix`.

## Shared CLI capabilities

`system/cli-tools/` exports `cli-unix`, `cli-archives`, `cli-network`, and their `cli-tools` aggregate under each of `flake.modules.nixos`, `flake.modules.darwin`, and `flake.modules.homeManager`.
Import the export matching the consumer's module class; package selection uses that consumer's `pkgs`.
The aggregate adds jq through its configured Home Manager module or as a system package.
These exports are opt-in: Omnigent workers import `homeManager.cli-tools`, while human terminal declarations remain independent.
Worker profiles prefer procps' `kill` over coreutils' overlapping executable, matching the existing supervisor PATH; the shared capabilities impose no worker-specific package priorities.
`checks.<system>.omnigent-worker-capabilities` evaluates the matching system adapter and Home Manager adapter, then exercises file, text, archive, and JSON operations on the generated worker PATH without a login shell or network requests.
Its foreign-input guards keep the ordinary-sized fixtures; the two 300,000-character settings fixtures that checked the same guards at size were removed for evaluation cost.

## On-demand VM tests

`nixbot.toml` evaluates `checks.x86_64-linux`; VM tests instead live under `vmTests` and are not part of pull-request coverage.
The independent `checks.<system>.zerotier-mss-clamp` structural check remains gated.
Run the runtime test on a reachable KVM-capable Linux host, such as Pyrite, from its checkout of the intended revision:

```sh
nix build .#vmTests.x86_64-linux.zerotier-mss-clamp-runtime
```

The test requires `kvm` and `nixos-test` builder features and forces KVM acceleration rather than falling back to TCG.
Unavailable hardware is a build failure if this command is requested, not a passed or silently skipped test.
Leaving this output outside PR gating allows operators to run it when a suitable host is available without making PR CI depend on a laptop.
Automatic opportunistic scheduling and registering Pyrite as a remote builder are deferred; adding a builder alone does not put this output back into PR gating.
Every NixOS host imports `system/kvm-declaration.nix` and states `declaredKvm.present` explicitly, because NixOS advertises `kvm` in `nix.settings.system-features` unconditionally and that claim is true only on Pyrite: Cinnabar, Electrum, Galena, Magnetite, and Scheelite are cloud VMs without nested virtualisation.
Evaluation cannot inspect a machine's device nodes, so the option is an operator declaration rather than a detection, and a wrong declaration is visible at one line per host instead of inherited silently.
Stibnite's `nix.buildMachines` mirror of the rosetta builder no longer advertises `kvm` either; the VM has no `/dev/kvm`, and Rosetta translates userspace rather than providing a hypervisor.
Corrected advertisements take effect only after each machine is activated.
New VM test modules belong in `vm-tests/` and assign `perSystem.vmTests`, using the same automatically discovered flake-parts composition as the other module directories.

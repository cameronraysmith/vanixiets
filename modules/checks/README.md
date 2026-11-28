---
title: Flake checks
created: 2026-11-27
---

## Flake checks

Every file here defines outputs under `checks.<system>`, which nixbot builds on every pull request for `x86_64-linux` and `aarch64-darwin`.
A fact is checked on the cheapest rung that can observe its failure, and a check that a cheaper rung could replace without losing a failure mode is moved there.

## The ladder

1. **A fact about one configuration's values** is a module `assertions` entry, or a fleet obligation judged in the existing machine checks.
   The machine checks (`checks/machines.nix`, `nixos-<host>` and `darwin-<host>`) evaluate every checked host anyway, so the fact is judged against real values at almost no extra cost.
   An obligation is registered beside the judge it runs, as `fleetObligations.<key> = { classes; failures = name: hostConfig: [ message ]; }` (`lib/fleet-obligations.nix`; example `darwin/resolver-reload.nix`), and its key enters the literal `registeredObligations` list in `checks/machines.nix`.
   Its fixtures and mutants are one `flake.lib.mkJudgeCheck` check (`lib/judge-check.nix`; example `checks/mesh-hosts-obligations.nix`).
2. **A fact that must also hold on hosts the machine checks skip, a fact across configurations, or a fact about the flake's structure** is a check in this directory.
   Example: `sshd-no-keyboard-interactive.nix` compares one sshd setting on every NixOS machine of the inventory, with a mutant that must differ.
3. **Runtime behaviour**, what a built system does when it runs, is a runtime test under `modules/vm-tests/`, outside pull-request gating.

Pure logic of our own is tested in-process beside the function, as `home/users/lib.test.nix` tests `home/users/lib.nix`.

### The one exception to rung 1

Fleet obligations run only in the machine checks, and the registry's `checked = false` (`flake.fleet.hosts.<name>.checked`, `lib/hosts.nix`; scheelite) removes a host's machine check.
A fact that must hold on such a host as well is therefore a standalone check on rung 2, even though it is about one configuration's values.

Before adding a setting and a check for "every host", read the option's default: a setting nixpkgs or nix-darwin already turns on needs neither.

## What every check here carries

- **A literal attribute name.** Names come from static data (the registry, the inventory's names), never from an evaluated configuration, so listing `checks` evaluates no host; configurations are read only in a check's value.
- **A size class** in `testSizes.checks`, beside the check's definition; `checks/test-size-classes.nix` fails on a check without one. An unmeasured check is `class = "medium"; measured = false;`.
- **A negative control in the same comparison.** A structural check built with `flake.lib.mkStructuralCheck` carries a phantom entry whose `expected` value is the one a correct comparison gives it, so the equality passes only if the comparison really tells the phantom apart (`checks/validation.nix`, `home-module-exports`). A judge over fixtures carries a case that must fail, with its expected count of failures. A check that compares a value with itself, both sides drawn from one source, judges nothing and is deleted.
- **A source no wider than it reads**, so an unrelated change does not rebuild it.

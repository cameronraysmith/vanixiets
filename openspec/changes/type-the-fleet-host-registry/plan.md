# Type the fleet host registry implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** one typed record per fleet host, `flake.fleet.hosts.<name>`, from which the Nix system table, inventory class and NixOS deploy target, `clan.machines` with `nixpkgs.hostPlatform`, the darwin tests, the collector platforms, the NixOS key-host list, the lifecycle selections, cloud memory, role membership and the ZeroTier controller's external members are all derived. `flake.lib.hosts` stays as a read-only alias. This covers tasks.md groups 1–8.

**Architecture:** `modules/lib/hosts.nix` declares a flake-parts option, an `attrsOf` submodule with declared and read-only fields, and holds the values. Readers either keep using `flake.lib.hosts` (the alias) or read `config.flake.fleet.hosts`. A new `modules/lib/inventory-members.nix` holds the role resolver. No vendored module is patched: clan-core's inventory, `clan.machines` and ZeroTier settings are used through their documented options.

**Tech Stack:** flake-parts with import-tree; the nixpkgs module system (`types.submodule`, `readOnly`, `apply`); clan-core inventory and `clan.machines`; terranix's `flake.lib.cloudMachines` (read only).

**Spec:** `openspec/changes/type-the-fleet-host-registry/`: `design.md` (D1–D10), `specs/fleet-host-registry`, `specs/fleet-host-registry-interface`, `specs/world-assumptions` (A300–A305), `tasks.md`, `brainstorm.md`, `proposal.md`.

---

## Global Constraints

- Lands after establish-refactor-oracle and stop-reading-other-hosts-configs; its parent is the latter's tip, and after any rebase onto it `just drv-diff` is re-run from the new parent. `just drv-diff` is the acceptance oracle; `just eval-identity` is not (it compares stock and iets at one revision).
- One pull request of one commit: the task groups 2, 3, 4 and 5 are not separately shippable, and a drvPath diff costs about 15 minutes. Each group keeps its own evidence by evaluation against task 1's baselines. Edits are made in `@` and routed into the change's chain with `jj squash --into <chain> --use-destination-message --keep-emptied <paths>`. This repository is a shared jj development join, so never `jj new`, `describe` or `commit` on another session's chain.
- The commit and the merged head each run `just drv-diff <parent> <tip> openspec/changes/type-the-fleet-host-registry/drv-delta.txt` once, which declares `nixos.cinnabar`, `checks.x86_64-linux.nixos-cinnabar`, `checks.x86_64-linux.eval-fleet-topology`, `checks.x86_64-linux.fleet-topology-fresh`, `checks.x86_64-linux.fleet-alert` and the checks that build or consume the docs package changed, and `checks.x86_64-linux.eval-inventory-members` added (design D10).
- Check key sets read only `flake.fleet.hosts`, the inventory, literals and `system`; never an evaluated configuration.
- Mutants run in a throwaway tree (`jj workspace add` under `/tmp`, or a `git worktree`), never in `@`, and each runs only the expression it must fail.
- Every run is small or medium. The drvPath diff's own duration is set by establish-refactor-oracle. If it exceeds 5 minutes, announce it with its expected duration, the fact that it alone proves neutrality, and that the commit's push waits on it.

## Grounding: the vendored consumers' interfaces

- clan-core inventory machine entry: `tags : listOf str`, `machineClass : enum [ nixos darwin ]`, `description`, `deploy.targetHost`. `flake.clan.machines.<name>` is a module for that machine's configuration.
- clan-core ZeroTier controller (`clanServices/zerotier/default.nix:173,241,338`): `roles.controller.machines.<m>.settings.allowedIps : listOf str`, concatenated before the clan members' addresses and rendered into the controller's script in list order. Re-read at the locked revision `78d5de23` before task 5.3.
- nixpkgs module system: a type mismatch and `lib.assertMsg` both `throw` (`lib/modules.nix` "is not of type"). Re-read at the locked revision `2074cc67` before task 2.4.
- clan role membership: named machines plus tagged machines, with `all` matching every machine (clan-core `lib/inventory/distributed-service/tests/default.nix:267`). Locate the resolving function in clan-core before task 5.1 and cite it in the resolver's header.

## Interface contract

| Kind | Name | Defined in |
|---|---|---|
| Option | `flake.fleet.hosts.<name>` declared: `system`, `endpoints`, `deployUser`, `services`, `zerotier.{address,memberId}`, `primaryUser`, `memory`, `nixClassic`, `checked`, `stateVersion` | Task 2 |
| Option (read-only) | `class`, `fqdn`, `address`, `targetHost`, `memoryGiB`, `enrolled`, `cloud` | Tasks 2, 4 |
| Lib alias | `flake.lib.hosts = config.flake.fleet.hosts` | Task 2 |
| Lib | `flake.lib.machineSystems` (derived) | Task 3 |
| Lib | `flake.lib.hostKeys`: NixOS names derived from `class` (stop-reading-other-hosts-configs' `nixosKeyHosts`) | Task 3 |
| Lib | `flake.lib.cloudMachineMemoryGiB : attrsOf ints.positive` | Task 4 |
| Lib | `flake.lib.inventoryMembers : instance -> role -> [str]`; `flake.lib.inventoryMembersIn : machines -> instance -> role -> [str]` | Task 5 |
| Check | the resolver's evaluation check, `checks.x86_64-linux.eval-inventory-members`, with a `testSizes` entry `small` (`measured = false` until nixbot runs it) | Task 5 |

---

## Task 1: Baseline (tasks 1.1–1.2)

- [ ] **Step 1:** Confirm establish-refactor-oracle and stop-reading-other-hosts-configs have landed and this change is rebased onto the latter's tip. Read `just drv-diff`'s usage and the oracle's base allow-list.
- [ ] **Step 2:** Run `just drv-diff <parent> <parent>`; it must exit 0.
- [ ] **Step 3:** At the parent revision, dump the projections:

```bash
nix eval --json .#lib.hosts --apply 'hs: builtins.mapAttrs (_: h: { inherit (h) class endpoints deployUser services zerotier fqdn address primaryUser memoryGiB nixClassic targetHost; }) hs' > logs/thr-1-hosts-<ts>.json
nix eval --json .#lib.machineSystems > logs/thr-1-machine-systems-<ts>.json
nix eval --json .#clan.inventory.machines --apply 'ms: builtins.mapAttrs (_: m: { inherit (m) machineClass; deploy = m.deploy or null; }) ms' > logs/thr-1-inventory-<ts>.json
nix eval --json .#clan.inventory.instances.zerotier.roles.controller.machines.cinnabar.settings.allowedIps > logs/thr-1-allowed-ips-<ts>.json
nix eval --json .#lib.observabilityHosts --apply 'hs: builtins.mapAttrs (_: h: h.platform) hs' > logs/thr-1-platforms-<ts>.json
nix eval --json .#checks.x86_64-linux --apply builtins.attrNames > logs/thr-1-checks-x86-<ts>.json
nix eval --json .#checks.aarch64-darwin --apply builtins.attrNames > logs/thr-1-checks-darwin-<ts>.json
```

- [ ] **Step 4:** Record the tincr peers. Read the instance's `roles.peer.machines` names from `.#clan.inventory.instances` (the instance name is `flake.lib.mesh.instance`).
- [ ] **Step 5:** Measure the key set three times in fresh processes: `NIX_SHOW_STATS=1 nix eval .#checks.x86_64-linux --apply builtins.attrNames`. Record CPU time and thunks.

## Task 2: The typed record (tasks 2.1–2.4)

**Files:** `modules/lib/hosts.nix`.

- [ ] **Step 1:** Declare the option. Shape (the field list is design D1):

```nix
{ config, lib, self, ... }:
let
  inherit (config.flake.lib) fleet mesh cloudMachines;
  cloud = lib.concatMapAttrs (provider: ms: lib.mapAttrs (_: m: {
    inherit provider;
    type = m.serverType or m.machineType;
    inherit (m) enabled;
  }) ms) cloudMachines;
  hostModule = { name, config, ... }: {
    options = {
      system = lib.mkOption { type = lib.types.nullOr (lib.types.enum [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ]); };
      # endpoints, deployUser, services, zerotier, primaryUser, memory, nixClassic, checked, stateVersion …
      class = lib.mkOption { readOnly = true; type = lib.types.enum [ "nixos" "darwin" "android" ]; };
      # fqdn, address, targetHost, memoryGiB, enrolled, cloud …
    };
    config = {
      class =
        if config.system == null then "android"
        else if lib.hasSuffix "-darwin" config.system then "darwin"
        else "nixos";
      fqdn = "${name}.${fleet.domain}";
      address = mesh.addressOf mesh.instance name;
      targetHost = if config.deployUser == null then null else "${config.deployUser}@${name}.zt";
      enrolled = builtins.pathExists (self + "/sops/machines/${name}");
      cloud = cloud.${name} or null;
    };
  };
in
{
  options.flake.fleet.hosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule hostModule);
    description = "The fleet's host registry: one record per member.";
  };
  config.flake.fleet.hosts = { /* twelve members */ };
  config.flake.lib.hosts = config.flake.fleet.hosts;
}
```

  Put the class-dependent checks for `memory`, `nixClassic` and `stateVersion` in each option's `apply`, as `lib.assertMsg … "flake.fleet.hosts.${name}.<field>: …"`, so they fire on read and `throw`.
- [ ] **Step 2:** Move each member's values from `members`, `primaryUsers`, `memoryGiB` and `nixClassic` into its entry. Add `system` from the `machineSystems` literal, null for the phones. Add `stateVersion` from the host modules (tasks 2.1), and `checked = false` on scheelite.
- [ ] **Step 3:** Keep `flake.lib.meshRecords`, reading `config.flake.fleet.hosts`.
- [ ] **Step 4:** Evaluate the twelve names and diff the alias projection against `logs/thr-1-hosts-<ts>.json`. It must be empty.
- [ ] **Step 5:** Run the four mutants of task 2.4 in a throwaway tree; log them.
- [ ] **Step 6:** No separate drvPath diff: the group's evidence is Steps 4 and 5.

## Task 3: Derive system, class and the seam (tasks 3.1–3.9)

**Files:** `modules/lib/hosts.nix`, `modules/clan/inventory/machines.nix`, `modules/clan/machines.nix`, the nine host files, `modules/lib/host-keys.nix`, `modules/lib/{commit-signing,omnigent-fleet-obligations}.nix`, `modules/system/{deploy-record,harmonia-gc,mesh-hosts}.nix`, `modules/lib/observability-hosts.nix`, `modules/clan/inventory/services/otel-collector.nix`.

- [ ] **Step 1:** In `hosts.nix`: `flake.lib.machineSystems = lib.mapAttrs (_: h: h.system) (lib.filterAttrs (_: h: h.system != null) config.flake.fleet.hosts);`. Delete the literal in the inventory file.
- [ ] **Step 2:** In the inventory file, turn the attrset into `lib.mapAttrs (name: m: m // { machineClass = hosts.${name}.class; } // lib.optionalAttrs (hosts.${name}.class == "nixos") { deploy.targetHost = hosts.${name}.targetHost; }) { cinnabar = { tags = …; description = …; }; … }`. Keep the header comment's darwin rule.
- [ ] **Step 3:** Rewrite `clan/machines.nix` as a `mapAttrs` over the hosts with a system, setting `imports` and `nixpkgs.hostPlatform`. Delete the nine `hostPlatform` lines.
- [ ] **Step 4:** Replace the seven suffix tests with `config.flake.lib.hosts.${name}.class == "darwin"` (or `self.lib.hosts` in perSystem checks).
- [ ] **Step 5:** In `observability-hosts.nix`, make each row's `platform` read the registry's class. Keep the `agent` helper's `platform = "nixos"` default for rows the VM tests build. Delete `mismatched` in `otel-collector.nix`.
- [ ] **Step 6:** In `modules/lib/host-keys.nix`, replace the literal `nixosKeyHosts` with `lib.attrNames (lib.filterAttrs (_: h: h.class == "nixos") config.flake.fleet.hosts)`. Leave every assert in `checks/machines.nix:100-123` in place; the two name asserts catch a literal inventory entry with no record, and the directory assert catches a record with no inventory entry, since clan-core adds every `clan.machines` name to the inventory (design D4).
- [ ] **Step 7:** Evaluate each projection and `attrNames flake.lib.hostKeys` against its baseline, run the three mutants of task 3.8, and build `network-target-obligations`, `fleet-alert` and `otel-collector-config`.
- [ ] **Step 8:** Re-measure the key set against task 1's measurement.

## Task 4: Lifecycle, cloud and memory (tasks 4.1–4.6)

**Files:** `modules/lib/hosts.nix`, `modules/checks/machines.nix`, `modules/clan/inventory/services/tincr.nix`, `modules/lib/observability-hosts.nix` (comment), `modules/lib/fleet-deployer.nix`.

- [ ] **Step 1:** Add `flake.lib.cloudMachineMemoryGiB`, and compute `memoryGiB` as `if config.cloud != null then cloudMachineMemoryGiB.${config.cloud.type} or (throw "…: cloud machine type ${config.cloud.type} has no memory in flake.lib.cloudMachineMemoryGiB") else config.memory`. Delete the five cloud `memory` values.
- [ ] **Step 2:** In `checks/machines.nix`, replace `!(builtins.elem name deferred)` with `self.lib.hosts.${name}.checked` in both places, and delete `deferred`.
- [ ] **Step 3:** In `tincr.nix`, set `peers = lib.filterAttrs (_: host: host.class != "android" && host.enrolled) hosts;`.
- [ ] **Step 4:** In `fleet-deployer.nix`, set `enabledOf = name: (hosts.${name}.cloud or null).enabled or true;` and delete the local `cloud` merge if nothing else reads it.
- [ ] **Step 5:** Evaluate memory, peers, check names and deployer targets against their baselines. Run the `cx99` mutant. Build `nix-eval-jobs-iets` and `fleet-deployer-obligations`.
- [ ] **Step 6:** No separate drvPath diff: the group's evidence is Step 5.

## Task 5: Role membership, admission and the tag rename (tasks 5.1–5.5)

**Files:** new `modules/lib/inventory-members.nix` and its `.test.nix`; `modules/lib/fleet-topology.nix` and `fleet-topology.test.nix` (its `config.flake.lib` stub gains `inventoryMembersIn`); `modules/checks/{zerotier-mss-clamp,zerotierone-controller}.nix`; `modules/apps/omnigent-worker-login.nix`; `modules/clan/inventory/services/zerotier.nix`; `modules/clan/inventory/machines.nix` (stibnite's tag); `packages/docs/diagrams/topology/fleet.json` (regenerated).

- [ ] **Step 1:** Write the resolver:

```nix
inventoryMembersIn = machines: instance: role:
  let
    r = instance.roles.${role} or { };
    tags = builtins.attrNames (r.tags or { });
    byTag = builtins.filter (n: lib.elem "all" tags || lib.any (t: lib.elem t (machines.${n}.tags or [ ])) tags) (builtins.attrNames machines);
  in
  lib.sort lib.lessThan (lib.unique (byTag ++ builtins.attrNames (r.machines or { })));
```

  `inventoryMembers = inventoryMembersIn config.flake.clan.inventory.machines;`. Check whether fleet-topology's `namesOf` accepts lists as well as attrsets for `tags`, and match it.
- [ ] **Step 2:** Write the evaluation test (five cases) and a mutant that ignores `all`. Register `testSizes.checks.eval-inventory-members` beside it.
- [ ] **Step 3:** Switch the four readers. In `omnigent-worker-login.nix`, assert that `inventoryMembers omnigent "server"` has length 1 and that the member is a key of `.roles.server.machines`, then read that entry's `settings`.
- [ ] **Step 4:** In `zerotier.nix`, set `allowedIps = map (h: h.zerotier.address) (lib.attrValues (lib.filterAttrs (_: h: lib.elem h.class [ "darwin" "android" ]) config.flake.lib.hosts));` and update the comment.
- [ ] **Step 5:** Build the topology, clamp and controller checks. Evaluate `allowedIps` and compare it as a set with the baseline.
- [ ] **Step 6:** In `modules/clan/inventory/machines.nix`, replace stibnite's tag `controller` with `deployer-workstation`; leave cinnabar's `controller`. Run `just topology-generate`, confirm `fleet.json` changes only in stibnite's `tags`, and build `fleet-topology-fresh`. Evaluate the inventory machines carrying `controller`: exactly cinnabar.
- [ ] **Step 7:** Route the whole change into its chain as one commit, "hosts: record each fleet host once as one typed record", and run `just drv-diff <parent> <commit> openspec/changes/type-the-fleet-host-registry/drv-delta.txt`; it must exit 0.

## Task 6: Documents (task 6.1)

- [ ] **Step 1:** Update `modules/README.md` (:51 and the registry description), and the header comments touched in tasks 3–5.
- [ ] **Step 2:** Re-read ADR-0019:70-75 and ADR-0020:116-121 and decide whether their `hostPlatform` wording now matches. Amend only where it does not.
- [ ] **Step 3:** Run `prek run --files` on the changed documents.

## Task 7: Deploy and integration (tasks 7.1–8.3)

- [ ] **Step 1:** After merge, run `clan machines update cinnabar`, logging to `logs/thr-7-cinnabar-deploy-<ts>.log`.
- [ ] **Step 2:** Read the posts on the fleet alert and failure topics since the deploy start, and explain each.
- [ ] **Step 3:** On cinnabar, read the controller's admitted addresses and confirm the six.
- [ ] **Step 4:** Run `just drv-diff <parent> <merged head> openspec/changes/type-the-fleet-host-registry/drv-delta.txt` and the projection diffs at the merged head against task 1's baselines, and run the search of task 8.3.

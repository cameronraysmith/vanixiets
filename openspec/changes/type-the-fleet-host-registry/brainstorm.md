<!--
Raw capture of the decision chain for this change.
No interactive brainstorming session ran. The operator settled the direction in advance: a typed `flake.fleet.hosts` option with `flake.lib.hosts` kept as a read-only alias, and the stibnite `controller` tag rename left to the operator. The operator was not available to answer questions while this file was written.
The forks below were settled from the repository as read on 2026-11-26 and from the den-readiness audit of the same day. That audit is a session artifact outside the repository, so every figure and location it supplied was re-read in the tree and is restated here; this file stands alone without it.
Each fork the operator may want to overturn is repeated as an open question in design.md.
-->

# Brainstorm: one typed record per fleet host

## Background

### What a host is today

A fleet host's facts are written in six places, and four of them encode its kind:

| Where | What it holds | Kind written as |
|---|---|---|
| `modules/lib/hosts.nix:10-137` (`members`) | endpoints, deploy user, service labels, ZeroTier address and member id, for 12 members including the phones `pixel7` and `pixel11` | `class = "nixos" \| "darwin" \| "android"` |
| `modules/lib/hosts.nix:144-194` | primary user, memory in GiB, the iets classic-mode trial | — |
| `modules/clan/inventory/machines.nix:10-21` (`flake.lib.machineSystems`) | the Nix system of the 10 hosts that build a configuration | `"x86_64-linux"` / `"aarch64-darwin"` |
| `modules/clan/inventory/machines.nix:23-139` | tags, description, `machineClass`, NixOS `deploy.targetHost` | `machineClass = "nixos" \| "darwin"` |
| 8 host modules plus `modules/darwin/laptop.nix:69` (argentum, rosegold) | `nixpkgs.hostPlatform` | the system string again |
| `modules/lib/observability-hosts.nix:39-160` | collector rows | `platform = "nixos" \| "darwin"` |

The 8 host modules are `machines/nixos/{cinnabar:42,electrum:38,galena:37,scheelite:41,magnetite:143,pyrite:138}/default.nix` and `machines/darwin/{blackphos:59,stibnite:75}/default.nix`.

Seven readers test "is this host darwin?" by `lib.hasSuffix "-darwin"` on `machineSystems`. They are `checks/machines.nix:63` and `:67`, `lib/commit-signing.nix:188`, `lib/omnigent-fleet-obligations.nix:179`, `system/deploy-record.nix:148`, `system/harmonia-gc.nix:79` and `system/mesh-hosts.nix:84`. (`containers/default.nix:50` tests the perSystem `system`, not a host, and is out of scope.)

What holds these together is name-only asserts. `checks/machines.nix:100-117` compares the attribute names of `machineSystems`, the inventory, `nixosConfigurations`, `darwinConfigurations`, `clan.machines` and the `modules/machines/<class>/` directories. `clan/inventory/services/otel-collector.nix:14-34` compares `observabilityHosts.<h>.platform` with the inventory's `machineClass`. Nothing compares `hosts.<h>.class` with `machineClass`, or `machineSystems` with `nixpkgs.hostPlatform`.

The registry lives in `flake.lib`, which `modules/lib/option.nix:3-6` types as `lazyAttrsOf raw`. That type forbids two files writing the same nested path, which is why `hosts.nix:4-5` says the registry is "consolidated into this single file". It also gives each field no type: memory is checked by a hand-written `assertMsg` (`hosts.nix:179-190`), the primary user by another (`:151-159`), and the cross-table consistency by three more (`:196-205`).

### Facts about a host's life that are kept apart, and must stay apart

- **Deferred from checks.** `checks/machines.nix:6` lists `deferred = [ "scheelite" ]`. A deferred host gets no machine check; scheelite's only coverage is the fleet-wide sshd, zram and ZeroTier checks.
- **Cloud server up or down.** `lib/cloud-machines.nix` sets `enabled` per cloud host, and terranix creates or destroys the server from it. Today cinnabar and magnetite are `true`; electrum, galena and scheelite are `false`. Reusing `enabled` for "deferred" would drop the checks `nixos-electrum` and `nixos-galena`, which run today.
- **A name with no machine behind it.** blackphos has a host module (`machines/darwin/blackphos/`) but no clan machine key: `sops/machines/` and `vars/per-machine/` list every other NixOS and darwin host but not blackphos. The tincr peer set skips it by name (`clan/inventory/services/tincr.nix:22-24`, "reserved name with no machine"). The collector row keeps `collect = false` for it (`observability-hosts.nix:153-158`). `lib/commit-signing.nix:183` already tests the same fact as `!pathExists sops/machines/<name>`.
- **Clan install timestamp.** `inventory.json` records `installedAt` for the six NixOS hosts only, electrum included even though its server is destroyed. Darwin hosts are never `clan machines install`ed, so they have no entry.
- **Signing legacy and deployer workstations.** These are relations, not lifecycle states. `commitSigningLegacyMachines = [ "blackphos" ]` (`lib/commit-signing.nix:11`) names the machines whose homes sign with the login key. `excluded = [ "stibnite" "blackphos" ]` (`lib/fleet-deployer.nix:38-41`) names the operator's workstations that the fleet deployer never targets.

### Memory copied by hand

`hosts.nix:167-172` writes the memory of each cloud host with its server type in a comment (`cinnabar = 16; # cx43`). `cloud-machines.nix` writes the same server types (`serverType = "cx43"` at :12, `machineType = "n1-standard-8"` at :53). Nothing ties the two, so a resized server keeps its old memory in the registry. The memory alone decides whether the host's evaluator is iets or stock, and its bound (`lib/nix-eval-jobs-host.nix`).

### Role membership resolved three ways

- `lib/fleet-topology.nix:89-98` (`membersOf`) resolves a clan role as named machines plus machines carrying any of the role's tags, with the `all` tag matching every machine.
- `checks/zerotier-mss-clamp.nix:20-27` (`roleMembers`) does the same but ignores `all`.
- `checks/zerotierone-controller.nix:36-38` and `apps/omnigent-worker-login.nix:3-6` read `roles.<r>.machines` only, so a member added by tag would be missed.

The ZeroTier controller's `allowedIps` (`clan/inventory/services/zerotier.nix:17-24`) is a hand-written list of the six members that do not join ZeroTier through clan: the four darwin hosts and the two phones. That is exactly the set whose class is darwin or android.

Two hosts carry an inventory tag `controller` with different meanings. On cinnabar (`machines.nix:29`) it means the ZeroTier controller; on stibnite (`:112`) it means the operator's deployment workstation. No clan role reads either tag, so the only consumer is `clan machines update --tags controller` from the operator's shell.

## Decision chain

**Q1. Where does the host entity live?**
Options: (a) a new typed option `options.flake.fleet.hosts = attrsOf (submodule …)`; (b) keep one raw file under `flake.lib` and add more asserts.
→ (a), settled by the operator. It types every field, lets a later change add a field from its own file (needed by the host↔user relation record), and is a direct rename away from den's `den.hosts.<system>.<host>`. `flake.lib.hosts` stays as a read-only alias, so its ~40 readers keep working and migrate at their own pace. `flake.users` (`modules/home/users/lib.nix:41`) is the precedent: a typed `flake.*` option with read-only derived fields.

**Q2. Which fact is primary: class or system?**
Options: (a) declare `system` and derive `class`; (b) declare `class` and `system` and assert they agree; (c) declare `class` and derive `system` from a default per class.
→ (a). Only `system` carries information `class` does not: aarch64 vs x86_64. Declaring both repeats the fact with an assert, which is today's arrangement in a smaller form. (c) breaks the first time an aarch64-linux host arrives.
The phones run no Nix configuration, so their `system` is null and their class is `android`. The `-darwin` suffix test then lives in one place, the derivation of `class`.

**Q3. What is derived from the record?**
- `flake.lib.machineSystems` becomes `mapAttrs (_: h: h.system)` over the hosts whose system is non-null. It stays flake-level data, never read back from an evaluated configuration, so check key sets that read it stay cheap (`preferences-nix-checks-architecture` SKILL.md:153,172).
- The inventory's `machineClass` and, for NixOS hosts, `deploy.targetHost` are generated from the record. Tags and descriptions stay literal per host in `clan/inventory/machines.nix`.
- `flake.clan.machines` is generated from the record. Each entry imports `flake.modules.<class>."machines/<class>/<name>"`, keeping the key ADR-0020 fixes, and sets `nixpkgs.hostPlatform = system`. The nine literal `hostPlatform` lines are deleted.
- The seven suffix readers read `class` from the record.
- The collector table's `platform` is set from the record's class. The `platform`-vs-`machineClass` assert in `otel-collector.nix` then compares a value with itself and is removed.

**Q4. Which asserts survive?**
- The registry-vs-inventory asserts become tautologies and are deleted: `machineSystems` names vs inventory names, and `clan.machines` names vs inventory names. (Revised in design D4: the inventory keeps its own literal entries, so these asserts still compare two independent sources and are kept.)
- Kept: inventory vs `nixosConfigurations` / `darwinConfigurations`, because they compare against clan's output. Also kept: the `modules/machines/<class>/` directory asserts, because they compare against the file tree, which the record cannot write.
- Kept unchanged: the flake-shape golden pin (`checks/structure/flake-shape.nix`). It is an independent literal and the oracle a den migration will be measured against, so it must not be derived from the record it checks.

**Q5. How are lifecycle facts typed?**
→ As separate fields, never one enum. A lifecycle enum (`active | deferred | reserved | legacy`) would force one value where the facts are independent: electrum is checked, its server is down, and it is enrolled.
- `checked : bool`, default true; scheelite false. Replaces `deferred`.
- `enrolled`, read-only: true when `sops/machines/<name>` exists in the repository. Replaces tincr's `name != "blackphos"`.
- `cloud`, read-only: `null` or `{ provider, type, enabled }`, read from `flake.lib.cloudMachines`, which stays the single writer terranix reads.
- `installedAt` from `inventory.json` was considered for "provisioned" and rejected. Darwin hosts never have it, and electrum has it while its server is destroyed, so it cannot say whether a machine stands behind a name.
- Signing legacy and deployer workstations stay in their own files as relations.

**Q6. Memory of cloud hosts.**
→ A table from cloud machine type to GiB (`cx43 = 16; ccx23 = 16; cx53 = 32; e2-standard-8 = 32; n1-standard-8 = 30;`). A cloud host's memory is that table at its `cloud.type`; a missing type fails evaluation and names the type. Other hosts keep their declared memory, including blackphos's `"unknown"`, which `modules/README.md:51` specifies.
The report `nixEvalJobsBoundProblems` (`nix-eval-jobs-host.nix:169-173`) catches an unreadable memory with `builtins.tryEval`. That keeps working only if every failure on that path is a `throw`, not an `abort` or an `assert` without a message. `lib.assertMsg` and the module system's type errors are both `throw` (nixpkgs `lib/modules.nix`, "is not of type"). The memory field keeps its derivation lazy and its check a `throw`.

**Q7. One role resolver.**
→ `flake.lib.inventoryMembers instance role` returns the sorted, unique names that are named in `roles.<role>.machines` or carry one of its tags, with `all` matching every inventory machine. It reads only the declared inventory, never a configuration (`fleet-topology.nix:6-8`). Its four readers use it:
- fleet-topology's `membersOf`;
- the MSS-clamp check, which gains `all`;
- the controller check;
- the worker-login app, which still needs per-machine `settings` and so asserts exactly one member that is named in `.machines`.

**Q8. ZeroTier `allowedIps` from class.**
→ The ZeroTier addresses of every member whose class is darwin or android, in registry name order. This is the same six members.
The order changes: today it is blackphos, stibnite, argentum, rosegold, pixel7, pixel11, and name order is argentum, blackphos, pixel11, pixel7, rosegold, stibnite. clan's ZeroTier controller writes `allowedIps ++ networkIps` into its unit script in list order (clan-core `clanServices/zerotier/default.nix:241,338`). So cinnabar's system derivation changes, and only it does. Kept as a declared drvPath change rather than preserving the old order with a hand-kept list, which would restate the set. The fleet-topology model builds an attribute set from the list and does not change. The operator accepted the reorder on 2026-11-26.

**Q9. The `controller` tag homonym.**
→ Left to the operator when this file was written. The operator decided on 2026-11-26 to rename stibnite's tag to `deployer-workstation` (design D12), so `clan machines update --tags controller` selects only cinnabar. The rename is one inventory line plus the regenerated topology files.

**Q10. State version (scope added by the operator on 2026-11-26).**
→ The record gets a declared `stateVersion` field. This change only declares and fills it; a later change (compose-hosts-from-cohesive-aspects) makes the host modules read it in place of their own lines.
- Today the darwin base sets `system.stateVersion = 5` (`darwin/base.nix:54`), and every darwin host forces 4 over it with `lib.mkForce`: `darwin/laptop.nix:72` for argentum and rosegold, `machines/darwin/blackphos/default.nix:63` and `machines/darwin/stibnite/default.nix:79`.
- The NixOS hosts write a release string: `"25.05"` on cinnabar, electrum, galena, scheelite and magnetite, and `"26.05"` on pyrite (`machines/nixos/pyrite/default.nix:160`). `system/nix-settings.nix:21` sets `mkDefault "24.11"` beneath them.
- The type is `nullOr (either ints.positive str)`: an integer for nix-darwin, a release string for NixOS, and null for a phone. A class-dependent check (integer on darwin, string on NixOS, null on android) fails with a `throw` like the memory check.
- Nothing reads the field in this change, so no configuration changes. Until the later change lands, the field and the host modules are two copies of one fact. The record carries the same values, and the later change's drvPath diff proves they agree when it switches the readers over.

## Trade-offs carried forward

- Declaring `flake.fleet` adds a `fleet` flake output, as `flake.users` and `flake.userAliases` already do. `nix flake check` lists unknown outputs as a warning; nothing fails on it.
- Typing does not make evaluation eager. Every check stays lazy and fires only when the field is read, so the gain is in error messages and a fixed shape, not speed.
- The change is meant to leave every evaluated output's drvPath unchanged except cinnabar's (Q8). The proof is the before/after drvPath diff that the change establishing the refactor oracle commits. `just eval-identity` compares stock and iets evaluation at one revision and cannot show this.

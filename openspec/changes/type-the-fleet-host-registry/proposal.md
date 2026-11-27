---
linear_story_id: CAM-134
linear_story_identifier: CAM-134
linear_story_title: "Record each fleet host once, as one typed record"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-134/record-each-fleet-host-once-as-one-typed-record
linear_story_state: In Review
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: In Review
last_synced_at: "2026-11-27T06:20:11Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-26T23:02:17Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-134 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes; state and project confirmed by read-only view; bind comment posted" }
  - { at: "2026-11-27T05:44:22Z", transition: "Todo->In Progress", outcome: "posted", note: "first tasks.md checkbox (1.2 baseline) checked; state confirmed In Progress by read-only view" }
  - { at: "2026-11-27T06:20:11Z", transition: "In Progress->In Review", outcome: "posted", note: "verify.md written (PASS WITH WARNINGS); state confirmed In Review by read-only view; comment posted" }
---

## Why

Each fleet host's facts are spread across six hand-kept tables, and its kind is written four ways: a class, a Nix system, an inventory class and a collector platform. Asserts compare only names, so a host whose kind or memory drifts in one table goes unnoticed. Cloud memory is copied by hand from server types, and role membership is resolved three ways. One typed record per host, with everything else derived from it, removes these drift points, and it is the step that makes a later move to den mechanical rather than a redesign.

## What Changes

**One typed host record**
- From: `flake.lib.hosts` is untyped data in one file (`lib/hosts.nix`), guarded by hand-written asserts. The system, inventory class and platform are written separately.
- To: a typed option `flake.fleet.hosts.<name>` that declares each host's system once, with its endpoints, deploy user, services, ZeroTier address, primary user, memory, the classic-mode trial, whether it is checked, and its state version. Class, address, fully qualified name and deploy target are derived. `flake.lib.hosts` stays as a read-only alias, so existing readers are unaffected.
- Impact: non-breaking. Built configurations are intended to be unchanged, except cinnabar's (below); the declared drvPath differences are listed in `drv-delta.txt`.

**Derived instead of restated**
- From: the Nix system table, the inventory class, the NixOS deploy target, nine `nixpkgs.hostPlatform` lines, seven "ends in -darwin" tests, the collector rows' platform and the NixOS key-host list that stop-reading-other-hosts-configs adds are each written by hand.
- To: all of them are generated from the record. The phones, which run no Nix configuration, are left out of every host set that builds one. The collector's platform assert, which would only compare the record with itself, is removed. Every assert in `checks/machines.nix` is kept: the inventory keeps its own literal entries, so the name asserts still compare it against the record. The flake-shape golden pin and the darwin rule that no inventory deploy target is set are kept.

**Lifecycle and cloud facts kept apart**
- From: "deferred from checks" is a list in one check. "Reserved name with no machine" is a literal name in the tincr peer set. Cloud memory is copied from server types in a comment.
- To: separate typed fields. Whether a host is checked is declared. Whether it is enrolled with clan is read from its machine key. Its cloud provider, type and up/down state are read from the terraform table, which stays the only writer. A table maps cloud machine type to memory. None of these fields reuses the cloud `enabled` flag, which means "the server exists" and would drop two machine checks if read as "checked".

**One role-membership rule**
- From: four readers resolve clan role membership in three different ways, and two of them miss members added by tag.
- To: one resolver over the declared inventory, used by all four. The ZeroTier controller's list of external members is derived from class (darwin or phone) instead of written out.
- Impact: the controller's list changes order, so cinnabar's configuration and machine check change and cinnabar is redeployed once; the operator accepted this reorder on 2026-11-26 rather than keep a hand-ordered list that restates the set. The members are the same six. The fleet-topology evaluation check also changes, because it copies the source file this change edits, and the resolver gains a new evaluation check, which the fleet alert check's list of check sizes gains too.

**One meaning per inventory tag**
- From: the inventory tag `controller` means the ZeroTier controller on cinnabar and the operator's deployment workstation on stibnite, so `clan machines update --tags controller` reaches both a NixOS server and a darwin workstation.
- To: stibnite's tag becomes `deployer-workstation`, as the operator decided on 2026-11-26. `--tags controller` then selects only cinnabar. No clan role reads either tag.
- Impact: the committed fleet map (`fleet.json`) is regenerated, so `fleet-topology-fresh` changes, and so does every check that builds or consumes the docs package, whose source holds the map. An operator who types `--tags controller` to deploy stibnite must now type `--tags deployer-workstation`. No host configuration changes.

**Non-goals**: the host↔user relation record, generating clan user instances, and making host modules read the new `stateVersion` field (later changes build on this record); retyping the collector table beyond its platform field; moving terraform's cloud table into the record; per-machine-directory contributions to the record.

## Dependencies

- **establish-refactor-oracle** must land first. This change is accepted by `just drv-diff <parent> <tip> openspec/changes/type-the-fleet-host-registry/drv-delta.txt`, which that change commits; `just eval-identity` compares two evaluators at one revision and cannot show a cross-revision refactor is neutral.
- **stop-reading-other-hosts-configs** lands before this change, which is rebased onto it and re-runs `just drv-diff` from its tip. That change adds the literal NixOS key-host list in `modules/lib/host-keys.nix`; this change derives it from host class.
- **declare-host-user-relations-once** and **compose-hosts-from-cohesive-aspects** depend on this change: the host↔user record and the host modules' state version become fields of `flake.fleet.hosts`.

## Capabilities

### New Capabilities

- `fleet-host-registry` (stratum: behavioral): each fleet host's facts are recorded once and every fact that follows from another is derived. A host that runs no Nix configuration is never treated as one that does. Lifecycle facts stay independent. A cloud host's memory follows from its machine type. Role membership is decided by one rule. The ZeroTier controller admits exactly the hosts that do not join through clan. A host dropped from every table at once, or whose kind flips, is still caught by an independent record.
- `fleet-host-registry-interface` (stratum: interface): the `flake.fleet.hosts` option and its field types, the read-only `flake.lib.hosts` alias, the derived `flake.lib.machineSystems`, inventory `machineClass` and NixOS `deploy.targetHost`, the generated `flake.clan.machines` with `nixpkgs.hostPlatform`, the derived NixOS names of `flake.lib.hostKeys`, `flake.lib.cloudMachineMemoryGiB`, `flake.lib.inventoryMembers`, the derived ZeroTier `allowedIps`, and the kept and removed asserts. **Trust boundary**: the option types and evaluation-time asserts check only what is written in the repository. They do not show that a machine has the system, memory or server type recorded for it, that a cloud provider's type still has the memory the table gives it, or that a host enrolled in the repository holds its key. The drvPath diff shows the derived values equal the hand-written ones only for the attributes it dumps.

### Modified Capabilities

- `world-assumptions` (stratum: world): A300–A305. These cover clan's ZeroTier controller writing members in list order; the module system's type errors and `lib.assertMsg` failing with a catchable `throw`; clan's inventory resolving role tags including `all`; the cloud providers' memory per machine type; a clan machine key existing exactly for enrolled machines; and an option value defined in a different module of the same configuration producing the same derivation. It also adds designations for fleet host, fleet member, phone, system, class, host registry, enrolled, checked, cloud machine type, role membership and inventory tag.

## Impact

- Code: `modules/lib/hosts.nix` (becomes the option declaration and values), `modules/lib/option.nix` (unchanged type; `flake.lib.hosts` becomes an alias), `modules/clan/inventory/machines.nix`, `modules/clan/machines.nix`, `modules/lib/cloud-machines.nix` (read, not changed), a new `modules/lib/inventory-members.nix` and its test, `modules/lib/host-keys.nix`, `modules/checks/machines.nix`, `modules/checks/zerotier-mss-clamp.nix`, `modules/checks/zerotierone-controller.nix`, `modules/apps/omnigent-worker-login.nix`, `modules/lib/fleet-topology.nix` and its test, `modules/clan/inventory/services/{zerotier,tincr,otel-collector}.nix`, `modules/lib/observability-hosts.nix`, `modules/lib/{commit-signing,omnigent-fleet-obligations,fleet-deployer}.nix`, `modules/system/{deploy-record,harmonia-gc,mesh-hosts}.nix`, the nine host modules that set `nixpkgs.hostPlatform`, and `modules/README.md` with ADR-0019/0020 notes where they describe `hostPlatform` placement.
- Hosts: cinnabar (the controller list's order) is redeployed. Every other host's configuration is meant to stay identical, so nothing else needs a deploy.
- Evaluation: check key sets read only the record, which is flake-level data. The `checks.x86_64-linux` attribute names are compared before and after.

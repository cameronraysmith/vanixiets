---
linear_story_id: CAM-130
linear_story_identifier: CAM-130
linear_story_title: "Declare which people have accounts on which hosts once, and derive everything else from it"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-130/declare-which-people-have-accounts-on-which-hosts-once-and-derive
linear_story_state: Todo
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: Todo
last_synced_at: "2026-11-26T22:58:33Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-26T22:58:33Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-130 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes; state and project confirmed by read-only view; bind comment posted" }
---

## Why

Which people have accounts on which hosts, who is each host's primary user, and which hosts run whose omnigent workers are each written by hand in four to seven places: clan user instances, host bodies, the secret bridge, the home check and the deployer. Adding a user or host means editing all of them, and the checks compare names only. Home-manager also receives two different `flake` values, and on four darwin hosts whichever merges last wins. Declaring each relation once and deriving the rest removes that drift, settles the `flake` value, and is the step that makes a later move to den's host-to-user policies mechanical.

## What Changes

**Host↔user relations**
- From: user membership in `clan/inventory/services/users/{cameron:15-22,crs58:15-16,tara:14-15}.nix`, primary users in `lib/hosts.nix:144-150` and again in darwin host bodies (`machines/darwin/argentum/default.nix:7`), eight `hm-sops-bridge.users` lines and the matching `home-manager.users.<u>.imports` in NixOS host bodies, darwin uids as host literals, and `checks/home.nix:53-66` `checkedUsers` chosen by hand.
- To: one record per (host, user) on the host entity, with a role (primary, admin or account), whether the user's personal key is bridged, extra home imports and overrides, and a darwin uid. The clan machine lists, `custom.laptop.primaryUser`, the secret bridge, the home imports and `checkedUsers` are generated from it; clan inventory remains the deployment authority.
- Impact: non-breaking; every host and home is expected to evaluate to the same derivation.

**Home-manager integration**
- From: the same integration block in six files (the three user services, `darwin/laptop.nix`, stibnite, blackphos).
- To: one `{nixos,darwin}.home-manager-integration` aspect. The home-manager module import stays at machine level, which avoids duplicate catppuccin imports.

**The ambient `flake` argument**
- From: `_module.args.flake = inputs.self` in nine host modules, and `extraSpecialArgs.flake` set to `config.flake // { inherit inputs; }` in some files and `inputs.self // { inherit inputs; }` in others. The worker check relies on that argument for its guard (`checks/omnigent-workers.nix:16-21`).
- To: one value, set once; then the argument is removed. In the same change, worker homes get a home-manager aspect that only sees a restricted set of inputs, and a mutant check proves that reaching `contentPrivate` or a whole-user alias fails.
- Impact: the only step that may change derivations, on the hosts where the losing value differs today. The before/after diff decides which hosts.

**Omnigent worker relation**
- From: owners and hosts written in `clan/inventory/services/omnigent.nix:58-126`, again as `requesterNames` (`lib/fleet-deployer.nix:46-52`), and again as `shared-reference-tree` participants in magnetite, pyrite and stibnite.
- To: `workers.<owner>.hosts` declared once. The inventory host blocks, `requesterNames` and the participants are derived from it.

**Smaller items**
- The omnigraph desktop client flag is read from the attachment record, replacing the host-name list at `home/users/crs58/default.nix:71-74`. `services.jj-pr-sync.enable` defaults to `!deploysWithoutScreenSession`.
- `accountOf` (person→account) is added beside `personOf` (account→person) in one file, read by `lib/commit-signing.nix` and `home/ai/agent-telemetry.nix`. `system/stibnite-access.nix` is renamed to match the keys it exports.

**Constraints (kept as is)**
- No person or account key is renamed. A rename would move `vars/shared/crs58-commit-signing-key` and split the agent-session telemetry history.
- nix-darwin's `system.primaryUser` stays the admin account (`darwin/laptop.nix:75`). It is never set from the primary role.
- `checkedUsers` reads static data only. Computing `checks.<system>` names must not force `flake.users`, a machine configuration or `pkgs` (`checks/home.nix:37-38`).
- `omnigent-*` worker accounts stay owned by `nixos/omnigent-host.nix`, whose `:322` assertion keeps them out of the personal secret bridge. They do not get attachment records.
- `hostMatrix`/`serverMatrix` (`checks/omnigent-workers.nix:594-600`) and the host list at `checks/omnigent-acp-spawn-env.nix:19-22` stay literal oracles. `operators` stays a separate relation.
- Devin's `outpostByHost` and worker statements stay separate (`home/users/crs58/default.nix`). Standalone homes (`osConfig == null`) keep their behaviour.

**Non-goals**: retyping the host registry itself; replacing clan inventory; renaming the stibnite `controller` inventory tag; the darwin workstation template split.

## Dependencies

Landing order: establish-refactor-oracle → stop-reading-other-hosts-configs → type-the-fleet-host-registry → register-fleet-obligations → declare-host-user-relations-once. This change rebases onto register-fleet-obligations and re-runs `just drv-diff` after rebasing.

- **establish-refactor-oracle** must land first. It provides `just drv-diff`, which accepts each step. `just eval-identity` does not answer this, because it compares two evaluators at one revision.
- **stop-reading-other-hosts-configs** must land first. `modules/system/ssh-known-hosts.nix` takes the ambient `flake` argument and reads `flake.nixosConfigurations.<h>.config.clan.core.vars…` for every NixOS host's key. Removing that argument breaks it until that change moves those keys to `hostKeys`.
- **type-the-fleet-host-registry** must land first. The attachment record is a field of its typed host entity `flake.fleet.hosts.<host>`, and `flake.lib.hosts` remains its read-only alias. This change cannot choose the record's option path or type until that entity exists.

## Acceptance

Each step passes `just drv-diff <parent> <tip> openspec/changes/declare-host-user-relations-once/drv-delta.txt`. The oracle dumps all NixOS and darwin toplevels, home activation packages, `checks.{x86_64-linux,aarch64-darwin}` and `vmTests.{x86_64-linux,aarch64-linux}`. The allow-list names exact attribute paths only, with no globs. It marks each entry `changed` (must change), `may-change`, `added` or `removed`. A step that changes a toplevel, which only the single `flake` value may do, lists that toplevel and every `checks` and `vmTests` attribute that embeds it. The new mutant check and any renamed check appear as `added`/`removed`. Every other dumped path must stay equal.

World-assumption designations added by this change use ids A340–A349.

## Open questions

Each question is answered in design, after the dependencies land:

1. Which `flake` value each darwin host gets today, and whether one value can be kept everywhere without changing a derivation.
2. What the worker homes' restricted input set contains, read off the current worker homes.
3. The exact field names and types of the attachment record, including whether `overrides` is a home-manager module and how the darwin uid is validated.
4. Whether `checkedUsers` can be generated while keeping the static key set. If it can't, it stays a literal with a judge that compares it to the record.
5. Whether the desktop-client flag is a field of the attachment or a fact about the host.
6. Where `workers.<owner>.hosts` lives: on the host entity or in a separate relation table that the inventory reads.

## Capabilities

### New Capabilities

- `host-user-attachment` (stratum: behavioral): each account a person holds on a host is declared once, with its role, and the host provides exactly those accounts, their home environments and their secret access. Each omnigent worker owner's hosts are declared once. A worker home cannot read private content or another person's whole configuration.
- `host-user-attachment-interface` (stratum: interface): the attachment field on the host entity and the outputs generated from it (clan machine lists, `custom.laptop.primaryUser`, `hm-sops-bridge.users`, home imports, `checkedUsers`), the home-manager integration aspect, the single `flake` value, the worker aspect and its mutant check, the `workers.<owner>.hosts` declaration, and `accountOf`/`personOf`. Trust boundary: the drvPath diff shows the derived outputs equal the hand-written ones for every attribute it dumps. It says nothing about state already on a host, such as existing accounts or uids on disk. The mutant check shows only that the two named reaches fail. It does not show that a worker home has no other route to private content.

### Modified Capabilities

- `world-assumptions` (stratum: world): designations for a host's primary user and admin account, and for the person↔account correspondence that `personOf` and `accountOf` name. The existing `person` and `account` designations are reused.

## Impact

- Code: `clan/inventory/services/users/{cameron,crs58,tara}.nix`, `clan/inventory/services/omnigent.nix`, `darwin/laptop.nix`, every host under `machines/`, `checks/home.nix`, `checks/omnigent-workers.nix`, `lib/hosts.nix` (or its typed successor), `lib/fleet-deployer.nix`, `lib/commit-signing.nix`, `home/ai/agent-telemetry.nix`, `home/mk-home.nix`, `home/users/crs58/default.nix`, `home/development/jj-pr-tags.nix`, `system/stibnite-access.nix`, and a new home-manager integration aspect (all under `modules/`).
- Hosts: all ten. Derivations are expected unchanged except where the single `flake` value differs from today's.
- Checks: `structure-home-configurations`, `home`, `omnigent-workers` (plus its new mutant), `fleet-deployer-obligations`, `sops-correspondence`.

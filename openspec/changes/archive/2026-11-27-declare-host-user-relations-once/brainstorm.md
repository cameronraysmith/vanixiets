<!--
Raw capture of the decision chain for this change.
No interactive brainstorming session ran. The change was opened on 2026-11-26 from a read-only review of how the repository's host and user relations are declared, done by reading the clan user and omnigent inventory services, `lib/hosts.nix`, the host bodies under `machines/`, the home-manager integration blocks, `checks/home.nix`, `checks/omnigent-workers.nix` and `lib/fleet-deployer.nix`. The operator had already settled four forks, recorded below as settled.
The remaining forks depend on contracts that other changes introduce first (type-the-fleet-host-registry, stop-reading-other-hosts-configs and establish-refactor-oracle), so they are left open here and repeated as open questions in proposal.md rather than decided.
Every file:line below was re-read against the tree on 2026-11-26. Paths are relative to `modules/` unless they start with `openspec/` or `docs/`.
-->

# Brainstorm: declare each host↔user relation once

## Background

Three relations between hosts and users, and one between omnigent worker owners and hosts, are written by hand in several places that must agree.
Nothing derives one from another; the checks that compare them compare names only.

### Which users have a home on which host

- The clan user instances list machines one by one: `clan/inventory/services/users/cameron.nix:15-22` (cinnabar, electrum, argentum, rosegold, galena, scheelite, magnetite, pyrite), `crs58.nix:15-16` (stibnite, blackphos), `tara.nix:14-15` (scheelite, galena).
- Each NixOS host repeats its users twice more: once as `hm-sops-bridge.users.<u> = { }` and once as `home-manager.users.<u>.imports = flakeUsers.<u>.modules` (for example `machines/nixos/galena/default.nix:95-108`, `pyrite/default.nix:761`, `magnetite/default.nix:1131`; the bridge line appears eight times across cinnabar, electrum, galena ×2, magnetite, pyrite and scheelite ×2).
- tara's home on galena turns `programs.agents-md.enable` off at the host (`galena/default.nix:106-107`); the same kind of per-pair override lives only in host bodies.

### Who is a host's primary user

- `lib/hosts.nix:144-150` `primaryUsers` names pyrite→cameron, stibnite→crs58, blackphos→raquel, argentum→christophersmith, rosegold→janettesmith; `flake.lib.fleetDeployer` derives who may deploy each machine from it.
- The darwin hosts state it again: `machines/darwin/argentum/default.nix:7` `custom.laptop.primaryUser = "christophersmith"`, read by `darwin/laptop.nix:25,46,100-134`.
- `darwin/laptop.nix:75` sets nix-darwin's `system.primaryUser = "cameron"`, the admin account, which is a different fact from the registry's primary user and must stay separate.
- Darwin uids are host-body literals: `laptop.nix:101,109` (501, 502), `blackphos:135,143` (502, 506), `stibnite:134,142` (501, 551).

### Which homes the home check builds

- `checks/home.nix:53-66` `checkedUsers` is a literal per system, chosen by hand from the users no host already embeds (comment at `:20-31`, last revisited 2026-10-06). It is deliberately static: computing `checks.<system>` names must not force `flake.users`, a machine configuration or `pkgs` (`:37-38`).

### The home-manager integration block

The block that sets `useGlobalPkgs`, `useUserPackages`, `backupFileExtension` and `extraSpecialArgs.flake` is written six times: `clan/inventory/services/users/cameron.nix:70-82`, `crs58.nix:41-53`, `tara.nix:40-48`, `darwin/laptop.nix:121-129`, `machines/darwin/stibnite/default.nix:243-252`, `blackphos/default.nix:157-166`.
The home-manager module itself is imported at machine level (for example `galena/default.nix:23`, `stibnite/default.nix:29`), on purpose: importing it from the user services duplicated catppuccin's imports when clan deploys (`cameron.nix:68-69`, `crs58.nix:39-40`).
The worker check builds its own fixtures that import home-manager themselves (`checks/omnigent-workers.nix:216,349`).

### The ambient `flake` argument holds two different values

- `_module.args.flake = inputs.self` in nine host modules (`darwin/laptop.nix:52`, which covers argentum and rosegold, `blackphos:26`, `stibnite:26`, `cinnabar:39`, `electrum:35`, `galena:34`, `magnetite:141`, `pyrite:135`, `scheelite:38`).
- Home-manager's `extraSpecialArgs.flake` is `config.flake // { inherit inputs; }` in `home/mk-home.nix:17-19` and in the `flakeForHomeManager` binding of `darwin/laptop.nix:11`, `stibnite:13` and `blackphos:13`, but `inputs.self // { inherit inputs; }` in the user services (`cameron.nix:78-81`, `crs58.nix:49-52`, `tara.nix:45-48`).
- Home-manager types `extraSpecialArgs` as `attrs`, so on a darwin host where both the user service and the host set it (stibnite, blackphos, argentum, rosegold) whichever definition merges last wins. Which value each host gets today is not visible from the source.
- `checks/omnigent-workers.nix:16-21` relies on that argument: it hands the worker homes a `flake` whose `inputs.contentPrivate` and `users` throw, so a worker home that reached for private content or a whole-user alias fails the check. Removing the argument removes that guard unless something replaces it.

### The omnigent worker relation

- `clan/inventory/services/omnigent.nix:58-126` lists each host's workers with their owners: magnetite and pyrite each carry cameron and janettesmith, stibnite carries cameron.
- `lib/fleet-deployer.nix:46-52` restates the owners as `requesterNames`.
- `services.shared-reference-tree.participants` restates the worker accounts per host (`magnetite/default.nix:131-138`, `pyrite/default.nix:87-93`, `stibnite/default.nix:46-50`).
- Two lists in checks are kept as literal oracles and must not be derived: `checks/omnigent-workers.nix:594-600` `hostMatrix`/`serverMatrix`, and the NixOS-only host list at `checks/omnigent-acp-spawn-env.nix:19-22`. `operators` is a separate relation.

### Other host literals in user modules and the person/account vocabulary

- `home/users/crs58/default.nix:71-74` enables the omnigraph desktop client by matching `osConfig.networking.hostName` against `[ "stibnite" "pyrite" ]`.
- `services.jj-pr-sync.enable = false` is written per account wherever `deploysWithoutScreenSession = true` (`darwin/laptop.nix:135-144`, `blackphos/default.nix:174-175`).
- The account→person direction is `personOf` in `home/ai/agent-telemetry.nix:30-43` (crs58→cameron); the person→account direction is open-coded in `lib/commit-signing.nix:5` through `flake.userAliases`. Nothing names the second direction.
- `system/stibnite-access.nix` exports `stibnite-session` and `stibnite-session-host` (`:37,75`); the file name matches neither key.

## Decision chain

### Q1. Rename the canonical person or account keys? (settled)

No. Renaming `crs58` or `cameron` would move `vars/shared/crs58-commit-signing-key` and split the agent-session telemetry history (`openspec/changes/agent-session-telemetry/design.md:50-51`).
Add `accountOf` beside `personOf`, in one file, so both directions have a name and one definition; `lib/commit-signing.nix:5` and `home/ai/agent-telemetry.nix:30` read it.

### Q2. What replaces the poisoned `flake` guard? (settled)

A worker home-manager aspect closed over a restricted input set, so a worker home cannot name `contentPrivate` or a whole-user alias because nothing in its scope holds them, plus a mutant check that proves an attempt to reach either fails evaluation.
It lands in the same change that removes the ambient `flake` argument, so there is no revision where workers lose the guard.

### Q3. Where does the attachment record live? (settled by the host-registry change)

The per-(host, user) record is a field of the typed host entity `flake.fleet.hosts.<host>` that type-the-fleet-host-registry introduces, with `flake.lib.hosts` kept as a read-only alias.
This change cannot fix its option path or type until that entity exists; it adds the field and its consumers.

### Q4. How is a refactor proven neutral? (settled by the oracle change)

By the before/after drvPath diff that establish-refactor-oracle commits: every NixOS and darwin toplevel, every home activation package, and every `checks.{x86_64-linux,aarch64-darwin}` attribute, dumped at both revisions and diffed.
`just eval-identity` does not answer this; it compares the stock and iets evaluators at one revision.
Every step here is expected drvPath-neutral except the one that picks a single `flake` value, which may change the hosts where the losing value differed today.

### Q5. One record, or one per relation?

Considered:
1. One record per (host, user) carrying the role, the bridge flag, extra imports and overrides, and the darwin uid; every consumer derives from it.
2. Separate tables per relation (membership, primary, bridge), each derived from nothing.
3. Generate host bodies from `flake.users` alone, with per-user host lists.

Option 1 chosen. Option 2 keeps the restatement this change removes. Option 3 puts host facts (uid, admin) in user modules, the inverse of the problem the studio literal already shows.
Record fields, as first proposed: `role ∈ { primary, admin, account }`, `sopsBridge`, `extraImports`, `overrides`, and `uid` on darwin.
Generated from it: the clan user instances' `roles.default.machines`, `custom.laptop.primaryUser`, `hm-sops-bridge.users`, `home-manager.users.<u>.imports`, and `checkedUsers`.
Clan inventory stays the authority for deployment; its machine lists are generated, not removed.

### Q6. Order of the steps

1. One home-manager integration aspect (`{nixos,darwin}.home-manager-integration`), replacing the six blocks; the machine-level module import stays.
2. The attachment record and its generated consumers; `checkedUsers` generated from static data only.
3. One `flake` value, set once; then the worker aspect and mutant check; then removal of the ambient argument.
4. The worker relation declared once, deriving the inventory host blocks, `requesterNames` and `participants`; and the studio flag read from the attachment record.
5. `accountOf`, and the `stibnite-access.nix` file renamed to match its keys, at any point.

Steps 1–3 share user-service and host files and run in order. Each step is checked by the drvPath diff before the next.

## Trade-offs and open forks

- **Which `flake` value wins.** `config.flake // { inherit inputs; }` and `inputs.self // { inherit inputs; }` differ (one is the module-system value, the other the flake's outputs). The diff run on today's tree decides which one each darwin host already gets; the change keeps that one where it can and declares the drvPath change for any host where it cannot. Open until measured.
- **Restricted input set.** Which inputs a worker home needs (nixpkgs, home-manager, the worker's own modules) is read off the current worker homes, not guessed; the list is fixed in design.
- **`checkedUsers` stays static.** Generating it is only acceptable if computing `checks.<system>` names still forces no `flake.users` aggregate, machine configuration or `pkgs`; otherwise it stays a literal with a judge that compares it to the record.
- **The worker homes stay with their service.** `omnigent-*` accounts are created by `nixos/omnigent-host.nix`, which asserts at `:322` that a worker never enrolls in the personal age bridge; they are not attachment records.
- **Studio flag.** A field on the attachment record (the account is used at a display) versus a host-level fact; open.
- **`jj-pr-sync` default.** Defaulting it to `!deploysWithoutScreenSession` in home-manager removes three per-account lines; standalone homes (`osConfig == null`) keep their current value.
- **Admin versus primary.** nix-darwin's `system.primaryUser` stays the admin account, set from the record's `admin` role, never from `primary`.

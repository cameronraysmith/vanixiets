## Context

### Current state

Paths are relative to `modules/` unless they start with `openspec/`, `docs/`, `packages/` or `logs/`. Every file:line below was re-read on main at `9055ae0f1` (type-the-fleet-host-registry merged) on 2026-11-27; several of brainstorm.md's line numbers moved when that change deleted the `nixpkgs.hostPlatform` lines, and the current ones are given here.

**Which accounts a host has, and their homes.** Membership is written three times and in three shapes:
- the clan user instances list machines by hand: `clan/inventory/services/users/cameron.nix:15-22` (cinnabar, electrum, argentum, rosegold, galena, scheelite, magnetite, pyrite), `crs58.nix:15-16` (stibnite, blackphos), `tara.nix:14-15` (scheelite, galena);
- each NixOS host body writes the secret bridge and the home again: `hm-sops-bridge.users.<u> = { }` at `machines/nixos/cinnabar/default.nix:97`, `electrum:96`, `galena:92-93`, `scheelite:103-104`, `magnetite:1129`, `pyrite:758`, and `home-manager.users.<u>.imports = flakeUsers.<u>.modules` beside each (`cinnabar:102-104`, `electrum:101-103`, `galena:98-105`, `scheelite:109-116`, `magnetite:1134-1136`, `pyrite:764-775`);
- each darwin body writes its homes inside its own integration block (`darwin/laptop.nix:131-143`, `machines/darwin/stibnite/default.nix:258-274`, `machines/darwin/blackphos/default.nix:166-174`).

Per-pair settings live only in host bodies: tara's `programs.agents-md.enable = false` (`galena:104`, `scheelite:115`), pyrite's six extra home modules and its niri package (`pyrite:765-774`), stibnite's extra module, packages and k3s profiles (`stibnite:259-273`), and `deploysWithoutScreenSession = true` with `services.jj-pr-sync.enable = false` for every darwin account deployed without a screen session (`laptop.nix:133-134,141-142`, `blackphos:172-173`).

**Primary user and admin account.** The primary user is a declared field of the typed host record (`lib/hosts.nix:82-85`; values pyrite cameron, stibnite crs58, blackphos raquel, argentum christophersmith, rosegold janettesmith). The two laptops state it again as `custom.laptop.primaryUser` (`machines/darwin/argentum/default.nix:7`, `rosegold:7`), an option `darwin/laptop.nix:46-49` declares and `:25,98-104,114-116,131` read. nix-darwin's `system.primaryUser`, the admin account, is a third literal per darwin host: `laptop.nix:73` (`"cameron"`), `stibnite:88` and `blackphos:85` (`"crs58"`). Darwin uids are literals: `laptop.nix:99,107` (501, 502), `stibnite:132` (501), `blackphos:133,141` (502, 506). On stibnite and pyrite one person's account is both the primary user and the admin; on blackphos and the laptops they differ.

**The home check.** `checks/home.nix:53-66` `checkedUsers` is a literal per system, chosen by hand from the users no host of that system embeds (rule at `:9-31`, last revisited 2026-10-06). It is static on purpose: `checks.<system>` names must not force `flake.users` aggregates, a machine configuration or `pkgs` (`:37-38`).

**The integration block.** `useGlobalPkgs`, `useUserPackages`, `backupFileExtension` and `extraSpecialArgs.flake` are set six times: `clan/inventory/services/users/cameron.nix:70-83`, `crs58.nix:41-54`, `tara.nix:40-49`, `darwin/laptop.nix:119-128`, `stibnite:247-256`, `blackphos:155-164`. The home-manager module is imported at machine level (for example `galena:23`, `stibnite:29`), because importing it from the user services duplicated catppuccin's imports when clan deploys (`cameron.nix:67-69`, `crs58.nix:38-40`).

**The ambient `flake` argument.** Three values reach homes today:
- `config.flake // { inherit inputs; }` from `home/mk-home.nix:17-20` (standalone homes) and the `flakeForHomeManager` bindings of `laptop.nix:11-13`, `stibnite:13-15`, `blackphos:13-15`;
- `inputs.self // { inherit inputs; }` from the three user services (`cameron.nix:78-82`, `crs58.nix:49-53`, `tara.nix:45-49`), the only writer on the six NixOS hosts, and from the two runtime tests `vm-tests/omnigent-worker-isolation.nix:161-163` and `vm-tests/shared-reference-tree.nix:69-71`;
- `inputs.self` for the darwin worker homes (`darwin/omnigent-host.nix:107-110`).

Home-manager types `extraSpecialArgs` as `attrs`, which merges shallowly with the last definition winning (A340), so on argentum, rosegold, stibnite and blackphos, where a user service and the host both set it, the value depends on definition order. Forty home modules destructure `flake`; six of them read it inside `imports` (`home/base/sops.nix:25`, `home/core/catppuccin.nix:33`, `home/shell/tmux.nix:38`, `home/development/neovim/default.nix:19`, `home/terminal/direnv.nix:19`, `home/terminal/nix-index.nix:6`). Separately, nine host modules covering all ten hosts (`laptop.nix` serves argentum and rosegold) set `_module.args.flake = inputs.self` (`laptop.nix:52`, `blackphos:26`, `stibnite:26`, `cinnabar:39`, `electrum:35`, `galena:34`, `magnetite:140-141`, `pyrite:135`, `scheelite:38`); since stop-reading-other-hosts-configs moved `system/ssh-known-hosts.nix` to `flake.lib.hostKeys`, no first-party NixOS or darwin module destructures it (search of 2026-11-27), and home-manager does not pass a host's `_module.args` to its homes (A346).

**The worker guard.** `checks/omnigent-workers.nix:16-21` builds a `flake` whose `inputs.contentPrivate` and `users` throw, and passes it to the fixture worker homes (`:32-35`, `:225-229`). It guards only the fixtures: the real worker homes on magnetite and pyrite are integrated homes and receive the host's full `inputs.self // { inherit inputs; }`, and stibnite's receive `inputs.self`. The worker home (`home/ai/omnigent/worker.nix:7-127`) imports twenty-five shared modules; read off them, the `flake` reads it can force are `flake.inputs.llm-agents` (`omp:88,130`, `pi:31`, `openspec:29`), `flake.inputs.direnv-instant` (`direnv:19,59`) and `flake.packages` (`worker.nix:151`). `git.nix:61-62` and `vcs-author.nix:11` read `flake.users` only under conditions a worker home does not meet (a personal home, an unset `vcs.author`), which is why the poison passes today.

**The worker relation.** `clan/inventory/services/omnigent.nix:57-125` writes each host's workers and owners (magnetite and pyrite carry cameron and janettesmith, stibnite cameron). `lib/fleet-deployer.nix:46-51` restates the owners as `requesterNames`. `services.shared-reference-tree.participants` restates the worker accounts per host (`magnetite:131-138`, `pyrite:87-94`, `stibnite:46-55`). Three literals stay literal oracles: `checks/omnigent-workers.nix:594-600` (`hostMatrix`, `serverMatrix`), `checks/omnigent-acp-spawn-env.nix:19-22`, and `lib/omnigent-fleet-obligations.nix:7-17` `expectedOwners`, which the machine-check obligations compare each host's worker owners against.

**Smaller items.** `home/users/crs58/default.nix:70-76` enables the omnigraph desktop client by matching `osConfig.networking.hostName` against `[ "stibnite" "pyrite" ]`. The account→person direction is `personOf` (`home/ai/agent-telemetry.nix:30-43`, crs58→cameron); the person→account direction is `flake.lib.signingPerson` (`lib/commit-signing.nix:5`, cameron→crs58), read in seven places (`lib/commit-signing.nix:201,203,212,261`, `system/commit-signing-key.nix:19,23`, `home/development/vcs-signing.nix:27`, `home/users/lib.nix:103`, `home/ai/omnigent/credentials.nix:143`, `lib/omnigent-fleet-obligations.nix:286`). `system/stibnite-access.nix` exports `flake.modules.nixos.stibnite-session` (`:37`) and `flake.modules.darwin.stibnite-session-host` (`:75`).

### Requirements and the world they rest on

| Req | Statement (behavioral, `host-user-attachment`) | Rests on | Breaks if it fails | Discharged by |
|---|---|---|---|---|
| R1 | Each account a person holds on a host is declared once; every other fact about it follows | A343 | a new account is added in one place and missing from another, and the host builds without it | D1, D3, D4 |
| R2 | A host provides exactly its declared accounts, each with its home configuration, and secret access only where declared | A343, A344 | a person loses a home, or a personal key reaches a host it was not declared for | D3, D4 |
| R3 | A nix-darwin host's admin account is declared separately and never inferred from its primary user | A345, A346 | blackphos or a laptop is administered as its primary user | D2, D4 |
| R4 | Which hosts run a person's Omnigent workers is declared once | — | a worker is added to a host and its deploy requests or reference tree access are missing | D8 |
| R5 | A worker's home configuration cannot read any person's private settings or whole home configuration | A341, A347 | a worker home is built with another person's private settings | D6, D7 |
| R6 | The person-account correspondence is stated once and read in both directions | — | telemetry and commit signing disagree about who cameron is | D10 |
| R7 | Every home configuration is checked on each checked system, inside a host or standalone, without a hand-kept list | — | a person's home stops being checked when a host attachment changes | D9 |
| R8 | Every home configuration a host or the standalone builder composes receives the same description of the fleet | A340, A342, A348 | a home's derivation depends on which module was evaluated last | D5 |

### Stakeholders

The operator, who adds people and hosts. The people whose accounts these are. compose-hosts-from-cohesive-aspects, which lands after this change and builds its `darwin-workstation` aspect from the attachment's admin, primary user and uid. A later den migration, which maps the attachment onto den's host-to-user relations.

## Goals / Non-Goals

**Goals:**
- One attachment record per (host, account), a field of the typed host entity `flake.fleet.hosts.<host>`, from which the clan user instances' machine lists, the primary user, nix-darwin's admin account, the darwin uids, the secret bridge, the homes and `checkedUsers` are generated.
- One home-manager integration aspect per class replacing the six blocks.
- No ambient `flake` argument: no host-wide `extraSpecialArgs.flake` and no host `_module.args.flake`. Every home receives the one `flake` value from what composes it, and worker homes receive a restricted value from their own aspect, with a check that fails if a worker home reaches private content or a whole user.
- The Omnigent worker relation declared once.
- `accountOf` beside `personOf`; the studio flag and the `jj-pr-sync` default read from the attachment and the screen-session flag; `stibnite-access.nix` renamed.
- Every NixOS, darwin and home configuration keeps its drvPath; `just drv-diff` proves it, with only the checks and runtime tests `drv-delta.txt` names differing (D12).

**Non-Goals:**
- Retyping the host registry's existing fields, or deriving `deployUser` from the admin attachment.
- Replacing clan inventory; clan remains the deployment authority, and its user instances keep their settings (`groups`, `share`, `prompt`) and their shell and key `extraModules`.
- Generating the darwin `users.users.<u>` blocks or `users.knownUsers`; compose-hosts-from-cohesive-aspects builds those from this record.
- The `omnigent-*` worker accounts: they stay owned by `nixos/omnigent-host.nix` and the host bodies, keep their pinned uids, and get no attachment (`nixos/omnigent-host.nix:322` keeps them out of the bridge).
- Deriving any literal check oracle (`hostMatrix`, `serverMatrix`, `expectedOwners`, `omnigent-acp-spawn-env`'s host list, `sops-correspondence`'s anchors, `structure-home-configurations`' pin) or `operators`.
- Devin's `outpostByHost` and worker statements in `home/users/crs58/default.nix`; renaming any person or account key or the stibnite `controller` tag.

## Decisions

### D1: the attachment is `flake.fleet.hosts.<host>.users.<account>`, declared in a new file

- **Choice**: a new `modules/lib/host-users.nix` declares `options.flake.fleet.hosts` again, as `attrsOf (submodule { options.users = …; })`, which the module system merges with `lib/hosts.nix`'s submodule, and holds the values for every host in one table. Each attachment, keyed by account name (a `flake.users` key, aliases included), carries:
  - `primary : bool`, default false: this account is the person the host belongs to;
  - `admin : bool`, default false: this account is nix-darwin's admin account;
  - `sopsBridge : bool`, default `class == "nixos"`: the person's personal key is bridged to the account;
  - `uid : nullOr ints.positive`, default null: the account's uid, required on darwin and forbidden on NixOS (D2);
  - `extraImports : listOf raw`, default `[ ]`: home modules beyond the person's own. `raw`, not `deferredModule`: a `deferredModule` list wraps each module in a fresh one and re-keys it, so a module the person's aggregates also import applied twice and reordered pyrite's home (D4, task 4.4);
  - `overrides : deferredModule`, default `{ }`: a home-manager module for this pair, which may take `osConfig` and `pkgs`.

  The values are the fifteen attachments of today: cameron on the six NixOS hosts and on argentum and rosegold; tara on galena and scheelite; crs58 on stibnite and blackphos; christophersmith on argentum, janettesmith on rosegold, raquel on blackphos.
- **Rationale**: the host entity is where den will look for a host's users, and the submodule merge lets the record grow without editing `hosts.nix`'s table (type-the-fleet-host-registry D1). `role ∈ { primary, admin, account }`, as brainstorm Q5 first proposed, cannot state stibnite's crs58 or pyrite's cameron, who are both; two independent flags can, and "account" is the case where both are false. `overrides` is a module rather than an attribute set because pyrite's niri package is read from the host (`osConfig.programs.niri.package`) and stibnite's packages from `pkgs`. Boundary: source-only.
- **Alternatives considered**: (a) separate tables per relation (brainstorm Q5 option 2): the restatement this change removes. (b) per-user host lists in `flake.users` (option 3): it puts host facts (uid, admin) in user modules. (c) a single `role` enum: see above.

### D2: field constraints throw on read; `primaryUser` becomes read-only

- **Choice**: in `lib/hosts.nix`, `primaryUser` becomes a read-only field set to the one attachment with `primary = true`, or null; its type stays `nullOr (enum (attrNames flake.users))`, and the five values leave the table. Each constraint is an `apply`-time `lib.assertMsg` naming `flake.fleet.hosts.<host>.users.<account>.<field>`, as the registry's other class constraints are:
  - at most one attachment per host has `primary`;
  - a darwin host has exactly one `admin`; a NixOS host has none, because NixOS administration comes from the clan instance's `groups`;
  - `uid` is required on darwin and forbidden on NixOS;
  - `sopsBridge` is false on darwin, where `hm-sops-bridge` does not exist;
  - the account is a `flake.users` key.
- **Rationale**: the same `throw`-on-read pattern as `stateVersion` and `nixClassic` (A301), so a read under `tryEval` still sees a catchable failure. `primaryUser` keeps every reader working (`lib/fleet-deployer.nix:96,403`, `home/development/nix-classic.nix:25`, the `nixClassic` assert). Boundary: source-only.
- **Alternatives considered**: keep `primaryUser` declared and assert it equals the primary attachment: two copies with a guard.

### D3: the clan user instances' machine lists are generated

- **Choice**: `flake.lib.hostsOfAccount account` (in `host-users.nix`) returns the sorted names of the hosts with an attachment for `account`. Each of `clan/inventory/services/users/{cameron,crs58,tara}.nix` sets `roles.default.machines = lib.genAttrs (hostsOfAccount "<u>") (_: { })` and deletes its literal lines. Attachments for accounts with no clan instance (christophersmith, janettesmith, raquel, all on darwin) generate nothing here; their accounts are created by the darwin host bodies.
- **Rationale**: clan stays the authority that creates the accounts on NixOS (A343); only the list it reads is generated. Boundary: vendored-versus-first-party: clan-core's `roles.default.machines` is set as documented, nothing in clan-core is patched.
- **Alternatives considered**: one generic user-instance generator over every attachment. It would create clan instances for the three darwin-only people, a behaviour change for clan's NixOS-only settings, and it belongs with compose-hosts' user blocks.

### D4: one `home-manager-integration` aspect per class generates the homes, the bridge, the admin and the uids

- **Choice**: a new `modules/system/home-manager-integration.nix` defines `flake.modules.{nixos,darwin}.home-manager-integration`. With `host = hosts.${config.networking.hostName}` it sets:
  - `home-manager.{useGlobalPkgs,useUserPackages}` to true and `backupFileExtension = "before-home-manager"`;
  - `home-manager.users.<a>` for every attachment, as one module: `{ imports = flake.users.<a>.modules ++ a.extraImports ++ [ a.overrides ]; _module.args.flake = homeFlake; }`. `extraImports` is `listOf raw`, not a `deferredModule` list, which wrapped each module afresh and lost its key, so a module the person's aggregates also import applied twice and reordered pyrite's `home.packages`. A module's own definitions merge after its imports' (A344), so a host body that defined a home inline came last in each of that home's lists; the aspect is one of the host's imports, so where order reaches a derivation the override says so: stibnite's crs58 adds its three packages with `lib.mkAfter`, which keeps `home-manager-path` identical;
  - on NixOS, `hm-sops-bridge.users = lib.genAttrs <bridged accounts> (_: { })`;
  - on darwin, `system.primaryUser` = the `admin` attachment and `users.users.<a>.uid` = each attachment's `uid`;
  - an assertion that `home-manager.extraSpecialArgs` has no `flake` (D6). The planned per-attachment assertion that `config.users.users ? <a>` was removed: home-manager's NixOS module defines `users.users.<name>` for every home, and the darwin aspect itself sets each attachment's uid, so it could not fail. Its mutant (christophersmith attached to cinnabar, `logs/dhuro-4-mutants-20261127T090540Z.log`) fails instead on NixOS's own user assertions (`isSystemUser`/`isNormalUser`, `group is unset`) and the commit-signing vars assertion; on darwin the attachment declares the account with its recorded uid, so no unmatched case exists.

  Every host imports it beside the home-manager module, which stays at machine level. The six integration blocks, the hand-written `home-manager.users.*`, `hm-sops-bridge.users.*`, `system.primaryUser` and uid lines go. `custom.laptop.primaryUser` and its two host lines go: `laptop.nix` reads `hosts.${hostName}.primaryUser`. Per-pair settings move into `overrides`: tara's `programs.agents-md.enable = false`, pyrite's niri package (`osConfig.programs.niri.package`, the same value), stibnite's packages and k3s profile, and `deploysWithoutScreenSession = true` on the laptop and blackphos accounts.
- **Rationale**: the aspect is the one writer of each generated value, and the host name is read the way `laptop.nix:67` already reads `targetHost`. The home-manager module import stays where it is, because moving it reintroduces the duplicate catppuccin imports (`cameron.nix:67-69`). nix-darwin's `system.primaryUser` stays the admin account, set from `admin`, never from `primary` (A345). Deleting a repository option leaves the darwin manuals unchanged, because no module documents first-party options into them (the same finding compose-hosts-from-cohesive-aspects records); the drvPath diff confirms it. Boundary: vendored-versus-first-party: home-manager's and nix-darwin's options are used as documented.
- **Alternatives considered**: (a) generate the darwin `users.users.<a>` blocks and `knownUsers` too. `knownUsers` is a list whose order reaches the activation script, and stibnite's also holds `omnigent-cameron`; compose-hosts owns that template. (b) `home-manager.sharedModules` for the `flake` value. It reaches worker homes too, so the worker's restricted value would have to win by priority, and a forgotten priority would hand a worker the full value.

### D5: one `flake` value, and no ambient argument

- **Choice**: `flake.lib.homeFlake = config.flake // { inherit inputs; }`, defined once in the integration aspect's file. It reaches homes only by `_module.args.flake`, set per home by what composes it: the integration aspect for host homes (D4), `flake.lib.mkHome` for standalone homes (replacing `extraSpecialArgs.flake`), and the worker aspect for worker homes (D6). The runtime-test homes of `vm-tests/shared-reference-tree.nix` receive no `flake` at all: none of their modules reads it. `flake` is removed from every `extraSpecialArgs` (`mk-home.nix`, the three user services, `laptop.nix`, stibnite, blackphos, `darwin/omnigent-host.nix:107-110`, `checks/omnigent-workers.nix:32-35,225-229`, the two runtime tests) and the nine `_module.args.flake = inputs.self` lines, in nine host modules covering ten hosts, go. The six home modules that read `flake` inside `imports` read their flake-parts scope instead (`inputs.sops-nix`, `config.flake.lib.catppuccinHomeModule`, `inputs.lazyvim-nix`, `inputs.direnv-instant`, `inputs.nix-index-database`); `direnv.nix:59` moves with its import so the file no longer takes `flake`. The other thirty-four modules keep reading the argument.
- **Which value each darwin host gets today** (proposal question 1) is measured, not assumed: task 1.3 evaluates `config.home-manager.extraSpecialArgs.flake ? outPath` on each darwin host. `config.flake` was chosen because `mk-home.nix` and three of the four darwin bodies already use it, and because a flake's `self` outputs are the flake-parts `config.flake` values (A348): with `inputs` added to both, the two values differ only in the attributes Nix adds to `self` (`outPath`, `sourceInfo`, `_type`, `outputs`), and no home reads one of them (search of 2026-11-27: no `flake.outPath`, `"${flake}"`, `flake + …` or `flake.sourceInfo`). So no derivation is expected to change on any host; if the drvPath diff shows one, the cause is traced and declared (D12).
- **Measured 2026-11-27 (task 1.3, `logs/dhuro-1-flake-value-20261127T081053Z.log`)**: at the parent `dfcee2e1c`, argentum's and rosegold's homes receive `inputs.self // { inherit inputs; }` (`extraSpecialArgs.flake ? outPath` is true: the cameron user service's value wins the shallow merge), and stibnite's and blackphos's receive `config.flake // { inherit inputs; }` (`? outPath` false). In a throwaway tree, giving argentum and rosegold `config.flake // { inherit inputs; }`, and switching the three user services to it on the NixOS hosts, left the toplevel drvPaths of argentum (`mahsrkd5…`), rosegold (`x5k2dgkp…`), cinnabar (`m8gsv920…`), pyrite (`j67w0zs0…`) and galena (`080zi1nb…`) identical. A first probe that forced `home-manager.extraSpecialArgs` with `lib.mkForce` changed cinnabar's and pyrite's toplevels through `glibc-locales`: home-manager's NixOS module passes `nixosConfig` through the same `extraSpecialArgs` (home-manager `nixos/default.nix:72`), which `modules/config/i18n.nix:68` reads for `i18n.glibcLocales`. So the aspect never forces or replaces `extraSpecialArgs`; it only asserts that `flake` is absent from it.
- **Rationale**: an argument that every home receives whether or not its composer chose it cannot be narrowed for one home: specialArgs are host-wide, shallowly merged (A340), and shadow any `_module.args` of the same name (A341). Passing it per home is what lets the worker aspect hand worker homes something smaller (D6), and the single definition removes the order-dependent merge. A `_module.args` value cannot be read while `imports` are collected (A341), which is why the six import sites must read their flake-parts scope. Removing the host `_module.args.flake` changes nothing if no module reads it (A342). Boundary: source-only.
- **Alternatives considered**: (a) every home module reads the flake-parts scope (`inputs`, `config.flake`) and no `flake` argument exists at all. It is den's shape, but each of the forty modules then closes over the full flake, including the twenty-five a worker imports, so no value handed to a worker home can narrow what it reaches, and the guard would shrink to the worker aspect's own file (Open Question 1). (b) keep a host-wide specialArg holding the one value: removes the order dependence but cannot restrict workers.

### D6: the worker aspect closes over a restricted value

- **Choice**: `home/ai/omnigent/worker.nix` binds, in its flake-parts scope,
  `workerFlake = { inputs = { inherit (inputs) llm-agents; contentPrivate = throw "omnigent worker home: contentPrivate is outside the worker's inputs"; }; packages = config.flake.packages; users = throw "omnigent worker home: flake.users is outside the worker's inputs"; userAliases = throw "…"; }`,
  and `flake.modules.homeManager.omnigent-worker` sets `_module.args.flake = workerFlake`. Every builder of a worker home gets it with the aspect: `nixos/omnigent-host.nix:342-370` (integrated), `darwin/omnigent-host.nix:103-131` (standalone, whose `extraSpecialArgs.flake` goes), and the fixtures in `checks/omnigent-workers.nix`, whose local poisoned `flake` (`:16-21`) goes. The list (proposal question 2) is read off the worker's imports (Context); `direnv-instant` leaves it because D5 moves `direnv.nix` to its flake-parts scope. A name is added only when a real worker home needs it and it is not a route to a person's settings.
- **Rationale**: the worker's `flake` now holds only what the worker's modules read, so a worker home names `contentPrivate` or a whole user only through the two bindings that fail. They are bindings to `throw` rather than absent, because `builtins.tryEval` catches a `throw` but not a missing attribute (A347), and the mutant check (D7) observes the failure under `tryEval`. The guard now covers the real worker homes on magnetite, pyrite and stibnite, which their machine checks evaluate, not only the fixtures. The integration aspect's assertion that no `extraSpecialArgs.flake` exists keeps a host-wide value from shadowing this one unseen (A341). Boundary: source-only.
- **Alternatives considered**: (a) keep the check-local poison: it guards fixtures only. (b) leave `users` absent: a reach then fails evaluation, but not catchably, so no check could observe it pass or fail.

### D7: a mutant check, `checks.x86_64-linux.omnigent-worker-scope`

- **Choice**: a new check in `checks/omnigent-workers.nix`, declared `testSizes.checks.omnigent-worker-scope = { class = "medium"; measured = false; }` on x86_64-linux. Its cases, each an `assertMsg` at evaluation:
  - `positive`: a fixture worker home built with the worker aspect evaluates (`home.activationPackage.drvPath` forces);
  - `reachUsers`: the same home plus a module that sets a file's text from `flake.users.crs58.meta.email` fails under `tryEval`;
  - `reachContentPrivate`: the same with `flake.inputs.contentPrivate` fails under `tryEval`;
  - `allowedNames`: `attrNames workerFlake` and `attrNames workerFlake.inputs` equal a literal list in the check;
  - `noShadow`: the Linux host fixture, composed with the NixOS integration aspect, records in a probe file the attribute names of the `flake` its worker home receives, and they equal the same literal.

  The check's derivation is a `runCommand` that records the case names.
- **Rationale**: the two mutants show the two named reaches fail; the literal pins the value's names by equality, so the check fails if a name is added or removed without review; the probe shows the value a worker sees on a composed host is the worker's, not a shadowing specialArg. Class `medium` and `measured = false` until nixbot has run it. Boundary: source-only.
- **Alternatives considered**: a runtime test. Nothing at runtime adds evidence about what a home's evaluation can read.

### D8: the worker relation is `flake.fleet.workers.<owner>`

- **Choice**: a new `modules/lib/fleet-workers.nix` declares `options.flake.fleet.workers : attrsOf (submodule { linearLabels : listOf str; hosts : attrsOf (submodule { containers : attrs, default { }; }); })`, keyed by owner (a `flake.users` key, asserted on read). Values: cameron with `[ "personal" "work" ]` on magnetite (`containers.engine = "rootless-podman"`), pyrite (`rootless-podman`, `incus = "restricted"`) and stibnite; janettesmith with `[ "personal" ]` on magnetite and pyrite. Derived from it:
  - `clan/inventory/services/omnigent.nix`'s `roles.host.machines.<h>.settings = { legacyEnable = false; workers = <owner> ↦ { enable = true; owner; user = "omnigent-<owner>"; credentials = workerCredentials owner user linearLabels; } // optionalAttrs (containers != { }) { inherit containers; }; }` for every host named by some owner;
  - `lib/fleet-deployer.nix`'s `requesterNames = attrNames config.flake.fleet.workers`;
  - `flake.lib.workerAccountsOn host`, the sorted `omnigent-<owner>` names on a host, which the three hosts' `participants` append to their literal human participant (`[ "cameron" ]` on magnetite and pyrite, `[ "crs58" ]` on stibnite).

  `expectedOwners`, `hostMatrix`, `serverMatrix` and `omnigent-acp-spawn-env`'s host list stay literal oracles: they are what the derived inventory is judged against.
- **Rationale**: the relation is between a person and hosts, and its other facts (Linear labels) belong to the owner, so it sits beside the host entity, not inside it (proposal question 6). `containers` is per (owner, host) because the service takes it per worker; omitting it where empty keeps stibnite's settings byte-identical, which the `serializable` and `hostMatrix` cases of `omnigent-worker-inventory` check. Derived lists come out in today's order (sorted names). Boundary: vendored-versus-first-party: the omnigent clan service is first-party (`input = "self"`), and its settings are set as its interface declares.
- **Alternatives considered**: (a) `flake.fleet.hosts.<h>.workers`: puts owner facts on hosts and makes the deployer and inventory read across every host. (b) keep `containers` host-level: no host fact today says a host runs rootless podman for workers only.

### D9: `checkedUsers` is generated from the attachments and `flake.users`' names and systems

- **Choice**: for each of `x86_64-linux` and `aarch64-darwin` only, `checkedUsers.${s} = [ "crs58" ] ++` the `flake.users` keys that are not `flake.userAliases` keys, whose `systems` include `s`, and that no host of system `s` attaches, without `crs58`. It reads attachment names, `flake.users` names, `userAliases` and each user's `systems`, never `aggregates`, a machine configuration or `pkgs`. The result for today's data equals the literals (x86_64-linux: crs58, christophersmith, claude-sandbox, janettesmith, raquel, ubuntu; aarch64-darwin: crs58, tara). It is accepted only if `just eval-cost checks.x86_64-linux <parent> <tip> 2 keys` stays within the run-to-run spread of the parent's measurement; otherwise the literal stays and an evaluation-time assertion on the checks' values (not their names) compares it with the generated set (proposal question 4).
- **Rationale**: the rule in `checks/home.nix:9-31` is exactly this computation; generating it removes the "revisit this list" instruction. Restricting it to the two checked systems keeps `aarch64-linux` free of new checks. Boundary: source-only.
- **Measured 2026-11-27 (tasks 1.5, 4.9, `logs/dhuro-1-keyset-cost-20261127T092547Z.log`, `logs/dhuro-4-keyset-cost-20261127T092547Z.log`)**: stock Nix, a fresh process per run, two rounds per side. At the parent the key sets cost 811296 thunks and 0.32-0.33 s CPU (x86_64-linux) and 578987 thunks and 0.28-0.29 s (aarch64-darwin); thunks and allocation are identical between runs. Against the same tree with the literal lists, the generated `checkedUsers` adds 4314 thunks (0.5%) and 0.16% allocation on x86_64-linux and 5677 thunks (1.0%) and 0.3% on aarch64-darwin, with CPU and wall within the parent's run-to-run spread.
- **Outcome**: accepted on CPU and wall time, the measures whose run-to-run spread is not zero by construction. Thunk and allocation counts are deterministic, so their increase is real, not noise: generating the key set costs 0.5% (x86_64-linux) and 1.0% (aarch64-darwin) more thunks, which this acceptance takes on. If a later measurement puts CPU or wall time outside the spread, the fallback is to restore the literal lists with the evaluation-time judge described above.
- **Alternatives considered**: reading `homeConfigurations` names: they filter on `aggregates`, which forces every user's aggregate list.

### D10: `accountOf` and `personOf` in one file; `signingPerson` goes

- **Choice**: `home/users/aliases.nix`, which holds `flake.userAliases`, defines `flake.lib.accountOf = name: userAliases.${name} or name` (person→account, today's `signingPerson`) and `flake.lib.personOf` (account→person, today's agent-telemetry function with its two throws reworded without the module's name). `agent-telemetry.nix` reads `flake.lib.personOf`; every `signingPerson` reader (Context) reads `accountOf`, and `flake.lib.signingPerson` is removed. No key is renamed: the generator stays `crs58-commit-signing-key` and telemetry still records cameron.
- **Rationale**: both directions get a name and one definition, next to the table they read. A rename of the canonical keys would move `vars/shared/crs58-commit-signing-key` and split the agent-session telemetry history (brainstorm Q1, settled). Editing `home/users/lib.nix:103` changes `checks.x86_64-linux.eval-users-lib`, whose test imports `${./lib.nix}` by store path (D12). Boundary: source-only.
- **Alternatives considered**: keep `signingPerson` as a second name for `accountOf`: two names for one function.

### D11: smaller items

- `services.jj-pr-sync.enable` defaults to `!(config.deploysWithoutScreenSession or false)` in `home/development/jj-pr-tags.nix:297-305`; the three `= false` lines go. Standalone homes, where the flag is false, keep `true`. The `or false` keeps homes that do not import `core` (which declares the flag) evaluable.
- The omnigraph desktop client: `programs.omnigraph.studio.enable = true` moves into the `overrides` of (stibnite, crs58) and (pyrite, cameron); `home/users/crs58/default.nix:70-76` drops its host list and the option's default (false) applies elsewhere (proposal question 5: a fact of the attachment, because cameron's home on argentum and rosegold, which have displays, does not enable it).
- `system/stibnite-access.nix` is renamed `system/stibnite-session.nix`; its two module keys stay.

### D12: the acceptance oracle is one `just drv-diff` over the change's one commit

- **Choice**: `just drv-diff <parent> <tip> openspec/changes/declare-host-user-relations-once/drv-delta.txt`, about 16 minutes, run once by the operator over the single commit, and again at the merged head; the implementer returns the command rather than running it. `drv-delta.txt` declares:
  - `checks.x86_64-linux.omnigent-worker-scope added` (D7);
  - `checks.x86_64-linux.fleet-alert changed`: its size-rule clause renders every `testSizes.checks` entry;
  - `checks.x86_64-linux.eval-users-lib changed` (D10);
  - every check that builds or consumes `packages.vanixiets-docs` `changed`, on each system it exists on, because task 8.2 edits `packages/docs` (the same twenty-eight attributes type-the-fleet-host-registry's `drv-delta.txt` names);
  - `may-change`, because their source files are edited while the values they read should not change: `checks.x86_64-linux.{omnigent-worker-capabilities,omnigent-worker-linux}`, `checks.aarch64-darwin.{omnigent-worker-capabilities,omnigent-worker-darwin}`, `vmTests.x86_64-linux.{omnigent-worker-isolation,shared-reference-tree,shared-reference-tree-migration}` and `vmTests.aarch64-linux.omnigent-worker-isolation`. Each is resolved to `changed` or removed from the file, with its cause, before archive. Resolved 2026-11-27: all eight were identical in the run of task 9.1 (`logs/drv-diff-ec2c878bf4bc-1be931444c18-20261127T092819Z`), so the values they read did not change, and all eight are removed; the re-judgement passes (`report.20261127T094539Z`).

  Every NixOS, darwin and home configuration is expected identical. A toplevel that differs is traced with `nix derivation show` and, if its cause is the `flake` value or definition order, declared with every check and runtime test that embeds it; otherwise the edit is fixed.
- **Rationale**: one commit and one pull request, accepted on one full diff, because the groups share host and user-service files and a diff costs about 16 minutes. Each group keeps its own evidence by evaluation against task 1's baselines. Boundary: source-versus-delivered: equal drvPaths say the delivered closures are unchanged.

## Risks / Trade-offs

- [Risk] Definition order changes a list option inside a home (for example `home.packages` on stibnite), so `home-manager-path` differs → Mitigation: the entry imports the pair's overrides after the person's modules, and an override whose list order reaches a derivation uses `lib.mkAfter` (stibnite's crs58, D4, A344); the full projection of every host, home and worker home against the parent (`logs/dhuro-9-projection-diff-20261127T091051Z.txt`) and the drvPath diff detect any reorder.
- [Risk] A home module outside the six reads `flake` while `imports` are collected, giving infinite recursion → Mitigation: the search of task 5.2 for `imports` that mention `flake` across lines; evaluation of every configuration in group 5 fails loudly if one is missed.
- [Risk] A real worker home forces a name outside `workerFlake` (through `extraHomeModules`, or a shared module edited later) and fails evaluation uncatchably → Mitigation: the machine checks of magnetite, pyrite and stibnite evaluate every real worker home before merge; `omnigent-worker-scope`'s `allowedNames` makes a widening visible in review.
- [Risk] `config.networking.hostName` names a host with no registry entry (a runtime-test node importing the aspect) → Mitigation: the aspect reads `hosts.${hostName}.users or { }` only where a test imports it; the Linux fixture of D7 imports it with an attachment table of its own.
- [Risk] The darwin integration aspect and a host body both define `users.users.<a>.uid` → Mitigation: the bodies' uid lines are deleted in the same group; a remaining one fails with a conflicting-definition error.
- [Risk] An archive-time conflict on `world-assumptions`' grounded vocabulary, which other active changes also modify in full → Mitigation: the delta copies the corpus requirement as of 2026-11-27 and only appends rows; rows added since are merged by hand at archive.
- [Known gap] A wrong darwin `uid` in an attachment is detected by nothing: nix-darwin's activation warns, skips the account and succeeds, leaving it unmanaged (A346, read at the locked revision, `modules/users/default.nix:285-288` and `:197-198`). In this change the four darwin hosts' uids are copied unchanged, and the task 1.2 baseline projection shows them equal; after it, a later wrong edit goes unnoticed. No check is added here: it is the same exposure the host modules' literal uids have today.
- [Trade-off] The `flake` argument survives as a per-home argument in thirty-four home modules rather than disappearing, so a den migration still has to replace it → accepted: it is what lets worker homes receive less (D5, Open Question 1).
- [Trade-off] The guard names two reaches; a worker home could still reach private content through a name in `workerFlake.packages` or through a module's own flake-parts scope → accepted and stated in the interface's trust boundary.
- [Trade-off] Twenty-eight documentation checks rebuild for documentation edits → accepted, because the onboarding guides would otherwise tell a reader to declare `hm-sops-bridge.users` and `requesterNames` by hand.

## Migration Plan

1. Land establish-refactor-oracle, stop-reading-other-hosts-configs (both archived), type-the-fleet-host-registry (merged at `9055ae0f1`) and register-fleet-obligations; this change's parent is the latter's tip. register-fleet-obligations edits `checks/omnigent-workers.nix:11-15` and the two runtime tests this change also edits, so after rebasing onto it the baselines of task 1 are re-recorded and the drvPath diff is run from the new parent.
2. Land this change as one pull request of one commit, before compose-hosts-from-cohesive-aspects, which reads the attachment's admin, primary and uid. The commit passes `just drv-diff <parent> <tip> openspec/changes/declare-host-user-relations-once/drv-delta.txt`, run once by the operator (about 16 minutes).
3. Deploy: none if, as expected, no NixOS or darwin toplevel changes; the change then takes effect at each host's next deploy without changing it. If the diff declares a toplevel, that host is deployed after merge (`clan machines update <h>`), and every post on the fleet alert and failure topics since the deploy began is read and explained.
4. Rollback: revert the pull request. No state is migrated; no account, uid or key on any host changes.

## Pre-apply alignment

This table is the pre-apply spec-and-feature alignment record. It carries one row per requirement in this change's three delta specs, with the capability's stratum tag from the proposal and the executable check that realizes it.
No row routes to a Gherkin scenario: the repository has no BDD runner and no `.feature` file, so a laid-out scenario would be an unbound surface. Every observable this change asserts is a value of the evaluated flake or a drvPath, which `nix eval`, the flake checks and their mutants, and `just drv-diff` witness; the scenarios are realized as those checks, as type-the-fleet-host-registry's are.
No row routes to an executable-specification modality: the mutant check is an example-based build gate, not a ∀-quantified property.
Where a scenario has no task that observes it, the row says so.

| Requirement | Capability | Stratum | Executable check | Witness |
|---|---|---|---|---|
| Each account a person holds on a host is declared once | `host-user-attachment` | behavioral | content search (task 9.3) and `nix eval` projections against task 1's baselines; `just drv-diff` | tasks 3.4, 4.1-4.4, 9.1-9.3; the scenario "A person is given an account on a new host" has no witnessing task, since no attachment is added |
| A host provides exactly its declared accounts, home configurations and secret access | `host-user-attachment` | behavioral | machine checks `checks.x86_64-linux.nixos-*`, `checks.aarch64-darwin.darwin-*`; NixOS's own user assertions (task 4.6's mutant); projections of `home-manager.users` and `hm-sops-bridge.users`; home drvPaths against the baseline | tasks 4.6, 4.7, 9.2 |
| A darwin host's admin account is declared separately from its primary user | `host-user-attachment` | behavioral | `nix eval` of `system.primaryUser` and `primaryUser` per darwin host; mutants of task 3.5 | tasks 3.3, 3.5, 4.3 |
| Which hosts run a person's Omnigent workers is declared once | `host-user-attachment` | behavioral | `checks.x86_64-linux.omnigent-worker-inventory` (`hostMatrix`, `serverMatrix`, `serializable`), `fleet-deployer-obligations`, the machine checks' shared-reference-tree membership assertion | tasks 7.1-7.4 |
| An Omnigent worker's home configuration cannot read any person's private settings or whole home configuration | `host-user-attachment` | behavioral | `checks.x86_64-linux.omnigent-worker-scope` (new); `omnigent-worker-{capabilities,linux,darwin}`; machine checks of magnetite, pyrite, stibnite | tasks 6.1-6.5 |
| The person-account correspondence is stated once | `host-user-attachment` | behavioral | `nix eval` of both functions over every `flake.users` and alias key; `agent-telemetry-emitters`; machine checks' commit-signing obligations | tasks 2.1-2.3 |
| Every home configuration is checked without a hand-kept list | `host-user-attachment` | behavioral | `nix eval` of `checks.<s>` names against the baseline; `just eval-cost … keys` | tasks 4.8, 4.9 |
| A person's home configuration does not depend on the order a host's settings are read | `host-user-attachment` | behavioral | the aspect's no-specialArg assertion (machine checks); home drvPaths against the baseline; `just drv-diff` | tasks 1.3, 5.1-5.6, 9.1 |
| The attachment field on the host entity | `host-user-attachment-interface` | interface | `nix eval` (module types) | tasks 3.1-3.4 |
| Attachment constraints fail when read | `host-user-attachment-interface` | interface | mutants under `nix eval` and `tryEval` | task 3.5 |
| primaryUser is derived from the attachments | `host-user-attachment-interface` | interface | `nix eval` projection; `fleet-deployer-obligations` | tasks 3.3, 3.4 |
| The clan user instances' machine lists are generated | `host-user-attachment-interface` | interface | `nix eval` of the three instances' machines | task 4.1 |
| One home-manager integration aspect per class | `host-user-attachment-interface` | interface | machine checks; projections; content search | tasks 4.2-4.7 |
| No ambient flake argument | `host-user-attachment-interface` | interface | content search; the aspect's assertion; `nix eval` of every configuration | tasks 5.1-5.6 |
| The worker aspect closes over a restricted value | `host-user-attachment-interface` | interface | `omnigent-worker-scope` (`allowedNames`, `noShadow`) | tasks 6.1-6.3 |
| The worker-scope mutant check | `host-user-attachment-interface` | interface | `nix build .#checks.x86_64-linux.omnigent-worker-scope` | task 6.4 |
| The worker relation and what is derived from it | `host-user-attachment-interface` | interface | `omnigent-worker-inventory`, `fleet-deployer-obligations`, projections | tasks 7.1-7.4 |
| checkedUsers is generated from static data | `host-user-attachment-interface` | interface | check-name projection; `just eval-cost` | tasks 4.8, 4.9 |
| accountOf and personOf | `host-user-attachment-interface` | interface | `nix eval`; content search; `eval-users-lib` | tasks 2.1-2.3 |
| Per-pair flags read from the attachment and the screen-session flag | `host-user-attachment-interface` | interface | `nix eval` of `studio.enable` and `services.jj-pr-sync.enable` per home | task 4.5 |
| The stibnite session modules' file name matches its keys | `host-user-attachment-interface` | interface | content search; `nix-builders-wiring` | task 2.4 |
| Only the declared derivations change | `host-user-attachment-interface` | interface | `just drv-diff` with `drv-delta.txt` | tasks 9.1 |
| Trust boundary of the host-user attachment interface | `host-user-attachment-interface` | interface | capability text | specs text; the scenario "A recorded uid differs from the account on disk" has no witness after this change: nix-darwin's activation skips the account with a warning (A346), and the uids this change writes are witnessed only by task 1.2/9.2's projection |
| A340-A348 | `world-assumptions` | world | monitoring (violation scenarios) | A340, A341, A345-A347 by task 1.4's source reads; A341 also by task 6.4's `noShadow`; A342, A344, A348 by 9.1's drv-diff; A343 by 4.1; A346 by its source read alone (a darwin deploy warns and skips on a uid mismatch rather than failing); A347 by 6.4's mutants |
| Grounded vocabulary for behavioral requirements | `world-assumptions` | world | capability text | specs text |

## Open Questions

Each needs the operator; each carries the recommended answer.

1. **How far the ambient `flake` argument is removed.** Recommended: as D5 — no host-wide specialArg and no host `_module.args.flake`, with `flake` passed per home and a restricted value for workers. The alternative, every home module closing over the flake-parts scope, is den's shape but leaves nothing a worker's value can narrow, so the guard would cover only the worker aspect's own file.
2. **Two flags instead of a role enum.** Recommended: `primary` and `admin` as two booleans (D1), because stibnite's crs58 and pyrite's cameron hold both roles; the proposal's capability text said "role" and now states these two flags, as the specs do.
3. **`checkedUsers` generated or a literal with a judge** (proposal question 4). Recommended: generated (D9), accepted only if the key-set cost stays within the parent's spread; otherwise the literal stays with an evaluation-time judge.
4. **The studio flag** (proposal question 5). Recommended: a fact of the attachment, set in the two attachments' `overrides` (D11).
5. **Where `workers.<owner>.hosts` lives** (proposal question 6). Recommended: `flake.fleet.workers`, beside the host entity (D8).
6. **Editing `packages/docs`.** Recommended: update the onboarding and deploy-delegation guides (task 8.2), accepting the twenty-eight documentation checks as `changed`; leaving them would keep instructions to declare `hm-sops-bridge.users` and `requesterNames` by hand.
7. **Removing `flake.lib.signingPerson`.** Recommended: remove it and move its seven readers to `accountOf` (D10), accepting `eval-users-lib` as `changed`.

Proposal questions 1 (which `flake` value each darwin host gets) and 2 (the worker's input set) are answered by measurement and reading: D5 and task 1.3; D6 and the Context's worker-import survey. Proposal question 3 (field names and types) is answered by D1 and D2.

## Resolved Questions

The operator answered Open Questions 1-7 on 2026-11-27; every answer is the recommendation, so no task is added or changed by them.

1. **How far the ambient `flake` argument is removed** — "no host-wide specialArgs and no host-level `_module.args.flake`; `flake` is passed per home, with a restricted value for omnigent workers" (D5). Reason: only a per-home value can be narrowed for worker homes.
2. **Two flags instead of a role enum** — "`primary` and `admin` are two booleans, not a role enum" (D1). Reason: stibnite's crs58 and pyrite's cameron hold both roles.
3. **`checkedUsers`** — "generated from the attachments, accepted only if the key-set evaluation cost stays within the parent's run-to-run spread; otherwise keep the literal with an evaluation-time judge" (D9), measured with single-attribute `NIX_SHOW_STATS` runs in the manner of `just eval-cost`. Reason: the rule in `checks/home.nix` is that computation; the cost bound keeps `checks.<system>` names cheap. The measured outcome is recorded under D9.
4. **The studio flag** — "a fact of the attachment, set in the two attachments' `overrides`" (D11). Reason: cameron's homes on argentum and rosegold have displays and do not enable it.
5. **Where the worker relation lives** — "`flake.fleet.workers`, beside the host records" (D8). Reason: its other facts (Linear labels) belong to the owner.
6. **Editing `packages/docs`** — "update the onboarding and deploy-delegation guides (task 8.2), declaring every docs-package check as changed". Reason: the guides would otherwise instruct declaring `hm-sops-bridge.users` and `requesterNames` by hand.
7. **Removing `flake.lib.signingPerson`** — "remove it and move its seven readers to `accountOf`" (D10). Reason: two names for one function.

Settled before these: no person or account key is renamed, and the poisoned `flake` in `checks/omnigent-workers.nix` is replaced by the worker aspect's restricted value and the `omnigent-worker-scope` mutant check (D6, D7).

Sequencing during apply (2026-11-27): an earlier plan left `modules/darwin/omnigent-host.nix` and `modules/vm-tests/shared-reference-tree.nix` to another change that was to land first. The commit makes both edits itself: the darwin worker builder passes only `extraSpecialArgs.osConfig = null`, so stibnite's standalone worker homes receive the worker aspect's restricted value, and neither runtime test passes `extraSpecialArgs.flake`. The drvPath diff of task 9.1 shows `checks.aarch64-darwin.omnigent-worker-darwin`, stibnite's toplevel and both runtime tests identical. Tasks 5.3 and 6.2 record these edits.

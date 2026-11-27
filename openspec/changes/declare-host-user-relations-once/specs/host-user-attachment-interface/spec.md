## ADDED Requirements

### Requirement: The attachment field on the host entity

`modules/lib/host-users.nix` SHALL add a field `users : attrsOf (submodule …)` to the host entity `flake.fleet.hosts.<host>` of `modules/lib/hosts.nix`, and SHALL hold every attachment's value. Each attachment SHALL be keyed by a `flake.users` key and carry the fields with the types and defaults the scenario "The fields have their types" lists. `flake.lib.hostsOfAccount account` SHALL return the sorted names of the hosts with an attachment for `account`.

#### Scenario: The fields have their types

- **WHEN** the attachment submodule is read
- **THEN** it declares `primary : bool` (default false), `admin : bool` (default false), `sopsBridge : bool` (default `class == "nixos"`), `uid : nullOr ints.positive` (default null), `extraImports : listOf deferredModule` (default `[ ]`) and `overrides : deferredModule` (default `{ }`)

#### Scenario: The attachments are listed

- **WHEN** `nix eval --json .#fleet.hosts --apply 'hs: builtins.mapAttrs (_: h: builtins.attrNames h.users) hs'` runs
- **THEN** cinnabar, electrum and magnetite list `cameron`; galena and scheelite `cameron` and `tara`; pyrite `cameron`; argentum `cameron` and `christophersmith`; rosegold `cameron` and `janettesmith`; stibnite `crs58`; blackphos `crs58` and `raquel`; the phones none

#### Scenario: The darwin fields carry today's values

- **WHEN** `admin`, `primary` and `uid` are read for the darwin attachments
- **THEN** argentum and rosegold have cameron admin with uid 502 and the primary person with uid 501; stibnite has crs58 admin and primary with uid 501; blackphos has crs58 admin with uid 502 and raquel primary with uid 506

### Requirement: Attachment constraints fail when read

Reading an attachment field, or a host's `primaryUser`, SHALL fail with a `throw` naming `flake.fleet.hosts.<host>.users.<account>.<field>` when: more than one attachment on a host has `primary`; a darwin host does not have exactly one `admin`; a NixOS attachment has `admin`; `uid` is null on darwin or non-null on NixOS; `sopsBridge` is true on darwin; or the account is not a `flake.users` key.

#### Scenario: Each constraint has a mutant

- **WHEN** a throwaway tree applies each violation in turn and evaluates the field it constrains
- **THEN** each evaluation fails naming the host and account, and `builtins.tryEval` of the same read returns `success = false`

### Requirement: primaryUser is derived from the attachments

`flake.fleet.hosts.<host>.primaryUser` SHALL be read-only, set to the account of the one attachment with `primary = true`, or null, with its type unchanged, and SHALL be written nowhere else.

#### Scenario: The primary users are unchanged

- **WHEN** `primaryUser` is read for every member through `flake.lib.hosts` at the parent revision and at the change's tip
- **THEN** the values are equal: pyrite cameron, stibnite crs58, blackphos raquel, argentum christophersmith, rosegold janettesmith, every other member null

### Requirement: The clan user instances' machine lists are generated

`flake.clan.inventory.instances.user-{cameron,crs58,tara}.roles.default.machines` SHALL each be `lib.genAttrs (flake.lib.hostsOfAccount "<user>") (_: { })`, with no host named literally in those three files.

#### Scenario: The instances name the same machines

- **WHEN** the three instances' `roles.default.machines` names are read before and after
- **THEN** they are equal, and `rg -n 'roles.default.machines\."' modules/clan/inventory/services/users` finds nothing

### Requirement: One home-manager integration aspect per class

`flake.modules.{nixos,darwin}.home-manager-integration`, in `modules/system/home-manager-integration.nix` and imported by every NixOS and darwin host, SHALL be the only writer of home-manager's integration settings, and SHALL generate from the host's attachments the values the scenario "What the aspect generates" lists. It SHALL assert that each attached account exists in `users.users`. `custom.laptop.primaryUser` SHALL NOT exist; `laptop.nix` SHALL read the registry's `primaryUser`.

#### Scenario: What the aspect generates

- **WHEN** the aspect's definitions are read
- **THEN** it sets `home-manager.useGlobalPkgs`, `useUserPackages` and `backupFileExtension`; one `home-manager.users.<account>` per attachment, of the form `{ imports = [ overrides ] ++ flake.users.<account>.modules ++ extraImports; _module.args.flake = flake.lib.homeFlake; }`; on NixOS, `hm-sops-bridge.users` for the attachments with `sopsBridge`; on darwin, `system.primaryUser` from the `admin` attachment and `users.users.<account>.uid` from each `uid`

#### Scenario: The generated values equal the hand-written ones

- **WHEN** each host's `home-manager.users` names, `hm-sops-bridge.users` names, darwin `system.primaryUser` and darwin uids are read before and after
- **THEN** they are equal, and each attached home's `home.activationPackage.drvPath` equals its parent-revision value

#### Scenario: No host writes them by hand

- **WHEN** `rg -n 'hm-sops-bridge\.users\.[a-z]+ =|home-manager\.users\.[a-z0-9]+ =|system\.primaryUser =|custom\.laptop\.primaryUser|useGlobalPkgs' modules/machines modules/darwin/laptop.nix modules/clan/inventory/services/users` runs
- **THEN** it finds nothing

#### Scenario: An attachment for an account nothing creates

- **WHEN** a throwaway tree attaches a `flake.users` key with no clan user instance to a NixOS host
- **THEN** evaluating that host's configuration fails with the aspect's assertion naming the host and account

### Requirement: No ambient flake argument

No `home-manager.extraSpecialArgs`, `homeManagerConfiguration` `extraSpecialArgs` or host `_module.args` SHALL define `flake`. `flake.lib.homeFlake` SHALL be `config.flake // { inherit inputs; }`, defined once, and SHALL reach a home only through `_module.args.flake` set by the integration aspect or by `flake.lib.mkHome`. No home module SHALL read `flake` while its `imports` are collected. Both integration aspects SHALL assert that `home-manager.extraSpecialArgs` has no `flake` attribute.

#### Scenario: The ambient writers are gone

- **WHEN** `rg -n '_module\.args\.flake|extraSpecialArgs[^;]*flake' modules` runs, and a search for `imports` lists that mention the `flake` argument runs
- **THEN** the first finds only `_module.args.flake` in the integration aspect, `mk-home.nix` and the worker aspect, and the second finds nothing

#### Scenario: A host-wide value is reintroduced

- **WHEN** a throwaway tree sets `home-manager.extraSpecialArgs.flake` on one host
- **THEN** evaluating that host's configuration fails with the aspect's assertion

### Requirement: The worker aspect closes over a restricted value

`flake.modules.homeManager.omnigent-worker` SHALL set `_module.args.flake` to a value bound in its own flake-parts scope, holding only the names the scenario "The restricted value" lists. Every builder of a worker home (`nixos/omnigent-host.nix`, `darwin/omnigent-host.nix`, the fixtures of `checks/omnigent-workers.nix`) SHALL take the value from the aspect and pass no `flake` of its own. The check-local poisoned `flake` SHALL NOT exist.

#### Scenario: The restricted value

- **WHEN** the value's names are read
- **THEN** it holds `inputs.llm-agents` and `packages`, and binds `users`, `userAliases` and `inputs.contentPrivate` to a `throw` naming the breach

#### Scenario: The real worker homes evaluate with the restricted value

- **WHEN** the worker homes of magnetite, pyrite and stibnite are evaluated
- **THEN** each `home.activationPackage.drvPath` equals its parent-revision value

### Requirement: The worker-scope mutant check

`checks.x86_64-linux.omnigent-worker-scope` SHALL exist, with `testSizes.checks.omnigent-worker-scope = { class = "medium"; measured = false; }`, and SHALL fail evaluation unless each case the scenario "The cases" lists holds.

#### Scenario: The cases

- **WHEN** the check's cases are read
- **THEN** they are: a fixture worker home built with the worker aspect evaluates; the same home with a module reading `flake.users.crs58.meta.email` fails under `builtins.tryEval`; the same with `flake.inputs.contentPrivate` fails under `builtins.tryEval`; the names of the restricted value and of its `inputs` equal a literal in the check; and the worker home of a fixture NixOS host composed with the integration aspect receives a `flake` with exactly those names

#### Scenario: The check passes on the change

- **WHEN** `nix build .#checks.x86_64-linux.omnigent-worker-scope` runs
- **THEN** it succeeds

#### Scenario: The guard is weakened

- **WHEN** a throwaway tree binds the restricted value's `users` to `config.flake.users`
- **THEN** the check fails evaluation, naming the `reachUsers` case

### Requirement: The worker relation and what is derived from it

`modules/lib/fleet-workers.nix` SHALL declare `options.flake.fleet.workers : attrsOf (submodule { linearLabels : listOf str; hosts : attrsOf (submodule { containers : attrs; }); })`, keyed by `flake.users` keys. The omnigent inventory's `roles.host.machines`, the deployer's requester names and each host's worker participants in its reference tree SHALL be computed from it. `expectedOwners`, `hostMatrix`, `serverMatrix` and `omnigent-acp-spawn-env`'s host list SHALL stay literals.

#### Scenario: The declared owners

- **WHEN** `nix eval --json .#fleet.workers` runs
- **THEN** it holds cameron (`personal`, `work`; magnetite, pyrite, stibnite) and janettesmith (`personal`; magnetite, pyrite)

#### Scenario: The derived values are unchanged

- **WHEN** the omnigent inventory's `roles.host.machines` settings (as JSON), `flake.lib.fleetDeployer.requesters` names and the three hosts' `participants` are read before and after
- **THEN** each is equal, and `checks.x86_64-linux.omnigent-worker-inventory` and `fleet-deployer-obligations` build

### Requirement: checkedUsers is generated from static data

`checks/home.nix`'s `checkedUsers.<s>`, for `s` in `x86_64-linux` and `aarch64-darwin` only, SHALL be `crs58` together with the `flake.users` keys that are not `flake.userAliases` keys, whose `systems` contain `s`, and that no host of system `s` attaches. Computing it SHALL read no user's `aggregates`, no machine configuration and no `pkgs`.

#### Scenario: The checked names are unchanged and cost no more

- **WHEN** `checks.x86_64-linux` and `checks.aarch64-darwin` names are read, and `just eval-cost checks.x86_64-linux <parent> <tip> 2 keys` runs
- **THEN** the names equal the parent's, and the key-set cost is within the parent measurement's run-to-run spread

### Requirement: accountOf and personOf

`modules/home/users/aliases.nix` SHALL define `flake.lib.accountOf` (an alias key to its target, any other name to itself) and `flake.lib.personOf` (a name to the one alias key naming it, else to itself when it is a `flake.users` or alias key, else a `throw`). `flake.lib.signingPerson` SHALL NOT exist; its readers SHALL read `accountOf`, and `home/ai/agent-telemetry.nix` SHALL read `personOf`.

#### Scenario: Both directions over every key

- **WHEN** both functions are evaluated over every `flake.users` and `flake.userAliases` key
- **THEN** `accountOf "cameron"` is `"crs58"`, `personOf "crs58"` is `"cameron"`, every other key maps to itself, and `rg -n signingPerson modules` finds nothing

### Requirement: Per-pair flags read from the attachment and the screen-session flag

`services.jj-pr-sync.enable` SHALL default to `!(config.deploysWithoutScreenSession or false)` with no account setting it to false by hand. `programs.omnigraph.studio.enable` SHALL be set only in the `overrides` of the stibnite crs58 and pyrite cameron attachments, and `home/users/crs58/default.nix` SHALL name no host.

#### Scenario: The flags are unchanged per home

- **WHEN** both options are read for every attached and standalone home before and after
- **THEN** every value is equal

### Requirement: The stibnite session modules' file name matches its keys

`flake.modules.nixos.stibnite-session` and `flake.modules.darwin.stibnite-session-host` SHALL be defined in `modules/system/stibnite-session.nix`, and `modules/system/stibnite-access.nix` SHALL NOT exist.

#### Scenario: The rename keeps the modules

- **WHEN** `checks.x86_64-linux.nix-builders-wiring` is built after the rename
- **THEN** it succeeds

### Requirement: Only the declared derivations change

The change SHALL leave every dumped derivation unchanged except those its `drv-delta.txt` names.

#### Scenario: The drvPath diff over the change's commit

- **WHEN** `just drv-diff <parent> <tip> openspec/changes/declare-host-user-relations-once/drv-delta.txt` runs
- **THEN** it exits 0: `checks.x86_64-linux.omnigent-worker-scope` was added; `checks.x86_64-linux.fleet-alert`, `checks.x86_64-linux.eval-users-lib` and every check that builds or consumes the docs package changed; each `may-change` entry is resolved; and no NixOS, darwin or home configuration differs unless declared with its cause

### Requirement: Trust boundary of the host-user attachment interface

The option types, evaluation-time assertions and the worker-scope check SHALL be read as checking only what is written in the repository and what an evaluation of it can reach. The drvPath diff SHALL be read as showing that the generated values equal the hand-written ones only for the attributes it dumps.

#### Scenario: What the interface does not show

- **WHEN** the interface's guarantees are relied on
- **THEN** they do not show that an account, uid or home already on a host matches its attachment, that a worker home has no route to private content other than the two names the check reaches for (through `packages`, or through a shared module's own flake-parts scope), or that a person's personal key on a host is the one the bridge expects

#### Scenario: A recorded uid differs from the account on disk

- **WHEN** a darwin attachment's `uid` differs from the uid of the existing account on that Mac
- **THEN** no check of this interface fails, and the difference is found only when that host is deployed, as A346's monitor states

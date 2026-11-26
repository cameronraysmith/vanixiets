## Context

### Current state

A fleet host is described in six hand-kept tables (brainstorm.md, "What a host is today"). Its kind is written four ways:
- `class` in `modules/lib/hosts.nix`;
- the system string in `flake.lib.machineSystems` (`modules/clan/inventory/machines.nix:10-21`);
- `machineClass` in the clan inventory (same file, :23-139);
- `platform` in `flake.lib.observabilityHosts`.

The system string is written a fifth time as `nixpkgs.hostPlatform` in eight host modules and `darwin/laptop.nix:69`. Seven readers recover "darwin" from the system by `lib.hasSuffix "-darwin"`. The registry lives under `flake.lib`, typed `lazyAttrsOf raw` (`modules/lib/option.nix:3-6`), so its fields have no types and it has to stay in one file (`hosts.nix:4-5`).

The checks that hold the tables together compare attribute names (`modules/checks/machines.nix:100-117`) and, in one place, platform with inventory class (`clan/inventory/services/otel-collector.nix:14-34`). Lifecycle facts are a list in one check (`deferred`, `checks/machines.nix:6`), a literal name in another file (`tincr.nix:24`) and a comment beside a memory figure (`hosts.nix:168-172`). Role membership is resolved in three different ways (brainstorm.md, "Role membership resolved three ways").

### Requirements and the world they rest on

| Req | Statement (behavioral, `fleet-host-registry`) | Rests on | Breaks if it fails | Discharged by |
|---|---|---|---|---|
| R1 | Each fact about a fleet host is recorded once; a fact that follows from another is derived | A305 | two tables disagree and a host builds as the wrong kind | D1, D2, D3 |
| R2 | A fleet member that runs no Nix configuration is never treated as a host that builds one | — | a phone appears in a machine check or a system list and evaluation fails | D2 |
| R3 | Lifecycle facts are independent: changing whether a host is checked, enrolled or has its cloud server up changes none of the others | A304 | turning a cloud server off removes its machine check | D5 |
| R4 | A cloud host's memory follows from its cloud machine type | A303 | a resized server keeps its old evaluator bound | D6 |
| R5 | Membership in a service role is decided by one rule, the one clan applies | A302 | a check or app misses a member clan deploys the role to | D7 |
| R6 | The ZeroTier controller admits exactly the members that do not join ZeroTier through clan | A300 | a new laptop or phone cannot join, or a removed one stays admitted | D8 |
| R7 | A host dropped from every table at once, or whose kind flips, is still caught by a record kept independently of the one it checks | — | the derivation hides its own mistakes | D4 (golden pin kept) |
| R8 | A host whose memory cannot be read is reported, never silently classified | A301 | an unclassified host gets the wrong evaluator | D6 |

### Stakeholders

The operator, who edits host facts and deploys. The checks that read the record's key sets. Later changes that hang fields on the record: the host↔user relations, the host module state version and the worker relation. A future den migration, which will map `flake.fleet.hosts.<h>` onto `den.hosts.<system>.<h>`.

## Goals / Non-Goals

**Goals:**
- One typed record per fleet host, `flake.fleet.hosts.<name>`, holding every per-host fact the registry holds today, plus `system`, `checked` and `stateVersion`.
- Every per-host value now written in a second place is derived from the record instead.
- Every NixOS, darwin and home configuration, every gated check and every runtime test keeps its drvPath, except the ones the change's `drv-delta.txt` declares: cinnabar's system and machine check (D8), the fleet-topology evaluation check whose tested source file this change edits, the fleet-topology freshness check whose committed files the tag rename changes (D12), and the resolver's new evaluation check (D10). `just drv-diff` proves it.
- Every kept assert is still seen failing on a mutant after the change.

**Non-Goals:**
- The host↔user relation record and generated user instances. A later change adds them as a field of this record.
- Making host modules read `stateVersion`. A later change switches them; this one only declares and fills it.
- Moving `flake.lib.cloudMachines` into the record. Terranix reads it, and its `enabled` is a cost decision with its own meaning.
- Typing `observabilityHosts` beyond deriving its `platform`, and typing its other row fields.
- Letting each `modules/machines/<class>/<h>/` directory contribute its own record. The type allows it later; this change keeps the values in one file.

## Decisions

### D1: a typed option `flake.fleet.hosts`, with `flake.lib.hosts` as its read-only alias

- **Choice**: `options.flake.fleet.hosts = lib.mkOption { type = attrsOf (submodule hostModule); }`, declared in `modules/lib/hosts.nix`. Values are declared in the same file. The declared fields are:
  - `system : nullOr (enum [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ])`
  - `endpoints : listOf str`
  - `deployUser : nullOr str`
  - `services : listOf str`
  - `zerotier : { address : str; memberId : str; }`
  - `primaryUser : nullOr (enum (attrNames config.flake.users))`
  - `memory : nullOr (either ints.positive (enum [ "unknown" ]))`
  - `nixClassic : bool`
  - `checked : bool`, default true
  - `stateVersion : nullOr (either ints.positive str)`

  The read-only fields are `class`, `fqdn`, `address`, `targetHost`, `memoryGiB`, `enrolled` and `cloud`, each set by the submodule from `name` and the declared fields. `flake.lib.hosts = config.flake.fleet.hosts`. `meshRecords` stays in `hosts.nix` and reads the option.
- **Rationale**: types replace four hand-written asserts. A submodule option can be declared again from another file, which lets the host↔user record be added as a field without touching this file. The flake-parts `flake.users` option (`modules/home/users/lib.nix:41-230`) already works this way. The alias keeps every existing reader of `flake.lib.hosts` working, so readers migrate one file at a time. Boundary: source-only. Nothing vendored changes, and no delivered file changes.
- **What typing does not give**: option values are still lazy. A type error fires only when that field is read, so evaluation is no more eager than today and the gain is in diagnosis, not speed.
- **Alternatives considered**: (a) keep raw data under `flake.lib` and add asserts. It is the smallest change, but it keeps the one-file restriction and the untyped shape a den migration must reinterpret. (b) Put the record under `flake.lib.hosts` with a typed sub-option of `flake.lib`. `flake.lib` is `lazyAttrsOf raw` for good reason (functions), and typing one key of it is not expressible without retyping the whole option.

### D2: `system` is the declared fact; `class` is derived from it

- **Choice**: `class = if system == null then "android" else if lib.hasSuffix "-darwin" system then "darwin" else "nixos"`. This is the only `-darwin` suffix test that remains. The phones `pixel7` and `pixel11` declare `system = null`. `flake.lib.machineSystems = mapAttrs (_: h: h.system) (filterAttrs (_: h: h.system != null) hosts)`. The seven suffix readers (`checks/machines.nix:63,67`, `lib/commit-signing.nix:188`, `lib/omnigent-fleet-obligations.nix:179`, `system/deploy-record.nix:148`, `system/harmonia-gc.nix:79`, `system/mesh-hosts.nix:84`) read `hosts.${name}.class == "darwin"`.
- **Rationale**: only the system carries information the class does not (architecture). `machineSystems` stays flake-level data computed from the record and is never read back from an evaluated configuration. Check key sets that filter on it, such as `zerotierone-controller` and `machines`, still depend only on static data (`preferences-nix-checks-architecture` SKILL.md:153,172). Boundary: source-only.
- **Alternatives considered**: (a) declare `class` and `system` and assert they agree. That is today's duplication with a guard. (b) Derive `system` from `class` with a per-class default. It fails at the first aarch64-linux or x86_64-darwin host.

### D3: the inventory and `clan.machines` are generated from the record

- **Choice**:
  - `clan/inventory/machines.nix` keeps its literal `tags` and `description` per host and merges each entry with `{ machineClass = h.class; }`, plus `deploy.targetHost = h.targetHost` where `h.class == "nixos"`.
  - `clan/machines.nix` becomes `mapAttrs (name: h: { imports = [ config.flake.modules.${h.class}."machines/${h.class}/${name}" ]; nixpkgs.hostPlatform = h.system; })` over the hosts whose `system` is non-null.
  - The nine literal `nixpkgs.hostPlatform` lines are deleted from `machines/nixos/{cinnabar,electrum,galena,scheelite,magnetite,pyrite}/default.nix`, `machines/darwin/{blackphos,stibnite}/default.nix` and `darwin/laptop.nix`.
- **Rationale**: the host key `machines/<class>/<name>` is kept as ADR-0020 and ADR-0018 fix it, because `checks/ssh-identity.nix:30,41` and `checks/pyrite-desktop.nix:102` inject into it. The darwin hosts still get no inventory `deploy.targetHost`. That obligation is backed by mutants (`clan/inventory/machines.nix:1-4`, `flake.lib.networkTargetObligations`). The same platform value defined from the seam instead of from the host module leaves the system derivation unchanged (A305). No check or VM test imports a host module outside `clan/machines.nix` (searched 2026-11-26), so moving the line cannot leave a consumer without a platform. Boundary: vendored-versus-first-party. clan-core's inventory and `clan.machines` interfaces are used as documented and not patched.
- **Alternatives considered**: (a) generate tags and descriptions too. Tags are operator vocabulary for `clan machines update --tags` and deserve to stay where they are read; D12 renames one of them in place. (b) Keep `hostPlatform` in each host module and assert it equals the record. The assert would have to evaluate every configuration to read it.

### D4: which asserts go and which stay

- **Choice**:
  - Kept, unchanged: every assert in `checks/machines.nix:100-123`. That is `machineSystems` names = inventory names (`:100-102`), inventory = `nixosConfigurations` / `darwinConfigurations` names (`:103-108`), `clan.machines` names = inventory names (`:109-111`), the `modules/machines/<class>/` directory asserts (`:112-117`), and the omnigent expected-owners and fleet-deployer asserts (`:118-123`). `checks/structure/flake-shape.nix` relies on them, and its golden pin stays a literal over the inventory's `machineClass`.
  - Removed as a tautology: the collector `platform` = `machineClass` assert (`otel-collector.nix:14-34`). Both of its sides now read the record's `class`.
  - Moved into the option: the `hosts.nix:196-205` cross-table asserts. `primaryUser` and `memory` become fields of the same record, so the name-coverage asserts have nothing to compare. The rule that `nixClassic` requires a `primaryUser` stays as a `throw` on `nixClassic`'s read.
- **Rationale**: the inventory keeps its own literal entries (D3: per-host `tags` and `description`, keyed by name), so its name set is still written independently of the record. After this change `machineSystems` and `clan.machines` are computed from the record, so the two name asserts compare the record's hosts with a system against the inventory's literal entries. They catch a host added to one and not the other, and are not tautologies. Only an assert whose two sides come from one source cannot fail; the collector assert is the one such case. The golden pin is the one record kept independent of both, so it catches a host dropped from the record and inventory together, or a class flipped by a wrong `system`. It is also the oracle a den migration will be measured against (`flake-shape.nix:1-12`). Boundary: source-only.
- **Alternatives considered**: (a) delete the two name asserts as tautologies. Rejected: the inventory's names are not derived from the record, so the asserts still guard a real disagreement, and `flake-shape.nix:3-5` relies on them. (b) Replace them with one "record names with a system = inventory names" assert. It would carry the same coverage under a new message for no gain. (c) Derive the golden pin from the record. That would make it check the record against itself.

### D5: lifecycle and cloud facts are separate fields, never one enum

- **Choice**:
  - `checked : bool` (default true; scheelite false) replaces `deferred` in `checks/machines.nix` and its use in the omnigent owners assert.
  - `enrolled` is read-only: `builtins.pathExists (self + "/sops/machines/${name}")`. It is false for blackphos and the phones. tincr's peer filter becomes `host.class != "android" && host.enrolled`, and the literal `name != "blackphos"` goes.
  - `cloud` is read-only: `null`, or `{ provider; type; enabled; }` read from `flake.lib.cloudMachines.<provider>.<name>`. The type is `serverType` on Hetzner and `machineType` on GCP.
  - `lib/fleet-deployer.nix`'s `enabledOf` reads `hosts.${name}.cloud.enabled` (true when `cloud` is null) instead of merging the two provider tables itself.
  - The deployer's `excluded` workstations and commit signing's `commitSigningLegacyMachines` stay where they are.
- **Rationale**: the facts are independent (A304; brainstorm.md, "Facts about a host's life"). electrum is checked, enrolled and has its server down. Reading `cloud.enabled` as "checked" would drop `nixos-electrum` and `nixos-galena`. `inventory.json`'s `installedAt` was rejected as a "provisioned" signal: darwin hosts never have it, and electrum has it while destroyed. The signing-legacy and deployer-workstation lists are relations with their own owners. Folding them in would couple two policies to the record's lifecycle. Boundary: source-versus-delivered. `cloudMachines` stays the single writer that terranix reads into terraform; the record only reads it, so no terraform plan changes.
- **Alternatives considered**: (a) one `lifecycle` enum. It forces one value where three are independent. (b) A declared `enrolled` bool. That restates what the repository already shows; the machine key's presence is the fact clan itself acts on.

### D6: a cloud host's memory comes from its machine type

- **Choice**: `flake.lib.cloudMachineMemoryGiB = { cx43 = 16; ccx23 = 16; cx53 = 32; "e2-standard-8" = 32; "n1-standard-8" = 30; }`. The read-only `memoryGiB` is:
  - for a cloud host, the table at `cloud.type`, with a `throw` naming the type if absent;
  - otherwise, the declared `memory`, kept positive or `"unknown"` for a host that runs Nix and null for a phone.

  The literals for the five cloud hosts in `hosts.nix:168-172` go. pyrite 16, stibnite 64, blackphos `"unknown"`, argentum 8 and rosegold 8 stay declared.
- **Rationale**: the memory alone decides each host's evaluator and bound. Today a resized server keeps its old figure. `"unknown"` stays as `modules/README.md:51` specifies, and blackphos keeps it. The report `nixEvalJobsBoundProblems` (`lib/nix-eval-jobs-host.nix:169-173`) wraps each read in `builtins.tryEval`. That catches only `throw`, and both `lib.assertMsg` and module type errors are `throw` (A301). So every failure path on `memoryGiB` stays a `throw`, and the `unclassifiedIets` mutant in `checks/nix-eval-jobs-iets.nix:169-184` keeps being reported. Boundary: source-only.
- **Alternatives considered**: a declared `memory` with an assert that it matches the type's table entry. Two copies again.

### D7: one role-membership resolver over the declared inventory

- **Choice**: `flake.lib.inventoryMembers = instance: role:` returns sorted unique names. A name is included if it is named in `role.machines`, or if it is an inventory machine carrying one of `role.tags`, with `all` matching every inventory machine. It is defined in a new `modules/lib/inventory-members.nix`, and it takes the inventory machines from `config.flake.clan.inventory.machines`. A second form, `inventoryMembersIn machines instance role`, is for fleet-topology's fixtures, which pass their own inventory. The readers are:
  - `lib/fleet-topology.nix:89-98` (`membersOf`) through the second form. Its evaluation test stubs `config.flake.lib` (`fleet-topology.test.nix:26-34`), so the stub gains `inventoryMembersIn`, imported from `inventory-members.nix` the same way;
  - `checks/zerotier-mss-clamp.nix:20-27`, which gains `all`;
  - `checks/zerotierone-controller.nix:36-38`;
  - `apps/omnigent-worker-login.nix:3-6`. It asserts exactly one server member and that it is named in `.machines`, because it reads that entry's `settings`.
- **Rationale**: it is the rule clan applies (A302), stated once. It reads only the declared inventory, never a configuration, so `fleet-topology.nix:6-8`'s cost claim holds and check key sets stay static. Boundary: vendored-versus-first-party. This is a first-party restatement of clan's rule, held to it by A302's monitor.
- **Alternatives considered**: reading clan's resolved roles (`clanInternals`). It is accurate by construction but forces clan's inventory evaluation, which `fleet-topology` deliberately avoids.

### D8: ZeroTier `allowedIps` from class, accepted as cinnabar's one drvPath change

- **Choice**: `allowedIps = map (h: h.zerotier.address) (attrValues (filterAttrs (_: h: elem h.class [ "darwin" "android" ]) hosts))`, in registry name order.
- **Rationale**: it is the same six members, now derived from the fact that decides them: these members do not run clan's ZeroTier service. Clan writes the list into the controller's unit script in order (A300). The order goes from blackphos, stibnite, argentum, rosegold, pixel7, pixel11 to argentum, blackphos, pixel11, pixel7, rosegold, stibnite, so `nixosConfigurations.cinnabar` and `checks.x86_64-linux.nixos-cinnabar` change; both are declared in `drv-delta.txt` (D10). fleet-topology folds the list into an attribute set, so its committed files do not change. Boundary: vendored-versus-first-party. clan's setting is used as documented.
- **Alternatives considered**: keep a hand-ordered list and assert its set equals the derived one. It is neutral, but it is the restatement this change removes. The operator accepted the reorder on 2026-11-26 (Resolved Questions).

### D9: `stateVersion` is declared and filled, not yet read

- **Choice**: `stateVersion : nullOr (either ints.positive str)`. It is 4 for the four darwin hosts, `"25.05"` for cinnabar, electrum, galena, scheelite and magnetite, `"26.05"` for pyrite, and null for the phones. A read of the field `throw`s unless darwin carries an integer, NixOS a string and android null. Nothing reads the field in this change.
- **Rationale**: this is scope the operator added on 2026-11-26. The later host-composition change makes `darwin/base.nix:54`'s 5 and the `mkForce 4` lines (`darwin/laptop.nix:72`, `machines/darwin/blackphos/default.nix:63`, `machines/darwin/stibnite/default.nix:79`) read the record. Declaring the field here lets that change be a pure reader switch, with its own drvPath diff as the proof. Boundary: source-only. An unread field changes no derivation.
- **Alternatives considered**: switching the readers here too. It touches host modules other changes are reshaping, and the operator assigned it elsewhere.

### D10: the acceptance oracle is `just drv-diff` with a declared allow-list

- **Choice**: `just drv-diff <parent> <tip> openspec/changes/type-the-fleet-host-registry/drv-delta.txt`, the recipe establish-refactor-oracle commits. It dumps the drvPaths of every NixOS and darwin toplevel, every home `activationPackage`, `checks.{x86_64-linux,aarch64-darwin}` and `vmTests.{x86_64-linux,aarch64-linux}` at both revisions and fails on any difference the allow-list does not declare, and on any declared `changed`/`added` that does not happen. `drv-delta.txt` declares exactly:
  - `nixos.cinnabar changed` (D8);
  - `checks.x86_64-linux.nixos-cinnabar changed`, the machine check that returns cinnabar's toplevel. No other check or runtime test embeds that toplevel: the others read single option values of it, which do not include the controller's script;
  - `checks.x86_64-linux.eval-fleet-topology changed`. Its test imports `lib/fleet-topology.nix` by store path (`fleet-topology.test.nix:26`), so editing `membersOf` (D7) changes the check's source even though its results stay equal;
  - `checks.x86_64-linux.fleet-topology-fresh changed` (D12). It embeds the committed `packages/docs/diagrams/topology/` directory, and stibnite's tag rename changes `fleet.json`;
  - `checks.x86_64-linux.eval-inventory-members added` (D7).

  Checks that embed the whole flake source change on every commit and are covered by the oracle's own base allow-list, not by this file. Each of the first three commits runs the recipe with no change-specific allow-list and must pass; the fourth and the merged head run it with `drv-delta.txt`.
- **Rationale**: `just eval-identity` compares stock and iets at one revision (`justfile:435-450`) and cannot show that a cross-revision refactor is neutral. The allow-list takes exact attribute paths, so every affected attribute is named and reviewed with the change.

### D11: stop-reading-other-hosts-configs' NixOS key-host list is derived from class

- **Choice**: this change lands after stop-reading-other-hosts-configs, which adds `modules/lib/host-keys.nix` with the literal `nixosKeyHosts = [ "cinnabar" "electrum" "galena" "scheelite" "magnetite" "pyrite" ]`. This change replaces the literal with `attrNames (filterAttrs (_: h: h.class == "nixos") config.flake.fleet.hosts)`.
- **Rationale**: that list is the set of NixOS hosts, a fact the record now holds; leaving it literal would keep one more hand-kept host table, and a new NixOS host would be missing from `known_hosts` without any check failing. The list feeds `genAttrs`, so its order is irrelevant and every `hostKeys` value, and every drvPath, stays the same. Boundary: source-only.
- **Alternatives considered**: leave the literal and assert it equals the NixOS hosts. That keeps the restatement this change removes.

### D12: stibnite's inventory tag `controller` is renamed `deployer-workstation`

- **Choice**: in `modules/clan/inventory/machines.nix`, stibnite's tag `controller` becomes `deployer-workstation`. cinnabar keeps `controller`, which names its ZeroTier controller role. The committed fleet map is regenerated with `just topology-generate`; only stibnite's `tags` in `packages/docs/diagrams/topology/fleet.json` changes. The operator decided this on 2026-11-26.
- **Rationale**: the two tags shared a name with two meanings: the ZeroTier controller on cinnabar, the operator's deployment workstation on stibnite. A search on 2026-11-26 found no clan role that reads `tags.controller` and no repository script that passes `--tags controller`; the only readers are `lib/topology-facts.nix`, which copies tags into the fleet map, and the operator's shell. After the rename, `clan machines update --tags controller` selects only cinnabar, which is what the tag's name says. Boundary: source-only. No host configuration reads inventory tags, so no toplevel changes; the drvPath diff shows it if one does.
- **Alternatives considered**: keep both tags. That keeps a tag that selects a darwin workstation together with a NixOS server under one name, so a tag-scoped deploy reaches a host it does not name.

## Risks / Trade-offs

- [Risk] A reader serialises a whole `flake.lib.hosts` record, so new fields (`system`, `checked`, `stateVersion`, `enrolled`, `cloud`, `memory`) change its output → Mitigation: a search on 2026-11-26 found only field-wise reads. The drvPath diff catches any reader that does serialise.
- [Risk] `enrolled` via `pathExists` on a source path reads the working tree. In a jj working copy, a sops directory can be present before it is committed → Mitigation: evaluation from a flake reads the committed tree (`self`). The field is evaluated only from `self`, never from a relative path.
- [Risk] The `throw` paths change wording, and a check that matches a message string breaks → Mitigation: `nix-eval-jobs-iets`'s `unclassifiedIets` mutant (`checks/nix-eval-jobs-iets.nix:183-184`) asserts only that blackphos yields a non-empty problem list, never a message. Its run is part of task group 5.
- [Risk] An archive-time conflict on `world-assumptions`' grounded-vocabulary requirement, which this and several active changes each modify in full → Mitigation: the delta copies the corpus requirement as of 2026-11-26 and only appends rows. At archive, rows other changes added since are merged by hand before syncing.
- [Trade-off] A `fleet` flake output appears, as `users` and `userAliases` did. `nix flake check` lists it as unknown; nothing fails on it. Accepted.
- [Trade-off] Until the later change switches the readers, `stateVersion` is written twice: in the record and in the host modules. Accepted, because it lands in a known follow-on change and the drvPath diff there proves they agree.

## Migration Plan

1. Land establish-refactor-oracle, then stop-reading-other-hosts-configs; this change's parent is the latter's tip. After rebasing onto it, re-run `just drv-diff` from the new parent.
2. Land this change as one pull request in four commits, each evaluating alone, with `just drv-diff` run after each:
   - the option and alias;
   - derived system, class, `clan.machines` and the NixOS key-host list;
   - lifecycle, cloud and memory;
   - the resolver, `allowedIps` and stibnite's tag rename.

   The first three must show no drvPath difference outside the oracle's base allow-list; the fourth shows exactly the entries of `drv-delta.txt`.
3. After merge, deploy cinnabar (`clan machines update cinnabar`). Then read every post on the fleet alert and failure topics since the deploy began, and confirm from cinnabar that the controller's allowed member list holds the six addresses. No other host's configuration changes, so no other deploy is needed. A host deployed later for unrelated reasons picks up nothing new.
4. Rollback: revert the pull request and redeploy cinnabar. No state is migrated.

## Resolved Questions

1. **The `controller` tag on stibnite.** Decided by the operator on 2026-11-26: rename it to `deployer-workstation` (D12), so it stops sharing its name with cinnabar's ZeroTier controller tag. `clan machines update --tags controller` then selects only cinnabar.
2. **cinnabar's drvPath change.** Decided by the operator on 2026-11-26: accept the reorder of the ZeroTier allowed list (D8) and redeploy cinnabar once. ZeroTier is transitional (migrate-mesh-to-tincr) and the list's order has no meaning to the controller, so a hand-ordered list kept only to stay neutral would restate the set for no gain. `drv-delta.txt` keeps `nixos.cinnabar changed`.

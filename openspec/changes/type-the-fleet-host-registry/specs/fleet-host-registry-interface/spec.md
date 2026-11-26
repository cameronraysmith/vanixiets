## ADDED Requirements

### Requirement: flake.fleet.hosts holds one typed entry per fleet member

The flake SHALL declare `options.flake.fleet.hosts` in `modules/lib/hosts.nix` as `attrsOf (submodule …)`, with one entry for each of the twelve fleet members.
Each entry SHALL carry the declared fields `system`, `endpoints`, `deployUser`, `services`, `zerotier`, `primaryUser`, `memory`, `nixClassic`, `checked` and `stateVersion`, with the types and default given in this requirement's scenarios.

#### Scenario: The option's entries are listed

- **WHEN** `nix eval .#fleet.hosts --apply builtins.attrNames` runs
- **THEN** it lists argentum, blackphos, cinnabar, electrum, galena, magnetite, pixel11, pixel7, pyrite, rosegold, scheelite and stibnite

#### Scenario: The declared fields have their types

- **WHEN** the option's submodule is read
- **THEN** `system` is `nullOr (enum [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ])`, `endpoints` and `services` are `listOf str`, `deployUser` is `nullOr str`, `zerotier` is `{ address : str; memberId : str; }`, `primaryUser` is `nullOr (enum (attrNames flake.users))`, `memory` is `nullOr (either ints.positive (enum [ "unknown" ]))`, `nixClassic` is `bool`, `checked` is `bool` with default `true`, and `stateVersion` is `nullOr (either ints.positive str)`

### Requirement: The submodule sets the read-only fields of each entry

Each entry SHALL carry the read-only fields `class`, `fqdn`, `address`, `targetHost`, `memoryGiB`, `enrolled` and `cloud`, set by the submodule from the entry's name and declared fields and defined nowhere else.

#### Scenario: class follows system

- **WHEN** an entry's `class` is read
- **THEN** it is `"android"` when `system` is null, `"darwin"` when `system` ends in `-darwin`, and `"nixos"` otherwise

#### Scenario: targetHost follows deployUser

- **WHEN** an entry's `targetHost` is read
- **THEN** it is `"<deployUser>@<name>.zt"`, or null when `deployUser` is null

#### Scenario: enrolled reads the committed flake source

- **WHEN** an entry's `enrolled` is read
- **THEN** it is `builtins.pathExists (self + "/sops/machines/<name>")`, never a path relative to the working tree

#### Scenario: cloud is read from the cloud machine table

- **WHEN** an entry's `cloud` is read
- **THEN** it is null for a host absent from `flake.lib.cloudMachines`, and otherwise `{ provider; type; enabled; }`, with `type` taken from `serverType` on Hetzner and `machineType` on GCP

### Requirement: A field that contradicts the host's class fails when read

Reading `memoryGiB`, `nixClassic` or `stateVersion` SHALL fail with a `throw` naming the host when the value contradicts the host's class.

#### Scenario: The class constraints

- **WHEN** these fields are read for each class
- **THEN** memory and state version are null exactly for `android`, the state version is an integer on `darwin` and a string on `nixos`, and `nixClassic = true` requires a non-null `primaryUser`; any other combination throws

#### Scenario: A mistyped field is rejected at its read

- **WHEN** a throwaway tree gives one host `memory = 0` and evaluates that host's `memoryGiB`
- **THEN** evaluation fails with a message naming the option path, and `builtins.tryEval` of the same read returns `success = false`

### Requirement: flake.lib.hosts is a read-only alias of flake.fleet.hosts

`flake.lib.hosts` SHALL equal `config.flake.fleet.hosts` and SHALL be written nowhere else. Every field it exposed before this requirement was met SHALL keep the same name and value for every member.

#### Scenario: The alias carries the prior fields

- **WHEN** `class`, `endpoints`, `deployUser`, `services`, `zerotier`, `fqdn`, `address`, `primaryUser`, `memoryGiB`, `nixClassic` and `targetHost` are read for every member through `flake.lib.hosts` at the parent revision and at this change's head
- **THEN** the two JSON dumps are equal

### Requirement: Per-host values are derived from flake.fleet.hosts

`flake.lib.machineSystems`, each inventory `machineClass`, each NixOS inventory `deploy.targetHost`, each `flake.clan.machines.<name>`, each `flake.lib.observabilityHosts.<name>.platform` and the NixOS names of `flake.lib.hostKeys` SHALL be computed from `flake.fleet.hosts` and SHALL NOT be written as literals.

#### Scenario: machineSystems holds the hosts with a system

- **WHEN** `flake.lib.machineSystems` is read
- **THEN** it maps every entry whose `system` is non-null to that `system`, and its defining expression reads only `flake.fleet.hosts`, never a `nixosConfigurations`, `darwinConfigurations` or `clan.machines` configuration value

#### Scenario: clan.machines carries the platform

- **WHEN** `flake.clan.machines.<name>` is read for an entry with a non-null `system`
- **THEN** it imports `flake.modules.<class>."machines/<class>/<name>"` and sets `nixpkgs.hostPlatform` to the entry's `system`, and `rg -n 'nixpkgs.hostPlatform =' modules/machines modules/darwin/laptop.nix` finds nothing

#### Scenario: The NixOS key-host list is derived

- **WHEN** the NixOS names of `flake.lib.hostKeys` are read before and after this change
- **THEN** they are equal, they are the entries whose `class` is `nixos`, and `rg -n 'nixosKeyHosts = \[' modules` finds nothing

### Requirement: Host kind is read from class

A reader that needs to know whether a host is darwin SHALL read its `class`; no module outside `modules/lib/hosts.nix` SHALL test a host's system with `hasSuffix "-darwin"`. No darwin entry SHALL have an inventory `deploy.targetHost`.

#### Scenario: No host suffix test remains

- **WHEN** `rg -n 'hasSuffix "-darwin"' modules` runs
- **THEN** it finds only `modules/lib/hosts.nix` and `modules/containers/default.nix`, the latter testing the perSystem system, not a host

#### Scenario: Darwin keeps no inventory deploy target

- **WHEN** the network-target obligation's darwin mutant (a darwin inventory entry given `deploy.targetHost`) runs
- **THEN** it is still reported

### Requirement: Machine checks are selected by checked

`checks.<system>` SHALL select machine checks by `flake.fleet.hosts.<name>.checked`, with no `deferred` list, and no field SHALL read `cloud.enabled` to decide `checked`.

#### Scenario: The machine checks are unchanged

- **WHEN** `checks.x86_64-linux` and `checks.aarch64-darwin` attribute names are listed before and after group 4
- **THEN** they are equal, with `nixos-electrum` and `nixos-galena` present and no `nixos-scheelite`

### Requirement: tincr peers are selected by class and enrolment

The tincr peer set SHALL select the entries with `class != "android" && enrolled`, with no host named literally.

#### Scenario: tincr peers are unchanged

- **WHEN** the tincr instance's peer names are read before and after
- **THEN** they are equal and exclude blackphos and both phones

### Requirement: The deployer reads cloud state from the record

`flake.lib.fleetDeployer` SHALL read whether a cloud host is up from `flake.fleet.hosts.<name>.cloud.enabled`, treating a null `cloud` as up. `flake.lib.cloudMachines` SHALL remain the only writer of cloud provider, type and `enabled`.

#### Scenario: Deployer targets are unchanged

- **WHEN** `flake.lib.fleetDeployer.targets` and `problems` are read before and after
- **THEN** they are equal

### Requirement: Cloud memory is read from a machine-type table

`flake.lib.cloudMachineMemoryGiB` SHALL map each cloud machine type in `flake.lib.cloudMachines` to its memory in GiB. A cloud entry's `memoryGiB` SHALL be that table at its `cloud.type`, and a type with no entry SHALL `throw` naming the type. A non-cloud entry's `memoryGiB` SHALL be its declared `memory`.

#### Scenario: Memory values are unchanged

- **WHEN** `memoryGiB` is read for every member before and after
- **THEN** every value is equal, blackphos's being `"unknown"` and the phones' null

#### Scenario: The unclassified-host mutant is still reported

- **WHEN** `checks.x86_64-linux.nix-eval-jobs-iets` is built
- **THEN** it succeeds, `flake.lib.nixEvalJobsBoundProblems` still reads each host's `memoryGiB` under `builtins.tryEval`, and its `unclassifiedIets` case reports blackphos

### Requirement: flake.lib.inventoryMembers resolves role membership from the declared inventory

`flake.lib.inventoryMembers instance role` SHALL return the sorted, unique names that are keys of `roles.<role>.machines` or inventory machines carrying any key of `roles.<role>.tags`, with `all` matching every inventory machine. It SHALL read only `flake.clan.inventory`, never a machine configuration or `clanInternals`.

#### Scenario: The resolver honours all

- **WHEN** the resolver's evaluation test `checks.x86_64-linux.eval-inventory-members` runs on a fixture role whose tags are `{ all = { }; }`
- **THEN** it returns every fixture machine

### Requirement: Every role-membership reader uses the resolver

`lib/fleet-topology.nix`, `checks/zerotier-mss-clamp.nix`, `checks/zerotierone-controller.nix` and `apps/omnigent-worker-login.nix` SHALL take role membership from the resolver, fleet-topology through `inventoryMembersIn`, which accepts its fixture's machines.

#### Scenario: The resolver changes no role membership in the committed topology

- **WHEN** `checks.x86_64-linux.fleet-topology-fresh` and `eval-fleet-topology` are built after the readers switch to the resolver
- **THEN** both succeed, and the committed topology files differ from the parent revision only in stibnite's `tags` in `fleet.json`, which the tag rename changes

### Requirement: An inventory tag has one meaning across hosts

The inventory tag `controller` SHALL be carried only by cinnabar, the ZeroTier controller. stibnite, the operator's deployment workstation, SHALL carry `deployer-workstation` in its place.

#### Scenario: A tag-scoped deploy by controller reaches only the ZeroTier controller

- **WHEN** the inventory machines whose `tags` contain `controller` are listed by evaluation
- **THEN** the list is exactly `[ "cinnabar" ]`, and stibnite's `tags` contain `deployer-workstation`, so `clan machines update --tags controller` selects only cinnabar

### Requirement: The ZeroTier controller's allowedIps is derived from class

The cinnabar controller's `allowedIps` SHALL be the `zerotier.address` of every `flake.fleet.hosts` entry whose class is `darwin` or `android`, in attribute-name order.

#### Scenario: The admitted addresses are the same six

- **WHEN** the setting is read before and after
- **THEN** the two lists hold the same six addresses, and differ only in order

#### Scenario: Only the declared derivations change

- **WHEN** `just drv-diff <parent> <tip> openspec/changes/type-the-fleet-host-registry/drv-delta.txt` runs
- **THEN** it exits 0: `nixos.cinnabar`, `checks.x86_64-linux.nixos-cinnabar`, `checks.x86_64-linux.eval-fleet-topology` and `checks.x86_64-linux.fleet-topology-fresh` changed, `checks.x86_64-linux.eval-inventory-members` was added, and no other dumped attribute differs outside the oracle's base allow-list

### Requirement: The machine-check asserts are kept

Every assert in `modules/checks/machines.nix` SHALL be kept, including the `machineSystems`-names and `clan.machines`-names asserts against the inventory, whose literal entries are written independently of `flake.fleet.hosts`. The observability `platform`-vs-`machineClass` assert SHALL be removed, because both of its sides read the record's `class`.

#### Scenario: A record without an inventory entry is caught

- **WHEN** a throwaway tree adds a NixOS record with no inventory entry and evaluates `checks.x86_64-linux`
- **THEN** evaluation fails with the `machineSystems`-names assert's message

#### Scenario: The directory assert still catches a missing directory

- **WHEN** a throwaway tree adds a NixOS record and its inventory entry with no `modules/machines/nixos/<name>/` directory
- **THEN** evaluation of `checks.x86_64-linux` fails with the directory assert's message

### Requirement: The golden pin stays a literal

The flake-shape golden pin `checks.x86_64-linux.structure-fleet` SHALL stay a literal map from host to inventory `machineClass`, never derived from `flake.fleet.hosts`.

#### Scenario: The golden pin still catches a flipped class

- **WHEN** a throwaway tree changes one host's `system` from `x86_64-linux` to `aarch64-darwin` and `structure-fleet` is built
- **THEN** the check fails, naming the host

### Requirement: Trust boundary of the host registry interface

The option types and evaluation-time asserts of this interface SHALL be read as checking only what is written in the repository. The drvPath diff SHALL be read as showing that derived values equal the hand-written ones only for the attributes it dumps.

#### Scenario: What the interface does not show

- **WHEN** the interface's guarantees are relied on
- **THEN** they do not show that a machine has the system, memory or state version recorded for it, that a provider's machine type still has the memory the table gives it (world assumption A303), that an enrolled host holds the key whose public half is committed, or that the ZeroTier controller admits the addresses once deployed, which only a read on cinnabar shows

#### Scenario: A registry fact is wrong about the machine

- **WHEN** a host's recorded memory differs from what the machine reports
- **THEN** no check of this interface fails, and the difference is found only by reading the machine, as A303's monitor states

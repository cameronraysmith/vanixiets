## ADDED Requirements

### Requirement: A383 — A definition made through flake.modules keeps the option name in its file string

It is true of the nixpkgs module system and flake-parts at the locked revisions, independent of what this fleet builds, that a module assigned into `flake.modules.<class>.<name>` reaches a configuration with the file `"<file>, via option flake.modules.<class>.<name>"`, which `definitionsWithLocations` reports for its definitions.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Read at the source at apply

- **WHEN** nixpkgs `lib/types.nix` (the deferred-module merge's `setDefaultModuleLocation "${def.file}, via option ${showOption loc}"`, line 1996 in store copy `xl9r82h0f4mvaqiv566fd8v37ma5xy5h-source`) and `lib/modules.nix:1260,1327` (`definitionsWithLocations = res.defsFinal`) are read at the locked revision
- **THEN** the merge prefixes each definition's file with `, via option` and the option path, `definitionsWithLocations` reports it for each final definition, and `modules/checks/structure/aspect-parts.nix` reads the same string (A375)

#### Scenario: The file string changes form

- **WHEN** a nixpkgs update changes the location string or stops propagating it to definitions inside the module
- **THEN** this assumption is void; the `repository-shape-interface` requirement `A named module arriving by an unknown route kind fails the machine check` and the `repository-shape` requirement `Each configuration's composition can be stated on request and its routes are known` lose their discharge until the check's parsing is re-read

### Requirement: A384 — An upstream list option can be re-declared with apply alone

It is true of the nixpkgs module system at the locked revision, independent of what this fleet builds, that a second declaration of an option merges with the first when only one of them sets `apply`, and that `environment.systemPackages` (NixOS, nix-darwin) and `home.packages` (home-manager) set no `apply` upstream.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Read at the source at apply

- **WHEN** nixpkgs `lib/modules.nix:1157-1166`, NixOS `nixos/modules/config/system-path.nix:74-87`, nix-darwin `modules/config/system-path.nix:39-52` and home-manager `modules/home-environment.nix:402-406` are read at the locked revisions (read 2026-11-27 from the store and ghq copies, revisions not confirmed against the lock)
- **THEN** the merge throws only when both declarations set `default`, `example`, `description` or `apply`, and none of the three upstream declarations sets `apply`

#### Scenario: Upstream adds an apply

- **WHEN** an update of nixpkgs, nix-darwin or home-manager gives one of the three options an `apply`, or makes the merge reject a second declaration
- **THEN** this assumption is void; evaluation fails at the fleet's sort module, and the `repository-shape` requirement `Restructuring delivers nothing but declared priority and order` loses its discharge for every later step until a new mechanism is chosen, since list order would again follow import depth (A344)

### Requirement: A385 — A clan service's per-machine module reaches every machine of any of its instances

It is true of clan-core at the locked revision, independent of what this fleet builds, that a clan service's `perMachine` module is evaluated once for every machine that holds any role in any instance of the service, and that a role's `perInstance` module reaches only the machines of that role.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: clan-core `lib/inventory/distributed-service/service-module.nix:714-745` ("Per-machine configuration of the service … once, if any service-instance is used") and `:830-840` ("'perMachine' maps over all machines of a service"), read from the ghq copy, revision not confirmed against the lock. Observed in this fleet: `modules/clan/services/omnigent/flake-module.nix:20-23` imports `nixos.omnigent` into magnetite, whose host module does not import it.

#### Scenario: Read at the source at apply

- **WHEN** the service module's `perMachine` and `perInstance` are read at the locked clan-core revision
- **THEN** `perMachine` maps over every machine of the service and `perInstance` over a role's machines

#### Scenario: clan changes the scope of perMachine

- **WHEN** a clan-core update evaluates `perMachine` for a different set of machines
- **THEN** this assumption is void; the clan-service route kind is misattributed for the affected machines, and the `repository-shape` requirement `Each configuration's composition can be stated on request and its routes are known` loses its discharge for them until the judge is re-read

### Requirement: A386 — An evaluated configuration records its import tree

It is true of the nixpkgs module system at the locked revision, independent of what this fleet builds, that an evaluation's result carries `graph`, one node per collected module with `key`, `file`, `imports` and `disabled`, and that NixOS, nix-darwin and standalone home-manager configurations keep it.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

#### Scenario: Read at the source at apply

- **WHEN** nixpkgs `lib/modules.nix:410` and `:616-645` (store copy `xl9r82h0f4mvaqiv566fd8v37ma5xy5h-source`), `nixos/lib/eval-config.nix`'s `withExtraAttrs`, nix-darwin's `eval-config.nix` and home-manager's `modules/default.nix` are read at the locked revisions
- **THEN** the evaluation result carries `graph` with those four fields per node, and each of the three wrappers returns the result merged with `//`, not a new attribute set

#### Scenario: graph is removed or reshaped

- **WHEN** an update removes `graph`, changes its node fields, or a wrapper stops returning it
- **THEN** this assumption is void; the `repository-shape-interface` requirements `A command prints any configuration's composition from its import tree` and `A named module arriving by an unknown route kind fails the machine check` lose their discharge for the affected class until re-read

### Requirement: Designations for the shape of the fleet description

The corpus SHALL provide one designation record for each term the `repository-shape` requirements introduce, recording the term, the phenomenon it denotes and whether that phenomenon is world-only, shared or machine-only, in addition to the records of the requirement `Grounded vocabulary for behavioral requirements`.

#### Scenario: The added designation records are read

- **WHEN** the designation records this requirement adds are read
- **THEN** they are the rows of this table

| Term | Sense | Phenomenon it denotes | Status |
|---|---|---|---|
| part | fleet description | one named unit of the fleet description that a host's configuration or a home configuration takes as a whole | shared |
| guarded part | — | a part that changes a configuration only when a host fact or a setting holds | shared |
| route | — | the way a part reaches a configuration: the host's own list, a shared list, another part, a service's assignment of hosts, or a host fact | shared |
| composition | host | the parts a host's configuration or a home configuration takes, each with its route | shared |
| composition statement | — | the statement of one composition that the documented command prints on request | shared |
| host list | — | a place in the fleet description, outside the host registry and the host's own directory, where a host's name or one of its facts is written | shared |
| host directory | — | the part of the fleet description kept for one host: its configuration module and its disk layout | shared |
| entry-point document | — | the one document that states the fleet description's kinds and its placement rules | world-only |
| placement rule | — | a documented statement of where one kind of addition to the fleet description is written and under what name | world-only |
| fleet-wide setting | — | a setting every host of a host kind takes; distinct from `policy` (fleet), the organisation's decision about acceptable mutations | shared |
| hand-entered secret | — | a secret a person types once rather than the fleet generating it | world-only |
| Mac application | — | a program installed on darwin hosts for people to use | world-only |
| installed packages | — | the packages a configuration places on a host's or home's search path | shared |
| review binding | — | one key binding of the pull-request dashboard that starts a review action | shared |
| reader measure | — | the committed tasks, keys, protocol and grading by which fresh agents' answers about the repository are scored | world-only |
| lookup task | — | a reader-measure task asking where something is or what decides it | world-only |
| placement task | — | a reader-measure task asking where a new addition goes | world-only |
| enumeration task | — | a reader-measure task asking for everything of a kind that a host or the fleet has | world-only |
| impact task | — | a reader-measure task asking what changes when one file changes | world-only |
| priority step | — | the restructuring step that fixes, by explicit priority, which package provides a file wherever two equal-priority packages provide differing files | shared |
| order step | — | the restructuring step that makes the order of installed packages and review bindings irrelevant to every configuration | shared |

#### Scenario: A term resolves to two phenomena

- **WHEN** a term in this table is found to denote two phenomena in the repository's vocabulary
- **THEN** it is split into two rows with senses, as the requirement `Grounded vocabulary for behavioral requirements` requires

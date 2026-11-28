## ADDED Requirements

### Requirement: Each host list is derived from the registry or checked against it

Inventory `tags` and `description` SHALL be fields of `flake.fleet.hosts.<host>`; `flake.clan.inventory.machines`, `machineAnchors` in `checks/sops-correspondence.nix` and, where their values equal today's, the ssh `logins` SHALL be computed from the registry; the assert comparing `machineSystems` names with the inventory's SHALL be removed.

Trust boundary: where host facts are written; not that a fact is true of the machine.

#### Scenario: The derived lists are evaluated

- **WHEN** the inventory machines with their tags and descriptions, `machineAnchors` and the ssh `logins` are evaluated at the step's commit and at its parent
- **THEN** each value is equal, and none of their source files names a host literally outside comments

#### Scenario: A list left by design is read

- **WHEN** `ztRecords` and the justfile's `check-uncached-machine` recipe are read
- **THEN** `ztRecords` is unchanged and named in the onboarding guide as the one list a new host joins by hand, and the recipe reads the host's class from `lib.hosts` with no host list

### Requirement: Hand-written host lists are checked against the registry, with controls

Fleet checks SHALL fail, naming the host, when `lib/cloud-machines.nix`'s keys differ from the registry's cloud hosts or `observabilityHostsFor`'s keys from the registry's hosts; `structure-fleet` SHALL hold a phantom entry whose `expected` value is what a correct comparison gives it. The machine `testSizes` entries and `.sops.yaml` stay judged as today.

Trust boundary: agreement of names; not the rows' contents.

#### Scenario: A cloud row names no host

- **WHEN** a throwaway tree adds a row to `lib/cloud-machines.nix` for a name the registry lacks
- **THEN** the check fails naming that name

#### Scenario: The fleet pin's control is read

- **WHEN** the `structure-fleet` comparison is evaluated
- **THEN** its phantom entry's actual value equals its expected value, and a mutant that breaks the comparison makes them differ

### Requirement: The host-onboarding guide lists every generated step with the check that enforces it

One section of the host-onboarding guide SHALL list, in order, the steps a new host needs that no registry field can derive: machine key and vars, bridge files re-encrypted for the new recipient, the `sops/secrets/<host>-age.key/groups/fleet-deployers` link for an enabled deploy target, and regenerated topology files; each SHALL name the check that fails until it is done.

Trust boundary: the list and its checks; not the key material itself.

#### Scenario: A new enabled host lacks its deployer group link

- **WHEN** a throwaway tree adds an enabled host with key and vars but without its `fleet-deployers` link
- **THEN** `sops-correspondence` fails naming the host, and the guide's section names that step and that check

### Requirement: A new Hetzner host's boot loader follows its server type

`nixos.hetzner-cloud` SHALL set UEFI with systemd-boot for `ccx*` and `cax*` server types and leave BIOS with GRUB for `cx*`; `flake.fleet.hosts.<host>.cloud.type` SHALL fail evaluation naming the host when its row has no type; a fleet obligation SHALL fail when a Hetzner host's boot loader differs from its type's.

Trust boundary: the configured loader; not the firmware of the provisioned server.

#### Scenario: A host forces the other loader

- **WHEN** a throwaway tree makes electrum force GRUB on
- **THEN** the machine check fails naming electrum and its server type

#### Scenario: electrum's hand-written lines are removed

- **WHEN** electrum's three boot-loader lines are removed after the mapping lands
- **THEN** electrum's toplevel drvPath equals the parent's, or the lines stay

### Requirement: A command prints any configuration's composition from its import tree

`just composition <name>` SHALL print, for a NixOS or darwin host or a standalone home, each named module in its evaluated `graph` with its route kind and parent file, and for a standalone home the systems it is built for. This relies on A375, A383, A385 and A386.

Trust boundary: what the fleet description composes at a commit; integrated homes are printed as the standalone home plus the attachment's extra imports.

#### Scenario: magnetite's composition is printed

- **WHEN** `just composition magnetite` runs at a commit
- **THEN** it prints every named module of the graded enumeration key for magnetite, each with one route kind

#### Scenario: A home's systems are printed

- **WHEN** `just composition crs58` runs
- **THEN** it prints the systems for which `homeConfigurations` holds a `crs58` entry, equal to those `structure-home-configurations` pins

### Requirement: A named module arriving by an unknown route kind fails the machine check

A fleet obligation `composition-routes` SHALL fail, naming the host, the module and its parent's file, when a named module in the host configuration's `graph` has a route kind outside the entry point's list; the machine checks SHALL pass each configuration's `graph` to judges that ask for it. This relies on A383 and A386.

Trust boundary: route kinds of checked hosts; not hosts with `checked = false`, nor integrated homes.

#### Scenario: A module reaches a host under an unknown parent

- **WHEN** the judge's fixture check gives it a graph with a named module under an unclassified parent
- **THEN** the judge returns one failure naming the module and the parent's file

#### Scenario: Its cost is measured first

- **WHEN** the obligation is registered
- **THEN** a `just eval-cost` run of one host's machine check with and without it is recorded beside its registration

### Requirement: Equal-priority collisions in the system path are settled by priority before order is sorted

For every enabled host, each path that two equal-priority members of the system path provide with differing contents SHALL have today's winner fixed by `lib.hiPrio` or `lib.lowPrio`, in a step before the sort. This relies on A376.

Trust boundary: the measured collisions; not packages added later.

#### Scenario: The collisions are listed

- **WHEN** the system path of each enabled host is built at the step's parent and its members' files compared
- **THEN** every path provided by two equal-priority members with differing contents is listed, and each has a priority mark at the step's commit

### Requirement: Package list order is irrelevant in every host and home

`environment.systemPackages` (NixOS, darwin), `home.packages` and nix-darwin's `homebrew.taps`, `homebrew.brews` and `homebrew.casks` SHALL each be re-declared once with only `apply = lib.sort`; the gh-dash `keybindings.prs` SHALL be attributes keyed by key; the nixpkgs overlays SHALL apply in one named list. This relies on A376 and A384.

Trust boundary: list order in evaluation; profile contents by the built comparison only.

#### Scenario: The sorted lists' keys are read

- **WHEN** the re-declarations of `environment.systemPackages`, `home.packages`, `homebrew.taps`, `homebrew.brews` and `homebrew.casks` are read
- **THEN** each holds only `apply = lib.sort`, the package lists comparing the name alone (`lib.getName` of a derivation, else its string), so same-named entries keep their definition order, and the Homebrew lists comparing `name`

#### Scenario: The home sort reaches every home

- **WHEN** the integrated homes' `home-manager.sharedModules` and `flake.lib.mkHome` are read
- **THEN** both include the module that sorts `home.packages`

#### Scenario: A darwin part moves in its list

- **WHEN** `base-homebrew`, or a module adding a cask, takes another position in the darwin base list or the import tree
- **THEN** every darwin toplevel's drvPath is unchanged, the `Brewfile` included

#### Scenario: The sort changes a file's content

- **WHEN** a system path built at the order step's commit resolves a path to a file whose content differs from its parent's
- **THEN** the step is not accepted; identical content from a different package is not a difference

### Requirement: Ordered-on-purpose lists take their order from one table

Every darwin `postActivation` and launchd activation snippet written in the fleet description SHALL take its `lib.mkOrder` priority from `activationOrder` in `modules/system/deploy-record.nix`, and `modules/README.md` SHALL name that table and the overlay list as the places order is written.

Trust boundary: the priorities written; not the upstream snippets' own priorities.

#### Scenario: A snippet has no slot

- **WHEN** the fleet description's darwin activation snippets are read
- **THEN** each uses a priority from `activationOrder`, including stibnite's k8s certificate snippet

### Requirement: One check placement rule is documented

`modules/README.md`, `modules/checks/README.md` and the checks skill SHALL state one rule: a value fact about one configuration is an assertion or fleet obligation; a fact that must hold on `checked = false` hosts, spans configurations or concerns flake structure is a `modules/checks/` check with `testSizes` and a negative control; runtime behaviour is a runtime test.

Trust boundary: the documents agree; not that every existing check follows the rule.

#### Scenario: The documents are compared

- **WHEN** the three documents' placement rules for checks are read side by side
- **THEN** they state the same three rungs and the same exception, in the same order

### Requirement: One shape for a hand-entered secret is documented

The header of `modules/system/secrets.nix` and `modules/README.md` SHALL name one shape for a new hand-entered secret: a hidden prompt, `files.<f>.deploy = false`, and a script rendering the file the service reads; they SHALL name the script that exits 1 as superseded.

Trust boundary: the documented shape; not the generators already committed.

#### Scenario: A reader looks for how to declare a hand-entered token

- **WHEN** `modules/system/secrets.nix`'s header and the README's placement table are read
- **THEN** both name the same shape and cite an existing module that uses it

### Requirement: The reader measure is committed and its targets are per-run passes

`docs/notes/development/reader-measure/` SHALL hold the lookup questions and hard tasks with keys, the protocol with its tree and commands arms, and a grading script reporting each target as a count of runs meeting it, never as a rate.

Trust boundary: three runs per task and one model; not every reader.

#### Scenario: The re-measure is graded

- **WHEN** the grading script reads the re-measure's transcripts
- **THEN** it reports, per target, how many runs met it, beside the baseline, and the sample size

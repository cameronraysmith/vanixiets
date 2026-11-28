# secret-consumption-seam-interface Specification

## Purpose

This capability (stratum: `interface`) states the `vanixiets.secrets.<name>` option on the NixOS and nix-darwin classes, with its writable fields, its read-only file fields and `resolved`; the secrets module's translation of each entry into `clan.core.vars.generators.<name>`, made only when clan-core is present; the read-only fields taken from the backend, `placeholder` being `null` where sops-nix defines none; provided entries for the generators clan-core's own services declare; the home view the bridge modules set for every home-manager user; where obligations read secrets, by name through the option or through `flake.lib.secretsBackend.generatorsOf`; the confinement check and its final list; and the per-step drvPath comparison.
Trust boundary: the confinement check reads the source text of `.nix` files under `modules/`; it does not see `inherit (config.clan.core) vars;`, a quoted or string-built attribute path, a read through `generatorsOf`, or a file outside `modules/`. The drvPath comparison shows that evaluated outputs are unchanged, not that clan generates or installs the same files at runtime; clan still generates, encrypts and deploys every secret, and nothing here checks clan's behaviour (A361, A363, A364).

## Requirements

### Requirement: vanixiets.secrets is declared on both classes

`flake.modules.nixos.secrets` and `flake.modules.darwin.secrets`, defined in `modules/system/secrets.nix`, SHALL declare `options.vanixiets.secrets`, an attribute set of submodules keyed by generator name with the fields below, and each SHALL carry one `key` and be imported by `nixos.base` and `darwin.base`.

**Self-import**: a module that writes or reads `vanixiets.secrets` imports its class's secrets module itself when some configuration evaluates it without that class's base aspect: every NixOS and darwin module of a clan service, and every feature module that a runtime test or check fixture imports without the base aspect.

**Trust boundary**: the option fixes the shape of a declaration. It does not check that a declared recipe produces the files it names.

**Writable fields**: `share`, `dependencies`, `validation`, `runtimeInputs`, `script`, `prompts.<p>.{description,type,persist}` and `prompts.<p>.display.{group,label,required,helperText}` on the generator; `files.<f>.{secret,deploy,owner,group,mode,neededFor,restartUnits}` on each file, each defaulting to `null` (`[ ]` for a list); and `provided`, a boolean defaulting to false.

**Read-only fields**: `files.<f>.{path,value,exists,placeholder}` on each file, and `resolved` on the entry: the generator as the backend evaluated it, in the writable fields' names, with the backend's defaults for every field no module set.

**Discharged by**: `nix eval` of `vanixiets.secrets` on every NixOS and darwin host, and of the option's declared fields.

#### Scenario: Every host has the option

- **WHEN** `nixosConfigurations.<h>.config.vanixiets.secrets` and `darwinConfigurations.<h>.config.vanixiets.secrets` are evaluated for every fleet host after the first delivery step
- **THEN** each evaluates, to `{ }` before any feature moves

#### Scenario: A clan-free fixture imports a secret-owning module

- **WHEN** a fixture that does not import clan-core evaluates a module that writes `vanixiets.secrets`
- **THEN** it evaluates, because that module imports the secrets module

### Requirement: The secrets module writes only defined fields, and only when clan is present

When `options ? clan.core.vars` holds, the secrets module SHALL define, for each entry of `vanixiets.secrets` whose `provided` is false, `clan.core.vars.generators.<name>` holding exactly the fields that entry defines, with no `null` field and no empty list. When clan-core is not imported, it SHALL define nothing outside `vanixiets`. No other first-party module SHALL test `options ? clan.core.vars`.

**Trust boundary**: this fixes what the seam hands clan. It relies on world assumption `A363 — A clan generator's result depends only on the definitions it receives, merging list fields in definition order` for the claim that the generator clan then evaluates is unchanged, and does not observe what clan generates or installs at runtime.

**Discharged by**: `checks.x86_64-linux.secrets-seam-translation`, which evaluates the module against a stub clan option and literal fixtures; its mutant.

#### Scenario: The translation fixtures

- **WHEN** the translation judge runs
- **THEN** it reports that a fixture setting every writable field yields every field, a fixture setting only `files.<f>.secret` yields only that field, a provided entry yields no generator, a declared file's `placeholder` is the stub's `sops.placeholder` entry where the stub has one and `null` where it has none, and an evaluation without the stub clan option yields no `clan` definition

#### Scenario: Mutant dropping a field

- **WHEN** a throwaway tree removes `restartUnits` from the translation
- **THEN** the translation judge fails, naming the fixture

### Requirement: Read-only fields come from the backend

For each entry and each declared file, the secrets module SHALL set the read-only fields `files.<f>.path`, `files.<f>.value` and `files.<f>.exists` from `clan.core.vars.generators.<name>.files.<f>`, and `files.<f>.placeholder` from `sops.placeholder."vars/<rel_dir>/<f>"` where sops-nix defines it and `null` elsewhere, and SHALL set each to `null` when clan-core is not imported.

**Trust boundary**: these are the backend's evaluated values. Their correspondence to the file a host holds at runtime rests on world assumption `A361 — clan's sops backend installs each secret var under the sops name vars/<rel_dir>/<file>, at that sops secret's path`.

**Discharged by**: the translation judge's read-back fixture (a stub placeholder read back), its absent-placeholder fixture (`null`), and its absent-backend fixture; at each delivery step, `nix eval` of each moved file's `path` equal to the parent revision's `clan.core.vars.generators.<name>.files.<f>.path`; on every NixOS and darwin host, `nix eval` of every declared file's `placeholder`, equal to `sops.placeholder."vars/<rel_dir>/<f>"` where that is defined and `null` elsewhere.

#### Scenario: A file sops-nix has no placeholder for

- **WHEN** a declared file's `placeholder` is evaluated on a host without `sops.templates`, where sops-nix defines no placeholder, or for a file that is no sops secret
- **THEN** it evaluates to `null`

#### Scenario: A moved secret's path

- **WHEN** a delivery step moves a generator and its `path` is evaluated on its host
- **THEN** it equals the path clan gave that file at the step's parent revision

### Requirement: A generator clan's own service declares is read as a provided entry

A module that reads a generator declared by a clan-core service SHALL declare `vanixiets.secrets.<name>.provided = true` for it and read only the read-only fields of its files, and the secrets module SHALL NOT define that generator.

**Readers**: `lib/host-keys.nix` reads `openssh`, and cinnabar's `zt-dns` feature reads `zerotier-network-zerotier`, in this way.

**Trust boundary**: a provided entry assumes the clan service declares the generator, as world assumption `A364 — clan-core's own services declare generators the fleet reads` records.

**Discharged by**: the translation judge's provided-entry fixture, its fixture of a provided entry that sets a writable field, and its fixture of a provided entry whose generator the backend lacks; `nix eval` of `nixosConfigurations.cinnabar.config.vanixiets.secrets.openssh.files."ssh.id_ed25519.pub".value` equal to `flake.lib.hostKeys.cinnabar`.

#### Scenario: The host key through the option

- **WHEN** cinnabar's `vanixiets.secrets.openssh` public value is evaluated
- **THEN** it equals `flake.lib.hostKeys.cinnabar`, ending in `" \n"`

#### Scenario: A reader declares the files it reads

- **WHEN** a module reads a file `f` of a provided entry
- **THEN** that module declares the file by name only, as `files.<f> = { }`, and reads only its read-only fields

#### Scenario: A provided entry sets a writable field

- **WHEN** a provided entry sets any writable field on a host where the backend is present
- **THEN** evaluation fails with a message naming the entry and each field set

#### Scenario: A provided entry whose generator clan lacks

- **WHEN** a module reads a file of a provided entry whose generator clan does not declare
- **THEN** evaluation fails with a message naming the entry

### Requirement: Homes see a view of the secrets they own

`flake.modules.homeManager.secrets` SHALL declare a home option `vanixiets.secrets` of `{ files.<f>.{path,placeholder} }` entries, default `{ }`, imported by every home configuration. The bridge modules SHALL set it for every home-manager user of the host. No home-manager module SHALL read `osConfig.clan.core.vars` or `osConfig.sops`.

**Exception**: `modules/home/ai/omnigent/credentials.nix` lives under `modules/home` but is no home-manager module: it defines `flake.lib.mkOmnigentWorkerCredentials` and the omnigent credential policy, functions a host evaluates with its own configuration as `osConfig`, and it reads that host's `sops.secrets` and `sops.templates` to judge what sops-nix installs for each worker.

**Bridge**: `flake.modules.nixos.hm-sops-bridge` and `flake.modules.darwin.hm-sops-bridge`, each keyed `vanixiets/hm-sops-bridge` through `flake.lib.exportAs` and imported by `nixos.base` and `darwin.base`, add to `home-manager.sharedModules` the home option and a module that sets it, in each home, from that home's `home.username` `u` to the host's `vanixiets.secrets` entries that have a file whose `owner` is `u`, whether or not `u` is in `hm-sops-bridge.users`.

**Trust boundary**: the view carries delivered locations, not contents, and only for files the home's user owns. It says nothing about `clan.core.settings`, which `vcs-signing.nix` still reads for the machine name.

**Discharged by**: `nix eval` of the view on cameron's home on cinnabar, crs58's home on stibnite, and a standalone `homeConfigurations` entry; the translation judge's home-view fixture, which evaluates a whole view on a stub host without sops placeholders; a source search of `modules/home` for `osConfig.clan.core.vars`, which finds no file, and for `osConfig.sops`, which finds only the exception above.

#### Scenario: A darwin home's signing key

- **WHEN** crs58's home on stibnite is evaluated after the commit-signing step
- **THEN** its `vanixiets.secrets.crs58-commit-signing-key.files.key.path` equals the host's path for that file, and its `vcs.signing.keyFile` equals the parent revision's

#### Scenario: A standalone home

- **WHEN** a `homeConfigurations` entry is evaluated
- **THEN** its `vanixiets.secrets` is `{ }` and its `vcs.signing.keyFile` equals the parent revision's

### Requirement: Obligations read the option or the backend function

An obligation SHALL read a secret only through `hostConfig.vanixiets.secrets.<name>` or `flake.lib.secretsBackend.generatorsOf hostConfig`, and no obligation file SHALL name `clan.core.vars`.

**By-name readers**: an obligation that reads one host's secret by name reads `hostConfig.vanixiets.secrets.<name>`, a file's location from its read-only fields and its custody from `resolved`. These are `commitSigningObligations`, `hostKeyObligations`, the omnigent fleet obligations and the r2-usage obligation.

**Backend readers**: `sharedVarsObligations` and `flake.lib.fleetDeployer`'s local secrets, which judge every generator on a host, and an obligation that asks whether the backend declares a generator at all, take the generators from `flake.lib.secretsBackend.generatorsOf hostConfig`, defined in `modules/system/secrets.nix`.

**Trust boundary**: the obligations keep their logic and fixtures' meaning; this fixes only where they read. `generatorsOf` is the backend's whole tree, including generators clan's own services declare.

**Discharged by**: `checks.x86_64-linux.{host-key-obligations,shared-vars-obligations,fleet-deployer-obligations}` and the commit-signing and omnigent obligation checks building; for every host, each obligation's `failures` equal to its parent-revision value.

#### Scenario: The obligation results

- **WHEN** each obligation's `failures` is evaluated for every NixOS and darwin host after the step that moves it
- **THEN** each equals its value at the step's parent revision

### Requirement: No module outside the seam names the backend

`checks.x86_64-linux.secrets-seam-confinement` SHALL compare a literal list against the files the confinement search finds, and SHALL fail when they differ. It is its own `runCommand`, built from the two lists alone as `flake.lib.mkStructuralCheck` builds, so that a failure prints each list one file per line. Before the last delivery step the literal list SHALL only shrink; after it, the list SHALL be exactly the final list below.

**Trust boundary**: the check reads source text. It cannot see an attribute path built from strings at evaluation time, and it says nothing about what clan does with what the seam hands it.

**Search**: the sorted `.nix` files under `modules/`, `_`-prefixed path components included, that have a non-comment line naming `clan.core.vars`, `vars/shared/` or `vars/per-machine/`, excluding the two seam files `modules/system/secrets.nix` and `modules/lib/vars.nix`, which neither the search nor the literal list ever includes. The search matches text: it does not see `inherit (config.clan.core) vars;`, a quoted attribute name, a path built from strings, or a file outside `modules/`.

**Final list**: `modules/vm-tests/{fleet-ingress,devloop-ingest,greptimedb-oom-order,greptimedb-pipeline,perses-greptimedb}.nix`, `modules/checks/greptimedb-envelope.nix` and `modules/checks/ntfy-provisioning.nix`, which run a generator's recipe; `modules/vm-tests/clan-test-vars-fixture.nix`; `modules/checks/secrets-seam-translation.nix`, an independent judge of the translation whose literal fixture is a stub of clan's generator option; `modules/checks/host-key-obligations.nix`, whose literal fixtures stub clan's generator tree; and the four files whose vars literals `modules/lib/vars.nix` documents, `modules/checks/{sops-correspondence,fleet-deployer-obligations,langfuse-query}.nix`, which spell the committed layout, and `modules/checks/commit-signing-key.nix`, which spells a delivered key path.

**Discharged by**: the check building at every step; the mutant below.

#### Scenario: Mutant adding a direct reader

- **WHEN** a throwaway tree adds a line reading `config.clan.core.vars.generators.ntfy-alerter.files.token.path` to `modules/system/ssh-known-hosts.nix`
- **THEN** the confinement check fails, and its diff names `modules/system/ssh-known-hosts.nix`

### Requirement: Every step's derivations are unchanged except its allow-list

For each delivery step, the drvPath of every NixOS, darwin and home toplevel and of every check and runtime test SHALL be the same at the step's commit as at its parent, except the differences its `drv-delta/<step>.txt` declares and those the refactor oracle's base allow-list covers. Every `may-change` entry SHALL be resolved to `changed` or removed before the step merges.

**Outputs compared**: `nixosConfigurations.<h>.config.system.build.toplevel`, `darwinConfigurations.<h>.config.system.build.toplevel`, `homeConfigurations.<h>.activationPackage`, and every attribute of `checks.x86_64-linux`, `checks.aarch64-darwin`, `vmTests.x86_64-linux` and `vmTests.aarch64-linux`.

**Trust boundary**: drvPath identity shows the evaluated outputs are unchanged. It does not show that clan generates or installs the same file at runtime, which no host deploy is made to observe because no host's configuration changes.

**Discharged by**: `just drv-diff <parent> <commit> openspec/changes/seam-secrets-away-from-clan-vars/drv-delta/<file>.txt` for each of the two commits that delivered the change: the seam with `01-seam.txt`, and every remaining move, delivered as one commit, with `02-13-move.txt`. The whole change is covered by those two comparisons together with the generator data of every host, which is identical at the change's base and on `main` after it; no single comparison over the whole change is run, because between the two commits other changes landed that change homes.

#### Scenario: A step's comparison

- **WHEN** `just drv-diff` runs over one delivery step with that step's allow-list
- **THEN** it exits 0, and no NixOS, darwin or home toplevel and no runtime test differs

### Requirement: Trust boundary of the seam interface

The seam interface SHALL be read as guaranteeing that first-party modules declare and read secrets only through `vanixiets.secrets` and the home view, and that every evaluated output is unchanged step by step. It SHALL NOT be read as guaranteeing that clan generates, encrypts or installs any secret correctly, that a recipe produces what its files declare, or that a string-built attribute path does not reach clan.

**Discharged by**: the statement above, and the trust boundary of each requirement in this capability.

#### Scenario: Clan installs a different file than it evaluates

- **WHEN** clan's runtime installation diverges from its evaluated paths or recipes
- **THEN** nothing in this capability observes it; world assumption `A361 — clan's sops backend installs each secret var under the sops name vars/<rel_dir>/<file>, at that sops secret's path` is void and the read-only fields lose their meaning

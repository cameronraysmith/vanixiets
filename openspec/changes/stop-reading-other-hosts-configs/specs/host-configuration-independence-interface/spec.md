## ADDED Requirements

### Requirement: No host configuration reads another host's evaluated configuration

No module imported by a `nixosConfigurations.<h>` or `darwinConfigurations.<h>` configuration SHALL read `nixosConfigurations`, `darwinConfigurations` or a `flake` module argument's configurations. In particular, `flake.modules.{nixos,darwin}.ssh-known-hosts` SHALL take no `flake` module argument, and stibnite's `services.stibnite-session-host.keys` SHALL be read through `flake.lib.vars`.

**Trust boundary**: this constrains the modules a host imports. Checks under `checks.<system>` and tests under `vmTests.<system>` may still read host configurations, and do so as drift oracles.

**Discharged by**: a source search of the modules every host imports for `nixosConfigurations.`, `darwinConfigurations.` and a `flake` module argument, run at the change's tip. Expected hits are confined to `modules/checks/`, `modules/vm-tests/` and to comments.

#### Scenario: The source search at the change's tip

- **WHEN** the `.nix` files under `modules/system`, `modules/nixos`, `modules/darwin`, `modules/home`, `modules/clan` and `modules/machines` are searched for those names
- **THEN** no non-comment hit is found

#### Scenario: Mutant restoring one cross-host read

- **WHEN** a throwaway tree restores `stibnite/default.nix`'s read of `inputs.self.nixosConfigurations.magnetite`
- **THEN** the source search reports that line

### Requirement: flake.lib.vars reads the committed vars layout in one place

`flake.lib.vars` SHALL provide:
- `relPath { generator, file, machine ? null }`: `vars/shared/<generator>/<file>`, or `vars/per-machine/<machine>/<generator>/<file>` when `machine` is set;
- `path`: the repository root joined to `relPath`;
- `public`: the untrimmed `readFile` of `<path>/value`;
- `exists`: `pathExists` of `<path>/secret`, or of `<path>/value` when `secret = false`;
- `isRecipient`: `pathExists` of `<path>/machines/<m>`, `<path>/groups/<g>` or `<path>/users/<u>`.

**Trust boundary**: the accessor guarantees one reading of the layout stated in world assumption `A320 — clan reads a public var's value as the committed file, untrimmed, at a path fixed by machine, generator and file`. It does not guarantee that clan still writes that layout.

**Discharged by**: `nix eval` of `flake.lib.vars.relPath` for one shared and one per-machine argument.

#### Scenario: Shared and per-machine paths

- **WHEN** `relPath { generator = "langfuse"; file = "secret-key"; }` and `relPath { machine = "cinnabar"; generator = "caddy-root-ca"; file = "root.crt"; }` are evaluated
- **THEN** they are `"vars/shared/langfuse/secret-key"` and `"vars/per-machine/cinnabar/caddy-root-ca/root.crt"`

### Requirement: Every reader of the committed vars tree uses one accessor and keeps its read

Every first-party module that reads the committed vars tree, other than the exempt sites named in the scenario below, SHALL do so through `flake.lib.vars`, keeping at each site its result value and its read function (`readFile`, `fileContents`, `trim`, `pathExists`, `readDir`, `hashFile`). A site MAY change whether it names the file as a path or a string; the drvPath diff proves that no derivation changes.

**Trust boundary**: one reading of the layout, resting on world assumption `A320 — clan reads a public var's value as the committed file, untrimmed, at a path fixed by machine, generator and file`; it does not guarantee that clan still writes that layout.

**Discharged by**: a source search for `vars/per-machine` and `vars/shared` outside `modules/lib/vars.nix` returning only exempt sites, comments and option documentation; the drvPath diff in `Every output's derivation is unchanged`, which shows every drvPath unchanged, including at the sites that moved from string to path. Rests on world assumption `A322 — A committed file reads the same through a repository path and through the flake source string`.

#### Scenario: Exempt sites keep their hand-written layout

- **WHEN** the source search is run at the change's tip
- **THEN** its only non-comment hits outside `modules/lib/vars.nix` are:
  - `modules/checks/sops-correspondence.nix`, the independent judge of the committed tree;
  - the literal fixtures of `modules/checks/fleet-deployer-obligations.nix`;
  - `modules/home/ai/omnigent/credentials.nix`, which uses clan's `rel_dir`;
  - `modules/checks/langfuse-query.nix`'s encrypted-file interpolation;
  - the absolute `/run/secrets/vars/…` runtime paths in check scripts.

#### Scenario: The deployer's local secret paths

- **WHEN** `flake.lib.fleetDeployer`'s local secrets are computed for a host after the migration
- **THEN** each path string equals the one computed at the parent revision

### Requirement: flake.lib.hostKeys holds every pinned host key and known_hosts reads only it

`flake.lib.hostKeys` SHALL map each of cinnabar, electrum, galena, scheelite, magnetite and pyrite to `flake.lib.vars.public { machine = <h>; generator = "openssh"; file = "ssh.id_ed25519.pub"; }`, and each name in `flake.lib.darwinHostKeys` to its literal value. Every `publicKey` that `flake.modules.{nixos,darwin}.ssh-known-hosts` sets for a fleet host SHALL be `hostKeys.<h>`.

**Trust boundary**: `hostKeys` is the committed record. Nothing here compares it with the key a running host presents.

**Discharged by**: `nix eval --json` of `darwinConfigurations.stibnite.config.programs.ssh.knownHosts` and of `nixosConfigurations.cinnabar.config.programs.ssh.knownHosts`, compared with the same expressions at the parent revision, must give identical JSON; the drvPath diff. Rests on world assumptions `A320 — clan reads a public var's value as the committed file, untrimmed, at a path fixed by machine, generator and file` and `A321 — The sshd service's host key generator is per machine and its public half is public`.

#### Scenario: A NixOS key keeps its trailing bytes

- **WHEN** `hostKeys.magnetite` is evaluated
- **THEN** it ends in `" \n"`, as clan's `.value` for magnetite's `openssh` public file does

### Requirement: Each NixOS host asserts that its generated host key equals its pinned key

`flake.lib.hostKeyObligations.failures name hostConfig` SHALL return exactly one failure when all three hold, and none otherwise:
- `hostKeys` has an entry for `name`;
- `hostConfig` declares a `clan.core.vars.generators.openssh` generator;
- that generator's `ssh.id_ed25519.pub` value differs from `hostKeys.<name>`.

**Trust boundary**: this compares the host's own evaluated generator with the committed file. It reads no other host and does not observe the running sshd.

**Discharged by**: `checks.x86_64-linux.host-key-obligations`, which judges the function over literal fixtures and evaluates no host.

#### Scenario: The judge's fixtures

- **WHEN** the judge check runs
- **THEN** it reports:
  - no failure for an accepted host, for a host absent from `hostKeys`, and for a host with no `openssh` generator;
  - one failure for a value differing by one character;
  - one failure for a value with the trailing `" \n"` removed.

### Requirement: Every NixOS host build enforces its own host-key obligation

`flake.modules.nixos.base` SHALL turn each failure of `flake.lib.hostKeyObligations.failures` for `config.clan.core.settings.machine.name` into an assertion, so that the `nixos-<host>` check and any deploy of that host fail on it.

**Trust boundary**: the assertion fires only for a host whose configuration imports `flake.modules.nixos.base`.

**Discharged by**: the throwaway-tree mutant below.

#### Scenario: Mutant on cinnabar's generated key

- **WHEN** a throwaway tree forces cinnabar's `clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value` to another ed25519 public key, leaving the committed file unchanged
- **THEN** evaluating `nixosConfigurations.cinnabar.config.system.build.toplevel` fails with an assertion naming cinnabar

### Requirement: Tests take magnetite's telemetry databases from flake data and assert magnetite declares them

Each of `vmTests.x86_64-linux.{greptimedb-pipeline, fleet-ingress, fleet-ingress-outage, devloop-ingest, devloop-ingest-reconcile, greptimedb-oom-order, perses-greptimedb}` SHALL take the telemetry store's databases from `flake.lib.otelCollectorSchema.databases`, and SHALL fail evaluation unless `nixosConfigurations.magnetite.config.services.greptimedb.databases` equals that map.

**Trust boundary**: this keeps each test's guard against magnetite drifting from the data. It does not stop the tests from evaluating magnetite, which they still do for the assertion and for other reads.

**Discharged by**: evaluation of each test's `driver` drvPath, which must equal the parent revision's; the throwaway-tree mutant below.

#### Scenario: Mutant on magnetite's databases

- **WHEN** a throwaway tree sets magnetite's `services.greptimedb.databases.fleet` to a TTL other than the data's
- **THEN** evaluating each of the seven tests fails with a message naming its test file and the mismatch

### Requirement: Every output's derivation is unchanged

The drvPath of every `nixosConfigurations.<h>.config.system.build.toplevel`, `darwinConfigurations.<h>.config.system.build.toplevel` and `homeConfigurations.<h>.activationPackage`, and of every attribute of `checks.x86_64-linux`, `checks.aarch64-darwin`, `vmTests.x86_64-linux` and `vmTests.aarch64-linux`, SHALL be the same at the change's tip as at its parent revision, except the differences declared in `drv-delta.txt` and those the refactor oracle's base allow-list covers.

**Trust boundary**: drvPath identity shows that no closure changes. It does not show that the new obligation is wired, which the mutant on a committed key shows.

**Discharged by**: `just drv-diff <parent> <tip> openspec/changes/stop-reading-other-hosts-configs/drv-delta.txt`, whose report is recorded in the change's verify evidence.

#### Scenario: The oracle diff

- **WHEN** `just drv-diff` runs from the parent revision to the tip with this change's `drv-delta.txt`
- **THEN** it exits 0, and outside the base allow-list the only differences are `checks.x86_64-linux.host-key-obligations` added and `checks.x86_64-linux.fleet-alert` and `checks.x86_64-linux.eval-users-lib` changed

#### Scenario: The vm-tests D6 edits keep their derivations

- **WHEN** the same report is read for the seven tests defined by the five vm-test files design D6 edits
- **THEN** none of them is reported as differing, and a reported difference blocks landing until design D8 explains it

### Requirement: The evaluation saving is measured, not inferred

The change's verify evidence SHALL record `cpuTime`, `nrThunks` and `gc.totalBytes` of evaluating the toplevel drvPath of `darwinConfigurations.stibnite` and `nixosConfigurations.cinnabar`, from interleaved A/B/A/B `NIX_SHOW_STATS` runs (A the parent revision, B the tip), one fresh process each, on one host with one Nix, compared with world assumption `A323 — The evaluation cost of other hosts' configurations on stibnite, measured 2026-11-26`.

**Trust boundary**: the figures are one host's measurements. They state the saving on that host and Nix, not on every evaluator.

**Discharged by**: the recorded stats files and the comparison table in the verify evidence.

#### Scenario: The A/B runs

- **WHEN** the four runs per configuration are taken
- **THEN** the two B runs of stibnite show fewer thunks than both A runs, and the table states the observed difference beside A323's 0.98 s / 3.7M thunks / 423 MB upper bound

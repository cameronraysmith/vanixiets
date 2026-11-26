## ADDED Requirements

<!--
Stratum: interface.
Trust boundary: these properties guarantee that every registered judge is evaluated against every machine-checked configuration of the classes it names, and that every judge-over-fixtures check reports its wrong cases. They do not guarantee that a judge is correct beyond its fixtures and mutants. They say nothing about a host with no machine check: a host listed as deferred is covered only by the fleet-wide checks. A judge sees the evaluated configuration, never the deployed host, so a host deployed from another revision or changed by hand is outside them.
-->

### Requirement: Each host judge is registered once, beside its definition

The flake-parts option `fleetObligations` SHALL map each key to `{ classes; failures; }`: `classes` a non-empty list drawn from `nixos` and `darwin` (default both), `failures` a function `name: hostConfig: [ string ]`. Each entry SHALL be defined in the module that defines its judge's `flake.lib` export, and `fleetObligations` SHALL NOT be a flake output.

**Discharged by**: `rg -n 'fleetObligations\.' modules` listing each entry in the file that defines its judge's export; the flake's output names, which include no `fleetObligations`.

#### Scenario: A registration sits beside its judge

- **WHEN** a reader opens the module that defines `flake.lib.harmoniaGcObligations`
- **THEN** the `fleetObligations.harmoniaGcObligations` entry is defined in that module, and in no other

#### Scenario: The registry is not an output

- **WHEN** the flake's top-level output names are listed
- **THEN** none is `fleetObligations`

### Requirement: The registry holds exactly the fleet's twelve judges

The keys of `fleetObligations` SHALL be exactly `commitSigningObligations`, `deployRecordObligations`, `fleetDeployer`, `harmoniaGcObligations`, `meshHostsObligations`, `networkTargetObligations`, `nixEvalJobsObligations`, `omnigentFleetObligations`, `postgresqlBackupObligations`, `r2UsageObligations`, `resolverReloadObligations` and `sopsBootInstallObligations`. The last two SHALL have `classes = [ "darwin" ]`; every other entry has both classes.

**Discharged by**: an evaluation-time assertion in `modules/checks/machines.nix` that `attrNames config.fleetObligations` equals that literal list, failing every machine check otherwise; the scenario below's mutant.

#### Scenario: A registration is removed

- **WHEN** one entry, for example `harmoniaGcObligations`, is deleted from the module that defines it
- **THEN** evaluating `checks.x86_64-linux.nixos-cinnabar.drvPath` fails, naming the key that the literal list holds and the registry lacks

#### Scenario: A judge is added

- **WHEN** a new judge's module adds an entry and the literal key list in `modules/checks/machines.nix` gains its key
- **THEN** every machine check of the entry's classes asserts it, and no other file is edited

### Requirement: Every machine check asserts every judge registered for its class

Each `checks.x86_64-linux.nixos-<host>` and `checks.aarch64-darwin.darwin-<host>` SHALL fail evaluation exactly when, for its host's configuration, some entry whose `classes` contain the host's class returns a non-empty list, or the configuration has a failing `assertions` entry. The class SHALL be taken from the configuration set being checked (`nixos` or `darwin`), never from the host's system string. A passing check's derivation SHALL be the host's toplevel unchanged.

**Discharged by**: the scenarios below, run as `extendModules` mutants of the real configurations; the cross-revision identity oracle showing every machine check's drvPath unchanged.

#### Scenario: A darwin-only judge does not run on NixOS

- **WHEN** a NixOS machine check is evaluated
- **THEN** neither `resolverReloadObligations` nor `sopsBootInstallObligations` is called for it

#### Scenario: Unchanged hosts

- **WHEN** the oracle compares the revision before this requirement with the one after
- **THEN** every `nixos-<host>` and `darwin-<host>` check has the same drvPath

### Requirement: A failing machine check names each unmet judge

A failing machine check's message SHALL begin `Fleet obligations unmet on <host>:` and carry one line `<key>: <message>` per message of each failing entry, followed by the configuration's failing assertion messages. It SHALL carry no line for an entry that returned `[ ]`.

**Discharged by**: the scenario below, run as an `extendModules` mutant of cinnabar's configuration.

#### Scenario: A NixOS host breaks a judge

- **WHEN** cinnabar's configuration is extended with `systemd.services.harmonia-gc.serviceConfig.TimeoutStartSec = lib.mkForce null`
- **THEN** evaluating its machine check fails with a message beginning `Fleet obligations unmet on cinnabar:`, a line beginning `harmoniaGcObligations: `, and no line for any other key

### Requirement: A judge-over-fixtures check reports each wrong case

`flake.lib.judgeCases { name; judge; cases; assertions ? [ ]; }` SHALL return its argument derivation unchanged when every case's judge (the case's own `judge`, else `judge`) returns exactly the case's `problems` count of messages and every `assertions` entry holds. Otherwise it SHALL throw a message with one line `<name>: <case>: expected <n> problems, the judge gave <m>: <messages>` per wrong case, followed by each failing assertion's message.

**Discharged by**: a one-case mutant run per migrated check, which shows the message's expected and actual counts.

#### Scenario: A fixture's count is wrong

- **WHEN** `harmonia-gc-obligations`'s `nixosNoTimeout` case is edited to expect 0 problems
- **THEN** evaluating `checks.x86_64-linux.harmonia-gc-obligations.drvPath` fails with `harmonia-gc-obligations: nixosNoTimeout: expected 0 problems, the judge gave 1:` and the judge's message

### Requirement: Every count-judged fixture check is built by one constructor

`flake.lib.mkJudgeCheck pkgs args` SHALL equal `judgeCases args (pkgs.runCommand args.name { } "touch $out")`. Every check that judges a fixture set by problem count SHALL use `judgeCases` or `mkJudgeCheck`. A check that judges by another predicate (`perses-config`) and a nix-unit check (`flake.lib.mkEvalCheck`) are outside this requirement. Neither constructor SHALL read or emit a `testSizes` entry.

**Discharged by**: the oracle showing each migrated check's drvPath unchanged; `checks.x86_64-linux.test-size-classes` passing with unchanged key sets.

#### Scenario: Migrated checks keep their derivations

- **WHEN** the oracle compares the revisions before and after the migration
- **THEN** the drvPaths of `darwin-resolver-reload`, `deploy-record-order`, `fleet-deployer-obligations`, `harmonia-gc-obligations`, `mesh-hosts-obligations`, `network-target-obligations`, `postgresql-backup-obligations`, `r2-usage`, `shared-vars-obligations`, `user-slice-guard-obligations` and `otel-collector-config` are unchanged

### Requirement: A check module states its system condition once

A check module whose whole `perSystem` value is conditioned on `system` SHALL NOT repeat that condition inside its `testSizes.checks` entries. The entries SHALL remain literal data keyed by the check names.

**Discharged by**: `rg -n 'testSizes\.checks = lib\.optionalAttrs \(system ==' modules` returning no file that also has an enclosing `system ==` condition; `checks.x86_64-linux.test-size-classes` passing with unchanged key sets.

#### Scenario: The gate is removed from one module

- **WHEN** `pyrite-audio.nix`'s inner condition is removed
- **THEN** `checks.x86_64-linux.pyrite-audio` and its `testSizes.checks.pyrite-audio` entry exist as before, and neither exists on `aarch64-darwin`

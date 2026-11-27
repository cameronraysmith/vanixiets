<!--
Raw capture of the decision chain for this change.
No interactive brainstorming session ran. On 2026-11-27 the operator decided to split the blocked work out of `register-fleet-obligations`, so that change can archive with every requirement it keeps met on `main`. The scope was fixed by that decision: the two runtime tests still building their own nixpkgs, the typing of the collector's envelope budget and its misspelled-field mutant, and two evaluation-only mutants that the verification of `register-fleet-obligations` found missing.
The forks below were settled from the repository as read on 2026-11-27 and from `register-fleet-obligations`' design (D5, D7), whose decisions this change carries over unchanged.
-->

# Brainstorm: finish the fleet package set and the budget typing

## Background

`register-fleet-obligations` landed its code on `main` (registry fold, judge constructor, nine runtime tests and two fixture checks on `fleetPkgs`, `patched` removed, the observability-host validator) and, with the host-key check converted, every task it could do. Three of its tasks could not run because another session holds the files they edit, with edits not yet landed:

- `modules/vm-tests/perses-greptimedb.nix:57-61` and `modules/vm-tests/shared-reference-tree.nix:35-39` still `import inputs.nixpkgs { … overlays = [ self.overlays.default ]; config.allowUnfree = true; }` for their nodes, where the other nine runtime-test modules now bind `nodePkgs = fleetPkgs;`.
- `vanixiets.otelCollector.envelopeBudget` is still `nullOr attrs` (`modules/clan/services/otel-collector/flake-module.nix:165-175`). Its two writers are the clan ingress role (`:1722`) and the `fleet-ingress` test's store container (`modules/vm-tests/fleet-ingress.nix:2213`); its reader is `flake.lib.otelEnvelope` through `:624`.

Verification of `register-fleet-obligations` also found two scenarios that the fleet's specs state but that no mutant has ever run:

- `fleet-host-registry` "A host disappears from the registry": a host's record removed from `flake.fleet.hosts`, nothing else edited, must fail the comparison with the fleet pin, naming the host. The pin is `checks.x86_64-linux.structure-fleet` (`modules/checks/structure/flake-shape.nix`); the machine checks' own asserts in `modules/checks/machines.nix` compare the inventory, `clan.machines` and the per-class directories.
- `database-backup-interface` "a database is added without a backup" (held in `back-up-postgresql-off-host`'s delta until that change archives): magnetite, with the backup on (`modules/machines/nixos/magnetite/default.nix:383`, `awaitingSecrets = [ ]`), gaining a database the backup set does not cover must fail `nixos-magnetite` naming `postgresqlBackupObligations` and the database's dump unit. The judge is registered as `fleetObligations.postgresqlBackupObligations` on `main`.

## Decision chain

Q1. One change or three? One. All four pieces are drvPath-neutral or evaluation-only, they share one oracle run, and the two held pieces are waiting on the same other session. The two mutants need no held file and can run first.

Q2. How do the two runtime tests move? Exactly as the nine did in `register-fleet-obligations` (its D5): take `fleetPkgs` from the `perSystem` arguments and bind `nodePkgs = fleetPkgs;`, so the test bodies are untouched. `shared-reference-tree` keyed its import on `pkgs.stdenv.hostPlatform.system`, which equals the perSystem `system`. The difference between their imports and `fleetPkgs` is `permittedInsecurePackages`, which A330 says enters no derivation.

Q3. How is the budget typed? As `register-fleet-obligations` D7 decided: `nullOr (submodule { storeUrl : str; notifiedUnits : attrsOf (listOf str); databases : attrsOf str; })`, in whatever file holds the option once the other session lands. Alternative `attrsOf anything` plus an assertion: rejected again, weaker and later.

Q4. Do the two mutants need new requirements? No. Each discharges a scenario another capability already states. They are tasks with recorded evidence, not spec text. The backup scenario is not restated here, so this change does not wait for `back-up-postgresql-off-host` to archive.

Q5. How is the change accepted? One commit, one `just drv-diff <parent> <commit> openspec/changes/finish-fleet-package-set-and-budget-typing/drv-delta.txt` (about 16 minutes), the delta file naming exact attribute paths only. Each task group keeps its own per-attribute evaluation against the parent, as `register-fleet-obligations` did.

Q6. Which requirements move here from `register-fleet-obligations`? Its "The envelope budget has a declared shape" (whole) and the runtime-test half of "Runtime tests and fixture checks evaluate against the fleet package set". `register-fleet-obligations` keeps the fixture-check half and A330, both met on `main`; the runtime-test requirement here names A330 too.

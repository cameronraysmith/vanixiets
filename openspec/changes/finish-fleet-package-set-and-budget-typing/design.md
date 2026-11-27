## Context

`register-fleet-obligations` moved nine runtime-test modules and two fixture checks to the per-system `fleetPkgs`, and decided how to type `vanixiets.otelCollector.envelopeBudget` (its D5 and D7). It could not apply either decision to the files another session holds with unlanded edits, and on 2026-11-27 the operator split that remainder off into this change. As of `main` on 2026-11-27:

- `modules/vm-tests/perses-greptimedb.nix:57-61` binds `nodePkgs = import inputs.nixpkgs { inherit system; config.allowUnfree = true; overlays = [ self.overlays.default ]; }`. `modules/vm-tests/shared-reference-tree.nix:35-39` does the same, keyed on `pkgs.stdenv.hostPlatform.system`. `fleetPkgs` (`modules/nixpkgs/base-defaults.nix`) is the flake's nixpkgs with `[ config.flake.overlays.default ]`, `allowUnfree` and `permittedInsecurePackages`.
- `envelopeBudget` is `lib.types.nullOr lib.types.attrs` (`modules/clan/services/otel-collector/flake-module.nix:165-175`). The clan ingress role (`:1722`) and the `fleet-ingress` test's store container (`modules/vm-tests/fleet-ingress.nix:2213`) set exactly `storeUrl`, `notifiedUnits` and `databases`; `flake.lib.otelEnvelope` reads it (`:624`).
- `register-fleet-obligations`' verification found two stated scenarios with no mutant run: `fleet-host-registry` "A host disappears from the registry", whose pin is `checks.x86_64-linux.structure-fleet` (`modules/checks/structure/flake-shape.nix`) beside the asserts in `modules/checks/machines.nix`; and `database-backup-interface` "a database is added without a backup", whose judge is registered as `fleetObligations.postgresqlBackupObligations` (`modules/nixos/postgresql-backup.nix`) and folded into every machine check. Magnetite has the backup on (`modules/machines/nixos/magnetite/default.nix:383`).

## Goals / Non-Goals

**Goals:**
- No runtime test instantiates a package set of its own; the two moved tests keep their derivations.
- `envelopeBudget` rejects a malformed definition at evaluation, with every derivation unchanged.
- The two scenarios above are each shown failing by one recorded mutant run.
- The change is accepted on one `just drv-diff` run with an exact-path allow-list.

**Non-Goals:**
- Editing the test bodies of the two runtime tests.
- Any other option or behaviour of the otel-collector service.
- Changing what `postgresqlBackupObligations` or the fleet pin enforce.
- Restating the backup scenario in this change's specs.

## Decisions

### D1: the two runtime tests read `fleetPkgs`

- **Choice**: each module takes `fleetPkgs` from its `perSystem` arguments and binds `nodePkgs = fleetPkgs;` in place of the import, so every use of `nodePkgs` keeps its name and the test bodies are not edited. `shared-reference-tree`'s `pkgs.stdenv.hostPlatform.system` equals the perSystem `system`, so no per-system lookup is needed.
- **Rationale**: the same move as `register-fleet-obligations` D5, which left the other nine tests' drvPaths unchanged. The only configuration difference is `permittedInsecurePackages`, which in the locked nixpkgs decides only whether evaluation throws (A330). Boundary: vendored-versus-first-party. nixpkgs and the NixOS test framework are used through `node.pkgs` and are not patched.
- **Alternatives considered**: the perSystem `pkgs`. It lacks `flake.overlays.default`.

### D2: `envelopeBudget` becomes a submodule

- **Choice**: `type = lib.types.nullOr (lib.types.submodule { options = { storeUrl = mkOption { type = str; }; notifiedUnits = mkOption { type = attrsOf (listOf str); }; databases = mkOption { type = attrsOf str; }; }; });`, in the file that holds the option once the other session has landed, with the description unchanged apart from dropping the inline shape.
- **Rationale**: both writers set exactly these three fields. The merged value has the same attributes and values, so `otelEnvelope`'s rendered script is unchanged and magnetite's toplevel and `vmTests.x86_64-linux.fleet-ingress` keep their derivations. A definition with a field the record does not have, such as `storeURL`, now fails evaluation at the option, naming it; the untyped set accepted such a field (a missing `storeUrl` already failed, where `otelEnvelope` reads `budget.storeUrl`). Boundary: first-party option on a vendored service; only the first-party option type changes.
- **Alternatives considered**: `attrsOf anything` with an assertion. It is weaker, and the error arrives later.

### D3: two evaluation-only mutants, as tasks rather than requirements

- **Choice**: in throwaway copies of the tree under `/tmp`:
  - delete one checked host's record from `flake.fleet.hosts` and evaluate the machine checks of the remaining hosts and `checks.x86_64-linux.structure-fleet`;
  - extend magnetite's configuration with one database in `services.postgresql.ensureDatabases` outside the backup set and evaluate `checks.x86_64-linux.nixos-magnetite`.
  Each run's output goes to `logs/` and its result into `tasks.md` and `verify.md`.
- **Rationale**: both scenarios are already stated in other capabilities; what is missing is the evidence. Restating the backup scenario here would make this change wait for `back-up-postgresql-off-host` to archive. Boundary: source-only; nothing committed changes.
- **Amendment (2026-11-27)**: the host-record mutant showed evaluation failing at the `flake.lib.machineSystems names must match clan.inventory.machines` assert in `modules/checks/machines.nix`, before the fleet pin, with a message that does not name the host, so the assert's message now lists the names only in `machineSystems` and only in the inventory (`lib.subtractLists` both ways); its condition, every other assert and every derivation are unchanged.
- **Alternatives considered**: permanent mutant checks in `checks.<system>`. Each would need a fixture configuration and a size-class entry for a one-off proof.

### D4: sequencing and acceptance

- **Choice**: the mutants (D3) run as soon as convenient. D1 and D2 start only after the other session's edits to `modules/vm-tests/{perses-greptimedb,shared-reference-tree}.nix` and `modules/clan/services/otel-collector/**` have landed on `main`. The change lands as one commit, accepted on one `just drv-diff <parent> <commit> openspec/changes/finish-fleet-package-set-and-budget-typing/drv-delta.txt` (about 16 minutes). `drv-delta.txt` names exact attribute paths only; it is expected to be empty, and any entry carries the cause the per-attribute evaluation found.
- **Rationale**: one oracle run covers both edits; the per-attribute evaluations of each group catch a difference earlier and name it.
- **Alternatives considered**: one commit per group. Two full diffs for no added coverage.

### D5: spec deltas

- **Choice**: ADDED `fleet-package-set-interface` "Runtime tests evaluate against the fleet package set" and ADDED `fleet-ingress-interface` "The envelope budget has a declared shape", both moved from `register-fleet-obligations`. That change keeps "Fixture checks evaluate against the fleet package set" and A330.
- **Archive order**: after `register-fleet-obligations`, which creates `fleet-package-set-interface` and A330 in the corpus.

## Spec and feature alignment

No row routes to a Gherkin scenario or an executable-specification modality: every observable is an evaluated value or a drvPath.

| Requirement or scenario | Capability | Stratum | Modality | Nix check that realizes it | Witness |
|---|---|---|---|---|---|
| Runtime tests evaluate against the fleet package set | `fleet-package-set-interface` | interface | content search and build gate (drvPath comparison) | `vmTests.<system>` attributes of the two modules | tasks 2.1, 2.2, 5.1 |
| The envelope budget has a declared shape | `fleet-ingress-interface` | interface | build gate (`extendModules` mutant; drvPath comparison) | `checks.x86_64-linux.nixos-magnetite`, `vmTests.x86_64-linux.fleet-ingress` | tasks 3.1, 3.2, 5.1 |
| `fleet-host-registry` "A host disappears from the registry" | `fleet-host-registry` (corpus) | behavioral | build gate (mutant) | `checks.x86_64-linux.structure-fleet`, the machine checks | task 4.1 |
| `database-backup-interface` "a database is added without a backup" | `database-backup-interface` (via `back-up-postgresql-off-host`) | interface | build gate (`extendModules` mutant) | `checks.x86_64-linux.nixos-magnetite` | task 4.2 |

## Risks / Trade-offs

- [Risk] The other session's edits change the two test modules or the option's file so that the moves no longer apply as written. → Mitigation: task 1.1 re-reads both files after they land; the decision, not the line numbers, is what applies.
- [Risk] `fleetPkgs` changes a moved test's derivation. → Mitigation: the per-attribute evaluation names it; its cause is found with `nix derivation show` on both drvs and declared in `drv-delta.txt`, or the move is reconsidered if A330 is violated.
- [Risk] The host-record mutant fails for a reason other than the pin, for example an inventory assert. → Mitigation: the run records which message fired; the scenario holds only if the failure names the host.
- [Trade-off] The mutants leave no permanent regression check. Accepted: D3.

## Migration Plan

N/A — this change does not involve a deployment change. No host deploys, and no host's derivation changes.

The commit lands after the other session's edits; rollback is its revert.

## Open Questions

None.

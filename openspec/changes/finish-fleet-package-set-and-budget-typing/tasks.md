The change lands as one commit parented on `main`, accepted on one `just drv-diff` (task 5.1). Each group keeps its own evidence by evaluating the attributes it touches against the parent, one process per side. Every mutant runs in a throwaway copy of the tree under `/tmp`, never in the committed tree. A run expected to take over 5 minutes is announced first with its expected duration, what it proves and what waits on it. Nothing here deploys a host.

## 1. Baseline

- [ ] 1.1 Confirm that the other session's edits to `modules/vm-tests/perses-greptimedb.nix`, `modules/vm-tests/shared-reference-tree.nix` and `modules/clan/services/otel-collector/**` have landed on `main`, and re-read where `nodePkgs` is bound in the two test modules and which file declares `envelopeBudget` — verify: `jj log -r 'mutable() & ~::@ & files(<those three paths>)'` returns no other change; the parent commit and the option's file and line are recorded here. Groups 2 and 3 start only after this task
- [ ] 1.2 Record the base drvPaths, in one evaluation of the parent, of every `vmTests.<system>` attribute the two test modules define, `checks.x86_64-linux.nixos-magnetite` and `vmTests.x86_64-linux.fleet-ingress` — verify: `logs/ffp-base-drvpaths-<ts>.json` holds a drvPath for each, with the attribute names listed by evaluation, not by reading the source

## 2. The last two runtime tests on the fleet package set (design D1)

- [ ] 2.1 In `modules/vm-tests/perses-greptimedb.nix`, take `fleetPkgs` from the `perSystem` arguments and bind `nodePkgs = fleetPkgs;`, deleting the local `import inputs.nixpkgs`; the test body is not edited — verify: by evaluation, `vmTests.x86_64-linux.perses-greptimedb` keeps its base drvPath, or its difference is recorded with the cause `nix derivation show` finds on both drvs
- [ ] 2.2 The same in `modules/vm-tests/shared-reference-tree.nix` — verify: `rg -n 'import inputs\.nixpkgs' modules/vm-tests` returns nothing; by evaluation, every `vmTests` attribute the module defines keeps its base drvPath, or its difference is recorded with its cause

## 3. The envelope budget's shape (design D2)

- [ ] 3.1 Type `vanixiets.otelCollector.envelopeBudget` as `nullOr (submodule { storeUrl : str; notifiedUnits : attrsOf (listOf str); databases : attrsOf str; })` in the file task 1.1 found — verify: by evaluation, `checks.x86_64-linux.nixos-magnetite` and `vmTests.x86_64-linux.fleet-ingress` keep their base drvPaths
- [ ] 3.2 Run the misspelled-field mutant: an `extendModules` of magnetite's configuration setting `vanixiets.otelCollector.envelopeBudget = { storeURL = "http://127.0.0.1:4000"; notifiedUnits = { }; databases = { }; }` — verify: evaluation fails naming `envelopeBudget.storeURL` (`logs/ffp-mutants-<ts>.log`)

## 4. Two evaluation-only mutants (design D3)

- [ ] 4.1 In a throwaway tree, delete one checked host's record from `flake.fleet.hosts` and nothing else; evaluate `checks.x86_64-linux.structure-fleet.drvPath` and the remaining hosts' machine checks — verify: evaluation fails with a message naming the removed host, as the `fleet-host-registry` scenario "A host disappears from the registry" states; the log records which check and which assertion fired (`logs/ffp-mutants-<ts>.log`)
- [ ] 4.2 In a throwaway tree, extend magnetite's configuration (backup on) with one database in `services.postgresql.ensureDatabases` that the backup set does not cover — verify: `checks.x86_64-linux.nixos-magnetite.drvPath` fails with `Fleet obligations unmet on magnetite:` and a `postgresqlBackupObligations: ` line naming the database's dump unit, as the `database-backup-interface` scenario "a database is added without a backup" states (`logs/ffp-mutants-<ts>.log`)

## 5. Integration Verification

- [ ] 5.1 Write `drv-delta.txt` naming, by exact attribute path, each difference groups 2 and 3 recorded, with its cause (empty if none), then run the oracle once, announced first: `just drv-diff <parent> <commit> openspec/changes/finish-fleet-package-set-and-budget-typing/drv-delta.txt`, about 16 minutes — verify: exit 0; every difference is in `drv-delta.txt` or the base allow-list; no declared entry fails to occur; output in `logs/drv-diff-*`. Needs the committed revision

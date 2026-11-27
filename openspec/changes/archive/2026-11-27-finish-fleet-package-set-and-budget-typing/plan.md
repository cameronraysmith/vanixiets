# Finish the fleet package set and the budget typing implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** move the last two runtime tests to `fleetPkgs`, type `envelopeBudget`, and run the two missing mutants, accepted on one `just drv-diff` (tasks.md groups 1–5).

**Architecture:** both edits are local and drvPath-neutral: a `let` alias `nodePkgs = fleetPkgs;` in each test module (design D1) and a submodule type on one option (D2). The mutants are evaluation-only runs in throwaway trees (D3).

**Tech Stack:** flake-parts perSystem arguments; the NixOS module system (`lib.types.submodule`, `extendModules`); the NixOS test framework's `node.pkgs`; `just drv-diff` from `establish-refactor-oracle`.

**Spec:** `openspec/changes/finish-fleet-package-set-and-budget-typing/`: `design.md` (D1–D5), `specs/` (`fleet-package-set-interface`, `fleet-ingress-interface`), `tasks.md`, `brainstorm.md`, `proposal.md`.

## Global Constraints

- Groups 2 and 3 do not start until task 1.1 finds the other session's edits to `modules/vm-tests/{perses-greptimedb,shared-reference-tree}.nix` and `modules/clan/services/otel-collector/**` landed. Group 4 needs no held file.
- One commit; `drv-delta.txt` takes exact attribute paths only, each with its cause. The base allow-list (`modules/apps/drv-diff-base-allow.txt`) covers `gitleaks`, `treefmt` and `ntfy-tls-verification`.
- Mutants run in a throwaway copy of the tree under `/tmp`. A run expected to take over 5 minutes is announced first with its duration, what it proves that a cheaper run cannot, and what waits on it.
- Test bodies, other otel-collector options and the judges are not edited.

---

## Task 1: Baseline (tasks 1.1, 1.2)

- [ ] **Step 1:** check that no other mutable change touches the three held paths; record the parent commit.
- [ ] **Step 2:** list by evaluation the `vmTests.<system>` names the two modules define (`nix eval .#vmTests.x86_64-linux --apply builtins.attrNames`, and the same for every system that has `vmTests`).
- [ ] **Step 3:** evaluate, in one process at the parent, the drvPaths of those attributes, `checks.x86_64-linux.nixos-magnetite` and `vmTests.x86_64-linux.fleet-ingress`, into `logs/ffp-base-drvpaths-<ts>.json`.

## Task 2: Runtime tests on `fleetPkgs` (tasks 2.1, 2.2)

- [ ] **Step 1:** in `perses-greptimedb.nix`, add `fleetPkgs` to the `perSystem` argument set and replace the `nodePkgs = import inputs.nixpkgs { … };` binding with `nodePkgs = fleetPkgs;`. Drop `inputs` from the module arguments if nothing else reads it.
- [ ] **Step 2:** the same in `shared-reference-tree.nix`.
- [ ] **Step 3:** `rg -n 'import inputs\.nixpkgs' modules/vm-tests` returns nothing.
- [ ] **Step 4:** evaluate the same attributes at the working copy into `logs/ffp-head-drvpaths-<ts>.json` and compare; for any difference run `nix derivation show` on both drvs and record the cause in tasks.md.

## Task 3: `envelopeBudget` (tasks 3.1, 3.2)

- [ ] **Step 1:** replace `lib.types.nullOr lib.types.attrs` with D2's `nullOr (submodule { … })` in the file task 1.1 recorded; trim the description's inline shape.
- [ ] **Step 2:** re-evaluate `nixos-magnetite` and `vmTests.x86_64-linux.fleet-ingress`; both drvPaths equal the base.
- [ ] **Step 3:** in a throwaway tree, evaluate `self.nixosConfigurations.magnetite.extendModules { modules = [ { vanixiets.otelCollector.envelopeBudget = { storeURL = "http://127.0.0.1:4000"; notifiedUnits = { }; databases = { }; }; } ]; }` down to `config.system.build.toplevel.drvPath`; the error names `envelopeBudget.storeURL`. Log to `logs/ffp-mutants-<ts>.log`.

## Task 4: Mutants (tasks 4.1, 4.2)

- [ ] **Step 1:** copy the tree to `/tmp/ffp-mut-host`; delete one checked host's record (for example `electrum`, `modules/lib/hosts.nix:243`) from `flake.fleet.hosts`, nothing else; evaluate `checks.x86_64-linux.structure-fleet.drvPath` and `checks.x86_64-linux.nixos-cinnabar.drvPath`; record each error and that it names the host.
- [ ] **Step 2:** copy the tree to `/tmp/ffp-mut-db`; extend magnetite's configuration with `services.postgresql.ensureDatabases = [ "ffpmutant" ];`; evaluate `checks.x86_64-linux.nixos-magnetite.drvPath`; the error begins `Fleet obligations unmet on magnetite:` and carries a `postgresqlBackupObligations: ` line naming the database's dump unit.
- [ ] **Step 3:** record both results as evidence under tasks 4.1 and 4.2.

## Task 5: Oracle (task 5.1)

- [ ] **Step 1:** write `drv-delta.txt` from the differences tasks 2 and 3 recorded (empty if none).
- [ ] **Step 2:** after the orchestrator commits, announce and run `just drv-diff <parent> <commit> openspec/changes/finish-fleet-package-set-and-budget-typing/drv-delta.txt` (about 16 minutes); record the report path and result under task 5.1.

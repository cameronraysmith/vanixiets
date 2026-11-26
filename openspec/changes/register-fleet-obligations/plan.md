# Register fleet obligations implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** register the twelve host judges once beside their definitions and fold them in the machine checks; give every judge-over-fixtures check one constructor that reports per case; drop 25 redundant system gates; evaluate runtime tests and fixture checks against `fleetPkgs`; remove the unused `patched` channel with an ADR-0017 amendment; type `envelopeBudget` and validate `observabilityHosts` (tasks.md groups 1–7).

**Architecture:** a flake-parts option `fleetObligations` (not a flake output) collects `{ classes; failures; }` entries; `modules/checks/machines.nix` folds the entries for each configuration's class into one assertion. `flake.lib.judgeCases` wraps a check derivation in per-case assertions, and `flake.lib.mkJudgeCheck` applies it to the empty marker derivation the fixture checks already build. Every edit is drvPath-neutral except `vmTests`, which may differ through `fleetPkgs` and only with a named cause.

**Tech Stack:** flake-parts with import-tree; the NixOS module system (`lib.types.submodule`, `functionTo`); nixpkgs `import` and the NixOS test framework's `node.pkgs`; `just drv-diff` and `just eval-cost` from `establish-refactor-oracle`.

**Spec:** `openspec/changes/register-fleet-obligations/`: `design.md` (D1–D10), `specs/` (`fleet-obligation-registry-interface`, `fleet-package-set-interface`, `database-backup-interface`, `fleet-ingress-interface`, `world-assumptions` A330–A332), `tasks.md`, `brainstorm.md`, `proposal.md`.

## Global Constraints

- Five stacked chains, one per tasks.md group 1–5, each landing as one pull request in order; groups 6–7 close out. Each commit evaluates and passes its checks alone. In this jj-colocated repository, edits are made in `@` and routed with `jj squash --into <chain> --use-destination-message --keep-emptied <paths>`.
- Group 1 starts only after `just drv-diff` exists on `main`, as delivered by `establish-refactor-oracle` with `vmTests.{x86_64-linux,aarch64-linux}` in its dumps. There is no second dump script.
- Allow-lists: empty for groups 1, 2, 4 and 5. For group 3, the fifteen exact `vmTests` attribute paths listed in design D10, each `may-change`; no globs.
- Never edit: the `testSizes` literal entries, apart from deleting the inner gate in 2.5; `checks/omnigent-workers.nix:16-21`; the literal oracles `omnigent-workers.nix:594-600`, `omnigent-acp-spawn-env.nix:19-22`, `nix-builders-wiring.nix:11-12,43-55`, `sops-correspondence.nix:35-62`; `deferred = [ "scheelite" ]`; `machines.nix:99-123` apart from appending the key-list assert; `nixidy.nix`; the `nixpkgs`/`unstable` channel attributes; `perses-config.nix`; the `mkEvalCheck` users.
- Registry keys are exactly the names machines.nix prints today (design Context table); no judge's `flake.lib` export is renamed or changed.
- x86_64-linux evaluation and builds run on magnetite's store (`--eval-store auto --store ssh-ng://magnetite.zt`); aarch64-darwin attributes are evaluated, never built. A run expected to take over 5 minutes is announced first with its duration, what it proves that a cheaper run cannot, and what waits on it.
- Mutants run as `extendModules` overrides or in a throwaway tree, never in the committed tree.

## Review Focus

- A judge that returns a non-string element (an attribute set, a path) breaks the fold's `functionTo (listOf str)` type. Task 1 checks that each judge's output type is a list of strings by reading its definition, and `omnigentFleetObligations` (case names from `attrNames`) is confirmed.
- A judge that throws on a class it does not apply to, such as `resolverReloadObligations` reading darwin-only `system.activationScripts.script.text`: the fold must never call it for NixOS. Task 1's fourth mutant pins this.
- A fixture case set whose cases carry a field named `judge` for another purpose would be taken as a per-case judge override. Task 2 checks each migrated case set for a `judge` key before migrating.
- A `vmTests` module that read `pkgs` (the perSystem instance) for a node package where `nodePkgs` was meant: the swap changes only `nodePkgs`, so those uses keep their instance. Task 3 lists every `pkgs.` use in the eleven files and records which instance each meant.
- A row in `observabilityHosts` built by `agent [ ] // { … }` that adds a new field intentionally (none today): the validator rejects it. That is the intended behavior, and the schema list in D8 is the one to extend.

## Interface contract

| Kind | Name | Defined in |
|---|---|---|
| flake-parts option | `fleetObligations : attrsOf { classes : listOf (enum [ "nixos" "darwin" ]) = [ "nixos" "darwin" ]; failures : name -> hostConfig -> [ str ]; }` | Task 1 |
| machines.nix function | `withFleetObligations : class -> name -> machineConfig -> toplevel -> toplevel` | Task 1 |
| machines.nix assert | `attrNames config.fleetObligations == [ "commitSigningObligations" "deployRecordObligations" "fleetDeployer" "harmoniaGcObligations" "meshHostsObligations" "networkTargetObligations" "nixEvalJobsObligations" "omnigentFleetObligations" "postgresqlBackupObligations" "r2UsageObligations" "resolverReloadObligations" "sopsBootInstallObligations" ]` | Task 1 |
| Lib | `flake.lib.judgeCases : { name; judge; cases : attrsOf { problems : int; judge ? fn; … }; assertions ? [ { assertion : bool; message : str; } ]; } -> drv -> drv` | Task 2 |
| Lib | `flake.lib.mkJudgeCheck : pkgs -> args -> drv` = `judgeCases args (pkgs.runCommand args.name { } "touch $out")` | Task 2 |
| Option type | `vanixiets.otelCollector.envelopeBudget : nullOr { storeUrl : str; notifiedUnits : attrsOf (listOf str); databases : attrsOf str; }` | Task 5 |
| Lib | `flake.lib.observabilityHostProblems : attrsOf row -> [ str ]` | Task 5 |

---

## Task 1: the registry and the fold (tasks.md 1.1–1.7)

**Files:**
- Create: `modules/lib/fleet-obligations.nix`
- Modify: `modules/checks/machines.nix:31-98` (the fold) and `:123` (append the key-list assert)
- Modify, one registration each: `modules/lib/omnigent-fleet-obligations.nix:588`, `modules/system/deploy-record.nix:143`, `modules/lib/commit-signing.nix:273`, `modules/darwin/resolver-reload.nix:74`, `modules/darwin/sops-boot-install.nix:85`, `modules/system/mesh-hosts.nix:79`, `modules/system/harmonia-gc.nix:75`, `modules/nixos/postgresql-backup.nix:386`, `modules/nixos/r2-usage.nix:426`, `modules/lib/fleet-deployer.nix:360`, `modules/lib/nix-eval-jobs-host.nix:188`, `modules/lib/network-targets.nix:82`
- Modify: `modules/README.md:89,120-124`

**Interfaces:**
- Produces: `config.fleetObligations` (read by Task 7's probe); `withFleetObligations class name machineConfig toplevel`.

- [ ] **Step 1:** Record the base: `just drv-diff` needs a base revision; note `git rev-parse main` in `logs/rfo-1-base-<ts>.log`.
- [ ] **Step 2:** Write the mutant harness first, in a throwaway tree: a scratch module that evaluates `withFleetObligations "nixos" "cinnabar" (self.nixosConfigurations.cinnabar.extendModules { modules = [ { systemd.services.harmonia-gc.serviceConfig.TimeoutStartSec = lib.mkForce null; } ]; }).config null`. Run it on base, where `withFleetObligations` takes no class, and expect an evaluation error about the arity. This is the red run.
- [ ] **Step 3:** Create `modules/lib/fleet-obligations.nix` with the option from the interface contract, `default = { }`, and a description naming the machine-check fold.
- [ ] **Step 4:** In each of the twelve judge files, add a top-level `fleetObligations.<key> = { failures = <export>.failures; };`, adding `classes = [ "darwin" ];` for `resolverReloadObligations` and `sopsBootInstallObligations`. Reference the same value the file exports under `flake.lib`, so the export and the entry cannot diverge. For `lib/commit-signing.nix` and `lib/nix-eval-jobs-host.nix`, whose exports sit inside a `flake.lib = { … }` attrset, bind the judge in the file's `let` and use it in both places.
- [ ] **Step 5:** Rewrite `machines.nix`'s `let`: delete `withNetworkTargets` (`:31-42`) and the bindings `:44-54`. Define

  ```nix
  withFleetObligations =
    class: name: machineConfig: toplevel:
    let
      unmet = lib.concatLists (
        lib.mapAttrsToList (
          key: entry:
          lib.optionals (lib.elem class entry.classes) (
            map (m: "${key}: ${m}") (entry.failures name machineConfig)
          )
        ) config.fleetObligations
      );
      hostFailures = map (a: a.message) (lib.filter (a: !a.assertion) machineConfig.assertions);
    in
    assert lib.assertMsg (unmet == [ ]) (
      "Fleet obligations unmet on ${name}:\n${lib.concatStringsSep "\n" unmet}"
      + lib.optionalString (hostFailures != [ ]) "\n${name} assertion failures: ${lib.concatStringsSep "\n" hostFailures}"
    );
    toplevel;
  ```

  Call it as `withFleetObligations "nixos" name cfg toplevel` and `withFleetObligations "darwin" name cfg toplevel` at `:158` and `:167`, dropping the `withNetworkTargets` wrapper. Add `config` to the module's arguments. Keep `obligations.expectedOwners` reachable for the `:118-120` assert as `self.lib.omnigentFleetObligations.expectedOwners`.
- [ ] **Step 6:** Append the key-list assert from the interface contract after `:123`.
- [ ] **Step 7:** Evaluate `nixos-cinnabar`, `nixos-magnetite` and `darwin-stibnite` `.drvPath`; then run Step 2's harness and the other three mutants of tasks.md 1.4. Expect: one `harmoniaGcObligations: ` line on each harmonia mutant, the missing-key message on the deletion, and a clean evaluation for the darwin-only throwing entry on a NixOS check. Log to `logs/rfo-1-mutants-<ts>.log`.
- [ ] **Step 8:** `just eval-cost` on `checks.x86_64-linux.nixos-magnetite.drvPath`, base against head (tasks.md 1.5).
- [ ] **Step 9:** Update `modules/README.md` (tasks.md 1.6); `prek run --files modules/README.md`.
- [ ] **Step 10:** `just drv-diff <base> @` with an empty allow-list; expect exit 0 (tasks.md 1.7).
- [ ] **Step 11:** Commit: `refactor(checks): register host obligation judges beside their definitions`.

## Task 2: judge-check constructor and system gates (tasks.md 2.1–2.6)

**Files:**
- Create: `modules/lib/judge-check.nix`
- Modify: `modules/lib/mk-eval-check.nix:1-22` (one header line)
- Modify: `modules/checks/{darwin-resolver-reload,fleet-deployer-obligations,harmonia-gc-obligations,mesh-hosts-obligations,network-target-obligations,postgresql-backup-obligations,shared-vars-obligations,user-slice-guard-obligations}.nix` (to `mkJudgeCheck`), `modules/checks/{deploy-record-order,r2-usage}.nix` (to `judgeCases`)
- Modify: the 25 files of design Context (inner gate)

**Interfaces:**
- Produces: `flake.lib.judgeCases`, `flake.lib.mkJudgeCheck` (read by Task 5).

- [ ] **Step 1:** Red first: in a throwaway tree, change `harmonia-gc-obligations`'s `nixosNoTimeout` to `problems = 0` and evaluate its `.drvPath`. Record the current message, `the judge misjudges nixosNoTimeout`, which names no counts.
- [ ] **Step 2:** Create `modules/lib/judge-check.nix`:

  ```nix
  judgeCases =
    { name, judge, cases, assertions ? [ ] }:
    drv:
    let
      wrong = lib.filterAttrs (_: r: r.got != r.case.problems) (
        lib.mapAttrs (_: case: { inherit case; msgs = (case.judge or judge) case; got = lib.length ((case.judge or judge) case); }) cases
      );
      failing = lib.filter (a: !a.assertion) assertions;
      lines =
        lib.mapAttrsToList (n: r: "${name}: ${n}: expected ${toString r.case.problems} problems, the judge gave ${toString r.got}: ${builtins.toJSON r.msgs}") wrong
        ++ map (a: "${name}: ${a.message}") failing;
    in
    assert lib.assertMsg (lines == [ ]) (lib.concatStringsSep "\n" lines);
    drv;
  ```

  Add `mkJudgeCheck = pkgs: args: judgeCases args (pkgs.runCommand args.name { } "touch $out");`. Export both under `flake.lib`.
- [ ] **Step 3:** For each case set, `rg -n '\bjudge\b'` the file to confirm no case already carries a `judge` field (Review Focus). Then migrate the eight files. The judge adapts the case to the judge's arguments, as the file's `wrong` filter does today (for harmonia, `case: o.problems { inherit (case) platform service argv; }`, keeping the `{ argv = null; } //` default). Two-judge files tag each case with its own `judge`. `fleet-deployer-obligations` passes `derivedTargets` as `{ assertion = derivedTargets; message = "targetsFrom misderives the targets"; }`.
- [ ] **Step 4:** Wrap `deploy-record-order.nix:92`'s and `r2-usage.nix:206`'s derivations in `judgeCases { … }`. Move `r2-usage`'s cost-panel equality into `assertions` with its current message.
- [ ] **Step 5:** Add the header line to `mk-eval-check.nix`.
- [ ] **Step 6:** Rerun Step 1's mutant; expect `harmonia-gc-obligations: nixosNoTimeout: expected 0 problems, the judge gave 1: [...]`. Run one wrong-count mutant per migrated file (tasks.md 2.4) into `logs/rfo-2-mutants-<ts>.log`.
- [ ] **Step 7:** Delete the inner gate in the 25 files: `testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {` becomes `testSizes.checks = {`, with its closing brace unchanged. Evaluate both `test-size-classes` checks.
- [ ] **Step 8:** `just drv-diff <base> @` with an empty allow-list; expect exit 0.
- [ ] **Step 9:** Commit: `refactor(checks): one judge-check constructor; state each system gate once`.

## Task 3: tests on `fleetPkgs` (tasks.md 3.1–3.6)

**Files:**
- Modify: `modules/vm-tests/{devloop-ingest:77,fleet-deployer:38,fleet-ingress:79,greptimedb-oom-order:42,greptimedb-pipeline:67,omnigent-worker-isolation:97,omnigraph-local-root:79,omnigraph-seed:49,omnigraph-state-directory-transitions:71,perses-greptimedb:55,shared-reference-tree:35}.nix`
- Modify: `modules/checks/omnigent-workers.nix:8-15`, `modules/checks/devin-worker.nix:1-77`

- [ ] **Step 1:** For each of the eleven files, list every `pkgs.` and `nodePkgs.` use, and record which instance each uses, in `logs/rfo-3-instances-<ts>.log` (Review Focus).
- [ ] **Step 2:** Add `fleetPkgs` to each file's `perSystem` argument set. Replace the `nodePkgs = import inputs.nixpkgs { … };` binding with `nodePkgs = fleetPkgs;`, and drop `inputs` from the module arguments where it is now unused.
- [ ] **Step 3:** In `omnigent-workers.nix`, take `fleetPkgs` from `perSystem`'s arguments and bind `pkgs = fleetPkgs;` in place of `:11-15`. Leave `:16-21` byte-identical.
- [ ] **Step 4:** In `devin-worker.nix`, add `withSystem` to the module arguments, replace `probePkgs` with `fleetPkgsBySystem` from the interface in tasks.md 3.3, and change `pkgs = probePkgs system;` to `pkgs = fleetPkgsBySystem.${system};`.
- [ ] **Step 5:** `rg -n 'import inputs\.nixpkgs' modules/vm-tests modules/checks`; expect no output. Evaluate `vmTests.x86_64-linux` and `vmTests.aarch64-linux` attribute names and compare them with base.
- [ ] **Step 6:** `just drv-diff <base> @ <allow>`, where `<allow>` is the fifteen exact `vmTests` attribute paths of design D10, each `may-change`. For each `vmTests` difference, run `nix derivation show` on both drvs, diff them, and record the cause. An empty `vmTests` difference is recorded as A330's prediction holding.
- [ ] **Step 7:** `just eval-cost` on `checks.x86_64-linux.devin-worker.drvPath` and `vmTests.x86_64-linux.greptimedb-pipeline.drvPath` (tasks.md 3.5).
- [ ] **Step 8:** Only if a `vmTests` derivation differs: run that test on pyrite (`ssh pyrite.vanixiets.internal nix build --builders '' …`), announcing first if it is expected to take over 5 minutes (tasks.md 3.6).
- [ ] **Step 9:** Commit: `refactor(tests): evaluate runtime tests and fixture checks against fleetPkgs`.

## Task 4: remove `patched` (tasks.md 4.1–4.3)

**Files:**
- Modify: `modules/nixpkgs/overlays/channels.nix:10,40-45`
- Modify: `packages/docs/src/content/docs/development/architecture/adrs/0017-deferred-module-composition-overlay-patterns.md` (append the amendment)
- Modify: `packages/docs/src/content/docs/development/architecture/architecture.md:168,329`, `…/requirements/functional-hierarchy.md:172,206`, `…/requirements/usage-model.md:305`, `packages/docs/src/content/docs/guides/handling-broken-packages.md` (its `patched` steps)

- [ ] **Step 1:** Delete `patched` and the header line; `rg -n '\bpatched\b' modules/nixpkgs`; expect no output.
- [ ] **Step 2:** Append to ADR-0017 a `## Amendment (2026-11-26)` section stating what design D6 states, with an `overrideAttrs` plus `fetchpatch` example in an overlay. Leave the Decision text as it is.
- [ ] **Step 3:** Rewrite the guide's patched steps as that per-package recipe. Edit the three architecture and requirements lines so that they list only `stable`, `unstable` and `nixpkgs`, and describe per-package patching.
- [ ] **Step 4:** `rg -n 'pkgs\.patched|final\.patched|\.patched\.' packages/docs/src/content/docs`; expect only the amendment. Run `just docs-build`, logging to `logs/rfo-4-docs-build-<ts>.log`.
- [ ] **Step 5:** `just drv-diff <base> @` with an empty allow-list; expect exit 0.
- [ ] **Step 6:** Commit: `refactor(nixpkgs): drop the unused patched channel; amend ADR-0017`.

## Task 5: the two shapes (tasks.md 5.1–5.4)

**Files:**
- Modify: `modules/clan/services/otel-collector/flake-module.nix:165-174`, or the split file holding the option if `compose-hosts-from-cohesive-aspects` has split it
- Modify: `modules/lib/observability-hosts.nix` (add the validator after the table)
- Modify: `modules/checks/otel-collector-config.nix` (wrap its derivation)

**Interfaces:**
- Consumes: `flake.lib.judgeCases` (Task 2).

- [ ] **Step 1:** Red first: evaluate an `extendModules` of magnetite setting `vanixiets.otelCollector.envelopeBudget.storeURL = "x";`. On base it evaluates, because the type is `attrs`; record that.
- [ ] **Step 2:** Change the type to `nullOr (submodule { options = { storeUrl = mkOption { type = str; }; notifiedUnits = mkOption { type = attrsOf (listOf str); }; databases = mkOption { type = attrsOf str; }; }; })`, keeping the description apart from the inline shape. Rerun Step 1's mutant; expect a failure naming `storeURL`.
- [ ] **Step 3:** Add `observabilityHostProblems` with the D8 rules: known fields as a list, then per row `unknown`, `missing`, and type checks with `lib.isBool`, `lib.isList` plus `lib.all lib.isString`, and `lib.isInt` plus `> 0`. Export it beside `observabilityHosts`.
- [ ] **Step 4:** In `otel-collector-config.nix`, wrap the existing check derivation in `flakeLib.judgeCases { name = "otel-collector-config"; judge = flakeLib.observabilityHostProblems; cases = { committed = { table = hosts; problems = 0; }; … }; }`, using a `judge` that reads `case.table`. Add one mutant per rule, each `hosts // { x = hosts.cinnabar // { … }; }`, with 1 problem each; the unknown-field and missing-field mutants are separate, so each gives exactly one.
- [ ] **Step 5:** Evaluate `otel-collector-config.drvPath` and run one wrong-count mutant (tasks.md 5.3).
- [ ] **Step 6:** `just drv-diff <base> @` with an empty allow-list; expect exit 0.
- [ ] **Step 7:** Commit: `refactor(otel): type the envelope budget; validate the observability host table`.

## Task 6: corpus and coordination (tasks.md 6.1–6.3)

- [ ] **Step 1:** `rg -n "A host's backup set is pinned by a fleet obligation" openspec/specs/database-backup-interface/spec.md`. If it is absent, hold this change's archive until `back-up-postgresql-off-host` archives. Then run `openspec validate register-fleet-obligations --strict`.
- [ ] **Step 2:** Message the owner of `delegate-fleet-deploys` about its design's `:154` (tasks.md 6.2), and record the exchange in `verify.md`.
- [ ] **Step 3:** Record the operator's answer, or that none was given, to Open Question 1 in design.md.

## Task 7: integration verification (tasks.md 7.1–7.3)

- [ ] **Step 1:** `just drv-diff <base-before-task-1> <head> <vmTests allow-list>`; expect exit 0, with the same `vmTests` differences, if any, as in Task 3.
- [ ] **Step 2:** On magnetite's store, build the five `nixos-<host>` checks and the ten migrated fixture checks, and evaluate the four `darwin-<host>` checks. Compare the `checks.x86_64-linux` and `checks.aarch64-darwin` attribute names with base. Each machine check is small (median 14–25 s, test-size entries); log to `logs/rfo-7-gate-<ts>.log`.
- [ ] **Step 3:** In a throwaway tree, add `modules/lib/probe-obligation.nix` with `fleetObligations.probeObligations.failures = _: _: [ "probe" ];` and add the key to the literal list. Evaluate one NixOS and one darwin machine check; expect `probeObligations: probe`. `git diff --stat` shows two files.
